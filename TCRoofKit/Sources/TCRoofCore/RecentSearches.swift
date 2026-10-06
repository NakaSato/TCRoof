import Foundation

/// The last few submitted queries of a search field (`ค้นหาล่าสุด`), newest first and without duplicates,
/// stored as one newline-separated string (for `@AppStorage`).
public enum RecentSearches {
    public static let limit = 4

    /// `list` with `query` moved to the front; blank queries leave it unchanged. Duplicates ignore case and surrounding spaces.
    public static func adding(_ query: String, to list: [String], limit: Int = limit) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(list.prefix(limit)) }
        let rest = list.filter { $0.compare(q, options: .caseInsensitive) != .orderedSame }
        return Array(([q] + rest).prefix(limit))
    }

    public static func decode(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    public static func encode(_ list: [String]) -> String {
        list.joined(separator: "\n")
    }
}
