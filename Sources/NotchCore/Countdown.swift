import Foundation

public struct Countdown: Equatable, Sendable {
    public private(set) var deadline: Date?
    public private(set) var pausedRemaining: TimeInterval?
    public var isActive: Bool { deadline != nil || pausedRemaining != nil }
    public var isPaused: Bool { pausedRemaining != nil }
    public init() {}

    public mutating func start(seconds: TimeInterval, at now: Date = Date()) {
        guard seconds.isFinite, seconds > 0 else { return }
        pausedRemaining = nil
        deadline = now.addingTimeInterval(min(seconds, 86400))
    }

    public func remaining(at now: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        return max(0, deadline?.timeIntervalSince(now) ?? 0)
    }

    public mutating func pause(at now: Date = Date()) {
        guard deadline != nil else { return }
        pausedRemaining = remaining(at: now)
        deadline = nil
    }

    public mutating func resume(at now: Date = Date()) {
        guard let pausedRemaining else { return }
        deadline = now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
    }

    @discardableResult public mutating func completeIfNeeded(at now: Date = Date()) -> Bool {
        guard let deadline, deadline <= now else { return false }
        cancel()
        return true
    }

    public mutating func cancel() { deadline = nil; pausedRemaining = nil }
}
