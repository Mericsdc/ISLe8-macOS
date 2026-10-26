import Foundation
import IOKit
import IOKit.ps

// Ported from LimitBar LRX's PowerMonitor.swift (see UsageModule.swift for the credit).

/// What the battery controller reports about power going in and out. The adapter's rated
/// wattage is never used as a measurement.
nonisolated struct UsagePowerSnapshot: Equatable, Sendable {
    var externalConnected: Bool?
    var isCharging: Bool?
    var batteryPercent: Double?
    /// DC power going into the Mac from the adapter.
    var inputWatts: Double?
    /// Positive = charging, negative = discharging.
    var batteryWatts: Double?
    var measuredAt = Date()

    /// Watts from the adapter; nil on battery or when the sensor has nothing.
    var adapterWatts: Double? { externalConnected == true ? inputWatts : nil }

    static func parse(_ properties: [String: Any], now: Date = Date()) -> UsagePowerSnapshot {
        let external = properties["ExternalConnected"] as? Bool
        let charging = properties["IsCharging"] as? Bool
        let telemetry = properties["PowerTelemetryData"] as? [String: Any] ?? [:]
        func validWatts(_ value: Double?) -> Double? {
            guard let value, value.isFinite, abs(value) <= 500 else { return nil }
            return value
        }
        var input: Double?
        if external == true {
            if let milliwatts = UsageNumber.finite(telemetry["SystemPowerIn"]), milliwatts >= 0 {
                input = validWatts(milliwatts / 1000)
            }
            if input == nil, let millivolts = UsageNumber.finite(telemetry["SystemVoltageIn"]),
               let milliamps = UsageNumber.finite(telemetry["SystemCurrentIn"]), millivolts > 0, milliamps >= 0 {
                input = validWatts(millivolts * milliamps / 1_000_000)
            }
            // A newly attached adapter may report an old zero before the next hardware sample.
            if charging == true && input == 0 { input = nil }
        }
        var battery: Double?
        if let millivolts = UsageNumber.finite(properties["Voltage"]), millivolts > 0, millivolts < 30_000,
           let milliamps = signedCurrent(properties["InstantAmperage"] ?? properties["Amperage"]) {
            battery = validWatts(millivolts * milliamps / 1_000_000)
        }
        var percent: Double?
        if let current = UsageNumber.finite(properties["CurrentCapacity"]),
           let maximum = UsageNumber.finite(properties["MaxCapacity"]), maximum > 0 {
            percent = UsageNumber.percent(current / maximum * 100)
        }
        return UsagePowerSnapshot(externalConnected: external, isCharging: charging, batteryPercent: percent,
                                  inputWatts: input, batteryWatts: battery, measuredAt: now)
    }

    /// Drivers report the current as a signed value in an unsigned 32- or 64-bit field.
    private static func signedCurrent(_ raw: Any?) -> Double? {
        guard let raw = raw as? NSNumber, CFGetTypeID(raw) != CFBooleanGetTypeID() else { return nil }
        var value = Double(raw.int64Value)
        if value > Double(Int32.max) && value <= Double(UInt32.max) {
            value = Double(Int32(bitPattern: raw.uint32Value))
        }
        return value.isFinite && abs(value) <= 30_000 ? value : nil
    }
}

nonisolated enum UsagePowerReader {
    /// Only power fields, straight from IOKit: no shell process, root helper, serial number or history.
    static func read() -> UsagePowerSnapshot {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return UsagePowerSnapshot.parse([:]) }
        defer { IOObjectRelease(service) }
        var values: [String: Any] = [:]
        for key in ["ExternalConnected", "IsCharging", "Voltage", "InstantAmperage", "Amperage",
                    "CurrentCapacity", "MaxCapacity", "PowerTelemetryData"] {
            if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                values[key] = value
            }
        }
        return UsagePowerSnapshot.parse(values)
    }
}

/// Reads the power fields while enabled: every 5 s on the adapter (15 s in saver mode), and on
/// battery only when macOS reports a power source change, with no timer at all.
final class UsagePowerMonitor {
    var onChange: ((UsagePowerSnapshot) -> Void)?
    private let queue = DispatchQueue(label: "com.lrxe8.isle8.usage.power", qos: .utility)
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var enabled = false
    private var economy = false
    private var busy = false
    /// Bumped on stop, so a read that was already under way is dropped.
    private var generation = 0

    var isEnabled: Bool { enabled }

    func configure(enabled: Bool, economy: Bool) {
        if self.enabled == enabled && self.economy == economy { return }
        stop()
        self.enabled = enabled
        self.economy = economy
        guard enabled else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<UsagePowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        refresh()
    }

    func stop() {
        enabled = false
        generation += 1
        busy = false
        timer?.invalidate()
        timer = nil
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        source = nil
    }

    private func refresh() {
        guard enabled, !busy else { return }
        busy = true
        let current = generation
        queue.async { [weak self] in
            let snapshot = UsagePowerReader.read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.received(snapshot, generation: current) }
            }
        }
    }

    private func received(_ snapshot: UsagePowerSnapshot, generation current: Int) {
        guard enabled, generation == current else { return }
        busy = false
        onChange?(snapshot)
        // On battery the OS notification is enough: no recurring timer.
        if snapshot.externalConnected == true {
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: economy ? 15 : 5, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
                timer?.tolerance = economy ? 3 : 1
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }
}
