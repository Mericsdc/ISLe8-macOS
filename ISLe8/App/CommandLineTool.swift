import AppKit

/// The `isle8` command. It is the app's own binary started with arguments: it talks to the
/// running ISLe8 over the local socket and exits without ever opening a window.
///
///     isle8 hook claude|codex          agent hook; reads the hook's JSON on stdin
///     isle8 activity start|update|end  --id ID [--title T] [--subtitle S] [--progress 0.4] [--icon sf.symbol]
///     isle8 open [home|shelf|clipboard|notes|agents|devices|system]
///     isle8 close
///     isle8 devices
///     isle8 ping
///
/// Hooks always exit 0 and stay silent when ISLe8 isn't running, so an agent simply carries
/// on as if no hook were installed.
nonisolated enum CommandLineTool {
    private static let commands: Set<String> = ["hook", "activity", "open", "close", "devices", "ping", "help", "--help", "-h"]

    /// Runs the command and returns its exit code, or nil when the app should start normally.
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        guard arguments.count > 1, commands.contains(arguments[1]) else { return nil }
        let rest = Array(arguments.dropFirst(2))
        switch arguments[1] {
        case "hook": return hook(rest)
        case "activity": return activity(rest)
        case "open", "close": return island(arguments[1], tab: rest.first)
        case "devices": return devices()
        case "ping": return ping()
        default:
            print(usage)
            return 0
        }
    }

    /// The app's translations in the user's language. Run through the ~/.local/bin/isle8 link,
    /// Bundle.main is the link's folder and finds none, and another bundle would follow its
    /// language, so the language folder is picked here.
    private static let bundle: Bundle = {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath(),
              // ISLe8.app/Contents/MacOS/ISLe8
              let app = Bundle(url: executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()),
              let language = Bundle.preferredLocalizations(from: app.localizations, forPreferences: Locale.preferredLanguages).first,
              let folder = app.path(forResource: language, ofType: "lproj") else { return .main }
        return Bundle(path: folder) ?? .main
    }()

    private static let usage = String(localized: """
        isle8 — ISLe8'e komut satırından ulaşır.

          isle8 hook claude|codex         Claude Code / Codex hook'u (girdi stdin'den JSON)
          isle8 activity start --id ID --title "Başlık" [--subtitle "…"] [--progress 0.4] [--icon sf.symbol]
          isle8 activity update --id ID [--title …] [--subtitle …] [--progress …]
          isle8 activity end --id ID
          isle8 open [home|shelf|clipboard|notes|agents|devices|system]   Adayı açar
          isle8 close                     Adayı kapatır
          isle8 devices                   Bağlı kablosuz cihazlar ve pilleri
          isle8 ping                      ISLe8 çalışıyor mu?
        """, bundle: bundle)

    // MARK: Commands

    private static func hook(_ arguments: [String]) -> Int32 {
        let agent = arguments.first ?? "claude"
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let event = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { return 0 }
        let name = event["hook_event_name"] as? String
        let isApproval = name == "PermissionRequest"
        var request: [String: Any] = ["type": "hook", "agent": agent, "event": event]
        // Once per session or turn is enough to know which app to bring forward.
        if name == "SessionStart" || name == "UserPromptSubmit" {
            request["app_pid"] = hostAppPID().map { Int($0) }
        }
        // An approval waits for the user; Claude Code and Codex allow hooks 600 s by default.
        guard let response = send(request, timeout: isApproval ? 590 : 3) else { return 0 }

        if isApproval, let decision = response["decision"] as? String, decision == "allow" || decision == "deny" {
            var choice: [String: Any] = ["behavior": decision]
            if decision == "deny" {
                choice["message"] = response["message"] as? String ?? "Denied from ISLe8."
            }
            let output: [String: Any] = [
                "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": choice],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: output) {
                FileHandle.standardOutput.write(data)
            }
        }
        return 0
    }

    private static func activity(_ arguments: [String]) -> Int32 {
        guard let action = arguments.first, ["start", "update", "end"].contains(action) else {
            print(usage)
            return 2
        }
        var request: [String: Any] = ["type": "activity", "action": action]
        var index = 1
        while index + 1 < arguments.count {
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--id": request["id"] = value
            case "--title": request["title"] = value
            case "--subtitle": request["subtitle"] = value
            case "--icon": request["icon"] = value
            case "--progress": request["progress"] = Double(value)
            default: break
            }
            index += 2
        }
        guard request["id"] != nil else {
            FileHandle.standardError.write(Data("isle8: \(String(localized: "--id gerekli", bundle: bundle))\n".utf8))
            return 2
        }
        guard send(request, timeout: 3) != nil else {
            FileHandle.standardError.write(Data("isle8: \(String(localized: "ISLe8 çalışmıyor", bundle: bundle))\n".utf8))
            return 1
        }
        return 0
    }

    /// The nearest ancestor process that is an app with a window, e.g. Terminal or Claude.
    private static func hostAppPID() -> pid_t? {
        var pid = getppid()
        for _ in 0..<24 where pid > 1 {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                return pid
            }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
            pid = info.kp_eproc.e_ppid
        }
        return nil
    }

    private static func island(_ action: String, tab: String?) -> Int32 {
        var request: [String: Any] = ["type": "island", "action": action]
        request["tab"] = tab
        guard send(request, timeout: 3) != nil else {
            FileHandle.standardError.write(Data("isle8: \(String(localized: "ISLe8 çalışmıyor", bundle: bundle))\n".utf8))
            return 1
        }
        return 0
    }

    private static func devices() -> Int32 {
        guard let response = send(["type": "devices"], timeout: 3) else {
            FileHandle.standardError.write(Data("isle8: \(String(localized: "ISLe8 çalışmıyor", bundle: bundle))\n".utf8))
            return 1
        }
        let lines = response["devices"] as? [String] ?? []
        print(lines.isEmpty ? String(localized: "Pil bildiren bağlı kablosuz cihaz yok", bundle: bundle) : lines.joined(separator: "\n"))
        return 0
    }

    private static func ping() -> Int32 {
        guard send(["type": "ping"], timeout: 2) != nil else {
            print(String(localized: "ISLe8 çalışmıyor", bundle: bundle))
            return 1
        }
        print(String(localized: "ISLe8 çalışıyor", bundle: bundle))
        return 0
    }

    // MARK: Socket client

    /// Sends one JSON line and waits for one back. Nil if ISLe8 isn't there or doesn't answer.
    private static func send(_ request: [String: Any], timeout: TimeInterval) -> [String: Any]? {
        guard var payload = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        payload.append(0x0A)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0, var address = LocalServer.address(for: ISLe8Paths.socket.path) else { return nil }
        defer { close(descriptor) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let sent = payload.withUnsafeBytes { buffer in
            write(descriptor, buffer.baseAddress, buffer.count)
        }
        guard sent == payload.count else { return nil }

        var response = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !response.contains(0x0A) {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, Int32(min(remaining, 60) * 1000)) > 0 else { continue }
            let count = read(descriptor, &chunk, chunk.count)
            guard count > 0 else { break }
            response.append(contentsOf: chunk[0..<count])
        }
        guard let line = response.split(separator: 0x0A).first else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
    }
}
