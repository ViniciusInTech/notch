import Foundation

/// A keep-awake period: an absolute deadline, or none until switched off.
public struct KeepAwakeSession: Equatable, Sendable {
    public let start: Date
    public let deadline: Date?
    /// Chosen duration; zero without a limit.
    public let minutes: Int
    public var isIndefinite: Bool { deadline == nil }

    /// Zero or fewer minutes means no time limit.
    public init(minutes: Int, at now: Date = Date()) {
        start = now
        self.minutes = max(0, min(minutes, KeepAwakeUnit.maximumMinutes))
        deadline = minutes > 0 ? now.addingTimeInterval(Double(min(minutes, KeepAwakeUnit.maximumMinutes)) * 60) : nil
    }

    public func remaining(at now: Date = Date()) -> TimeInterval? {
        deadline.map { max(0, $0.timeIntervalSince(now)) }
    }

    /// Remaining share of the period; a full ring without a limit.
    public func progress(at now: Date = Date()) -> Double {
        guard let deadline else { return 1 }
        let total = deadline.timeIntervalSince(start)
        return total > 0 ? max(0, deadline.timeIntervalSince(now)) / total : 0
    }

    public func isExpired(at now: Date = Date()) -> Bool { deadline.map { $0 <= now } ?? false }
}

public enum KeepAwakeUnit: String, CaseIterable, Sendable {
    case minutes, hours, days

    /// Thirty days; longer periods are better served by the system's own energy settings.
    public static let maximumMinutes = 43_200

    public var factor: Int {
        switch self { case .minutes: return 1; case .hours: return 60; case .days: return 1440 }
    }

    public var maximumQuantity: Int { Self.maximumMinutes / factor }

    public func minutes(_ quantity: Int) -> Int { min(maximumQuantity, max(1, quantity)) * factor }
}

public enum KeepAwakePresets {
    public static let defaults = [15, 30, 60, 120, 240]
    public static let maximumCount = 5
    public static let range = 5...1440

    /// Sorted, unique, clamped and at most five; quick access keeps one row in the island.
    public static func normalized(_ minutes: [Int]) -> [Int] {
        let clamped = minutes.map { min(range.upperBound, max(range.lowerBound, $0)) }
        return Array(Set(clamped).sorted().prefix(maximumCount))
    }

    /// Five-minute steps up to an hour, fifteen up to twelve hours, then hourly.
    public static func step(_ minutes: Int, up: Bool) -> Int {
        let size: Int
        if up { size = minutes < 60 ? 5 : minutes < 720 ? 15 : 60 }
        else { size = minutes <= 60 ? 5 : minutes <= 720 ? 15 : 60 }
        let next = up ? (minutes / size + 1) * size : ((minutes + size - 1) / size - 1) * size
        return min(range.upperBound, max(range.lowerBound, next))
    }

    /// A preset after the last one, for "add": double it, or the next step when doubling overflows.
    public static func next(after presets: [Int]) -> Int {
        guard let last = presets.max() else { return 30 }
        return last * 2 <= range.upperBound ? last * 2 : step(last, up: true)
    }
}

public enum KeepAwakeFormat {
    /// "15 min", "1 h", "1 h 30 min", "2 dias".
    public static func label(minutes: Int) -> String {
        if minutes >= 1440 && minutes % 1440 == 0 { return minutes == 1440 ? "1 dia" : "\(minutes / 1440) dias" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// Chip in the island's quick-access row: "15 min", "2 h", "1h30", "3 d".
    public static func chip(minutes: Int) -> String {
        if minutes >= 1440 && minutes % 1440 == 0 { return "\(minutes / 1440) d" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : String(format: "%dh%02d", minutes / 60, minutes % 60)
    }

    /// Large clock in the panel: "58:12", "1:59:30" or "2 d 3 h".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? ceil(seconds) : 0))
        if total >= 86_400 { return "\(total / 86_400) d \((total % 86_400) / 3600) h" }
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Collapsed ear: seconds only under an hour, so the narrow ear never overflows.
    public static func compact(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? ceil(seconds) : 0))
        if total >= 86_400 { return "\(total / 86_400)d \((total % 86_400) / 3600)h" }
        if total >= 3600 { return String(format: "%dh%02d", total / 3600, (total / 60) % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
