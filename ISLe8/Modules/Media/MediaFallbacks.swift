import AppKit

/// Controls Spotify and Music through AppleScript when MediaRemote commands don't get through.
/// The first use asks for Automation permission.
enum PlayerScript {
    static func run(_ command: MediaCommand, on player: PlayerApp) {
        let verb = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .next: "next track"
        case .previous: player == .music ? "back track" : "previous track"
        case .advanceShuffle: player == .music ? "set shuffle enabled to not shuffle enabled" : "set shuffling to not shuffling"
        case .advanceRepeat: player == .music
            ? "if song repeat is off then set song repeat to all else set song repeat to off"
            : "set repeating to not repeating"
        }
        tell(player, verb)
    }

    static func seek(to seconds: TimeInterval, on player: PlayerApp) {
        tell(player, "set player position to \(seconds)")
    }

    /// osascript runs out of process, so a pending permission prompt never blocks the island.
    private static func tell(_ player: PlayerApp, _ statement: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"\(player.scriptingName)\" to \(statement)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

/// The last resort: press the keyboard's media keys. Works for any player but only once
/// ISLe8 has Accessibility permission, which it does not ask for in this phase.
enum MediaKeys {
    @discardableResult
    static func press(_ command: MediaCommand) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let key: Int = switch command {
        case .next: 17          // NX_KEYTYPE_NEXT
        case .previous: 18      // NX_KEYTYPE_PREVIOUS
        default: 16             // NX_KEYTYPE_PLAY
        }
        for isDown in [true, false] {
            let state = isDown ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (key << 16) | (state << 8),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        return true
    }
}
