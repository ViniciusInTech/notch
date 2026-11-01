import AppKit
import Combine
import NotchCore
import QuickLookThumbnailing
import UniformTypeIdentifiers
import os

private let shelfLog = Logger(subsystem: "dev.vinicius.Notch", category: "shelf")

/// Files kept on the island. References are bookmarks to the originals; only content without a
/// file (browser images, links, text) is written to Notch's own folder and deleted on expiry.
/// File work runs off the main actor; the list is saved in UserDefaults.
@MainActor final class ShelfStore: ObservableObject {
    @Published private(set) var shelf = Shelf()
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    private let defaults: UserDefaults
    private var expiryHours = 24
    private var expiryTask: Task<Void, Never>?
    private var pendingThumbnails: Set<String> = []

    var items: [ShelfItem] { shelf.items }

    nonisolated static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch/Shelf", isDirectory: true)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "shelfItems"), let items = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            shelf = Shelf(items: items)
        }
    }

    func setExpiry(hours: Int) {
        expiryHours = hours
        expire()
    }

    // MARK: Adding

    func addReferences(_ urls: [URL], origin: ShelfOrigin) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        Task {
            let items = await Task.detached { files.compactMap { Self.reference($0, origin: origin) } }.value
            items.forEach(insert)
        }
    }

    /// Writes content that has no file of its own into the shelf folder.
    func addOwned(_ data: Data, name: String, origin: ShelfOrigin) {
        Task {
            let item = await Task.detached { Self.write(data, name: name, origin: origin) }.value
            if let item { insert(item) }
        }
    }

    /// Files a browser promised, received straight into the shelf folder.
    func addPromises(_ promises: [NSFilePromiseReceiver]) {
        guard let folder = try? Self.prepareFolder() else { return }
        let queue = OperationQueue()
        for promise in promises {
            promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { [weak self] url, error in
                guard error == nil else { return }
                Task { @MainActor in self?.insert(ShelfItem(path: url.path, owned: true, origin: .browser)) }
            }
        }
    }

    private func insert(_ item: ShelfItem) {
        let dropped = shelf.add(item)
        shelfLog.info("add origin=\(item.origin.rawValue, privacy: .public) owned=\(item.owned)")
        discard(dropped)
        save()
        expire()
    }

    // MARK: Removing

    func remove(_ id: UUID) {
        guard let item = shelf.remove(id) else { return }
        discard([item])
        save()
        expire()
    }

    /// A move out of the shelf took the file with it; nothing is left to delete.
    func moved(_ id: UUID) {
        guard shelf.remove(id) != nil else { return }
        save()
        expire()
    }

    /// Delivered by a copy: leaves the shelf right away. The receiver may still be copying, so
    /// an owned file is deleted only after a minute.
    func delivered(_ id: UUID) {
        guard let item = shelf.remove(id) else { return }
        thumbnails[item.path] = nil
        save()
        expire()
        guard item.owned else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            self?.discard([item])
        }
    }

    func clear() {
        discard(shelf.removeAll())
        save()
        expire()
    }

    /// Drops expired items and waits for the next expiry with a single task.
    func expire() {
        expiryTask?.cancel()
        let expired = shelf.removeExpired(hours: expiryHours)
        if !expired.isEmpty { discard(expired); save() }
        guard let next = shelf.nextExpiry(hours: expiryHours) else { return }
        let wait = max(1, next.timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) } catch { return }
            self?.expire()
        }
    }

    func suspend() { expiryTask?.cancel() }

    /// Follows moved originals and drops items whose file is gone or in the Trash.
    func validate() {
        let items = shelf.items
        guard !items.isEmpty else { return }
        Task {
            let checked = await Task.detached { items.map { ($0.id, Self.resolve($0)) } }.value
            var changed = false
            for (id, result) in checked {
                guard let current = shelf.items.first(where: { $0.id == id }) else { continue }
                if let result {
                    if result != current { shelf.update(result); changed = true }
                } else {
                    shelf.remove(id); changed = true
                }
            }
            if changed { save() }
        }
    }

    /// The current location, checked right before a drag or open.
    func resolvedURL(_ item: ShelfItem) -> URL? {
        guard let resolved = Self.resolve(item) else { remove(item.id); return nil }
        if resolved != item { shelf.update(resolved); save() }
        return resolved.url
    }

    private func discard(_ items: [ShelfItem]) {
        let owned = items.filter(\.owned).map(\.url)
        for item in items { thumbnails[item.path] = nil }
        guard !owned.isEmpty else { return }
        Task.detached {
            let folder = Self.folder.standardizedFileURL.path
            for url in owned where url.standardizedFileURL.path.hasPrefix(folder + "/") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(shelf.items) { defaults.set(data, forKey: "shelfItems") }
    }

    // MARK: Thumbnails

    /// Quick Look renders previews off the main actor; until then the type's generic icon shows.
    func thumbnail(for item: ShelfItem) -> NSImage {
        if let image = thumbnails[item.path] { return image }
        requestThumbnail(path: item.path)
        let type = UTType(filenameExtension: item.url.pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    func requestThumbnail(path: String) {
        guard thumbnails[path] == nil, !pendingThumbnails.contains(path) else { return }
        pendingThumbnails.insert(path)
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: 64, height: 64),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.nsImage
            Task { @MainActor in
                self?.pendingThumbnails.remove(path)
                if let image { self?.thumbnails[path] = image }
            }
        }
    }

    // MARK: File work, off the main actor

    nonisolated private static func reference(_ url: URL, origin: ShelfOrigin) -> ShelfItem? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let owned = url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
        return ShelfItem(path: url.standardizedFileURL.path, bookmark: bookmark, owned: owned, origin: origin)
    }

    nonisolated private static func prepareFolder() throws -> URL {
        let folder = Self.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return folder
    }

    nonisolated private static func write(_ data: Data, name: String, origin: ShelfOrigin) -> ShelfItem? {
        guard let folder = try? prepareFolder() else { return nil }
        let safe = WatchedFile.safeName(name, fallback: "Item")
        let base = (safe as NSString).deletingPathExtension, ext = (safe as NSString).pathExtension
        var url = folder.appendingPathComponent(safe)
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)")
            index += 1
        }
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return ShelfItem(path: url.path, owned: true, origin: origin)
    }

    nonisolated private static func resolve(_ item: ShelfItem) -> ShelfItem? {
        var url = item.url
        var updated = item
        if let bookmark = item.bookmark {
            var stale = false
            if let found = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                    relativeTo: nil, bookmarkDataIsStale: &stale) {
                url = found
                if stale { updated.bookmark = try? found.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
            }
        }
        let path = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path), !path.contains("/.Trash/") else { return nil }
        updated.path = path
        return updated
    }
}

/// Source of drags out of the shelf: copy by default, move with ⌘ (or the reverse, per preference).
/// It outlives the island views, which may collapse while the drag is still in flight.
@MainActor final class ShelfDragCoordinator: NSObject, NSDraggingSource {
    static let shared = ShelfDragCoordinator()
    weak var store: ShelfStore?
    var movesByDefault = false
    /// Whether a drop elsewhere takes the item off the shelf, copied or moved.
    var removesAfterDrop = true
    private var dragging: UUID?

    func begin(_ item: ShelfItem, from view: NSView, event: NSEvent) {
        guard let store, let url = store.resolvedURL(item) else { return }
        dragging = item.id
        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = store.thumbnail(for: item)
        draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 36, height: 36), contents: icon)
        view.beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard context == .outsideApplication else { return [] }
        let command = NSEvent.modifierFlags.contains(.command), option = NSEvent.modifierFlags.contains(.option)
        let moves = MainActor.assumeIsolated { movesByDefault }
        return (moves ? !option : command) ? .move : .copy
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated {
            defer { dragging = nil }
            guard let id = dragging else { return }
            if operation.contains(.move) { store?.moved(id) }
            else if !operation.isEmpty && removesAfterDrop { store?.delivered(id) }
            else { store?.validate() }
        }
    }
}
