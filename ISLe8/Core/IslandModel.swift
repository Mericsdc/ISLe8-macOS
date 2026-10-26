import SwiftUI

enum IslandState: Equatable {
    /// Hidden behind the notch.
    case idle
    /// A live activity shows in the ears beside the notch.
    case compact
    /// The pointer is resting on the island.
    case peek
    /// A short-lived banner, for example a new song.
    case alert
    /// The full panel.
    case expanded
    /// Files are being dragged towards the notch: shows the shelf and AirDrop drop zones.
    case dropTarget
}

enum IslandAlert: Equatable {
    case nowPlaying
    case airDropReceived(count: Int)
    case notification(AppNotification)
    /// A short open-lock in the ears right after the Mac is unlocked.
    case unlocked
    case hud(HUDValue)
    case battery(BatteryEvent)
    case meeting(UpcomingItem)
    case timer(TimerEvent)
    case approval(AgentApproval)
    case agentDone(AgentSession)
    case usageLimit(UsageSnapshot, UsageWindow)
    case deviceConnected(WirelessDevice)
    case deviceLowBattery(WirelessDevice)
}

enum IslandTab: String, Hashable, CaseIterable {
    case home
    case shelf
    case clipboard
    case agents
    case devices
    /// The ⌘K command palette; opened by its shortcut, never shown among the tabs.
    case palette
}

/// Where the island lives: the notch, or a notch-sized pill on a screen without one.
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchMidX: CGFloat
    var notchSize: CGSize
    var hasNotch: Bool
    /// How big the island should be drawn on this screen when set to automatic: 1 on a
    /// MacBook or 1080p screen, more on 2K and 4K ones.
    var autoScale: CGFloat = 1
}

/// The island's state machine. It decides which state the island is in and how big each
/// state is; IslandController moves the window, the views draw it.
@Observable
final class IslandModel {
    static let earWidth: CGFloat = 40
    /// Wider ears for volume and brightness, so the level bar has room.
    static let hudEarWidth: CGFloat = 70
    /// Reopening within this time returns to the tab you left; later it starts at Home.
    private static let tabMemory: TimeInterval = 15

    let settings: SettingsStore
    let modules: [any IslandModule]
    private(set) var state: IslandState = .idle
    private(set) var alert: IslandAlert?
    private(set) var geometry: NotchGeometry?
    private(set) var isPinned = false
    /// Whether the last change made the island bigger. Growing and shrinking use different springs.
    private(set) var isGrowing = true
    private(set) var tab: IslandTab = .home
    /// Set when the clipboard shortcut opens the island, so the search field takes the keyboard.
    private(set) var wantsSearchFocus = false
    /// While the screen is locked the island stays at rest; the lock screen window takes over.
    private(set) var isLocked = false
    /// Notifications waiting for the current banner to finish, shown as "+N" on it.
    private(set) var pendingNotificationCount = 0
    /// Shows the lock screen layout for a few seconds while unlocked, to place the cards.
    private(set) var isPreviewingLockScreen = false
    @ObservationIgnored var onLockScreenPreviewChange: ((Bool) -> Void)?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    @ObservationIgnored var onLayoutChange: (() -> Void)?
    /// The island opened (true) or closed (false).
    @ObservationIgnored var onExpandedChange: ((Bool) -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?
    /// Lets a module claim the tab the island opens on, e.g. agents waiting for an answer.
    @ObservationIgnored var preferredTabOnOpen: (() -> IslandTab?)?
    /// Asks the window to take keyboard input without activating ISLe8.
    @ObservationIgnored var onRequestKeyboard: (() -> Void)?

    /// A text field on the open island (the calendar's quick add) wants to be typed into.
    func requestKeyboard() {
        onRequestKeyboard?()
    }
    @ObservationIgnored private var isHovering = false
    @ObservationIgnored private var closedAt = Date.distantPast
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private var pendingNotifications: [AppNotification] = [] {
        didSet { pendingNotificationCount = pendingNotifications.count }
    }

    init(settings: SettingsStore, modules: [any IslandModule]) {
        self.settings = settings
        self.modules = modules
        for module in modules {
            module.onActivityChange = { [weak self] in self?.activitiesChanged() }
        }
    }

    /// An agent waiting for approval always wins; otherwise the user's order decides.
    var primaryActivity: LiveActivity? {
        let activities = modules.compactMap { $0.activity }
        if let urgent = activities.first(where: { $0.priority >= ActivityPriority.agentApproval }) {
            return urgent
        }
        let order = settings.activityOrder
        return activities.min { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
    }

    /// The tabs in the header, in the user's order, without hidden ones.
    var visibleTabs: [IslandTab] {
        let tabs = settings.tabOrder
            .filter { !settings.hiddenTabs.contains($0) }
            .compactMap(IslandTab.init(rawValue:))
        return tabs.isEmpty ? [.home] : tabs
    }

    /// One height for every tab. Switching tabs then only swaps the content: the island and
    /// its dock stay where they are, so the pointer resting on the dock stays inside and the
    /// island doesn't close under it. Sized for Home's calendar, media and weather columns.
    /// The open island's width, by Home style.
    var expandedWidth: CGFloat {
        let notch = geometry?.notchSize.width ?? 185
        switch settings.homeStyle {
        case .dashboard: return max(settings.expandedWidth, notch + 480)
        case .compact: return max(640, notch + 400)
        case .minimal: return max(600, notch + 380)
        }
    }

    /// Content height between the header and the dock. Within the dashboard and compact
    /// styles every tab has the same height, so switching tabs never resizes the island;
    /// minimal Home is a single strip and the other tabs need more room than that.
    func contentHeight(for tab: IslandTab) -> CGFloat {
        if tab == .palette { return 280 }
        switch settings.homeStyle {
        case .dashboard: return 304
        case .compact: return 196
        case .minimal: return tab == .home ? 64 : 196
        }
    }

    /// How much bigger or smaller the island is drawn. Always 1 under the notch, which has
    /// a fixed physical size; on other screens by their resolution or the setting, and never
    /// wider than the screen.
    var scale: CGFloat {
        guard let geometry, !geometry.hasNotch else { return 1 }
        let wanted = settings.externalScale > 0 ? CGFloat(settings.externalScale) : geometry.autoScale
        let room = (geometry.screenFrame.width - 40) / expandedWidth
        return min(wanted, max(room, 0.5))
    }

    /// Space under the content for the tab dock, or a margin where there is none.
    func bottomSpace(for tab: IslandTab) -> CGFloat {
        tab == .palette ? 14 : 8 + TabDock.height + 10
    }

    /// The state the island returns to when nobody is interacting with it.
    var restingState: IslandState {
        primaryActivity == nil ? .idle : .compact
    }

    var animation: Animation {
        // With Reduce Motion on, the island changes size quickly and without bouncing.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .easeInOut(duration: 0.16)
        }
        let speed = min(max(settings.animationSpeed, 0.5), 2)
        return isGrowing
            ? .spring(response: 0.34 / speed, dampingFraction: 0.78)
            : .spring(response: 0.28 / speed, dampingFraction: 0.95)
    }

    // MARK: Geometry

    func size(for state: IslandState) -> CGSize {
        guard let geometry else { return .zero }
        let notch = geometry.notchSize
        let compact = CGSize(
            width: notch.width + 2 * Self.earWidth + 2 * shoulder(for: .compact),
            height: notch.height
        )
        switch state {
        case .idle:
            // A hair smaller than the physical notch so that none of it peeks out.
            return geometry.hasNotch ? CGSize(width: notch.width - 4, height: notch.height - 1) : notch
        case .compact:
            return compact
        case .peek:
            let base = restingState == .compact
                ? compact
                : CGSize(width: notch.width + 2 * shoulder(for: .peek), height: notch.height)
            return CGSize(width: base.width + 18, height: base.height + 6)
        case .alert:
            switch alert {
            case .notification, .meeting:
                return CGSize(width: max(400, notch.width + 200), height: notch.height + 74)
            case .approval:
                return CGSize(width: max(440, notch.width + 240), height: notch.height + 100)
            case .agentDone:
                return CGSize(width: max(400, notch.width + 200), height: notch.height + 50)
            case .deviceConnected, .deviceLowBattery:
                return CGSize(width: max(420, notch.width + 220), height: notch.height + 56)
            case .unlocked:
                return compact
            case .hud:
                return CGSize(width: notch.width + 2 * Self.hudEarWidth + 2 * shoulder(for: .compact), height: notch.height)
            case .nowPlaying, .airDropReceived, .battery, .timer, .usageLimit, nil:
                return CGSize(width: max(compact.width + 60, 340), height: notch.height + 46)
            }
        case .expanded:
            return CGSize(
                width: expandedWidth,
                height: notch.height + 6 + contentHeight(for: tab) + bottomSpace(for: tab)
            )
        case .dropTarget:
            return CGSize(width: max(460, notch.width + 240), height: notch.height + 112)
        }
    }

    /// The window's fixed size: room for the biggest the island gets, plus what a bouncing
    /// spring overshoots.
    var canvasSize: CGSize {
        guard let geometry else { return .zero }
        let notch = geometry.notchSize
        let widest = max(expandedWidth, notch.width + 320, 480)
        return CGSize(width: (widest + 60) * scale, height: (notch.height + 460) * scale)
    }

    /// Radius of the concave corners where the island meets the top edge of the screen.
    func shoulder(for state: IslandState) -> CGFloat {
        switch state {
        case .idle: 0
        case .compact, .peek: 6
        case .alert: 8
        case .expanded, .dropTarget: 10
        }
    }

    func bottomRadius(for state: IslandState) -> CGFloat {
        switch state {
        case .idle: 9
        case .compact: 12
        case .peek: 14
        case .alert: 20
        // The open island follows the theme's corners: sharp themes get a crisper outline.
        case .dropTarget, .expanded: min(settings.theme.cornerRadius + 12, 28)
        }
    }

    func setGeometry(_ geometry: NotchGeometry?) {
        guard geometry != self.geometry else { return }
        self.geometry = geometry
        onLayoutChange?()
    }

    // MARK: Interaction

    func setHovering(_ inside: Bool) {
        isHovering = inside
        // A file drag decides on its own when the drop target closes.
        guard state != .dropTarget, !isLocked else { return }
        // A banner stays while the pointer rests on it, so there is time to read it.
        if state == .alert {
            alertTask?.cancel()
            if !inside {
                endAlert(after: .seconds(1.2))
            }
            return
        }
        hoverTask?.cancel()
        closeTask?.cancel()

        if inside {
            guard state != .expanded else { return }
            alertTask?.cancel()
            hoverTask = Task {
                if self.settings.openMode == .hover {
                    // Straight open; the short wait only skips a pointer passing over the notch.
                    try? await Task.sleep(for: .seconds(max(self.settings.openDelay, 0.05)))
                    guard !Task.isCancelled else { return }
                    self.openFromHover()
                } else {
                    // Click mode: a slight swell says the island can be clicked.
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled else { return }
                    self.transition(to: .peek)
                }
            }
        } else {
            guard !(isPinned && state == .expanded) else { return }
            let delay = state == .expanded ? settings.closeDelay : 0.05
            closeTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self.transition(to: self.restingState)
            }
        }
    }

    /// A click on the island.
    func open() {
        cancelPendingChanges()
        if state != .expanded {
            chooseTabForOpening()
        }
        transition(to: .expanded)
    }

    func open(_ tab: IslandTab) {
        cancelPendingChanges()
        self.tab = tab
        transition(to: .expanded)
        onLayoutChange?()
    }

    func close() {
        cancelPendingChanges()
        transition(to: restingState)
    }

    func select(_ tab: IslandTab) {
        guard tab != self.tab else { return }
        let old = size(for: state)
        self.tab = tab
        guard state == .expanded else { return }
        let new = size(for: .expanded)
        isGrowing = new.height >= old.height
        onLayoutChange?()
    }

    /// The clipboard shortcut: opens the clipboard tab ready for typing, or closes it again.
    func toggleClipboardFromShortcut() {
        guard !isLocked else { return }
        if state == .expanded && tab == .clipboard {
            close()
            return
        }
        open(.clipboard)
        wantsSearchFocus = true
        onRequestKeyboard?()
    }

    /// The ⌘K palette shortcut: opens the palette ready for typing, or closes it again.
    func togglePaletteFromShortcut() {
        guard !isLocked else { return }
        if state == .expanded && tab == .palette {
            close()
            return
        }
        open(.palette)
        wantsSearchFocus = true
        onRequestKeyboard?()
    }

    /// A two-finger swipe on the open island: the next (1) or previous (-1) tab.
    func selectAdjacentTab(_ step: Int) {
        let tabs = visibleTabs
        guard state == .expanded, let index = tabs.firstIndex(of: tab), tabs.indices.contains(index + step) else { return }
        select(tabs[index + step])
    }

    /// A click somewhere outside ISLe8 closes an island that the pointer never entered,
    /// for example one opened with the keyboard.
    func clickedOutside() {
        guard state == .expanded, !isPinned, !isHovering else { return }
        close()
    }

    func togglePin() {
        isPinned.toggle()
        if !isPinned && !isHovering {
            setHovering(false)
        }
    }

    func openSettings() {
        onOpenSettings?()
        isPinned = false
        close()
    }

    func showAlert(_ alert: IslandAlert, for duration: Duration = .seconds(2.5)) {
        guard canShowAlert else { return }
        alertTask?.cancel()
        let old = size(for: state)
        self.alert = alert
        if state == .alert {
            // Swapping one banner for another can change its size without a state change.
            isGrowing = size(for: .alert).height >= old.height
            onLayoutChange?()
        } else {
            transition(to: .alert)
        }
        endAlert(after: duration)
    }

    /// Notifications queue up behind a banner that is already showing one, and wait while
    /// the island is open, instead of being dropped.
    func showNotification(_ notification: AppNotification) {
        guard !isLocked else { return }
        if canShowAlert, !isShowingNotification {
            showAlert(.notification(notification), for: .seconds(settings.notificationDuration))
        } else {
            pendingNotifications = Array((pendingNotifications + [notification]).suffix(5))
        }
    }

    /// Volume or brightness. Unlike other banners it also shows while the pointer rests on
    /// the island, since with the system HUD replaced it is the only feedback. It never
    /// covers an open island or a notification.
    func showHUD(_ value: HUDValue) {
        guard !isLocked else { return }
        switch state {
        case .expanded, .dropTarget:
            return
        case .alert where isShowingNotification:
            return
        default:
            break
        }
        hoverTask?.cancel()
        alertTask?.cancel()
        let old = size(for: state)
        alert = .hud(value)
        if state == .alert {
            isGrowing = size(for: .alert).width >= old.width
            onLayoutChange?()
        } else {
            transition(to: .alert)
        }
        endAlert(after: .seconds(1.5))
    }

    /// A click on a banner: it has done its job.
    func dismissAlert() {
        alertTask?.cancel()
        guard state == .alert else { return }
        transition(to: restingState)
    }

    // MARK: Lock screen

    /// Shows (or keeps showing) the lock screen layout for three seconds without locking.
    func previewLockScreen() {
        guard !isLocked else { return }
        previewTask?.cancel()
        isPreviewingLockScreen = true
        onLockScreenPreviewChange?(true)
        previewTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.endLockScreenPreview()
        }
    }

    private func endLockScreenPreview() {
        previewTask?.cancel()
        guard isPreviewingLockScreen else { return }
        isPreviewingLockScreen = false
        onLockScreenPreviewChange?(false)
    }

    func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        endLockScreenPreview()
        isLocked = locked
        cancelPendingChanges()
        isPinned = false
        pendingNotifications.removeAll()
        if locked {
            transition(to: restingState)
        } else if settings.lockScreenEnabled {
            showAlert(.unlocked, for: .seconds(1.2))
        }
    }

    // MARK: File drags

    /// A file drag came close to the notch (true) or went away or ended (false).
    func setFileDragNearby(_ near: Bool) {
        guard !isLocked else { return }
        if near {
            guard state != .dropTarget else { return }
            cancelPendingChanges()
            transition(to: .dropTarget)
        } else if state == .dropTarget {
            transition(to: restingState)
        }
    }

    /// Files landed on the shelf zone: show them.
    func showShelfAfterDrop() {
        open(.shelf)
    }

    // MARK: Private

    private var canShowAlert: Bool {
        [.idle, .compact, .alert].contains(state) && !isHovering && !isLocked
    }

    private var isShowingNotification: Bool {
        if state == .alert, case .notification = alert { return true }
        return false
    }

    private func endAlert(after duration: Duration) {
        alertTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, self.state == .alert else { return }
            self.transition(to: self.restingState)
        }
    }

    /// Shows the next waiting notification once the island is back at rest.
    private func showNextPendingNotification() {
        guard !pendingNotifications.isEmpty, canShowAlert, !isShowingNotification else { return }
        let next = pendingNotifications.removeFirst()
        showAlert(.notification(next), for: .seconds(settings.notificationDuration))
    }

    private func openFromHover() {
        chooseTabForOpening()
        transition(to: .expanded)
    }

    /// A module that needs the user wins; otherwise the last tab if it was recent, else the first.
    private func chooseTabForOpening() {
        if let preferred = preferredTabOnOpen?() {
            tab = preferred
            return
        }
        if Date().timeIntervalSince(closedAt) > Self.tabMemory || tab == .palette || !visibleTabs.contains(tab) {
            tab = visibleTabs.first ?? .home
        }
    }

    private func cancelPendingChanges() {
        hoverTask?.cancel()
        closeTask?.cancel()
        alertTask?.cancel()
    }

    private func activitiesChanged() {
        switch state {
        case .idle, .compact:
            transition(to: restingState)
        case .peek:
            // The peek size depends on whether there is an activity underneath.
            onLayoutChange?()
        case .alert, .expanded, .dropTarget:
            break
        }
    }

    private func transition(to newState: IslandState) {
        guard newState != state else { return }
        let old = size(for: state)
        let new = size(for: newState)
        isGrowing = new.width * new.height >= old.width * old.height
        if state == .expanded {
            closedAt = Date()
            wantsSearchFocus = false
        }
        let wasExpanded = state == .expanded
        state = newState
        onLayoutChange?()
        if wasExpanded != (newState == .expanded) {
            onExpandedChange?(newState == .expanded)
        }
        if newState == restingState && !pendingNotifications.isEmpty {
            Task { self.showNextPendingNotification() }
        }
    }
}
