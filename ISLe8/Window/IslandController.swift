import AppKit

/// Owns the island panel and keeps it over the notch.
///
/// The window has a fixed size, room for the biggest the island gets, and the island grows
/// and shrinks inside it. Resizing the window during an animation made SwiftUI animate the
/// container too, so the island floated in the middle of the window instead of growing out
/// of the notch. Clicks on the window's transparent part reach the apps underneath, and
/// hover only counts over the island itself.
final class IslandController {
    private let model: IslandModel
    private let panel = IslandPanel()
    private let hostingView: IslandHostingView
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    /// The screen last clicked on or holding the window last brought to the front, for the
    /// "active screen" setting.
    private var activeScreen: CGDirectDisplayID?
    private var clickMonitor: Any?
    private var scrollMonitor: Any?
    /// Horizontal travel of the current two-finger swipe, and whether it already switched tabs.
    private var swipeDistance: CGFloat = 0
    private var swipeHandled = false

    init(model: IslandModel) {
        self.model = model
        hostingView = IslandHostingView(rootView: IslandRootView(model: model))
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        hostingView.onHoverChange = { [weak model] inside in model?.setHovering(inside) }
        panel.contentView = hostingView

        model.onLayoutChange = { [weak self] in self?.layout() }
        model.onRequestKeyboard = { [weak self] in self?.panel.makeKey() }
        model.settings.onLayoutChange = { [weak self] in self?.updateScreen() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateScreen() }
        }
        // Clicks inside ISLe8 never reach a global monitor, so this only sees clicks elsewhere.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.clickedOutside()
                self?.followActiveScreen(ScreenLocator.screen(containing: NSEvent.mouseLocation))
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                MainActor.assumeIsolated {
                    guard let self, self.model.settings.screenMode == .active, let pid else { return }
                    self.followActiveScreen(ScreenLocator.screenOfFrontWindow(pid: pid))
                }
            },
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.followActiveScreen(ScreenLocator.screen(containing: NSEvent.mouseLocation))
                }
            },
        ]
        // Only sees scrolls inside ISLe8's own windows; the event always goes on unchanged.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.trackSwipe(event) }
            return event
        }

        updateScreen()
    }

    /// Two fingers sideways on the open island switch tabs. On the shelf, whose files scroll
    /// sideways themselves, only the header row takes the gesture.
    private func trackSwipe(_ event: NSEvent) {
        guard model.settings.swipeToChangeTabs, model.state == .expanded, event.window === panel else { return }
        switch event.phase {
        case .began:
            swipeDistance = 0
            swipeHandled = false
        case .changed:
            guard !swipeHandled else { return }
            if model.tab == .shelf || model.tab == .clipboard || model.tab == .palette {
                // The header row or the dock; the window's top edge is the island's.
                let top = panel.frame.height
                let island = model.size(for: .expanded).height * model.scale
                let y = event.locationInWindow.y
                let inHeader = y > top - (model.geometry?.notchSize.height ?? 32)
                let inDock = y < top - island + model.bottomSpace(for: model.tab)
                guard inHeader || inDock else { return }
            }
            swipeDistance += event.scrollingDeltaX
            if abs(swipeDistance) > 60 && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                swipeHandled = true
                model.selectAdjacentTab(swipeDistance < 0 ? 1 : -1)
            }
        default:
            break
        }
    }

    /// Moves the island to `screen` when it follows the active screen. Clicks on the island
    /// itself never get here, so it doesn't jump away from under the pointer.
    private func followActiveScreen(_ screen: NSScreen?) {
        guard model.settings.screenMode == .active, let id = screen?.displayID, id != activeScreen else { return }
        activeScreen = id
        updateScreen()
    }

    private func updateScreen() {
        panel.sharingType = model.settings.hideFromScreenCapture ? .none : .readOnly
        let geometry = ScreenLocator.islandGeometry(settings: model.settings, activeScreen: activeScreen)
        model.setGeometry(geometry)
        layout()
        if geometry == nil {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func layout() {
        if model.state != .expanded {
            panel.giveUpKeyboard()
        }
        guard let geometry = model.geometry else { return }
        // Changes only with the screen or the width setting, never during an animation.
        setFrame(model.canvasSize, in: geometry)
        let scale = model.scale
        let size = model.size(for: model.state)
        hostingView.setIslandSize(CGSize(width: size.width * scale, height: size.height * scale), staysOpen: model.state == .expanded)
        // After the current layout pass, so a hover change doesn't re-enter it.
        Task { [weak self] in self?.hostingView.resyncHover() }
    }

    private func setFrame(_ size: CGSize, in geometry: NotchGeometry) {
        let frame = CGRect(
            x: (geometry.notchMidX - size.width / 2).rounded(),
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }
}
