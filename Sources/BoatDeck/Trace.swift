import Foundation
import Darwin

/// Diagnostics deliberately accept no headers, response bodies or full URLs.
/// Dynamic path components are removed before formatting the log entry.
enum Trace {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "debugTrace") }
    static let maxBytes = 1_048_576
    private static let lock = NSLock()
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BoatDeck")
    }

    static func route(_ path: String) -> String {
        let parts = (path.split(separator: "?", maxSplits: 1).first ?? "").split(separator: "/").map(String.init)
        let roots: Set<String> = ["me", "limits", "orgs", "sandboxes", "environments", "named-snapshots", "snapshots", "webhooks", "api-keys", "provider-models", "repos", "account"]
        let children: Set<String> = ["stop", "resume", "fork", "usage", "prompt", "conversations", "steer", "interrupt", "events", "commands", "files", "artifacts", "desktop", "sshkey", "host", "snapshots", "tree", "vars", "secret-files", "repos", "upgrade", "rotate"]
        guard let root = parts.first, roots.contains(root) else { return "/:route" }
        return "/" + parts.enumerated().map { index, value in
            if index == 0 { return value }
            if index == 1, root == "account", value == "data-retention" { return value }
            if index == 1, root == "orgs", value == "active" { return value }
            if index == 1, root == "api-keys", value == "scoped" { return value }
            if index == 2, children.contains(value) { return value }
            return ":id"
        }.joined(separator: "/")
    }

    static func entry(_ method: String, _ path: String, _ status: Int, bytes: Int?, duration: TimeInterval) -> String {
        let verb = ["GET", "POST", "PUT", "PATCH", "DELETE"].contains(method) ? method : "OTHER"
        return "\(Date()) \(verb) \(route(path)) status=\(status) bytes=\(bytes.map(String.init) ?? "stream") ms=\(Int(max(0, duration) * 1000))\n"
    }

    static func log(_ method: String, _ path: String, _ status: Int, bytes: Int?, duration: TimeInterval) {
        guard enabled else { return }
        // Best effort: inability to log must not break the request or expose its payload elsewhere.
        try? append(entry(method, path, status, bytes: bytes, duration: duration), directory: dir)
    }

    static func append(_ line: String, directory: URL) throws {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let file = directory.appendingPathComponent("api-metadata.log")
        let fd = Darwin.open(file.path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, fchmod(fd, 0o600) == 0 else { throw POSIXError(.EIO) }
        let data = Data(line.utf8)
        guard data.count <= maxBytes else { return }
        if info.st_size + Int64(data.count) > maxBytes {
            guard ftruncate(fd, 0) == 0 else { throw POSIXError(.EIO) }
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw POSIXError(.EIO) }
                offset += written
            }
        }
    }
}
