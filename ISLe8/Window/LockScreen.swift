import AppKit
import SwiftUI

/// Reports when the screen locks and unlocks.
final class LockMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var isLocked = LockMonitor.currentlyLocked()
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            let observer = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.set(locked) }
            }
            observers.append(observer)
        }
    }

    private func set(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        onChange?(locked)
    }

    private static func currentlyLocked() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

/// The private window server calls that put a window above the lock screen. Nothing here is
/// public API: it can break with a macOS update, which is why the lock screen is optional.
enum SkyLight {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsToSpace = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// The level Notification Center uses on the lock screen; the lock screen itself is 300.
    private static let lockScreenNotificationLevel: Int32 = 400

    private struct Space {
        let connection: Int32
        let id: Int32
        let addWindows: AddWindowsToSpace
    }

    /// One space for the whole app, created on first use and shown permanently.
    private static let space: Space? = {
        guard let framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let mainConnection = dlsym(framework, "SLSMainConnectionID"),
              let create = dlsym(framework, "SLSSpaceCreate"),
              let setLevel = dlsym(framework, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(framework, "SLSShowSpaces"),
              let add = dlsym(framework, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else { return nil }
        let connection = unsafeBitCast(mainConnection, to: MainConnectionID.self)()
        let id = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, 0)
        _ = unsafeBitCast(setLevel, to: SpaceSetAbsoluteLevel.self)(connection, id, lockScreenNotificationLevel)
        _ = unsafeBitCast(show, to: ShowSpaces.self)(connection, [id] as CFArray)
        return Space(connection: connection, id: id, addWindows: unsafeBitCast(add, to: AddWindowsToSpace.self))
    }()

    static var isAvailable: Bool { space != nil }

    /// Moves an on-screen window into the space above the lock screen. Returns false if the
    /// API isn't there.
    @discardableResult
    static func moveAboveLockScreen(_ window: NSWindow) -> Bool {
        guard let space, window.windowNumber > 0 else { return false }
        // 7: take the window out of every kind of space it was in.
        _ = space.addWindows(space.connection, space.id, [window.windowNumber] as CFArray, 7)
        return true
    }
}

/// A second, separate window that sits above the lock screen. It is on screen only while
/// the Mac is locked; once unlocked it is removed entirely, so it can never get in the way
/// of the normal island or of clicks at the top of the screen.
final class LockScreenController {
    private static let width: CGFloat = 420
    /// Room for the media card and three notification cards.
    private static let cardAreaHeight: CGFloat = 340

    private let model: IslandModel
    private let panel = IslandPanel()
    private let hostingView: LockScreenHostingView
    private var transition = 0

    init?(model: IslandModel) {
        guard SkyLight.isAvailable else { return nil }
        self.model = model
        hostingView = LockScreenHostingView(rootView: LockScreenRootView(model: model))
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        panel.contentView = hostingView
        panel.level = NSWindow.Level(rawValue: Int(Int32.max - 2))
        panel.canBecomeVisibleWithoutLogin = true
        panel.alphaValue = 0
        if model.isLocked {
            update(locked: true)
        }
    }

    func update(locked: Bool) {
        transition += 1
        let current = transition
        if locked {
            reposition()
            panel.sharingType = model.settings.hideFromScreenCapture ? .none : .readOnly
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            // Ordering out loses the space, so the window moves up again on every lock.
            SkyLight.moveAboveLockScreen(panel)
            // No fade: with the display asleep an animation never advances and the window
            // would stay invisible. The system's own lock transition covers the change.
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.transition == current else { return }
                    self.panel.orderOut(nil)
                }
            }
        }
    }

    /// Shows the lock screen layout over the unlocked desktop while its position is being
    /// adjusted. It lets every click through, so it never gets in the way.
    func setPreview(_ visible: Bool) {
        guard !model.isLocked else { return }
        transition += 1
        if visible {
            reposition()
            panel.ignoresMouseEvents = true
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
            panel.ignoresMouseEvents = false
        }
    }

    /// From the top of the screen down to just past the cards below the clock.
    func reposition() {
        guard let geometry = model.geometry else { return }
        let screen = geometry.screenFrame
        let height = min(screen.height, LockScreenView.cardTop(in: screen, settings: model.settings) + Self.cardAreaHeight)
        panel.setFrame(CGRect(
            x: (geometry.notchMidX - Self.width / 2).rounded(),
            y: screen.maxY - height,
            width: Self.width,
            height: height
        ), display: true)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

final class LockScreenHostingView: NSHostingView<LockScreenRootView> {
    required init(rootView: LockScreenRootView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
