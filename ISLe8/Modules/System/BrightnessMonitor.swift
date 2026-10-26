import CoreGraphics
import Foundation

/// The built-in display's brightness, through the private DisplayServices framework (the
/// one the brightness keys use). It calls back on every change, including the slow ones
/// automatic brightness makes, so the caller decides which changes deserve a HUD.
final class BrightnessMonitor {
    var onChange: ((Float) -> Void)?

    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias Register = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?, CFNotificationCallback) -> Int32

    private struct API {
        let get: Get
        let set: Set
        let register: Register
    }

    private static let api: API? = {
        guard let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(framework, "DisplayServicesGetBrightness"),
              let set = dlsym(framework, "DisplayServicesSetBrightness"),
              let register = dlsym(framework, "DisplayServicesRegisterForBrightnessChangeNotifications")
        else { return nil }
        return API(
            get: unsafeBitCast(get, to: Get.self),
            set: unsafeBitCast(set, to: Set.self),
            register: unsafeBitCast(register, to: Register.self)
        )
    }()

    private var display: CGDirectDisplayID?
    private var isRegistered = false
    private var isActive = false

    /// The registration can't be undone safely, so stop() only mutes the callback.
    func start() {
        isActive = true
        guard !isRegistered, let api = Self.api, let display = Self.builtInDisplay() else { return }
        self.display = display
        let observer = Unmanaged.passUnretained(self).toOpaque()
        let callback: CFNotificationCallback = { _, observer, _, _, userInfo in
            guard let observer,
                  let info = userInfo as NSDictionary?,
                  let value = (info["value"] as? NSNumber)?.floatValue
            else { return }
            let monitor = Unmanaged<BrightnessMonitor>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { monitor.changed(value) }
            }
        }
        isRegistered = api.register(display, observer, callback) == 0
    }

    func stop() {
        isActive = false
    }

    var brightness: Float? {
        guard let api = Self.api, let display = display ?? Self.builtInDisplay() else { return nil }
        var value: Float = 0
        return api.get(display, &value) == 0 ? value : nil
    }

    @discardableResult
    func setBrightness(_ value: Float) -> Bool {
        guard let api = Self.api, let display = display ?? Self.builtInDisplay() else { return false }
        return api.set(display, min(max(value, 0), 1)) == 0
    }

    private func changed(_ value: Float) {
        guard isActive else { return }
        onChange?(value)
    }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }
}
