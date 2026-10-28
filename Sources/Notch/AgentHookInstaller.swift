import Foundation
import NotchCore

/// Adds or removes the `notch-hook` entries in each assistant's user-level hook file.
/// Other hooks are preserved; the original file is copied once to `<file>.notch-backup`.
enum AgentHookInstaller {
    private static let marker = "notch-hook"

    static var helperURL: URL {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .deletingLastPathComponent().appendingPathComponent("notch-hook")
    }

    static var helperExists: Bool { FileManager.default.isExecutableFile(atPath: helperURL.path) }

    static func configURL(_ agent: AgentKind) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch agent {
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        case .cursor: return home.appendingPathComponent(".cursor/hooks.json")
        }
    }

    static func command(_ agent: AgentKind) -> String { "\"\(helperURL.path)\" \(agent.rawValue)" }

    static func isInstalled(_ agent: AgentKind) -> Bool {
        guard let data = try? Data(contentsOf: configURL(agent)) else { return false }
        return String(decoding: data, as: UTF8.self).contains(marker)
    }

    static func install(_ agent: AgentKind) throws { try rewrite(agent, adding: true) }
    static func uninstall(_ agent: AgentKind) throws { try rewrite(agent, adding: false) }

    private static func rewrite(_ agent: AgentKind, adding: Bool) throws {
        let url = configURL(agent)
        let manager = FileManager.default
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
            }
            root = object
            let backup = url.appendingPathExtension("notch-backup")
            if !manager.fileExists(atPath: backup.path) { try manager.copyItem(at: url, to: backup) }
        } else if !adding { return }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = command(agent)
        if agent == .cursor {
            root["version"] = root["version"] ?? 1
            var entries = (hooks["stop"] as? [[String: Any]] ?? []).filter { !isOurs($0["command"]) }
            if adding { entries.append(["command": command]) }
            hooks["stop"] = entries.isEmpty ? nil : entries
        } else {
            // Waits while the request is read or answered on the island; Notch gives up on its own
            // countdown, which pauses while the mini chat is open, and then returns no decision.
            let events: [(String, [String: Any])] = [
                ("PermissionRequest", ["type": "command", "command": command, "timeout": 3600]),
                ("Stop", ["type": "command", "command": command, "timeout": 10])
            ]
            for (event, handler) in events {
                var groups: [[String: Any]] = (hooks[event] as? [[String: Any]] ?? []).compactMap { group in
                    var group = group
                    let handlers = (group["hooks"] as? [[String: Any]] ?? []).filter { !isOurs($0["command"]) }
                    if handlers.isEmpty { return nil }
                    group["hooks"] = handlers
                    return group
                }
                if adding { groups.append(event == "PermissionRequest" ? ["matcher": "*", "hooks": [handler]] : ["hooks": [handler]]) }
                hooks[event] = groups.isEmpty ? nil : groups
            }
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks

        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    private static func isOurs(_ command: Any?) -> Bool { (command as? String)?.contains(marker) == true }
}
