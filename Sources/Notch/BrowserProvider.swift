import Foundation
import NotchCore

struct BrowserProvider {
    let source: MediaSource
    let runner: AutomationRunner

    private var mediaLookup: String {
        """
        const media = Array.from(document.querySelectorAll('video,audio'));
        const m = media.find(x => !x.paused && !x.ended) || media.find(x => x.currentTime > 0);
        """
    }

    func snapshot() async throws -> MediaSnapshot? {
        let script = """
        (() => {
            \(mediaLookup)
            if (!m) return 'null';
            const meta = navigator.mediaSession && navigator.mediaSession.metadata;
            return JSON.stringify({
                title: ((meta && meta.title) || document.title || 'Mídia').slice(0,200),
                artist: ((meta && meta.artist) || location.hostname).slice(0,200),
                duration: Number.isFinite(m.duration) ? m.duration : null,
                position: Number.isFinite(m.currentTime) ? m.currentTime : 0,
                isPlaying: !m.paused && !m.ended,
                volume: m.muted ? 0 : m.volume,
                canSkip: location.hostname === 'www.youtube.com' || location.hostname === 'music.youtube.com'
            });
        })()
        """
        let result = try await evaluate(script)
        return MediaParser.browser(result, source: source)
    }

    func perform(_ command: MediaCommand) async throws {
        let operation: String
        switch command {
        case .togglePlayback: operation = "if (m.paused) { m.play().catch(() => {}); } else { m.pause(); }"
        case .volume(let value):
            guard value.isFinite else { return }
            operation = "m.muted = false; m.volume = \(min(1, max(0, value)));"
        case .seek(let seconds):
            guard seconds.isFinite else { return }
            operation = "if (Number.isFinite(m.duration)) m.currentTime = Math.min(m.duration, \(max(0, seconds)));"
        case .next: operation = "document.querySelector('.ytp-next-button, .next-button')?.click();"
        case .previous: operation = "document.querySelector('.ytp-prev-button, .previous-button')?.click();"
        }
        _ = try await evaluate("(() => { \(mediaLookup) if (!m) return 'null'; \(operation) return 'ok'; })()")
    }

    private func evaluate(_ javaScript: String) async throws -> String {
        let literal = AutomationRunner.literal(javaScript)
        if source == .safari {
            return try await runner.run("""
            if application id "com.apple.Safari" is not running then return "null"
            tell application id "com.apple.Safari"
                if (count of windows) is 0 then return "null"
                return do JavaScript \(literal) in current tab of front window
            end tell
            """)
        }
        return try await runner.run("""
        if application id "com.google.Chrome" is not running then return "null"
        tell application id "com.google.Chrome"
            if (count of windows) is 0 then return "null"
            return execute active tab of front window javascript \(literal)
        end tell
        """)
    }
}
