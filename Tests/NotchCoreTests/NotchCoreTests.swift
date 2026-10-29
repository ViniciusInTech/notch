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

    @Test func testPomodoroOffersShortBreaksThenLongBreakAfterConfiguredSessions() {
        var cycle = PomodoroCycle()
        let settings = PomodoroSettings()
        #expect(cycle.phase == .work)
        #expect(settings.minutes(for: .work) == 25)
        #expect(settings.minutes(for: .shortBreak) == 5)
        #expect(settings.minutes(for: .longBreak) == 15)
        for completed in 1...3 {
            var finished = cycle.complete(sessions: 3)
            #expect(!finished)
            #expect(cycle.completedSessions == completed)
            #expect(cycle.phase == (completed == 3 ? .longBreak : .shortBreak))
            if completed < 3 {
                finished = cycle.complete(sessions: 3)
                #expect(!finished)
                #expect(cycle.phase == .work)
            }
        }
        let finished = cycle.complete(sessions: 3)
        #expect(finished)
        #expect(cycle.phase == .work)
        #expect(cycle.completedSessions == 0)
    }

    @Test func testPomodoroSettingsClampValues() {
        let settings = PomodoroSettings(focusMinutes: 0, shortBreakMinutes: -2, longBreakMinutes: 0, sessions: 40)
        #expect(settings.minutes(for: .work) == 1)
        #expect(settings.minutes(for: .shortBreak) == 1)
        #expect(settings.sessions == PomodoroSettings.sessionRange.upperBound)
        var cycle = PomodoroCycle()
        cycle.complete(sessions: 1)
        #expect(cycle.phase == .longBreak)
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

    @Test func testAgentPermissionRequestBecomesIslandEvent() throws {
        let payload = Data(#"{"hook_event_name":"PermissionRequest","cwd":"/Users/ana/notch","tool_name":"Bash","tool_input":{"command":"npm test\n  --watch","description":"Run"}}"#.utf8)
        let event = try #require(AgentHook.event(agent: .claude, payload: payload))
        #expect(event.kind == .permission)
        #expect(event.tool == "Bash")
        #expect(event.detail == "npm test --watch")
        #expect(event.project == "notch")
        let codex = AgentHook.event(agent: .codex, payload: payload)
        #expect(codex?.kind == .permission)
        #expect(AgentHook.event(agent: .cursor, payload: payload) == nil)
    }

    @Test func testAgentCompletionsSkipLoopsAndAborts() throws {
        let stop = Data(#"{"hook_event_name":"Stop","cwd":"/tmp/app","last_assistant_message":"Pronto.\n\nTestes passam."}"#.utf8)
        #expect(AgentHook.event(agent: .claude, payload: stop)?.detail == "Pronto. Testes passam.")
        let loop = Data(#"{"hook_event_name":"Stop","stop_hook_active":true}"#.utf8)
        #expect(AgentHook.event(agent: .codex, payload: loop) == nil)
        let cursor = Data(#"{"hook_event_name":"stop","status":"completed","workspace_roots":["/Users/ana/site"]}"#.utf8)
        let event = try #require(AgentHook.event(agent: .cursor, payload: cursor))
        #expect(event.kind == .completion)
        #expect(event.project == "site")
        let aborted = Data(#"{"hook_event_name":"stop","status":"aborted"}"#.utf8)
        #expect(AgentHook.event(agent: .cursor, payload: aborted) == nil)
        #expect(AgentHook.event(agent: .claude, payload: Data("not json".utf8)) == nil)
    }

    @Test func testAgentDecisionMatchesHookOutput() throws {
        let allow = try #require(JSONSerialization.jsonObject(with: AgentHook.response(.allow)) as? [String: Any])
        let output = try #require(allow["hookSpecificOutput"] as? [String: Any])
        #expect(output["hookEventName"] as? String == "PermissionRequest")
        #expect((output["decision"] as? [String: Any])?["behavior"] as? String == "allow")
        let deny = String(decoding: AgentHook.response(.deny(nil)), as: UTF8.self)
        #expect(deny.contains(#""behavior":"deny""#))
        let instructed = String(decoding: AgentHook.response(.deny("Use pnpm")), as: UTF8.self)
        #expect(instructed.contains(#""message":"Use pnpm""#))
        let long = AgentHook.clean(String(repeating: "a", count: 1000))
        #expect(long.count == AgentHook.detailLimit)
    }

    @Test func testAgentQuestionIsAnsweredThroughUpdatedInput() throws {
        let payload = Data(#"{"hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Qual banco?","header":"Banco","multiSelect":false,"options":[{"label":"Postgres","description":"Relacional"},{"label":"SQLite"}]}]}}"#.utf8)
        let event = try #require(AgentHook.event(agent: .claude, payload: payload))
        #expect(event.kind == .question)
        #expect(event.questions.first?.options.map(\.label) == ["Postgres", "SQLite"])
        #expect(event.questions.first?.header == "Banco")
        let output = try #require(JSONSerialization.jsonObject(with: AgentHook.response(.answer(["Qual banco?": "SQLite"]), for: event)) as? [String: Any])
        let decision = try #require((output["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "allow")
        let input = try #require(decision["updatedInput"] as? [String: Any])
        #expect((input["answers"] as? [String: String])?["Qual banco?"] == "SQLite")
        #expect((input["questions"] as? [Any])?.count == 1)
    }

    @Test func testPlanApprovalKeepsMoreText() throws {
        let plan = String(repeating: "passo ", count: 150)
        let payload = try JSONSerialization.data(withJSONObject: ["hook_event_name": "PermissionRequest", "tool_name": "ExitPlanMode", "tool_input": ["plan": plan]])
        let event = try #require(AgentHook.event(agent: .claude, payload: payload))
        #expect(event.kind == .permission)
        #expect(event.detail.count > AgentHook.detailLimit)
    }

    @Test func testCompositionPlacesBubbleAndCardBesideCenteredIsland() {
        let island = IslandSize(width: 300, height: 32)
        let plain = IslandComposition(island: island, notchHeight: 32)
        #expect(plain.halfWidth == 150)
        #expect(plain.height == 32)
        let bubble = IslandComposition(island: island, notchHeight: 32, bubbleSize: 30)
        #expect(bubble.bubbleMinX == 158)
        #expect(bubble.halfWidth == 196)
        #expect(bubble.bubbleMinY == 1)
        #expect(bubble.region(x: 170, y: 10) == .bubble)
        #expect(bubble.region(x: 0, y: 0) == .island)
        #expect(bubble.region(x: 0, y: 40) == nil)
        let card = IslandComposition(island: island, notchHeight: 32, bubbleSize: 30, card: IslandSize(width: 420, height: 200))
        #expect(card.cardMinX == 188 - 420)
        #expect(card.halfWidth == 232)
        #expect(card.height == 240)
        #expect(card.region(x: 0, y: 100) == .card)
        let centered = IslandComposition(island: island, notchHeight: 32, card: IslandSize(width: 420, height: 100))
        #expect(centered.cardMinX == -210)
        #expect(centered.halfWidth == 210)
    }

    @Test func testKeepAwakeSessionExpiresAtDeadlineOrNeverWithoutLimit() {
        let now = Date(timeIntervalSince1970: 1_000)
        let timed = KeepAwakeSession(minutes: 30, at: now)
        #expect(timed.remaining(at: now.addingTimeInterval(600)) == 1200)
        #expect(abs(timed.progress(at: now.addingTimeInterval(900)) - 0.5) < 0.0001)
        #expect(!timed.isExpired(at: now.addingTimeInterval(1799)))
        #expect(timed.isExpired(at: now.addingTimeInterval(1800)))
        let open = KeepAwakeSession(minutes: 0, at: now)
        #expect(open.isIndefinite && open.minutes == 0)
        #expect(open.remaining(at: now) == nil)
        #expect(open.progress(at: now.addingTimeInterval(1e6)) == 1)
        #expect(!open.isExpired(at: now.addingTimeInterval(1e9)))
        #expect(KeepAwakeSession(minutes: 999_999, at: now).minutes == KeepAwakeUnit.maximumMinutes)
    }

    @Test func testKeepAwakeCustomUnitsConvertAndClampToThirtyDays() {
        #expect(KeepAwakeUnit.minutes.minutes(45) == 45)
        #expect(KeepAwakeUnit.hours.minutes(3) == 180)
        #expect(KeepAwakeUnit.days.minutes(2) == 2880)
        #expect(KeepAwakeUnit.days.minutes(90) == 43_200)
        #expect(KeepAwakeUnit.hours.minutes(0) == 60)
    }

    @Test func testKeepAwakePresetsStayOrderedUniqueAndStepByScale() {
        #expect(KeepAwakePresets.normalized([240, 15, 15, 1, 5000, 60, 30]) == [5, 15, 30, 60, 240])
        #expect(KeepAwakePresets.step(55, up: true) == 60)
        #expect(KeepAwakePresets.step(60, up: true) == 75)
        #expect(KeepAwakePresets.step(60, up: false) == 55)
        #expect(KeepAwakePresets.step(65, up: false) == 60)
        #expect(KeepAwakePresets.step(720, up: true) == 780)
        #expect(KeepAwakePresets.step(5, up: false) == 5)
        #expect(KeepAwakePresets.step(1440, up: true) == 1440)
        #expect(KeepAwakePresets.next(after: [15, 30, 60]) == 120)
        #expect(KeepAwakePresets.next(after: [1000]) == 1020)
    }

    @Test func testKeepAwakeLabelsFitChipsAndEars() {
        #expect(KeepAwakeFormat.label(minutes: 15) == "15 min")
        #expect(KeepAwakeFormat.label(minutes: 90) == "1 h 30 min")
        #expect(KeepAwakeFormat.label(minutes: 2880) == "2 dias")
        #expect(KeepAwakeFormat.chip(minutes: 90) == "1h30")
        #expect(KeepAwakeFormat.chip(minutes: 120) == "2 h")
        #expect(KeepAwakeFormat.chip(minutes: 4320) == "3 d")
        #expect(KeepAwakeFormat.clock(3492) == "58:12")
        #expect(KeepAwakeFormat.clock(7170) == "1:59:30")
        #expect(KeepAwakeFormat.clock(97_200) == "1 d 3 h")
        #expect(KeepAwakeFormat.compact(1450) == "24:10")
        #expect(KeepAwakeFormat.compact(5040) == "1h24")
        #expect(KeepAwakeFormat.compact(183_600) == "2d 3h")
    }
}
