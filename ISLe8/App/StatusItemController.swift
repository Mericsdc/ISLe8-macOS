import AppKit

/// The menu bar icon. ISLe8 has no Dock icon, so this is how you reach settings or quit,
/// unless it is turned off in Settings > General.
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings: SettingsStore
    private let onOpenSettings: () -> Void

    init(settings: SettingsStore, onOpenSettings: @escaping () -> Void) {
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        super.init()
        followVisibilitySetting()

        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "ISLe8")

        let menu = NSMenu()
        let settings = NSMenuItem(title: String(localized: "Ayarlar…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "ISLe8'den çık"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    private func followVisibilitySetting() {
        withObservationTracking {
            item.isVisible = settings.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor in self?.followVisibilitySetting() }
        }
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
