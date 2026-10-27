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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["spotifyEnabled": true, "browserEnabled": false,
                                     "browser": "safari", "expandOnHover": true,
                                     "reduceMotion": false, "soundEnabled": true,
                                     "offerMoveToApplications": true])
        spotifyEnabled = defaults.bool(forKey: "spotifyEnabled")
        browserEnabled = defaults.bool(forKey: "browserEnabled")
        browser = MediaSource(rawValue: defaults.string(forKey: "browser") ?? "safari") == .chrome ? .chrome : .safari
        expandOnHover = defaults.bool(forKey: "expandOnHover")
        reduceMotion = defaults.bool(forKey: "reduceMotion")
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        offerMoveToApplications = defaults.bool(forKey: "offerMoveToApplications")
    }
}
