import AppKit

/// Swallows every key, modifier and media key while the keyboard is being wiped, as
/// CleanMyKeyboard does. The mouse and trackpad keep working, so the unlock button can be
/// clicked. Needs Accessibility permission; the tap goes away with the process, so a crash
/// can never leave the keyboard locked.
final class KeyboardLock {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isLocked: Bool { tap != nil }

    /// False without Accessibility permission.
    func lock() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }
        let keys: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, CGEventType(rawValue: 14)!] // 14: NX_SYSDEFINED
        let mask = keys.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                // macOS switches a tap off if it ever stalls; switch it straight back on.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let refcon {
                    let lock = Unmanaged<KeyboardLock>.fromOpaque(refcon).takeUnretainedValue()
                    MainActor.assumeIsolated { lock.reenable() }
                    return Unmanaged.passUnretained(event)
                }
                return nil
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

    func unlock() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
    }

    private func reenable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}
