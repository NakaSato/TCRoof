import Foundation

/// B2 inverter area: the equipment, breakers, cables, tray and ladder chosen from the catalog for the inverters picked,
/// and whether they fit the measured area. Pure values; the reference is the canvas page `iPadB2`.
public struct InverterStation: Hashable, Sendable {
    public enum Site: String, CaseIterable, Sendable {
        /// Covered station with columns.
        case outdoor = "out"
        /// Wall-mounted inside a building.
        case indoor = "in"
        public var label: String { self == .outdoor ? "ภายนอกอาคาร" : "ภายในอาคาร" }
    }

    // MARK: inputs

    /// Inverter sizes (kW), 1…`maxInverters`.
    public var sizes: [Int]
    /// True when `sizes` were not picked yet: seeded from an old `inverterCount`, or one inverter on a new section.
    public var sizesAssumed = false
    /// Measured width ก, length ย and height ส (m); nil when not measured.
    public var width: Double?
    public var length: Double?
    public var height: Double?
    public var site: Site = .outdoor
    /// Outdoor column spans set by the surveyor (all but the last); nil = automatic.
    public var userSpans: [Double]?
    /// Tray / ladder width picked by the surveyor (mm); never used below the calculated minimum.
    public var trayPick: Int?
    public var ladderPick: Int?
    public var catalog: EquipmentCatalog

    public init(sizes: [Int], width: Double? = nil, length: Double? = nil, height: Double? = nil, site: Site = .outdoor,
                userSpans: [Double]? = nil, trayPick: Int? = nil, ladderPick: Int? = nil, catalog: EquipmentCatalog = .bundled) {
        self.sizes = sizes; self.width = width; self.length = length; self.height = height; self.site = site
        self.userSpans = userSpans; self.trayPick = trayPick; self.ladderPick = ladderPick; self.catalog = catalog
    }

    // MARK: limits and standard sizes

    public static let maxInverters = 8
    public static let widthRange = 1.5...5.0, widthStep = 0.1
    public static let lengthRange = 4.0...16.0, lengthStep = 0.5
    public static let spanRange = 0.5...6.0, spanStep = 0.05, maxSpans = 10
    public static let minWalkway = 1.20
    public static let traySizes = [100, 150, 200, 300, 400, 450, 500, 600]
    public static let ladderSizes = [200, 300, 400, 500, 600, 750, 900]
    public static let feederSizes = [100, 125, 160, 200, 250, 320, 400, 500, 630, 800, 1000, 1250]
    /// Width shown for the outdoor room (m).
    public static let roomWidth = 2.5

    // MARK: per inverter

    public struct Breaker: Hashable, Sendable {
        /// Maximum AC current (A).
        public var current: Double
        public var at: Int
        public var af: Int
    }
    /// Inverter output breaker: first standard AT ≥ Imax × factor; AF = max(100, AT).
    public func breaker(kw: Int) -> Breaker {
        let i = catalog.inverter(kw: kw).imax, std = catalog.rules.cbStd
        let at = std.first { Double($0) >= i * catalog.rules.cbFactor - 1e-9 } ?? std[std.count - 1]
        return Breaker(current: i, at: at, af: max(100, at))
    }

    public struct Cable: Hashable, Sendable {
        public var label: String
        /// Outside diameter including the ground cable (mm).
        public var od: Int
    }
    /// Inverter AC cable by breaker AT (the largest for anything bigger than the table).
    public static func cable(at: Int) -> Cable {
        let t: [Int: (String, Int, Int)] = [80: ("4×25+G10", 30, 7), 125: ("4×35+G16", 33, 8), 160: ("4×50+G16", 37, 8),
                                            200: ("4×95+G16", 47, 8), 250: ("4×120+G25", 52, 10)]
        let r = t[at] ?? t[250]!
        return Cable(label: r.0, od: r.1 + r.2)
    }
    public func cable(kw: Int) -> Cable { Self.cable(at: breaker(kw: kw).at) }

    // MARK: tray, feeder, ladder

    /// Smallest standard tray ≥ 1.2 × Σ cable OD.
    public var trayMin: Int {
        let need = 1.2 * Double(sizes.reduce(0) { $0 + cable(kw: $1).od })
        return Self.traySizes.first { Double($0) >= need - 1e-9 } ?? Self.traySizes[Self.traySizes.count - 1]
    }
    public var trayWidth: Int { max(trayMin, trayPick ?? 0) }

    public struct Feeder: Hashable, Sendable {
        /// Σ Imax (A).
        public var current: Double
        public var at: Int
        /// Parallel runs of 4 single cores.
        public var runs: Int
        /// Phase conductor size (mm²).
        public var mm2: Int
        /// Ground conductor size (mm²).
        public var ground: Int
        /// Single core diameter (mm).
        public var diameter: Double
        /// Smallest standard ladder for the runs, cables spaced one diameter apart.
        public var ladderMin: Int
        /// "4×1C 120 + G25", "2×(4×1C 120) + G35".
        public var label: String { (runs > 1 ? "\(runs)×(" : "") + "4×1C \(mm2)" + (runs > 1 ? ")" : "") + " + G\(ground)" }
    }
    /// Single-core Cu table: mm², A, Ø mm.
    static let singleCore: [(mm2: Int, amp: Double, d: Double)] = [(25, 100, 11.5), (35, 125, 12.5), (50, 150, 14), (70, 190, 16), (95, 230, 18),
                                                                    (120, 270, 20), (150, 310, 22), (185, 355, 24.5), (240, 420, 27.5), (300, 480, 30.5)]
    /// AC-DB → injection point.
    public var feeder: Feeder {
        let itot = sizes.reduce(0) { $0 + catalog.inverter(kw: $1).imax }
        let at = Self.feederSizes.first { Double($0) >= itot * catalog.rules.cbFactor - 1e-9 } ?? Self.feederSizes[Self.feederSizes.count - 1]
        var pick: (runs: Int, c: (mm2: Int, amp: Double, d: Double))?
        for runs in 1...4 { if let c = Self.singleCore.first(where: { $0.amp * Double(runs) >= Double(at) }) { pick = (runs, c); break } }
        let (runs, c) = pick ?? (4, Self.singleCore[Self.singleCore.count - 1])
        let g = at <= 100 ? 10 : at <= 200 ? 16 : at <= 400 ? 25 : at <= 500 ? 35 : at <= 800 ? 50 : 70
        let need = Double(8 * runs - 1) * c.d + 50
        let lad = Self.ladderSizes.first { Double($0) >= need - 1e-9 } ?? Self.ladderSizes[Self.ladderSizes.count - 1]
        return Feeder(current: itot, at: at, runs: runs, mm2: c.mm2, ground: g, diameter: c.d, ladderMin: lad)
    }
    public var ladderWidth: Int { max(feeder.ladderMin, ladderPick ?? 0) }

    /// The next standard size up or down from `value`, never below `min`; nil at either end.
    public static func step(_ sizes: [Int], from value: Int, by d: Int, min: Int) -> Int? {
        guard let i = sizes.firstIndex(of: value), sizes.indices.contains(i + d), sizes[i + d] >= min else { return nil }
        return sizes[i + d]
    }
    /// The next catalog inverter size (clamped at the ends).
    public func stepSize(_ kw: Int, by d: Int) -> Int {
        let s = catalog.inverterSizes
        guard !s.isEmpty else { return kw }
        let i = s.firstIndex(of: kw) ?? s.firstIndex { $0 >= kw } ?? s.count - 1
        return s[Swift.max(0, Swift.min(s.count - 1, i + d))]
    }

    /// "2 × 125AT" or "2×125+1×200 AT".
    public var breakerSummary: String {
        var count: [Int: Int] = [:]
        for k in sizes { count[breaker(kw: k).at, default: 0] += 1 }
        let keys = count.keys.sorted()
        if keys.count == 1 { return "\(count[keys[0]]!) × \(keys[0])AT" }
        return keys.map { "\(count[$0]!)×\($0)" }.joined(separator: "+") + " AT"
    }
    public var totalKW: Int { sizes.reduce(0, +) }

    // MARK: the row of equipment

    public struct Item: Hashable, Sendable {
        public enum Kind: Sendable { case cabinet, inverter }
        public var kind: Kind
        public var name: String
        /// Width along the row and depth (m).
        public var w: Double
        public var d: Double
        /// Inverter size, for inverters.
        public var kw: Int?
        /// Height (m), from the catalog: what the front and side views draw.
        public var h: Double = 0
    }
    /// Equipment in row order and the clear gap after each (one fewer than the items).
    public var row: (items: [Item], gaps: [Double]) {
        let ac = Double(catalog.acCabinet(inverters: sizes.count).w) / 1000
        let meter = Double(catalog.cabinets.meter.w) / 1000, sem = Double(catalog.cabinets.sem.w) / 1000
        let acH = Double(catalog.acCabinet(inverters: sizes.count).h) / 1000
        var items = [Item(kind: .cabinet, name: "AC-DB-01", w: ac, d: 0.45, h: acH),
                     Item(kind: .cabinet, name: "METER-DB-01", w: meter, d: 0.28, h: Double(catalog.cabinets.meter.h) / 1000)]
        var gaps: [Double]
        let gap: Double
        if site == .outdoor {
            gaps = [0.24, 0.45]; gap = 0.47
        } else {
            items.append(Item(kind: .cabinet, name: "SEM-DB", w: sem, d: 0.28, h: Double(catalog.cabinets.sem.h) / 1000))
            gaps = [0.24, 0.37, 0.46]; gap = 0.46
        }
        for (i, kw) in sizes.enumerated() {
            let inv = catalog.inverter(kw: kw)
            let dc = catalog.dcCabinet(mppt: inv.mppt)
            items.append(Item(kind: .inverter, name: "INVERTER No.\(i + 1)", w: Double(inv.w) / 1000, d: Double(inv.d) / 1000, kw: kw, h: Double(inv.h) / 1000))
            items.append(Item(kind: .cabinet, name: String(format: "DC-DB-%02d", i + 1), w: Double(dc.w) / 1000, d: 0.28, h: Double(dc.h) / 1000))
            gaps += [gap, gap]
        }
        gaps.removeLast(gaps.count - (items.count - 1))
        return (items, gaps)
    }
    /// Length of the row, cabinets and gaps (m).
    public var used: Double { let r = row; return r.items.reduce(0) { $0 + $1.w } + r.gaps.reduce(0, +) }

    /// Rounds up to 0.5 m (ignoring float noise).
    static func upToHalf(_ x: Double) -> Double { ((x * 2 * 1e6).rounded() / 1e6).rounded(.up) / 2 }

    /// Minimum room length (outdoor, row + 2.25) or wall length (indoor, row + 0.60), rounded up to 0.5 m.
    public var minLength: Double { Self.upToHalf(used + (site == .outdoor ? 2.25 : 0.60)) }
    /// Length the plan is drawn with: the measured one, or the minimum when not measured.
    public var planLength: Double { length ?? minLength }
    public var planWidth: Double { width ?? Self.roomWidth }
    /// How much longer the area must be (m); 0 when it fits.
    public var shortfall: Double { max(0, minLength - planLength) }
    public var fits: Bool { minLength <= planLength + 1e-9 }

    // MARK: outdoor frame

    /// Frame and tray band from the left wall (m): start 1.05, back 0.17.
    public static let bandX = 1.05, bandY = 0.17
    public var bandDepth: Double { max(0.40, Double(trayWidth) / 1000 + 0.20) }
    public var bandLength: Double { 0.10 + used + 0.30 }

    /// Clear walkway in front of the equipment (m).
    public var walkway: Double {
        site == .outdoor ? planWidth - (Self.bandY + bandDepth + 0.45) : planWidth - 0.85
    }
    public var walkwayOK: Bool { walkway >= Self.minWalkway - 1e-9 }

    // MARK: outdoor columns

    /// `2.5, k × (L − 5)/k, 2.5` with k = ceil((L − 5)/2.5); `[L]` for a room of 5 m or less.
    public static func autoSpans(_ L: Double) -> [Double] {
        let mid = L - 5
        guard mid > 0 else { return [L] }
        let k = max(1, Int(((mid / 2.5 * 1e6).rounded() / 1e6).rounded(.up)))
        return [2.5] + Array(repeating: mid / Double(k), count: k) + [2.5]
    }
    static func r2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
    /// The spans the surveyor sets (all but the last).
    public var editableSpans: [Double] { userSpans ?? Array(Self.autoSpans(planLength).dropLast()) }
    /// The last span: what is left of L.
    public var lastSpan: Double { Self.r2(planLength - editableSpans.reduce(0, +)) }
    public var spans: [Double] { editableSpans + [lastSpan] }
    public var spansOK: Bool { lastSpan >= Self.spanRange.lowerBound - 1e-9 }
    /// Spans used by the plan: the surveyor's when they add up, else automatic.
    public var planSpans: [Double] { spansOK ? spans : Self.autoSpans(planLength) }
    /// Equal spans over L, the last one implied.
    public var equalSpans: [Double] {
        let m = spans.count
        return m > 1 ? Array(repeating: planLength / Double(m), count: m - 1) : editableSpans
    }

    // MARK: checks

    /// Width and length measured (the plan is drawn with defaults until then).
    public var measured: Bool { width != nil && length != nil }
    public var isOK: Bool { measured && fits && walkwayOK && (site == .indoor || spansOK) }
    /// Status line of the page.
    public var status: String {
        let n = sizes.count
        if !measured { return "ใส่ขนาดพื้นที่ที่มีจริง ก × ย | แปลนแสดงขนาดขั้นต่ำ" }
        if site == .outdoor && !spansOK { return "ระยะช่วงเสารวมเกินความยาวห้อง" }
        if isOK { return "ครบช่องบังคับแล้ว | พื้นที่พอสำหรับ \(n) เครื่อง" }
        if !fits { return "พื้นที่จริงสั้นไป \(String(format: "%.1f", shortfall)) ม. สำหรับ \(n) เครื่อง" }
        return "ทางเดินหน้าตู้แคบกว่า 1.2 ม."
    }
    /// "= A1 ✓" / "≠ A1 120" (the kWp of A1), nil when A1 has no capacity.
    public func capacityCheck(_ kwp: Double?) -> (ok: Bool, text: String)? {
        guard let kwp, kwp > 0 else { return nil }
        let ok = abs(Double(totalKW) - kwp) < 1e-6
        return (ok, ok ? "= A1 ✓" : "≠ A1 \(fmt(kwp))")
    }
}

// MARK: - stored answers

public extension InverterStation {
    enum Key {
        public static let width = "invAreaW", length = "invAreaL", height = "invAreaH", boundary = "invBoundary", site = "invSite"
        public static let sizes = "invSizes", spans = "invSpans", tray = "invTrayW", ladder = "invLadderW"
        public static let sizeLWH = "sizeLWH", count = "inverterCount"
    }

    /// "6x2", "6 x 2 x 3", "6×2.5" → (6, 2, nil / 3), in the labelled order ก x ย x ส.
    static func parseLWH(_ s: String) -> (Double, Double, Double?)? {
        let parts = s.lowercased().split { "x×*".contains($0) }.map { NumberInput.value(String($0).trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 2, let a = parts[0], let b = parts[1] else { return nil }
        return (a, b, parts.count > 2 ? parts[2] : nil)
    }
    /// "9.5 x 2.5 x 3" as written back to `sizeLWH`.
    static func formatLWH(_ w: Double?, _ l: Double?, _ h: Double?) -> String {
        guard let w, let l else { return "" }
        return [w, l, h].compactMap { $0 }.map { fmt($0) }.joined(separator: " x ")
    }

    /// The station from a B2 section's answers. Old sections (only `sizeLWH` / `inverterCount`) are read as labelled,
    /// with assumed inverters of the smallest catalog size; a `sizeLWH` or count edited on the form page wins over stale numbers.
    init(_ v: Values, catalog: EquipmentCatalog = .bundled) {
        var w = v.number(Key.width), l = v.number(Key.length), h = v.number(Key.height)
        let lwh = v.text(Key.sizeLWH).trimmingCharacters(in: .whitespaces)
        if !lwh.isEmpty, lwh != Self.formatLWH(w, l, h), let p = Self.parseLWH(lwh) { (w, l, h) = (p.0, p.1, p.2 ?? h) }
        var sizes = v.text(Key.sizes).split(separator: ",").compactMap { Int(NumberInput.value(String($0)) ?? 0) }.filter { $0 > 0 }
        var assumed = false
        let count = v.number(Key.count).map { Int($0) }.flatMap { $0 > 0 ? min($0, Self.maxInverters) : nil }
        if sizes.isEmpty {
            sizes = Array(repeating: catalog.inverterSizes.first ?? 60, count: count ?? 1)
            assumed = true
        } else if let count, count != sizes.count {
            sizes = count < sizes.count ? Array(sizes.prefix(count)) : sizes + Array(repeating: sizes[sizes.count - 1], count: count - sizes.count)
        }
        let spans = parseSpans(v.text(Key.spans))
        self.init(sizes: Array(sizes.prefix(Self.maxInverters)), width: w, length: l, height: h,
                  site: v.choice(Key.site).flatMap { c in Site.allCases.first { $0.label == c || $0.rawValue == c } } ?? .outdoor,
                  userSpans: spans.isEmpty ? nil : spans,
                  trayPick: v.number(Key.tray).map { Int($0) }, ladderPick: v.number(Key.ladder).map { Int($0) }, catalog: catalog)
        sizesAssumed = assumed
    }

    /// The section was filled on the B2 wide page (sizes picked or the area measured there).
    static func isDesigned(_ v: Values) -> Bool { !v.text(Key.sizes).isEmpty || v.number(Key.width) != nil }

    /// "ห้องขั้นต่ำ 9.5 × 2.5 ม." / "ผนังยาวขั้นต่ำ 8.5 ม."
    var minimumText: String {
        site == .outdoor ? "ห้องขั้นต่ำ \(String(format: "%.1f", minLength)) × \(fmt(Self.roomWidth)) ม." : "ผนังยาวขั้นต่ำ \(String(format: "%.1f", minLength)) ม."
    }
    /// "2 × 60 kW" / "60 + 60 + 80 kW"
    var sizesText: String {
        Set(sizes).count == 1 ? "\(sizes.count) × \(sizes[0]) kW" : sizes.map(String.init).joined(separator: " + ") + " kW"
    }

    /// Writes the station back, keeping `sizeLWH` and `inverterCount` in step. Sizes are stored only once picked.
    func write(to v: inout Values) {
        func num(_ k: String, _ x: Double?) { v[k] = x.map { .text(fmt($0)) } }
        num(Key.width, width); num(Key.length, length); num(Key.height, height)
        v[Key.site] = .choice(site.label, other: "")
        if !sizesAssumed { v[Key.sizes] = .text(sizes.map(String.init).joined(separator: ",")) }
        v[Key.spans] = userSpans.map { .text($0.map { fmt($0) }.joined(separator: ",")) }
        v[Key.tray] = trayPick.flatMap { $0 > trayMin ? .text(String($0)) : nil }
        v[Key.ladder] = ladderPick.flatMap { $0 > feeder.ladderMin ? .text(String($0)) : nil }
        let lwh = Self.formatLWH(width, length, height)
        if !lwh.isEmpty { v[Key.sizeLWH] = .text(lwh) }
        if !sizesAssumed { v[Key.count] = .text(String(sizes.count)) }
    }
}
