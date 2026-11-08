import Foundation

/// Battery of a Bluetooth headset as the system reports it at a given moment. AirPods report each
/// side and the case; other headsets one value. Unknown parts are nil.
public struct HeadphoneBattery: Equatable, Sendable {
    public let single: Int?
    public let left: Int?
    public let right: Int?
    public let caseLevel: Int?

    /// Zero or out-of-range readings mean the device has not reported that part yet.
    public init(single: Int? = nil, left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil) {
        func valid(_ value: Int?) -> Int? { value.flatMap { (1...100).contains($0) ? $0 : nil } }
        self.single = valid(single)
        self.left = valid(left)
        self.right = valid(right)
        self.caseLevel = valid(caseLevel)
    }

    public var isEmpty: Bool { single == nil && left == nil && right == nil && caseLevel == nil }
    public var hasSides: Bool { left != nil || right != nil }

    /// One number for the collapsed island: the lowest earbud, else the headset itself.
    public var summary: Int? {
        let buds = [left, right].compactMap { $0 }
        return buds.min() ?? single
    }
}

public enum HeadphoneStyle: Sendable {
    case airpods, airpodsPro, airpodsMax, beats, headphones

    /// Guessed from the name the user sees in Bluetooth settings.
    public init(name: String) {
        let lower = name.lowercased()
        if lower.contains("airpods max") { self = .airpodsMax }
        else if lower.contains("airpods pro") { self = .airpodsPro }
        else if lower.contains("airpods") { self = .airpods }
        else if lower.contains("beats") || lower.contains("powerbeats") { self = .beats }
        else { self = .headphones }
    }
}

public struct HeadphoneDevice: Equatable, Sendable {
    public let address: String
    public let name: String
    public let battery: HeadphoneBattery

    public init(address: String, name: String, battery: HeadphoneBattery) {
        self.address = address
        self.name = name
        self.battery = battery
    }

    public var style: HeadphoneStyle { HeadphoneStyle(name: name) }
}
