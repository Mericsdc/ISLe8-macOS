import CoreAudio
import CoreMediaIO
import Foundation
import IOKit.pwr_mgt
import IOKit.ps

// MARK: Battery

struct BatteryState: Equatable {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var isCharged: Bool
}

/// The internal battery. IOKit calls back whenever the power source changes (about once
/// per percent, and on plugging in or out).
final class BatteryMonitor {
    var onChange: ((BatteryState) -> Void)?
    private(set) var state: BatteryState?
    private var source: CFRunLoopSource?

    func start() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.update() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
        state = Self.read()
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        source = nil
    }

    private func update() {
        let new = Self.read()
        guard new != state else { return }
        state = new
        if let new {
            onChange?(new)
        }
    }

    private static func read() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            return BatteryState(
                percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false
            )
        }
        return nil
    }
}

// MARK: Camera and microphone

/// Whether any app is using a camera or the microphone, the same thing macOS shows with its
/// green and orange dots. Both are property listeners; nothing polls, and no camera or
/// microphone permission is needed to ask.
final class PrivacyMonitor {
    var onChange: ((_ camera: Bool, _ microphone: Bool) -> Void)?
    private(set) var isCameraInUse = false
    private(set) var isMicrophoneInUse = false

    private var cameraListener: CMIOObjectPropertyListenerBlock?
    private var cameras: [CMIOObjectID] = []
    private var microphoneListener: AudioObjectPropertyListenerBlock?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var microphone = AudioObjectID(kAudioObjectUnknown)

    func start() {
        guard cameraListener == nil else { return }
        let cameraListener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.update() }
        }
        self.cameraListener = cameraListener
        cameras = Self.cameraDevices()
        for camera in cameras {
            var address = Self.cameraRunningAddress
            CMIOObjectAddPropertyListenerBlock(camera, &address, .main, cameraListener)
        }

        let microphoneListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.update() }
        }
        self.microphoneListener = microphoneListener
        let defaultInputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachMicrophone() }
        }
        self.defaultInputListener = defaultInputListener
        var defaultInput = Self.audioAddress(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInput, .main, defaultInputListener)
        attachMicrophone()
        update()
    }

    func stop() {
        if let cameraListener {
            for camera in cameras {
                var address = Self.cameraRunningAddress
                CMIOObjectRemovePropertyListenerBlock(camera, &address, .main, cameraListener)
            }
        }
        cameraListener = nil
        cameras = []
        detachMicrophone()
        if let defaultInputListener {
            var address = Self.audioAddress(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, defaultInputListener)
        }
        defaultInputListener = nil
    }

    private func update() {
        let camera = cameras.contains(where: Self.isCameraRunning)
        let microphone = Self.isAudioDeviceRunning(self.microphone)
        guard camera != isCameraInUse || microphone != isMicrophoneInUse else { return }
        isCameraInUse = camera
        isMicrophoneInUse = microphone
        onChange?(camera, microphone)
    }

    private func attachMicrophone() {
        detachMicrophone()
        var address = Self.audioAddress(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              let microphoneListener
        else { return }
        microphone = id
        var running = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectAddPropertyListenerBlock(microphone, &running, .main, microphoneListener)
        update()
    }

    private func detachMicrophone() {
        guard let microphoneListener, microphone != kAudioObjectUnknown else { return }
        var running = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectRemovePropertyListenerBlock(microphone, &running, .main, microphoneListener)
        microphone = AudioObjectID(kAudioObjectUnknown)
    }

    private static var cameraRunningAddress: CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private static func cameraDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return [] }
        return devices
    }

    private static func isCameraRunning(_ device: CMIOObjectID) -> Bool {
        var address = cameraRunningAddress
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &value) == noErr && value != 0
    }

    private static func isAudioDeviceRunning(_ device: AudioObjectID) -> Bool {
        guard device != kAudioObjectUnknown else { return false }
        var address = audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}

// MARK: Keep awake

/// Keeps the display from sleeping, like `caffeinate -d`, until switched off.
final class KeepAwake {
    private var assertion: IOPMAssertionID = 0
    private(set) var isOn = false

    func set(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "ISLe8: Uyanık tut" as CFString,
                &assertion
            )
            isOn = result == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(assertion)
            isOn = false
        }
    }
}
