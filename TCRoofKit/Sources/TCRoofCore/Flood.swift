import Foundation

/// GISTDA repeat-flood lookup stored in the job (`floodGistda`, JSON text), so it shows again offline and prints in the PDF.
/// It says which years flooded around the point, not how deep: the service has no depth.
public struct FloodGistda: Codable, Hashable, Sendable {
    public struct YearPlots: Codable, Hashable, Sendable {
        /// พ.ศ.
        public var year: Int
        /// Repeat-flood plots inside the search box that flooded in that year.
        public var plots: Int
        public init(year: Int, plots: Int) { self.year = year; self.plots = plots }
    }
    public var lat = 0.0
    public var lon = 0.0
    /// Half-side of the search box, in metres.
    public var radiusMeters = 1000
    /// Every year from `firstYear`, flooded or not (plots = 0).
    public var years: [YearPlots] = []
    /// "ต.ยางซ้าย อ.เมืองสุโขทัย จ.สุโขทัย"
    public var place = ""
    public var fetchedAt = Date(timeIntervalSince1970: 0)
    /// The surveyor chose the default estimate because GISTDA did not answer; nothing was fetched.
    public var manual: Bool?
    public init() {}
    public static func estimate(now: Date = Date()) -> FloodGistda { var g = FloodGistda(); g.manual = true; g.fetchedAt = now; return g }

    public static let defaultDepthCm = 50
    /// First year of the GISTDA repeat-flood history (2011).
    public static let firstYear = 2554
    /// GISTDA gives no depth, so the drawing and the check table use the default.
    public var estimatedDepthCm: Int { Self.defaultDepthCm }

    public enum Tone: Sendable { case normal, good, warn, bad }
    public struct Row: Hashable, Sendable { public let label: String; public let value: String; public let tone: Tone }

    public var floodedYears: [YearPlots] { years.filter { $0.plots > 0 } }
    var radiusText: String { radiusMeters >= 1000 ? "\(radiusMeters / 1000) กม." : "\(radiusMeters) ม." }

    /// Plain-language answer: "ท่วม 9 จาก 14 ปี (2554–2567)".
    public var headline: String {
        guard let first = years.first?.year, let last = years.last?.year else { return "" }
        let n = floodedYears.count
        return n == 0 ? "ไม่พบน้ำท่วมซ้ำซากในรัศมี \(radiusText) · \(first)–\(last)" : "ท่วม \(n) จาก \(years.count) ปี (\(first)–\(last))"
    }
    /// "ล่าสุดปี 2567 · ท่วมมากสุดปี 2554 (101 แปลง)"; nil when nothing flooded.
    public var detail: String? {
        let f = floodedYears
        guard let latest = f.last, let most = f.max(by: { $0.plots < $1.plots }) else { return nil }
        return "ล่าสุดปี \(latest.year)" + (most.year == latest.year ? "" : " · ท่วมมากสุดปี \(most.year) (\(most.plots) แปลง)")
    }

    /// Bars for each year, tallest = the most plots that flooded; drawn by the editor and the PDF from the same ops.
    public static let chartHeight = 112.0
    public func chart(width: Double = 480) -> Sketch {
        let n = max(years.count, 1), slot = width / Double(n), barW = min(24, slot * 0.62), top = 16.0, base = 78.0
        let maxPlots = Double(max(years.map(\.plots).max() ?? 1, 1))
        let orange = RGBA(hex: 0xC4650B), grey = RGBA(hex: 0xC9D1DC), ink = RGBA(hex: 0x16325C), muted = RGBA(hex: 0x5B6B82)
        var o: [DrawOp] = []
        for (i, y) in years.enumerated() {
            let cx = slot * (Double(i) + 0.5), h = y.plots > 0 ? max(4, (base - top) * Double(y.plots) / maxPlots) : 2
            o.append(.rect(Box(cx - barW / 2, base - h, barW, h), stroke: nil, fill: y.plots > 0 ? orange : grey))
            if y.plots > 0 { o.append(.text("\(y.plots)", at: Pt(cx, base - h - 7), size: 9, bold: true, color: orange, align: .center)) }
            o.append(.text(String(y.year % 100), at: Pt(cx, base + 10), size: 9.5, bold: y.plots > 0, color: y.plots > 0 ? ink : muted, align: .center))
        }
        o.append(.line(Pt(0, base), Pt(width, base), width: 1, color: muted))
        o.append(.text("ปี พ.ศ. 25xx · ความสูงแท่ง = จำนวนแปลงที่ท่วมในรัศมี \(radiusText)", at: Pt(width / 2, base + 28), size: 9, color: muted, align: .center))
        return Sketch(width: width, height: Self.chartHeight, ops: o)
    }

    /// Label / value rows of the GISTDA card and the PDF table.
    public var rows: [Row] {
        if manual == true {
            return [Row(label: "ความลึกน้ำ", value: "ยังไม่ได้ข้อมูลจาก GISTDA · ใช้ค่าประเมิน \(estimatedDepthCm) ซม.", tone: .bad)]
        }
        let f = floodedYears
        var r = [Row(label: "สรุป", value: headline + (detail.map { " · " + $0 } ?? ""), tone: f.isEmpty ? .good : .warn)]
        if !f.isEmpty { r.append(Row(label: "จำนวนแปลงที่ท่วม", value: f.map { "\($0.year) (\($0.plots))" }.joined(separator: " · "), tone: .normal)) }
        r.append(Row(label: "ความลึกน้ำ", value: "ไม่มีข้อมูลความลึก · ใช้ค่าประเมิน \(estimatedDepthCm) ซม.", tone: .bad))
        return r
    }
    /// "GISTDA API: flood-freq · ต.ยางซ้าย … · ดึงเมื่อ 30/9/2569 10:37 · ควรยืนยันความลึกกับเจ้าหน้าที่สถานี"
    public var footnote: String {
        if manual == true { return "ใช้ค่าประเมิน \(estimatedDepthCm) ซม. เพราะ GISTDA ไม่ตอบ · ควรยืนยันความลึกกับเจ้าหน้าที่สถานี" }
        var f = Date.FormatStyle(date: .numeric, time: .shortened).locale(Locale(identifier: "th_TH"))
        f.calendar = Calendar(identifier: .buddhist)
        return ["GISTDA API: flood-freq · ตัวเลขในวงเล็บคือจำนวนแปลงที่ท่วม", place.isEmpty ? nil : place, "ดึงเมื่อ " + fetchedAt.formatted(f),
                "ควรยืนยันความลึกกับเจ้าหน้าที่สถานี"].compactMap { $0 }.joined(separator: " · ")
    }
    /// One line for the report summary.
    public var summary: String {
        if manual == true { return "ไม่ได้ข้อมูล GISTDA · ใช้ค่าประเมิน \(estimatedDepthCm) ซม." }
        let n = floodedYears.count
        return "GISTDA: " + (n == 0 ? "ไม่พบพื้นที่ท่วมซ้ำซาก" : "ท่วม \(n) ปีในรัศมี \(radiusText)")
    }
    /// Banner over the drawing.
    public var banner: String {
        if manual == true { return "ยังไม่ได้ข้อมูล GISTDA · ใช้ค่าประเมินระดับน้ำ \(estimatedDepthCm) ซม." }
        let n = floodedYears.count
        return "GISTDA · " + (n == 0 ? "ไม่พบน้ำท่วมซ้ำซาก" : "ท่วม \(n) ปี") + " รัศมี \(radiusText) · ความลึกเป็นค่าประเมิน"
    }
}

public extension Values {
    /// The stored GISTDA lookup, if any (and readable).
    var gistda: FloodGistda? {
        let t = text("floodGistda")
        guard !t.isEmpty, let d = t.data(using: .utf8) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(FloodGistda.self, from: d)
    }
    mutating func setGistda(_ g: FloodGistda?) {
        guard let g else { self["floodGistda"] = nil; return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(g), let s = String(data: d, encoding: .utf8) { self["floodGistda"] = .text(s) }
    }
}

/// Water level, minimum install level and the equipment height check of A4.
public enum FloodCheck {
    public static let freeboardCm = 50.0
    public static let defaultFloorCm = 0.0, defaultMountCm = 100.0, defaultEmergencyCm = 140.0

    public enum State: Sendable { case never, flooded, unknownEmpty, unknownFetched }
    public static func state(_ v: Values) -> State {
        switch v.choice("floodHistory") {
        case "เคย"?: return .flooded
        case "ไม่ทราบ"?: return v.gistda == nil ? .unknownEmpty : .unknownFetched
        default: return .never
        }
    }
    /// Water level in cm above the reference: the reported depth when flooded, the GISTDA estimate when unknown and fetched, else 0.
    public static func level(_ v: Values) -> Double {
        switch state(v) {
        case .flooded: return max(0, v.number("floodDepth") ?? 0)
        case .unknownFetched: return Double(v.gistda?.estimatedDepthCm ?? 0)
        default: return 0
        }
    }
    /// (level + freeboard) rounded up to 10 cm; with no water it is just the freeboard from the reference level.
    public static func minCm(_ v: Values) -> Int {
        let l = level(v)
        return Int(((l + freeboardCm) / 10).rounded(.up) * 10)
    }
    public static func floorCm(_ v: Values) -> Double { v.number("invFloorCm") ?? defaultFloorCm }
    public static func mountCm(_ v: Values) -> Double { v.number("invMountCm") ?? defaultMountCm }
    public static func emergencyCm(_ v: Values) -> Double { v.number("emgMountCm") ?? defaultEmergencyCm }

    public enum Status: Hashable, Sendable { case ok, pass, fail(Int), aboveWater, belowWater(Int), floodedHere(Int), nearFlood
        public var isFail: Bool { if case .fail = self { return true }; return false }
        public var text: String {
            switch self {
            case .ok: return "✓ สูงกว่าน้ำ"
            case .pass: return "✓ ผ่าน"
            case .fail(let n): return "✗ ต่ำกว่า \(n) ซม."
            case .aboveWater: return "✓ สูงกว่าน้ำ"
            case .belowWater(let n): return "! ต่ำกว่าน้ำ \(n) ซม."
            case .floodedHere(let n): return "! น้ำเคยเข้า \(n) ซม."
            case .nearFlood: return "! ใกล้พื้นที่ท่วมซ้ำซาก"
            }
        }
        public enum Tone: Sendable { case good, warn, bad }
        public var tone: Tone {
            switch self {
            case .ok, .pass, .aboveWater: return .good
            case .fail: return .bad
            default: return .warn
            }
        }
    }
    public struct Row: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        /// Section number the value comes from ("B2").
        public let tag: String
        public let height: String
        public let status: Status
    }
    public struct Result: Sendable {
        public var state: State
        public var level: Double
        public var minCm: Int
        public var rows: [Row]
        public var mdbName: String
        public var fails: Int { rows.filter { $0.status.isFail }.count }
    }

    /// Everything the drawing, the table and the bottom bar show, computed from the job.
    public static func result(_ job: Job) -> Result {
        let v = job.values, lvl = level(v), min = minCm(v), st = state(v)
        let sections = job.sectionsByCategory.flatMap(\.sections)
        func first(_ t: ModuleType) -> NumberedSection? { sections.first { $0.module.type == t } }
        let floor = floorCm(v), mount = mountCm(v)
        func cm(_ x: Double) -> String { "\(Int(x.rounded())) ซม." }
        var rows: [Row] = []
        if let inv = first(.inverter) {
            let n = sections.filter { $0.module.type == .inverter }.reduce(0) { $0 + Int($1.module.values.number("inverterCount") ?? 0) }
            rows.append(Row(id: "floor", name: "พื้นห้อง Inverter", tag: inv.number, height: cm(floor),
                            status: lvl > 0 && floor < lvl ? .belowWater(Int((lvl - floor).rounded())) : .aboveWater))
            let h = floor + mount
            rows.append(Row(id: "inv", name: "อินเวอร์เตอร์" + (n > 0 ? " × \(n)" : ""), tag: inv.number, height: cm(h), status: pass(h, min)))
        }
        if let bf = first(.backfeed) {
            let h = floor + mount
            rows.append(Row(id: "smdb", name: "ตู้ SMDB-PV · รีเลย์กันย้อน", tag: bf.number, height: cm(h), status: pass(h, min)))
        }
        if let f = first(.fts) {
            let h = emergencyCm(v)
            rows.append(Row(id: "emg", name: "ปุ่ม Emergency", tag: f.number, height: cm(h), status: pass(h, min)))
        }
        let mdb = job.mainBoardName
        if lvl > 0 {
            rows.append(Row(id: "mdb", name: "\(mdb) จุดเชื่อมต่อ (เดิม)", tag: "A3", height: "ฐาน 0 ซม.",
                            status: st == .flooded ? .floodedHere(Int(lvl.rounded())) : .nearFlood))
        }
        return Result(state: st, level: lvl, minCm: min, rows: rows, mdbName: mdb)
    }
    private static func pass(_ h: Double, _ min: Int) -> Status { h >= Double(min) ? .pass : .fail(min - Int(h.rounded())) }

    /// "ต้อง ≥ 130 ซม. จากดินเดิม"
    public static func requirement(_ v: Values) -> String {
        "ต้อง ≥ \(minCm(v)) ซม. จาก" + (v.choice("floodRef") ?? "ดินเดิม")
    }
    /// The bottom-bar line of the wide page.
    public static func statusLine(_ r: Result) -> String {
        let head = r.fails > 0 ? "อุปกรณ์ต่ำกว่าเกณฑ์ \(r.fails) รายการ" : "ครบช่องบังคับแล้ว · อุปกรณ์ใหม่ผ่านเกณฑ์ ≥ \(r.minCm) ซม."
        switch r.state {
        case .flooded: return head + " · จุดต่อ \(r.mdbName) เคยน้ำท่วม"
        case .unknownFetched: return head + " · ระดับน้ำจาก GISTDA เป็นค่าประเมิน"
        case .unknownEmpty: return head + " · ยังไม่มีข้อมูลน้ำท่วม ดึงจาก GISTDA ได้"
        case .never: return head
        }
    }
}

public extension Job {
    var floodCheck: FloodCheck.Result { FloodCheck.result(self) }
    /// Name of the first transformer's main board ("MDB1"), the connection point that already exists.
    var mainBoardName: String {
        let n = values.transformers("trafos").first?.resolvedBoards.first?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "MDB1" : n
    }
}
