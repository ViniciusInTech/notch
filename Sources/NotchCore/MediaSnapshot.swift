import Foundation

public enum MediaSource: String, Codable, CaseIterable, Sendable {
    case spotify, safari, chrome

    public var name: String {
        switch self { case .spotify: return "Spotify"; case .safari: return "Safari"; case .chrome: return "Google Chrome" }
    }

    public var bundleIdentifier: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        }
    }
}

public struct MediaSnapshot: Equatable, Sendable {
    public var source: MediaSource
    public var title: String
    public var artist: String
    public var isPlaying: Bool
    public var duration: Double
    public var position: Double
    public var volume: Double
    public var artworkURL: URL?
    public var canSkip: Bool
    public var updatedAt: Date
    public var canSeek: Bool { duration.isFinite && duration > 0 }

    public init(source: MediaSource, title: String, artist: String, isPlaying: Bool,
                duration: Double = 0, position: Double = 0, volume: Double = 0.5,
                artworkURL: URL? = nil, canSkip: Bool = true, updatedAt: Date = Date()) {
        self.source = source
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.position = position.isFinite ? max(0, position) : 0
        self.volume = volume.isFinite ? min(1, max(0, volume)) : 0.5
        self.artworkURL = artworkURL
        self.canSkip = canSkip
        self.updatedAt = updatedAt
    }

    public func position(at date: Date) -> Double {
        let elapsed = isPlaying ? max(0, date.timeIntervalSince(updatedAt)) : 0
        let estimate = position + elapsed
        return duration > 0 ? min(duration, estimate) : estimate
    }
}

public enum MediaSelection {
    public static func choose(spotify: MediaSnapshot?, browser: MediaSnapshot?) -> MediaSnapshot? {
        if spotify?.isPlaying == true { return spotify }
        if browser?.isPlaying == true { return browser }
        return spotify ?? browser
    }
}

public enum MediaParser {
    public static func spotify(_ raw: String) -> MediaSnapshot? {
        let parts = raw.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1F}")
        guard parts.count == 7, ["playing", "paused"].contains(parts[0]),
              let duration = Double(parts[3]), let position = Double(parts[4].replacingOccurrences(of: ",", with: ".")),
              let volume = Double(parts[5]), duration.isFinite, position.isFinite, volume.isFinite else { return nil }
        return MediaSnapshot(source: .spotify, title: parts[1], artist: parts[2], isPlaying: parts[0] == "playing",
                             duration: duration / 1000, position: position, volume: volume / 100,
                             artworkURL: URL(string: parts[6]))
    }

    public static func browser(_ raw: String, source: MediaSource) -> MediaSnapshot? {
        struct Payload: Decodable {
            let title: String
            let artist: String
            let duration: Double?
            let position: Double
            let isPlaying: Bool
            let volume: Double
            let canSkip: Bool
        }
        guard let data = raw.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return MediaSnapshot(source: source, title: payload.title, artist: payload.artist,
                             isPlaying: payload.isPlaying, duration: payload.duration ?? 0,
                             position: payload.position, volume: payload.volume, canSkip: payload.canSkip)
    }
}
