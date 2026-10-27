public enum IslandActivity: String, Equatable, Sendable {
    case music, timer
}

public struct ActivityOrder: Equatable, Sendable {
    public private(set) var items: [IslandActivity] = []
    public init() {}

    public mutating func update(music: Bool, timer: Bool) {
        let active: [IslandActivity] = (music ? [.music] : []) + (timer ? [.timer] : [])
        items.removeAll { !active.contains($0) }
        for activity in active where !items.contains(activity) { items.append(activity) }
    }
}
