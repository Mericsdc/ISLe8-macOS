import SwiftUI

/// What a volume or brightness HUD shows.
struct HUDValue: Equatable {
    enum Kind {
        case volume
        case brightness
    }

    var kind: Kind
    var level: Double
    var isMuted = false
}

/// Volume and brightness HUDs in the ears. By default they appear next to the system's own
/// HUD; with "replace system HUD" on, ISLe8 takes over the keys and the system HUD stays away.
@Observable
final class HUDModule: IslandModule {
    let id = "hud"
    var activity: LiveActivity? { nil }
    /// Whether the key tap is actually running (it needs Accessibility permission).
    private(set) var isReplacingSystemHUD = false
    /// The output volume, 0…1 (0 when muted), for the slider on the open island.
    private(set) var outputVolume: Double?

    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored var onHUD: ((HUDValue) -> Void)?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let volume = VolumeMonitor()
    @ObservationIgnored private let brightness = BrightnessMonitor()
    @ObservationIgnored private let keys = MediaKeyTap()
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var lastVolume: (level: Float, muted: Bool)?
    /// Brightness at the start of the current burst of changes.
    @ObservationIgnored private var brightnessBaseline: Float?
    @ObservationIgnored private var lastBrightnessChange = Date.distantPast
    @ObservationIgnored private var lastBrightnessHUD = Date.distantPast

    private static let step: Float = 1 / 16
    private static let fineStep: Float = 1 / 64

    init(settings: SettingsStore) {
        self.settings = settings
        volume.onChange = { [weak self] level, muted in self?.volumeChanged(level, muted) }
        brightness.onChange = { [weak self] value in self?.brightnessChanged(value) }
        keys.onKey = { [weak self] key, fine in self?.handleKey(key, fine: fine) ?? false }
        settings.onModuleSettingsChange { [weak self] in self?.applySettings() }
    }

    func start() {
        isStarted = true
        applySettings()
    }

    func stop() {
        isStarted = false
        applySettings()
    }

    /// The slider on the open island; dragging up from zero also unmutes.
    func setOutputVolume(_ value: Double) {
        let level = Float(min(max(value, 0), 1))
        guard volume.setVolume(level) else { return }
        if level > 0 && volume.isMuted {
            volume.setMuted(false)
        }
        outputVolume = Double(level)
    }

    /// Asks for Accessibility permission, needed to take over the keys.
    func requestAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func applySettings() {
        // Followed even with the volume HUD off, for the slider; Core Audio only calls back
        // on a change.
        if isStarted {
            volume.start()
            lastVolume = volume.volume.map { ($0, volume.isMuted) }
            outputVolume = lastVolume.map { $0.muted ? 0 : Double($0.level) }
        } else {
            volume.stop()
        }
        if isStarted && settings.showBrightnessHUD {
            brightness.start()
        } else {
            brightness.stop()
        }
        if isStarted && settings.replaceSystemHUD {
            isReplacingSystemHUD = keys.start()
        } else {
            keys.stop()
            isReplacingSystemHUD = false
        }
    }

    // MARK: Changes from anywhere

    private func volumeChanged(_ level: Float, _ muted: Bool) {
        // Core Audio repeats itself; only real changes get a HUD.
        if let last = lastVolume, abs(last.level - level) < 0.001, last.muted == muted { return }
        lastVolume = (level, muted)
        outputVolume = muted ? 0 : Double(level)
        guard settings.showVolumeHUD else { return }
        onHUD?(HUDValue(kind: .volume, level: Double(level), isMuted: muted))
    }

    /// Automatic brightness nudges the value a little at a time. A HUD appears only for a
    /// clear change within a short burst, as the keys or the Control Center slider make.
    private func brightnessChanged(_ value: Float) {
        let now = Date()
        if now.timeIntervalSince(lastBrightnessChange) > 1 {
            brightnessBaseline = value
        }
        lastBrightnessChange = now
        let isOngoing = now.timeIntervalSince(lastBrightnessHUD) < 1.5
        let isClearChange = abs(value - (brightnessBaseline ?? value)) >= 0.04
        guard isOngoing || isClearChange else { return }
        lastBrightnessHUD = now
        onHUD?(HUDValue(kind: .brightness, level: Double(value)))
    }

    // MARK: Keys, when replacing the system HUD

    private func handleKey(_ key: MediaKeyTap.Key, fine: Bool) -> Bool {
        let step = fine ? Self.fineStep : Self.step
        switch key {
        case .volumeUp, .volumeDown:
            guard let current = volume.volume else { return false }
            let target = key == .volumeUp ? current + step : current - step
            guard volume.setVolume(Self.snap(target, to: step)) else { return false }
            if key == .volumeUp && volume.isMuted {
                volume.setMuted(false)
            }
        case .mute:
            guard volume.setMuted(!volume.isMuted) else { return false }
        case .brightnessUp, .brightnessDown:
            guard let current = brightness.brightness else { return false }
            let target = key == .brightnessUp ? current + step : current - step
            guard brightness.setBrightness(Self.snap(target, to: step)) else { return false }
            lastBrightnessHUD = Date()
            onHUD?(HUDValue(kind: .brightness, level: Double(Self.snap(target, to: step))))
        }
        return true
    }

    /// Lands on whole steps, as macOS does, so 16 presses always go from 0 to full.
    private static func snap(_ value: Float, to step: Float) -> Float {
        min(max((value / step).rounded() * step, 0), 1)
    }
}
