import AppKit
import Combine
import UserNotifications
import NotchCore

@MainActor final class AppModel: ObservableObject {
    let preferences = Preferences()
    let login = LoginService()
    let artwork = ArtworkStore()
    @Published private(set) var media: MediaSnapshot?
    @Published private(set) var countdown = Countdown()
    @Published private(set) var errors: [MediaSource: String] = [:]
    @Published private(set) var commandBusy = false
    @Published var expanded = false
    @Published var timerPage = false
    @Published var completionVisible = false
    @Published private(set) var activityOrder = ActivityOrder()
    @Published private(set) var pomodoro = PomodoroCycle()
    @Published private(set) var timerIsPomodoro = false
    @Published private(set) var completionTitle = "Concluído"
    @Published private(set) var timerDuration: TimeInterval = 1500
    /// A running source whose Automation access failed; shown only while nothing else is active.
    @Published private(set) var attention: MediaSource?

    var showsAttention: Bool { attention != nil && activityOrder.items.isEmpty && !completionVisible }
    var active: Bool { media?.isPlaying == true || countdown.isActive || completionVisible || showsAttention }
    /// The collapsed island needs both ears for two activities or a short status label.
    var compactIsWide: Bool { activityOrder.items.count > 1 || completionVisible || showsAttention }
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
    private var subscriptions = Set<AnyCancellable>()

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            Task { @MainActor in self?.sleeping = true; self?.loop?.cancel(); self?.timerTask?.cancel() }
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
    }

    func start() {
        loop?.cancel()
        checkTimer()
        scheduleTimer()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.sleeping else { return }
                await self.refresh()
                do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                catch { return }
            }
        }
    }

    func stop() { loop?.cancel(); timerTask?.cancel(); completionTask?.cancel() }

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

    func startTimer(minutes: Double) {
        guard minutes.isFinite, minutes > 0 else { return }
        completionVisible = false
        completionTask?.cancel()
        timerDuration = min(1440, minutes) * 60
        countdown.start(seconds: timerDuration)
        timerIsPomodoro = false
        synchronizeActivities()
        scheduleTimer()
        timerPage = true
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }
    }

    func startPomodoro() {
        startTimer(minutes: Double(pomodoro.phase.minutes))
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
        if activityOrder.items.isEmpty, let first = next.items.first { timerPage = first == .timer }
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
        if timerIsPomodoro {
            pomodoro.complete()
            completionTitle = pomodoro.phase == .work ? "Foco pronto" : "Pausa pronta"
        } else { completionTitle = "Concluído" }
        timerIsPomodoro = false
        synchronizeActivities()
        completionVisible = true
        if preferences.soundEnabled { NSSound(named: "Glass")?.play() }
        if Bundle.main.bundleURL.pathExtension == "app" {
            let content = UNMutableNotificationContent()
            content.title = "Tempo concluído"
            content.body = "Seu temporizador do Notch terminou."
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
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
