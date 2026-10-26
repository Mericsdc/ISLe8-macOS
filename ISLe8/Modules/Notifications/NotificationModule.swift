import SwiftUI

/// Mirrors other apps' notifications on the island, and collects them for the lock screen.
@Observable
final class NotificationModule: IslandModule {
    enum Access {
        case off
        case checking
        case granted
        case needsFullDiskAccess
        case unavailable
    }

    let id = "notifications"
    var activity: LiveActivity? { nil }
    private(set) var access: Access = .off
    /// What arrived while the screen was locked; cleared on unlock.
    private(set) var lockedNotifications: [AppNotification] = []

    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored var onShow: ((AppNotification) -> Void)?
    @ObservationIgnored var isLocked: () -> Bool = { false }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let diagnosticsURL: URL
    @ObservationIgnored private var database: NotificationDatabase?
    @ObservationIgnored private var isStarted = false

    init(settings: SettingsStore, folder: URL) {
        self.settings = settings
        diagnosticsURL = folder.appending(path: "notification-db.txt")
        settings.onModuleSettingsChange { [weak self] in self?.applySettings() }
    }

    func start() {
        isStarted = true
        applySettings()
    }

    func stop() {
        isStarted = false
        closeDatabase()
    }

    /// Tries the database again, for example after Full Disk Access was granted.
    func retry() {
        closeDatabase()
        applySettings()
    }

    /// Opens the Full Disk Access list next to ISLe8 in Finder. Apps don't appear in that list
    /// on their own; they have to be dragged in or added with "+".
    func openFullDiskAccessSettings() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func lockChanged(_ locked: Bool) {
        if !locked {
            lockedNotifications.removeAll()
        }
    }

    private func applySettings() {
        guard isStarted, settings.notificationsEnabled else {
            closeDatabase()
            return
        }
        guard database == nil else { return }
        let database = NotificationDatabase(diagnosticsURL: diagnosticsURL)
        self.database = database
        access = .checking
        database.start(
            onAccess: { access in
                Task { @MainActor in self.accessChecked(access) }
            },
            onNew: { notifications in
                Task { @MainActor in self.received(notifications) }
            }
        )
    }

    private func closeDatabase() {
        database?.stop()
        database = nil
        access = .off
    }

    private func accessChecked(_ result: NotificationDatabase.Access) {
        guard database != nil else { return }
        switch result {
        case .granted: access = .granted
        case .needsFullDiskAccess: access = .needsFullDiskAccess
        case .unavailable: access = .unavailable
        }
    }

    private func received(_ notifications: [AppNotification]) {
        remember(notifications.map(\.bundleID))
        let visible = notifications.filter { !settings.mutedNotificationApps.contains($0.bundleID) }
        guard !visible.isEmpty else { return }

        if isLocked() {
            guard settings.lockScreenShowsNotifications, settings.notificationTiming != .whenUnlocked else { return }
            lockedNotifications = Array((visible.reversed() + lockedNotifications).prefix(20))
            return
        }
        guard settings.notificationTiming != .whenLocked else { return }
        let respectFocus = settings.respectFocus
        Task {
            if respectFocus, await Task.detached(operation: { FocusStatus.isActive() }).value {
                return
            }
            visible.forEach { onShow?($0) }
        }
    }

    /// Keeps a short list of apps that sent notifications, for muting them in Settings.
    private func remember(_ bundleIDs: [String]) {
        var seen = settings.notificationSeenApps
        for id in bundleIDs where !seen.contains(id) {
            seen.insert(id, at: 0)
        }
        if seen != settings.notificationSeenApps {
            settings.notificationSeenApps = Array(seen.prefix(30))
        }
    }
}
