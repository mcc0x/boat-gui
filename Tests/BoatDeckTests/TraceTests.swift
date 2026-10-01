import Foundation

func testMetadataLogging() throws {
    let line = Trace.entry("PUT", "/environments/private-name/vars/API_SECRET?token=synthetic", 200, bytes: 123, duration: 0.25)
    try expect(line.contains("/environments/:id/vars/:id"))
    for secret in ["private-name", "API_SECRET", "synthetic", "token="] { try expect(!line.contains(secret)) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Trace.append(line, directory: directory)
    let file = directory.appendingPathComponent("api-metadata.log")
    let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
    try expectEqual(permissions?.intValue, 0o600)
    try Data(repeating: 65, count: Trace.maxBytes).write(to: file)
    try Trace.append(line, directory: directory)
    try expectEqual(try String(contentsOf: file, encoding: .utf8), line)
    // Existing symlinks must never cause a write to another file.
    try FileManager.default.removeItem(at: file)
    let target = directory.appendingPathComponent("target")
    try "untouched".write(to: target, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
    try expectThrows { try Trace.append(line, directory: directory) }
    try expectEqual(try String(contentsOf: target, encoding: .utf8), "untouched")
}
