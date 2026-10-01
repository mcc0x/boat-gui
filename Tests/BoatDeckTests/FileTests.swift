import Foundation

func testLocalFiles() async throws {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source"), target = directory.appendingPathComponent("target")
    try Data(repeating: 65, count: 1024).write(to: source)
    do {
        _ = try await LocalFiles.read(source, limit: 100)
        throw TestFailure("Oversized file accepted")
    } catch let error as BoatError { try expectEqual(error.code, "file_too_large") }
    try expectEqual(try await LocalFiles.read(source, limit: 1024).count, 1024)
    try await LocalFiles.saveDownload(source, to: target)
    try expectEqual(try Data(contentsOf: target), Data(repeating: 65, count: 1024))
    try Data("replacement".utf8).write(to: source)
    try await LocalFiles.saveDownload(source, to: target)
    try expectEqual(try String(contentsOf: target, encoding: .utf8), "replacement")
}
