import Foundation

func testCredentialPersistence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("credentials")
    try expectNil(try Credentials.load(from: file))
    try Credentials.save("test-key", to: file)
    try expectEqual(try Credentials.load(from: file), "test-key")
    let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
    try expectEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    try Credentials.save("", to: file)
    // An explicit empty credential prevents Keychain/environment fallback after restarting.
    try expectEqual(try Credentials.load(from: file) ?? "would-restore-old-key", "")
    try Credentials.save("replacement", to: file)
    try expectEqual(try Credentials.load(from: file), "replacement")
    // Failed replacement leaves the existing credential intact and reports an error.
    let invalid = file.appendingPathComponent("child")
    try expectThrows { try Credentials.save("new", to: invalid) }
    try expectEqual(try Credentials.load(from: file), "replacement")
}
