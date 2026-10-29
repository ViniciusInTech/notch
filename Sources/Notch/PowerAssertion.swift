import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// The power assertion `caffeinate` itself takes, held in-process: no helper process, and the
/// system drops it on its own if the app quits or crashes.
@MainActor final class PowerAssertion {
    private var id = IOPMAssertionID(0)
    private var held: Bool?
    private var powerSource: CFRunLoopSource?
    /// Called on the main run loop when the power source or charge changes, only while held.
    var powerChanged: (() -> Void)?

    /// `display` keeps the screen on too; otherwise only idle system sleep is prevented.
    func hold(display: Bool) {
        guard held != display else { return }
        release()
        let type = (display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep) as CFString
        guard IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Notch: manter acordado" as CFString, &id) == kIOReturnSuccess else { return }
        held = display
        observePower()
    }

    func release() {
        if held != nil { IOPMAssertionRelease(id) }
        held = nil
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
    }

    private func observePower() {
        guard powerSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let owner = Unmanaged<PowerAssertion>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { owner.powerChanged?() }
        }, context)?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
    }

    /// Internal battery charge in percent while running on it; nil on AC power or without a battery.
    static func batteryLevelOnBattery() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            guard description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { return nil }
            return current * 100 / maximum
        }
        return nil
    }
}
