import Foundation

/// C1 "หลังคา (แปลนและโครงสร้าง)" wide page (docs/ui/survey-c1): the roof plan, the frame type and section A-A, the
/// member sizes and the six photo angles. Field ids, labels and Excel cells are unchanged; the page's own answers
/// (`frameType`, `ridgeDir`, `trussBays`, `postGrid`, `pvOrientation`, `roofShots`, `eaveOverhang`, `clearHeight`,
/// `purlinSpacing`, `roofStd`, `pvRows`, `pvPerTable`, `pvGap`) are optional and hidden, so the section's completion
/// counts as before.
public enum Roof {
    public enum Key {
        public static let spansX = "spansX", spansY = "spansY", sheetDir = "sheetDir", obstacles = "obst"
        public static let frame = "frameType", ridge = "ridgeDir", bays = "trussBays", posts = "postGrid"
        public static let pvOrientation = "pvOrientation", shots = "roofShots"
        public static let overhang = "eaveOverhang", clearHeight = "clearHeight"
        public static let purlin = "purlinSpacing", standard = "roofStd"
        public static let pvRows = "pvRows", pvPerTable = "pvPerTable", pvGap = "pvGap"
        public static let shape = "roofShape", material = "roofMaterial", structure = "roofStructure", panels = "panelsBefore"
        public static let aerial = "aerialPhoto", general = "generalPhotos", structPhotos = "structPhotos"
        public static func member(_ n: Int) -> String { "comp\(n)" }
    }

    // MARK: spans

    public enum Axis: Sendable { case x, y }
    public static func key(_ a: Axis) -> String { a == .x ? Key.spansX : Key.spansY }
    /// The grid spans in metres, or the schema's placeholder when none are stored (the plan is never empty).
    public static func spans(_ v: Values, _ a: Axis) -> [Double] {
        let s = parseSpans(v.text(key(a)))
        if !s.isEmpty { return s }
        return a == .x ? [1.5, 4, 4, 4, 4, 1.5] : [1.5, 4.5, 4, 4.5, 1.5]
    }
    /// Writes the spans back in the form's format, "1.5,4,4,4,4,1.5".
    public static func setSpans(_ v: inout Values, _ a: Axis, _ s: [Double]) {
        let t = s.filter { $0 > 0 }.map { fmt(($0 * 1000).rounded() / 1000, digits: 3) }.joined(separator: ",")
        v[key(a)] = t.isEmpty ? nil : .text(t)
    }
    /// Grid line names: 1, 2, 3 … across x, A, B, C … down y.
    public static func gridName(_ a: Axis, _ i: Int) -> String {
        a == .x ? String(i + 1) : i < 26 ? String(UnicodeScalar(UInt8(65 + i))) : "A\(i - 25)"
    }
    public static func spanName(_ a: Axis, _ i: Int) -> String { gridName(a, i) + "-" + gridName(a, i + 1) }

    // MARK: ridge

    public enum Ridge: String, Sendable { case h, v }
    /// The ridge runs along x (`h`, นอน) or y (`v`, ตั้ง). Without a stored `ridgeDir` it follows `sheetDir`: the sheets'
    /// ribs run down the slope, across the ridge, and the old plan (`Drawings.plan`) draws ribs along x when `sheetDir`
    /// is แนวนอน or empty, so แนวนอน / empty means a ridge along y.
    public static func ridge(_ v: Values) -> Ridge {
        if let r = Ridge(rawValue: v.text(Key.ridge)) { return r }
        return v.choice(Key.sheetDir) == "แนวตั้ง" ? .h : .v
    }
    /// Stores the ridge and writes `sheetDir` back so the old plan, the PDF and Excel agree.
    public static func setRidge(_ v: inout Values, _ r: Ridge) {
        v[Key.ridge] = .text(r.rawValue)
        v[Key.sheetDir] = .choice(r == .h ? "แนวตั้ง" : "แนวนอน", other: "")
    }

    // MARK: frame

    public static func frame(_ v: Values) -> RoofFrame { RoofFrame(rawValue: v.text(Key.frame)) ?? .pratt }
    /// A frame type was chosen on the C1 page; the report then draws the new plan and section and names the members by it.
    public static func hasFrame(_ v: Values) -> Bool { RoofFrame(rawValue: v.text(Key.frame)) != nil }
    public static func setFrame(_ v: inout Values, _ f: RoofFrame) { v[Key.frame] = .text(f.rawValue) }

    /// Width across the ridge (the section's span).
    public static func span(_ v: Values) -> Double {
        (ridge(v) == .h ? spans(v, .y) : spans(v, .x)).reduce(0, +)
    }
    /// Truss panels per half: stored, else about one per metre (at least 2).
    public static func autoBays(_ v: Values) -> Int { max(2, Int((span(v) / 2).rounded())) }
    public static func bays(_ v: Values) -> Int {
        if let n = v.number(Key.bays), n >= 2 { return min(20, Int(n)) }
        return autoBays(v)
    }
    public static func baysAreAuto(_ v: Values) -> Bool { !((v.number(Key.bays) ?? 0) >= 2) }
    public static let baysRange = 2...20
    public static func setBays(_ v: inout Values, _ n: Int?) {
        v[Key.bays] = n.map { .text(String(min(baysRange.upperBound, max(baysRange.lowerBound, $0)))) }
    }

    /// Eave overhang and clear height (m) for section A-A; the design's 0.70 (1.20 for ชายคาฝ้า) / 4.00 until measured.
    public static func overhang(_ v: Values) -> Double { v.number(Key.overhang) ?? frame(v).overhang }
    public static func clearHeight(_ v: Values) -> Double { v.number(Key.clearHeight) ?? 4.0 }
    public static func setLength(_ v: inout Values, _ key: String, _ m: Double?) {
        v[key] = m.map { .text(fmt(($0 * 100).rounded() / 100)) }
    }

    // MARK: purlins

    /// ระยะแป measured along the slope (m), 0.60–1.50 in 0.05 steps; 1.00 until set.
    public static let purlinRange = 0.6...1.5
    public static func purlinSpacing(_ v: Values) -> Double {
        guard let p = v.number(Key.purlin), p > 0 else { return 1.0 }
        return min(purlinRange.upperBound, max(purlinRange.lowerBound, p))
    }
    public static func setPurlinSpacing(_ v: inout Values, _ p: Double?) {
        v[Key.purlin] = p.map { .text(String(format: "%.2f", min(purlinRange.upperBound, max(purlinRange.lowerBound, ($0 * 100).rounded() / 100)))) }
    }
    /// Purlin lines across the ridge, metres from the plan's first grid line: 0.15 m each side of the ridge, then every
    /// `spacing · cos(slope)` down to the eaves (the design's `PUR`).
    public static func purlinLines(_ v: Values) -> [Double] {
        let across = ridge(v) == .h ? spans(v, .y).reduce(0, +) : spans(v, .x).reduce(0, +)
        let step = purlinSpacing(v) * cos(frame(v).slope * .pi / 180)
        var out: [Double] = [], d = 0.15
        while d < across / 2 - 0.05 { out += [across / 2 - d, across / 2 + d]; d += step }
        return out
    }
    /// "ข้างละ 9 แนว"
    public static func purlinNote(_ v: Values) -> String {
        let across = ridge(v) == .h ? spans(v, .y).reduce(0, +) : spans(v, .x).reduce(0, +)
        let step = purlinSpacing(v) * cos(frame(v).slope * .pi / 180)
        return "ข้างละ \(Int(((across / 2 - 0.15) / step).rounded(.up))) แนว"
    }

    // MARK: PV layout settings (การจัดแผง)

    /// Rows of modules per table down the slope: 0 = one continuous field (ต่อเนื่อง), else 1–4.
    public static func pvRows(_ v: Values) -> Int { min(4, max(0, Int(v.number(Key.pvRows) ?? 0))) }
    /// Modules per table along the ridge: 0 = continuous, else 2, 4 or 6. Until chosen, portrait modules go in pairs
    /// (the design's default, "ทุก 2 แผง") and landscape ones run continuous.
    public static func pvPerTable(_ v: Values, portrait: Bool? = nil) -> Int {
        guard let n = v.number(Key.pvPerTable) else { return (portrait ?? pvPortrait(v)) ? 2 : 0 }
        return min(6, max(0, Int(n)))
    }
    /// Gap between tables (m), 0–2; 0.40 until set.
    public static func pvGap(_ v: Values) -> Double { min(2, max(0, v.number(Key.pvGap) ?? 0.4)) }
    public static func setPV(_ v: inout Values, rows: Int? = nil, perTable: Int? = nil, gap: Double? = nil) {
        if let rows { v[Key.pvRows] = rows == 0 ? nil : .text(String(rows)) }
        if let perTable { v[Key.pvPerTable] = .text(String(perTable)) }
        if let gap { v[Key.pvGap] = .text(String(format: "%.2f", min(2, max(0, (gap * 100).rounded() / 100)))) }
    }
    public static func pvPortrait(_ v: Values) -> Bool { v.text(Key.pvOrientation) != "l" }

    // MARK: posts

    /// Grid intersections "i,j" (x line i, y line j) with a post by default for this frame.
    public static func defaultPosts(_ f: RoofFrame, nx: Int, ny: Int, ridge: Ridge) -> Set<String> {
        // a = grid lines along the ridge, c = across it; nx / ny count grid lines
        let na = ridge == .h ? nx : ny, nc = ridge == .h ? ny : nx
        var out = Set<String>()
        func add(_ ia: Int, _ ic: Int) { out.insert(ridge == .h ? "\(ia),\(ic)" : "\(ic),\(ia)") }
        guard na >= 2, nc >= 2 else { return out }
        switch f {
        case .rafterTie, .eaveCeiling:
            for ia in 0..<na { for ic in Set([1, nc - 2]) where ic >= 0 && ic < nc { add(ia, ic) } }
        case .rafterTruss:
            for ia in 1..<max(1, na - 1) { for ic in 1..<max(1, nc - 1) { add(ia, ic) } }
        default:
            for ia in 1..<max(1, na - 1) { for ic in Set([1, nc - 2]) where ic >= 0 && ic < nc { add(ia, ic) } }
        }
        return out
    }
    /// Posts added (true) or removed (false) on the page, per frame type.
    public static func postEdits(_ v: Values) -> [String: [String: Bool]] {
        guard let d = v.text(Key.posts).data(using: .utf8),
              let o = try? JSONDecoder().decode([String: [String: Bool]].self, from: d) else { return [:] }
        return o
    }
    public static func posts(_ v: Values) -> Set<String> {
        let f = frame(v), nx = spans(v, .x).count + 1, ny = spans(v, .y).count + 1
        var s = defaultPosts(f, nx: nx, ny: ny, ridge: ridge(v))
        for (k, on) in postEdits(v)[f.rawValue] ?? [:] {
            let p = k.split(separator: ",").compactMap { Int($0) }
            guard p.count == 2, p[0] < nx, p[1] < ny else { continue }
            if on { s.insert(k) } else { s.remove(k) }
        }
        return s
    }
    /// Adds or removes the post at grid intersection (i, j) for the current frame type.
    public static func togglePost(_ v: inout Values, i: Int, j: Int) {
        let f = frame(v), k = "\(i),\(j)", on = posts(v).contains(k)
        var all = postEdits(v), mine = all[f.rawValue] ?? [:]
        let def = defaultPosts(f, nx: spans(v, .x).count + 1, ny: spans(v, .y).count + 1, ridge: ridge(v)).contains(k)
        if !on == def { mine[k] = nil } else { mine[k] = !on }
        all[f.rawValue] = mine.isEmpty ? nil : mine
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        if all.isEmpty { v[Key.posts] = nil }
        else if let d = try? enc.encode(all), let t = String(data: d, encoding: .utf8) { v[Key.posts] = .text(t) }
    }

    // MARK: skylights and keep-out zones (in `obst`)

    public static let skylightKind = "sky", keepOutKind = "keep"
    public struct Area: Hashable, Sendable {
        public var index: Int
        public var x, y, w, h: Double
        public var kind: String
        public var canCover: Bool
        public var label: String
        /// Height above the roof (m), typed; nil = the kind's default.
        public var height: Double? = nil
    }
    /// Every entry of `obst` with a usable rectangle (metres from the plan's top-left).
    public static func areas(_ v: Values) -> [Area] {
        v.obstacles(Key.obstacles).enumerated().compactMap { i, o in
            guard let x = NumberInput.value(o.x), let y = NumberInput.value(o.y), let w = NumberInput.value(o.w), let h = NumberInput.value(o.h),
                  w > 0, h > 0 else { return nil }
            return Area(index: i, x: x, y: y, w: w, h: h, kind: o.kind, canCover: o.canCover, label: o.label, height: NumberInput.value(o.height))
        }
    }
    /// Adds a skylight or keep-out zone; rounded to 0.1 m, at least 0.3 × 0.3 m. Returns false when too small.
    @discardableResult
    public static func addArea(_ v: inout Values, kind: String, x1: Double, y1: Double, x2: Double, y2: Double) -> Bool {
        let r = { (d: Double) in (d * 10).rounded() / 10 }
        let x = r(min(x1, x2)), y = r(min(y1, y2)), w = r(abs(x2 - x1)), h = r(abs(y2 - y1))
        guard w >= 0.3, h >= 0.3 else { return false }
        var list = v.obstacles(Key.obstacles)
        let label = kind == skylightKind ? "แผ่นใส" : kind == keepOutKind ? "เขตห้ามติด" : RoofObstacleKind(rawValue: kind)?.title ?? "สิ่งกีดขวาง"
        list.append(Obstacle(label: label, x: fmt(x), y: fmt(y), w: fmt(w), h: fmt(h), kind: kind))
        v[Key.obstacles] = .obstacles(list)
        return true
    }
    public static func removeArea(_ v: inout Values, index: Int) {
        var list = v.obstacles(Key.obstacles)
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        v[Key.obstacles] = list.isEmpty ? nil : .obstacles(list)
    }
    public static func toggleCover(_ v: inout Values, index: Int) {
        var list = v.obstacles(Key.obstacles)
        guard list.indices.contains(index) else { return }
        list[index].canCover.toggle()
        v[Key.obstacles] = .obstacles(list)
    }

    // MARK: members

    /// Row n (1…7) is always stored in `comp<n>`, "size @spacing"; only the name shown changes with the frame type.
    public static func member(_ v: Values, _ n: Int) -> String { v.text(Key.member(n)) }
    /// The size part of a stored member ("C-100x50x20x3.2 @1.00M" → "C-100x50x20x3.2").
    public static func memberSize(_ v: Values, _ n: Int) -> String { StructureSizes.split(member(v, n)).size }
    /// Picks a size and keeps the spacing (or the usual spacing for rows 1–2 when none is stored). "-" stores "-".
    public static func setMember(_ v: inout Values, _ n: Int, size: String) {
        let old = StructureSizes.split(member(v, n)).spacing
        let sp = size == "-" ? "" : old.isEmpty ? (StructureSizes.defaultSpacing(n) ?? "") : old
        let t = StructureSizes.join(size: size, spacing: sp)
        v[Key.member(n)] = t.isEmpty ? nil : .text(t)
    }
    public static func setSpacing(_ v: inout Values, _ n: Int, spacing: String) {
        let size = memberSize(v, n)
        guard !size.isEmpty, size != "-" else { return }
        v[Key.member(n)] = .text(StructureSizes.join(size: size, spacing: spacing))
    }
    /// A stored size the current frame type doesn't list (kept, the row is marked).
    public static func memberOffList(_ v: Values, _ n: Int) -> Bool {
        let s = memberSize(v, n)
        guard !s.isEmpty, let m = frame(v).members[safe: n - 1] else { return false }
        return !m.sizes.contains(s)
    }

    /// Profile glyph for a size: C, 2C, box, tube, wood, rc, T2, none or other.
    public static func profile(_ size: String) -> String {
        let s = size.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == "-" { return "none" }
        if s.hasPrefix("2C") { return "2C" }
        if s.hasPrefix("C-") || s.hasPrefix("C ") { return "C" }
        if s.hasPrefix("□") { return "box" }
        if s.hasPrefix("ท่อ") || s.hasPrefix("Ø") { return "tube" }
        if s.hasPrefix("ไม้") || s.hasPrefix("ไฟเบอร์") { return "wood" }
        if s.hasPrefix("ค.ส.ล") { return "rc" }
        if s.hasPrefix("T2") { return "T2" }
        return "other"
    }

    /// "ชุดมาตรฐาน · โครงถักเหล็ก 16 ม."
    public static func memberNote(_ v: Values) -> String {
        let f = frame(v), wood = v.choice(Key.structure) == "ไม้"
        let kind = f.isTruss ? "โครงถัก" : f == .rafterTie ? "โครงขื่อรัด" : f == .rafterTruss ? "โครงจันทันถัก" : "โครง"
        return "ชุดมาตรฐาน · \(kind)\(wood ? "ไม้" : "เหล็ก") \(fmt(span(v))) ม."
    }

    // MARK: roof shape and material

    /// A design option and the existing choice it is stored as (nil: "อื่นๆ" with the design name as the text).
    public struct Option: Hashable, Sendable {
        public let name: String, sub: String
        public let stored: String?
    }
    public static let shapes: [Option] = [
        Option(name: "ทรงจั่ว", sub: "Gable · ลาด 2 ด้าน", stored: "หลังคาทรงจั่ว"),
        Option(name: "ทรงปั้นหยา", sub: "Hip · ลาด 4 ด้าน", stored: "หลังคาทรงปั้นหยา"),
        Option(name: "ทรงเพิงหมาแหงน", sub: "Shed · ลาดด้านเดียว", stored: "หลังคาเพิงหมาแหงน"),
        Option(name: "ทรงฟันเลื่อย", sub: "Saw-tooth · โรงงาน", stored: nil),
        Option(name: "ทรงโค้ง", sub: "Arch / Curved", stored: "หลังคาทรงโค้ง"),
        Option(name: "หลังคาแบน / ดาดฟ้า", sub: "Flat · คอนกรีต", stored: "หลังคาคอนกรีต (ดาดฟ้า)"),
    ]
    public static let materials: [Option] = [
        Option(name: "เมทัลชีท", sub: "ลอนสแน็ปล็อก / ลอนทั่วไป", stored: "เมทัลชีท"),
        Option(name: "เมทัลชีทบุฉนวน", sub: "Sandwich / PU foam", stored: nil),
        Option(name: "กระเบื้องลอนคู่", sub: "ไฟเบอร์ซีเมนต์", stored: "กระเบื้องลอนคู่/เดี่ยว"),
        Option(name: "กระเบื้องคอนกรีต", sub: "ซีแพค / โมเนีย", stored: "กระเบื้องซีแพค"),
        Option(name: "แผ่นโปร่งแสง", sub: "ไฟเบอร์กลาส / โพลีคาร์บอเนต", stored: nil),
        Option(name: "คอนกรีต (ดาดฟ้า)", sub: "พื้น คสล.", stored: "คอนกรีตเสริมเหล็ก"),
    ]
    /// The design option the stored answer matches, if any.
    public static func option(_ v: Values, _ key: String, in list: [Option]) -> Option? {
        guard let c = v.choice(key) else { return nil }
        if c == "อื่นๆ" { return list.first { $0.stored == nil && $0.name == v.other(key) } }
        return list.first { $0.stored == c }
    }
    /// What the dropdown shows: the design name, else the stored choice or its other-text as typed.
    public static func shown(_ v: Values, _ key: String, in list: [Option]) -> String? {
        if let o = option(v, key, in: list) { return o.name }
        guard let c = v.choice(key) else { return nil }
        return c == "อื่นๆ" ? (v.other(key).isEmpty ? "อื่นๆ" : v.other(key)) : c
    }
    public static func choose(_ v: inout Values, _ key: String, _ o: Option) {
        v[key] = o.stored.map { .choice($0, other: "") } ?? .choice("อื่นๆ", other: o.name)
    }
    public static func chooseOther(_ v: inout Values, _ key: String, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        v[key] = .choice("อื่นๆ", other: t)
    }

    // MARK: photos

    /// The six recommended angles. มุมสูง is `aerialPhoto`; ด้านหน้า / ด้านข้าง / แผ่นมุง are `generalPhotos`;
    /// ใต้หลังคา โครง / จุดต่อ are `structPhotos`. `roofShots` keeps which angle each list photo is, so deleting one
    /// doesn't move the others to another slot.
    public enum Shot: Int, CaseIterable, Sendable {
        case aerial, front, side, frame, joint, sheet
        public var name: String { ["มุมสูง ภาพรวม", "ด้านหน้า", "ด้านข้าง", "ใต้หลังคา โครง", "ใต้หลังคา จุดต่อ", "แผ่นมุง ระยะใกล้"][rawValue] }
        var tag: String { ["a", "f", "s", "r", "j", "c"][rawValue] }
        var field: String { self == .aerial ? Key.aerial : self == .frame || self == .joint ? Key.structPhotos : Key.general }
    }
    static let generalOrder: [Shot] = [.front, .side, .sheet], structOrder: [Shot] = [.frame, .joint]

    /// Which angle each `generalPhotos` / `structPhotos` item is; nil for extra old photos.
    static func tags(_ v: Values) -> (general: [Shot?], structure: [Shot?]) {
        let g = v.photos(Key.general).count, s = v.photos(Key.structPhotos).count
        let parts = v.text(Key.shots).split(separator: "|", omittingEmptySubsequences: false).map { $0.split(separator: ",").map(String.init) }
        func resolve(_ stored: [String]?, count: Int, order: [Shot]) -> [Shot?] {
            if let stored, stored.count == count {
                let t = stored.map { tag in order.first { $0.tag == tag } }
                // a slot named twice keeps the first photo only
                var seen = Set<Shot>()
                return t.map { s in guard let s, !seen.contains(s) else { return nil }; seen.insert(s); return s }
            }
            return (0..<count).map { order[safe: $0] }
        }
        return (resolve(parts[safe: 0], count: g, order: generalOrder), resolve(parts[safe: 1], count: s, order: structOrder))
    }
    static func writeTags(_ v: inout Values, general: [Shot?], structure: [Shot?]) {
        let t = general.map { $0?.tag ?? "x" }.joined(separator: ",") + "|" + structure.map { $0?.tag ?? "x" }.joined(separator: ",")
        v[Key.shots] = t == "|" ? nil : .text(t)
    }

    public static func photo(_ v: Values, _ s: Shot) -> Photo? {
        if s == .aerial { return v.photo(Key.aerial) }
        let t = tags(v)
        let (list, tg) = s.field == Key.general ? (v.photos(Key.general), t.general) : (v.photos(Key.structPhotos), t.structure)
        return tg.firstIndex(of: s).flatMap { list[safe: $0] }
    }
    /// Old structure photos beyond the two angles (kept; the page shows "+n").
    public static func extraStructPhotos(_ v: Values) -> Int { tags(v).structure.filter { $0 == nil }.count }

    public static func setPhoto(_ v: inout Values, _ s: Shot, _ p: Photo?) {
        if s == .aerial { v[Key.aerial] = p.map { .photo($0) }; return }
        var t = tags(v), list = v.photos(s.field)
        var tg = s.field == Key.general ? t.general : t.structure
        if let i = tg.firstIndex(of: s) {
            if let p { list[i] = p } else { list.remove(at: i); tg.remove(at: i) }
        } else if let p {
            list.append(p); tg.append(s)
        }
        v[s.field] = list.isEmpty ? nil : .photos(list)
        if s.field == Key.general { t.general = tg } else { t.structure = tg }
        writeTags(&v, general: t.general, structure: t.structure)
    }
    public static func missingShots(_ v: Values) -> [Shot] { Shot.allCases.filter { photo(v, $0) == nil } }

    // MARK: gaps (bottom bar)

    /// Something the page still needs: a required field (`key` is its id, "spans" for both span lists) or a photo
    /// angle (`key` "shot-<n>").
    public struct Gap: Hashable, Sendable {
        public let key: String, title: String
    }
    /// The section's required fields still empty (the same as `Progress`, photos aside), then the photo angles.
    public static func gaps(_ v: Values) -> [Gap] {
        let photoFields: Set = [Key.aerial, Key.general, Key.structPhotos]
        var out: [Gap] = []
        for f in Schema.spec(.roof).groups.flatMap({ $0.missing(v) }) where !photoFields.contains(f.id) {
            let g: Gap
            switch f.id {
            case Key.spansX, Key.spansY: g = Gap(key: "spans", title: "ระยะช่วงเสา")
            case Key.shape: g = Gap(key: f.id, title: "รูปแบบหลังคา")
            case Key.material: g = Gap(key: f.id, title: "วัสดุมุง")
            case Key.structure: g = Gap(key: f.id, title: "วัสดุโครงสร้าง")
            case Key.panels: g = Gap(key: f.id, title: "จำนวนแผง")
            default:
                if f.id.hasPrefix("comp"), let n = Int(f.id.dropFirst(4)) { g = Gap(key: f.id, title: "ขนาดชิ้นส่วน \(n)") }
                else { g = Gap(key: f.id, title: f.label) }
            }
            if !out.contains(g) { out.append(g) }
        }
        return out + missingShots(v).map { Gap(key: "shot-\($0.rawValue)", title: $0.name) }
    }
    /// The bottom bar's line: the missing fields and angles, or ครบช่องบังคับแล้ว.
    public static func statusLine(_ v: Values) -> String {
        let g = gaps(v)
        if g.isEmpty { return "ครบช่องบังคับแล้ว" }
        if g.allSatisfy({ $0.key.hasPrefix("shot-") }) { return "ยังขาดภาพหลังคา: " + g.map(\.title).joined(separator: " · ") }
        return "ยังขาด: " + g.map { $0.key.hasPrefix("shot-") ? "ภาพ" + $0.title : $0.title }.joined(separator: " · ")
    }
}

/// ชนิดโครงหลังคา, stored in `frameType`.
public enum RoofFrame: String, CaseIterable, Sendable {
    case normal = "n", pratt = "p", warren = "w", rafterTie = "c", rafterTruss = "r", eaveCeiling = "k"

    /// The segmented control's label, in the design's order (ปกติ first).
    public var label: String { ["n": "ปกติ", "p": "ถัก Pratt", "w": "ถัก Warren", "c": "ขื่อรัด", "r": "จันทันถัก", "k": "ชายคาฝ้า"][rawValue]! }
    public var title: String {
        ["n": "โครงปกติ", "p": "โครงถัก Pratt", "w": "โครงถัก Warren", "c": "โครงจันทัน-ขื่อรัด", "r": "โครงจันทันถัก + T2",
         "k": "โครงจันทันพาดเสา · ชายคาฝ้า"][rawValue]!
    }
    public static let ordered: [RoofFrame] = [.normal, .pratt, .warren, .rafterTie, .rafterTruss, .eaveCeiling]
    /// Pratt, Warren and the normal frame are trusses with a bottom chord.
    public var isTruss: Bool { self == .normal || self == .pratt || self == .warren }
    /// Rafters on eaves beams (ขื่อรัด, ชายคาฝ้า): no truss panels, the plan draws rafters @1.00.
    public var isRafter: Bool { self == .rafterTie || self == .eaveCeiling }
    public var slope: Double { self == .rafterTie ? 30 : 15 }
    /// Truss depth at the heel (m).
    public var heel: Double { isRafter ? 0 : 0.5 }
    /// Eave overhang (m) until measured: the boxed eave of ชายคาฝ้า is deeper.
    public var overhang: Double { self == .eaveCeiling ? 1.2 : 0.7 }
    /// Thumbnail family in `icons/members`.
    public var iconFamily: String {
        switch self {
        case .rafterTie: return "rafter-tie"
        case .rafterTruss: return "rafter-truss-T2"
        case .eaveCeiling: return "eave-ceiling"
        default: return "truss-pratt-normal-warren"
        }
    }

    public struct Member: Sendable {
        public let name: String
        /// "-" (ไม่มี / ไม่ใช้) first, then the sizes.
        public let sizes: [String]
        public let defaultSize: String
    }

    /// The seven rows (`comp1`…`comp7`) as the design names and sizes them for this frame type.
    public var members: [Member] {
        func m(_ n: String, _ s: [String], _ d: Int) -> Member { Member(name: n, sizes: ["-"] + s, defaultSize: (["-"] + s)[d + 1]) }
        let chord = ["2C-100x50x20x3.2", "2C-125x50x20x3.2", "2C-150x50x20x3.2", "2C-150x65x20x3.2"]
        let web = ["C-75x45x15x2.3", "C-75x45x15x3.2", "C-100x50x20x2.3", "C-100x50x20x3.2"]
        let post = ["□-75x75x3.2", "□-100x100x3.2", "□-100x100x4.0", "□-125x125x4.5"]
        var r = [m("แป", ["C-75x45x15x2.3", "C-100x50x20x2.3", "C-100x50x20x3.2", "C-125x50x20x3.2", "C-150x50x20x3.2"], 2),
                 m("คอร์ดบน", chord, 2), m("คอร์ดล่าง", chord, 2), m("ตัวตั้ง", web, 0), m("ตัวทแยง", web, 0),
                 m("เชิงชาย", ["ไม้ 1\"x6\"", "ไม้ 1\"x8\"", "ไฟเบอร์ซีเมนต์ 1\"x8\"", "C-100x50x20x2.3"], 1),
                 m("เสากลาง", post, 1)]
        let rafter = ["C-125x50x20x3.2", "C-150x50x20x3.2", "2C-125x50x20x3.2", "2C-150x50x20x3.2"]
        let tie = ["C-100x50x20x2.3", "C-100x50x20x3.2", "C-125x50x20x3.2"]
        switch self {
        case .rafterTie:
            r[1] = m("จันทัน", rafter, 1)
            r[2] = m("ขื่อรัด", tie, 1)
            r[3] = m("อเส", ["C-100x50x20x3.2", "C-125x50x20x3.2", "ค.ส.ล. (เดิม)"], 2)
            r[4] = m("ตัวค้ำ", ["C-75x45x15x2.3", "C-75x45x15x3.2"], -1)
            r[6] = m("เสากลาง", post, -1)
        case .eaveCeiling:
            r[1] = m("จันทัน", rafter, 1)
            r[2] = m("ขื่อรัด", tie, 1)
            r[3] = m("คานหัวเสา", ["ค.ส.ล. (เดิม)", "C-125x50x20x3.2", "2C-150x50x20x3.2"], 0)
            r[4] = m("โครงฝ้า", ["C-75x45x15x2.3", "ไม้ 1½\"x3\"", "โครงคร่าวเหล็กชุบสังกะสี"], 0)
            r[6] = m("เสา", ["ค.ส.ล. (เดิม)", "□-100x100x3.2", "□-125x125x4.5"], 0)
        case .rafterTruss:
            let tube = ["ท่อกลม Ø1\" หนา 1.6", "ท่อกลม Ø1¼\" หนา 2.0", "ท่อกลม Ø1½\" หนา 2.3"]
            r[1] = m("คอร์ดบน", tube, 0); r[2] = m("คอร์ดล่าง", tube, 0); r[3] = m("ตัวทแยง", tube, 0)
            r[4] = m("T2 รับจันทัน", ["T2 ลึก 1.00 ท่อ Ø1\"", "T2 ลึก 0.80 ท่อ Ø1\"", "2C-150x65x20x3.2"], 0)
            r[6] = m("เสา", ["□-100x100x3.2", "□-125x125x4.5", "ค.ส.ล. (เดิม)"], 0)
        default: break
        }
        return r
    }
}

/// หลังคามาตรฐาน: a roof the team draws often (spans, frame type, purlin spacing). The PWA standards ship with the app
/// (the design's `STD`); a team member can save the current roof as a new one (`Roof.Standard` is Codable for that).
public extension Roof {
    struct Standard: Codable, Hashable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var xs: [Double], ys: [Double]
        public var frame: String
        /// Purlin spacing saved with the roof; nil for the PWA standards (any spacing matches).
        public var purlin: Double?
        /// Saved by, scope (ทั้งทีม / เฉพาะฉัน) and date, for the team's own roofs.
        public var by: String?, scope: String?, date: String?
        public init(id: String, name: String, xs: [Double], ys: [Double], frame: RoofFrame, purlin: Double? = nil,
                    by: String? = nil, scope: String? = nil, date: String? = nil) {
            self.id = id; self.name = name; self.xs = xs; self.ys = ys; self.frame = frame.rawValue; self.purlin = purlin
            self.by = by; self.scope = scope; self.date = date
        }
        public var roofFrame: RoofFrame { RoofFrame(rawValue: frame) ?? .pratt }
        var isTeam: Bool { by != nil }

        /// "โรงกรอง 19 × 16 ม." (a trailing "(…)" stays at the end: "โรงสูบน้ำ 14 × 10 ม. (พิจิตร)").
        public func title(_ sep: String = " × ") -> String {
            let size = fmt(xs.reduce(0, +)) + sep + fmt(ys.reduce(0, +)) + (sep == "×" ? "" : " ม.")
            if let r = name.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
                return String(name[..<r.lowerBound]) + " " + size + " " + name[r].trimmingCharacters(in: .whitespaces)
            }
            return name + " " + size
        }
        /// "ถัก Pratt · ช่วงเสา 4 ม. · 7 × 6 กริด", or for a saved roof "ขื่อรัด · แป @0.90 · โดย วิชัย · 28 ก.ย. · ทั้งทีม".
        public var subtitle: String {
            if let by {
                return [roofFrame.label, "แป @" + String(format: "%.2f", purlin ?? 1), "โดย " + by, date ?? "", scope ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
            }
            return roofFrame.label + " · ช่วงเสา " + fmt(xs.max() ?? 0) + " ม. · \(xs.count + 1) × \(ys.count + 1) กริด"
        }
    }

    /// แบบมาตรฐาน กปภ. (the design's `STD`).
    static let standards: [Standard] = [
        Standard(id: "filter", name: "โรงกรอง", xs: [1.5, 4, 4, 4, 4, 1.5], ys: [1.5, 4.5, 4, 4.5, 1.5], frame: .pratt),
        Standard(id: "pump", name: "อาคารสูบน้ำ", xs: [4, 4, 4], ys: [1, 3, 3, 1], frame: .rafterTie),
        Standard(id: "office", name: "อาคารสำนักงาน", xs: [4, 4, 4, 4], ys: [1.2, 3.8, 3.8, 1.2], frame: .eaveCeiling),
        Standard(id: "chem", name: "อาคารเก็บสารเคมี", xs: [6, 6, 6, 6], ys: [1, 5, 5, 1], frame: .warren),
        Standard(id: "park", name: "โรงจอดรถ", xs: [5, 5, 5, 5, 5, 5], ys: [1, 9, 9, 1], frame: .rafterTruss),
    ]

    /// The standard (or saved roof) the roof's spans, frame and purlin spacing match, if any.
    static func matchingStandard(_ v: Values, in list: [Standard]) -> Standard? {
        let xs = spans(v, .x), ys = spans(v, .y), f = frame(v), pp = purlinSpacing(v)
        func same(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 0.001 } }
        return list.first { $0.roofFrame == f && same($0.xs, xs) && same($0.ys, ys) && ($0.purlin.map { abs($0 - pp) < 0.001 } ?? true) }
    }
    /// The dropdown's text: "โรงกรอง 19×16", else "กำหนดเอง 19×16 ม.".
    static func standardLabel(_ v: Values, in list: [Standard]) -> String {
        if let s = matchingStandard(v, in: list) { return s.title("×") }
        return "กำหนดเอง " + fmt(spans(v, .x).reduce(0, +)) + "×" + fmt(spans(v, .y).reduce(0, +)) + " ม."
    }
    /// Fills the spans, frame type and purlin spacing; the frame's edited posts and the truss panels go back to their
    /// defaults, and the roof shape becomes ทรงจั่ว (every standard is a gable).
    static func applyStandard(_ v: inout Values, _ s: Standard) {
        setSpans(&v, .x, s.xs); setSpans(&v, .y, s.ys)
        setFrame(&v, s.roofFrame)
        if let p = s.purlin { setPurlinSpacing(&v, p) }
        var edits = postEdits(v); edits[s.frame] = nil
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        if edits.isEmpty { v[Key.posts] = nil }
        else if let d = try? enc.encode(edits), let t = String(data: d, encoding: .utf8) { v[Key.posts] = .text(t) }
        setBays(&v, nil)
        if let gable = shapes.first?.stored { v[Key.shape] = .choice(gable, other: "") }
        v[Key.standard] = .text(s.id)
    }
    /// The current roof as a new saved standard.
    static func standard(from v: Values, id: String, name: String, by: String, scope: String, date: String) -> Standard {
        Standard(id: id, name: name, xs: spans(v, .x), ys: spans(v, .y), frame: frame(v), purlin: purlinSpacing(v), by: by, scope: scope, date: date)
    }
}
