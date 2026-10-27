import SwiftUI
import AppKit
import UserNotifications

@main struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppDelegate.model

    var body: some Scene {
        MenuBarExtra("Notch", systemImage: "rectangle.topthird.inset.filled") {
            Button("Abrir ilha") { delegate.panel?.showExpanded() }
            Button("Temporizador") { model.timerPage = true; delegate.panel?.showExpanded() }
            Divider()
            SettingsLink { Text("Configurações…") }
                .keyboardShortcut(",")
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            Divider()
            Button("Sair do Notch") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        Settings { SettingsView(model: model, preferences: model.preferences, login: model.login) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let model = AppModel()
    var panel: IslandPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            if await ApplicationMover.moveIfAccepted(preferences: Self.model.preferences) { return }
            self.launch()
        }
    }

    private func launch() {
        let identifier = Bundle.main.bundleIdentifier ?? "dev.vinicius.Notch"
        if NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter({ $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }).count > 0 {
            NSApp.terminate(nil)
            return
        }
        if Bundle.main.bundleURL.pathExtension == "app" { UNUserNotificationCenter.current().delegate = self }
        panel = IslandPanelController(model: Self.model)
        Self.model.start()
    }

    func applicationWillTerminate(_ notification: Notification) { Self.model.stop() }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The app already plays the timer sound once, regardless of notification authorization.
        completionHandler([.banner])
    }
}
