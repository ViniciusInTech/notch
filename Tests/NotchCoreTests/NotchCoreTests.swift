import Foundation
import Testing
@testable import NotchCore

struct NotchCoreTests {
    @Test func testOutwardShouldersPreserveBodyAndFitSmallScreens() {
        let layout = IslandLayout(notchWidth: 180, notchHeight: 32, screenWidth: 1512)
        #expect(layout.outerSize(active: false, expanded: false).width == 204)
        #expect(layout.outerSize(active: true, expanded: true).width == 484)
        let small = IslandLayout(notchWidth: 180, notchHeight: 32, screenWidth: 320)
        #expect(small.outerSize(active: true, expanded: true).width <= 304)
        #expect(small.outerSize(active: true, expanded: true).height == 128)
    }
    @Test func testAlbumAccentUsesDominantColorAndIgnoresTransparentPixels() {
        let pixels: [UInt8] = [220, 45, 30, 255, 220, 45, 30, 255, 20, 60, 220, 255, 0, 255, 0, 0]
        let accent = ArtworkPalette.dominantColor(inRGBA: pixels)
        #expect(accent.red > accent.green * 2)
        #expect(accent.red > accent.blue * 2)
    }

    @Test func testAlbumAccentRemainsVisibleOnBlackAndHandlesMissingPixels() {
        let accent = ArtworkPalette.dominantColor(inRGBA: [40, 10, 5, 255])
        #expect(max(accent.red, accent.green, accent.blue) >= 0.7)
        #expect(ArtworkPalette.dominantColor(inRGBA: []) == .fallback)
        #expect(ArtworkPalette.dominantColor(inRGBA: [1, 2]) == .fallback)
        #expect(ArtworkPalette.dominantColor(inRGBA: [0, 0, 0, 255]) == .fallback)
    }

    @Test func testActiveIslandOnlyGrowsHorizontally() {
        let layout = IslandLayout(notchWidth: 180, notchHeight: 32, screenWidth: 1512)
        #expect(layout.size(active: false, expanded: false).width == 180)
        #expect(layout.size(active: true, expanded: false).width == 284)
        #expect(layout.size(active: true, expanded: false).height == 32)
        #expect(layout.size(active: false, expanded: false).height == 32)
        #expect(layout.size(active: true, expanded: true).height == 128)
    }

    @Test func testExpandedPanelIsCompactAndCanFitTwoActivitiesAtRest() {
        let layout = IslandLayout(notchWidth: 180, notchHeight: 32, screenWidth: 1512)
        let size = layout.size(active: true, expanded: true)
        #expect(size.width == 460)
        #expect(size.height == 128)
        #expect(layout.size(active: true, expanded: false, activityCount: 2).width == 364)
        #expect(layout.size(active: true, expanded: false, activityCount: 2).height == 32)
        #expect(layout.size(active: false, expanded: true).width == size.width)
        #expect(layout.size(active: false, expanded: true).height == size.height)
    }

    @Test func testActivitiesKeepTheirStartOrderAndReappendAfterStopping() {
        var order = ActivityOrder()
        order.update(music: false, timer: true)
        order.update(music: true, timer: true)
        #expect(order.items == [.timer, .music])
        order.update(music: true, timer: false)
        order.update(music: true, timer: true)
        #expect(order.items == [.music, .timer])
        order.update(music: false, timer: false)
        #expect(order.items.isEmpty)
    }

    @Test func testPomodoroOffersShortBreaksThenLongBreakAfterFourSessions() {
        var cycle = PomodoroCycle()
        #expect(cycle.phase == .work)
        #expect(cycle.phase.minutes == 25)
        for completed in 1...4 {
            cycle.complete()
            #expect(cycle.completedSessions == completed)
            #expect(cycle.phase == (completed == 4 ? .longBreak : .shortBreak))
            cycle.complete()
            #expect(cycle.phase == .work)
        }
        #expect(PomodoroPhase.shortBreak.minutes == 5)
        #expect(PomodoroPhase.longBreak.minutes == 15)
    }

    @Test func testOffersMoveOnlyForDownloadedCopies() {
        let home = "/Users/ana"
        #expect(InstallLocation.shouldOfferMove(bundlePath: "/Volumes/Notch/Notch.app", homeDirectory: home))
        #expect(InstallLocation.shouldOfferMove(bundlePath: "/Users/ana/Downloads/Notch.app", homeDirectory: home))
        #expect(InstallLocation.shouldOfferMove(bundlePath: "/private/var/folders/x/AppTranslocation/ABC/d/Notch.app", homeDirectory: home))
        #expect(!InstallLocation.shouldOfferMove(bundlePath: "/Applications/Notch.app", homeDirectory: home))
        #expect(!InstallLocation.shouldOfferMove(bundlePath: "/Users/ana/Applications/Notch.app", homeDirectory: home))
        #expect(!InstallLocation.shouldOfferMove(bundlePath: "/Users/ana/Develop/notch/dist/Notch.app", homeDirectory: home))
        #expect(InstallLocation.mountedVolume(bundlePath: "/Volumes/Notch 1/Notch.app") == "/Volumes/Notch 1")
        #expect(InstallLocation.mountedVolume(bundlePath: "/Users/ana/Downloads/Notch.app") == nil)
    }

    @Test func testExpandedWidthFitsSmallScreen() {
        let layout = IslandLayout(notchWidth: 180, notchHeight: 32, screenWidth: 320)
        #expect(layout.size(active: true, expanded: true).width <= 304)
    }

    @Test func testPlayingBrowserWinsOverPausedSpotify() {
        let spotify = snapshot(source: .spotify, playing: false)
        let browser = snapshot(source: .chrome, playing: true)
        #expect(MediaSelection.choose(spotify: spotify, browser: browser)?.source == .chrome)
    }

    @Test func testSpotifyWinsWhenBothPlayAndPausedMediaStaysAvailable() {
        let spotify = snapshot(source: .spotify, playing: true)
        #expect(MediaSelection.choose(spotify: spotify, browser: snapshot(source: .safari, playing: true))?.source == .spotify)
        #expect(MediaSelection.choose(spotify: snapshot(source: .spotify, playing: false), browser: nil)?.source == .spotify)
    }

    @Test func testProgressIsEstimatedAndClamped() {
        let date = Date(timeIntervalSince1970: 100)
        var media = snapshot(source: .spotify, playing: true)
        media.position = 98
        media.duration = 100
        media.updatedAt = date
        #expect(media.position(at: date.addingTimeInterval(20)) == 100)
        media.isPlaying = false
        #expect(media.position(at: date.addingTimeInterval(20)) == 98)
    }

    @Test func testCountdownPauseResumeAndSleep() {
        let now = Date(timeIntervalSince1970: 100)
        var timer = Countdown()
        timer.start(seconds: 60, at: now)
        #expect(timer.remaining(at: now.addingTimeInterval(10)) == 50)
        timer.pause(at: now.addingTimeInterval(10))
        #expect(timer.remaining(at: now.addingTimeInterval(200)) == 50)
        timer.resume(at: now.addingTimeInterval(200))
        #expect(timer.remaining(at: now.addingTimeInterval(230)) == 20)
        let completed = timer.completeIfNeeded(at: now.addingTimeInterval(300))
        let completedTwice = timer.completeIfNeeded(at: now.addingTimeInterval(301))
        #expect(completed)
        #expect(!completedTwice)
        #expect(!(timer.isActive))
    }

    @Test func testInvalidTimerDoesNotStartAndCancelClearsState() {
        var timer = Countdown()
        timer.start(seconds: -.infinity)
        #expect(!(timer.isActive))
        timer.start(seconds: .nan)
        #expect(!(timer.isActive))
        timer.start(seconds: 90)
        timer.cancel()
        #expect(timer.remaining() == 0)
        #expect(!(timer.isActive))
    }

    private func snapshot(source: MediaSource, playing: Bool) -> MediaSnapshot {
        MediaSnapshot(source: source, title: "Song", artist: "Artist", isPlaying: playing)
    }

    @Test func testSpotifyResponseParsingAndInvalidPayload() throws {
        let raw = ["playing", "Song", "Artist", "240000", "12.5", "65", "https://example.com/cover.jpg"].joined(separator: "\u{1F}")
        let media = try #require(MediaParser.spotify(raw))
        #expect(media.duration == 240)
        #expect(media.position == 12.5)
        #expect(media.volume == 0.65)
        #expect(media.isPlaying)
        #expect(MediaParser.spotify("stopped") == nil)
        #expect(MediaParser.spotify("bad input") == nil)
    }

    @Test func testBrowserResponseLiveStreamAndInvalidPayload() throws {
        let raw = #"{"title":"Live","artist":"Channel","duration":null,"position":10,"isPlaying":true,"volume":0.4,"canSkip":false}"#
        let media = try #require(MediaParser.browser(raw, source: .safari))
        #expect(media.duration == 0)
        #expect(!media.canSeek)
        #expect(media.isPlaying)
        #expect(MediaParser.browser("null", source: .chrome) == nil)
        #expect(MediaParser.browser("not json", source: .chrome) == nil)
    }

    @Test func testSpotifyPositionSupportsDecimalCommaFromAppleScriptLocale() throws {
        let raw = ["playing", "Song", "Artist", "240000", "12,5", "65", ""].joined(separator: "\u{1F}")
        let media = try #require(MediaParser.spotify(raw))
        #expect(media.position == 12.5)
    }

    @Test func testPausedTimerCannotFinishUntilResumed() {
        let now = Date(timeIntervalSince1970: 100)
        var timer = Countdown()
        timer.start(seconds: 30, at: now)
        timer.pause(at: now.addingTimeInterval(5))
        let completed = timer.completeIfNeeded(at: now.addingTimeInterval(1000))
        #expect(!completed)
        #expect(timer.isActive)
        #expect(timer.remaining() == 25)
    }
}
