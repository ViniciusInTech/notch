import Foundation
import Darwin
import NotchCore

/// Reads the macOS Now Playing session (Music, Spotify, browsers, any app that
/// publishes to Control Center). Since macOS 15.4, MediaRemote only answers
/// Apple-signed processes, so `/usr/bin/perl` loads the bridge library and
/// streams JSON lines; commands go back through its stdin. The helper waits on
/// notifications, without polling, and exits when the app closes its stdin.
final class SystemMediaProvider: @unchecked Sendable {
    /// Delivered on the main actor; nil media means nothing is playing.
    var onUpdate: (@MainActor (NowPlayingUpdate) -> Void)?
    /// Delivered on the main actor after repeated helper failures.
    var onFailure: (@MainActor (String) -> Void)?

    private let queue = DispatchQueue(label: "dev.vinicius.Notch.nowplaying", qos: .utility)
    private var process: Process?
    private var input: FileHandle?
    private var wanted = false
    private var failures = 0
    private var restart: DispatchWorkItem?

    private static let script = """
    use DynaLoader;
    my $library = DynaLoader::dl_load_file($ARGV[0], 0) or exit 2;
    my $symbol = DynaLoader::dl_find_symbol($library, "notch_media_stream") or exit 2;
    DynaLoader::dl_install_xsub("main::stream", $symbol);
    stream();
    """

    static var libraryURL: URL? {
        let name = "libNotchMediaBridge.dylib"
        let candidates = [Bundle.main.privateFrameworksURL?.appendingPathComponent(name),
                          Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name)]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func start() {
        queue.async { [self] in
            wanted = true
            failures = 0
            if process == nil { launch() }
        }
    }

    func stop() {
        queue.async { [self] in
            wanted = false
            restart?.cancel(); restart = nil
            terminate()
        }
    }

    func perform(_ command: MediaCommand) {
        let line: String
        switch command {
        case .togglePlayback: line = "toggle"
        case .next: line = "next"
        case .previous: line = "previous"
        case .seek(let seconds):
            guard seconds.isFinite else { return }
            line = "seek \(max(0, seconds))"
        case .volume: return
        }
        queue.async { [self] in try? input?.write(contentsOf: Data((line + "\n").utf8)) }
    }

    private func launch() {
        guard let library = Self.libraryURL else { return fail("A ponte do Tocando agora não está no app. Recompile o Notch.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.script, library.path]
        let output = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] ended in
            self?.queue.async { self?.ended(ended) }
        }
        do { try process.run() } catch { return fail(error.localizedDescription) }
        self.process = process
        self.input = input.fileHandleForWriting
        let reader = output.fileHandleForReading
        Thread.detachNewThread { [weak self] in self?.read(reader) }
    }

    /// Splits stdout into lines; a cover image is the largest payload, capped by the bridge at 2 MB.
    private func read(_ handle: FileHandle) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        // read(2) returns what the pipe holds now; FileHandle.read(upToCount:) waits to fill the count.
        while true {
            let count = chunk.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { break }
            buffer.append(contentsOf: chunk[0..<count])
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let update = MediaParser.nowPlaying(line) else { continue }
                queue.async { [weak self] in self?.failures = 0 }
                // The main queue keeps line order; separate Tasks could deliver a stale state last.
                DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.onUpdate?(update) } }
            }
            if buffer.count > 4_000_000 { buffer.removeAll() }
        }
    }

    private func ended(_ ended: Process) {
        guard ended === process else { return }
        process = nil
        try? input?.close(); input = nil
        guard wanted else { return }
        Task { @MainActor [weak self] in self?.onUpdate?(NowPlayingUpdate(media: nil)) }
        failures += 1
        guard failures <= 3 else { return fail("O macOS não entregou o Tocando agora (código \(ended.terminationStatus)).") }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wanted, self.process == nil else { return }
            self.launch()
        }
        restart = work
        queue.asyncAfter(deadline: .now() + .seconds(2 * failures), execute: work)
    }

    private func terminate() {
        guard let process else { return }
        self.process = nil
        try? input?.close(); input = nil
        if process.isRunning { process.terminate() }
    }

    private func fail(_ message: String) {
        Task { @MainActor [weak self] in self?.onFailure?(message) }
    }
}
