import AppKit
import SwiftUI

/// A plain window for SettingsView. A SwiftUI Settings scene is awkward to open from an
/// app without a Dock icon, so the window is managed by hand.
final class SettingsWindowController {
    private let model: IslandModel
    private var window: NSWindow?

    init(model: IslandModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        // The same environment the island gets, so every settings tab can reach its module.
        let controller = NSHostingController(
            rootView: SettingsView()
                .environment(model)
                .environment(model.settings)
                .modifier(ModuleEnvironment(modules: model.modules))
        )
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "ISLe8 Ayarları")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
