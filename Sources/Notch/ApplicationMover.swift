import AppKit
import NotchCore

/// Offers to copy a downloaded Notch into /Applications, where login items and Automation stay stable.
@MainActor enum ApplicationMover {
    /// Returns true when this instance is quitting so the copy in Applications can take over.
    static func moveIfAccepted(preferences: Preferences) async -> Bool {
        let source = Bundle.main.bundleURL
        guard source.pathExtension == "app", preferences.offerMoveToApplications,
              InstallLocation.shouldOfferMove(bundlePath: source.path, homeDirectory: NSHomeDirectory()) else { return false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Mover o Notch para Aplicativos?"
        alert.informativeText = "O Notch está sendo executado a partir de \(origin(of: source.path)). Em Aplicativos ele pode iniciar com o Mac e manter as permissões de Automação."
        alert.addButton(withTitle: "Mover para Aplicativos")
        alert.addButton(withTitle: "Agora não")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Não perguntar novamente"
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { preferences.offerMoveToApplications = false }
        guard response == .alertFirstButtonReturn else { return false }

        let destination = URL(fileURLWithPath: "/Applications/Notch.app")
        await terminateOtherInstances()
        do {
            // Copying touches the disk; keep it off the main actor.
            try await Task.detached(priority: .userInitiated) {
                let files = FileManager.default
                if files.fileExists(atPath: destination.path) { try files.trashItem(at: destination, resultingItemURL: nil) }
                try files.copyItem(at: source, to: destination)
            }.value
            try relaunch(destination, ejecting: InstallLocation.mountedVolume(bundlePath: source.path))
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "Não foi possível mover o Notch"
            failure.informativeText = "Arraste o Notch.app para a pasta Aplicativos pelo Finder.\n\n\(error.localizedDescription)"
            failure.runModal()
            return false
        }
        NSApp.terminate(nil)
        return true
    }

    private static func origin(of path: String) -> String {
        if path.hasPrefix("/Volumes/") { return "da imagem de instalação" }
        if path.contains("/AppTranslocation/") { return "uma pasta temporária do macOS" }
        return "Downloads"
    }

    /// Replacing an older copy requires it to quit first; the single-instance check would close the new one otherwise.
    private static func terminateOtherInstances() async {
        let identifier = Bundle.main.bundleIdentifier ?? "dev.vinicius.Notch"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        others.forEach { $0.terminate() }
        for _ in 0..<30 where others.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// A detached shell waits for this process to exit, opens the new copy and ejects the disk image.
    /// Paths are passed as positional arguments, never interpolated into the script.
    private static func relaunch(_ app: URL, ejecting volume: String?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", """
            while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
            /usr/bin/open "$2"
            if [ -n "$3" ]; then /usr/bin/hdiutil detach "$3" -quiet; fi
            """, "notch-relaunch", String(ProcessInfo.processInfo.processIdentifier), app.path, volume ?? ""]
        try process.run()
    }
}
