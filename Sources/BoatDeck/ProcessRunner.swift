import Foundation
import Darwin

final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

/// Drains pipes without blocking, even when descendants inherit them or stdin isn't consumed.
/// Timeout/cancellation covers the child lifetime and escalates to SIGKILL after a short grace period.
enum ProcessRunner {
    static let outputLimit = 1_048_576

    static func run(_ executable: String, _ arguments: [String], environment: [String: String],
                    stdin: String? = nil, timeout: TimeInterval,
                    cancellation: ProcessCancellation = ProcessCancellation(),
                    onOutput: ((String) -> Void)? = nil) -> CLIResult {
        if cancellation.isCancelled { return CLIResult(exitCode: 130, stdout: "", stderr: "Cancelled") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out; process.standardError = err; process.standardInput = input
        do { try process.run() }
        catch { return CLIResult(exitCode: -1, stdout: "", stderr: error.localizedDescription) }
        let outFD = out.fileHandleForReading.fileDescriptor, errFD = err.fileHandleForReading.fileDescriptor
        let inFD = input.fileHandleForWriting.fileDescriptor
        for fd in [outFD, errFD, inFD] { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) }
        // A child may close stdin before all input is written; get EPIPE instead of killing the app.
        _ = fcntl(inFD, F_SETNOSIGPIPE, 1)
        defer {
            try? out.fileHandleForReading.close(); try? err.fileHandleForReading.close()
            try? input.fileHandleForWriting.close()
        }
        let payload = Data((stdin ?? "").utf8)
        var inputOffset = 0, inputClosed = false
        var stdout = Data(), stderr = Data(), outTruncated = false, errTruncated = false
        var outDecoder = UTF8Chunks(), errDecoder = UTF8Chunks()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        var stoppedAt: TimeInterval?, stopCode: Int32?

        func drain(_ fd: Int32, _ data: inout Data, _ truncated: inout Bool, _ decoder: inout UTF8Chunks) {
            var buffer = [UInt8](repeating: 0, count: 8192)
            // Bound each pass so continuous output cannot starve the deadline check.
            for _ in 0..<16 {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { break }
                let chunk = Data(buffer.prefix(count))
                let text = decoder.decode(chunk)
                if !text.isEmpty { onOutput?(text) }
                let keep = min(count, max(0, outputLimit - data.count))
                data.append(chunk.prefix(keep))
                if keep < count { truncated = true }
            }
        }

        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if stoppedAt == nil && (cancellation.isCancelled || now >= deadline) {
                stopCode = cancellation.isCancelled ? 130 : 124
                stoppedAt = now
                if process.isRunning { process.terminate() }
            }
            if let stoppedAt, now - stoppedAt >= 0.3, process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
            }
            drain(outFD, &stdout, &outTruncated, &outDecoder)
            drain(errFD, &stderr, &errTruncated, &errDecoder)
            if !inputClosed {
                if inputOffset < payload.count {
                    let count = payload.withUnsafeBytes {
                        Darwin.write(inFD, $0.baseAddress!.advanced(by: inputOffset), min(8192, payload.count - inputOffset))
                    }
                    if count > 0 { inputOffset += count }
                    else if count < 0 && errno != EAGAIN && errno != EINTR { inputOffset = payload.count }
                }
                if inputOffset == payload.count {
                    try? input.fileHandleForWriting.close(); inputClosed = true
                }
            }
            if !process.isRunning {
                drain(outFD, &stdout, &outTruncated, &outDecoder)
                drain(errFD, &stderr, &errTruncated, &errDecoder)
                break
            }
            // Never wait for pipe EOF: a grandchild may keep the descriptors open indefinitely.
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.waitUntilExit() // isRunning is already false.
        for tail in [outDecoder.finish(), errDecoder.finish()] where !tail.isEmpty { onOutput?(tail) }
        var error = String(decoding: stderr, as: UTF8.self)
        if errTruncated { error += "\n[output truncated]" }
        if let stopCode { error += stopCode == 124 ? "\nCommand timed out." : "\nCommand cancelled." }
        return CLIResult(exitCode: stopCode ?? process.terminationStatus,
                         stdout: String(decoding: stdout, as: UTF8.self) + (outTruncated ? "\n[output truncated]" : ""),
                         stderr: error)
    }
}

/// Preserve a UTF-8 scalar split across arbitrary pipe reads.
struct UTF8Chunks {
    private var pending = Data()
    mutating func decode(_ chunk: Data) -> String {
        pending.append(chunk)
        let bytes = Array(pending)
        var cut = bytes.count
        if !bytes.isEmpty {
            var start = bytes.count - 1
            while start > 0 && bytes[start] & 0xc0 == 0x80 { start -= 1 }
            let lead = bytes[start]
            let length = lead & 0xf8 == 0xf0 ? 4 : lead & 0xf0 == 0xe0 ? 3 : lead & 0xe0 == 0xc0 ? 2 : 1
            if bytes.count - start < length { cut = start }
        }
        let text = String(decoding: pending.prefix(cut), as: UTF8.self)
        pending = Data(pending.dropFirst(cut))
        return text
    }
    mutating func finish() -> String {
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }
}
