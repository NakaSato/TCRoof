import Foundation

/// Caches decoded JSON values alongside the raw JSON string that produced them.
/// Marked `@Transient` on SwiftData `@Model` classes so repeated view-body reads avoid re-allocating
/// `JSONDecoder` and re-parsing UTF-8 strings on the main thread when the underlying JSON is unchanged.
final class ModelJSONCache {
    static let decoder = JSONDecoder()
    static let encoder = JSONEncoder()
    static let sortedKeysEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    private struct Entry {
        let raw: String?
        let value: Any?
    }

    private var entries: [String: Entry] = [:]

    func decode<T: Decodable>(_ type: T.Type, for key: String, raw: String?) -> T? {
        if let hit = entries[key], hit.raw == raw {
            return hit.value as? T
        }
        let decoded = raw.flatMap { try? Self.decoder.decode(type, from: Data($0.utf8)) }
        entries[key] = Entry(raw: raw, value: decoded)
        return decoded
    }

    func value<T>(for key: String, raw: String?, decode: (String?) -> T) -> T {
        if let hit = entries[key], hit.raw == raw, let v = hit.value as? T {
            return v
        }
        let decoded = decode(raw)
        entries[key] = Entry(raw: raw, value: decoded)
        return decoded
    }

    func set<T>(for key: String, raw: String?, value: T?) {
        entries[key] = Entry(raw: raw, value: value)
    }

    static func encode<T: Encodable>(_ value: T, sortedKeys: Bool = false) -> String? {
        let enc = sortedKeys ? sortedKeysEncoder : encoder
        return (try? enc.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
