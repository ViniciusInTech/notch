public enum PomodoroPhase: String, CaseIterable, Sendable {
    case work, shortBreak, longBreak

    public var minutes: Int {
        switch self { case .work: return 25; case .shortBreak: return 5; case .longBreak: return 15 }
    }

    public var title: String {
        switch self { case .work: return "Sessão"; case .shortBreak: return "Pausa curta"; case .longBreak: return "Pausa longa" }
    }
}

public struct PomodoroCycle: Equatable, Sendable {
    public private(set) var phase: PomodoroPhase = .work
    public private(set) var completedSessions = 0
    public init() {}

    public mutating func select(_ phase: PomodoroPhase) { self.phase = phase }

    public mutating func complete() {
        if phase == .work {
            completedSessions += 1
            phase = completedSessions.isMultiple(of: 4) ? .longBreak : .shortBreak
        } else { phase = .work }
    }
}
