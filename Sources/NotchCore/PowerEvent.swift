import Foundation

/// The internal battery as the power source reports it.
public struct PowerState: Equatable, Sendable {
    public let onAC: Bool
    public let level: Int
    public let charged: Bool
    /// The system's estimate on battery; nil while it is still calculating.
    public let minutesToEmpty: Int?

    public init(onAC: Bool, level: Int, charged: Bool = false, minutesToEmpty: Int? = nil) {
        self.onAC = onAC
        self.level = min(100, max(0, level))
        self.charged = charged
        self.minutesToEmpty = minutesToEmpty.flatMap { $0 > 0 ? $0 : nil }
    }
}

public enum PowerEvent: Equatable, Sendable {
    case connected(level: Int)
    case disconnected(level: Int, minutesLeft: Int?)
    case charged
    case low(level: Int)
}

public enum PowerEvents {
    public static let lowLevels = [20, 10]

    /// The change worth showing between two readings; the first reading only sets the baseline.
    public static func event(from old: PowerState?, to new: PowerState, warnLow: Bool) -> PowerEvent? {
        guard let old else { return nil }
        if new.onAC && !old.onAC { return .connected(level: new.level) }
        if !new.onAC && old.onAC { return .disconnected(level: new.level, minutesLeft: new.minutesToEmpty) }
        if new.onAC && new.charged && !old.charged { return .charged }
        if warnLow && !new.onAC, lowLevels.contains(where: { old.level > $0 && new.level <= $0 }) { return .low(level: new.level) }
        return nil
    }
}
