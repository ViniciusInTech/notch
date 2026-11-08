import Foundation
import Combine
import NotchCore

@MainActor final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    /// Reads the macOS Now Playing session; Spotify and browser scripts become fallbacks.
    @Published var systemMediaEnabled: Bool { didSet { defaults.set(systemMediaEnabled, forKey: "systemMediaEnabled") } }
    @Published var spotifyEnabled: Bool { didSet { defaults.set(spotifyEnabled, forKey: "spotifyEnabled") } }
    @Published var browserEnabled: Bool { didSet { defaults.set(browserEnabled, forKey: "browserEnabled") } }
    @Published var browser: MediaSource { didSet { defaults.set(browser.rawValue, forKey: "browser") } }
    @Published var expandOnHover: Bool { didSet { defaults.set(expandOnHover, forKey: "expandOnHover") } }
    /// Hover grows the island sideways only, with one activity's controls; a click still opens the panel.
    @Published var compactHover: Bool { didSet { defaults.set(compactHover, forKey: "compactHover") } }
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
    @Published var agentAlertMode: AgentAlertMode { didSet { defaults.set(agentAlertMode.rawValue, forKey: "agentAlertMode") } }
    /// System sound name from /System/Library/Sounds.
    @Published var agentAlertSound: String { didSet { defaults.set(agentAlertSound, forKey: "agentAlertSound") } }
    @Published var agentAlertCompletions: Bool { didSet { defaults.set(agentAlertCompletions, forKey: "agentAlertCompletions") } }
    /// Switches assistant alerts while another app uses the camera or microphone.
    @Published var callAdjust: Bool { didSet { defaults.set(callAdjust, forKey: "callAdjust") } }
    @Published var callAlertMode: CallAlertMode { didSet { defaults.set(callAlertMode.rawValue, forKey: "callAlertMode") } }
    @Published var callUsesMicrophone: Bool { didSet { defaults.set(callUsesMicrophone, forKey: "callUsesMicrophone") } }
    @Published var meetingsEnabled: Bool { didSet { defaults.set(meetingsEnabled, forKey: "meetingsEnabled") } }
    @Published var meetingLeadMinutes: Int { didSet { defaults.set(meetingLeadMinutes, forKey: "meetingLeadMinutes") } }
    @Published var meetingsLinkOnly: Bool { didSet { defaults.set(meetingsLinkOnly, forKey: "meetingsLinkOnly") } }
    @Published var meetingExcludedCalendars: [String] { didSet { defaults.set(meetingExcludedCalendars, forKey: "meetingExcludedCalendars") } }
    /// Files dragged onto the notch are kept as references on the shelf.
    @Published var shelfEnabled: Bool { didSet { defaults.set(shelfEnabled, forKey: "shelfEnabled") } }
    /// Hours before an item leaves the shelf; zero keeps it until removed.
    @Published var shelfExpiryHours: Int { didSet { defaults.set(shelfExpiryHours, forKey: "shelfExpiryHours") } }
    @Published var shelfDragMoves: Bool { didSet { defaults.set(shelfDragMoves, forKey: "shelfDragMoves") } }
    /// A drop elsewhere takes the item off the shelf, whether it was copied or moved.
    @Published var shelfRemoveAfterDrop: Bool { didSet { defaults.set(shelfRemoveAfterDrop, forKey: "shelfRemoveAfterDrop") } }
    @Published var shelfShowCollapsed: Bool { didSet { defaults.set(shelfShowCollapsed, forKey: "shelfShowCollapsed") } }
    @Published var screenshotsToShelf: Bool { didSet { defaults.set(screenshotsToShelf, forKey: "screenshotsToShelf") } }
    @Published var screenshotNotice: Bool { didSet { defaults.set(screenshotNotice, forKey: "screenshotNotice") } }
    @Published var screenshotRecordings: Bool { didSet { defaults.set(screenshotRecordings, forKey: "screenshotRecordings") } }
    @Published var downloadsNotify: Bool { didSet { defaults.set(downloadsNotify, forKey: "downloadsNotify") } }
    @Published var downloadsToShelf: Bool { didSet { defaults.set(downloadsToShelf, forKey: "downloadsToShelf") } }
    @Published var powerNotice: Bool { didSet { defaults.set(powerNotice, forKey: "powerNotice") } }
    @Published var powerChargedNotice: Bool { didSet { defaults.set(powerChargedNotice, forKey: "powerChargedNotice") } }
    @Published var powerLowNotice: Bool { didSet { defaults.set(powerLowNotice, forKey: "powerLowNotice") } }
    /// Volume and brightness keys show their level on the island instead of the macOS HUD.
    @Published var levelHUD: Bool { didSet { defaults.set(levelHUD, forKey: "levelHUD") } }
    @Published var headphonesNotice: Bool { didSet { defaults.set(headphonesNotice, forKey: "headphonesNotice") } }
    /// Keeps what is copied with Command-C/X in the shelf's second section.
    @Published var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: "clipboardEnabled") } }
    @Published var clipboardLimit: Int { didSet { defaults.set(clipboardLimit, forKey: "clipboardLimit") } }
    @Published var clipboardExpiryHours: Int { didSet { defaults.set(clipboardExpiryHours, forKey: "clipboardExpiryHours") } }
    @Published var clipboardNotice: Bool { didSet { defaults.set(clipboardNotice, forKey: "clipboardNotice") } }
    /// Bundle identifiers whose copies are never kept.
    @Published var clipboardIgnoredApps: [String] { didSet { defaults.set(clipboardIgnoredApps, forKey: "clipboardIgnoredApps") } }
    /// Quick-access durations in minutes, shown as chips in the Keep Awake tab.
    @Published var keepAwakePresets: [Int] { didSet { defaults.set(keepAwakePresets, forKey: "keepAwakePresets") } }
    /// Duration used by the play button; zero means no time limit.
    @Published var keepAwakeDefault: Int { didSet { defaults.set(keepAwakeDefault, forKey: "keepAwakeDefault") } }
    @Published var keepAwakeAllowDisplaySleep: Bool { didSet { defaults.set(keepAwakeAllowDisplaySleep, forKey: "keepAwakeAllowDisplaySleep") } }
    @Published var keepAwakeBatteryCutoff: Bool { didSet { defaults.set(keepAwakeBatteryCutoff, forKey: "keepAwakeBatteryCutoff") } }
    @Published var keepAwakeShowCollapsed: Bool { didSet { defaults.set(keepAwakeShowCollapsed, forKey: "keepAwakeShowCollapsed") } }
    /// Last custom duration, offered again by the "Outro" chip.
    @Published var keepAwakeCustomQuantity: Int { didSet { defaults.set(keepAwakeCustomQuantity, forKey: "keepAwakeCustomQuantity") } }
    @Published var keepAwakeCustomUnit: KeepAwakeUnit { didSet { defaults.set(keepAwakeCustomUnit.rawValue, forKey: "keepAwakeCustomUnit") } }
    @Published var keepAwakeCustomUsed: Bool { didSet { defaults.set(keepAwakeCustomUsed, forKey: "keepAwakeCustomUsed") } }

    var pomodoro: PomodoroSettings {
        PomodoroSettings(focusMinutes: pomodoroFocusMinutes, shortBreakMinutes: pomodoroShortBreakMinutes,
                         longBreakMinutes: pomodoroLongBreakMinutes, sessions: pomodoroSessions)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["systemMediaEnabled": true, "spotifyEnabled": true, "browserEnabled": false,
                                     "browser": "safari", "expandOnHover": true, "compactHover": true,
                                     "reduceMotion": false, "soundEnabled": true,
                                     "offerMoveToApplications": true,
                                     "pomodoroFocusMinutes": 25, "pomodoroShortBreakMinutes": 5,
                                     "pomodoroLongBreakMinutes": 15, "pomodoroSessions": 4,
                                     "pomodoroAutoStart": false, "agentsEnabled": false,
                                     "agentsPaused": false, "agentPermissionWait": 30,
                                     "agentAlertMode": "sound", "agentAlertSound": "Ping", "agentAlertCompletions": true,
                                     "callAdjust": true, "callAlertMode": "silent", "callUsesMicrophone": true,
                                     "meetingsEnabled": false, "meetingLeadMinutes": 5, "meetingsLinkOnly": true,
                                     "meetingExcludedCalendars": [String](),
                                     "shelfEnabled": true, "shelfExpiryHours": 24, "shelfDragMoves": false, "shelfRemoveAfterDrop": true,
                                     "shelfShowCollapsed": true, "screenshotsToShelf": false, "screenshotNotice": true,
                                     "screenshotRecordings": false, "downloadsNotify": false, "downloadsToShelf": false,
                                     "powerNotice": true, "powerChargedNotice": true, "powerLowNotice": false,
                                     "levelHUD": false, "headphonesNotice": false, "clipboardEnabled": false,
                                     "clipboardLimit": 20, "clipboardExpiryHours": 24, "clipboardNotice": false,
                                     "clipboardIgnoredApps": ClipboardPolicy.defaultIgnoredApps,
                                     "keepAwakePresets": KeepAwakePresets.defaults, "keepAwakeDefault": 60,
                                     "keepAwakeAllowDisplaySleep": false, "keepAwakeBatteryCutoff": true,
                                     "keepAwakeShowCollapsed": true, "keepAwakeCustomQuantity": 3,
                                     "keepAwakeCustomUnit": "hours", "keepAwakeCustomUsed": false])
        systemMediaEnabled = defaults.bool(forKey: "systemMediaEnabled")
        spotifyEnabled = defaults.bool(forKey: "spotifyEnabled")
        browserEnabled = defaults.bool(forKey: "browserEnabled")
        browser = MediaSource(rawValue: defaults.string(forKey: "browser") ?? "safari") == .chrome ? .chrome : .safari
        expandOnHover = defaults.bool(forKey: "expandOnHover")
        compactHover = defaults.bool(forKey: "compactHover")
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
        agentAlertMode = AgentAlertMode(rawValue: defaults.string(forKey: "agentAlertMode") ?? "") ?? .sound
        agentAlertSound = defaults.string(forKey: "agentAlertSound") ?? "Ping"
        agentAlertCompletions = defaults.bool(forKey: "agentAlertCompletions")
        callAdjust = defaults.bool(forKey: "callAdjust")
        callAlertMode = CallAlertMode(rawValue: defaults.string(forKey: "callAlertMode") ?? "") ?? .silent
        callUsesMicrophone = defaults.bool(forKey: "callUsesMicrophone")
        meetingsEnabled = defaults.bool(forKey: "meetingsEnabled")
        let lead = defaults.integer(forKey: "meetingLeadMinutes")
        meetingLeadMinutes = MeetingSchedule.leadOptions.contains(lead) ? lead : 5
        meetingsLinkOnly = defaults.bool(forKey: "meetingsLinkOnly")
        meetingExcludedCalendars = defaults.stringArray(forKey: "meetingExcludedCalendars") ?? []
        shelfEnabled = defaults.bool(forKey: "shelfEnabled")
        let expiry = defaults.integer(forKey: "shelfExpiryHours")
        shelfExpiryHours = ShelfExpiry.options.contains(expiry) ? expiry : 24
        shelfDragMoves = defaults.bool(forKey: "shelfDragMoves")
        shelfRemoveAfterDrop = defaults.bool(forKey: "shelfRemoveAfterDrop")
        shelfShowCollapsed = defaults.bool(forKey: "shelfShowCollapsed")
        screenshotsToShelf = defaults.bool(forKey: "screenshotsToShelf")
        screenshotNotice = defaults.bool(forKey: "screenshotNotice")
        screenshotRecordings = defaults.bool(forKey: "screenshotRecordings")
        downloadsNotify = defaults.bool(forKey: "downloadsNotify")
        downloadsToShelf = defaults.bool(forKey: "downloadsToShelf")
        powerNotice = defaults.bool(forKey: "powerNotice")
        powerChargedNotice = defaults.bool(forKey: "powerChargedNotice")
        powerLowNotice = defaults.bool(forKey: "powerLowNotice")
        levelHUD = defaults.bool(forKey: "levelHUD")
        headphonesNotice = defaults.bool(forKey: "headphonesNotice")
        clipboardEnabled = defaults.bool(forKey: "clipboardEnabled")
        let limit = defaults.integer(forKey: "clipboardLimit")
        clipboardLimit = Clipboard.limitOptions.contains(limit) ? limit : 20
        let clipExpiry = defaults.integer(forKey: "clipboardExpiryHours")
        clipboardExpiryHours = ShelfExpiry.options.contains(clipExpiry) ? clipExpiry : 24
        clipboardNotice = defaults.bool(forKey: "clipboardNotice")
        clipboardIgnoredApps = defaults.stringArray(forKey: "clipboardIgnoredApps") ?? ClipboardPolicy.defaultIgnoredApps
        keepAwakePresets = KeepAwakePresets.normalized(defaults.array(forKey: "keepAwakePresets") as? [Int] ?? KeepAwakePresets.defaults)
        keepAwakeDefault = min(KeepAwakePresets.range.upperBound, max(0, defaults.integer(forKey: "keepAwakeDefault")))
        keepAwakeAllowDisplaySleep = defaults.bool(forKey: "keepAwakeAllowDisplaySleep")
        keepAwakeBatteryCutoff = defaults.bool(forKey: "keepAwakeBatteryCutoff")
        keepAwakeShowCollapsed = defaults.bool(forKey: "keepAwakeShowCollapsed")
        let unit = KeepAwakeUnit(rawValue: defaults.string(forKey: "keepAwakeCustomUnit") ?? "") ?? .hours
        keepAwakeCustomUnit = unit
        keepAwakeCustomQuantity = min(unit.maximumQuantity, max(1, defaults.integer(forKey: "keepAwakeCustomQuantity")))
        keepAwakeCustomUsed = defaults.bool(forKey: "keepAwakeCustomUsed")
    }
}
