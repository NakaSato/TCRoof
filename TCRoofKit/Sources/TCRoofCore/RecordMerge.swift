import Foundation

/// A three-way merge of a synced record that changed on this device and on the server since they last agreed
/// (`base`), field by field over the record's top-level coding keys. A field only one side changed takes that side's
/// value; a field both sides changed to different values keeps `local`'s and is named in `conflicts`. Values compare
/// as JSON, so a field holding JSON text or a list is one value: two edits inside the same text are a conflict.
public enum RecordMerge {
    public struct Result<Record> {
        public let merged: Record
        /// The fields both sides changed to different values, sorted; `local`'s value was kept.
        public let conflicts: [String]
    }

    /// nil when a record doesn't encode as a JSON object, or the merged fields don't decode back as a record.
    public static func merge<Record: Codable>(base: Record, local: Record, remote: Record) -> Result<Record>? {
        guard let b = fields(base), let l = fields(local), let r = fields(remote) else { return nil }
        var merged = l
        var conflicts: [String] = []
        for key in Set(b.keys).union(l.keys).union(r.keys).sorted() {
            let before = b[key]?.json
            guard r[key]?.json != before else { continue }       // the server didn't change it: ours stands
            if l[key]?.json == before {
                merged[key] = r[key]                             // only the server changed it (nil: it took it out)
            } else if l[key]?.json != r[key]?.json {
                conflicts.append(key)                            // both changed it, differently: ours stands
            }
        }
        let object = merged.mapValues(\.value)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
        return Result(merged: record, conflicts: conflicts)
    }

    /// A field's decoded JSON value, and the same value written out canonically for comparing.
    private struct Field {
        let value: Any
        let json: Data
    }

    private static func fields<Record: Encodable>(_ record: Record) -> [String: Field]? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(record),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var out: [String: Field] = [:]
        for (key, value) in object {
            // wrapped in an array: a bare string or number is a JSON fragment, which not every Foundation writes
            guard let json = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys]) else { return nil }
            out[key] = Field(value: value, json: json)
        }
        return out
    }
}
