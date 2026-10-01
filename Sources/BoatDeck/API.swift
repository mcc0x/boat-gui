import Foundation

struct BoatError: LocalizedError {
    let status: Int
    let code: String?
    let message: String
    var json: JSON? = nil
    /// e.g. a link to the dashboard page that fixes the problem.
    var setupURL: URL? {
        (json?["error"]?["details"]?["setupUrl"]?.string ?? json?["details"]?["setupUrl"]?.string).flatMap(URL.init(string:))
    }
    var errorDescription: String? {
        var s = message
        if let code { s = "\(code): \(s)" }
        if status > 0 { s = "[\(status)] \(s)" }
        return s
    }
}

/// Thin client over https://boat.dev/api/v1
final class BoatAPI: @unchecked Sendable {
    let baseURL: String
    let apiKey: String
    let org: String?
    private let session: URLSession

    init(baseURL: String, apiKey: String, org: String? = nil, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.org = org
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 60 * 60 * 6
        self.session = session ?? URLSession(configuration: cfg)
    }

    func cancel() { session.invalidateAndCancel() }

    /// A single opaque path component; delimiters must never become routing syntax.
    static func segment(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        if value == "." || value == ".." { return value.replacingOccurrences(of: ".", with: "%2E") }
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    func makeRequest(_ method: String, _ path: String, query: [String: String?] = [:],
                     body: JSON? = nil, headers: [String: String] = [:]) throws -> URLRequest {
        try Task.checkCancellation()
        guard !apiKey.isEmpty else {
            throw BoatError(status: 0, code: "no_api_key", message: "Add your Boat API key in Settings (⌘,).")
        }
        guard let base = URLComponents(string: baseURL), let host = base.host,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)) else {
            throw BoatError(status: 0, code: "bad_url", message: "Use an HTTPS API URL (HTTP is allowed only on localhost).")
        }
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard var comps = URLComponents(string: trimmed + path) else {
            throw BoatError(status: 0, code: nil, message: "Bad URL: \(path)")
        }
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        if !items.isEmpty { comps.queryItems = (comps.queryItems ?? []) + items }
        guard let url = comps.url else { throw BoatError(status: 0, code: nil, message: "Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("BoatDeck/2.0 (macOS)", forHTTPHeaderField: "User-Agent")
        if let org, !org.isEmpty { req.setValue(org, forHTTPHeaderField: "X-Boat-Org") }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        return req
    }

    @discardableResult
    func call(_ method: String, _ path: String, query: [String: String?] = [:],
              body: JSON? = nil, headers: [String: String] = [:]) async throws -> JSON {
        guard !apiKey.isEmpty else {
            throw BoatError(status: 0, code: "no_api_key", message: "Add your Boat API key in Settings (⌘,).")
        }
        let req = try makeRequest(method, path, query: query, body: body, headers: headers)
        let started = Date()
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = JSON.parse(data)
        Trace.log(method, path, status, bytes: data.count, duration: Date().timeIntervalSince(started))
        if status >= 400 || json?["ok"]?.bool == false {
            throw BoatError(status: status,
                            code: json?["code"]?.string,
                            message: json?["message"]?.string ?? json?["error"]?["message"]?.string
                                ?? String(decoding: data.prefix(500), as: UTF8.self),
                            json: json)
        }
        return json ?? .object(["raw": .string(String(decoding: data, as: UTF8.self))])
    }

    /// Raw bytes (used for file downloads).
    func raw(_ method: String, _ path: String, query: [String: String?] = [:]) async throws -> (Data, HTTPURLResponse) {
        let req = try makeRequest(method, path, query: query)
        let started = Date()
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw BoatError(status: 0, code: nil, message: "No response") }
        Trace.log(method, path, http.statusCode, bytes: data.count, duration: Date().timeIntervalSince(started))
        if http.statusCode >= 400 {
            let j = JSON.parse(data)
            throw BoatError(status: http.statusCode, code: j?["code"]?.string,
                            message: j?["message"]?.string ?? String(decoding: data.prefix(300), as: UTF8.self))
        }
        return (data, http)
    }

    /// Streams NDJSON lines (events, streamed commands).
    func stream(_ method: String, _ path: String, query: [String: String?] = [:], body: JSON? = nil) -> AsyncThrowingStream<JSON, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = try makeRequest(method, path, query: query, body: body)
                    req.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
                    req.timeoutInterval = 60 * 60 * 6
                    let started = Date()
                    let (bytes, resp) = try await session.bytes(for: req)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    Trace.log(method, path, status, bytes: nil, duration: Date().timeIntervalSince(started))
                    if status >= 400 {
                        var buf = ""
                        for try await line in bytes.lines { buf += line; if buf.count > 800 { break } }
                        let j = JSON.parse(Data(buf.utf8))
                        throw BoatError(status: status, code: j?["code"]?.string, message: j?["message"]?.string ?? buf)
                    }
                    for try await line in bytes.lines {
                        let t = line.trimmingCharacters(in: .whitespaces)
                        if t.isEmpty { continue }
                        let payload = t.hasPrefix("data:") ? String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces) : t
                        if let j = JSON.parse(Data(payload.utf8)) { continuation.yield(j) }
                        else { continuation.yield(.object(["type": "raw", "data": .string(payload)])) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Convenience endpoints

    func sb(_ id: String) -> String { "/sandboxes/\(Self.segment(id))" }

    func me() async throws -> JSON { try await call("GET", "/me") }
    func limits() async throws -> JSON { try await call("GET", "/limits") }
    func orgs() async throws -> JSON { try await call("GET", "/orgs") }

    func sandboxes() async throws -> [Record] {
        try await call("GET", "/sandboxes").list("sandboxes", "items", "data").map(Record.init)
    }
    func sandbox(_ id: String) async throws -> JSON {
        let j = try await call("GET", sb(id))
        return j["sandbox"] ?? j
    }
    func createSandbox(_ body: JSON) async throws -> JSON {
        try await call("POST", "/sandboxes", body: body, headers: ["Idempotency-Key": UUID().uuidString])
    }
    func updateSandbox(_ id: String, _ body: JSON) async throws -> JSON { try await call("PATCH", sb(id), body: body) }
    func stop(_ id: String, force: Bool = false) async throws -> JSON {
        try await call("POST", sb(id) + "/stop", body: JSON.object(force ? ["force": JSON.bool(true)] : [:]))
    }
    func resume(_ id: String, _ body: JSON = [:]) async throws -> JSON { try await call("POST", sb(id) + "/resume", body: body) }
    func fork(_ id: String, _ body: JSON = [:]) async throws -> JSON {
        try await call("POST", sb(id) + "/fork", body: body, headers: ["Idempotency-Key": UUID().uuidString])
    }
    func delete(_ id: String) async throws -> JSON {
        try await call("DELETE", sb(id), headers: ["X-Ascii-Confirm-Delete": id])
    }
    func usage(_ id: String) async throws -> JSON { try await call("GET", sb(id) + "/usage") }

    func prompt(_ id: String, _ body: JSON) async throws -> JSON { try await call("POST", sb(id) + "/prompt", body: body) }
    func conversations(_ id: String) async throws -> [Record] {
        try await call("GET", sb(id) + "/conversations").list("conversations").map(Record.init)
    }
    func steer(_ id: String, message: String, convo: String?) async throws -> JSON {
        var b: [String: JSON] = ["message": .string(message)]
        if let convo { b["conversationId"] = .string(convo); b["conversation"] = .string(convo) }
        return try await call("POST", sb(id) + "/steer", body: .object(b))
    }
    func interrupt(_ id: String, convo: String?) async throws -> JSON {
        var b: [String: JSON] = [:]
        if let convo { b["conversationId"] = .string(convo); b["conversation"] = .string(convo) }
        return try await call("POST", sb(id) + "/interrupt", body: .object(b))
    }
    func events(_ id: String, convo: String?, follow: Bool) -> AsyncThrowingStream<JSON, Error> {
        stream("GET", sb(id) + "/events", query: ["conversation": convo, "follow": follow ? "true" : nil])
    }
    func providerModels() async throws -> JSON { try await call("GET", "/provider-models") }

    func exec(_ id: String, command: String, cwd: String?, timeout: Int = 600) async throws -> JSON {
        var b: [String: JSON] = ["command": .string(command), "timeoutSeconds": .number(Double(timeout))]
        if let cwd, !cwd.isEmpty { b["cwd"] = .string(cwd) }
        return try await call("POST", sb(id) + "/commands", body: .object(b))
    }
    func execStream(_ id: String, command: String, cwd: String?, timeout: Int) -> AsyncThrowingStream<JSON, Error> {
        var b: [String: JSON] = ["command": .string(command), "timeoutSeconds": .number(Double(timeout)), "stream": true]
        if let cwd, !cwd.isEmpty { b["cwd"] = .string(cwd) }
        return stream("POST", sb(id) + "/commands", body: .object(b))
    }
    func execDetached(_ id: String, command: String, cwd: String?) async throws -> JSON {
        var b: [String: JSON] = ["command": .string(command), "detached": true]
        if let cwd, !cwd.isEmpty { b["cwd"] = .string(cwd) }
        return try await call("POST", sb(id) + "/commands", body: .object(b))
    }
    func commandStatus(_ id: String, pid: String) async throws -> JSON { try await call("GET", sb(id) + "/commands/\(Self.segment(pid))") }

    func readFile(_ id: String, path: String) async throws -> (Data, HTTPURLResponse) {
        try await raw("GET", sb(id) + "/files", query: ["path": path])
    }
    func writeFile(_ id: String, path: String, data: Data) async throws {
        try await call("PUT", sb(id) + "/files",
                       body: ["path": .string(path), "content": .string(data.base64EncodedString()), "encoding": "base64"])
    }
    func artifacts(_ id: String) async throws -> (Data, HTTPURLResponse) { try await raw("GET", sb(id) + "/artifacts") }
    func desktop(_ id: String) async throws -> JSON { try await call("POST", sb(id) + "/desktop") }
    func addSSHKey(_ id: String, publicKey: String) async throws -> JSON {
        try await call("POST", sb(id) + "/sshkey", body: ["publicKey": .string(publicKey), "key": .string(publicKey)])
    }
    func host(_ id: String, port: Int, title: String?, isPublic: Bool) async throws -> JSON {
        var b: [String: JSON] = ["port": .number(Double(port)), "public": .bool(isPublic)]
        if let title, !title.isEmpty { b["title"] = .string(title) }
        return try await call("POST", sb(id) + "/host", body: .object(b))
    }

    // Snapshots
    func sandboxSnapshots(_ id: String) async throws -> [Record] {
        try await call("GET", sb(id) + "/snapshots").list("snapshots").map(Record.init)
    }
    func allSnapshots() async throws -> [Record] { try await call("GET", "/snapshots").list("snapshots").map(Record.init) }
    func namedSnapshots() async throws -> [Record] {
        try await call("GET", "/named-snapshots").list("namedSnapshots", "snapshots", "named").map(Record.init)
    }
    func saveNamedSnapshot(sandboxId: String, name: String) async throws -> JSON {
        try await call("POST", "/named-snapshots", body: ["sandboxId": .string(sandboxId), "name": .string(name)])
    }
    func deleteNamedSnapshot(_ name: String) async throws -> JSON { try await call("DELETE", "/named-snapshots/\(Self.segment(name))") }
    func deleteSnapshot(_ id: String) async throws -> JSON { try await call("DELETE", "/snapshots/\(Self.segment(id))") }
    func snapshotTree(_ id: String) async throws -> JSON { try await call("GET", "/snapshots/\(Self.segment(id))/tree") }

    // Environments
    func environments() async throws -> [Record] { try await call("GET", "/environments").list("environments").map(Record.init) }
    func createEnvironment(name: String) async throws -> JSON { try await call("POST", "/environments", body: ["name": .string(name)]) }
    func updateEnvironment(_ id: String, _ body: JSON) async throws -> JSON { try await call("PUT", "/environments/\(Self.segment(id))", body: body) }
    func deleteEnvironment(_ id: String) async throws -> JSON { try await call("DELETE", "/environments/\(Self.segment(id))") }
    func setVar(_ env: String, key: String, value: String) async throws -> JSON {
        try await call("PUT", "/environments/\(Self.segment(env))/vars/\(Self.segment(key))", body: ["value": .string(value)])
    }
    func removeVar(_ env: String, key: String) async throws -> JSON { try await call("DELETE", "/environments/\(Self.segment(env))/vars/\(Self.segment(key))") }
    func setSecretFile(_ env: String, path: String, contents: Data) async throws -> JSON {
        guard let text = String(data: contents, encoding: .utf8) else {
            throw BoatError(status: 0, code: "invalid_text", message: "Environment secret files must be UTF-8 text.")
        }
        return try await call("PUT", "/environments/\(Self.segment(env))/secret-files",
                              body: ["path": .string(path), "contents": .string(text)])
    }
    func removeSecretFile(_ env: String, path: String) async throws -> JSON {
        try await call("DELETE", "/environments/\(Self.segment(env))/secret-files", query: ["path": path], body: ["path": .string(path)])
    }
    func addRepo(_ env: String, repositoryId: String, branch: String?) async throws -> JSON {
        var b: [String: JSON] = ["repositoryId": .string(repositoryId), "repo": .string(repositoryId)]
        if let n = Double(repositoryId) { b["repositoryId"] = .number(n) }
        if let branch, !branch.isEmpty { b["baseBranch"] = .string(branch) }
        return try await call("POST", "/environments/\(Self.segment(env))/repos", body: .object(b))
    }
    func removeRepo(_ env: String, repoId: String) async throws -> JSON { try await call("DELETE", "/environments/\(Self.segment(env))/repos/\(Self.segment(repoId))") }
    func upgradeEnvironment(_ env: String) async throws -> JSON { try await call("POST", "/environments/\(Self.segment(env))/upgrade") }
    func repos() async throws -> [Record] { try await call("GET", "/repos").list("repos", "repositories").map(Record.init) }

    // Keys & webhooks
    func apiKeys() async throws -> [Record] { try await call("GET", "/api-keys").list("apiKeys", "keys").map(Record.init) }
    func apiKeyUsage(_ id: String) async throws -> JSON { try await call("GET", "/api-keys/\(Self.segment(id))/usage") }
    func webhooks() async throws -> [Record] { try await call("GET", "/webhooks").list("webhooks").map(Record.init) }
    func createWebhook(url: String, events: [String]) async throws -> JSON {
        try await call("POST", "/webhooks", body: ["url": .string(url), "events": .array(events.map { .string($0) })])
    }
    func updateWebhook(_ id: String, _ body: JSON) async throws -> JSON { try await call("PATCH", "/webhooks/\(Self.segment(id))", body: body) }
    func rotateWebhook(_ id: String) async throws -> JSON { try await call("POST", "/webhooks/\(Self.segment(id))/rotate") }
    func deleteWebhook(_ id: String) async throws -> JSON { try await call("DELETE", "/webhooks/\(Self.segment(id))") }

    func dataRetention() async throws -> JSON { try await call("GET", "/account/data-retention") }
    func setDataRetention(_ zdr: Bool) async throws -> JSON {
        try await call("PATCH", "/account/data-retention", body: ["enabled": .bool(zdr), "zeroDataRetention": .bool(zdr)])
    }
}

/// Shell single-quote.
func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
