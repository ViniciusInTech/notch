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
    /// Space below the notch row: one content row plus the progress or phase row.
    public static let expandedBodyHeight = 96.0
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
        // Expanded ears hold the tab switcher and actions beside the camera.
        let width = expanded ? max(460, notchWidth + 280) : notchWidth + (active ? wings : 0)
        return IslandSize(width: min(width, screenWidth - 16 - 2 * Self.shoulderWidth), height: expanded ? notchHeight + Self.expandedBodyHeight : notchHeight)
    }

    public func outerSize(active: Bool, expanded: Bool, activityCount: Int = 1) -> IslandSize {
        let body = size(active: active, expanded: expanded, activityCount: activityCount)
        return IslandSize(width: body.width + 2 * Self.shoulderWidth, height: body.height)
    }
}

/// Island plus the assistant bubble beside it and the mini chat below, measured from the
/// notch center (x) and the screen top (y). The window is symmetric so the island stays centered.
public struct IslandComposition: Equatable, Sendable {
    public static let bubbleGap = 8.0
    public static let cardGap = 8.0
    public let island: IslandSize
    public let notchHeight: Double
    /// Zero when no bubble is shown.
    public let bubbleSize: Double
    public let card: IslandSize?

    public init(island: IslandSize, notchHeight: Double, bubbleSize: Double = 0, card: IslandSize? = nil) {
        self.island = island
        self.notchHeight = notchHeight
        self.bubbleSize = max(0, bubbleSize)
        self.card = card
    }

    public var bubbleMinX: Double { island.width / 2 + Self.bubbleGap }
    public var bubbleMinY: Double { max(0, (notchHeight - bubbleSize) / 2) }
    /// Under the bubble, sharing its right edge; centered under the island without one.
    public var cardMinX: Double {
        guard let card else { return 0 }
        return bubbleSize > 0 ? bubbleMinX + bubbleSize - card.width : -card.width / 2
    }
    public var cardMinY: Double { notchHeight + Self.cardGap }

    public var halfWidth: Double {
        var half = island.width / 2
        if bubbleSize > 0 { half = max(half, bubbleMinX + bubbleSize + 8) }  // room for the badge
        if let card { half = max(half, cardMinX + card.width, -cardMinX) }
        return half
    }

    public var height: Double { max(island.height, card.map { cardMinY + $0.height } ?? 0) }

    public enum Region: Sendable { case island, bubble, card }

    /// Region under a point given relative to the notch center and the screen top (y grows down).
    public func region(x: Double, y: Double, margin: Double = 0) -> Region? {
        if let card, x >= cardMinX - margin, x <= cardMinX + card.width + margin, y >= cardMinY - margin, y <= cardMinY + card.height + margin { return .card }
        if bubbleSize > 0, x >= bubbleMinX - margin, x <= bubbleMinX + bubbleSize + margin, y <= bubbleMinY + bubbleSize + margin { return .bubble }
        if abs(x) <= island.width / 2 + margin, y <= island.height + margin { return .island }
        return nil
    }
}
