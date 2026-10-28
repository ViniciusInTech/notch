import Foundation
import Combine
import NotchCore

@MainActor final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var spotifyEnabled: Bool { didSet { defaults.set(spotifyEnabled, forKey: "spotifyEnabled") } }
    @Published var browserEnabled: Bool { didSet { defaults.set(browserEnabled, forKey: "browserEnabled") } }
    @Published var browser: MediaSource { didSet { defaults.set(browser.rawValue, forKey: "browser") } }
    @Published var expandOnHover: Bool { didSet { defaults.set(expandOnHover, forKey: "expandOnHover") } }
    @Published var reduceMotion: Bool { didSet { defaults.set(reduceMotion, forKey: "reduceMotion") } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "soundEnabled") } }
    @Published var offerMoveToApplications: Bool { didSet { defaults.set(offerMoveToApplications, forKey: "offerMoveToApplications") } }
    @Published var pomodoroFocusMinutes: Int { didSet { defaults.set(pomodoroFocusMinutes, forKey: "pomodoroFocusMinutes") } }
    @Published var pomodoroShortBreakMinutes: Int { didSet { defaults.set(pomodoroShortBreakMinutes, forKey: "pomodoroShortBreakMinutes") } }
    @Published var pomodoroLongBreakMinutes: Int { didSet { defaults.set(pomodoroLongBreakMinutes, forKey: "pomodoroLongBreakMinutes") } }
    @Published var pomodoroSessions: Int { didSet { defaults.set(pomodoroSessions, forKey: "pomodoroSessions") } }
    @Published var pomodoroAutoStart: Bool { didSet { defaults.set(pomodoroAutoStart, forKey: "pomodoroAutoStart") } }
    @Published var agentsEnabled: Bool { didSet { defaults.set(agentsEnabled, forKey: "agentsEnabled") } }
    /// Do Not Disturb for assistant notifications, e.g. while sharing the screen.
    @Published var agentsPaused: Bool { didSet { defaults.set(agentsPaused, forKey: "agentsPaused") } }
    @Published var agentPermissionWait: Int { didSet { defaults.set(agentPermissionWait, forKey: "agentPermissionWait") } }

    var pomodoro: PomodoroSettings {
        PomodoroSettings(focusMinutes: pomodoroFocusMinutes, shortBreakMinutes: pomodoroShortBreakMinutes,
                         longBreakMinutes: pomodoroLongBreakMinutes, sessions: pomodoroSessions)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["spotifyEnabled": true, "browserEnabled": false,
                                     "browser": "safari", "expandOnHover": true,
                                     "reduceMotion": false, "soundEnabled": true,
                                     "offerMoveToApplications": true,
                                     "pomodoroFocusMinutes": 25, "pomodoroShortBreakMinutes": 5,
                                     "pomodoroLongBreakMinutes": 15, "pomodoroSessions": 4,
                                     "pomodoroAutoStart": false, "agentsEnabled": false,
                                     "agentsPaused": false, "agentPermissionWait": 30])
        spotifyEnabled = defaults.bool(forKey: "spotifyEnabled")
        browserEnabled = defaults.bool(forKey: "browserEnabled")
        browser = MediaSource(rawValue: defaults.string(forKey: "browser") ?? "safari") == .chrome ? .chrome : .safari
        expandOnHover = defaults.bool(forKey: "expandOnHover")
        reduceMotion = defaults.bool(forKey: "reduceMotion")
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        offerMoveToApplications = defaults.bool(forKey: "offerMoveToApplications")
        let stored = PomodoroSettings(focusMinutes: defaults.integer(forKey: "pomodoroFocusMinutes"),
                                      shortBreakMinutes: defaults.integer(forKey: "pomodoroShortBreakMinutes"),
                                      longBreakMinutes: defaults.integer(forKey: "pomodoroLongBreakMinutes"),
                                      sessions: defaults.integer(forKey: "pomodoroSessions"))
        pomodoroFocusMinutes = stored.focusMinutes
        pomodoroShortBreakMinutes = stored.shortBreakMinutes
        pomodoroLongBreakMinutes = stored.longBreakMinutes
        pomodoroSessions = stored.sessions
        pomodoroAutoStart = defaults.bool(forKey: "pomodoroAutoStart")
        agentsEnabled = defaults.bool(forKey: "agentsEnabled")
        agentsPaused = defaults.bool(forKey: "agentsPaused")
        agentPermissionWait = min(120, max(10, defaults.integer(forKey: "agentPermissionWait")))
    }
}
