import Foundation

/// iPhone and iPad batteries, read the way Finder reaches the devices. Apple's MobileDevice
/// framework sees every device this Mac trusts, by cable or on the same Wi-Fi with "Show
/// this iPhone when on Wi-Fi" on in Finder, and opens a lockdown session with the pairing
/// record macOS made when "Trust This Computer" was tapped. Read-only: nothing on the device
/// changes and no pairing is ever started. No permission is needed. Comings and goings arrive
/// as notifications; nothing polls. See docs/apple-device-batteries.md.
final class AppleDeviceSource {
    nonisolated struct Reading: Equatable, Sendable {
        let id: String
        let name: String
        let productType: String
        let level: Int
        let isCharging: Bool
    }

    /// A trusted device came or went.
    var onChange: (() -> Void)?

    /// False when the framework can't be loaded; the feature then just stays empty.
    var isAvailable: Bool { MobileDevice.shared != nil }

    private var subscription: UnsafeMutableRawPointer?
    /// Retained devices by their object address. A device on both cable and Wi-Fi is two
    /// objects with one identifier.
    private var attached: [Int: DeviceRef] = [:]

    func start() {
        guard subscription == nil, let api = MobileDevice.shared else { return }
        var reference: UnsafeMutableRawPointer?
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard api.subscribe(Self.callback, 0, 0, context, &reference) == 0 else { return }
        subscription = reference
    }

    func stop() {
        guard let api = MobileDevice.shared else { return }
        if let subscription {
            _ = api.unsubscribe(subscription)
        }
        subscription = nil
        attached.values.forEach { api.release($0.pointer) }
        attached = [:]
    }

    /// Every attached device, once each, off the main thread. One that is asleep or out of
    /// reach is left out.
    func read(_ completion: @escaping @MainActor @Sendable ([Reading]) -> Void) {
        let devices = Array(attached.values)
        DispatchQueue.global(qos: .utility).async {
            let readings = Self.read(devices)
            Task { @MainActor in completion(readings) }
        }
    }

    // MARK: Notifications

    nonisolated private static let callback: MobileDevice.Callback = { info, context in
        // struct am_device_notification_callback_info { am_device *device; unsigned int message; … }
        guard let info, let context, let api = MobileDevice.shared,
              let device = info.load(as: UnsafeMutableRawPointer?.self) else { return }
        let message = info.load(fromByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        guard message == 1 || message == 2 else { return }
        let source = SourceRef(pointer: context)
        let key = Int(bitPattern: device)
        // The device object is only lent for the call; keep it while it stays attached.
        let arrived: DeviceRef? = if message == 1, let id = api.copyIdentifier(device)?.takeRetainedValue() {
            DeviceRef(pointer: api.retain(device), id: id as String)
        } else {
            nil
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Unmanaged<AppleDeviceSource>.fromOpaque(source.pointer).takeUnretainedValue().handle(key: key, arrived: arrived)
            }
        }
    }

    private func handle(key: Int, arrived: DeviceRef?) {
        if let arrived {
            if let old = attached.updateValue(arrived, forKey: key) {
                MobileDevice.shared?.release(old.pointer)
            }
        } else if let gone = attached.removeValue(forKey: key) {
            MobileDevice.shared?.release(gone.pointer)
        } else {
            return
        }
        onChange?()
    }

    // MARK: Reading

    nonisolated private static func read(_ devices: [DeviceRef]) -> [Reading] {
        guard let api = MobileDevice.shared else { return [] }
        var readings: [String: Reading] = [:]
        for device in devices where readings[device.id] == nil {
            if let reading = read(device, with: api) {
                readings[device.id] = reading
            }
        }
        return readings.values.sorted { $0.name < $1.name }
    }

    nonisolated private static func read(_ device: DeviceRef, with api: MobileDevice) -> Reading? {
        let pointer = device.pointer
        guard api.connect(pointer) == 0 else { return nil }
        defer { _ = api.disconnect(pointer) }
        // Only devices that already trust this Mac; validating never asks the device anything.
        guard api.isPaired(pointer) == 1, api.validatePairing(pointer) == 0, api.startSession(pointer) == 0 else { return nil }
        defer { _ = api.stopSession(pointer) }
        let product = value(api, pointer, domain: nil, key: "ProductType") as? String ?? ""
        guard ["iPhone", "iPad", "iPod"].contains(where: product.hasPrefix) else { return nil }
        let battery = value(api, pointer, domain: "com.apple.mobile.battery", key: nil) as? [String: Any] ?? [:]
        guard let level = battery["BatteryCurrentCapacity"] as? Int else { return nil }
        return Reading(
            id: device.id,
            name: value(api, pointer, domain: nil, key: "DeviceName") as? String ?? product,
            productType: product,
            level: min(max(level, 0), 100),
            isCharging: battery["BatteryIsCharging"] as? Bool ?? false
        )
    }

    nonisolated private static func value(_ api: MobileDevice, _ device: UnsafeMutableRawPointer, domain: String?, key: String?) -> Any? {
        api.copyValue(device, domain as CFString?, key as CFString?)?.takeRetainedValue()
    }
}

/// A retained MobileDevice device object; only used on one thread at a time.
private nonisolated struct DeviceRef: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
    let id: String
}

private nonisolated struct SourceRef: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
}

/// The few MobileDevice functions used, looked up at run time. The framework is private, so
/// nothing links against it.
private nonisolated struct MobileDevice: @unchecked Sendable {
    /// Gets the notification (device, then 1 connected / 2 disconnected / 3 unsubscribed) and
    /// the context passed to `subscribe`.
    typealias Callback = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias DeviceCall = @convention(c) (UnsafeMutableRawPointer) -> Int32

    let subscribe: @convention(c) (Callback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    let unsubscribe: DeviceCall
    let connect: DeviceCall
    let disconnect: DeviceCall
    let isPaired: DeviceCall
    let validatePairing: DeviceCall
    let startSession: DeviceCall
    let stopSession: DeviceCall
    let copyValue: @convention(c) (UnsafeMutableRawPointer, CFString?, CFString?) -> Unmanaged<AnyObject>?
    let copyIdentifier: @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFString>?
    let retain: @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer
    let release: @convention(c) (UnsafeMutableRawPointer) -> Void

    static let shared: MobileDevice? = load()

    private static func load() -> MobileDevice? {
        let paths = [
            "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice",
            "/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice",
        ]
        guard let handle = paths.lazy.compactMap({ dlopen($0, RTLD_LAZY) }).first else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let subscribe = symbol("AMDeviceNotificationSubscribe", as: (@convention(c) (Callback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32).self),
              let unsubscribe = symbol("AMDeviceNotificationUnsubscribe", as: DeviceCall.self),
              let connect = symbol("AMDeviceConnect", as: DeviceCall.self),
              let disconnect = symbol("AMDeviceDisconnect", as: DeviceCall.self),
              let isPaired = symbol("AMDeviceIsPaired", as: DeviceCall.self),
              let validatePairing = symbol("AMDeviceValidatePairing", as: DeviceCall.self),
              let startSession = symbol("AMDeviceStartSession", as: DeviceCall.self),
              let stopSession = symbol("AMDeviceStopSession", as: DeviceCall.self),
              let copyValue = symbol("AMDeviceCopyValue", as: (@convention(c) (UnsafeMutableRawPointer, CFString?, CFString?) -> Unmanaged<AnyObject>?).self),
              let copyIdentifier = symbol("AMDeviceCopyDeviceIdentifier", as: (@convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFString>?).self),
              let retain = symbol("AMDeviceRetain", as: (@convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer).self),
              let release = symbol("AMDeviceRelease", as: (@convention(c) (UnsafeMutableRawPointer) -> Void).self)
        else { return nil }
        return MobileDevice(
            subscribe: subscribe, unsubscribe: unsubscribe, connect: connect, disconnect: disconnect,
            isPaired: isPaired, validatePairing: validatePairing, startSession: startSession,
            stopSession: stopSession, copyValue: copyValue, copyIdentifier: copyIdentifier,
            retain: retain, release: release
        )
    }
}
