import Foundation
import NotchCore

/// Reports files that appear in one folder. A kqueue source wakes it only when the folder
/// changes; listing and filtering run on its own queue, never on the main actor.
final class FolderWatcher: @unchecked Sendable {
    private let queue: DispatchQueue
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private var folder: URL?
    private var onNew: (@Sendable ([URL]) -> Void)?

    init(label: String) {
        queue = DispatchQueue(label: "dev.vinicius.Notch.watch.\(label)")
    }

    /// Files already there are ignored; finished, visible files that show up later are reported.
    func start(_ url: URL, onNew: @escaping @Sendable ([URL]) -> Void) {
        queue.async { [self] in
            guard folder?.standardizedFileURL != url.standardizedFileURL || source == nil else { self.onNew = onNew; return }
            cancel()
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { return }
            folder = url
            self.onNew = onNew
            known = names()
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: queue)
            source.setEventHandler { [weak self] in self?.scan() }
            source.setCancelHandler { close(descriptor) }
            self.source = source
            source.resume()
        }
    }

    func stop() {
        queue.async { [self] in cancel() }
    }

    private func cancel() {
        source?.cancel()
        source = nil
        folder = nil
        onNew = nil
        known = []
    }

    private func names() -> Set<String> {
        guard let folder else { return [] }
        return Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    private func scan() {
        guard let folder else { return }
        let current = names()
        let added = current.subtracting(known).filter { !WatchedFile.isPartial($0) }.sorted()
        known = current
        guard !added.isEmpty else { return }
        onNew?(added.map { folder.appendingPathComponent($0) })
    }
}
