import Foundation

public enum LevelKind: Sendable { case volume, brightness }

/// A volume or brightness change shown on the island in place of the macOS HUD.
public struct SystemLevel: Equatable, Sendable {
    public let kind: LevelKind
    /// Zero to one.
    public let value: Double
    public let muted: Bool

    public init(kind: LevelKind, value: Double, muted: Bool = false) {
        self.kind = kind
        self.value = min(1, max(0, value.isFinite ? value : 0))
        self.muted = muted
    }

    /// What the bar shows: a muted output reads as empty.
    public var shown: Double { muted ? 0 : value }
}

/// The special keys the island takes over.
public enum MediaKey: Equatable, Sendable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown

    public var kind: LevelKind {
        switch self { case .volumeUp, .volumeDown, .mute: return .volume; case .brightnessUp, .brightnessDown: return .brightness }
    }

    /// Reads an NX_SYSDEFINED event: subtype 8 carries the key in the high half of data1 and
    /// the state in the low half (0xA down, 0xB up; bit 0 marks a repeat). Nil for other keys.
    public static func decode(subtype: Int, data1: Int) -> (key: MediaKey, down: Bool, isRepeat: Bool)? {
        guard subtype == 8 else { return nil }
        let code = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        guard state == 0xA || state == 0xB else { return nil }
        let key: MediaKey
        switch code {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        case 7: key = .mute
        default: return nil
        }
        return (key, state == 0xA, flags & 0x1 == 1)
    }

}

public enum LevelStep {
    /// Sixteen steps like the macOS HUD; with Shift and Option, four times finer.
    public static func next(_ value: Double, up: Bool, fine: Bool = false) -> Double {
        let steps = fine ? 64.0 : 16.0
        // Snap to the grid first so an odd value lands on the next mark, not past it.
        let position = (min(1, max(0, value)) * steps)
        let snapped = up ? floor(position + 0.001) + 1 : ceil(position - 0.001) - 1
        return min(1, max(0, snapped / steps))
    }

    /// Filled segments out of sixteen.
    public static func segments(_ value: Double) -> Int { Int((min(1, max(0, value)) * 16).rounded()) }
}
