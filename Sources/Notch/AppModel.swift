import AppKit
import Combine
import UserNotifications
import NotchCore
import os

private let agentLog = Logger(subsystem: "dev.vinicius.Notch", category: "agents")
private let awakeLog = Logger(subsystem: "dev.vinicius.Notch", category: "keepAwake")

/// Tabs of the expanded island.
enum IslandPage { case music, timer, keepAwake }

@MainActor final class AppModel: ObservableObject {
    let preferences = Preferences()
    let login = LoginService()
    let artwork = ArtworkStore()
    @Published private(set) var media: MediaSnapshot?
    @Published private(set) var countdown = Countdown()
    @Published private(set) var errors: [MediaSource: String] = [:]
    @Published private(set) var commandBusy = false
    @Published var expanded = false { didSet { if !expanded { keepAwakeEditing = false } } }
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

    var agentEvent: AgentEvent? { agentEvents.first }
    var showsAttention: Bool { attention != nil && activityOrder.items.isEmpty && !completionVisible }
    /// Keep Awake on the collapsed island: both ears alone, a small cup beside music or a timer.
    var keepAwakeVisible: Bool { keepAwake != nil && preferences.keepAwakeShowCollapsed }
    var hasOtherActivity: Bool { media?.isPlaying == true || countdown.isActive || completionVisible || showsAttention || keepAwakeVisible }
    /// With music or a timer on the island, the assistant gets its own bubble beside it.
    var agentInBubble: Bool { agentEvent != nil && hasOtherActivity }
    /// Alone, the assistant takes both ears of the island.
    var agentInIsland: Bool { agentEvent != nil && !hasOtherActivity }
    var active: Bool { hasOtherActivity || agentEvent != nil }
    /// The collapsed island needs both ears for two activities or a short status label.
    /// A timer's clock plus the Keep Awake cup also needs the wider ears.
    var compactIsWide: Bool {
        activityOrder.items.count > 1 || completionVisible || showsAttention || agentInIsland
            || (keepAwakeVisible && countdown.isActive)
    }
    private let runner = AutomationRunner()
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
    private var agentTimeouts: [UUID: Task<Void, Never>] = [:]
    private var agentDeadlines: [UUID: Date] = [:]
    /// Time left on a request whose countdown is frozen by the open mini chat.
    private var agentRemaining: [UUID: TimeInterval] = [:]
    private var agentTotals: [UUID: TimeInterval] = [:]

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            Task { @MainActor in self?.sleeping = true; self?.loop?.cancel(); self?.timerTask?.cancel(); self?.keepAwakeTask?.cancel() }
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
            .merge(with: preferences.$browserEnabled.dropFirst().map { _ in () }, preferences.$browser.dropFirst().map { _ in () })
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.spotifySnapshot = nil; self.browserSnapshot = nil; self.errors = [:]
                Task { await self.refresh(force: true) }
            }.store(in: &subscriptions)
        // @Published emits before storing, so read the other flag and take the new value from the event.
        preferences.$agentsEnabled.dropFirst()
            .sink { [weak self] enabled in self?.setAgentServer(running: enabled && self?.preferences.agentsPaused == false) }
            .store(in: &subscriptions)
        preferences.$agentsPaused.dropFirst()
            .sink { [weak self] paused in self?.setAgentServer(running: !paused && self?.preferences.agentsEnabled == true) }
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
        setAgentServer(running: preferences.agentsEnabled && !preferences.agentsPaused)
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
        power.release()
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

    // MARK: Assistants

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
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).isEmpty
    }

    func refresh(force: Bool = false) async {
        guard !refreshing, !sleeping, !commandBusy else { return }
        refreshing = true
        defer { refreshing = false }
        let now = Date()
        if !preferences.spotifyEnabled || !isRunning(.spotify) { spotifySnapshot = nil }
        else if errors[.spotify] == nil, force || now.timeIntervalSince(lastSpotifyRead) >= 5 {
            lastSpotifyRead = now
            do { spotifySnapshot = try await SpotifyProvider(runner: runner).snapshot() }
            catch { errors[.spotify] = friendlyError(error); spotifySnapshot = nil }
        }
        let browser = preferences.browser
        if !preferences.browserEnabled || !isRunning(browser) { browserSnapshot = nil }
        else if errors[browser] == nil, force || now.timeIntervalSince(lastBrowserRead) >= 3 {
            lastBrowserRead = now
            do { browserSnapshot = try await BrowserProvider(source: browser, runner: runner).snapshot() }
            catch { errors[browser] = friendlyError(error); browserSnapshot = nil }
        }
        let chosen = MediaSelection.choose(spotify: spotifySnapshot, browser: browserSnapshot)
        if media != chosen { media = chosen; artwork.load(chosen?.artworkURL) }
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
                if source == .spotify { try await SpotifyProvider(runner: runner).perform(command) }
                else { try await BrowserProvider(source: source, runner: runner).perform(command) }
                // Release the command gate before reconciling; refresh itself remains single-flight.
                commandBusy = false
                await refresh(force: true)
            } catch { errors[source] = friendlyError(error) }
        }
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

    private func checkTimer() {
        guard countdown.completeIfNeeded() else { return }
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
        if preferences.soundEnabled { NSSound(named: "Glass")?.play() }
        if Bundle.main.bundleURL.pathExtension == "app" {
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
