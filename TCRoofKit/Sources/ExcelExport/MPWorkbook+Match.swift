import Foundation

/// Which station a plan file is for, when many are imported at once: the station named in its `PROJECT` line
/// (`…ภายใน สถานีผลิตน้ำประปาบางไทร การประปาส่วนภูมิภาคสาขา… ขนาดกำลังผลิต 414.96 kWp`), its kWp, and an MP number
/// in the file name, scored against the app's stations. The team checks the picks before anything is imported.
extension MPWorkbook {
    /// What a file says about its station.
    public struct FileStation: Sendable, Equatable {
        public var name: String?
        public var kWp: Double?
        public var mpNumber: Int?
    }

    /// A station of the app to match against.
    public struct Candidate: Sendable {
        public var id: String
        public var name: String
        public var mpNumber: Int?
        public var kWp: Double?
        public init(id: String, name: String, mpNumber: Int?, kWp: Double?) {
            self.id = id; self.name = name; self.mpNumber = mpNumber; self.kWp = kWp
        }
    }

    public struct Match: Sendable, Equatable {
        /// The station taken without asking: a clear best; nil when none is close or two are as close.
        public var pick: String?
        /// Candidates that fit at all, best first.
        public var ranked: [String]
    }

    public static func station(project: String?, fileName: String) -> FileStation {
        let base = (fileName as NSString).deletingPathExtension
        let text = project ?? base
        var name: String?
        if let s = text.range(of: "สถานี") {
            var tail = String(text[s.lowerBound...])
            for stop in ["การประปา", "กปภ", "ขนาด", "สาขา"] {
                if let r = tail.range(of: stop), r.lowerBound > tail.startIndex { tail = String(tail[..<r.lowerBound]) }
            }
            name = tail.trimmingCharacters(in: .whitespaces)
        } else if project == nil {
            name = base
        }
        let kWp = text.range(of: #"[\d,]+(\.\d+)?\s*kWp"#, options: [.regularExpression, .caseInsensitive]).flatMap {
            Double(text[$0].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "kWp", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces))
        }
        // "MP 189 …", or the list number the files start with ("37. Master Plan Weekly …")
        let mp = base.range(of: #"MP\s*\d+"#, options: [.regularExpression, .caseInsensitive])
            .flatMap { Int(base[$0].filter(\.isNumber)) }
            ?? base.range(of: #"^\s*\d+"#, options: .regularExpression).flatMap { Int(base[$0].trimmingCharacters(in: .whitespaces)) }
        return FileStation(name: name, kWp: kWp, mpNumber: mp)
    }

    /// A station name reduced to what tells it apart: `สถานีผลิตน้ำประปาบางไทร` and `สถานีผลิตน้ำ บางไทร กปภ.สาขา…`
    /// both give `บางไทร`.
    public static func stationKey(_ s: String) -> String {
        var t = s.lowercased()
        for stop in ["การประปา", "กปภ", "ขนาด", "สาขา", "kwp"] {
            if let r = t.range(of: stop), r.lowerBound > t.startIndex { t = String(t[..<r.lowerBound]) }
        }
        for word in ["โครงการ", "สถานี", "ผลิตน้ำ", "ประปา", "จ่ายน้ำ", "สูบน้ำ", "เพิ่มแรงดัน", "แรงดัน", "บ่อบาดาล"] {
            t = t.replacingOccurrences(of: word, with: "")
        }
        return String(t.unicodeScalars.filter { CharacterSet.letters.union(.decimalDigits).union(.nonBaseCharacters).contains($0) }.map(Character.init))
    }

    public static func match(_ f: FileStation, among stations: [Candidate]) -> Match {
        let key = f.name.map(stationKey) ?? ""
        var scored: [(id: String, score: Double)] = []
        for s in stations {
            var score = 0.0
            let other = stationKey(s.name)
            if !key.isEmpty, !other.isEmpty {
                if key == other { score = 100 }
                else if min(key.count, other.count) >= 3, key.contains(other) || other.contains(key) { score = 80 }
                else {
                    let r = Double(longestCommon(key, other)) / Double(min(key.count, other.count))
                    if r >= 0.7 { score = 60 * r }
                }
            }
            if let a = f.kWp, let b = s.kWp, b > 0, abs(a - b) <= max(0.5, b * 0.01) { score += 20 }
            if let a = f.mpNumber, a == s.mpNumber { score += 15 }
            if score >= 30 { scored.append((s.id, score)) }
        }
        scored.sort { $0.score > $1.score }
        let best = scored.first, second = scored.dropFirst().first
        let pick = best.flatMap { b in b.score >= 60 && (second.map { b.score - $0.score >= 15 } ?? true) ? b.id : nil }
        return Match(pick: pick, ranked: scored.map(\.id))
    }

    /// Characters in the longest run the two share.
    static func longestCommon(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var prev = [Int](repeating: 0, count: y.count + 1), best = 0
        for i in 1...x.count {
            var row = [Int](repeating: 0, count: y.count + 1)
            for j in 1...y.count where x[i - 1] == y[j - 1] {
                row[j] = prev[j - 1] + 1
                best = max(best, row[j])
            }
            prev = row
        }
        return best
    }
}
