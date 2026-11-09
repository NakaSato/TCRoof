import Foundation

/// A JSON value as Growatt sent it, for the calls whose answers carry dozens of fields (an inverter's or a storage
/// unit's readings) or fields the guide doesn't describe. Growatt writes numbers as numbers or as text, so `number`
/// reads both.
public enum JSONValue: Hashable, Sendable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public subscript(key: String) -> JSONValue? { object?[key] }

    public var object: [String: JSONValue]? { if case .object(let o) = self { o } else { nil } }
    public var array: [JSONValue]? { if case .array(let a) = self { a } else { nil } }

    /// A number, or text that reads as one ("0", " -1.0 "); nil for anything else.
    public var number: Double? {
        switch self {
        case .number(let d): d
        case .string(let s): Double(s.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    public var int: Int? { number.flatMap { $0.isFinite && $0.rounded() == $0 && abs($0) < 9e15 ? Int($0) : nil } }

    /// Text, or a number written as text (`124`, not `124.0`); nil for null, arrays and objects.
    public var text: String? {
        switch self {
        case .string(let s): s
        case .number(let d): d.isFinite && d.rounded() == d && abs(d) < 9e15 ? String(Int(d)) : String(d)
        case .bool(let b): b ? "true" : "false"
        default: nil
        }
    }

    /// A boolean, or 1 / 0, or "true" / "false" / "1" / "0".
    public var bool: Bool? {
        switch self {
        case .bool(let b): b
        case .number(let d): d != 0
        case .string(let s):
            switch s.lowercased() {
            case "true", "1": true
            case "false", "0": false
            default: nil
            }
        default: nil
        }
    }
}

extension GrowattAPI {
    /// One set of readings as Growatt sent it (an inverter's or a storage unit's), every field kept. `time` is the
    /// reading's time as written (`yyyy-MM-dd HH:mm:ss`, or `2015-12-08T11:00:00Z` in the guide's examples).
    public struct Readings: Hashable, Sendable {
        public var fields: [String: JSONValue]

        public init(fields: [String: JSONValue]) { self.fields = fields }

        public subscript(key: String) -> JSONValue? { fields[key] }
        public func number(_ key: String) -> Double? { fields[key]?.number }
        public func text(_ key: String) -> String? { fields[key]?.text }
        public var time: String { text("time") ?? "" }
    }
}
