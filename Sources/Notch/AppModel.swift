import AppKit
import Combine
import EventKit
import UniformTypeIdentifiers
import UserNotifications
import NotchCore
import os

private let agentLog = Logger(subsystem: "dev.vinicius.Notch", category: "agents")
private let awakeLog = Logger(subsystem: "dev.vinicius.Notch", category: "keepAwake")
private let meetingLog = Logger(subsystem: "dev.vinicius.Notch", category: "meetings")

/// Tabs of the expanded island.
enum IslandPage { case music, timer, keepAwake, shelf }

/// What the compact hover shows: one activity with its controls beside the camera.
enum CompactPanel { case drop, meeting, download, timer, music, keepAwake, shelf }

/// A short-lived message on the collapsed island.
enum IslandNotice: Equatable {
    case screenshot(count: Int, path: String)
    case download(path: String)
    case power(PowerEvent)
}

@MainActor final class AppModel: ObservableObject {
    let preferences = Preferences()
    let login = LoginService()
    let artwork = ArtworkStore()
    let shelf = ShelfStore()
    @Published private(set) var media: MediaSnapshot?
    @Published private(set) var countdown = Countdown()
    @Published private(set) var errors: [MediaSource: String] = [:]
    @Published private(set) var commandBusy = false
    @Published var expanded = false {
        didSet {
            guard expanded != oldValue else { return }
            if !expanded { keepAwakeEditing = false; return }
            compactOpen = false
            if let opening = openingPage { page = opening }
        }
    }

    /// Items placed on the shelf in this window take priority when the island opens.
    static let recentShelfWindow: TimeInterval = 600

    /// The tab to open on: freshly shelved items first, then the only ongoing activity;
    /// with several, the last tab used stays.
    private var openingPage: IslandPage? {
        let shelfOn = preferences.shelfEnabled && !shelf.items.isEmpty
        if shelfOn, let newest = shelf.items.first, Date().timeIntervalSince(newest.addedAt) < Self.recentShelfWindow { return .shelf }
        var ongoing: [IslandPage] = []
        if media?.isPlaying == true { ongoing.append(.music) }
        if countdown.isActive { ongoing.append(.timer) }
        if keepAwake != nil { ongoing.append(.keepAwake) }
        if shelfOn { ongoing.append(.shelf) }
        return ongoing.count == 1 ? ongoing[0] : nil
    }
    /// The compact hover: the island widens at the notch height instead of opening downward.
    @Published var compactOpen = false { didSet { if !compactOpen { compactSelection = nil } } }
    /// Panel picked with the switch button in the compact hover; reset when it closes.
    @Published private(set) var compactSelection: CompactPanel?
    /// A drag is near the notch: the island opens downward on the shelf with a drop area,
    /// so the file is released below the top edge instead of hitting it.
    @Published private(set) var shelfDropTarget = false
    /// The island was opened by the drag and closes again when it ends.
    private var expandedForDrop = false
    private var pageBeforeDrop = IslandPage.music
    private var dropCloseTask: Task<Void, Never>?
    @Published private(set) var notice: IslandNotice?
    /// The last finished download, offered by the compact hover for two minutes.
    @Published private(set) var recentDownload: URL?
    @Published var page = IslandPage.music { didSet { if page != .keepAwake { keepAwakeEditing = false } } }
    @Published var completionVisible = false
    @Published private(set) var activityOrder = ActivityOrder()
    @Published private(set) var pomodoro = PomodoroCycle()
    @Published private(set) var timerIsPomodoro = false
    @Published private(set) var completionTitle = "Concluído"
    @Published private(set) var timerDuration: TimeInterval = 1500
    /// A running source whose Automation access failed; shown only while nothing else is active.
    @Published private(set) var attention: MediaSource?
    /// Keeps the Mac awake until the deadline, or until switched off.
    @Published private(set) var keepAwake: KeepAwakeSession?
    /// The custom duration field is open; the island stays expanded while it is.
    @Published var keepAwakeEditing = false
    /// Assistant notifications, oldest first; the island shows one at a time.
    @Published private(set) var agentEvents: [AgentEvent] = []

    /// The mini chat under the island; while open, the visible request holds still.
    @Published private(set) var agentCardOpen = false
    /// Set by the mini chat while a choice or text is in progress: it stays open until sent.
    @Published var agentDraft = false
    /// Another app uses the camera or microphone; assistant alerts follow the call mode.
    @Published private(set) var inCall = false
    /// "Em chamada" on the collapsed island for a few seconds after a call starts.
    @Published private(set) var callNoticeVisible = false
    /// The meeting about to start or just started, while the agenda is on.
    @Published private(set) var meeting: MeetingAlert?
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var calendarDenied = false

    var agentEvent: AgentEvent? { agentEvents.first }
    var showsAttention: Bool { attention != nil && activityOrder.items.isEmpty && !completionVisible }
    /// Keep Awake on the collapsed island: both ears alone, a small cup beside music or a timer.
    var keepAwakeVisible: Bool { keepAwake != nil && preferences.keepAwakeShowCollapsed }
    var shelfVisible: Bool { preferences.shelfEnabled && preferences.shelfShowCollapsed && !shelf.items.isEmpty }
    var hasOtherActivity: Bool {
        media?.isPlaying == true || countdown.isActive || completionVisible || showsAttention || keepAwakeVisible
            || meeting != nil || callNoticeVisible || notice != nil || shelfVisible
    }
    /// With music or a timer on the island, the assistant gets its own bubble beside it.
    var agentInBubble: Bool { agentEvent != nil && hasOtherActivity }
    /// Alone, the assistant takes both ears of the island.
    var agentInIsland: Bool { agentEvent != nil && !hasOtherActivity }
    var active: Bool { hasOtherActivity || agentEvent != nil }
    /// The collapsed island needs both ears for two activities or a short status label.
    /// A timer's clock plus the Keep Awake cup also needs the wider ears.
    var compactIsWide: Bool {
        activityOrder.items.count > 1 || completionVisible || showsAttention || agentInIsland
            || (keepAwakeVisible && countdown.isActive) || meeting != nil || callNoticeVisible || notice != nil
    }

    /// What the compact hover can show, most urgent first: a drop in progress alone, then the
    /// meeting, a fresh download, the most recent activity, Keep Awake, the shelf, paused music.
    var compactPanels: [CompactPanel] {
        if shelfDropTarget { return [.drop] }
        var panels: [CompactPanel] = []
        if meeting != nil { panels.append(.meeting) }
        if recentDownload != nil { panels.append(.download) }
        for item in activityOrder.items.reversed() { panels.append(item == .timer ? .timer : .music) }
        if countdown.isActive && !panels.contains(.timer) { panels.append(.timer) }
        if keepAwake != nil { panels.append(.keepAwake) }
        if preferences.shelfEnabled && !shelf.items.isEmpty { panels.append(.shelf) }
        if media != nil && !panels.contains(.music) { panels.append(.music) }
        return panels
    }

    var compactPanel: CompactPanel? {
        let panels = compactPanels
        if let compactSelection, panels.contains(compactSelection) { return compactSelection }
        return panels.first
    }

    func cycleCompactPanel() {
        let panels = compactPanels
        guard panels.count > 1, let current = compactPanel, let index = panels.firstIndex(of: current) else { return }
        compactSelection = panels[(index + 1) % panels.count]
    }

    var compactShown: Bool { (compactOpen || shelfDropTarget) && !expanded && compactPanel != nil }
    private let runner = AutomationRunner()
    private let systemMedia = SystemMediaProvider()
    private var systemSnapshot: MediaSnapshot?
    private var systemArtwork: Data?
    /// Display names of Now Playing apps, resolved once per bundle.
    private var playerNames: [String: String] = [:]
    private var spotifySnapshot: MediaSnapshot?
    private var browserSnapshot: MediaSnapshot?
    private var lastSpotifyRead = Date.distantPast
    private var lastBrowserRead = Date.distantPast
    private var refreshing = false
    private var sleeping = false
    private var loop: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var keepAwakeTask: Task<Void, Never>?
    private let power = PowerAssertion()
    /// Started on battery below the cutoff: the user chose it, so the cutoff does not apply.
    private var keepAwakeStartedLow = false
    private var subscriptions = Set<AnyCancellable>()
    private lazy var agentServer = AgentHookServer(
        onEvent: { [weak self] event in Task { @MainActor in self?.receive(event) } },
        onGone: { [weak self] id in Task { @MainActor in self?.resolveAgent(id, decision: nil, reason: "helper closed") } })
    private var agentServerRunning = false
    private var lastAgentSound = Date.distantPast
    private var agentTimeouts: [UUID: Task<Void, Never>] = [:]
    private var agentDeadlines: [UUID: Date] = [:]
    /// Time left on a request whose countdown is frozen by the open mini chat.
    private var agentRemaining: [UUID: TimeInterval] = [:]
    private var agentTotals: [UUID: TimeInterval] = [:]
    private let calls = CallMonitor()
    private var callMonitorRunning = false
    private var callNoticeTask: Task<Void, Never>?
    /// Requests that arrived during the current call; one sound plays for them when it ends.
    private var eventsDuringCall = 0
    private let calendar = CalendarService()
    private var meetings: [Meeting] = []
    private var dismissedMeetings: Set<String> = []
    private var meetingTask: Task<Void, Never>?
    private var calendarAsked = false
    private var noticeTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private let screenshots = FolderWatcher(label: "screenshots")
    private let downloads = FolderWatcher(label: "downloads")
    private let powerMonitor = PowerMonitor()

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = true; self?.loop?.cancel(); self?.timerTask?.cancel(); self?.keepAwakeTask?.cancel()
                self?.systemMedia.stop()
                self?.meetingTask?.cancel(); self?.shelf.suspend()
            }
        }.store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; self?.start() }
        }.store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refresh(force: true) }
            }.store(in: &subscriptions)
        DistributedNotificationCenter.default().publisher(for: Notification.Name("com.spotify.client.PlaybackStateChanged"))
            .sink { [weak self] _ in Task { @MainActor in await self?.refresh(force: true) } }
            .store(in: &subscriptions)
        preferences.$spotifyEnabled.dropFirst().map { _ in () }
            .merge(with: preferences.$browserEnabled.dropFirst().map { _ in () }, preferences.$browser.dropFirst().map { _ in () },
                   preferences.$systemMediaEnabled.dropFirst().map { _ in () })
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.spotifySnapshot = nil; self.browserSnapshot = nil; self.errors = [:]
                self.syncSystemMedia()
                Task { await self.refresh(force: true) }
            }.store(in: &subscriptions)
        systemMedia.onUpdate = { [weak self] update in self?.receive(update) }
        systemMedia.onFailure = { [weak self] message in
            guard let self else { return }
            self.errors[.system] = message
            self.systemSnapshot = nil
            Task { await self.refresh(force: true) }
        }
        // @Published emits before storing; hopping to the next run loop turn reads the stored values.
        preferences.$agentsEnabled.dropFirst().map { _ in () }
            .merge(with: preferences.$agentsPaused.dropFirst().map { _ in () },
                   preferences.$callAdjust.dropFirst().map { _ in () },
                   preferences.$callAlertMode.dropFirst().map { _ in () },
                   preferences.$callUsesMicrophone.dropFirst().map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.syncCallMonitor(); self?.syncAgentServer() }
            .store(in: &subscriptions)
        preferences.$meetingsEnabled.dropFirst().map { _ in () }
            .merge(with: preferences.$meetingLeadMinutes.dropFirst().map { _ in () },
                   preferences.$meetingsLinkOnly.dropFirst().map { _ in () },
                   preferences.$meetingExcludedCalendars.dropFirst().map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshMeetings() }
            .store(in: &subscriptions)
        shelf.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        ShelfDragCoordinator.shared.store = shelf
        let flags = [preferences.$shelfEnabled, preferences.$shelfDragMoves, preferences.$shelfRemoveAfterDrop, preferences.$screenshotsToShelf,
                     preferences.$downloadsNotify, preferences.$downloadsToShelf, preferences.$powerNotice,
                     preferences.$powerChargedNotice, preferences.$powerLowNotice]
            .map { $0.dropFirst().map { _ in () }.eraseToAnyPublisher() }
        Publishers.MergeMany(flags + [preferences.$shelfExpiryHours.dropFirst().map { _ in () }.eraseToAnyPublisher()])
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.syncShelfSources() }
            .store(in: &subscriptions)
        powerMonitor.changed = { [weak self] old, new in self?.powerChanged(from: old, to: new) }
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMeetings() }
            .store(in: &subscriptions)
        preferences.$keepAwakeAllowDisplaySleep.dropFirst()
            .sink { [weak self] allow in if self?.keepAwake != nil { self?.power.hold(display: !allow) } }
            .store(in: &subscriptions)
        preferences.$keepAwakeBatteryCutoff.dropFirst()
            .sink { [weak self] cutoff in if cutoff { self?.checkBattery() } }
            .store(in: &subscriptions)
        power.powerChanged = { [weak self] in self?.checkBattery() }
    }

    func start() {
        syncSystemMedia()
        syncCallMonitor()
        syncAgentServer()
        refreshMeetings()
        syncShelfSources()
        shelf.validate()
        loop?.cancel()
        checkTimer()
        scheduleTimer()
        checkKeepAwake()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.sleeping else { return }
                await self.refresh()
                do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                catch { return }
            }
        }
    }

    func stop() {
        loop?.cancel(); timerTask?.cancel(); completionTask?.cancel(); keepAwakeTask?.cancel()
        systemMedia.stop()
        power.release()
        meetingTask?.cancel()
        calls.stop()
        screenshots.stop(); downloads.stop(); powerMonitor.stop()
        setAgentServer(running: false)
    }

    // MARK: Keep awake

    /// Zero or fewer minutes keeps the Mac awake until switched off.
    func startKeepAwake(minutes: Int) {
        keepAwake = KeepAwakeSession(minutes: minutes)
        keepAwakeEditing = false
        keepAwakeStartedLow = PowerAssertion.batteryLevelOnBattery().map { $0 < 20 } ?? false
        power.hold(display: !preferences.keepAwakeAllowDisplaySleep)
        awakeLog.info("start minutes=\(minutes)")
        scheduleKeepAwake()
    }

    /// Pushes a timed period later; a period without a limit is left alone.
    func extendKeepAwake(minutes: Int) {
        guard let keepAwake, !keepAwake.isIndefinite else { return }
        self.keepAwake = keepAwake.extended(byMinutes: minutes)
        scheduleKeepAwake()
    }

    func stopKeepAwake() {
        keepAwakeTask?.cancel()
        keepAwakeTask = nil
        keepAwake = nil
        power.release()
    }

    private func scheduleKeepAwake() {
        keepAwakeTask?.cancel()
        guard let remaining = keepAwake?.remaining(), !sleeping else { return }
        keepAwakeTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
            self?.checkKeepAwake()
        }
    }

    /// Ends an expired period; otherwise re-arms the deadline, e.g. after waking.
    private func checkKeepAwake() {
        guard let keepAwake else { return }
        if keepAwake.isExpired() { awakeLog.info("expired"); stopKeepAwake() } else { scheduleKeepAwake() }
    }

    private func checkBattery() {
        guard keepAwake != nil, preferences.keepAwakeBatteryCutoff else { return }
        guard let level = PowerAssertion.batteryLevelOnBattery() else { keepAwakeStartedLow = false; return }
        if level >= 20 { keepAwakeStartedLow = false; return }
        guard !keepAwakeStartedLow else { return }
        awakeLog.info("battery cutoff level=\(level)")
        stopKeepAwake()
    }

    // MARK: Calls

    private var callMonitorWanted: Bool { preferences.agentsEnabled && preferences.callAdjust }

    private func syncCallMonitor() {
        guard callMonitorWanted else {
            if callMonitorRunning { calls.stop(); callMonitorRunning = false }
            if inCall { callChanged(false) }
            return
        }
        // Restarting picks up a changed microphone choice; the first state arrives right away.
        callMonitorRunning = true
        calls.start(microphone: preferences.callUsesMicrophone) { [weak self] active in
            Task { @MainActor in self?.callChanged(active) }
        }
    }

    private func callChanged(_ active: Bool) {
        guard active != inCall else { return }
        agentLog.info("call active=\(active)")
        inCall = active
        callNoticeTask?.cancel()
        if active {
            eventsDuringCall = 0
            callNoticeVisible = true
            callNoticeTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
                self?.callNoticeVisible = false
            }
        } else {
            callNoticeVisible = false
            let pending = agentEvents.contains { $0.kind.waitsForAnswer }
            if eventsDuringCall > 0, pending, preferences.agentAlertMode == .sound { playAgentSound() }
            eventsDuringCall = 0
        }
        syncAgentServer()
    }

    /// Alert mode for the call, nil when the call pauses notifications.
    var callAlert: AgentAlertMode? {
        guard inCall, preferences.callAdjust else { return preferences.agentAlertMode }
        return preferences.callAlertMode.applied(to: preferences.agentAlertMode)
    }

    // MARK: Meetings

    func enableMeetings() async {
        let granted = CalendarService.authorized ? true : await calendar.requestAccess()
        calendarDenied = !granted
        preferences.meetingsEnabled = granted
        refreshMeetings()
    }

    /// Reads the next hours of events off the main actor, then waits for the next change.
    func refreshMeetings() {
        meetingTask?.cancel()
        calendarDenied = CalendarService.denied
        // An ad hoc signed rebuild loses the macOS grant: ask again once instead of going quiet.
        if preferences.meetingsEnabled, CalendarService.undetermined, !calendarAsked {
            calendarAsked = true
            meetingLog.info("access undetermined, asking again")
            Task { await enableMeetings() }
            return
        }
        guard preferences.meetingsEnabled, CalendarService.authorized, !sleeping else {
            if preferences.meetingsEnabled { meetingLog.info("not reading: authorized=\(CalendarService.authorized) sleeping=\(self.sleeping)") }
            meetings = []; meeting = nil; calendars = []
            return
        }
        let excluded = Set(preferences.meetingExcludedCalendars)
        meetingTask = Task { [weak self, calendar] in
            let now = Date()
            let list = await calendar.meetings(from: now, hours: 12, excluding: excluded)
            let available = await calendar.calendars()
            guard !Task.isCancelled, let self else { return }
            self.meetings = list
            meetingLog.info("read \(list.count) events, \(list.filter { $0.link != nil }.count) with video links")
            if self.calendars != available { self.calendars = available }
            self.evaluateMeeting()
        }
    }

    private func evaluateMeeting() {
        let now = Date()
        let lead = preferences.meetingLeadMinutes, linkOnly = preferences.meetingsLinkOnly
        dismissedMeetings = dismissedMeetings.filter { id in meetings.contains { $0.id == id } }
        let next = MeetingSchedule.alert(in: meetings, at: now, leadMinutes: lead, linkOnly: linkOnly, dismissed: dismissedMeetings)
        if next != meeting {
            meeting = next
            meetingLog.info("alert \(next.map { $0.phase == .now ? "now" : "soon" } ?? "none", privacy: .public)")
        }
        // One wait until the alert can change; events are re-read at least hourly for new ones.
        let change = MeetingSchedule.nextChange(in: meetings, after: now, leadMinutes: lead, linkOnly: linkOnly, dismissed: dismissedMeetings)
        let wait = min(change?.timeIntervalSince(now) ?? 3600, 3600)
        meetingTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(max(1, wait) * 1_000_000_000)) } catch { return }
            self?.refreshMeetings()
        }
    }

    func joinMeeting() {
        guard let meeting else { return }
        if let link = meeting.meeting.link { NSWorkspace.shared.open(link) }
        dismissMeeting()
    }

    func dismissMeeting() {
        guard let meeting else { return }
        dismissedMeetings.insert(meeting.meeting.id)
        compactOpen = false
        evaluateMeeting()
    }

    // MARK: Shelf, screenshots, downloads and power

    /// Watchers exist only for the options that are on; the folders prompt for access then.
    private func syncShelfSources() {
        ShelfDragCoordinator.shared.movesByDefault = preferences.shelfDragMoves
        ShelfDragCoordinator.shared.removesAfterDrop = preferences.shelfRemoveAfterDrop
        shelf.setExpiry(hours: preferences.shelfExpiryHours)
        if preferences.screenshotsToShelf && preferences.shelfEnabled {
            screenshots.start(Self.screenshotFolder) { [weak self] urls in
                Task { @MainActor in self?.screenshotsAppeared(urls) }
            }
        } else { screenshots.stop() }
        if preferences.downloadsNotify || (preferences.downloadsToShelf && preferences.shelfEnabled) {
            let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            downloads.start(folder) { [weak self] urls in
                Task { @MainActor in self?.downloadsAppeared(urls) }
            }
        } else { downloads.stop() }
        if preferences.powerNotice || preferences.powerChargedNotice || preferences.powerLowNotice { powerMonitor.start() }
        else { powerMonitor.stop() }
        if !preferences.shelfEnabled && page == .shelf { page = .music }
    }

    /// Where screencapture saves, from its own preferences; the Desktop by default.
    private static var screenshotFolder: URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !location.isEmpty {
            var isDirectory: ObjCBool = false
            let path = (location as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private func screenshotsAppeared(_ urls: [URL]) {
        let recordings = preferences.screenshotRecordings
        Task {
            // The capture flag is written with the file; a short wait covers a late attribute.
            try? await Task.sleep(nanoseconds: 400_000_000)
            let captures = await Task.detached { urls.filter { Self.isScreenCapture($0, recordings: recordings) } }.value
            guard !captures.isEmpty, preferences.screenshotsToShelf, preferences.shelfEnabled else { return }
            shelf.addReferences(captures, origin: .screenshot)
            guard preferences.screenshotNotice, let last = captures.last else { return }
            var count = captures.count
            if case .screenshot(let previous, _) = notice { count += previous }
            showNotice(.screenshot(count: count, path: last.path), seconds: 3)
        }
    }

    nonisolated private static func isScreenCapture(_ url: URL, recordings: Bool) -> Bool {
        guard getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0 else { return false }
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .image) == true { return true }
        return recordings && type?.conforms(to: .movie) == true
    }

    private func downloadsAppeared(_ urls: [URL]) {
        guard let last = urls.last else { return }
        if preferences.downloadsToShelf && preferences.shelfEnabled { shelf.addReferences(urls, origin: .download) }
        guard preferences.downloadsNotify else { return }
        recentDownload = last
        shelf.requestThumbnail(path: last.path)
        showNotice(.download(path: last.path), seconds: 5)
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
            self?.recentDownload = nil
        }
    }

    func openRecentDownload() {
        if let recentDownload { NSWorkspace.shared.open(recentDownload) }
        dismissRecentDownload()
    }

    func revealRecentDownload() {
        if let recentDownload { NSWorkspace.shared.activateFileViewerSelecting([recentDownload]) }
        dismissRecentDownload()
    }

    func shelveRecentDownload() {
        if let recentDownload { shelf.addReferences([recentDownload], origin: .download) }
        dismissRecentDownload()
    }

    private func dismissRecentDownload() {
        downloadTask?.cancel()
        recentDownload = nil
        if case .download = notice { notice = nil }
    }

    private func powerChanged(from old: PowerState?, to new: PowerState) {
        guard let event = PowerEvents.event(from: old, to: new, warnLow: preferences.powerLowNotice) else { return }
        switch event {
        case .connected, .disconnected: guard preferences.powerNotice else { return }
        case .charged: guard preferences.powerChargedNotice else { return }
        case .low: break
        }
        if case .low = event { showNotice(.power(event), seconds: 5) } else { showNotice(.power(event), seconds: 3) }
    }

    private func showNotice(_ next: IslandNotice, seconds: Double) {
        notice = next
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
            self?.notice = nil
        }
    }

    /// Reads a drop on the notch: files become references; promised files, images, links and
    /// text from a browser become the shelf's own copies.
    func receiveDrop(_ pasteboard: NSPasteboard) -> Bool {
        defer { endDropApproach(after: 0.9) }
        guard preferences.shelfEnabled else { return false }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            shelf.addReferences(urls, origin: .drop)
        } else if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !promises.isEmpty {
            shelf.addPromises(promises)
        } else if let image = (pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first,
                  let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            shelf.addOwned(png, name: "Imagem \(Self.stamp()).png", origin: .browser)
        } else if let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first, let scheme = url.scheme, ["http", "https"].contains(scheme) {
            let plist = try? PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)
            guard let plist else { return false }
            shelf.addOwned(plist, name: "\(url.host ?? "Link").webloc", origin: .browser)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            shelf.addOwned(Data(text.utf8), name: "Texto \(Self.stamp()).txt", origin: .browser)
        } else {
            return false
        }
        return true
    }

    func beginDropApproach() {
        guard preferences.shelfEnabled else { return }
        dropCloseTask?.cancel()
        dropCloseTask = nil
        guard !shelfDropTarget else { return }
        shelfDropTarget = true
        if !expanded {
            expandedForDrop = true
            pageBeforeDrop = page
            expanded = true
        }
        page = .shelf
    }

    /// Leaves the drop area; after a drop it stays a moment so the new item shows.
    func endDropApproach(after seconds: Double = 0) {
        guard shelfDropTarget || expandedForDrop else { return }
        shelfDropTarget = false
        dropCloseTask?.cancel()
        dropCloseTask = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            guard !Task.isCancelled, let self, self.expandedForDrop, !self.shelfDropTarget else { return }
            self.expandedForDrop = false
            self.expanded = false
            self.page = self.pageBeforeDrop
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    // MARK: Assistants

    private func syncAgentServer() {
        setAgentServer(running: preferences.agentsEnabled && !preferences.agentsPaused && callAlert != nil)
    }

    /// The socket exists only while notifications are on and not paused; closing it hands
    /// pending permission requests back to each assistant's own prompt.
    private func setAgentServer(running: Bool) {
        guard running != agentServerRunning else { return }
        agentServerRunning = running
        if running { agentServer.start(); return }
        agentServer.stop()
        agentTimeouts.values.forEach { $0.cancel() }
        agentTimeouts = [:]
        agentDeadlines = [:]
        agentRemaining = [:]
        agentTotals = [:]
        agentEvents = []
        agentCardOpen = false
        agentDraft = false
    }

    private func receive(_ event: AgentEvent) {
        agentLog.info("receive \(event.id, privacy: .public) kind=\(String(describing: event.kind), privacy: .public)")
        guard agentServerRunning else { agentServer.respond(event.id, with: nil); return }
        // Requests that wait for an answer go ahead of completions, never ahead of the visible one.
        if event.kind.waitsForAnswer, let index = agentEvents.indices.dropFirst().first(where: { !agentEvents[$0].kind.waitsForAnswer }) {
            agentEvents.insert(event, at: index)
        } else {
            agentEvents.append(event)
        }
        let wait = event.kind.waitsForAnswer ? Double(preferences.agentPermissionWait) : 8
        agentTotals[event.id] = wait
        if agentCardOpen && agentEvent?.id == event.id { agentRemaining[event.id] = wait }
        else { scheduleAgentTimeout(event.id, after: wait) }
        alertAgent(event)
    }

    /// Sound and macOS banner for a new notification, per the alert mode. Bursts play one sound.
    private func alertAgent(_ event: AgentEvent) {
        if inCall && event.kind.waitsForAnswer { eventsDuringCall += 1 }
        let mode = callAlert ?? .silent
        let alert = mode.alert(for: event.kind, includeCompletions: preferences.agentAlertCompletions)
        if alert.sound, Date().timeIntervalSince(lastAgentSound) > 1.5 {
            lastAgentSound = Date()
            playAgentSound()
        }
        guard alert.banner, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        switch event.kind {
        case .permission: content.title = "\(event.agent.name) pede permissão"
        case .question: content.title = "\(event.agent.name) tem uma pergunta"
        case .completion: content.title = "\(event.agent.name) concluiu"
        }
        if let project = event.project { content.subtitle = project }
        content.body = String((event.tool.isEmpty ? event.detail : "\(event.tool): \(event.detail)").prefix(200))
        // Sound comes from NSSound so the chosen tone and the mode apply the same way.
        content.sound = nil
        let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            try? await center.add(request)
        }
    }

    func playAgentSound() {
        NSSound(named: NSSound.Name(preferences.agentAlertSound))?.play()
    }

    private func scheduleAgentTimeout(_ id: UUID, after seconds: Double) {
        agentTimeouts[id]?.cancel()
        agentDeadlines[id] = Date().addingTimeInterval(seconds)
        agentRemaining[id] = nil
        agentTimeouts[id] = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
            self?.resolveAgent(id, decision: nil, reason: "timeout")
        }
    }

    /// Opening the mini chat freezes the visible request's deadline; nothing replaces it while open.
    func openAgentCard() {
        guard let event = agentEvent, !agentCardOpen else { return }
        agentLog.info("open card \(event.id, privacy: .public)")
        expanded = false
        agentCardOpen = true
        if let deadline = agentDeadlines[event.id] {
            agentTimeouts.removeValue(forKey: event.id)?.cancel()
            agentDeadlines[event.id] = nil
            agentRemaining[event.id] = max(0, deadline.timeIntervalSinceNow)
        }
    }

    /// Closing resumes the countdown, with a few seconds of grace. A draft keeps it open.
    func closeAgentCard(force: Bool = false) {
        guard agentCardOpen, force || !agentDraft else { return }
        agentLog.info("close card draft=\(self.agentDraft)")
        agentCardOpen = false
        agentDraft = false
        if let event = agentEvent, let remaining = agentRemaining[event.id] {
            scheduleAgentTimeout(event.id, after: max(remaining, event.kind.waitsForAnswer ? 5 : 3))
        }
    }

    /// Answers the visible request, or dismisses the visible completion with nil.
    func answerAgent(_ decision: AgentDecision?) {
        guard let event = agentEvent else { return }
        resolveAgent(event.id, decision: decision, reason: "user")
    }

    private func resolveAgent(_ id: UUID, decision: AgentDecision?, reason: String) {
        agentLog.info("resolve \(id, privacy: .public) reason=\(reason, privacy: .public) answered=\(decision != nil)")
        agentTimeouts.removeValue(forKey: id)?.cancel()
        agentDeadlines[id] = nil
        agentRemaining[id] = nil
        agentTotals[id] = nil
        guard let index = agentEvents.firstIndex(where: { $0.id == id }) else { return }
        let event = agentEvents.remove(at: index)
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        }
        if index == 0 { agentCardOpen = false; agentDraft = false }
        if event.kind.waitsForAnswer { agentServer.respond(id, with: decision.map { AgentHook.response($0, for: event) }) }
    }

    /// Remaining share of the visible request's wait, for the ring around the bubble.
    func agentProgress(at date: Date) -> Double {
        guard let event = agentEvent, let total = agentTotals[event.id], total > 0 else { return 1 }
        if let remaining = agentRemaining[event.id] { return remaining / total }
        guard let deadline = agentDeadlines[event.id] else { return 1 }
        return max(0, deadline.timeIntervalSince(date)) / total
    }

    func retryConnections() {
        errors = [:]
        attention = nil
        syncSystemMedia()
        Task { await refresh(force: true) }
    }

    /// Remaining fraction of the running timer; a full ring when idle.
    func timerProgress(at date: Date) -> Double {
        guard countdown.isActive, timerDuration > 0 else { return 1 }
        return countdown.remaining(at: date) / timerDuration
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func isRunning(_ source: MediaSource) -> Bool {
        guard source != .system else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).isEmpty
    }

    func refresh(force: Bool = false) async {
        guard !refreshing, !sleeping, !commandBusy else { return }
        refreshing = true
        defer { refreshing = false }
        let now = Date()
        // The system session already covers Spotify and browsers; AppleScript is only a fallback.
        let systemCovers = systemMediaActive
        if systemCovers || !preferences.spotifyEnabled || !isRunning(.spotify) { spotifySnapshot = nil }
        else if errors[.spotify] == nil, force || now.timeIntervalSince(lastSpotifyRead) >= 5 {
            lastSpotifyRead = now
            do { spotifySnapshot = try await SpotifyProvider(runner: runner).snapshot() }
            catch { errors[.spotify] = friendlyError(error); spotifySnapshot = nil }
        }
        let browser = preferences.browser
        if systemCovers || !preferences.browserEnabled || !isRunning(browser) { browserSnapshot = nil }
        else if errors[browser] == nil, force || now.timeIntervalSince(lastBrowserRead) >= 3 {
            lastBrowserRead = now
            do { browserSnapshot = try await BrowserProvider(source: browser, runner: runner).snapshot() }
            catch { errors[browser] = friendlyError(error); browserSnapshot = nil }
        }
        applyMediaSelection()
        let blocked = errors.isEmpty ? nil : MediaSource.allCases.first { errors[$0] != nil && isRunning($0) }
        if attention != blocked { attention = blocked }
        synchronizeActivities()
    }

    func perform(_ command: MediaCommand) {
        guard !commandBusy, let source = media?.source else { return }
        commandBusy = true
        Task {
            defer { commandBusy = false }
            do {
                if source == .system {
                    systemMedia.perform(command)
                    commandBusy = false
                    return
                }
                if source == .spotify { try await SpotifyProvider(runner: runner).perform(command) }
                else { try await BrowserProvider(source: source, runner: runner).perform(command) }
                // Release the command gate before reconciling; refresh itself remains single-flight.
                commandBusy = false
                await refresh(force: true)
            } catch { errors[source] = friendlyError(error) }
        }
    }

    private var systemMediaActive: Bool { preferences.systemMediaEnabled && errors[.system] == nil }

    private func syncSystemMedia() {
        if systemMediaActive && !sleeping { systemMedia.start() }
        else {
            systemMedia.stop()
            systemSnapshot = nil; systemArtwork = nil
        }
    }

    private func receive(_ update: NowPlayingUpdate) {
        guard systemMediaActive else { return }
        if let data = update.artwork { systemArtwork = data }
        var snapshot = update.media
        if let bundle = snapshot?.playerBundle {
            // Our own process never publishes; ignore a stale session pointing back at it.
            if bundle == Bundle.main.bundleIdentifier { snapshot = nil }
        }
        if snapshot?.artworkKey == nil { systemArtwork = nil }
        systemSnapshot = snapshot
        applyMediaSelection()
        // Cover bytes can arrive in a line whose fields match the shown snapshot.
        if update.artwork != nil, media?.source == .system { artwork.load(data: systemArtwork, key: media?.artworkKey) }
        synchronizeActivities()
    }

    private func applyMediaSelection() {
        let chosen = MediaSelection.choose(system: systemSnapshot, spotify: spotifySnapshot, browser: browserSnapshot)
        guard media != chosen else { return }
        media = chosen
        if chosen?.source == .system { artwork.load(data: systemArtwork, key: chosen?.artworkKey) }
        else { artwork.load(chosen?.artworkURL) }
    }

    /// App name shown beside the artist, such as "Música" or "Google Chrome".
    func playerName(_ media: MediaSnapshot) -> String {
        guard media.source == .system else { return media.source == .chrome ? "Chrome" : media.source.name }
        guard let bundle = media.playerBundle else { return "Mac" }
        if let cached = playerNames[bundle] { return cached }
        var name = bundle
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        }
        if bundle == MediaSource.chrome.bundleIdentifier { name = "Chrome" }
        playerNames[bundle] = name
        return name
    }

    func startTimer(minutes: Double, showPage: Bool = true) {
        guard minutes.isFinite, minutes > 0 else { return }
        completionVisible = false
        completionTask?.cancel()
        timerDuration = min(1440, minutes) * 60
        countdown.start(seconds: timerDuration)
        timerIsPomodoro = false
        synchronizeActivities()
        scheduleTimer()
        if showPage { page = .timer }
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }
    }

    func startPomodoro(showPage: Bool = true) {
        startTimer(minutes: Double(preferences.pomodoro.minutes(for: pomodoro.phase)), showPage: showPage)
        timerIsPomodoro = true
    }

    func selectPomodoroPhase(_ phase: PomodoroPhase) {
        guard !countdown.isActive else { return }
        pomodoro.select(phase)
        completionVisible = false
    }

    private func synchronizeActivities() {
        var next = activityOrder
        next.update(music: media?.isPlaying == true, timer: countdown.isActive)
        guard next != activityOrder else { return }
        if activityOrder.items.isEmpty, let first = next.items.first { page = first == .timer ? .timer : .music }
        activityOrder = next
    }

    func toggleTimer() {
        if countdown.isPaused { countdown.resume() } else { countdown.pause() }
        scheduleTimer()
    }

    func cancelTimer() {
        timerTask?.cancel(); countdown.cancel(); completionVisible = false
        timerIsPomodoro = false
        synchronizeActivities()
    }

    private func scheduleTimer() {
        timerTask?.cancel()
        guard countdown.isActive, !countdown.isPaused, !sleeping else { return }
        let delay = UInt64(max(0, countdown.remaining()) * 1_000_000_000)
        timerTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.checkTimer()
            // Re-evaluate if the system clock moved backwards during the wait.
            if self.countdown.isActive { self.scheduleTimer() }
        }
    }

    /// Ends the current Pomodoro phase now, as if its time ran out, without sound or notification.
    func skipPomodoroPhase() {
        guard countdown.isActive, timerIsPomodoro else { return }
        timerTask?.cancel()
        countdown.cancel()
        finishTimer(announce: false)
    }

    private func checkTimer() {
        guard countdown.completeIfNeeded() else { return }
        finishTimer(announce: true)
    }

    private func finishTimer(announce: Bool) {
        var advanced = false
        if timerIsPomodoro {
            let finished = pomodoro.complete(sessions: preferences.pomodoro.sessions)
            advanced = preferences.pomodoroAutoStart && !finished
            let focus = pomodoro.phase == .work
            if finished { completionTitle = "Ciclo concluído" }
            else if advanced { completionTitle = focus ? "Foco iniciado" : "Pausa iniciada" }
            else { completionTitle = focus ? "Foco pronto" : "Pausa pronta" }
        } else { completionTitle = "Concluído" }
        timerIsPomodoro = false
        // Auto-start chains phases until the long break closes the cycle.
        if advanced { startPomodoro(showPage: false) }
        synchronizeActivities()
        completionVisible = true
        if announce && preferences.soundEnabled { NSSound(named: "Glass")?.play() }
        if announce && Bundle.main.bundleURL.pathExtension == "app" {
            let content = UNMutableNotificationContent()
            content.title = advanced ? completionTitle : "Tempo concluído"
            content.body = advanced ? "A etapa anterior do Pomodoro terminou." : "Seu temporizador do Notch terminou."
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: advanced ? 4_000_000_000 : 12_000_000_000)
            guard !Task.isCancelled else { return }
            self?.completionVisible = false
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("-1743") || text.contains("-10004") {
            return "Autorize o Notch em Ajustes do Sistema → Privacidade e Segurança → Automação e clique em Tentar novamente."
        }
        if text.localizedCaseInsensitiveContains("JavaScript") {
            return "Habilite JavaScript via Apple Events no navegador e clique em Tentar novamente."
        }
        return String(text.prefix(400))
    }
}
