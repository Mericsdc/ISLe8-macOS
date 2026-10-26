import AppKit
import CoreAudio
import IOKit

/// A connected wireless device that reports its battery: AirPods (each bud and the case),
/// Beats, Magic Keyboard, Mouse and Trackpad, game controllers.
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
        case other
    }

    let id: String
    var name: String
    var kind: Kind
    var main: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

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
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}

/// Batteries of connected wireless devices, as macOS's Bluetooth report has them (the same
/// numbers System Settings shows). Nothing polls without a reason: the list is read again
/// when an audio device or an Apple input device comes or goes, when the island opens, and
/// every ten minutes while a device is connected. One read costs about 0.06 s of CPU.
@Observable
final class DevicesModule: IslandModule {
    let id = "devices"
    var activity: LiveActivity? { nil }
    private(set) var devices: [WirelessDevice] = []

    @ObservationIgnored var onActivityChange: (() -> Void)?
    /// A device that wasn't there at the last read; never for the ones present at launch.
    @ObservationIgnored var onConnected: ((WirelessDevice) -> Void)?
    @ObservationIgnored var onLowBattery: ((WirelessDevice) -> Void)?

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

    func start() {
        guard audioListener == nil else { return }
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
    }

    /// The island opened: numbers older than a minute are read again.
    func setVisible(_ visible: Bool) {
        if visible && Date().timeIntervalSince(lastRead) > 60 {
            refresh()
        }
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
        let previous = Set(devices.map(\.id))
        if found != devices {
            devices = found
            onActivityChange?()
        }
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
