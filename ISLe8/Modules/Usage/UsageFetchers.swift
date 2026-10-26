import Foundation

// Ported from LimitBar LRX's Fetchers.swift (see UsageModule.swift for the credit).

/// Where each vendor's limits come from. Error texts are fixed strings of ours: a CLI's own
/// error message is only matched against, never stored or shown, so nothing it says can end up
/// in the cache. Every source is the vendor's own CLI (or Codex's own session log), so sign-in
/// and token refresh stay inside the CLI: no credential file, cookie or keychain item is ever
/// opened, and nothing of an account is kept but the plan name.
nonisolated enum UsageFetch {
    static let home = UsageCLI.home

    // The formatter is not documented as thread-safe; `dateLock` serialises it.
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let dateLock = NSLock()

    static func date(_ any: Any?) -> Date? {
        if let number = UsageNumber.finite(any) {
            let seconds = number > 1e12 ? number / 1000 : number
            guard seconds >= 0, seconds < 32_503_680_000 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        if let string = any as? String {
            dateLock.lock()
            defer { dateLock.unlock() }
            return iso.date(from: string) ?? ISO8601DateFormatter().date(from: string)
                ?? ISO8601DateFormatter().date(
                    from: string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
                )
        }
        return nil
    }

    static func json(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    static func mtime(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// The CLI for a vendor, or the snapshot that explains why there is none.
    static func binary(_ vendor: UsageVendor) -> (String?, UsageSnapshot?) {
        switch UsageCLI.find(vendor.cli) {
        case .ok(let path):
            guard UsageCLI.launch(path) != nil else {
                return (nil, .status(vendor, .untrusted,
                                     String(localized: "\(vendor.cli) yorumlayıcısının izinleri güvenilir değil; çalıştırılmadı.")))
            }
            return (path, nil)
        case .missing:
            return (nil, .status(vendor, .missing))
        case .untrusted:
            return (nil, .status(vendor, .untrusted, String(localized: "\(vendor.cli) izinleri güvenilir değil; çalıştırılmadı.")))
        }
    }

    static func signedOutText(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return [
            "not logged in", "not signed in", "please log in", "please sign in", "login required",
            "unauthenticated", "unauthorized", "no credentials", "not authenticated", "authentication required",
        ].contains { lowered.contains($0) }
    }

    // MARK: Claude: `claude -p /usage`

    /// For every `claude` call. Not CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: since Claude Code
    /// 2.1 it also skips the usage request, and `/usage` then prints no "Current session" lines.
    static let claudeEnvironment = ["DISABLE_UPDATES": "1", "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1"]

    /// User and project settings files ignored (so none of their hooks run), hooks off, no MCP
    /// server, no transcript saved; plus the private empty cwd and allowlisted environment every
    /// CLI gets. Limitbar's tests/claude-canary.sh proves hooks and MCP servers fire without
    /// these flags and stay silent with them.
    static let claudeIsolation = [
        "--restricted", "--strict-mcp-config", "--no-session-persistence",
        "--settings", #"{"disableAllHooks":true,"language":"English"}"#,
    ]

    /// `/usage` makes no model call, but it is a full CLI start (a second or more of CPU), so it
    /// runs at most every 20 min on its own.
    static func claudeUsage() -> UsageSnapshot {
        let (found, why) = binary(.claude)
        guard let claude = found else { return why! }
        guard let out = UsageCLI.run(
            claude, ["-p", "/usage", "--output-format", "json", "--max-turns", "1"] + claudeIsolation,
            timeout: 40, extraEnv: claudeEnvironment
        ) else {
            return .status(.claude, .failed, String(localized: "Claude sorgusu zaman aşımına uğradı."))
        }
        guard let object = json(out.data), let text = object["result"] as? String else {
            let raw = String(decoding: out.data.prefix(2000), as: UTF8.self)
            if signedOutText(raw) { return .status(.claude, .signedOut) }
            return .status(.claude, .failed, String(localized: "Claude kullanım verisi döndürmedi (kod \(Int(out.code)))."))
        }
        if signedOutText(text) { return .status(.claude, .signedOut) }
        func line(_ title: String, _ kind: UsageWindow.Kind, weekly: Bool) -> UsageWindow? {
            let pattern = NSRegularExpression.escapedPattern(for: title)
                + #":\s*(\d+(?:\.\d+)?)%\s*used(?:\s*·\s*resets\s+([^(\n]+?)\s*\(([^)]+)\))?"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let usedRange = Range(match.range(at: 1), in: text),
                  let used = UsageNumber.percent(Double(text[usedRange]))
            else { return nil }
            var reset: Date?
            if let when = Range(match.range(at: 2), in: text), let zone = Range(match.range(at: 3), in: text) {
                reset = parseClaudeReset(String(text[when]), timeZone: String(text[zone]))
            }
            return UsageWindow(kind: kind, isWeekly: weekly, used: used, resetsAt: reset)
        }
        let five = line("Current session", .fiveHour, weekly: false)
        let week = line("Current week (all models)", .week, weekly: true)
        // Per-model weekly lines ("Current week (Opus)", …) appear on some plans; show each one.
        var extra: [UsageWindow] = []
        if let regex = try? NSRegularExpression(pattern: #"Current week \(([^)]+)\)"#) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let model = String(text[range])
                if model != "all models", let window = line("Current week (\(model))", .modelWeek(model), weekly: true) {
                    extra.append(window)
                }
            }
        }
        guard five != nil || week != nil else {
            return .status(.claude, .failed,
                           String(localized: "Claude CLI kota satırı döndürmedi (CLI sürümü değişmiş olabilir). Limitler okunamadı."))
        }
        return UsageSnapshot(vendor: .claude, bar: five ?? week, windows: [five, week].compactMap { $0 } + extra,
                             measuredAt: Date(), source: .live)
    }

    /// "Oct 21 at 9:10pm" / "Oct 24 at 11pm" in the given zone; the year is the next occurrence.
    static func parseClaudeReset(_ string: String, timeZone: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZone) ?? .current
        let year = Calendar.current.component(.year, from: Date())
        let clean = string.replacingOccurrences(of: " at ", with: " ").uppercased()
        for format in ["MMM d h:mma yyyy", "MMM d ha yyyy", "MMM d H:mm yyyy"] {
            formatter.dateFormat = format
            for candidate in [year, year + 1] {
                if let date = formatter.date(from: "\(clean) \(candidate)"), date > Date().addingTimeInterval(-86400) {
                    return date
                }
            }
        }
        return nil
    }

    /// `claude auth status --json`: whether someone is signed in, and the plan ("Max", "Pro").
    /// Its answer also carries the email and organisation; those are never kept or shown.
    static func claudeAccount() -> (signedIn: Bool, plan: String)? {
        guard case .ok(let claude) = UsageCLI.find("claude"),
              let out = UsageCLI.run(claude, ["auth", "status", "--json"], timeout: 20, extraEnv: claudeEnvironment),
              let object = json(out.data)
        else { return nil }
        let plan = (object["subscriptionType"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""
        return ((object["loggedIn"] as? Bool) == true, plan)
    }

    // MARK: Gemini: Antigravity CLI `agy -p /quota`, Google's own per-group buckets, zero tokens

    /// `bar` is the most-used bucket across the Gemini model groups (the one that stops you
    /// first); `windows` lists every group. Non-Gemini groups (Claude/GPT inside Antigravity)
    /// only once they have been used.
    static func gemini() -> UsageSnapshot {
        let (found, why) = binary(.gemini)
        guard let agy = found else { return why! }
        guard let box = UsageSandbox.wrap(.gemini, agy, ["-p", "/quota", "--output-format", "json", "--print-timeout", "30s"]) else {
            return .status(.gemini, .failed, String(localized: "Koruma ortamı kullanılamıyor; agy çalıştırılmadı."))
        }
        guard let out = UsageCLI.run(box.argv[0], Array(box.argv.dropFirst()), timeout: 40, extraEnv: box.env, envFor: box.binary) else {
            return .status(.gemini, .failed, String(localized: "Antigravity sorgusu zaman aşımına uğradı."))
        }
        guard let object = json(out.data),
              let data = (object["command"] as? [String: Any])?["data"] as? [String: Any],
              let groups = data["groups"] as? [[String: Any]]
        else {
            let raw = String(decoding: out.data.prefix(2000), as: UTF8.self)
            if signedOutText(raw) { return .status(.gemini, .signedOut) }
            return .status(.gemini, .failed, String(localized: "Antigravity kota verisi döndürmedi (kod \(Int(out.code)))."))
        }
        var gemini: [UsageWindow] = []
        var other: [UsageWindow] = []
        for group in groups {
            let name = group["name"] as? String ?? "Models"
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard let fraction = UsageNumber.finite(bucket["remaining_fraction"]), fraction >= 0, fraction <= 1 else { continue }
                let five = (bucket["window"] as? String) == "5h"
                let window = UsageWindow(kind: .group(name), isWeekly: !five, used: (1 - fraction) * 100,
                                         resetsAt: date(bucket["reset_time"]))
                if name.localizedCaseInsensitiveContains("Gemini") {
                    gemini.append(window)
                } else if fraction < 1 {
                    other.append(window)
                }
            }
        }
        guard !gemini.isEmpty else {
            return .status(.gemini, .failed, String(localized: "Antigravity yanıtında Gemini kotası bulunamadı."))
        }
        gemini.sort { ($0.used ?? 0) > ($1.used ?? 0) }
        return UsageSnapshot(vendor: .gemini, bar: gemini.first, windows: gemini + other, measuredAt: Date(), source: .live)
    }

    // MARK: Codex: app-server `account/rateLimits/read`

    static func codexFromServer() -> UsageSnapshot {
        let (found, why) = binary(.codex)
        guard let codex = found else { return why! }
        guard let box = UsageSandbox.wrap(.codex, codex, ["app-server"]) else {
            return .status(.codex, .failed, String(localized: "Koruma ortamı kullanılamıyor; Codex çalıştırılmadı."))
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        switch UsageCLI.rpc(box.argv, binary: box.binary, initialize: ["clientInfo": ["name": "lrxe8_isle8", "version": version]],
                            notify: "initialized", method: "account/rateLimits/read", extraEnv: box.env) {
        case .failed(let error):
            if let login = UsageSandbox.wrap(.codex, codex, ["login", "status"]),
               let out = UsageCLI.run(login.argv[0], Array(login.argv.dropFirst()), timeout: 15, extraEnv: login.env, envFor: login.binary),
               signedOutText(String(decoding: out.data, as: UTF8.self)) {
                return .status(.codex, .signedOut)
            }
            if signedOutText(error) { return .status(.codex, .signedOut) }
            return .status(.codex, .failed, String(localized: "Codex kota verisi alınamadı."))
        case .ok(let result):
            let buckets = result["rateLimitsByLimitId"] as? [String: Any]
            guard let limits = (buckets?["codex"] ?? result["rateLimits"]) as? [String: Any],
                  var snapshot = codexSnapshot(limits, used: "usedPercent", reset: "resetsAt", measured: Date())
            else {
                return .status(.codex, .failed, String(localized: "Codex geçerli kota verisi döndürmedi."))
            }
            snapshot.source = .live
            let credits = ((result["rateLimitResetCredits"] as? [String: Any])?["credits"] as? [[String: Any]] ?? [])
                .filter { ($0["status"] as? String) == "available" }
                .compactMap { date($0["expiresAt"]) }
                .sorted()
            if let next = credits.first {
                let day = relativeDay(next)
                snapshot.notes.append(String(localized: "\(credits.count) ücretsiz kota sıfırlama · son kullanım \(day)"))
            }
            return snapshot
        }
    }

    /// Both the session-log shape (`used_percent`, `window_minutes`) and the app-server shape
    /// (`usedPercent`, `windowDurationMins`). A missing number stays missing, never 0 %.
    static func codexSnapshot(_ limits: [String: Any], used: String, reset: String, measured: Date?) -> UsageSnapshot? {
        if let id = (limits["limit_id"] ?? limits["limitId"]) as? String, id != "codex" { return nil }
        func window(_ key: String) -> UsageWindow? {
            guard let entry = limits[key] as? [String: Any], let percent = UsageNumber.percent(entry[used]) else { return nil }
            let duration = UsageNumber.finite(entry["window_minutes"] ?? entry["windowDurationMins"]) ?? 0
            let minutes = duration >= 0 && duration <= 525_600 && duration.rounded() == duration ? Int(duration) : 0
            let kind: UsageWindow.Kind = minutes == 300 ? .fiveHour : minutes == 10080 ? .week : minutes > 0 ? .minutes(minutes) : .quota
            return UsageWindow(kind: kind, isWeekly: minutes >= 10080, used: percent, resetsAt: date(entry[reset]))
        }
        let five = window("primary")
        let week = window("secondary")
        guard five != nil || week != nil else { return nil }
        let plan = ((limits["plan_type"] ?? limits["planType"]) as? String)
            .map { "ChatGPT " + $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""
        return UsageSnapshot(vendor: .codex, plan: plan, bar: five ?? week, windows: [five, week].compactMap { $0 },
                             measuredAt: measured)
    }

    static func relativeDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let calendar = Calendar.current
        let time = formatter.string(from: date)
        if calendar.isDateInToday(date) { return String(localized: "bugün \(time)") }
        if calendar.isDateInTomorrow(date) { return String(localized: "yarın \(time)") }
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date)
    }
}

/// Codex writes `rate_limits` into its own session logs for free whenever it talks to the
/// server, so most Codex updates need no CLI at all. Only the last 256 KiB of each of the
/// eight newest logs is read, and only the quota lines in it are parsed; conversation content
/// is never kept.
nonisolated final class UsageCodexLogs: @unchecked Sendable {
    private struct Memo {
        var modified: Date
        var size: UInt64
        var snapshot: UsageSnapshot?
    }

    let root: String
    // Read from both the fetch and the local queue.
    private let lock = NSLock()
    private var memo: [String: Memo] = [:]

    init(root: String = "\(UsageCLI.home)/.codex/sessions") {
        self.root = root
    }

    /// The newest genuine measurement across recent sessions, or nil.
    func latest(now: Date = Date()) -> UsageSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        let paths = UsageSessionFiles.recent(root: root, now: now)
        let active = Set(paths)
        memo = memo.filter { active.contains($0.key) }
        var best: UsageSnapshot?
        for path in paths {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let modified = attributes[.modificationDate] as? Date,
                  let size = (attributes[.size] as? NSNumber)?.uint64Value
            else { continue }
            let previous = memo[path]
            var candidate: UsageSnapshot?
            if previous?.modified == modified && previous?.size == size {
                candidate = previous?.snapshot
            } else {
                // Only changed files are read again. A log append without a quota event keeps
                // that file's last genuine measurement.
                if let previous, size >= previous.size { candidate = previous.snapshot }
                if let handle = FileHandle(forReadingAtPath: path) {
                    defer { try? handle.close() }
                    try? handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
                    let tail = String(decoding: handle.readData(ofLength: 262_144), as: UTF8.self)
                    for line in tail.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
                        guard let object = UsageFetch.json(Data(line.utf8)), object["type"] as? String == "event_msg",
                              let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                              let limits = payload["rate_limits"] as? [String: Any],
                              let time = UsageFetch.date(object["timestamp"]), time <= now.addingTimeInterval(60),
                              var value = UsageFetch.codexSnapshot(limits, used: "used_percent", reset: "resets_at", measured: time)
                        else { continue }
                        value.source = .localSession
                        candidate = value
                        break
                    }
                }
                memo[path] = Memo(modified: modified, size: size, snapshot: candidate)
            }
            if let candidate, let time = candidate.measuredAt, time <= now.addingTimeInterval(60),
               time > (best?.measuredAt ?? .distantPast) {
                best = candidate
            }
        }
        return best
    }
}

/// Everything this feature writes lives in ~/Library/Caches/com.lrxe8.isle8/usage: quota
/// numbers, times, plan names and our own fixed texts. Never CLI output.
nonisolated enum UsageCache {
    /// 0700.
    static let folder: String = {
        let directory = "\(UsageCLI.home)/Library/Caches/com.lrxe8.isle8/usage"
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        chmod(directory, 0o700)
        return directory
    }()

    static var stateFile: String { "\(folder)/state.json" }

    /// Atomic, and readable only by this user (0600).
    static func write(_ data: Data, to path: String) {
        let temporary = path + ".\(getpid())"
        guard FileManager.default.createFile(atPath: temporary, contents: data, attributes: [.posixPermissions: 0o600]) else {
            return
        }
        if rename(temporary, path) != 0 { unlink(temporary) }
    }
}

/// The kernel sandbox (Resources/usage-cli.sb, applied with sandbox-exec) every CLI except
/// `claude` runs in. The CLI may start only programs from its own install folder, may read and
/// write nothing in the home folder but its own state folder, and nothing in other users'
/// folders, mounted volumes or shared temp. So no MCP server, hook or plugin configured anywhere
/// can start, and nothing else of the user's is readable. `claude` runs with its own isolation
/// flags instead (`UsageFetch.claudeIsolation`).
nonisolated enum UsageSandbox {
    struct Box {
        let argv: [String]
        let binary: String
        let env: [String: String]
    }

    static func real(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// nil when the profile or sandbox-exec is missing; the CLI is then not run at all.
    static func wrap(_ vendor: UsageVendor, _ link: String, _ args: [String]) -> Box? {
        guard let profile = Bundle.main.url(forResource: "usage-cli", withExtension: "sb")?.path,
              FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec"),
              let binary = real(link), let temporary = real(UsageCLI.workDir), let home = real(UsageCLI.home)
        else { return nil }
        let directory = (binary as NSString).deletingLastPathComponent
        let state: String
        let execDir: String
        switch vendor {
        case .codex:
            // Homebrew: <Caskroom>/codex/<version>/bin/codex → the version folder. npm:
            // <node_modules>/@openai/codex/bin/codex.js starts a native binary from the sibling
            // package @openai/codex-<platform> → the whole @openai scope folder.
            state = "\(home)/.codex"
            let package = (directory as NSString).deletingLastPathComponent
            let parent = (package as NSString).deletingLastPathComponent
            execDir = (parent as NSString).lastPathComponent.hasPrefix("@") ? parent : package
        case .gemini:
            state = "\(home)/.gemini"
            execDir = "\(home)/.gemini/antigravity-cli/bin"
        case .claude:
            return nil
        }
        // A script CLI (npm's `#!/usr/bin/env node`) is started through its checked interpreter.
        guard let start = UsageCLI.launch(binary), let interpreter = start.first else { return nil }
        // agy signs in through /usr/bin/security and the keychain and talks to its helper over
        // /tmp; no other CLI gets any of that.
        let none = "/nonexistent-lrxe8-isle8"
        let agy = vendor == .gemini
        let argv = [
            "/usr/bin/sandbox-exec", "-f", profile, "-D", "HOME=\(home)", "-D", "EXEC=\(binary)",
            "-D", "INTERP=\(interpreter)", "-D", "EXECDIR=\(execDir)", "-D", "STATE=\(state)", "-D", "PTMP=\(temporary)",
            "-D", "HELPER=\(agy ? "/usr/bin/security" : none)",
            "-D", "KEYCHAINS=\(agy ? "\(home)/Library/Keychains" : none)",
            "-D", "SHAREDTMP=\(agy ? "/private/tmp" : none)",
        ] + start + args
        return Box(argv: argv, binary: binary, env: ["TMPDIR": temporary + "/"])
    }
}
