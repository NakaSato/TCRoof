import Foundation

/// The PWA project's tracking workbook (`สรุปสถานะการยื่นขออนุญาตต่าง ๆ โครงการประปา เฟส 3-4`, sheet
/// `สรุปสถานะโครงการประปา ระยะที่ 3`, docs/specs/master-schedule-swift.md §4): one row per station with its branch, installed
/// kWp, inverter kW, coordinates and address. `read` takes the rows; `rows` matches them to the app's PWA stations and
/// says what each would fill. The app creates a job for a row with no station and fills only empty fields of a matched
/// one: a value that differs from the sheet is kept and shown.
///
/// The columns are found from the header texts (`สถานที่ติดตั้งจริง`, `กปภ.สาขา`, `LAT` …), not fixed cells, and the
/// sheet is the first with them, so the file's other sheets and a moved column read the same.
public enum StationList {
    public enum Failure: Error, Equatable {
        case notWorkbook
        case noStationSheet

        public var message: String {
            switch self {
            case .notWorkbook: "ไฟล์นี้ไม่ใช่ Excel (.xlsx)"
            case .noStationSheet: "ไม่พบชีตรายชื่อสถานี (หัวตาราง สถานที่ติดตั้ง / กปภ.สาขา)"
            }
        }
    }

    /// One station row of the sheet.
    public struct Station: Sendable, Equatable {
        /// The sheet row, 1-based.
        public var row: Int
        public var phase: Int?
        /// `ลำดับ`, which starts again in each phase.
        public var order: Int?
        public var name: String
        public var branch: String
        public var kWp: Double?
        public var inverterKW: Double?
        public var latitude: Double?
        public var longitude: Double?
        public var address: String
        /// The province the address names (`จ.ลพบุรี` → `ลพบุรี`); empty when it names none.
        public var province: String

        public init(row: Int, phase: Int? = nil, order: Int? = nil, name: String, branch: String = "", kWp: Double? = nil,
                    inverterKW: Double? = nil, latitude: Double? = nil, longitude: Double? = nil, address: String = "",
                    province: String? = nil) {
            self.row = row; self.phase = phase; self.order = order; self.name = name; self.branch = branch
            self.kWp = kWp; self.inverterKW = inverterKW; self.latitude = latitude; self.longitude = longitude
            self.address = address; self.province = province ?? StationList.province(in: address)
        }
    }

    public static func read(_ data: Data) throws -> [Station] {
        guard let zip = try? ZipArchive(data), let wb = zip.string("xl/workbook.xml") else { throw Failure.notWorkbook }
        let shared = MPWorkbook.Sheet.sharedStrings(zip.string("xl/sharedStrings.xml") ?? "")
        let rels = zip.string("xl/_rels/workbook.xml.rels") ?? ""
        for (_, id) in MPWorkbook.Book.sheetIDs(wb) {
            guard let path = MPWorkbook.Book.target(id, rels), let xml = zip.string(path) else { continue }
            let sheet = MPWorkbook.Sheet(xml, shared: shared)
            if let columns = Columns(sheet) { return stations(sheet, columns) }
        }
        throw Failure.noStationSheet
    }

    /// The header row and the column of each field.
    struct Columns {
        var header: Int
        var name: Int
        var branch, phase, order, kWp, inverterKW, latitude, longitude, address: Int?

        init?(_ sheet: MPWorkbook.Sheet) {
            func squeezed(_ s: String) -> String { s.filter { !$0.isWhitespace } }
            guard let title = sheet.texts.first(where: {
                let t = squeezed($0.text)
                return t.contains("สถานที่ติดตั้ง") && !t.contains("ที่อยู่")
            }) else { return nil }
            header = title.row; name = title.col
            for cell in sheet.texts where cell.row == header {
                let t = squeezed(cell.text)
                if t.contains("ที่อยู่") { address = cell.col }
                else if t.contains("สาขา") { branch = cell.col }
                else if t.contains("กำลังการผลิตติดตั้ง") || t.lowercased().contains("kwp") { kWp = cell.col }
                else if t.contains("อินเวอร์เตอร์") || t.lowercased().contains("inverter") { inverterKW = cell.col }
                else if t.uppercased() == "LAT" || t.uppercased() == "LATITUDE" { latitude = cell.col }
                else if t.uppercased() == "LONG" || t.uppercased() == "LON" || t.uppercased() == "LONGITUDE" { longitude = cell.col }
                else if t == "เฟส" || t == "ระยะ" { phase = cell.col }
                else if t == "ลำดับ" || t == "ลำดับที่" { order = cell.col }
            }
            // a sheet that only mentions the place somewhere is not the list
            guard branch != nil || kWp != nil else { return nil }
        }
    }

    static func stations(_ sheet: MPWorkbook.Sheet, _ c: Columns) -> [Station] {
        func text(_ col: Int?, _ row: Int) -> String {
            guard let col else { return "" }
            if let t = sheet.text(col, row) { return t.trimmingCharacters(in: .whitespacesAndNewlines) }
            return sheet.number(col, row).map { IECExcel.number($0) } ?? ""
        }
        func number(_ col: Int?, _ row: Int) -> Double? {
            guard let col else { return nil }
            if let n = sheet.number(col, row) { return n }
            return sheet.text(col, row).flatMap { Double($0.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) }
        }
        func coordinate(_ col: Int?, _ row: Int, limit: Double) -> Double? {
            number(col, row).flatMap { $0 != 0 && abs($0) <= limit ? $0 : nil }
        }
        return sheet.texts(col: c.name).compactMap { cell -> Station? in
            let r = cell.row, name = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard r > c.header, !name.isEmpty else { return nil }
            return Station(row: r, phase: number(c.phase, r).map { Int($0) }, order: number(c.order, r).map { Int($0) },
                           name: name, branch: text(c.branch, r),
                           kWp: number(c.kWp, r).flatMap { $0 > 0 ? $0 : nil }, inverterKW: number(c.inverterKW, r).flatMap { $0 > 0 ? $0 : nil },
                           latitude: coordinate(c.latitude, r, limit: 90), longitude: coordinate(c.longitude, r, limit: 180),
                           address: text(c.address, r).replacingOccurrences(of: "\n", with: " "))
        }
    }

    /// `… อ.เมืองลพบุรี จ.ลพบุรี 15000` → `ลพบุรี`.
    public static func province(in address: String) -> String {
        guard let r = address.range(of: #"(จ\.|จังหวัด)\s*[^\s\d]+"#, options: .regularExpression) else { return "" }
        var t = String(address[r])
        for prefix in ["จังหวัด", "จ."] where t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)) }
        return t.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Matching

extension StationList {
    /// A PWA station already in the app.
    public struct Existing: Sendable {
        public var id: String
        public var name: String
        public var branch: String
        public var kWp: Double?
        public var inverterKW: Double?
        public var address: String
        public var province: String
        public var latitude: Double?
        public var longitude: Double?

        public init(id: String, name: String, branch: String = "", kWp: Double? = nil, inverterKW: Double? = nil, address: String = "",
                    province: String = "", latitude: Double? = nil, longitude: Double? = nil) {
            self.id = id; self.name = name; self.branch = branch; self.kWp = kWp; self.inverterKW = inverterKW
            self.address = address; self.province = province; self.latitude = latitude; self.longitude = longitude
        }
    }

    /// What a row gives a station.
    public enum Field: String, CaseIterable, Sendable {
        case branch, kWp, inverterKW, address, province, coordinates

        public var label: String {
            switch self {
            case .branch: "กปภ.สาขา"
            case .kWp: "kWp"
            case .inverterKW: "อินเวอร์เตอร์"
            case .address: "ที่อยู่"
            case .province: "จังหวัด"
            case .coordinates: "พิกัด"
            }
        }
    }

    /// One sheet row against the app's stations.
    public struct Row: Sendable, Identifiable {
        public var id: Int { station.row }
        public var station: Station
        /// The station taken without asking; nil for a new one, or when it isn't clear (`ranked` then has the choices).
        public var match: String?
        /// Stations that fit at all, best first.
        public var ranked: [String]
    }

    /// Each row's station: a clear best by name, branch and kWp, never one a better row has taken.
    public static func rows(_ stations: [Station], existing: [Existing]) -> [Row] {
        var scored: [(row: Int, ranked: [(id: String, score: Double)])] = stations.enumerated().map { i, s in
            let r = existing.compactMap { e -> (id: String, score: Double)? in
                let v = score(s, e)
                return v >= 30 ? (e.id, v) : nil
            }.sorted { $0.score > $1.score }
            return (i, r)
        }
        // the best claim on each station wins it
        var owner: [String: (row: Int, score: Double)] = [:]
        var picks: [Int: String] = [:]
        for (i, ranked) in scored {
            guard let best = ranked.first, best.score >= 60 else { continue }
            if let second = ranked.dropFirst().first, best.score - second.score < 15 { continue }
            if let o = owner[best.id], o.score >= best.score { continue }
            if let o = owner[best.id] { picks[o.row] = nil }
            owner[best.id] = (i, best.score)
            picks[i] = best.id
        }
        scored.sort { $0.row < $1.row }
        return scored.map { i, ranked in
            Row(station: stations[i], match: picks[i], ranked: ranked.map { $0.id })
        }
    }

    static func score(_ s: Station, _ e: Existing) -> Double {
        let key = MPWorkbook.stationKey(s.name), other = MPWorkbook.stationKey(e.name)
        var score = 0.0
        // a name that is all generic words (`สถานีจ่ายน้ำ กปภ.เขต 7` gives an empty key) matches only itself, spaces aside
        if key.isEmpty || other.isEmpty {
            func squeezed(_ t: String) -> String { t.lowercased().filter { !$0.isWhitespace } }
            if !squeezed(s.name).isEmpty, squeezed(s.name) == squeezed(e.name) { score = 100 }
        } else {
            if key == other { score = 100 }
            else if min(key.count, other.count) >= 3, key.contains(other) || other.contains(key) { score = 80 }
            else {
                let r = Double(MPWorkbook.longestCommon(key, other)) / Double(min(key.count, other.count))
                if r >= 0.7 { score = 60 * r }
            }
        }
        guard score > 0 else { return 0 }
        let a = branchKey(s.branch), b = branchKey(e.branch)
        if !a.isEmpty, !b.isEmpty { score += a == b ? 15 : -15 }
        if let x = s.kWp, let y = e.kWp, y > 0, abs(x - y) <= max(0.5, y * 0.01) { score += 20 }
        return score
    }

    /// `การประปาส่วนภูมิภาคสาขาชัยบาดาล` and `กปภ.สาขาชัยบาดาล` both give `ชัยบาดาล`.
    static func branchKey(_ s: String) -> String {
        var t = s
        for word in ["การประปาส่วนภูมิภาค", "กปภ.", "กปภ", "สาขา"] { t = t.replacingOccurrences(of: word, with: "") }
        return t.filter { !$0.isWhitespace }
    }

    /// The fields a row fills on a station, which has them empty.
    public static func fills(_ s: Station, _ e: Existing) -> [Field] {
        Field.allCases.filter { f in
            switch f {
            case .branch: e.branch.isEmpty && !s.branch.isEmpty
            case .kWp: (e.kWp ?? 0) <= 0 && s.kWp != nil
            case .inverterKW: (e.inverterKW ?? 0) <= 0 && s.inverterKW != nil
            case .address: e.address.trimmingCharacters(in: .whitespaces).isEmpty && !s.address.isEmpty
            case .province: e.province.isEmpty && !s.province.isEmpty
            case .coordinates: (e.latitude == nil || e.longitude == nil) && s.latitude != nil && s.longitude != nil
            }
        }
    }

    /// The fields where the station already has a value other than the sheet's; it keeps its own.
    public static func differs(_ s: Station, _ e: Existing) -> [Field] {
        func near(_ a: Double?, _ b: Double?, _ tolerance: Double) -> Bool {
            guard let a, let b else { return true }
            return abs(a - b) <= tolerance
        }
        func squeezed(_ t: String) -> String { t.filter { !$0.isWhitespace } }
        return Field.allCases.filter { f in
            switch f {
            case .branch: !e.branch.isEmpty && !s.branch.isEmpty && branchKey(e.branch) != branchKey(s.branch)
            case .kWp: (e.kWp ?? 0) > 0 && !near(e.kWp, s.kWp, 0.01)
            case .inverterKW: (e.inverterKW ?? 0) > 0 && !near(e.inverterKW, s.inverterKW, 0.01)
            case .address: !squeezed(e.address).isEmpty && !s.address.isEmpty && squeezed(e.address) != squeezed(s.address)
            case .province: !e.province.isEmpty && !s.province.isEmpty && e.province != s.province
            case .coordinates: e.latitude != nil && e.longitude != nil && s.latitude != nil
                && !(near(e.latitude, s.latitude, 1e-5) && near(e.longitude, s.longitude, 1e-5))
            }
        }
    }
}
