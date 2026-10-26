import Darwin
import Foundation

// Ported from LimitBar LRX's Spawn.swift (see UsageModule.swift for the credit).

/// Lets the main thread stop a CLI without waiting for its timeout. The worker owns all file
/// descriptors and process cleanup; other threads only set this flag.
nonisolated final class UsageCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var children: Set<pid_t> = []

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        for pid in children { kill(-pid, SIGKILL) }
    }

    func track(_ pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        children.insert(pid)
        if cancelled { kill(-pid, SIGKILL) }
    }

    func untrack(_ pid: pid_t) {
        lock.lock()
        children.remove(pid)
        lock.unlock()
    }
}

/// A vendor CLI process. Each runs in its own session (POSIX_SPAWN_SETSID), so a timeout kills
/// the whole process group, node, helpers and all, not just the first pid. Used by one thread.
nonisolated final class UsageChild {
    let pid: pid_t
    private let inFD: Int32
    private let outFD: Int32
    private var buffer = Data()
    private var inputClosed = false
    private var reaped = false
    private let cancellation: UsageCancellation?

    private static let setsid: Int16 = 0x0400          // POSIX_SPAWN_SETSID
    private static let cloexecDefault: Int16 = 0x4000  // POSIX_SPAWN_CLOEXEC_DEFAULT
    /// A CLI that prints more than this is not answering a quota question; stop reading.
    static let maxOutput = 4 << 20

    init?(_ argv: [String], env: [String: String], cwd: String = UsageCLI.workDir) {
        cancellation = UsageCLI.currentCancellation
        guard cancellation?.isCancelled != true else { return nil }
        var inPipe: [Int32] = [0, 0]
        var outPipe: [Int32] = [0, 0]
        guard pipe(&inPipe) == 0 else { return nil }
        guard pipe(&outPipe) == 0 else {
            close(inPipe[0])
            close(inPipe[1])
            return nil
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, inPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addchdir_np(&actions, cwd)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Self.setsid | Self.cloexecDefault)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        var spawned: pid_t = 0
        let envList = env.map { "\($0.key)=\($0.value)" }
        let rc = usageWithCStrings(argv) { cargv in
            usageWithCStrings(envList) { cenv in posix_spawn(&spawned, argv[0], &actions, &attributes, cargv, cenv) }
        }
        close(inPipe[0])
        close(outPipe[1])
        guard rc == 0 else {
            close(inPipe[1])
            close(outPipe[0])
            return nil
        }
        pid = spawned
        inFD = inPipe[1]
        outFD = outPipe[0]
        cancellation?.track(spawned)
        _ = fcntl(outFD, F_SETFL, fcntl(outFD, F_GETFL) | O_NONBLOCK)
        _ = fcntl(inFD, F_SETNOSIGPIPE, 1)
    }

    func write(_ string: String) {
        guard !inputClosed else { return }
        let bytes = Array(string.utf8)
        bytes.withUnsafeBytes { _ = Darwin.write(inFD, $0.baseAddress, bytes.count) }
    }

    func closeInput() {
        guard !inputClosed else { return }
        inputClosed = true
        close(inFD)
    }

    /// Next newline-terminated line, or nil at EOF / deadline.
    func readLine(until deadline: Date) -> String? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return String(decoding: line, as: UTF8.self)
            }
            guard fill(until: deadline) else {
                if buffer.isEmpty { return nil }
                defer { buffer.removeAll() }
                return String(decoding: buffer, as: UTF8.self)
            }
        }
    }

    /// Everything until EOF (or deadline). `timedOut` tells which.
    func readAll(until deadline: Date) -> (Data, timedOut: Bool) {
        while fill(until: deadline) {}
        return (buffer, Date() >= deadline)
    }

    private func fill(until deadline: Date) -> Bool {
        guard buffer.count < Self.maxOutput else { return false }
        while cancellation?.isCancelled != true {
            let ms = Int32(min(200, max(0, deadline.timeIntervalSinceNow) * 1000))
            if ms == 0 { return false }
            var descriptor = pollfd(fd: outFD, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, ms)
            if ready == 0 { continue }
            if ready < 0 {
                if errno == EINTR { continue }
                return false
            }
            var chunk = [UInt8](repeating: 0, count: min(65536, Self.maxOutput - buffer.count))
            let count = read(outFD, &chunk, chunk.count)
            if count <= 0 { return false }
            buffer.append(contentsOf: chunk[0..<count])
            return true
        }
        return false
    }

    /// TERM the whole group, then KILL, then reap: no orphans, no zombies.
    func terminate() {
        guard !reaped else { return }
        kill(-pid, SIGTERM)
        var status: Int32 = 0
        for _ in 0..<20 {
            if waitpid(pid, &status, WNOHANG) == pid {
                kill(-pid, SIGKILL)
                cleanup()
                return
            }
            usleep(50_000)
        }
        kill(-pid, SIGKILL)
        waitpid(pid, &status, 0)
        cleanup()
    }

    /// Waits for a normal exit after output ended and kills it if it lingers. The exit code, or
    /// -1 if it was killed.
    func finish(within seconds: TimeInterval = 2) -> Int32 {
        var status: Int32 = 0
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if cancellation?.isCancelled == true {
                terminate()
                return -1
            }
            if waitpid(pid, &status, WNOHANG) == pid {
                kill(-pid, SIGKILL)  // helpers the CLI left behind in its group
                cleanup()
                return (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1
            }
            usleep(50_000)
        }
        terminate()
        return -1
    }

    private func cleanup() {
        guard !reaped else { return }
        reaped = true
        cancellation?.untrack(pid)
        close(outFD)
        closeInput()
    }
}

nonisolated private func usageWithCStrings<R>(
    _ strings: [String],
    _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R
) -> R {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    pointers.append(nil)
    defer { pointers.forEach { free($0) } }
    return pointers.withUnsafeBufferPointer { body($0.baseAddress!) }
}

/// Finding, checking and starting the vendor CLIs.
nonisolated enum UsageCLI {
    private static let cancellationKey = "com.lrxe8.isle8.usage.cancellation"

    /// The token of the job running on this thread; every child it starts dies with it.
    static var currentCancellation: UsageCancellation? {
        Thread.current.threadDictionary[cancellationKey] as? UsageCancellation
    }

    static func withCancellation<T>(_ token: UsageCancellation, _ body: () -> T) -> T {
        let previous = Thread.current.threadDictionary[cancellationKey]
        Thread.current.threadDictionary[cancellationKey] = token
        defer {
            if let previous {
                Thread.current.threadDictionary[cancellationKey] = previous
            } else {
                Thread.current.threadDictionary.removeObject(forKey: cancellationKey)
            }
        }
        return body()
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Where the vendor CLIs install themselves. Fixed: PATH is never taken from the environment,
    /// so a directory some other tool added is never searched.
    static let searchPath = [
        "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin",
        "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/.claude/local", "\(home)/.claude/bin",
        "\(home)/Library/pnpm",
    ]
    static let systemPath = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    /// A private, empty working directory: no CLI ever runs inside a project and picks up its config.
    static let workDir: String = {
        let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent("lrxe8-isle8-usage-cwd")
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        return directory
    }()

    enum Found {
        case ok(String)
        case missing
        case untrusted(String)
    }

    /// The executable for `name`: an explicit path from `defaults write com.lrxe8.isle8
    /// usage.<name>Path /abs/path` first, then the fixed search path. Only files that pass
    /// `trusted` are ever run.
    static func find(_ name: String) -> Found {
        if let path = UserDefaults.standard.string(forKey: "usage.\(name)Path"), path.hasPrefix("/") {
            guard FileManager.default.fileExists(atPath: path) else { return .missing }
            return trusted(path) ? .ok(path) : .untrusted(path)
        }
        for directory in searchPath {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return trusted(path) ? .ok(path) : .untrusted(path)
            }
        }
        return .missing
    }

    /// Whether another local account could replace what is about to run. The path, its resolved
    /// target and every directory above both, up to `/`, must be owned by this user or root, not
    /// writable by others, writable by group only for `admin` (who can sudo anyway), and carry no
    /// ACL entry that grants anyone write access. A file that fails is never run.
    static func trusted(_ path: String) -> Bool {
        guard let resolved = realpath(path, nil) else { return false }
        let target = String(cString: resolved)
        free(resolved)
        guard FileManager.default.isExecutableFile(atPath: target), safeNode(path, isLink: true) else { return false }
        return safeChain(target) && safeChain((path as NSString).deletingLastPathComponent)
    }

    /// `path` and all its ancestors pass `safeNode`.
    static func safeChain(_ path: String) -> Bool {
        var current = path
        while true {
            guard safeNode(current, isLink: false) else { return false }
            if current == "/" || current.isEmpty { return true }
            current = (current as NSString).deletingLastPathComponent
        }
    }

    private static let adminGroup: gid_t = 80

    static func safeNode(_ path: String, isLink: Bool) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        guard info.st_uid == getuid() || info.st_uid == 0 else { return false }
        if isLink && (info.st_mode & S_IFMT) == S_IFLNK { return true }  // a symlink's own mode means nothing
        if (info.st_mode & S_IWOTH) != 0 { return false }
        if (info.st_mode & S_IWGRP) != 0 && info.st_gid != adminGroup && info.st_gid != 0 { return false }
        return !aclGrantsWrite(path)
    }

    /// Any ALLOW entry in the extended ACL that lets someone write, delete or change
    /// ownership or permissions.
    static func aclGrantsWrite(_ path: String) -> Bool {
        guard let acl = acl_get_link_np(path, ACL_TYPE_EXTENDED) else { return false }  // no ACL
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        let writes: [acl_perm_t] = [
            ACL_WRITE_DATA, ACL_APPEND_DATA, ACL_DELETE, ACL_DELETE_CHILD,
            ACL_WRITE_ATTRIBUTES, ACL_WRITE_EXTATTRIBUTES, ACL_WRITE_SECURITY, ACL_CHANGE_OWNER,
        ]
        var entry: acl_entry_t?
        var which = ACL_FIRST_ENTRY.rawValue
        while acl_get_entry(acl, which, &entry) == 0, let current = entry {
            which = ACL_NEXT_ENTRY.rawValue
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(current, &tag) == 0, tag == ACL_EXTENDED_ALLOW else { continue }
            var permissions: acl_permset_t?
            guard acl_get_permset(current, &permissions) == 0, let set = permissions else { return true }
            if writes.contains(where: { acl_get_perm_np(set, $0) == 1 }) { return true }
        }
        return false
    }

    /// The environment a CLI gets is an allowlist, not ours minus a denylist: API keys, GitHub
    /// tokens, SSH agent sockets and anything else ISLe8 was started with stay out. The CLI's own
    /// directories go first on PATH so a Node-based CLI finds the `node` it was installed with.
    static func env(for binary: String) -> [String: String] {
        let mine = ProcessInfo.processInfo.environment
        var result: [String: String] = [:]
        for key in ["USER", "LOGNAME", "TMPDIR"] {
            if let value = mine[key] { result[key] = value }
        }
        let real = ((binary as NSString).resolvingSymlinksInPath as NSString).deletingLastPathComponent
        let link = (binary as NSString).deletingLastPathComponent
        // Only directories nobody else can write to: a Node-based CLI's `#!/usr/bin/env node`
        // resolves through this PATH, so an unchecked directory would undo the check on the CLI.
        var path: [String] = []
        for directory in [link, real] + searchPath + systemPath where !path.contains(directory) && safeChain(directory) {
            path.append(directory)
        }
        result["PATH"] = path.joined(separator: ":")
        result["HOME"] = home
        result["LANG"] = "en_US.UTF-8"
        result["NO_COLOR"] = "1"
        return result
    }

    /// How to start `binary`: itself if it is a native executable; for a script
    /// (`#!/usr/bin/env node`, `#!/bin/sh`) its interpreter first, resolved here, checked with
    /// `trusted` and passed explicitly, so nothing is looked up through PATH. nil = the
    /// interpreter is missing or untrusted: do not run.
    static func launch(_ binary: String) -> [String]? {
        guard let handle = FileHandle(forReadingAtPath: binary) else { return nil }
        let head = handle.readData(ofLength: 512)
        try? handle.close()
        guard head.starts(with: Array("#!".utf8)) else { return [binary] }
        guard let line = String(decoding: head, as: UTF8.self).split(separator: "\n").first else { return nil }
        var parts = line.dropFirst(2).split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return nil }
        if parts[0] == "/usr/bin/env" {
            parts.removeFirst()
            while let flag = parts.first, flag.hasPrefix("-") { parts.removeFirst() }  // `env -S` and the like
            guard let name = parts.first, case .ok(let found) = find(name), let resolved = realpath(found, nil) else {
                return nil
            }
            parts[0] = String(cString: resolved)
            free(resolved)
        }
        guard parts[0].hasPrefix("/"), trusted(parts[0]) else { return nil }
        return parts + [binary]
    }

    struct Output {
        let data: Data
        let code: Int32
    }

    /// Runs `binary` with `args` to completion under a hard deadline. nil if it could not start
    /// or timed out.
    static func run(
        _ binary: String,
        _ args: [String],
        timeout: TimeInterval = 20,
        extraEnv: [String: String] = [:],
        envFor: String? = nil
    ) -> Output? {
        let start = binary == "/usr/bin/sandbox-exec" ? [binary] : launch(binary)
        guard let argv0 = start,
              let child = UsageChild(argv0 + args, env: env(for: envFor ?? binary).merging(extraEnv) { $1 })
        else { return nil }
        child.closeInput()
        let (data, timedOut) = child.readAll(until: Date().addingTimeInterval(timeout))
        if timedOut || currentCancellation?.isCancelled == true {
            child.terminate()
            return nil
        }
        return Output(data: data, code: child.finish())
    }

    enum RPCResult {
        case ok([String: Any])
        case failed(String)
    }

    /// One JSON-RPC exchange over stdio: initialize, an optional notification, one call; then
    /// kill. `argv` may wrap `binary` (in sandbox-exec); the environment is built for `binary`.
    /// The failure text is only matched against, never shown or stored.
    static func rpc(
        _ argv: [String],
        binary: String,
        initialize: [String: Any],
        notify: String? = nil,
        method: String,
        params: [String: Any] = [:],
        timeout: TimeInterval = 20,
        extraEnv: [String: String] = [:]
    ) -> RPCResult {
        guard let child = UsageChild(argv, env: env(for: binary).merging(extraEnv) { $1 }) else {
            return .failed("could not start")
        }
        defer { child.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            child.write(String(decoding: data, as: UTF8.self) + "\n")
        }
        func reply(_ id: Int) -> [String: Any]? {
            while let line = child.readLine(until: deadline) {
                guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
                    continue
                }
                if (object["id"] as? Int) == id { return object }
            }
            return nil
        }
        func failure(_ object: [String: Any]?) -> String {
            guard let object else { return Date() >= deadline ? "timed out" : "no answer" }
            return ((object["error"] as? [String: Any])?["message"] as? String) ?? "unexpected answer"
        }
        send(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": initialize])
        let initialized = reply(1)
        guard initialized?["result"] != nil else { return .failed(failure(initialized)) }
        if let notify { send(["jsonrpc": "2.0", "method": notify, "params": [String: Any]()]) }
        send(["jsonrpc": "2.0", "id": 2, "method": method, "params": params])
        let answer = reply(2)
        guard let result = answer?["result"] as? [String: Any] else { return .failed(failure(answer)) }
        return .ok(result)
    }
}
