import AppKit

/// Catches the volume and brightness keys before macOS does, so ISLe8 can apply them and
/// show its own HUD instead of the system one. Needs Accessibility permission. If ISLe8
/// declines a key (for example an output without volume control), the key goes on to macOS.
final class MediaKeyTap {
    enum Key {
        case volumeUp
        case volumeDown
        case mute
        case brightnessUp
        case brightnessDown
    }

    /// Return true if the key was handled and must not reach macOS.
    var onKey: ((_ key: Key, _ isFineStep: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Keys whose key-down was handled; their key-up is swallowed too.
    private var swallowed: Set<Int> = []

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }
        let systemDefined = CGEventMask(1 << 14) // NX_SYSDEFINED
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: systemDefined,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { tap.handle(type, event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        swallowed.removeAll()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        // macOS switches a tap off if it ever stalls; switch it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }
        guard type.rawValue == 14, let system = NSEvent(cgEvent: event), system.subtype.rawValue == 8 else {
            return false
        }
        let code = (system.data1 & 0xFFFF_0000) >> 16
        let isDown = ((system.data1 & 0xFF00) >> 8) == 0xA
        let key: Key? = switch code {
        case 0: .volumeUp           // NX_KEYTYPE_SOUND_UP
        case 1: .volumeDown         // NX_KEYTYPE_SOUND_DOWN
        case 7: .mute               // NX_KEYTYPE_MUTE
        case 2: .brightnessUp       // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: .brightnessDown     // NX_KEYTYPE_BRIGHTNESS_DOWN
        default: nil
        }
        guard let key else { return false }
        guard isDown else {
            return swallowed.remove(code) != nil
        }
        // ⌥⇧ with a key means a quarter step, as in macOS.
        let isFineStep = event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift)
        guard onKey?(key, isFineStep) == true else { return false }
        swallowed.insert(code)
        return true
    }
}
