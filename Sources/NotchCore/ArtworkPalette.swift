public struct ArtworkAccent: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let fallback = ArtworkAccent(red: 0.72, green: 0.72, blue: 0.76)
}

public enum ArtworkPalette {
    /// A small RGBA sample is enough; this runs once per downloaded cover, never per frame.
    public static func dominantColor(inRGBA bytes: [UInt8]) -> ArtworkAccent {
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 4) else { return .fallback }
        struct Bucket {
            var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0, count = 0.0
        }
        var buckets: [Int: Bucket] = [:]
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            guard bytes[offset + 3] >= 200 else { continue }
            let r = Double(bytes[offset]) / 255
            let g = Double(bytes[offset + 1]) / 255
            let b = Double(bytes[offset + 2]) / 255
            let highest = max(r, g, b)
            let lowest = min(r, g, b)
            guard highest > 0.08 else { continue }
            let key = Int(bytes[offset] / 32) * 64 + Int(bytes[offset + 1] / 32) * 8 + Int(bytes[offset + 2] / 32)
            var bucket = buckets[key, default: Bucket()]
            bucket.red += r; bucket.green += g; bucket.blue += b
            bucket.count += 1
            bucket.weight += 1 + (highest - lowest) * 2
            buckets[key] = bucket
        }
        guard let key = buckets.keys.sorted().max(by: { buckets[$0]!.weight < buckets[$1]!.weight }),
              let best = buckets[key] else { return .fallback }
        let r = best.red / best.count, g = best.green / best.count, b = best.blue / best.count
        let brightness = max(r, g, b)
        let boost = max(1, 0.72 / brightness)
        return ArtworkAccent(red: min(1, r * boost), green: min(1, g * boost), blue: min(1, b * boost))
    }
}
