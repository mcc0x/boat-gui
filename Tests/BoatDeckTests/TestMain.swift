import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}
func expect(_ condition: Bool, _ message: String = "Expectation failed", file: StaticString = #file, line: UInt = #line) throws {
    if !condition { throw TestFailure("\(file):\(line): \(message)") }
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) throws {
    try expect(actual == expected, "Values differ", file: file, line: line)
}
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws {
    try expect(value == nil, "Expected nil", file: file, line: line)
}
func unwrap<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let value else { throw TestFailure("\(file):\(line): Unexpected nil") }
    return value
}
func expectThrows(_ work: () throws -> Void) throws {
    do { try work() } catch { return }
    throw TestFailure("Expected an error")
}

@main struct TestMain {
    static func main() async throws {
        let api = APITests()
        try await api.testOpaquePathComponents()
        try await api.testFileWriteFailureDoesNotExecuteFallbackCommand()
        try await api.testSecretFileUsesPlainUTF8()
        try await api.testRejectsBinarySecretFilesBeforeSending()
        try api.testCredentialsOnlySentToHTTPSOrLoopback()
        try testMetadataLogging()
        try testCredentialPersistence()
        print("API, logging and credential regression checks passed (7).")
    }
}
