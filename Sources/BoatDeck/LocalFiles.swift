import Foundation

/// File operations run outside the UI actor; bound reads before allocating file contents.
enum LocalFiles {
    static let previewLimit = 5_000_000
    static let uploadLimit = 16_000_000

    static func read(_ file: URL, limit: Int) async throws -> Data {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw BoatError(status: 0, code: "not_file", message: "Choose a regular file.")
        }
        guard (values.fileSize ?? 0) <= limit else { throw tooLarge(limit) }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw tooLarge(limit) }
        try Task.checkCancellation()
        return data
    }

    private static func tooLarge(_ limit: Int) -> BoatError {
        BoatError(status: 0, code: "file_too_large", message: "This operation supports files up to \(limit / 1_000_000) MB. Download large files or transfer them with the CLI.")
    }

    static func saveDownload(_ source: URL, to destination: URL) async throws {
        let fm = FileManager.default
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".boatdeck-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staged) }
        try fm.copyItem(at: source, to: staged)
        try Task.checkCancellation()
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: destination)
        }
    }
}
