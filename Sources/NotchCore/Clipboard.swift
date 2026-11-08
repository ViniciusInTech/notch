import Foundation

public enum ClipKind: String, Codable, Sendable {
    case text, link, color, image

    /// A single web address or a hex color gets its own card; anything else is text.
    public static func classify(_ text: String) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#, options: .regularExpression) != nil { return .color }
        if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host?.isEmpty == false { return .link }
        return .text
    }
}

/// Something copied. Text lives in the entry; an image is a file in Notch's clipboard folder.
public struct ClipEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: ClipKind
    public let text: String?
    /// File name inside the clipboard folder, for images.
    public let file: String?
    /// Identifies identical content so copying it again moves it up instead of repeating it.
    public let fingerprint: String
    public var pinned: Bool
    public var addedAt: Date
    public let sourceName: String?

    public init(id: UUID = UUID(), kind: ClipKind, text: String? = nil, file: String? = nil, fingerprint: String,
                pinned: Bool = false, addedAt: Date = Date(), sourceName: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.file = file
        self.fingerprint = fingerprint
        self.pinned = pinned
        self.addedAt = addedAt
        self.sourceName = sourceName
    }

    public static func text(_ value: String, source: String? = nil, at date: Date = Date()) -> ClipEntry {
        ClipEntry(kind: ClipKind.classify(value), text: value, fingerprint: "t:" + value, addedAt: date, sourceName: source)
    }
}

/// Copied items, newest first. Pinned items stay out of the limit and never expire.
public struct Clipboard: Equatable, Sendable {
    public static let limitOptions = Array(stride(from: 5, through: 50, by: 5))
    public static let maximumText = 100_000
    public private(set) var entries: [ClipEntry]

    public init(entries: [ClipEntry] = []) {
        self.entries = entries.sorted { $0.addedAt > $1.addedAt }
    }

    public var pinnedCount: Int { entries.filter(\.pinned).count }

    /// Adds at the front; the same content moves up and keeps its pin. Returns what was dropped,
    /// so image files can be deleted.
    @discardableResult public mutating func add(_ entry: ClipEntry, limit: Int) -> [ClipEntry] {
        var removed: [ClipEntry] = []
        var next = entry
        if let index = entries.firstIndex(where: { $0.fingerprint == entry.fingerprint }) {
            let old = entries.remove(at: index)
            next.pinned = old.pinned
            if old.file != entry.file { removed.append(old) }
        }
        entries.insert(next, at: 0)
        removed += trim(limit: limit)
        return removed
    }

    @discardableResult public mutating func trim(limit: Int) -> [ClipEntry] {
        var removed: [ClipEntry] = []
        var kept = 0
        entries.removeAll { entry in
            guard !entry.pinned else { return false }
            kept += 1
            if kept > max(1, limit) { removed.append(entry); return true }
            return false
        }
        return removed
    }

    @discardableResult public mutating func remove(_ id: UUID) -> ClipEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    public mutating func togglePin(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].pinned.toggle()
    }

    /// Clears everything except pinned items.
    @discardableResult public mutating func clearUnpinned() -> [ClipEntry] {
        let removed = entries.filter { !$0.pinned }
        entries.removeAll { !$0.pinned }
        return removed
    }

    /// Unpinned entries older than `hours`; zero keeps them.
    @discardableResult public mutating func removeExpired(at now: Date = Date(), hours: Int) -> [ClipEntry] {
        guard hours > 0 else { return [] }
        let limit = now.addingTimeInterval(-Double(hours) * 3600)
        let expired = entries.filter { !$0.pinned && $0.addedAt <= limit }
        entries.removeAll { !$0.pinned && $0.addedAt <= limit }
        return expired
    }
}

public enum ClipboardPolicy {
    /// Password managers and the system's own keychain apps.
    public static let defaultIgnoredApps = ["com.1password.1password", "com.agilebits.onepassword7", "com.apple.Passwords",
                                            "com.apple.keychainaccess", "com.bitwarden.desktop", "com.lastpass.LastPass"]

    /// Markers apps put on content that must not be kept (nspasteboard.org).
    public static let privateTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                                                   "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]

    public static func shouldSkip(types: [String], sourceBundle: String?, ignored: [String]) -> Bool {
        if types.contains(where: privateTypes.contains) { return true }
        if let sourceBundle, ignored.contains(sourceBundle) { return true }
        return false
    }

    /// Copy (C) or cut (X) with Command alone. The character follows the keyboard layout; the
    /// ANSI key codes cover events without one.
    public static func isCopyShortcut(characters: String?, keyCode: Int, command: Bool, control: Bool, option: Bool) -> Bool {
        guard command && !control && !option else { return false }
        if let characters = characters?.lowercased(), !characters.isEmpty { return characters == "c" || characters == "x" }
        return keyCode == 8 || keyCode == 7
    }
}
