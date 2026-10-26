import SwiftUI

/// The agent's desktop app icon, or a tinted symbol when that app isn't installed.
struct AgentIcon: View {
    let agent: AgentKind
    let size: CGFloat

    var body: some View {
        if let icon = AppInfo.icon(for: agent.appBundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: agent.fallbackSymbol)
                .font(.system(size: size * 0.7, weight: .semibold))
                .foregroundStyle(agent.tint)
                .frame(width: size, height: size)
        }
    }
}

// MARK: Ears

/// Bouncing bars in the agent's color while it works (Core Animation, no CPU).
struct AgentWorkingEar: View {
    let agent: AgentKind

    var body: some View {
        AudioBars(isPlaying: true, color: NSColor(agent.tint))
            .frame(width: 20, height: 12)
    }
}

/// Waiting on the user: an approval or a question.
struct AgentAttentionEar: View {
    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.orange)
            .symbolEffect(.pulse, options: .repeating)
    }
}

struct ScriptActivityEar: View {
    let activity: ScriptActivity

    var body: some View {
        if let progress = activity.progress {
            Text("%\(Int((progress * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        } else {
            AudioBars(isPlaying: true, color: .white)
                .frame(width: 20, height: 12)
        }
    }
}

// MARK: AI tab

/// Approvals first, then a run card for the session being followed, after componest's
/// agent status component; the usage rings sit below.
struct AgentsTab: View {
    @Environment(AgentsModule.self) private var agents
    @State private var followedID: String?

    var body: some View {
        // The island has a fixed height; a busy AI tab scrolls inside it.
        ScrollView(.vertical) {
            content
        }
        .scrollIndicators(.never)
    }

    private var content: some View {
        VStack(spacing: 8) {
            if let approval = agents.approvals.first {
                ApprovalCard(approval: approval)
            }
            if agents.sessions.isEmpty && agents.scriptActivities.isEmpty {
                if agents.approvals.isEmpty { emptyState }
            } else {
                if agents.sessions.count > 1 {
                    SessionSwitcher(sessions: agents.sessions, selection: followed?.id) { followedID = $0 }
                }
                if let session = followed {
                    RunCard(session: session)
                }
                ForEach(agents.scriptActivities.prefix(agents.sessions.isEmpty ? 3 : 1)) { activity in
                    ScriptActivityRow(activity: activity)
                }
            }
            UsageStrip()
        }
    }

    /// The one picked in the switcher, else whoever is working or waiting, else the latest.
    private var followed: AgentSession? {
        let sessions = agents.sessions
        return sessions.first { $0.id == followedID }
            ?? sessions.first { $0.status == .waitingApproval || $0.status == .needsInput }
            ?? sessions.first { $0.status == .working }
            ?? sessions.first
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
            Text("Çalışan ajan yok")
                .font(.system(size: 12, weight: .semibold))
            Text("Claude Code ya da Codex çalışınca burada görünür. Bağlamak için: Ayarlar > Ajanlar.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .islandTile()
    }
}

private struct SessionSwitcher: View {
    let sessions: [AgentSession]
    let selection: String?
    let select: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(sessions) { session in
                    Button { select(session.id) } label: {
                        HStack(spacing: 5) {
                            AgentIcon(agent: session.agent, size: 14)
                            Text(session.project)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            StatusDot(status: session.status)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white.opacity(session.id == selection ? 0.14 : 0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: 24)
    }
}

private struct StatusDot: View {
    let status: AgentSession.Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    private var color: Color {
        switch status {
        case .working: .blue
        case .needsInput, .waitingApproval: .orange
        case .done: .green
        case .idle: Color.white.opacity(0.4)
        }
    }
}

/// One session's turn: what it does now, how far along it is, the last few steps.
private struct RunCard: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                RunStatusGlyph(status: session.status)
                Text(headline)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Elapsed(session: session)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            HStack(spacing: 6) {
                AgentIcon(agent: session.agent, size: 13)
                Text("\(session.agent.name) · \(session.project)")
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(progressText)
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.5))

            SegmentedBar(session: session)

            VStack(spacing: 5) {
                ForEach(session.log.suffix(4)) { step in
                    StepRow(step: step, isCurrent: step.finished == nil && session.status == .working)
                }
                // While it thinks the headline already says so; after a turn without tools,
                // its last words.
                if session.log.isEmpty, session.status != .working, let message = session.lastMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if session.appPID != nil {
                HStack {
                    Spacer()
                    Button {
                        if let pid = session.appPID {
                            NSRunningApplication(processIdentifier: pid)?.activate()
                        }
                    } label: {
                        Label("Oturuma git", systemImage: "arrow.up.right")
                            .labelStyle(TrailingIconLabel())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .islandTile()
    }

    private var headline: String {
        switch session.status {
        case .done:
            var parts = [String(localized: "Bitti")]
            if let started = session.turnStarted, let ended = session.turnEnded {
                parts.append(String(localized: "\(Int(ended.timeIntervalSince(started).rounded())) sn"))
            }
            if !session.changedFiles.isEmpty {
                parts.append(String(localized: "\(session.changedFiles.count) dosya değişti"))
            }
            return parts.joined(separator: " · ")
        case .waitingApproval:
            return String(localized: "Onay bekliyor")
        case .needsInput:
            return session.action.isEmpty ? String(localized: "Seni bekliyor") : session.action
        case .working:
            return session.action.isEmpty ? String(localized: "Düşünüyor…") : session.action
        case .idle:
            return session.action.isEmpty ? String(localized: "Hazır") : session.action
        }
    }

    private var progressText: String {
        if let plan = session.planProgress {
            return String(localized: "Adım \(min(plan.done + (session.status == .done ? 0 : 1), plan.total))/\(plan.total)")
        }
        return String(localized: "\(session.steps) adım")
    }
}

private struct RunStatusGlyph: View {
    let status: AgentSession.Status

    var body: some View {
        switch status {
        case .working:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 14, height: 14)
        case .done:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.green)
        case .needsInput, .waitingApproval:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Color.orange)
        case .idle:
            Image(systemName: "circle.dashed")
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }
}

/// The turn's running time, ticking once a second only while the agent works.
private struct Elapsed: View {
    let session: AgentSession

    var body: some View {
        if let started = session.turnStarted {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let end = session.status == .working ? context.date : (session.turnEnded ?? session.updated)
                Text(TimerText.format(end.timeIntervalSince(started), roundingUp: false))
            }
        }
    }
}

/// One segment per item of the agent's plan; without a plan, one per step so far.
private struct SegmentedBar: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, state in
                Capsule()
                    .fill(fill(state))
                    .frame(height: 4)
            }
        }
    }

    private var segments: [AgentPlanItem.State] {
        if !session.plan.isEmpty {
            return session.plan.map { $0.state }
        }
        let done = min(session.steps, 12)
        let active: [AgentPlanItem.State] = session.status == .working ? [.active] : []
        return Array(repeating: .done, count: max(done - active.count, 0)) + active + (done == 0 ? [.pending] : [])
    }

    private func fill(_ state: AgentPlanItem.State) -> AnyShapeStyle {
        switch state {
        case .done: AnyShapeStyle(.tint)
        case .active: AnyShapeStyle(.tint.opacity(0.45))
        case .pending: AnyShapeStyle(Color.white.opacity(0.1))
        }
    }
}

private struct StepRow: View {
    let step: AgentStep
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: step.symbol)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 14)
            Text(step.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let finished = step.finished {
                Text(Self.seconds(finished.timeIntervalSince(step.started)))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.4))
            } else if isCurrent {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.seconds(context.date.timeIntervalSince(step.started)))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.white.opacity(isCurrent ? 0.55 : 0.85))
    }

    static func seconds(_ interval: TimeInterval) -> String {
        let value = interval < 10
            ? interval.formatted(.number.precision(.fractionLength(1)))
            : Int(interval.rounded()).formatted()
        return String(localized: "\(value) sn")
    }
}

/// "Oturuma git ↗": the text, then the icon.
private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

private struct ApprovalCard: View {
    let approval: AgentApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AgentIcon(agent: approval.agent, size: 18)
                Text("\(approval.agent.name) · \(approval.project)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer()
                Text("Onay bekliyor")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.orange)
            }
            Text(approval.detail)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
            ApprovalButtons(approval: approval)
        }
        .padding(10)
        .islandTile()
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.45), lineWidth: 1)
        }
    }
}

struct ApprovalButtons: View {
    @Environment(AgentsModule.self) private var agents
    let approval: AgentApproval

    var body: some View {
        HStack(spacing: 6) {
            Button {
                agents.decide(approval, allow: true)
            } label: {
                Label("Onayla", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(Capsule().fill(.tint))
            }
            .buttonStyle(.plain)
            PillButton(title: "Reddet", systemImage: "xmark") { agents.decide(approval, allow: false) }
            Spacer(minLength: 0)
            Button("Terminalde sor") { agents.decide(approval, allow: nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }
}

private struct ScriptActivityRow: View {
    let activity: ScriptActivity

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(.system(size: 12, weight: .semibold))
                if !activity.subtitle.isEmpty {
                    Text(activity.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                if let progress = activity.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .islandTile()
    }
}

// MARK: Banners

struct ApprovalAlertView: View {
    let approval: AgentApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AgentIcon(agent: approval.agent, size: 18)
                Text("\(approval.agent.name) onay istiyor · \(approval.project)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
            }
            Text(approval.detail)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(2)
            ApprovalButtons(approval: approval)
        }
    }
}

struct AgentDoneAlertView: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            AgentIcon(agent: session.agent, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(session.agent.name) bitti · \(session.project)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(session.lastMessage ?? String(localized: "Sıra sende"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
