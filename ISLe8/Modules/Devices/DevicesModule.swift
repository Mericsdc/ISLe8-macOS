import AppKit
import CoreAudio
import IOKit

/// A connected wireless device that reports its battery: AirPods (each bud and the case),
/// Beats, Magic Keyboard, Mouse and Trackpad, game controllers; and, when turned on, the
/// iPhones and iPads that trust this Mac.
nonisolated struct WirelessDevice: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case airPods
        case airPodsPro
        case airPodsMax
        case beats
        case headphones
        case speaker
        case keyboard
        case mouse
        case trackpad
        case gamepad
        case iPhone
        case iPad
        case other
    }

    let id: String
    var name: String
    var kind: Kind
    var main: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// Known for iPhone and iPad only.
    var isCharging = false

    /// "AirPods Pro 3" out of "Deniz (AirPods Pro 3)", "AirPods Pro" out of "Deniz's AirPods Pro".
    var shortName: String {
        if let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"), open < close {
            return String(name[name.index(after: open)..<close])
        }
        for marker in ["’s ", "'s "] {
            if let range = name.range(of: marker) { return String(name[range.upperBound...]) }
        }
        return name
    }

    /// The level that runs out first; the case doesn't count.
    var lowest: Int? { [main, left, right].compactMap { $0 }.min() }
    var hasBuds: Bool { left != nil || right != nil }

    var symbol: String {
        switch kind {
        case .airPods: "airpods.gen3"
        case .airPodsPro: "airpodspro"
        case .airPodsMax: "airpodsmax"
        case .beats: "beats.headphones"
        case .headphones: "headphones"
        case .speaker: "hifispeaker"
        case .keyboard: "keyboard"
        case .mouse: "magicmouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .gamepad: "gamecontroller"
        case .iPhone: "iphone"
        case .iPad: "ipad"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}

/// Batteries of connected wireless devices, as macOS's Bluetooth report has them (the same
/// numbers System Settings shows), and, when turned on in Settings > System, of the iPhones
/// and iPads that trust this Mac. Nothing polls without a reason: the list is read again
/// when an audio device, an Apple input device or a trusted iPhone comes or goes, when the
/// island opens, and every ten minutes while a device is connected. One Bluetooth read costs
/// about 0.06 s of CPU.
@Observable
final class DevicesModule: IslandModule {
    let id = "devices"
    var activity: LiveActivity? { nil }
    /// Bluetooth devices, then iPhones and iPads.
    private(set) var devices: [WirelessDevice] = []

    @ObservationIgnored var onActivityChange: (() -> Void)?
    /// A device that wasn't there at the last read; never for the ones present at launch.
    @ObservationIgnored var onConnected: ((WirelessDevice) -> Void)?
    @ObservationIgnored var onLowBattery: ((WirelessDevice) -> Void)?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let appleDevices = AppleDeviceSource()
    @ObservationIgnored private var bluetooth: [WirelessDevice] = []
    @ObservationIgnored private var phones: [WirelessDevice] = []
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isReadingPhones = false
    @ObservationIgnored private var phoneTask: Task<Void, Never>?
    @ObservationIgnored private let queue = DispatchQueue(label: "com.lrxe8.isle8.devices", qos: .utility)
    @ObservationIgnored private var audioListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var notifyPort: IONotificationPortRef?
    @ObservationIgnored private var iterators: [io_iterator_t] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    @ObservationIgnored private var isReading = false
    @ObservationIgnored private var hasReadOnce = false
    @ObservationIgnored private var lastRead = Date.distantPast
    /// Devices already warned about, until they charge back above 30 %.
    @ObservationIgnored private var warned: Set<String> = []

    static let lowLevel = 15

    init(settings: SettingsStore) {
        self.settings = settings
        // A device that just arrived needs a moment before it opens a session.
        appleDevices.onChange = { [weak self] in self?.readPhones(after: .seconds(2)) }
        settings.onModuleSettingsChange { [weak self] in self?.applyPhoneSetting() }
    }

    func start() {
        guard audioListener == nil else { return }
        isStarted = true
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.somethingConnected() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        audioListener = listener
        watchInputDevices()
        refresh()
        applyPhoneSetting()
    }

    func stop() {
        if let audioListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, audioListener)
        }
        audioListener = nil
        iterators.forEach { IOObjectRelease($0) }
        iterators = []
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
        notifyPort = nil
        refreshTask?.cancel()
        periodicTask?.cancel()
        isStarted = false
        applyPhoneSetting()
    }

    /// The island opened: numbers older than a minute are read again.
    func setVisible(_ visible: Bool) {
        if visible && Date().timeIntervalSince(lastRead) > 60 {
            refresh()
            readPhones()
        }
    }

    // MARK: iPhone and iPad

    /// Off by default. While off, the MobileDevice framework isn't even loaded.
    private func applyPhoneSetting() {
        if isStarted && settings.showAppleDevices {
            appleDevices.start()
            readPhones()
        } else {
            appleDevices.stop()
            phoneTask?.cancel()
            phones = []
            publish()
        }
    }

    private func readPhones(after delay: Duration = .zero) {
        guard isStarted, settings.showAppleDevices else { return }
        phoneTask?.cancel()
        phoneTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, !self.isReadingPhones else { return }
            self.isReadingPhones = true
            self.appleDevices.read { readings in
                self.isReadingPhones = false
                self.applyPhones(readings)
            }
        }
    }

    private func applyPhones(_ readings: [AppleDeviceSource.Reading]) {
        guard settings.showAppleDevices else { return }
        phones = readings.map { reading in
            WirelessDevice(
                id: reading.id,
                name: reading.name,
                kind: reading.productType.hasPrefix("iPad") ? .iPad : .iPhone,
                main: reading.level,
                isCharging: reading.isCharging
            )
        }
        // No "connected" banner: a phone on Wi-Fi comes and goes as it sleeps. Low battery
        // is said once, as for the other devices.
        for phone in phones {
            let level = phone.main ?? 100
            if level <= Self.lowLevel, !phone.isCharging, !warned.contains(phone.id) {
                warned.insert(phone.id)
                onLowBattery?(phone)
            } else if level > 30 {
                warned.remove(phone.id)
            }
        }
        publish()
        schedulePeriodicRead()
    }

    private func publish() {
        let merged = bluetooth + phones
        guard merged != devices else { return }
        devices = merged
        onActivityChange?()
    }

    // MARK: Triggers

    /// Read twice: right away the buds often report before the case does.
    private func somethingConnected() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.refresh()
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self.refresh()
        }
    }

    /// Magic Keyboard, Mouse and Trackpad appear and vanish as IOKit services.
    private func watchInputDevices() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            // Drain the iterator, or IOKit stops sending notifications.
            while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
            guard let context else { return }
            let module = Unmanaged<DevicesModule>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { module.somethingConnected() }
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
            guard IOServiceAddMatchingNotification(port, type, matching, callback, context, &iterator) == KERN_SUCCESS else { continue }
            while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
            iterators.append(iterator)
        }
    }

    /// Batteries change slowly; ten minutes is plenty, and nothing runs with no device.
    private func schedulePeriodicRead() {
        periodicTask?.cancel()
        guard !devices.isEmpty else { return }
        periodicTask = Task {
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            self.refresh()
            self.readPhones()
        }
    }

    // MARK: Reading

    func refresh() {
        guard !isReading else { return }
        isReading = true
        queue.async {
            let found = Self.readDevices()
            Task { @MainActor in
                self.isReading = false
                self.apply(found)
            }
        }
    }

    private func apply(_ found: [WirelessDevice]?) {
        lastRead = Date()
        // A failed read keeps what was there.
        guard let found else {
            schedulePeriodicRead()
            return
        }
        let previous = Set(bluetooth.map(\.id))
        bluetooth = found
        publish()
        for device in found {
            let level = device.lowest ?? 100
            let isNew = hasReadOnce && !previous.contains(device.id)
            // One banner per device: a low one says so instead of just "connected".
            if level <= Self.lowLevel, !warned.contains(device.id), hasReadOnce || level <= 10 {
                warned.insert(device.id)
                onLowBattery?(device)
            } else if isNew {
                onConnected?(device)
            }
            if level > 30 {
                warned.remove(device.id)
            }
        }
        hasReadOnce = true
        schedulePeriodicRead()
    }

    /// `system_profiler SPBluetoothDataType -json`, connected devices with a battery level.
    nonisolated private static func readDevices() -> [WirelessDevice]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // A hung report must not hold the queue.
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return parse(data)
    }

    nonisolated static func parse(_ data: Data) -> [WirelessDevice]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        var devices: [WirelessDevice] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    // "%80" in Turkish, "80%" in English.
                    func level(_ key: String) -> Int? {
                        guard let text = info[key] as? String, let number = Int(text.filter(\.isNumber)) else { return nil }
                        return min(max(number, 0), 100)
                    }
                    let device = WirelessDevice(
                        id: info["device_address"] as? String ?? name,
                        name: name,
                        kind: kind(name: name, minorType: info["device_minorType"] as? String, productID: info["device_productID"] as? String),
                        main: level("device_batteryLevelMain"),
                        left: level("device_batteryLevelLeft"),
                        right: level("device_batteryLevelRight"),
                        caseLevel: level("device_batteryLevelCase")
                    )
                    if device.lowest != nil || device.caseLevel != nil {
                        devices.append(device)
                    }
                }
            }
        }
        return merged(devices).sorted { $0.name < $1.name }
    }

    /// AirPods are listed twice while connected, over Bluetooth LE for the batteries and
    /// classic Bluetooth for audio, under the same name. One entry each, every field filled.
    nonisolated private static func merged(_ devices: [WirelessDevice]) -> [WirelessDevice] {
        var result: [WirelessDevice] = []
        for device in devices {
            guard let index = result.firstIndex(where: { $0.name == device.name }) else {
                result.append(device)
                continue
            }
            var kept = result[index]
            if kept.kind == .other { kept.kind = device.kind }
            kept.main = kept.main ?? device.main
            kept.left = kept.left ?? device.left
            kept.right = kept.right ?? device.right
            kept.caseLevel = kept.caseLevel ?? device.caseLevel
            result[index] = kept
        }
        return result
    }

    /// Renamed AirPods ("Deniz's AirPods") still carry their model in the name or product id.
    nonisolated private static func kind(name: String, minorType: String?, productID: String?) -> WirelessDevice.Kind {
        let name = name.lowercased()
        let product = Int(productID?.replacingOccurrences(of: "0x", with: "") ?? "", radix: 16)
        if name.contains("airpods max") || [0x200A, 0x201F].contains(product) { return .airPodsMax }
        if name.contains("airpods pro") || [0x200E, 0x2014, 0x2024, 0x2027].contains(product) { return .airPodsPro }
        if name.contains("airpods") || [0x2002, 0x200F, 0x2013, 0x2019, 0x201B].contains(product) { return .airPods }
        if name.contains("beats") || name.contains("powerbeats") { return .beats }
        switch minorType?.lowercased() ?? "" {
        case let type where type.contains("keyboard"): return .keyboard
        case let type where type.contains("mouse"): return .mouse
        case let type where type.contains("trackpad"): return .trackpad
        case let type where type.contains("gamepad") || type.contains("joystick"): return .gamepad
        case let type where type.contains("headphone") || type.contains("headset"): return .headphones
        case let type where type.contains("speaker"): return .speaker
        default: break
        }
        if name.contains("keyboard") { return .keyboard }
        if name.contains("mouse") { return .mouse }
        if name.contains("trackpad") { return .trackpad }
        return .other
    }
}
