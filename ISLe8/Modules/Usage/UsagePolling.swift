import Foundation

// Ported from LimitBar LRX's Preferences.swift and Store.swift (see UsageModule.swift for the credit).

nonisolated enum UsagePollingPolicy {
    /// How often a vendor is asked live with the island closed. Open, Codex and Antigravity are
    /// asked every minute instead (outside saver mode); Claude never more often than this.
    static func remoteInterval(_ vendor: UsageVendor, economy: Bool) -> TimeInterval {
        switch vendor {
        case .claude: 20 * 60
        case .codex, .gemini: economy ? 15 * 60 : 5 * 60
        }
    }

    /// 1, 2, 4 … up to 30 min after consecutive failures.
    static func retryDelay(failures: Int) -> TimeInterval {
        min(30 * 60, 60 * pow(2, Double(max(0, min(5, failures - 1)))))
    }
}

/// Decides, per vendor, whether a CLI has to be asked or a free source is enough, and asks.
/// Runs only on the module's serial fetch queue; every property is touched only there.
nonisolated final class UsageFetcher: @unchecked Sendable {
    let codexLogs: UsageCodexLogs
    private var lastClaudeUsage = Date.distantPast
    private var lastAccountCheck = Date.distantPast
    private var lastCodexServer = Date.distantPast
    private var claudeAccount: (signedIn: Bool, plan: String)?

    init(codexLogs: UsageCodexLogs = UsageCodexLogs()) {
        self.codexLogs = codexLogs
    }

    /// nil = nothing new (or cancelled). `asking` is called right before a CLI is started.
    func fetch(
        _ vendor: UsageVendor,
        previous: UsageSnapshot?,
        force: Bool,
        remoteGap: TimeInterval,
        asking: () -> Void
    ) -> UsageSnapshot? {
        let (found, why) = UsageFetch.binary(vendor)
        guard found != nil else { return why }
        switch vendor {
        case .claude:
            return claude(previous: previous, force: force, asking: asking)
        case .gemini:
            asking()
            return UsageFetch.gemini()
        case .codex:
            return codex(previous: previous, force: force, remoteGap: remoteGap, asking: asking)
        }
    }

    private var isCancelled: Bool { UsageCLI.currentCancellation?.isCancelled == true }

    private func claude(previous: UsageSnapshot?, force: Bool, asking: () -> Void) -> UsageSnapshot? {
        // Limitbar re-checked an unconfirmed sign-in on every 30 s tick; a CLI whose
        // `auth status` keeps failing would then start every 30 s. Five minutes is plenty.
        let sinceCheck = Date().timeIntervalSince(lastAccountCheck)
        if force || sinceCheck >= 30 * 60 || (claudeAccount?.signedIn != true && sinceCheck >= 5 * 60) {
            asking()
            let account = UsageFetch.claudeAccount()
            guard !isCancelled else { return nil }
            lastAccountCheck = Date()
            claudeAccount = account ?? claudeAccount
        }
        if claudeAccount?.signedIn == false { return .status(.claude, .signedOut) }
        // A manual refresh asks live at most every 30 s; otherwise at most every 20 min.
        var out: UsageSnapshot?
        let sinceLive = Date().timeIntervalSince(lastClaudeUsage)
        if force ? sinceLive >= 30 : sinceLive >= 20 * 60 {
            asking()
            out = UsageFetch.claudeUsage()
            guard !isCancelled else { return nil }
            lastClaudeUsage = Date()
        }
        guard var out else {
            return previous ?? .status(.claude, .failed, String(localized: "Kullanım verisi bekleniyor."))
        }
        out.plan = claudeAccount?.plan ?? out.plan
        return out
    }

    private func codex(previous: UsageSnapshot?, force: Bool, remoteGap: TimeInterval, asking: () -> Void) -> UsageSnapshot? {
        let logs = codexLogs.latest()
        let remoteAge = Date().timeIntervalSince(lastCodexServer)
        let remoteDue = remoteAge >= remoteGap
        // The session log is free; the app-server only when it is due (a manual refresh: at
        // most every 30 s).
        if (!force && !remoteDue) || (force && remoteAge < 30) {
            if let logs, (logs.measuredAt ?? .distantPast) > (previous?.measuredAt ?? .distantPast) { return logs }
            return previous?.state == .failed ? nil : (previous ?? logs)
        }
        asking()
        let server = UsageFetch.codexFromServer()
        guard !isCancelled else { return nil }
        lastCodexServer = Date()
        if server.state == .failed, var logs {
            logs.error = String(localized: "Sunucuya erişilemedi; son yerel kayıt gösteriliyor.")
            logs.state = .failed
            return logs
        }
        return server
    }
}
