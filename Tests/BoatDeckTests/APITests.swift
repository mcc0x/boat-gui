import Foundation

final class StubProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var reply: (Int, Data) = (200, Data("{}".utf8))

    static func reset(status: Int = 200, body: String = "{}") {
        lock.lock(); defer { lock.unlock() }
        requests = []; reply = (status, Data(body.utf8))
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let (status, data) = Self.reply
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct APITests {
    func client() -> BoatAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return BoatAPI(baseURL: "https://example.invalid/api/v1", apiKey: "test-key",
                       session: URLSession(configuration: config))
    }

    func testOpaquePathComponents() async throws {
        StubProtocol.reset()
        _ = try await client().deleteNamedSnapshot("team/a#b?c%25")
        let url = try unwrap(StubProtocol.requests.first?.url)
        try expectEqual(url.absoluteString, "https://example.invalid/api/v1/named-snapshots/team%2Fa%23b%3Fc%2525")
        try expectNil(url.query)
        try expectNil(url.fragment)
    }

    func testFileWriteFailureDoesNotExecuteFallbackCommand() async throws {
        StubProtocol.reset(status: 503, body: "{\"message\":\"temporary failure\"}")
        do {
            try await client().writeFile("test", path: "/tmp/file", data: Data("hello".utf8))
            throw TestFailure("Expected failure")
        } catch is BoatError {}
        try expectEqual(StubProtocol.requests.count, 1)
        try expectEqual(StubProtocol.requests.first?.httpMethod, "PUT")
    }

    func testSecretFileUsesPlainUTF8() async throws {
        StubProtocol.reset()
        _ = try await client().setSecretFile("env", path: ".env", contents: Data("TOKEN=example\n".utf8))
        let request = try client().makeRequest("PUT", "/environments/env/secret-files",
                                               body: ["path": ".env", "contents": "TOKEN=example\n"])
        // URLProtocol may expose a body stream instead of httpBody; inspect it without logging secrets.
        let captured = try unwrap(StubProtocol.requests.first)
        let actual = try bodyData(captured)
        try expectEqual(JSON.parse(actual), JSON.parse(try unwrap(request.httpBody)))
    }

    func testRejectsBinarySecretFilesBeforeSending() async throws {
        StubProtocol.reset()
        do {
            _ = try await client().setSecretFile("env", path: ".env", contents: Data([0xff, 0xfe]))
            throw TestFailure("Expected invalid UTF-8 error")
        } catch is BoatError {}
        try expect(StubProtocol.requests.isEmpty)
    }

    func testCredentialsOnlySentToHTTPSOrLoopback() throws {
        for base in ["http://example.com/api/v1", "https://user:password@example.com/api", "https://example.com/api?token=x"] {
            try expectThrows { _ = try BoatAPI(baseURL: base, apiKey: "test-key").makeRequest("GET", "/me") }
        }
        _ = try BoatAPI(baseURL: "http://127.0.0.1:8000/api/v1", apiKey: "test-key").makeRequest("GET", "/me")
    }

    private func bodyData(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try unwrap(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
