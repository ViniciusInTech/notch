public enum PomodoroPhase: String, CaseIterable, Sendable {
    case work, shortBreak, longBreak

    public var title: String {
        switch self { case .work: return "Sessão"; case .shortBreak: return "Pausa curta"; case .longBreak: return "Pausa longa" }
    }
}

public struct PomodoroSettings: Equatable, Sendable {
    public static let sessionRange = 1...8
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    /// Focus sessions per cycle; the long break follows the last one.
    public var sessions: Int

    public init(focusMinutes: Int = 25, shortBreakMinutes: Int = 5, longBreakMinutes: Int = 15, sessions: Int = 4) {
        self.focusMinutes = max(1, focusMinutes)
        self.shortBreakMinutes = max(1, shortBreakMinutes)
        self.longBreakMinutes = max(1, longBreakMinutes)
        self.sessions = min(Self.sessionRange.upperBound, max(Self.sessionRange.lowerBound, sessions))
    }

    public func minutes(for phase: PomodoroPhase) -> Int {
        switch phase { case .work: return focusMinutes; case .shortBreak: return shortBreakMinutes; case .longBreak: return longBreakMinutes }
    }
}

public struct PomodoroCycle: Equatable, Sendable {
    public private(set) var phase: PomodoroPhase = .work
    public private(set) var completedSessions = 0
    public init() {}

    public mutating func select(_ phase: PomodoroPhase) { self.phase = phase }

    /// Advances to the next phase. Returns true when the long break closes the cycle,
    /// which resets the session count and leaves a new focus session ready.
    @discardableResult public mutating func complete(sessions: Int) -> Bool {
        switch phase {
        case .work:
            completedSessions += 1
            phase = completedSessions >= sessions ? .longBreak : .shortBreak
            return false
        case .shortBreak:
            phase = .work
            return false
        case .longBreak:
            phase = .work
            completedSessions = 0
            return true
        }
    }
}
