import Foundation

/// Lenient JSON value so the app keeps working even if Boat adds or renames fields.
enum JSON: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSON].self) { self = .object(o) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    static func parse(_ data: Data) -> JSON? {
        try? JSONDecoder().decode(JSON.self, from: data)
    }

    subscript(key: String) -> JSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    /// First non-nil value among several candidate keys (handles naming drift).
    func first(_ keys: String...) -> JSON? {
        for k in keys { if let v = self[k], v != .null { return v } }
        return nil
    }

    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
    var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    var int: Int? { double.flatMap { Int(exactly: $0.rounded(.towardZero)) } }
    var bool: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s): return s == "true"
        case .number(let n): return n != 0
        default: return nil
        }
    }
    var array: [JSON]? { if case .array(let a) = self { return a }; return nil }
    var object: [String: JSON]? { if case .object(let o) = self { return o }; return nil }

    /// Finds the first array in an envelope, preferring the given keys.
    func list(_ keys: String...) -> [JSON] {
        for k in keys { if let a = self[k]?.array { return a } }
        if let a = self.array { return a }
        if let o = self.object {
            for (k, v) in o where !["ok", "type"].contains(k) { if let a = v.array { return a } }
        }
        return []
    }

    var pretty: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let d = try? enc.encode(self) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    var compact: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let d = try? enc.encode(self) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
                ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByFloatLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(dictionaryLiteral elements: (String, JSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { a, _ in a }))
    }
    init(arrayLiteral elements: JSON...) { self = .array(elements) }
}

/// Identifiable wrapper for a JSON record with a best-effort id.
struct Record: Identifiable, Hashable {
    let json: JSON
    var id: String {
        json.first("id", "name", "sandboxId", "snapshotId", "key", "path")?.string ?? json.compact
    }
    subscript(_ keys: String...) -> String? {
        for k in keys { if let s = json[k]?.string, !s.isEmpty { return s } }
        return nil
    }
}

extension Date {
    static func fromISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

func relative(_ iso: String?) -> String {
    guard let d = Date.fromISO(iso) else { return iso ?? "—" }
    if abs(d.timeIntervalSinceNow) < 45 { return "just now" }
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
}

func byteString(_ n: Double?) -> String {
    guard let n, let count = Int64(exactly: n.rounded(.towardZero)) else { return "—" }
    return ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}
