import Foundation
import NotchCore

enum MediaCommand {
    case togglePlayback, previous, next, volume(Double), seek(Double)
}

struct SpotifyProvider {
    let runner: AutomationRunner

    func snapshot() async throws -> MediaSnapshot? {
        let output = try await runner.run("""
        if application id "com.spotify.client" is not running then return "stopped"
        tell application id "com.spotify.client"
            if player state is stopped then return "stopped"
            set playback to player state as string
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackDuration to duration of current track
            set trackPosition to player position
            set trackVolume to sound volume
            set coverURL to artwork url of current track
        end tell
        set AppleScript's text item delimiters to ASCII character 31
        return {playback, trackName, trackArtist, trackDuration, trackPosition, trackVolume, coverURL} as text
        """)
        return MediaParser.spotify(output)
    }

    func perform(_ command: MediaCommand) async throws {
        let operation: String
        switch command {
        case .togglePlayback: operation = "playpause"
        case .previous: operation = "previous track"
        case .next: operation = "next track"
        case .volume(let value):
            guard value.isFinite else { return }
            operation = "set sound volume to \(Int(min(1, max(0, value)) * 100))"
        case .seek(let seconds):
            guard seconds.isFinite else { return }
            operation = "set player position to \(max(0, seconds))"
        }
        _ = try await runner.run("""
        if application id "com.spotify.client" is not running then return
        tell application id "com.spotify.client" to \(operation)
        """)
    }
}
