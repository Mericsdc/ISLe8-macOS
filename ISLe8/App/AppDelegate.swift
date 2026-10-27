import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: IslandModel?
    private var island: IslandController?
    private var lockScreen: LockScreenController?
    private let lockMonitor = LockMonitor()
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var clipboardHotKey: HotKey?
    private var paletteHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A write to a bridge process that just died must not take the app down with it.
        signal(SIGPIPE, SIG_IGN)

        let folder = Self.supportFolder()
        let settings = SettingsStore()
        let media = MediaModule(service: NowPlayingService())
        let shelf = ShelfModule(settings: settings, store: ShelfStore(folder: folder))
        let clipboard = ClipboardModule(service: ClipboardService(settings: settings, folder: folder))
        let notifications = NotificationModule(settings: settings, folder: folder)
        let system = SystemModule(settings: settings)
        let hud = HUDModule(settings: settings)
        let calendar = CalendarModule(settings: settings)
        let weather = WeatherModule(settings: settings)
        let timer = TimerModule(settings: settings)
        let agents = AgentsModule(settings: settings)
        let usage = UsageModule()
        let devices = DevicesModule(settings: settings)
        let notes = NotesModule(folder: folder)
        var modules: [any IslandModule] = [media, shelf, clipboard, notifications, system, hud, calendar, weather, timer, agents, usage, devices, notes]
        let palette = PaletteModule(modules: modules)
        modules.append(palette)
        let model = IslandModel(settings: settings, modules: modules)
        palette.attach(to: model)
        let settingsWindow = SettingsWindowController(model: model)

        model.onOpenSettings = { settingsWindow.show() }
        media.onTrackChange = { [weak model] in
            guard settings.showTrackChangeAlert else { return }
            model?.showAlert(.nowPlaying)
        }
        shelf.islandGeometry = { [weak model] in model?.geometry }
        shelf.onFileDragNearIsland = { [weak model] near in model?.setFileDragNearby(near) }
        shelf.onAirDropReceived = { [weak model] count in
            model?.showAlert(.airDropReceived(count: count), for: .seconds(3))
        }
        notifications.onShow = { [weak model] item in model?.showNotification(item) }
        notifications.isLocked = { [weak model] in model?.isLocked ?? false }
        hud.onHUD = { [weak model] value in model?.showHUD(value) }
        let keyboardLockWindow = KeyboardLockWindow(system: system, settings: settings)
        system.onKeyboardLockChange = { locked in
            locked ? keyboardLockWindow.show() : keyboardLockWindow.hide()
        }
        system.onBatteryEvent = { [weak model] event in
            model?.showAlert(.battery(event), for: .seconds(3))
        }
        system.onWiredChange = { [weak model] connected in
            guard settings.showNetworkChip else { return }
            model?.showAlert(.wired(connected), for: .seconds(3))
        }
        calendar.onMeetingSoon = { [weak model] item in
            model?.showAlert(.meeting(item), for: .seconds(10))
        }
        timer.onEvent = { [weak model] event in
            model?.showAlert(.timer(event), for: .seconds(4))
        }
        agents.onApprovalRequested = { [weak model] approval in
            model?.showAlert(.approval(approval), for: .seconds(15))
        }
        agents.onSessionFinished = { [weak model] session in
            model?.showAlert(.agentDone(session), for: .seconds(4))
        }
        model.preferredTabOnOpen = { agents.needsAttention ? .agents : nil }
        usage.onLimitWarning = { [weak model] snapshot, window in
            model?.showAlert(.usageLimit(snapshot, window), for: .seconds(6))
        }
        // Limits refresh faster and the adapter's watts are read only while the island is open.
        model.onExpandedChange = { open in
            usage.setVisible(open)
            devices.setVisible(open)
        }
        devices.onConnected = { [weak model] device in
            guard let model, model.settings.showDeviceConnectedAlert else { return }
            model.showAlert(.deviceConnected(device), for: .seconds(4))
        }
        devices.onLowBattery = { [weak model] device in
            guard let model, model.settings.showDeviceLowBatteryAlert else { return }
            model.showAlert(.deviceLowBattery(device), for: .seconds(5))
        }
        agents.onDevicesQuery = {
            // The answer is what was last read; the next one will be fresh.
            defer { devices.refresh() }
            return devices.devices.map { DevicesChip.summary($0) }
        }
        agents.onIslandCommand = { [weak model] action, tab in
            guard let model else { return }
            if action == "close" {
                model.close()
            } else if let tab = tab.flatMap(IslandTab.init(rawValue:)) {
                model.open(tab)
            } else {
                model.open()
            }
        }

        island = IslandController(model: model)
        statusItem = StatusItemController(settings: settings, onOpenSettings: { settingsWindow.show() })
        self.model = model
        self.settingsWindow = settingsWindow
        registerHotKeys()
        settings.onModuleSettingsChange { [weak self] in self?.registerHotKeys() }

        model.setLocked(lockMonitor.isLocked)
        lockMonitor.onChange = { [weak self, weak model] locked in
            model?.setLocked(locked)
            notifications.lockChanged(locked)
            self?.lockScreen?.update(locked: locked)
        }
        lockMonitor.start()
        model.onLockScreenPreviewChange = { [weak self] visible in
            self?.lockScreen?.setPreview(visible)
        }
        settings.onModuleSettingsChange { [weak self] in self?.applyLockScreenSetting() }
        applyLockScreenSetting()

        model.modules.forEach { $0.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.modules.forEach { $0.stop() }
    }

    /// Opening ISLe8 again from Finder or Launchpad while it runs shows Settings, as there is
    /// no window or Dock icon to click.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.openSettings()
        return false
    }

    /// Re-registered whenever a shortcut changes in Settings.
    private func registerHotKeys() {
        guard let model else { return }
        let settings = model.settings
        clipboardHotKey?.unregister()
        paletteHotKey?.unregister()
        clipboardHotKey = HotKey(keyCode: settings.clipboardShortcut.keyCode, modifiers: settings.clipboardShortcut.modifiers) { [weak model] in
            model?.toggleClipboardFromShortcut()
        }
        paletteHotKey = HotKey(keyCode: settings.paletteShortcut.keyCode, modifiers: settings.paletteShortcut.modifiers) { [weak model] in
            model?.togglePaletteFromShortcut()
        }
    }

    /// The lock screen window exists only while the feature is on.
    private func applyLockScreenSetting() {
        guard let model else { return }
        if model.settings.lockScreenEnabled {
            if lockScreen == nil {
                lockScreen = LockScreenController(model: model)
            }
        } else {
            lockScreen?.close()
            lockScreen = nil
        }
    }

    /// ~/Library/Application Support/ISLe8, where the shelf and clipboard history live.
    private static func supportFolder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appending(path: "ISLe8", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
