import Darwin
import Foundation
import NotchCore

/// Local Unix socket that receives payloads from `notch-hook`. Runs on its own queue and
/// exists only while assistant notifications are enabled and not paused.
/// Permission requests keep their connection open until answered, expired or abandoned.
final class AgentHookServer: @unchecked Sendable {
    static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Notch/agents.sock")
    }

    private static let payloadLimit = 4 * 1024 * 1024
    private let queue = DispatchQueue(label: "dev.vinicius.Notch.agents")
    private var listener: DispatchSourceRead?
    private var pending: [UUID: DispatchSourceRead] = [:]
    private let onEvent: @Sendable (AgentEvent) -> Void
    private let onGone: @Sendable (UUID) -> Void

    init(onEvent: @escaping @Sendable (AgentEvent) -> Void, onGone: @escaping @Sendable (UUID) -> Void) {
        self.onEvent = onEvent
        self.onGone = onGone
    }

    func start() { queue.async { self.open() } }

    /// Closing pending connections without a reply hands the request back to the assistant.
    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for source in self.pending.values { source.cancel() }
            self.pending = [:]
            unlink(Self.socketURL.path)
        }
    }

    func respond(_ id: UUID, with data: Data?) {
        queue.async {
            guard let source = self.pending.removeValue(forKey: id) else { return }
            if let data { Self.write(data, to: Int32(source.handle)) }
            source.cancel()
        }
    }

    private func open() {
        guard listener == nil else { return }
        let url = Self.socketURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        unlink(url.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = url.path
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else { close(fd); return }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept(on: fd) }
        source.setCancelHandler { close(fd) }
        listener = source
        source.resume()
    }

    private func accept(on listening: Int32) {
        while true {
            let client = Darwin.accept(listening, nil, nil)
            guard client >= 0 else { return }
            handle(client)
        }
    }

    private func handle(_ fd: Int32) {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { close(fd); return }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        // The helper writes everything right away; this only bounds a misbehaving peer.
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        // Header "<agent> <length>\n", then exactly <length> bytes of hook JSON.
        var data = Data()
        var expected: Int?
        var agent: AgentKind?
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            if expected == nil, let newline = data.firstIndex(of: 10) {
                let header = String(decoding: data[data.startIndex..<newline], as: UTF8.self).split(separator: " ")
                guard header.count == 2, let length = Int(header[1]), length <= Self.payloadLimit else { close(fd); return }
                agent = AgentKind(rawValue: String(header[0]))
                data = Data(data[(newline + 1)...])
                expected = length
            }
            if let expected, data.count >= expected { break }
            guard data.count <= Self.payloadLimit + 64 else { close(fd); return }
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { close(fd); return }
            data.append(buffer, count: count)
        }
        guard let agent, let event = AgentHook.event(agent: agent, payload: data) else { close(fd); return }
        guard event.kind.waitsForAnswer else { close(fd); onEvent(event); return }
        // Readable again only when the helper goes away (hook timeout or the user answered elsewhere).
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let id = event.id
        source.setEventHandler { [weak self] in
            guard let self, self.pending.removeValue(forKey: id) != nil else { return }
            source.cancel()
            self.onGone(id)
        }
        source.setCancelHandler { close(fd) }
        pending[id] = source
        source.resume()
        onEvent(event)
    }

    private static func write(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if sent <= 0 { return }
                offset += sent
            }
        }
    }
}
