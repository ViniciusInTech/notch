import Darwin
import Foundation

// Forwards a hook payload to the running Notch over a local socket.
// Exits silently with no output when Notch is closed or paused, so the
// assistant falls back to its own prompt. Usage: notch-hook <claude|codex|cursor>

let agent = CommandLine.arguments.dropFirst().first ?? "claude"
let input = FileHandle.standardInput.readDataToEndOfFile()
let path = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Notch/agents.sock").path

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
let capacity = MemoryLayout.size(ofValue: address.sun_path)
guard path.utf8.count < capacity else { exit(0) }
withUnsafeMutableBytes(of: &address.sun_path) { buffer in
    buffer.copyBytes(from: path.utf8)
    buffer[path.utf8.count] = 0
}
let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard connected == 0 else { exit(0) }
var on: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
// Notch answers or gives up well before this; it only guards against a stuck app.
var timeout = timeval(tv_sec: 3700, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

func send(_ data: Data) -> Bool {
    data.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let sent = write(fd, raw.baseAddress! + offset, raw.count - offset)
            if sent <= 0 { return false }
            offset += sent
        }
        return true
    }
}

// Length-prefixed so the connection stays open both ways: Notch reads closure as "abandoned".
guard send(Data("\(agent) \(input.count)\n".utf8) + input) else { exit(0) }

var reply = Data()
var buffer = [UInt8](repeating: 0, count: 4096)
while true {
    let count = read(fd, &buffer, buffer.count)
    if count <= 0 { break }
    reply.append(buffer, count: count)
}
close(fd)
if !reply.isEmpty { FileHandle.standardOutput.write(reply) }
exit(0)
