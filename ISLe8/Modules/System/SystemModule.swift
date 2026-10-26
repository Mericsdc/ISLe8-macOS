import SwiftUI

enum BatteryEvent: Equatable {
    case pluggedIn(percent: Int)
    case low(percent: Int)
    case critical(percent: Int)
    case full
}

/// Battery, camera and microphone use, and keeping the Mac awake.
@Observable
final class SystemModule: IslandModule {
    let id = "system"
    private(set) var battery: BatteryState?
    private(set) var isCameraInUse = false
    private(set) var isMicrophoneInUse = false
    private(set) var isKeepingAwake = false

    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored var onBatteryEvent: ((BatteryEvent) -> Void)?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let batteryMonitor = BatteryMonitor()
    @ObservationIgnored private let privacyMonitor = PrivacyMonitor()
    @ObservationIgnored private let keepAwake = KeepAwake()
    /// Thresholds already announced in the current discharge, so each is said once.
    @ObservationIgnored private var announcedLow: Set<Int> = []

    init(settings: SettingsStore) {
        self.settings = settings
        batteryMonitor.onChange = { [weak self] state in self?.batteryChanged(state) }
        privacyMonitor.onChange = { [weak self] camera, microphone in self?.privacyChanged(camera, microphone) }
    }

    /// Camera or microphone in use, in the ears when nothing more important is there.
    var activity: LiveActivity? {
        guard isCameraInUse || isMicrophoneInUse else { return nil }
        return LiveActivity(
            id: id,
            priority: ActivityPriority.privacy,
            leading: AnyView(PrivacyEar(camera: isCameraInUse, microphone: isMicrophoneInUse)),
            trailing: AnyView(EmptyView())
        )
    }

    func start() {
        batteryMonitor.start()
        battery = batteryMonitor.state
        privacyMonitor.start()
    }

    func stop() {
        batteryMonitor.stop()
        privacyMonitor.stop()
        setKeepAwake(false)
    }

    func setKeepAwake(_ on: Bool) {
        keepAwake.set(on)
        isKeepingAwake = keepAwake.isOn
    }

    private func batteryChanged(_ state: BatteryState) {
        let old = battery
        battery = state
        guard settings.showBatteryAlerts, let old else { return }

        if state.isPluggedIn && !old.isPluggedIn {
            announcedLow.removeAll()
            onBatteryEvent?(.pluggedIn(percent: state.percent))
        } else if state.isPluggedIn && state.isCharged && !old.isCharged {
            onBatteryEvent?(.full)
        } else if !state.isPluggedIn {
            for threshold in [10, 20] where state.percent <= threshold && old.percent > threshold && !announcedLow.contains(threshold) {
                announcedLow.insert(threshold)
                onBatteryEvent?(threshold == 10 ? .critical(percent: state.percent) : .low(percent: state.percent))
                break
            }
        }
    }

    private func privacyChanged(_ camera: Bool, _ microphone: Bool) {
        isCameraInUse = camera
        isMicrophoneInUse = microphone
        onActivityChange?()
    }
}
