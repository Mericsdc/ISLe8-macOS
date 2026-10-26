import AppKit

/// The menu bar icon. ISLe8 has no Dock icon, so this is how you reach settings or quit.
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onOpenSettings: () -> Void

    init(onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        super.init()

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

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
