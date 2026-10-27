import Network
import SwiftUI

enum BatteryEvent: Equatable {
    case pluggedIn(percent: Int)
    case unplugged(percent: Int)
    case low(percent: Int)
    case critical(percent: Int)
}

/// Battery, camera and microphone use, and keeping the Mac awake.
@Observable
final class SystemModule: IslandModule {
    let id = "system"
    private(set) var battery: BatteryState?
    private(set) var isCameraInUse = false
    private(set) var isMicrophoneInUse = false
    private(set) var isKeepingAwake = false
    /// How the Mac is online now, from the system's path monitor: no polling.
    private(set) var network: NetworkLink = .offline
    /// The System tab's figures; sampled only while that tab is on screen.
    let stats = SystemStats()
    /// While set, the keyboard is locked for cleaning until then.
    private(set) var keyboardUnlocksAt: Date?

    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored var onBatteryEvent: ((BatteryEvent) -> Void)?
    /// An Ethernet cable came (true) or went (false); not for one already in at launch.
    @ObservationIgnored var onWiredChange: ((Bool) -> Void)?
    /// The keyboard was locked (true) or unlocked (false) for cleaning.
    @ObservationIgnored var onKeyboardLockChange: ((Bool) -> Void)?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let batteryMonitor = BatteryMonitor()
    @ObservationIgnored private let privacyMonitor = PrivacyMonitor()
    @ObservationIgnored private let keepAwake = KeepAwake()
    @ObservationIgnored private let keyboardLock = KeyboardLock()
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var keyboardTask: Task<Void, Never>?
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
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let link = NetworkLink(path)
            Task { @MainActor in self?.networkChanged(link) }
        }
        monitor.start(queue: DispatchQueue(label: "com.lrxe8.isle8.network", qos: .utility))
        pathMonitor = monitor
    }

    func stop() {
        batteryMonitor.stop()
        privacyMonitor.stop()
        pathMonitor?.cancel()
        pathMonitor = nil
        setKeepAwake(false)
        unlockKeyboard()
    }

    @ObservationIgnored private var hasNetwork = false

    private func networkChanged(_ link: NetworkLink) {
        let old = network
        network = link
        if hasNetwork, (link == .wired) != (old == .wired) {
            onWiredChange?(link == .wired)
        }
        hasNetwork = true
    }

    func setKeepAwake(_ on: Bool) {
        keepAwake.set(on)
        isKeepingAwake = keepAwake.isOn
    }

    /// How long the keyboard stays locked if nobody unlocks it.
    static let keyboardLockLimit: Duration = .seconds(120)

    /// Locks the keyboard for cleaning. Without Accessibility permission it asks for it and
    /// returns false.
    @discardableResult
    func lockKeyboard() -> Bool {
        guard keyboardLock.lock() else {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return false
        }
        keyboardUnlocksAt = .now.addingTimeInterval(TimeInterval(Self.keyboardLockLimit.components.seconds))
        keyboardTask?.cancel()
        keyboardTask = Task { [weak self] in
            try? await Task.sleep(for: Self.keyboardLockLimit)
            guard !Task.isCancelled else { return }
            self?.unlockKeyboard()
        }
        onKeyboardLockChange?(true)
        return true
    }

    func unlockKeyboard() {
        keyboardTask?.cancel()
        keyboardTask = nil
        guard keyboardLock.isLocked else { return }
        keyboardLock.unlock()
        keyboardUnlocksAt = nil
        onKeyboardLockChange?(false)
    }

    private func batteryChanged(_ state: BatteryState) {
        let old = battery
        battery = state
        guard settings.showBatteryAlerts, let old else { return }

        if state.isPluggedIn && !old.isPluggedIn {
            announcedLow.removeAll()
            onBatteryEvent?(.pluggedIn(percent: state.percent))
        } else if !state.isPluggedIn && old.isPluggedIn {
            onBatteryEvent?(.unplugged(percent: state.percent))
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

/// The way out to the internet: an Ethernet cable, Wi-Fi, something else, or none.
nonisolated enum NetworkLink: Equatable, Sendable {
    case wired
    case wifi
    case cellular
    case other
    case offline

    init(_ path: NWPath) {
        guard path.status == .satisfied else {
            self = .offline
            return
        }
        if path.usesInterfaceType(.wiredEthernet) {
            self = .wired
        } else if path.usesInterfaceType(.wifi) {
            self = .wifi
        } else if path.usesInterfaceType(.cellular) {
            self = .cellular
        } else {
            self = .other
        }
    }
}
