import Foundation

/// D1 "ถังน้ำใส" wide page, sub-step 1 "ขนาดถัง" (docs/ui/survey-d1-size): size presets, height and exposed part, the
/// position, roof surface, soil cover and the tank's azimuth. Field ids, labels and Excel cells are unchanged; the page's
/// own answers (`tankExposed`, `tankAzimuth`, `tankAzimuthAt`, `tankAzimuthSrc`, `tankAzimuthAcc`) are optional and
/// hidden, so the section's completion counts as before.
public enum Tank {
    public enum Key {
        public static let type = "tankType", pos = "tankPos", height = "tankHeight", surface = "surface", soil = "soilDepth"
        public static let exposed = "tankExposed", azimuth = "tankAzimuth", azimuthAt = "tankAzimuthAt"
        public static let azimuthSrc = "tankAzimuthSrc", azimuthAcc = "tankAzimuthAcc"
        /// The vents' height above the roof (docs/specs/tank-mounting-layout.md §2), one value per tank.
        public static let ventHeight = "ventHeight"
    }

    // MARK: vent height

    /// The vents' height above the roof as measured, nil when not measured (the layout then assumes 1.00 m).
    public static func ventHeight(_ v: Values) -> Double? { v.number(Key.ventHeight) }
    public static func setVentHeight(_ v: inout Values, _ h: Double?) { v[Key.ventHeight] = h.map { num(min(5, max(0, $0))) } }

    // MARK: size presets

    public struct Preset: Hashable, Sendable {
        public let name: String
        public let sub: String
        public let nx: Int, ny: Int
        public let span: Double
        public var spansX: [Double] { Array(repeating: span, count: nx) }
        public var spansY: [Double] { Array(repeating: span, count: ny) }
    }
    public static let presets = [
        Preset(name: "40 × 40 ม.", sub: "กปภ. มาตรฐาน", nx: 10, ny: 10, span: 4),
        Preset(name: "64 × 40 ม.", sub: "กปภ. ขนาดใหญ่", nx: 16, ny: 10, span: 4),
        Preset(name: "30 × 30 ม.", sub: "กปภ. ขนาดกลาง", nx: 6, ny: 6, span: 5),
        Preset(name: "20 × 20 ม.", sub: "สถานีขนาดเล็ก", nx: 5, ny: 5, span: 4),
    ]

    /// Writes the preset's spans expanded ("4,4,4,…"): `parseSpans` has no "n@d" form.
    public static func apply(_ v: inout Values, _ p: Preset) {
        Roof.setSpans(&v, .x, p.spansX)
        Roof.setSpans(&v, .y, p.spansY)
    }
    public static func spans(_ v: Values) -> (x: [Double], y: [Double]) { (parseSpans(v.text(Roof.Key.spansX)), parseSpans(v.text(Roof.Key.spansY))) }
    /// The preset whose spans equal the stored ones exactly.
    public static func preset(_ v: Values) -> Preset? {
        let s = spans(v)
        return presets.first { $0.spansX == s.x && $0.spansY == s.y }
    }
    /// The size menu's label: a preset, "<sumX> × <sumY> ม." / "กำหนดเอง", or nil (placeholder) without spans.
    public static func sizeLabel(_ v: Values) -> (name: String, sub: String)? {
        if let p = preset(v) { return (p.name, p.sub) }
        let s = spans(v)
        guard !s.x.isEmpty, !s.y.isEmpty else { return nil }
        return ("\(fmt(s.x.reduce(0, +))) × \(fmt(s.y.reduce(0, +))) ม.", "กำหนดเอง")
    }
    public static func hasSize(_ v: Values) -> Bool { sizeLabel(v) != nil }

    // MARK: height, position and exposed part

    public static let positions = Schema.tankPositions
    public static let above = "บนดิน", buried = "ฝังดิน", partly = "กึ่งฝัง"
    public static let minHeight = 1.0
    /// The exposed part offered the first time the tank is partly buried.
    public static let defaultExposed = 1.2

    static func r2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
    static func num(_ x: Double) -> FieldValue { .text(fmt(r2(x))) }

    public static func height(_ v: Values) -> Double? { v.number(Key.height) }
    public static func position(_ v: Values) -> String? { v.choice(Key.pos) }
    /// The exposed part as stored; on/under ground it follows the height / 0.
    public static func exposed(_ v: Values) -> Double? {
        switch position(v) {
        case above?: return height(v)
        case buried?: return 0
        default: return v.number(Key.exposed)
        }
    }
    /// The exposed part can be typed only when the tank is partly buried.
    public static func exposedEditable(_ v: Values) -> Bool { position(v) == partly }

    public static func setHeight(_ v: inout Values, _ h: Double?) {
        v[Key.height] = h.map { num(max(minHeight, $0)) }
        syncExposed(&v)
    }
    public static func setPosition(_ v: inout Values, _ p: String) {
        let was = position(v)
        v[Key.pos] = .choice(p, other: "")
        // the first time partly buried, or coming back from on / under ground (which wrote the height / 0)
        if p == partly && (v.number(Key.exposed) == nil || (was != nil && was != partly)) { v[Key.exposed] = num(defaultExposed) }
        syncExposed(&v)
    }
    public static func setExposed(_ v: inout Values, _ e: Double?) {
        guard exposedEditable(v) else { syncExposed(&v); return }
        v[Key.exposed] = e.map { num(max(0, $0)) }
        syncExposed(&v)
    }
    /// Keeps `tankExposed` in step with the position and clamped to 0…height.
    public static func syncExposed(_ v: inout Values) {
        switch position(v) {
        case above?: v[Key.exposed] = height(v).map(num)
        case buried?: v[Key.exposed] = num(0)
        case partly?:
            if let e = v.number(Key.exposed) { v[Key.exposed] = num(min(max(0, e), height(v) ?? .infinity)) }
        default: break
        }
    }
    public static func setSoil(_ v: inout Values, _ d: Double?) { v[Key.soil] = d.map { num(max(0, $0)) } }

    // MARK: type and surface

    /// ค.ส.ล. / เหล็ก / FRP, the other text, or nil.
    public static func typeName(_ v: Values) -> String? {
        guard let t = v.choice(Key.type) else { return nil }
        let s = t == "อื่นๆ" ? v.other(Key.type).trimmingCharacters(in: .whitespaces) : t
        return s.isEmpty ? nil : s
    }
    public static let surfaces = ["คอนกรีต", "คอนกรีตเคลือบกันซึม", "ดินปลูกหญ้า", "หินกรวด"]

    // MARK: azimuth

    public static let directions = ["เหนือ", "ตะวันออกเฉียงเหนือ", "ตะวันออก", "ตะวันออกเฉียงใต้", "ใต้", "ตะวันตกเฉียงใต้", "ตะวันตก", "ตะวันตกเฉียงเหนือ"]
    public enum Source: String, Sendable { case compass, manual }

    /// 0…359, or nil when not set.
    public static func azimuth(_ v: Values) -> Int? { v.number(Key.azimuth).map { normalize(Int($0.rounded())) } }
    public static func normalize(_ a: Int) -> Int { ((a % 360) + 360) % 360 }
    /// The top wall (line A) faces the heading along wall A minus 90°.
    public static func azimuth(wall: Double) -> Int { normalize(Int(wall.rounded()) - 90) }
    public static func directionName(_ az: Int) -> String { directions[Int((Double(normalize(az)) / 45).rounded()) % 8] }
    /// "12° เหนือ"
    public static func azimuthText(_ az: Int) -> String { "\(az)° " + directionName(az) }

    public static func setAzimuth(_ v: inout Values, _ az: Int?, source: Source, at: Date = Date(), accuracy: Double? = nil) {
        guard let az else {
            for k in [Key.azimuth, Key.azimuthAt, Key.azimuthSrc, Key.azimuthAcc] { v[k] = nil }
            return
        }
        v[Key.azimuth] = .text(String(normalize(az)))
        v[Key.azimuthSrc] = .text(source.rawValue)
        v[Key.azimuthAt] = source == .compass ? .text(ISO8601DateFormatter().string(from: at)) : nil
        v[Key.azimuthAcc] = source == .compass ? accuracy.map { .text(String(Int($0.rounded()))) } : nil
    }
    public static func source(_ v: Values) -> Source? { Source(rawValue: v.text(Key.azimuthSrc)) }
    public static func measuredAt(_ v: Values) -> Date? { ISO8601DateFormatter().date(from: v.text(Key.azimuthAt)) }

    /// The line under the field: how the value was found; nil when empty.
    /// iPhone: `device` "iPhone" and the shorter tail "แปลนหมุนตามค่านี้".
    public static func sourceLine(_ v: Values, timeZone: TimeZone = .current, device: String = "iPad",
                                  tail: String = "แปลนและลูกศร N หมุนตามค่านี้") -> String? {
        guard azimuth(v) != nil else { return nil }
        guard source(v) == .compass else { return "ป้อนเอง · " + tail }
        var parts = ["วัดด้วยเข็มทิศ " + device]
        if let a = v.number(Key.azimuthAcc) { parts.append("±\(Int(a.rounded()))°") }
        if let d = measuredAt(v) {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
            let c = cal.dateComponents([.day, .month, .hour, .minute], from: d)
            parts.append(String(format: "%d/%d %02d:%02d", c.day ?? 0, c.month ?? 0, c.hour ?? 0, c.minute ?? 0))
        }
        return (parts + [tail]).joined(separator: " · ")
    }

    // MARK: sub-steps and status

    /// Sub-step 1 is done with the spans, type, height, position and surface set; the azimuth is optional.
    public static func sizeDone(_ v: Values) -> Bool {
        let s = spans(v)
        return !s.x.isEmpty && !s.y.isEmpty && typeName(v) != nil && height(v) != nil && position(v) != nil
            && !v.text(Key.surface).trimmingCharacters(in: .whitespaces).isEmpty
    }
    /// The required photos of the ภาพถ่าย group: filled / total.
    public static func photoCompletion(_ v: Values) -> Completion {
        Schema.spec(.tank).groups.first { $0.title == "ภาพถ่าย" }?.completion(v) ?? Completion()
    }
    /// The bottom bar's line: the required photos still missing, or nil to keep the bar's own completion text.
    public static func statusLine(_ v: Values) -> String? {
        let c = photoCompletion(v), k = c.total - c.filled
        return k > 0 ? "ยังขาดภาพบังคับ \(k) ภาพ" : nil
    }
}

/// D1 "วัดด้วย iPad": locks the wall heading when every reading of the last 2 s is within ±2° of their circular mean.
public struct HeadingLock: Sendable {
    public var window: TimeInterval = 2
    public var tolerance: Double = 2
    public private(set) var locked: Double?
    var samples: [(t: Date, h: Double)] = []
    public init() {}

    /// Adds a reading; returns the locked heading once stable. A locked value stays until `reset`.
    @discardableResult public mutating func add(_ h: Double, at t: Date = Date()) -> Double? {
        guard locked == nil else { return locked }
        samples.append((t, h))
        samples.removeAll { t.timeIntervalSince($0.t) > window + 0.2 }
        guard let first = samples.first, t.timeIntervalSince(first.t) >= window else { return nil }
        let m = Self.mean(samples.map(\.h))
        if samples.allSatisfy({ Self.diff($0.h, m) <= tolerance }) { locked = m }
        return locked
    }
    public mutating func reset() { locked = nil; samples.removeAll() }

    /// Circular mean in degrees, 0..<360 (359° and 1° average to 0°, not 180°).
    public static func mean(_ a: [Double]) -> Double {
        let s = a.reduce(0) { $0 + sin($1 * .pi / 180) }, c = a.reduce(0) { $0 + cos($1 * .pi / 180) }
        let m = (atan2(s, c) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        // a hair below 0 rounds to 360 when shifted; keep it in 0..<360
        return m >= 360 - 1e-9 ? 0 : m
    }
    /// Smallest angle between two headings, 0…180.
    public static func diff(_ a: Double, _ b: Double) -> Double { abs((a - b + 540).truncatingRemainder(dividingBy: 360) - 180) }
    /// Accuracy known (≥ 0) and within ±10°; otherwise บันทึกมุม stays disabled.
    public static func accuracyOK(_ a: Double?) -> Bool { a.map { $0 >= 0 && $0 <= 10 } ?? false }
}
