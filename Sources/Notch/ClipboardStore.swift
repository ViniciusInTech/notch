import AppKit
import Combine
import ImageIO
import NotchCore
import UniformTypeIdentifiers
import os

private let clipLog = Logger(subsystem: "dev.vinicius.Notch", category: "clipboard")

/// What was copied, kept on the shelf's second section. The pasteboard is never polled: it is read
/// once after Command-C/X and once when the island opens, comparing its change count. Reading and
/// image work run off the main actor; the list is saved in UserDefaults and images in a 0700 folder.
@MainActor final class ClipboardStore: ObservableObject {
    @Published private(set) var clipboard = Clipboard()
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]
    private let defaults: UserDefaults
    private var lastChange: Int
    private var pendingThumbnails: Set<UUID> = []
    private var captureTask: Task<Void, Never>?
    var limit = 20
    var expiryHours = 24
    var ignoredApps: [String] = []
    /// Called with the kind of each new entry.
    var captured: ((ClipKind) -> Void)?

    var entries: [ClipEntry] { clipboard.entries }

    nonisolated static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch/Clipboard", isDirectory: true)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastChange = NSPasteboard.general.changeCount
        if let data = defaults.data(forKey: "clipboardItems"), let entries = try? JSONDecoder().decode([ClipEntry].self, from: data) {
            clipboard = Clipboard(entries: entries)
        }
    }

    // MARK: Capturing

    /// After Command-C/X: the app writes the pasteboard right after the key, so look shortly
    /// after, and once more a bit later for slow apps.
    func copyShortcutPressed() {
        captureTask?.cancel()
        let source = NSWorkspace.shared.frontmostApplication
        captureTask = Task { [weak self] in
            for delay in [250_000_000, 900_000_000] as [UInt64] {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard let self else { return }
                if await self.captureIfChanged(source: source) { return }
            }
        }
    }

    /// Picks up something copied from a menu or a button while the island was closed.
    func checkNow() {
        let source = NSWorkspace.shared.frontmostApplication
        Task { await captureIfChanged(source: source) }
    }

    /// Reads the pasteboard if it changed since the last look; true when it had changed.
    @discardableResult private func captureIfChanged(source: NSRunningApplication?) async -> Bool {
        let change = NSPasteboard.general.changeCount
        guard change != lastChange else { return false }
        lastChange = change
        let bundle = source?.bundleIdentifier, name = source?.localizedName
        let ignored = ignoredApps
        let entry = await Task.detached { Self.read(change: change, sourceBundle: bundle, sourceName: name, ignored: ignored) }.value
        guard let entry else { return true }
        let removed = clipboard.add(entry, limit: limit)
        clipLog.info("captured kind=\(entry.kind.rawValue, privacy: .public)")
        discard(removed)
        save()
        captured?(entry.kind)
        return true
    }

    /// Text or an image from the general pasteboard; nil for files, private or ignored content.
    nonisolated private static func read(change: Int, sourceBundle: String?, sourceName: String?, ignored: [String]) -> ClipEntry? {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == change else { return nil }
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard !ClipboardPolicy.shouldSkip(types: types, sourceBundle: sourceBundle, ignored: ignored) else { return nil }
        // Files copied in Finder belong to the shelf's drag and drop, not here.
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) { return nil }
        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, text.count <= Clipboard.maximumText else { return nil }
            return .text(text, source: sourceName)
        }
        let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
        guard let data, data.count <= 30_000_000, let png = pngData(data) else { return nil }
        guard let folder = try? prepareFolder() else { return nil }
        let id = UUID()
        let file = id.uuidString + ".png"
        do { try png.write(to: folder.appendingPathComponent(file), options: .atomic) } catch { return nil }
        let fingerprint = "i:\(png.count):\(png.prefix(64).base64EncodedString())\(png.suffix(64).base64EncodedString())"
        return ClipEntry(id: id, kind: .image, file: file, fingerprint: fingerprint, sourceName: sourceName)
    }

    nonisolated private static func pngData(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        if CGImageSourceGetType(source) as String? == UTType.png.identifier { return data }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    nonisolated private static func prepareFolder() throws -> URL {
        let folder = Self.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return folder
    }

    // MARK: Using

    /// Puts an entry back on the pasteboard; it does not come back as a new entry.
    func copy(_ entry: ClipEntry) {
        if let text = entry.text {
            write { $0.setString(text, forType: .string) }
            return
        }
        guard let file = entry.file else { return }
        let url = Self.folder.appendingPathComponent(file)
        Task {
            guard let data = await Task.detached(operation: { try? Data(contentsOf: url) }).value else { return }
            write { $0.setData(data, forType: .png) }
        }
    }

    private func write(_ body: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        body(pasteboard)
        lastChange = pasteboard.changeCount
    }

    func fileURL(_ entry: ClipEntry) -> URL? { entry.file.map { Self.folder.appendingPathComponent($0) } }

    func togglePin(_ id: UUID) {
        clipboard.togglePin(id)
        if !(clipboard.entries.first { $0.id == id }?.pinned ?? true) { discard(clipboard.trim(limit: limit)) }
        save()
    }

    func remove(_ id: UUID) {
        guard let entry = clipboard.remove(id) else { return }
        discard([entry])
        save()
    }

    func clear() {
        discard(clipboard.clearUnpinned())
        save()
    }

    /// Removes everything, pinned included, when the feature is turned off.
    func eraseAll() {
        let all = clipboard.entries
        clipboard = Clipboard()
        discard(all)
        save()
    }

    /// Applied when the panel opens and after settings change; there is no expiry timer.
    func prune() {
        let removed = clipboard.removeExpired(hours: expiryHours) + clipboard.trim(limit: limit)
        guard !removed.isEmpty else { return }
        discard(removed)
        save()
    }

    // MARK: Thumbnails

    func thumbnail(for entry: ClipEntry) -> NSImage? {
        if let image = thumbnails[entry.id] { return image }
        guard let url = fileURL(entry), !pendingThumbnails.contains(entry.id) else { return nil }
        pendingThumbnails.insert(entry.id)
        let id = entry.id
        Task {
            let image = await Task.detached { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                kCGImageSourceThumbnailMaxPixelSize: 160,
                                                kCGImageSourceCreateThumbnailWithTransform: true]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
            pendingThumbnails.remove(id)
            if let image { thumbnails[id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
        }
        return nil
    }

    // MARK: Storage

    private func discard(_ entries: [ClipEntry]) {
        let files = entries.compactMap(\.file)
        entries.forEach { thumbnails[$0.id] = nil }
        guard !files.isEmpty else { return }
        let folder = Self.folder
        Task.detached { files.forEach { try? FileManager.default.removeItem(at: folder.appendingPathComponent($0)) } }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(clipboard.entries) { defaults.set(data, forKey: "clipboardItems") }
    }
}
