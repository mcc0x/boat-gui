import Foundation
import Security
import AppKit
import Darwin

// MARK: - Keychain

enum Keychain {
    static let service = "dev.boat.BoatDeck"

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func remove(_ account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

// MARK: - Credential file

/// An empty file is a sign-out marker: legacy Keychain/env credentials must not restore the session.
enum Credentials {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BoatDeck/credentials")
    }
    static func load(from file: URL = url) throws -> String? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func save(_ key: String, to file: URL = url) throws {
        let fm = FileManager.default
        let directory = file.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(".credentials-" + UUID().uuidString)
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(fd); try? fm.removeItem(at: temporary) }
        try Data(key.utf8).withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EIO) }
                offset += count
            }
        }
        guard fsync(fd) == 0, rename(temporary.path, file.path) == 0 else { throw POSIXError(.EIO) }
    }
}

// MARK: - boat CLI bridge

struct CLIResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var json: JSON? { JSON.parse(Data(stdout.utf8)) }
}

enum BoatCLI {
    static var candidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.boat/bin/boat", "\(home)/.ascii/bin/boat", "\(home)/.local/bin/boat", "/opt/homebrew/bin/boat",
                "/usr/local/bin/boat", "\(home)/.homebrew/bin/boat", "\(home)/bin/boat", "\(home)/.cargo/bin/boat"]
    }

    /// Locate the boat binary: explicit override, well-known paths, then the login shell's PATH.
    static func locate(override: String) -> String? {
        if !override.isEmpty, FileManager.default.isExecutableFile(atPath: override) { return override }
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        let r = runSync("/bin/zsh", ["-lic", "command -v boat"], timeout: 8)
        let p = r.stdout.split(separator: "\n").map(String.init).last?.trimmingCharacters(in: .whitespaces) ?? ""
        return p.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    private static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.boat/bin:\(home)/.ascii/bin:\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        env["NO_COLOR"] = "1"
        return env
    }

    static func runSync(_ exe: String, _ args: [String], stdin: String? = nil, timeout: TimeInterval = 120) -> CLIResult {
        ProcessRunner.run(exe, args, environment: environment, stdin: stdin, timeout: timeout)
    }

    static func run(_ binary: String, _ args: [String], stdin: String? = nil, timeout: TimeInterval = 300) async -> CLIResult {
        let cancellation = ProcessCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    continuation.resume(returning: ProcessRunner.run(binary, args + ["--no-update"],
                        environment: environment, stdin: stdin, timeout: timeout, cancellation: cancellation))
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    /// Streams recent output with bounded buffering. Cancelling the consumer stops the child.
    static func stream(_ binary: String, _ args: [String]) -> (AsyncStream<String>, () -> Void) {
        let cancellation = ProcessCancellation()
        let stream = AsyncStream<String>(bufferingPolicy: .bufferingNewest(128)) { continuation in
            continuation.onTermination = { _ in cancellation.cancel() }
            DispatchQueue.global().async {
                let result = ProcessRunner.run(binary, args, environment: environment,
                    timeout: 60 * 60 * 24, cancellation: cancellation,
                    onOutput: { continuation.yield($0) })
                continuation.yield("\n[exit \(result.exitCode)]\n")
                continuation.finish()
            }
        }
        return (stream, { cancellation.cancel() })
    }

    /// Opens Terminal.app running a boat command (for interactive things like ssh / login).
    static func openInTerminal(_ binary: String, _ args: [String]) {
        let cmd = ([binary] + args).map(shq).joined(separator: " ")
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if err != nil {
            // Fallback: .command file
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("boatdeck-\(UUID().uuidString).command")
            try? "#!/bin/zsh\n\(cmd)\n".write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        }
    }
}

func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
