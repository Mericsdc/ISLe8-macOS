import Foundation

/// Adds ISLe8's hooks to Claude Code (~/.claude/settings.json) or Codex (~/.codex/hooks.json),
/// and takes them out again. Only entries that call `isle8 hook` are ever touched; the
/// file is backed up next to itself before the first change.
enum AgentHooks {
    enum Target {
        case claude
        case codex

        var file: URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            switch self {
            case .claude: return home.appending(path: ".claude/settings.json")
            case .codex: return home.appending(path: ".codex/hooks.json")
            }
        }

        var agent: AgentKind {
            switch self {
            case .claude: .claude
            case .codex: .codex
            }
        }

        var events: [String] {
            switch self {
            case .claude:
                ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "SessionEnd"]
            case .codex:
                ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]
            }
        }
    }

    /// The `isle8` link that install.sh puts in ~/.local/bin, or the app binary itself.
    static var command: String {
        let link = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/isle8").path
        return FileManager.default.isExecutableFile(atPath: link) ? link : Bundle.main.executablePath ?? "isle8"
    }

    /// `file` defaults to the agent's own settings file; tests pass a copy.
    static func isInstalled(_ target: Target, file: URL? = nil) -> Bool {
        guard let hooks = read(file ?? target.file)["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in
            (groups as? [[String: Any]])?.contains(where: isOurs) ?? false
        }
    }

    static func install(_ target: Target, file: URL? = nil) throws {
        var root = read(file ?? target.file)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in target.events {
            var groups = (hooks[event] as? [[String: Any]] ?? []).filter { !isOurs($0) }
            // No matcher: every tool. An approval may wait for the user, so it gets the full 600 s.
            groups.append(["hooks": [[
                "type": "command",
                "command": "\"\(command)\" hook \(target.agent.rawValue)",
                "timeout": event == "PermissionRequest" ? 600 : 5,
            ]]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try write(root, to: file ?? target.file)
    }

    static func uninstall(_ target: Target, file: URL? = nil) throws {
        var root = read(file ?? target.file)
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            let remaining = (value as? [[String: Any]] ?? []).filter { !isOurs($0) }
            hooks[event] = remaining.isEmpty ? nil : remaining
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try write(root, to: file ?? target.file)
    }

    // MARK: Files

    private static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { handler in
            guard let command = (handler["command"] as? String)?.lowercased() else { return false }
            return command.contains("isle8") && (command.contains(" hook claude") || command.contains(" hook codex"))
        }
    }

    private static func read(_ file: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    private static func write(_ root: [String: Any], to file: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = file.appendingPathExtension("isle8-backup")
        if manager.fileExists(atPath: file.path) && !manager.fileExists(atPath: backup.path) {
            try manager.copyItem(at: file, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
    }
}
