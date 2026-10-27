import Foundation

public struct IslandSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct IslandLayout: Equatable {
    public static let shoulderWidth = 12.0
    public let notchWidth: Double
    public let notchHeight: Double
    public let screenWidth: Double

    public init(notchWidth: Double, notchHeight: Double, screenWidth: Double) {
        self.notchWidth = max(100, notchWidth)
        self.notchHeight = max(24, notchHeight)
        self.screenWidth = max(200, screenWidth)
    }

    public func size(active: Bool, expanded: Bool, activityCount: Int = 1) -> IslandSize {
        let wings = activityCount > 1 ? 184.0 : 104.0
        let width = expanded ? max(480, notchWidth + 120) : notchWidth + (active ? wings : 0)
        return IslandSize(width: min(width, screenWidth - 16 - 2 * Self.shoulderWidth), height: expanded ? 214 : notchHeight)
    }

    public func outerSize(active: Bool, expanded: Bool, activityCount: Int = 1) -> IslandSize {
        let body = size(active: active, expanded: expanded, activityCount: activityCount)
        return IslandSize(width: body.width + 2 * Self.shoulderWidth, height: body.height)
    }
}
