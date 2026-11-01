import Foundation
import IOKit.ps
import NotchCore

/// Watches the internal battery through power source notifications, only while some charger
/// notice is on; there is no polling.
@MainActor final class PowerMonitor {
    private var source: CFRunLoopSource?
    private var last: PowerState?
    var changed: ((PowerState?, PowerState) -> Void)?

    static var hasBattery: Bool { state() != nil }

    func start() {
        guard source == nil else { return }
        last = Self.state()
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let owner = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { owner.read() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
        last = nil
    }

    private func read() {
        guard let state = Self.state(), state != last else { return }
        let old = last
        last = state
        changed?(old, state)
    }

    /// The internal battery; nil on Macs without one.
    static func state() -> PowerState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return PowerState(onAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                              level: current * 100 / maximum,
                              charged: description[kIOPSIsChargedKey] as? Bool ?? false,
                              minutesToEmpty: description[kIOPSTimeToEmptyKey] as? Int)
        }
        return nil
    }
}
