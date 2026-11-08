import Foundation
import IOBluetooth
import NotchCore
import os

private let headphoneLog = Logger(subsystem: "dev.vinicius.Notch", category: "headphones")

/// Bluetooth audio devices through IOBluetooth connect and disconnect notifications; nothing polls.
/// Battery is read once at connection (and once more if the device has not reported it yet) and
/// again only when the compact hover asks for it.
@MainActor final class HeadphoneMonitor: NSObject {
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var startedAt = Date.distantPast
    /// The device and whether it just connected (false for those already connected at start).
    var connected: ((HeadphoneDevice, Bool) -> Void)?
    var disconnected: ((String) -> Void)?

    func start() {
        guard connectNotification == nil else { return }
        startedAt = Date()
        // Already connected devices are reported right away through the same callback.
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:fromDevice:)))
        headphoneLog.info("started")
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications = [:]
    }

    /// A fresh reading of one device, for the compact hover.
    func read(address: String) -> HeadphoneDevice? {
        guard let device = IOBluetoothDevice(addressString: address), device.isConnected() else { return nil }
        return Self.describe(device)
    }

    // IOBluetooth may call these on its own coordinator queue, so they hop to the main queue
    // instead of asserting isolation, which traps off the main thread.
    @objc nonisolated private func deviceConnected(_ note: IOBluetoothUserNotification, fromDevice device: IOBluetoothDevice) {
        nonisolated(unsafe) let device = device
        DispatchQueue.main.async { MainActor.assumeIsolated { self.connect(device) } }
    }

    @objc nonisolated private func deviceDisconnected(_ note: IOBluetoothUserNotification, fromDevice device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.disconnectNotifications.removeValue(forKey: address)?.unregister()
                headphoneLog.info("disconnected")
                self.disconnected?(address)
            }
        }
    }

    private func connect(_ device: IOBluetoothDevice) {
        guard UInt32(device.deviceClassMajor) == UInt32(kBluetoothDeviceClassMajorAudio), let address = device.addressString else { return }
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:fromDevice:)))
        let fresh = Date().timeIntervalSince(startedAt) > 2
        let info = Self.describe(device)
        headphoneLog.info("connected fresh=\(fresh) battery=\(!info.battery.isEmpty)")
        connected?(info, fresh)
        // Earbuds often report their battery a moment after the link comes up: one more look.
        guard info.battery.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.disconnectNotifications[address] != nil, let again = self.read(address: address), !again.battery.isEmpty else { return }
            self.connected?(again, false)
        }
    }

    /// Battery comes from private IOBluetoothDevice properties; each one is checked before use,
    /// so a macOS without them just shows no percentage.
    private static func describe(_ device: IOBluetoothDevice) -> HeadphoneDevice {
        func percent(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)) else { return nil }
            return (device.value(forKey: key) as? NSNumber)?.intValue
        }
        let battery = HeadphoneBattery(single: percent("batteryPercentSingle") ?? percent("batteryPercentCombined"),
                                       left: percent("batteryPercentLeft"), right: percent("batteryPercentRight"),
                                       caseLevel: percent("batteryPercentCase"))
        return HeadphoneDevice(address: device.addressString ?? "", name: device.nameOrAddress ?? "Fone", battery: battery)
    }
}
