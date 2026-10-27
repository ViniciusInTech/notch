import Foundation
import Darwin

enum AutomationFailure: LocalizedError {
    case failed(String), timeout, oversized
    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        case .timeout: return "A fonte não respondeu. Verifique as permissões de Automação e tente novamente."
        case .oversized: return "A fonte retornou uma resposta maior que o limite permitido."
        }
    }
}

/// Serializes short scripts and never waits for another app on the main thread.
final class AutomationRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.vinicius.Notch.automation", qos: .utility)

    func run(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    let timeout = DispatchWorkItem {
                        if process.isRunning {
                            process.terminate()
                            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                            }
                        }
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8, execute: timeout)
                    var data = Data()
                    while let chunk = try pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                        data.append(chunk)
                        if data.count > 65536 {
                            if process.isRunning { process.terminate() }
                            timeout.cancel()
                            continuation.resume(throwing: AutomationFailure.oversized)
                            return
                        }
                    }
                    process.waitUntilExit()
                    timeout.cancel()
                    let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
                    if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: AutomationFailure.timeout)
                    } else if process.terminationStatus != 0 {
                        continuation.resume(throwing: AutomationFailure.failed(output))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func literal(_ string: String) -> String {
        "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
