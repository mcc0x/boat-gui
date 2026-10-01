import Foundation
import Security
import AppKit

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

    static func set(_ account: String, _ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Credential file

/// API key stored at ~/Library/Application Support/BoatDeck/credentials (mode 0600), like most CLIs do.
/// Unlike an ad-hoc-signed app's Keychain item, this never triggers an access prompt after rebuilds.
enum Credentials {
    static var url: URL {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BoatDeck")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return d.appendingPathComponent("credentials")
    }
    static func load() -> String? {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    static func save(_ key: String) {
        if key.isEmpty { try? FileManager.default.removeItem(at: url); return }
        try? key.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
        return ["\(home)/.boat/bin/boat", "\(home)/.local/bin/boat", "/opt/homebrew/bin/boat",
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

    static func runSync(_ exe: String, _ args: [String], stdin: String? = nil, timeout: TimeInterval = 120) -> CLIResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.boat/bin:\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        env["NO_COLOR"] = "1"
        p.environment = env
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = inp
        do { try p.run() } catch { return CLIResult(exitCode: -1, stdout: "", stderr: error.localizedDescription) }
        if let stdin { inp.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? inp.fileHandleForWriting.close()
        var outData = Data(), errData = Data()
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        let deadline = DispatchTime.now() + timeout
        if g.wait(timeout: deadline) == .timedOut { p.terminate() ; g.wait() }
        p.waitUntilExit()
        return CLIResult(exitCode: p.terminationStatus,
                         stdout: String(decoding: outData, as: UTF8.self),
                         stderr: String(decoding: errData, as: UTF8.self))
    }

    static func run(_ binary: String, _ args: [String], stdin: String? = nil, timeout: TimeInterval = 300) async -> CLIResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                cont.resume(returning: runSync(binary, args + ["--no-update"], stdin: stdin, timeout: timeout))
            }
        }
    }

    /// Streams merged stdout/stderr lines of a long-running command.
    static func stream(_ binary: String, _ args: [String]) -> (AsyncStream<String>, () -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        let stream = AsyncStream<String> { cont in
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; cont.finish(); return }
                cont.yield(String(decoding: d, as: UTF8.self))
            }
            p.terminationHandler = { proc in
                cont.yield("\n[exit \(proc.terminationStatus)]\n")
            }
            do { try p.run() } catch { cont.yield("Failed: \(error.localizedDescription)\n"); cont.finish() }
        }
        return (stream, { if p.isRunning { p.terminate() } })
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
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        }
    }
}

func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
