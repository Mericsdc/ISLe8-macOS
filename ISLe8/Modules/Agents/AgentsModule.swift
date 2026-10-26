import SwiftUI

enum AgentKind: String {
    case claude
    case codex

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// The desktop app whose icon stands for the agent, if it is installed.
    var appBundleID: String {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }

    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(white: 0.9)
        }
    }
}

/// One Claude Code or Codex session, as its hooks describe it.
struct AgentSession: Identifiable, Equatable {
    enum Status: Equatable {
        case idle
        case working
        case needsInput
        case waitingApproval
        case done
    }

    let id: String
    let agent: AgentKind
    var project: String
    var status: Status
    /// What it is doing right now, e.g. "$ npm test" or "Düzenliyor: Island.swift".
    var action: String
    var steps: Int
    var turnStarted: Date?
    var updated: Date
    var lastMessage: String?
    /// The latest tool calls of this turn, oldest first.
    var log: [AgentStep] = []
    /// The agent's own to-do list (Claude Code's TodoWrite, Codex's update_plan), if it keeps one.
    var plan: [AgentPlanItem] = []
    /// Files written or edited this turn.
    var changedFiles: Set<String> = []
    var turnEnded: Date?
    /// The app the agent runs in (a terminal, the Claude app), to bring it forward.
    var appPID: pid_t?

    /// "3/6" from the plan, or nil without one.
    var planProgress: (done: Int, total: Int)? {
        guard !plan.isEmpty else { return nil }
        return (plan.filter { $0.state == .done }.count, plan.count)
    }
}

struct AgentStep: Identifiable, Equatable {
    let id: Int
    let tool: String
    let text: String
    let symbol: String
    let started: Date
    var finished: Date?
}

struct AgentPlanItem: Equatable {
    enum State: Equatable {
        case pending
        case active
        case done
    }

    let title: String
    let state: State
}

/// A tool call waiting for a yes or no. The hook that asked is still connected.
struct AgentApproval: Identifiable, Equatable {
    let id: Int
    let sessionID: String
    let agent: AgentKind
    let project: String
    let tool: String
    let detail: String
}

/// Something a script put on the island with `isle8 activity`.
struct ScriptActivity: Identifiable, Equatable {
    let id: String
    var title: String
    var subtitle: String
    var progress: Double?
    var symbol: String
}

/// Claude Code and Codex on the island, through their hooks: what each session is doing,
/// tool approvals answered with a click, and a note when a turn is done. Also hosts the
/// local socket that `isle8 activity` uses.
@Observable
final class AgentsModule: IslandModule {
    let id = "agents"
    private(set) var sessions: [AgentSession] = []
    private(set) var approvals: [AgentApproval] = []
    private(set) var scriptActivities: [ScriptActivity] = []

    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored var onApprovalRequested: ((AgentApproval) -> Void)?
    @ObservationIgnored var onSessionFinished: ((AgentSession) -> Void)?
    /// `isle8 open [tab]` and `isle8 close`: the action and the tab's name.
    @ObservationIgnored var onIslandCommand: ((String, String?) -> Void)?
    /// `isle8 devices`: one line per connected device and its batteries.
    @ObservationIgnored var onDevicesQuery: (() -> [String])?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let server = LocalServer()
    @ObservationIgnored private var replies: [Int: @Sendable (Data) -> Void] = [:]
    @ObservationIgnored private var approvalTimeouts: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
        server.onRequest = { data, connection, reply in
            Task { @MainActor in self.handle(data, connection: connection, reply: reply) }
        }
        server.onAbandoned = { connection in
            Task { @MainActor in self.abandoned(connection) }
        }
    }

    // MARK: Ears

    var activity: LiveActivity? {
        if let approval = approvals.first {
            return LiveActivity(
                id: id,
                priority: ActivityPriority.agentApproval,
                leading: AnyView(AgentIcon(agent: approval.agent, size: 18)),
                trailing: AnyView(AgentAttentionEar())
            )
        }
        if let session = sessions.first(where: { $0.status == .working || $0.status == .needsInput }) {
            return LiveActivity(
                id: id,
                priority: ActivityPriority.agents,
                leading: AnyView(AgentIcon(agent: session.agent, size: 18)),
                trailing: AnyView(session.status == .needsInput ? AnyView(AgentAttentionEar()) : AnyView(AgentWorkingEar(agent: session.agent)))
            )
        }
        if let script = scriptActivities.first {
            return LiveActivity(
                id: id,
                priority: ActivityPriority.agents,
                leading: AnyView(Image(systemName: script.symbol).font(.system(size: 12, weight: .semibold))),
                trailing: AnyView(ScriptActivityEar(activity: script))
            )
        }
        return nil
    }

    var needsAttention: Bool {
        !approvals.isEmpty || sessions.contains { $0.status == .needsInput }
    }

    func start() {
        server.start()
    }

    func stop() {
        // Leave no hook hanging: whoever is still waiting falls back to its own prompt.
        for approval in approvals {
            decide(approval, allow: nil)
        }
        server.stop()
    }

    // MARK: Approvals

    /// nil hands the question back to the agent, which then asks in its own window.
    func decide(_ approval: AgentApproval, allow: Bool?) {
        approvalTimeouts.removeValue(forKey: approval.id)?.cancel()
        let response: [String: Any] = switch allow {
        case true?: ["decision": "allow"]
        case false?: ["decision": "deny", "message": "Denied in ISLe8."]
        case nil: ["decision": "none"]
        }
        if let reply = replies.removeValue(forKey: approval.id) {
            reply(Self.json(response))
        }
        approvals.removeAll { $0.id == approval.id }
        updateSession(approval.sessionID) { session in
            if session.status == .waitingApproval {
                session.status = allow == nil ? .needsInput : .working
            }
        }
        onActivityChange?()
    }

    // MARK: Requests

    private func handle(_ data: Data, connection: Int, reply: @escaping @Sendable (Data) -> Void) {
        guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = request["type"] as? String
        else {
            reply(Self.json(["ok": false]))
            return
        }
        switch type {
        case "hook":
            let agent = AgentKind(rawValue: request["agent"] as? String ?? "") ?? .claude
            let event = request["event"] as? [String: Any] ?? [:]
            let appPID = (request["app_pid"] as? Int).map { pid_t($0) }
            handleHook(agent: agent, event: event, appPID: appPID, connection: connection, reply: reply)
        case "activity":
            handleActivity(request)
            reply(Self.json(["ok": true]))
        case "island":
            onIslandCommand?(request["action"] as? String ?? "", request["tab"] as? String)
            reply(Self.json(["ok": true]))
        case "devices":
            reply(Self.json(["ok": true, "devices": onDevicesQuery?() ?? []]))
        default:
            reply(Self.json(["ok": true, "app": "ISLe8"]))
        }
    }

    private func handleHook(agent: AgentKind, event: [String: Any], appPID: pid_t?, connection: Int, reply: @escaping @Sendable (Data) -> Void) {
        let name = event["hook_event_name"] as? String ?? ""
        let sessionID = "\(agent.rawValue):\(event["session_id"] as? String ?? "default")"
        let project = (event["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? agent.name
        let now = Date()

        func touch(_ change: (inout AgentSession) -> Void) {
            if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                var session = sessions.remove(at: index)
                session.project = project
                session.updated = now
                if let appPID { session.appPID = appPID }
                change(&session)
                sessions.insert(session, at: 0)
            } else {
                var session = AgentSession(
                    id: sessionID, agent: agent, project: project, status: .idle,
                    action: "", steps: 0, turnStarted: nil, updated: now, lastMessage: nil, appPID: appPID
                )
                change(&session)
                sessions.insert(session, at: 0)
            }
        }

        switch name {
        case "SessionStart":
            touch { _ in }
        case "UserPromptSubmit":
            touch {
                $0.status = .working
                $0.action = String(localized: "Düşünüyor…")
                $0.steps = 0
                $0.turnStarted = now
                $0.turnEnded = nil
                $0.lastMessage = nil
                $0.log = []
                $0.changedFiles = []
            }
        case "PreToolUse":
            let tool = event["tool_name"] as? String ?? "?"
            let input = event["tool_input"] as? [String: Any] ?? [:]
            touch {
                $0.status = .working
                $0.action = Self.describe(tool: tool, input: input)
                $0.steps += 1
                if $0.turnStarted == nil { $0.turnStarted = now }
                if let plan = Self.plan(tool: tool, input: input) {
                    $0.plan = plan
                }
                $0.changedFiles.formUnion(Self.changedFiles(tool: tool, input: input))
                // Anything still open was answered without a PostToolUse (denied, interrupted).
                for index in $0.log.indices where $0.log[index].finished == nil {
                    $0.log[index].finished = now
                }
                $0.log.append(AgentStep(
                    id: $0.steps, tool: tool, text: $0.action, symbol: Self.symbol(tool: tool), started: now
                ))
                if $0.log.count > 8 { $0.log.removeFirst($0.log.count - 8) }
            }
        case "PostToolUse":
            let tool = event["tool_name"] as? String ?? "?"
            touch {
                if $0.status != .waitingApproval { $0.status = .working }
                if let index = $0.log.lastIndex(where: { $0.tool == tool && $0.finished == nil }) {
                    $0.log[index].finished = now
                }
            }
        case "PermissionRequest":
            guard settings.agentApprovalsOnIsland else { break }
            let approval = AgentApproval(
                id: connection,
                sessionID: sessionID,
                agent: agent,
                project: project,
                tool: event["tool_name"] as? String ?? "?",
                detail: Self.describe(tool: event["tool_name"] as? String, input: event["tool_input"])
            )
            touch { $0.status = .waitingApproval }
            approvals.append(approval)
            replies[connection] = reply
            let timeout = TimeInterval(settings.agentApprovalTimeout)
            approvalTimeouts[connection] = Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled, let pending = self.approvals.first(where: { $0.id == connection }) else { return }
                self.decide(pending, allow: nil)
            }
            onActivityChange?()
            onApprovalRequested?(approval)
            return
        case "Notification":
            let kind = event["notification_type"] as? String ?? ""
            if ["permission_prompt", "idle_prompt", "agent_needs_input", "elicitation_dialog"].contains(kind) {
                touch {
                    $0.status = .needsInput
                    $0.action = event["message"] as? String ?? String(localized: "Girdi bekliyor")
                }
            }
        case "Stop":
            touch {
                $0.status = .done
                $0.lastMessage = (event["last_assistant_message"] as? String).map(Self.firstLine)
                $0.action = String(localized: "Bitti")
                $0.turnEnded = now
                for index in $0.log.indices where $0.log[index].finished == nil {
                    $0.log[index].finished = now
                }
            }
            if let session = sessions.first(where: { $0.id == sessionID }), settings.agentDoneAlert {
                onSessionFinished?(session)
            }
            scheduleCleanup()
        case "SessionEnd":
            sessions.removeAll { $0.id == sessionID }
        default:
            break
        }
        onActivityChange?()
        reply(Self.json(["ok": true]))
    }

    private func handleActivity(_ request: [String: Any]) {
        guard let id = request["id"] as? String else { return }
        let action = request["action"] as? String ?? "start"
        if action == "end" {
            scriptActivities.removeAll { $0.id == id }
        } else if let index = scriptActivities.firstIndex(where: { $0.id == id }) {
            var activity = scriptActivities[index]
            if let title = request["title"] as? String { activity.title = title }
            if let subtitle = request["subtitle"] as? String { activity.subtitle = subtitle }
            if let progress = request["progress"] as? Double { activity.progress = min(max(progress, 0), 1) }
            if let icon = request["icon"] as? String { activity.symbol = icon }
            scriptActivities[index] = activity
        } else {
            scriptActivities.insert(ScriptActivity(
                id: id,
                title: request["title"] as? String ?? id,
                subtitle: request["subtitle"] as? String ?? "",
                progress: (request["progress"] as? Double).map { min(max($0, 0), 1) },
                symbol: request["icon"] as? String ?? "terminal.fill"
            ), at: 0)
        }
        onActivityChange?()
    }

    /// The hook gave up (its own timeout, or the agent was stopped).
    private func abandoned(_ connection: Int) {
        replies[connection] = nil
        approvalTimeouts.removeValue(forKey: connection)?.cancel()
        guard let approval = approvals.first(where: { $0.id == connection }) else { return }
        approvals.removeAll { $0.id == connection }
        updateSession(approval.sessionID) { if $0.status == .waitingApproval { $0.status = .needsInput } }
        onActivityChange?()
    }

    /// Finished sessions fade from the list after ten minutes.
    private func scheduleCleanup() {
        cleanupTask?.cancel()
        cleanupTask = Task {
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            let cutoff = Date().addingTimeInterval(-600)
            self.sessions.removeAll { $0.status == .done && $0.updated < cutoff }
            if self.sessions.contains(where: { $0.status == .done }) {
                self.scheduleCleanup()
            }
        }
    }

    private func updateSession(_ id: String, _ change: (inout AgentSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[index])
    }

    // MARK: Helpers

    /// A short, readable line for a tool call: "$ npm test", "Düzenliyor: Island.swift".
    static func describe(tool: String?, input: Any?) -> String {
        let tool = tool ?? "?"
        let input = input as? [String: Any] ?? [:]
        func file(_ key: String) -> String? {
            (input[key] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        }
        switch tool {
        case "Bash", "shell", "exec_command", "local_shell":
            let command = input["command"] as? String ?? (input["command"] as? [String])?.joined(separator: " ") ?? ""
            return "$ " + firstLine(command)
        case "Read": return String(localized: "Okuyor: \(file("file_path") ?? "")")
        case "Write": return String(localized: "Yazıyor: \(file("file_path") ?? "")")
        case "Edit", "MultiEdit": return String(localized: "Düzenliyor: \(file("file_path") ?? "")")
        case "NotebookEdit": return String(localized: "Düzenliyor: \(file("notebook_path") ?? "")")
        case "apply_patch": return String(localized: "Yama uyguluyor")
        case "Grep", "Glob": return String(localized: "Arıyor: \(input["pattern"] as? String ?? "")")
        case "WebFetch": return "Web: " + (input["url"] as? String ?? "")
        case "WebSearch": return String(localized: "Web'de arıyor: \(input["query"] as? String ?? "")")
        case "Task", "Agent": return String(localized: "Alt ajan: \(input["description"] as? String ?? "")")
        case "TodoWrite", "update_plan": return String(localized: "Plan güncellendi")
        default:
            let detail = input.values.compactMap { $0 as? String }.first.map(firstLine) ?? ""
            return detail.isEmpty ? tool : "\(tool): \(detail)"
        }
    }

    /// The agent's to-do list, when this call writes one.
    static func plan(tool: String, input: [String: Any]) -> [AgentPlanItem]? {
        func state(_ status: Any?) -> AgentPlanItem.State {
            switch status as? String {
            case "completed": .done
            case "in_progress": .active
            default: .pending
            }
        }
        switch tool {
        case "TodoWrite":
            guard let todos = input["todos"] as? [[String: Any]] else { return nil }
            return todos.map { todo in
                let isActive = todo["status"] as? String == "in_progress"
                let title = (isActive ? todo["activeForm"] as? String : nil) ?? todo["content"] as? String ?? ""
                return AgentPlanItem(title: title, state: state(todo["status"]))
            }
        case "update_plan":
            guard let steps = input["plan"] as? [[String: Any]] else { return nil }
            return steps.map { AgentPlanItem(title: $0["step"] as? String ?? "", state: state($0["status"])) }
        default:
            return nil
        }
    }

    /// Paths a call writes to: Edit and Write name one; a Codex patch lists them in its text.
    static func changedFiles(tool: String, input: [String: Any]) -> [String] {
        switch tool {
        case "Write", "Edit", "MultiEdit":
            return (input["file_path"] as? String).map { [$0] } ?? []
        case "NotebookEdit":
            return (input["notebook_path"] as? String).map { [$0] } ?? []
        case "apply_patch":
            let text = input.values.compactMap { $0 as? String }.joined(separator: "\n")
            return text.split(whereSeparator: \.isNewline).compactMap { line in
                for prefix in ["*** Update File: ", "*** Add File: "] where line.hasPrefix(prefix) {
                    return String(line.dropFirst(prefix.count))
                }
                return nil
            }
        default:
            return []
        }
    }

    static func symbol(tool: String) -> String {
        switch tool {
        case "Bash", "shell", "exec_command", "local_shell": "terminal"
        case "Read": "doc.text"
        case "Write": "doc.badge.plus"
        case "Edit", "MultiEdit", "NotebookEdit", "apply_patch": "pencil.line"
        case "Grep", "Glob": "magnifyingglass"
        case "WebFetch", "WebSearch": "globe"
        case "Task", "Agent": "person.2"
        case "TodoWrite", "update_plan": "checklist"
        default: "wrench.and.screwdriver"
        }
    }

    static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.count > 120 ? String(line.prefix(117)) + "…" : line
    }

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }
}
