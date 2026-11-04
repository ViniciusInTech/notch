import Foundation

public enum MediaSource: String, Codable, CaseIterable, Sendable {
    /// The macOS Now Playing session, whichever app owns it.
    case system, spotify, safari, chrome

    public var name: String {
        switch self {
        case .system: return "Tocando agora"
        case .spotify: return "Spotify"; case .safari: return "Safari"; case .chrome: return "Google Chrome"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .system: return ""
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
    /// App that owns a system session, such as com.apple.Music.
    public var playerBundle: String?
    /// Identifies cover bytes delivered beside the snapshot instead of a URL.
    public var artworkKey: String?
    public var canSeek: Bool { duration.isFinite && duration > 0 }

    public init(source: MediaSource, title: String, artist: String, isPlaying: Bool,
                duration: Double = 0, position: Double = 0, volume: Double = 0.5,
                artworkURL: URL? = nil, canSkip: Bool = true, updatedAt: Date = Date(),
                playerBundle: String? = nil, artworkKey: String? = nil) {
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
        self.playerBundle = playerBundle
        self.artworkKey = artworkKey
    }

    public func position(at date: Date) -> Double {
        let elapsed = isPlaying ? max(0, date.timeIntervalSince(updatedAt)) : 0
        let estimate = position + elapsed
        return duration > 0 ? min(duration, estimate) : estimate
    }
}

public enum MediaSelection {
    public static func choose(system: MediaSnapshot? = nil, spotify: MediaSnapshot?, browser: MediaSnapshot?) -> MediaSnapshot? {
        if system?.isPlaying == true { return system }
        if spotify?.isPlaying == true { return spotify }
        if browser?.isPlaying == true { return browser }
        return system ?? spotify ?? browser
    }
}

/// One line from the Now Playing bridge: the session, or nil when nothing plays.
public struct NowPlayingUpdate: Equatable, Sendable {
    public var media: MediaSnapshot?
    public var artwork: Data?

    public init(media: MediaSnapshot?, artwork: Data? = nil) {
        self.media = media
        self.artwork = artwork
    }
}

public enum MediaParser {
    public static func nowPlaying(_ line: String) -> NowPlayingUpdate? {
        struct Payload: Decodable {
            let empty: Bool?
            let title: String?
            let artist: String?
            let album: String?
            let duration: Double?
            let elapsed: Double?
            let rate: Double?
            let timestamp: Double?
            let playing: Bool?
            let bundle: String?
            let artwork: String?
            let artworkId: Int?
        }
        guard let data = line.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        if payload.empty == true { return NowPlayingUpdate(media: nil) }
        let title = String((payload.title ?? "").prefix(200))
        guard !title.isEmpty else { return NowPlayingUpdate(media: nil) }
        let artist = payload.artist.flatMap { $0.isEmpty ? nil : $0 } ?? payload.album ?? ""
        let playing = payload.playing ?? ((payload.rate ?? 0) > 0)
        let stamp = payload.timestamp.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil } ?? Date()
        let media = MediaSnapshot(source: .system, title: title, artist: String(artist.prefix(200)), isPlaying: playing,
                                  duration: payload.duration ?? 0, position: payload.elapsed ?? 0,
                                  updatedAt: min(stamp, Date()), playerBundle: payload.bundle,
                                  artworkKey: payload.artworkId.map { "nowplaying-\($0)" })
        return NowPlayingUpdate(media: media, artwork: payload.artwork.flatMap { Data(base64Encoded: $0) })
    }


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
