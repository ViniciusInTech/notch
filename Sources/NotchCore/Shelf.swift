import Foundation

public enum ShelfOrigin: String, Codable, Sendable { case drop, screenshot, download, browser }

/// A file on the shelf. References point at the original through a bookmark and cost no space;
/// only content without a file (an image or text from the browser) is kept as Notch's own copy.
public struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// Last known location; a bookmark follows the original when it moves.
    public var path: String
    public var bookmark: Data?
    /// Lives in Notch's shelf folder and is deleted with the item.
    public let owned: Bool
    public let origin: ShelfOrigin
    public let addedAt: Date

    public init(id: UUID = UUID(), path: String, bookmark: Data? = nil, owned: Bool = false,
                origin: ShelfOrigin = .drop, addedAt: Date = Date()) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.owned = owned
        self.origin = origin
        self.addedAt = addedAt
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var url: URL { URL(fileURLWithPath: path) }
}

public struct Shelf: Equatable, Sendable {
    public static let capacity = 30
    /// Newest first.
    public private(set) var items: [ShelfItem]

    public init(items: [ShelfItem] = []) {
        self.items = Array(items.sorted { $0.addedAt > $1.addedAt }.prefix(Self.capacity))
    }

    /// Adds at the front; the same path moves to the front instead of repeating.
    /// Returns what fell off the end, so owned copies can be deleted.
    @discardableResult public mutating func add(_ item: ShelfItem) -> [ShelfItem] {
        var removed: [ShelfItem] = []
        if let index = items.firstIndex(where: { $0.path == item.path }) {
            let old = items.remove(at: index)
            if old.owned && old.id != item.id && !item.owned { removed.append(old) }
        }
        items.insert(item, at: 0)
        while items.count > Self.capacity { removed.append(items.removeLast()) }
        return removed
    }

    @discardableResult public mutating func remove(_ id: UUID) -> ShelfItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    public mutating func update(_ item: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    @discardableResult public mutating func removeAll() -> [ShelfItem] {
        defer { items = [] }
        return items
    }

    /// Items older than `hours`; zero keeps them until removed.
    @discardableResult public mutating func removeExpired(at now: Date = Date(), hours: Int) -> [ShelfItem] {
        guard hours > 0 else { return [] }
        let limit = now.addingTimeInterval(-Double(hours) * 3600)
        let expired = items.filter { $0.addedAt <= limit }
        items.removeAll { $0.addedAt <= limit }
        return expired
    }

    public func nextExpiry(hours: Int) -> Date? {
        guard hours > 0 else { return nil }
        return items.map { $0.addedAt.addingTimeInterval(Double(hours) * 3600) }.min()
    }
}

public enum ShelfExpiry {
    /// Hours; zero means never.
    public static let options = [1, 24, 168, 0]

    public static func label(hours: Int) -> String {
        switch hours {
        case 0: return "Nunca"
        case 1: return "1 hora"
        case 168: return "7 dias"
        default: return hours % 24 == 0 ? "\(hours / 24 == 1 ? "24 horas" : "\(hours / 24) dias")" : "\(hours) horas"
        }
    }
}

public enum WatchedFile {
    private static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload"]

    /// Hidden files and browsers' in-progress downloads; the final name appears when they finish.
    public static func isPartial(_ name: String) -> Bool {
        if name.hasPrefix(".") || name.hasPrefix("~$") { return true }
        return partialExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Leading characters that make a file name unsafe on the shelf folder.
    public static func safeName(_ proposed: String, fallback: String) -> String {
        let cleaned = proposed.components(separatedBy: CharacterSet(charactersIn: "/:\0\n\r")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = String(cleaned.drop(while: { $0 == "." }).prefix(120))
        return trimmed.isEmpty ? fallback : trimmed
    }
}
