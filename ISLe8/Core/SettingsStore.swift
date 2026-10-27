import Foundation
import ServiceManagement

/// User preferences. Every change is written to UserDefaults right away.
@Observable
final class SettingsStore {
    enum OpenMode: String, CaseIterable {
        case hover
        case click
    }

    /// Which screen the island lives on.
    enum ScreenMode: String, CaseIterable {
        /// The built-in notch screen, or the main screen as a pill when there is none.
        case automatic
        /// The screen with the menu bar in System Settings > Displays.
        case primary
        /// Wherever you last clicked or brought a window to the front.
        case active
        /// The screen named in `screenName`, while it is connected.
        case named
    }

    /// How much Home shows: the full dashboard, a smaller one, or a single strip.
    enum HomeStyle: String, CaseIterable {
        case dashboard
        case compact
        case minimal
    }

    enum NotificationTiming: String, CaseIterable {
        case always
        case whenUnlocked
        case whenLocked
    }

    enum TemperatureUnit: String, CaseIterable {
        case celsius
        case fahrenheit
    }

    /// A global shortcut: a `kVK_…` key code and a Carbon modifier mask.
    struct Shortcut: Equatable {
        var keyCode: Int
        var modifiers: Int
        /// As shown in Settings, e.g. "⌃⌥V".
        var display: String

        fileprivate var stored: String { "\(keyCode):\(modifiers):\(display)" }

        fileprivate init(keyCode: Int, modifiers: Int, display: String) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.display = display
        }

        fileprivate init?(stored: String?) {
            let parts = stored?.split(separator: ":", maxSplits: 2).map(String.init) ?? []
            guard parts.count == 3, let key = Int(parts[0]), let modifiers = Int(parts[1]) else { return nil }
            self.init(keyCode: key, modifiers: modifiers, display: parts[2])
        }

        static func make(keyCode: Int, modifiers: Int, display: String) -> Shortcut {
            Shortcut(keyCode: keyCode, modifiers: modifiers, display: display)
        }
    }

    // Tabs, Home tiles and live activities, by id, in the user's order.
    static let allTabs = ["home", "shelf", "clipboard", "notes", "agents", "devices", "system"]
    /// Home's columns, left to right.
    static let allHomeTiles = ["calendar", "media", "weather", "timer"]
    static let allActivities = ["agents", "media", "timer", "system"]

    var openMode: OpenMode {
        didSet { defaults.set(openMode.rawValue, forKey: Key.openMode) }
    }
    /// How long the pointer has to rest on the island before it opens (hover mode).
    var openDelay: Double {
        didSet { defaults.set(openDelay, forKey: Key.openDelay) }
    }
    /// How long the open island waits after the pointer leaves before it closes.
    var closeDelay: Double {
        didSet { defaults.set(closeDelay, forKey: Key.closeDelay) }
    }
    var homeStyle: HomeStyle {
        didSet {
            defaults.set(homeStyle.rawValue, forKey: Key.homeStyle)
            onLayoutChange?()
        }
    }
    /// The island's size on screens without a notch (external monitors); 0 = by the
    /// screen's resolution.
    var externalScale: Double {
        didSet {
            defaults.set(externalScale, forKey: Key.externalScale)
            onLayoutChange?()
        }
    }
    var expandedWidth: Double {
        didSet {
            defaults.set(expandedWidth, forKey: Key.expandedWidth)
            onLayoutChange?()
        }
    }
    var showOnScreensWithoutNotch: Bool {
        didSet {
            defaults.set(showOnScreensWithoutNotch, forKey: Key.showOnScreensWithoutNotch)
            onLayoutChange?()
        }
    }
    var screenMode: ScreenMode {
        didSet {
            defaults.set(screenMode.rawValue, forKey: Key.screenMode)
            onLayoutChange?()
        }
    }
    var screenName: String {
        didSet {
            defaults.set(screenName, forKey: Key.screenName)
            onLayoutChange?()
        }
    }
    var showTrackChangeAlert: Bool {
        didSet { defaults.set(showTrackChangeAlert, forKey: Key.showTrackChangeAlert) }
    }
    var showVisualizer: Bool {
        didSet { defaults.set(showVisualizer, forKey: Key.showVisualizer) }
    }
    private(set) var launchAtLogin: Bool

    // MARK: Shelf

    /// Copy dropped files into ISLe8's own folder instead of pointing at the originals.
    var copyFilesToShelf: Bool {
        didSet { defaults.set(copyFilesToShelf, forKey: Key.copyFilesToShelf) }
    }
    /// Watch Downloads for files arriving by AirDrop, announce them and put them on the shelf.
    var showAirDropReceived: Bool {
        didSet {
            defaults.set(showAirDropReceived, forKey: Key.showAirDropReceived)
            notifyModules()
        }
    }

    // MARK: Clipboard

    var recordClipboard: Bool {
        didSet {
            defaults.set(recordClipboard, forKey: Key.recordClipboard)
            notifyModules()
        }
    }
    /// Unpinned items kept in the history.
    var clipboardLimit: Int {
        didSet { defaults.set(clipboardLimit, forKey: Key.clipboardLimit) }
    }
    var clipboardMaxAgeDays: Int {
        didSet { defaults.set(clipboardMaxAgeDays, forKey: Key.clipboardMaxAgeDays) }
    }
    /// Bundle IDs whose copies are never recorded.
    var clipboardExcludedApps: [String] {
        didSet { defaults.set(clipboardExcludedApps, forKey: Key.clipboardExcludedApps) }
    }

    // MARK: Notifications

    var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled)
            notifyModules()
        }
    }
    var notificationTiming: NotificationTiming {
        didSet { defaults.set(notificationTiming.rawValue, forKey: Key.notificationTiming) }
    }
    var respectFocus: Bool {
        didSet { defaults.set(respectFocus, forKey: Key.respectFocus) }
    }
    /// Seconds a notification banner stays up.
    var notificationDuration: Double {
        didSet { defaults.set(notificationDuration, forKey: Key.notificationDuration) }
    }
    var mutedNotificationApps: [String] {
        didSet { defaults.set(mutedNotificationApps, forKey: Key.mutedNotificationApps) }
    }
    /// Apps that recently sent notifications, newest first, for the mute list.
    var notificationSeenApps: [String] {
        didSet { defaults.set(notificationSeenApps, forKey: Key.notificationSeenApps) }
    }

    // MARK: Lock screen

    /// Shows the island on the lock screen through a private window server API.
    var lockScreenEnabled: Bool {
        didSet {
            defaults.set(lockScreenEnabled, forKey: Key.lockScreenEnabled)
            notifyModules()
        }
    }
    var lockScreenShowsMedia: Bool {
        didSet { defaults.set(lockScreenShowsMedia, forKey: Key.lockScreenShowsMedia) }
    }
    var lockScreenMediaControls: Bool {
        didSet { defaults.set(lockScreenMediaControls, forKey: Key.lockScreenMediaControls) }
    }
    var lockScreenShowsNotifications: Bool {
        didSet { defaults.set(lockScreenShowsNotifications, forKey: Key.lockScreenShowsNotifications) }
    }
    /// On the lock screen, show "Messages · 2 new notifications" instead of the text.
    var hideNotificationContentWhenLocked: Bool {
        didSet { defaults.set(hideNotificationContentWhenLocked, forKey: Key.hideNotificationContentWhenLocked) }
    }
    /// Where the lock screen cards start, as a fraction of the screen height from the top,
    /// so they can sit just below the system clock.
    var lockScreenCardPosition: Double {
        didSet { defaults.set(lockScreenCardPosition, forKey: Key.lockScreenCardPosition) }
    }

    // MARK: System

    var showVolumeHUD: Bool {
        didSet {
            defaults.set(showVolumeHUD, forKey: Key.showVolumeHUD)
            notifyModules()
        }
    }
    var showBrightnessHUD: Bool {
        didSet {
            defaults.set(showBrightnessHUD, forKey: Key.showBrightnessHUD)
            notifyModules()
        }
    }
    /// Take over the volume and brightness keys so the system HUD stays away.
    var replaceSystemHUD: Bool {
        didSet {
            defaults.set(replaceSystemHUD, forKey: Key.replaceSystemHUD)
            notifyModules()
        }
    }
    var showBatteryAlerts: Bool {
        didSet { defaults.set(showBatteryAlerts, forKey: Key.showBatteryAlerts) }
    }
    /// A banner when AirPods, a Magic Mouse and the like connect, with their batteries.
    var showDeviceConnectedAlert: Bool {
        didSet { defaults.set(showDeviceConnectedAlert, forKey: Key.showDeviceConnectedAlert) }
    }
    var showDeviceLowBatteryAlert: Bool {
        didSet { defaults.set(showDeviceLowBatteryAlert, forKey: Key.showDeviceLowBatteryAlert) }
    }
    var showDevicesChip: Bool {
        didSet { defaults.set(showDevicesChip, forKey: Key.showDevicesChip) }
    }
    /// iPhones and iPads that trust this Mac, read the way Finder reaches them. Off by default.
    var showAppleDevices: Bool {
        didSet {
            defaults.set(showAppleDevices, forKey: Key.showAppleDevices)
            notifyModules()
        }
    }

    // MARK: Widgets

    var showReminders: Bool {
        didSet {
            defaults.set(showReminders, forKey: Key.showReminders)
            notifyModules()
        }
    }
    /// A banner five minutes before a meeting starts.
    var meetingHeadsUp: Bool {
        didSet {
            defaults.set(meetingHeadsUp, forKey: Key.meetingHeadsUp)
            notifyModules()
        }
    }
    /// Empty means "the city of the Mac's time zone".
    var weatherCity: String {
        didSet { defaults.set(weatherCity, forKey: Key.weatherCity) }
    }
    var weatherLatitude: Double {
        didSet { defaults.set(weatherLatitude, forKey: Key.weatherLatitude) }
    }
    var weatherLongitude: Double {
        didSet { defaults.set(weatherLongitude, forKey: Key.weatherLongitude) }
    }
    var weatherUnit: TemperatureUnit {
        didSet { defaults.set(weatherUnit.rawValue, forKey: Key.weatherUnit) }
    }
    var timerSound: Bool {
        didSet { defaults.set(timerSound, forKey: Key.timerSound) }
    }
    var pomodoroWorkMinutes: Int {
        didSet { defaults.set(pomodoroWorkMinutes, forKey: Key.pomodoroWorkMinutes) }
    }
    var pomodoroBreakMinutes: Int {
        didSet { defaults.set(pomodoroBreakMinutes, forKey: Key.pomodoroBreakMinutes) }
    }

    // MARK: Appearance and layout

    var themeID: String {
        didSet { defaults.set(themeID, forKey: Key.themeID) }
    }
    /// Themes the user made or imported, kept as one JSON string.
    var customThemes: [IslandTheme] {
        didSet {
            let data = (try? JSONEncoder().encode(customThemes)) ?? Data("[]".utf8)
            defaults.set(String(decoding: data, as: UTF8.self), forKey: Key.customThemes)
        }
    }
    /// The presets, each as the user changed it if they did, then the user's own themes. A
    /// changed preset is kept among `customThemes` under the preset's own ID.
    var allThemes: [IslandTheme] {
        let presets = IslandTheme.presets.map { preset in customThemes.first { $0.id == preset.id } ?? preset }
        return presets + customThemes.filter { !$0.isPreset }
    }
    var theme: IslandTheme {
        allThemes.first { $0.id == themeID } ?? .notchBlack
    }
    /// 1 is normal; higher is snappier.
    var animationSpeed: Double {
        didSet { defaults.set(animationSpeed, forKey: Key.animationSpeed) }
    }
    /// Keep the island out of screenshots, recordings and screen sharing.
    var hideFromScreenCapture: Bool {
        didSet {
            defaults.set(hideFromScreenCapture, forKey: Key.hideFromScreenCapture)
            onLayoutChange?()
        }
    }
    var swipeToChangeTabs: Bool {
        didSet { defaults.set(swipeToChangeTabs, forKey: Key.swipeToChangeTabs) }
    }
    var tabOrder: [String] {
        didSet { defaults.set(tabOrder, forKey: Key.tabOrder) }
    }
    var hiddenTabs: [String] {
        didSet { defaults.set(hiddenTabs, forKey: Key.hiddenTabs) }
    }
    /// Home tiles shown, in order; two per row.
    var homeTiles: [String] {
        didSet {
            defaults.set(homeTiles, forKey: Key.homeTiles)
            onLayoutChange?()
        }
    }
    /// Which live activity gets the ears when several want them, most important first.
    var activityOrder: [String] {
        didSet { defaults.set(activityOrder, forKey: Key.activityOrder) }
    }
    /// The player that play opens when nothing is playing: a PlayerApp bundle ID, or empty
    /// for the one used last.
    var defaultPlayer: String {
        didSet { defaults.set(defaultPlayer, forKey: Key.defaultPlayer) }
    }
    /// Decorations on the open island on days celebrated worldwide.
    var showSeasonal: Bool {
        didSet { defaults.set(showSeasonal, forKey: Key.showSeasonal) }
    }
    /// An occasion picked in Settings to see its decoration now; not saved.
    var seasonalPreview: Occasion?
    /// A "LAN" chip in the header while the Mac is online through an Ethernet cable.
    var showNetworkChip: Bool {
        didSet { defaults.set(showNetworkChip, forKey: Key.showNetworkChip) }
    }
    /// The theme the island wears: the user's, or a special day's over it.
    var islandTheme: IslandTheme {
        activeOccasion.map { $0.theme(over: theme) } ?? theme
    }
    /// What the open island is decorated for right now.
    var activeOccasion: Occasion? {
        if let seasonalPreview { return seasonalPreview }
        return showSeasonal ? Occasion.current() : nil
    }
    /// The capsule in the menu bar. Without it, Settings opens from the island's gear or by
    /// opening ISLe8 again.
    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }
    var showBatteryChip: Bool {
        didSet { defaults.set(showBatteryChip, forKey: Key.showBatteryChip) }
    }
    var showKeepAwakeChip: Bool {
        didSet { defaults.set(showKeepAwakeChip, forKey: Key.showKeepAwakeChip) }
    }
    var showPrivacyChip: Bool {
        didSet { defaults.set(showPrivacyChip, forKey: Key.showPrivacyChip) }
    }

    // MARK: Shortcuts

    var clipboardShortcut: Shortcut {
        didSet {
            defaults.set(clipboardShortcut.stored, forKey: Key.clipboardShortcut)
            notifyModules()
        }
    }
    var paletteShortcut: Shortcut {
        didSet {
            defaults.set(paletteShortcut.stored, forKey: Key.paletteShortcut)
            notifyModules()
        }
    }

    // MARK: Agents

    var agentApprovalsOnIsland: Bool {
        didSet { defaults.set(agentApprovalsOnIsland, forKey: Key.agentApprovalsOnIsland) }
    }
    /// Seconds an approval waits on the island before the agent asks in its own window.
    var agentApprovalTimeout: Int {
        didSet { defaults.set(agentApprovalTimeout, forKey: Key.agentApprovalTimeout) }
    }
    var agentDoneAlert: Bool {
        didSet { defaults.set(agentDoneAlert, forKey: Key.agentDoneAlert) }
    }

    /// Called when a setting changes the island's size or the screen it sits on.
    @ObservationIgnored var onLayoutChange: (() -> Void)?
    @ObservationIgnored private var moduleObservers: [() -> Void] = []
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.openMode: OpenMode.hover.rawValue,
            Key.openDelay: 0.0,
            Key.closeDelay: 0.35,
            Key.expandedWidth: 820.0,
            Key.homeStyle: HomeStyle.dashboard.rawValue,
            Key.externalScale: 0.0,
            Key.showOnScreensWithoutNotch: true,
            Key.showTrackChangeAlert: true,
            Key.showVisualizer: true,
            Key.copyFilesToShelf: false,
            Key.showAirDropReceived: true,
            Key.recordClipboard: true,
            Key.clipboardLimit: 200,
            Key.clipboardMaxAgeDays: 30,
            Key.clipboardExcludedApps: [
                "com.1password.1password",
                "com.agilebits.onepassword7",
                "com.bitwarden.desktop",
                "com.apple.keychainaccess",
                "com.apple.Passwords",
            ],
            Key.notificationsEnabled: true,
            Key.notificationTiming: NotificationTiming.always.rawValue,
            Key.respectFocus: true,
            Key.notificationDuration: 4.0,
            Key.mutedNotificationApps: [String](),
            Key.notificationSeenApps: [String](),
            Key.lockScreenEnabled: true,
            Key.lockScreenShowsMedia: true,
            Key.lockScreenMediaControls: true,
            Key.lockScreenShowsNotifications: true,
            Key.hideNotificationContentWhenLocked: true,
            Key.lockScreenCardPosition: 0.30,
            Key.showVolumeHUD: true,
            Key.showBrightnessHUD: true,
            Key.replaceSystemHUD: false,
            Key.showBatteryAlerts: true,
            Key.showDeviceConnectedAlert: true,
            Key.showDeviceLowBatteryAlert: true,
            Key.showDevicesChip: true,
            Key.showReminders: false,
            Key.meetingHeadsUp: true,
            Key.weatherCity: "",
            Key.weatherLatitude: 0.0,
            Key.weatherLongitude: 0.0,
            Key.weatherUnit: TemperatureUnit.celsius.rawValue,
            Key.timerSound: true,
            Key.pomodoroWorkMinutes: 25,
            Key.pomodoroBreakMinutes: 5,
            Key.themeID: IslandTheme.notchBlack.id,
            Key.animationSpeed: 1.0,
            Key.hideFromScreenCapture: false,
            Key.swipeToChangeTabs: true,
            Key.tabOrder: Self.allTabs,
            Key.hiddenTabs: [String](),
            Key.homeTiles: ["calendar", "media", "weather"],
            Key.activityOrder: Self.allActivities,
            Key.showMenuBarIcon: true,
            Key.showSeasonal: true,
            Key.showNetworkChip: true,
            Key.showAppleDevices: false,
            Key.defaultPlayer: "",
            Key.showBatteryChip: true,
            Key.showKeepAwakeChip: true,
            Key.showPrivacyChip: true,
            // ⌃⌥V and ⌃⌥K; 9 and 40 are kVK_ANSI_V and kVK_ANSI_K, 6144 is control + option.
            Key.clipboardShortcut: "9:6144:⌃⌥V",
            Key.paletteShortcut: "40:6144:⌃⌥K",
            Key.agentApprovalsOnIsland: true,
            Key.agentApprovalTimeout: 90,
            Key.agentDoneAlert: true,
        ])
        openMode = OpenMode(rawValue: defaults.string(forKey: Key.openMode) ?? "") ?? .hover
        // Hover used to swell first and open 0.3 s later; it now opens at once. A delay still at
        // the old default goes back to the new one.
        if !defaults.bool(forKey: Key.hoverOpensDirectly) {
            defaults.set(true, forKey: Key.hoverOpensDirectly)
            if abs(defaults.double(forKey: Key.openDelay) - 0.3) < 0.001 {
                defaults.removeObject(forKey: Key.openDelay)
            }
        }
        openDelay = defaults.double(forKey: Key.openDelay)
        closeDelay = defaults.double(forKey: Key.closeDelay)
        // Home became three columns (calendar, media, weather), which need a wider island
        // than the old two-to-a-row tiles; the old tiles map onto the new columns.
        if !defaults.bool(forKey: Key.homeColumns) {
            defaults.set(true, forKey: Key.homeColumns)
            if defaults.double(forKey: Key.expandedWidth) < 760 {
                defaults.removeObject(forKey: Key.expandedWidth)
            }
            if let saved = defaults.stringArray(forKey: Key.homeTiles) {
                var columns = ["calendar", "media", "weather"]
                if saved.contains("timer") { columns.append("timer") }
                defaults.set(columns, forKey: Key.homeTiles)
            }
        }
        expandedWidth = defaults.double(forKey: Key.expandedWidth)
        homeStyle = HomeStyle(rawValue: defaults.string(forKey: Key.homeStyle) ?? "") ?? .dashboard
        externalScale = defaults.double(forKey: Key.externalScale)
        showOnScreensWithoutNotch = defaults.bool(forKey: Key.showOnScreensWithoutNotch)
        screenMode = ScreenMode(rawValue: defaults.string(forKey: Key.screenMode) ?? "") ?? .automatic
        screenName = defaults.string(forKey: Key.screenName) ?? ""
        showTrackChangeAlert = defaults.bool(forKey: Key.showTrackChangeAlert)
        showVisualizer = defaults.bool(forKey: Key.showVisualizer)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        copyFilesToShelf = defaults.bool(forKey: Key.copyFilesToShelf)
        showAirDropReceived = defaults.bool(forKey: Key.showAirDropReceived)
        recordClipboard = defaults.bool(forKey: Key.recordClipboard)
        clipboardLimit = defaults.integer(forKey: Key.clipboardLimit)
        clipboardMaxAgeDays = defaults.integer(forKey: Key.clipboardMaxAgeDays)
        clipboardExcludedApps = defaults.stringArray(forKey: Key.clipboardExcludedApps) ?? []
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        notificationTiming = NotificationTiming(rawValue: defaults.string(forKey: Key.notificationTiming) ?? "") ?? .always
        respectFocus = defaults.bool(forKey: Key.respectFocus)
        notificationDuration = defaults.double(forKey: Key.notificationDuration)
        mutedNotificationApps = defaults.stringArray(forKey: Key.mutedNotificationApps) ?? []
        notificationSeenApps = defaults.stringArray(forKey: Key.notificationSeenApps) ?? []
        lockScreenEnabled = defaults.bool(forKey: Key.lockScreenEnabled)
        lockScreenShowsMedia = defaults.bool(forKey: Key.lockScreenShowsMedia)
        lockScreenMediaControls = defaults.bool(forKey: Key.lockScreenMediaControls)
        lockScreenShowsNotifications = defaults.bool(forKey: Key.lockScreenShowsNotifications)
        hideNotificationContentWhenLocked = defaults.bool(forKey: Key.hideNotificationContentWhenLocked)
        lockScreenCardPosition = defaults.double(forKey: Key.lockScreenCardPosition)
        showVolumeHUD = defaults.bool(forKey: Key.showVolumeHUD)
        showBrightnessHUD = defaults.bool(forKey: Key.showBrightnessHUD)
        replaceSystemHUD = defaults.bool(forKey: Key.replaceSystemHUD)
        showBatteryAlerts = defaults.bool(forKey: Key.showBatteryAlerts)
        showDeviceConnectedAlert = defaults.bool(forKey: Key.showDeviceConnectedAlert)
        showDeviceLowBatteryAlert = defaults.bool(forKey: Key.showDeviceLowBatteryAlert)
        showDevicesChip = defaults.bool(forKey: Key.showDevicesChip)
        showReminders = defaults.bool(forKey: Key.showReminders)
        meetingHeadsUp = defaults.bool(forKey: Key.meetingHeadsUp)
        weatherCity = defaults.string(forKey: Key.weatherCity) ?? ""
        weatherLatitude = defaults.double(forKey: Key.weatherLatitude)
        weatherLongitude = defaults.double(forKey: Key.weatherLongitude)
        weatherUnit = TemperatureUnit(rawValue: defaults.string(forKey: Key.weatherUnit) ?? "") ?? .celsius
        timerSound = defaults.bool(forKey: Key.timerSound)
        pomodoroWorkMinutes = defaults.integer(forKey: Key.pomodoroWorkMinutes)
        pomodoroBreakMinutes = defaults.integer(forKey: Key.pomodoroBreakMinutes)
        customThemes = defaults.string(forKey: Key.customThemes)
            .flatMap { try? JSONDecoder().decode([IslandTheme].self, from: Data($0.utf8)) } ?? []
        // Before themes had ids, the choice was "black", "glass" or "artwork".
        if let legacy = defaults.string(forKey: Key.legacyTheme) {
            defaults.removeObject(forKey: Key.legacyTheme)
            defaults.set(legacy == "black" ? IslandTheme.notchBlack.id : legacy, forKey: Key.themeID)
        }
        themeID = defaults.string(forKey: Key.themeID) ?? IslandTheme.notchBlack.id
        animationSpeed = defaults.double(forKey: Key.animationSpeed)
        hideFromScreenCapture = defaults.bool(forKey: Key.hideFromScreenCapture)
        swipeToChangeTabs = defaults.bool(forKey: Key.swipeToChangeTabs)
        tabOrder = Self.complete(defaults.stringArray(forKey: Key.tabOrder), with: Self.allTabs)
        hiddenTabs = defaults.stringArray(forKey: Key.hiddenTabs) ?? []
        homeTiles = (defaults.stringArray(forKey: Key.homeTiles) ?? []).filter(Self.allHomeTiles.contains)
        activityOrder = Self.complete(defaults.stringArray(forKey: Key.activityOrder), with: Self.allActivities)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        showSeasonal = defaults.bool(forKey: Key.showSeasonal)
        showNetworkChip = defaults.bool(forKey: Key.showNetworkChip)
        showAppleDevices = defaults.bool(forKey: Key.showAppleDevices)
        defaultPlayer = defaults.string(forKey: Key.defaultPlayer) ?? ""
        showBatteryChip = defaults.bool(forKey: Key.showBatteryChip)
        showKeepAwakeChip = defaults.bool(forKey: Key.showKeepAwakeChip)
        showPrivacyChip = defaults.bool(forKey: Key.showPrivacyChip)
        clipboardShortcut = Shortcut(stored: defaults.string(forKey: Key.clipboardShortcut))
            ?? Shortcut(keyCode: 9, modifiers: 6144, display: "⌃⌥V")
        paletteShortcut = Shortcut(stored: defaults.string(forKey: Key.paletteShortcut))
            ?? Shortcut(keyCode: 40, modifiers: 6144, display: "⌃⌥K")
        agentApprovalsOnIsland = defaults.bool(forKey: Key.agentApprovalsOnIsland)
        agentApprovalTimeout = defaults.integer(forKey: Key.agentApprovalTimeout)
        agentDoneAlert = defaults.bool(forKey: Key.agentDoneAlert)
    }

    /// The saved order, with anything new since it was saved added at the end.
    private static func complete(_ saved: [String]?, with all: [String]) -> [String] {
        let kept = (saved ?? []).filter(all.contains)
        return kept + all.filter { !kept.contains($0) }
    }

    // MARK: Backup

    /// Every ISLe8 setting as JSON, for moving to another Mac or keeping a copy.
    func exportJSON() throws -> Data {
        let domain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.lrxe8.isle8") ?? [:]
        let portable = domain.filter { JSONSerialization.isValidJSONObject([$0.value]) && !$0.key.hasPrefix("NS") }
        return try JSONSerialization.data(withJSONObject: portable, options: [.prettyPrinted, .sortedKeys])
    }

    /// Replaces every setting with the file's. Takes effect after a relaunch.
    func importJSON(_ data: Data) throws {
        guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defaults.setPersistentDomain(values, forName: Bundle.main.bundleIdentifier ?? "com.lrxe8.isle8")
    }

    /// Lets a module re-read its settings whenever one that starts or stops work changes.
    func onModuleSettingsChange(_ handler: @escaping () -> Void) {
        moduleObservers.append(handler)
    }

    private func notifyModules() {
        moduleObservers.forEach { $0() }
    }

    /// The app's language: "" follows the system, otherwise "tr" or "en". macOS reads it from
    /// AppleLanguages in ISLe8's own defaults, so it applies from the next launch.
    var language: String {
        let own = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        return (own?["AppleLanguages"] as? [String])?.first ?? ""
    }

    func setLanguage(_ code: String) {
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("ISLe8: could not change the login item: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private enum Key {
        static let openMode = "openMode"
        static let openDelay = "openDelay"
        static let hoverOpensDirectly = "hoverOpensDirectly"
        static let closeDelay = "closeDelay"
        static let expandedWidth = "expandedWidth"
        static let homeColumns = "homeColumns"
        static let homeStyle = "homeStyle"
        static let externalScale = "externalScale"
        static let showOnScreensWithoutNotch = "showOnScreensWithoutNotch"
        static let screenMode = "screenMode"
        static let screenName = "screenName"
        static let showTrackChangeAlert = "showTrackChangeAlert"
        static let showVisualizer = "showVisualizer"
        static let copyFilesToShelf = "copyFilesToShelf"
        static let showAirDropReceived = "showAirDropReceived"
        static let recordClipboard = "recordClipboard"
        static let clipboardLimit = "clipboardLimit"
        static let clipboardMaxAgeDays = "clipboardMaxAgeDays"
        static let clipboardExcludedApps = "clipboardExcludedApps"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationTiming = "notificationTiming"
        static let respectFocus = "respectFocus"
        static let notificationDuration = "notificationDuration"
        static let mutedNotificationApps = "mutedNotificationApps"
        static let notificationSeenApps = "notificationSeenApps"
        static let lockScreenEnabled = "lockScreenEnabled"
        static let lockScreenShowsMedia = "lockScreenShowsMedia"
        static let lockScreenMediaControls = "lockScreenMediaControls"
        static let lockScreenShowsNotifications = "lockScreenShowsNotifications"
        static let hideNotificationContentWhenLocked = "hideNotificationContentWhenLocked"
        static let lockScreenCardPosition = "lockScreenCardPosition"
        static let showVolumeHUD = "showVolumeHUD"
        static let showBrightnessHUD = "showBrightnessHUD"
        static let replaceSystemHUD = "replaceSystemHUD"
        static let showBatteryAlerts = "showBatteryAlerts"
        static let showDeviceConnectedAlert = "showDeviceConnectedAlert"
        static let showDeviceLowBatteryAlert = "showDeviceLowBatteryAlert"
        static let showDevicesChip = "showDevicesChip"
        static let showReminders = "showReminders"
        static let meetingHeadsUp = "meetingHeadsUp"
        static let weatherCity = "weatherCity"
        static let weatherLatitude = "weatherLatitude"
        static let weatherLongitude = "weatherLongitude"
        static let weatherUnit = "weatherUnit"
        static let timerSound = "timerSound"
        static let pomodoroWorkMinutes = "pomodoroWorkMinutes"
        static let pomodoroBreakMinutes = "pomodoroBreakMinutes"
        static let legacyTheme = "theme"
        static let themeID = "themeID"
        static let customThemes = "customThemes"
        static let animationSpeed = "animationSpeed"
        static let hideFromScreenCapture = "hideFromScreenCapture"
        static let swipeToChangeTabs = "swipeToChangeTabs"
        static let tabOrder = "tabOrder"
        static let hiddenTabs = "hiddenTabs"
        static let homeTiles = "homeTiles"
        static let activityOrder = "activityOrder"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showSeasonal = "showSeasonal"
        static let showNetworkChip = "showNetworkChip"
        static let showAppleDevices = "showAppleDevices"
        static let defaultPlayer = "defaultPlayer"
        static let showBatteryChip = "showBatteryChip"
        static let showKeepAwakeChip = "showKeepAwakeChip"
        static let showPrivacyChip = "showPrivacyChip"
        static let clipboardShortcut = "clipboardShortcut"
        static let paletteShortcut = "paletteShortcut"
        static let agentApprovalsOnIsland = "agentApprovalsOnIsland"
        static let agentApprovalTimeout = "agentApprovalTimeout"
        static let agentDoneAlert = "agentDoneAlert"
    }
}
