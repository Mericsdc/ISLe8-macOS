import AppKit

/// Finds the screen the island belongs on and the size of its notch.
enum ScreenLocator {
    /// The screen chosen in Settings > General. `activeScreen` is the one the user last
    /// worked on, for the "active screen" choice. When the chosen screen isn't connected, the
    /// island falls back to the automatic choice.
    static func islandGeometry(settings: SettingsStore, activeScreen: CGDirectDisplayID?) -> NotchGeometry? {
        let chosen: NSScreen? = switch settings.screenMode {
        case .automatic: nil
        case .primary: NSScreen.screens.first
        case .active: NSScreen.screens.first { $0.displayID == activeScreen } ?? screen(containing: NSEvent.mouseLocation)
        case .named: NSScreen.screens.first { $0.localizedName == settings.screenName }
        }
        if let chosen {
            return geometry(of: chosen)
        }
        // The built-in notch screen when there is one. Otherwise the main screen, where the
        // island shows as a pill, if the user allows that.
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let geometry = notchGeometry(of: screen) {
            return geometry
        }
        guard settings.showOnScreensWithoutNotch, let screen = NSScreen.screens.first else {
            return nil
        }
        return pillGeometry(of: screen)
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    /// The screen holding the frontmost window of the app that is now in front, or nil when
    /// it has no window on screen.
    static func screenOfFrontWindow(pid: pid_t) -> NSScreen? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return nil }
        // Front to back; layer 0 is ordinary app windows.
        let window = windows.first {
            $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0
        }
        guard let bounds = window?[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
        // Window bounds count down from the top of the primary screen; AppKit counts up.
        return screen(containing: CGPoint(x: rect.midX, y: primary.frame.maxY - rect.midY))
    }

    private static func geometry(of screen: NSScreen) -> NotchGeometry {
        notchGeometry(of: screen) ?? pillGeometry(of: screen)
    }

    private static func notchGeometry(of screen: NSScreen) -> NotchGeometry? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return nil
        }
        // The notch is whatever the two menu bar areas beside it leave over.
        let width = screen.frame.width - left.width - right.width
        return NotchGeometry(
            screenFrame: screen.frame,
            notchMidX: screen.frame.minX + left.width + width / 2,
            notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
            hasNotch: true
        )
    }

    private static func pillGeometry(of screen: NSScreen) -> NotchGeometry {
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return NotchGeometry(
            screenFrame: screen.frame,
            notchMidX: screen.frame.midX,
            notchSize: CGSize(width: 180, height: menuBarHeight),
            hasNotch: false,
            autoScale: autoScale(for: screen)
        )
    }

    /// The more points a screen has, the smaller everything on it looks, so the island is
    /// drawn larger there: 1080p and 4K at "looks like 1080p" stay at 1, 2K (1440p) and 4K
    /// at "looks like 1440p" get 1.15, 4K at full resolution 1.3. Screens drawn at 1x only
    /// grow at 4K, where the island would otherwise be tiny.
    private static func autoScale(for screen: NSScreen) -> CGFloat {
        let width = screen.frame.width
        if screen.backingScaleFactor >= 2 {
            switch width {
            case ..<2200: return 1
            case ..<3000: return 1.15
            default: return 1.3
            }
        }
        return width >= 3400 ? 1.25 : 1
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
