import AppKit
import SwiftUI

/// A borderless, transparent panel that sits above the menu bar on every Space and never
/// activates ISLe8. It takes the keyboard only when a text field inside needs it.
final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Not a floating panel: that would reset the level below the menu bar.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // AppKit normally pushes windows out from under the menu bar; the island belongs there.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Hands the keyboard back to the app you were using.
    func giveUpKeyboard() {
        guard isKeyWindow else { return }
        orderOut(nil)
        orderFrontRegardless()
    }
}

/// Hosts the SwiftUI island and reports when the pointer enters or leaves it.
final class IslandHostingView: NSHostingView<IslandRootView> {
    var onHoverChange: ((Bool) -> Void)?
    /// The island's size on screen. The view is bigger; the island sits at its top centre,
    /// and only that part counts for hover.
    private(set) var islandSize: CGSize = .zero
    /// When the open island gets shorter (minimal Home after a taller tab), the pointer that
    /// clicked the dock is suddenly below it. Until it moves into the new outline, the old
    /// one still counts, so the island doesn't close under it.
    private var slack: CGRect?
    private var hoverAreas: [NSTrackingArea] = []
    private var isPointerInside = false

    required init(rootView: IslandRootView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // The island lives in a panel that is rarely key, so clicks must work on the first try.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setIslandSize(_ size: CGSize, staysOpen: Bool) {
        guard size != islandSize else { return }
        let old = islandRect
        islandSize = size
        if staysOpen && isPointerInside && size.height < old.height {
            slack = old
        } else if !staysOpen {
            slack = nil
        }
        installTrackingAreas(assumeInside: isPointerInside)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        installTrackingAreas(assumeInside: isPointerInside)
    }

    // AppKit sends stray enter and exit events while the tracking area is being replaced,
    // sometimes several in the same millisecond and even with the pointer elsewhere. Each
    // one is checked against where the pointer really is.
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setPointerInside(pointerIsOverIsland)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setPointerInside(pointerIsOverIsland)
    }

    private var pointerIsOverIsland: Bool {
        guard let window else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if islandRect.contains(point) {
            // Back inside the real outline: the old one no longer counts.
            if slack != nil {
                slack = nil
                installTrackingAreas(assumeInside: true)
            }
            return true
        }
        if let slack, slack.contains(point) { return true }
        slack = nil
        return false
    }

    /// AppKit sends no enter or exit events during a drag, or when the window moves under a
    /// still pointer. Call this after the window changes to catch up.
    func resyncHover() {
        let inside = pointerIsOverIsland
        installTrackingAreas(assumeInside: inside)
        setPointerInside(inside)
    }

    private var islandRect: CGRect {
        CGRect(
            x: (bounds.width - islandSize.width) / 2,
            y: isFlipped ? 0 : bounds.height - islandSize.height,
            width: islandSize.width,
            height: islandSize.height
        )
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        onHoverChange?(inside)
    }

    /// One area for the island; with slack, a second for the old outline, so leaving it and
    /// entering the island both report.
    private func installTrackingAreas(assumeInside: Bool) {
        hoverAreas.forEach(removeTrackingArea)
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        if assumeInside {
            options.insert(.assumeInside)
        }
        hoverAreas = [islandRect, slack].compactMap { $0 }.map { rect in
            let area = NSTrackingArea(rect: rect, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            return area
        }
    }
}
