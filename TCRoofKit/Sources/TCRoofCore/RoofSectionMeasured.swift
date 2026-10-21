import Foundation

/// The roof framing section of C2 หลังคาอาคาร and C3 บ้าน (docs/specs/auto-drawing.md §4.4), drawn from the measured
/// sizes and heights rather than a chosen frame type: a rafter frame (rafter, tie beam, king post and struts) on a
/// gable or hip, a shed, a flat slab or a curved roof, with the purlins, columns, ground, dimensions, the members
/// entered and the assumed values. C1 has its own section (`RoofSection`).
public enum MeasuredRoofSection {
    public enum Shape: Sendable, Equatable { case gable, hip, shed, flat, curved }

    public struct Input: Sendable, Equatable {
        public var title: String
        public var shape: Shape
        /// Across the ridge (m).
        public var span: Double
        /// Ground to the tie beam at the column (m); nil when not measured.
        public var eave: Double?
        /// Tie beam to the roof at the ridge (m); 0 for a flat roof.
        public var rise: Double
        /// Horizontal, from the column to the rafter's tip (m).
        public var overhang: Double
        /// Along the slope (m).
        public var purlinSpacing: Double
        /// The members as entered: name and size.
        public var members: [Member]
        public var assumed: [String] = []
        public var warnings: [String] = []

        /// The horizontal run of one slope.
        public var run: Double { shape == .shed ? span : span / 2 }
        /// Degrees.
        public var pitch: Double { atan2(rise, run) * 180 / .pi }
        public var slopeLength: Double { hypot(run, rise) }
    }
    public struct Member: Sendable, Equatable {
        public let name: String, size: String
    }

    /// The drawing's input, or why it can't be drawn. Only C2 (`roofForm`) and C3 (`house`) have one.
    public static func input(_ m: SurveyModule) -> (input: Input?, missing: [String]) {
        switch m.type {
        case .house: return house(m.values)
        case .roofForm: return roofForm(m.values)
        default: return (nil, [])
        }
    }

    /// The section's `Sketch`, or why it can't be drawn.
    public static func draw(_ m: SurveyModule, width: Double = 690) -> (sketch: Sketch?, missing: [String]) {
        let r = input(m)
        return (r.input.map { sketch($0, width: width) }, r.missing)
    }

    /// The field ids C2 adds to its group "อาคาร" (optional, so completion is unchanged).
    public enum Key {
        public static let eaveHeight = "eaveHeight", ridgeHeight = "ridgeHeight"
    }

    // MARK: input

    static func shape(_ v: Values) -> Shape {
        switch v.choice("roofShape") {
        case "หลังคาทรงปั้นหยา"?: return .hip
        case "หลังคาเพิงหมาแหงน"?: return .shed
        case "หลังคาคอนกรีต (ดาดฟ้า)"?: return .flat
        case "หลังคาทรงโค้ง"?: return .curved
        default: return .gable
        }
    }
    static func cm(_ v: Values, _ id: String) -> Double? { v.number(id).flatMap { $0 > 0 ? $0 / 100 : nil } }

    /// Applies the pitch checks: ridge ≤ eave, pitch outside 3–45°, over 60° refused.
    static func checked(_ i: Input) -> (input: Input?, missing: [String]) {
        var i = i
        guard i.span > 0, i.span.isFinite, i.rise.isFinite, i.rise >= 0 else { return (nil, ["ความกว้างอาคาร"]) }
        if i.rise < 0.05 && i.shape != .flat { i.shape = .flat; i.rise = 0; i.warnings.append("ความสูงสันเท่าชายคา วาดเป็นหลังคาแบน") }
        if i.shape != .flat {
            guard i.pitch <= 60 else { return (nil, [String(format: "ความสูงที่ให้มุมไม่เกิน 60° (ได้ %.1f°)", i.pitch)]) }
            if i.pitch < 3 || i.pitch > 45 { i.warnings.append(String(format: "ตรวจความสูงอีกครั้ง (มุมประมาณ %.1f°)", i.pitch)) }
        } else { i.rise = 0 }
        return (i, [])
    }

    /// C3: the width (ซม.) across the ridge, i1 ground → ridge, i2 ground → the eave's tip (ซม.), h the rafter's tip
    /// to the column, c the purlin spacing; `roofAngle` only when the heights are missing or disagree by > 10 %.
    static func house(_ v: Values) -> (input: Input?, missing: [String]) {
        guard let B = cm(v, "buildingWidth") else { return (nil, ["ความกว้างอาคาร (ข้อ 1)"]) }
        let sh = shape(v), o = cm(v, "measH") ?? 0
        let i1 = cm(v, "measI1"), i2 = cm(v, "measI2"), angle = v.number("roofAngle").flatMap { $0 > 0 && $0 < 90 ? $0 : nil }
        var assumed: [String] = [], warnings: [String] = []
        let run = sh == .shed ? B : B / 2
        var theta: Double?   // radians
        if let i1, let i2 {
            if i1 > i2 {
                theta = atan((i1 - i2) / (run + o))
                if let angle, let t = theta, abs(t * 180 / .pi - angle) > 0.1 * angle {
                    warnings.append(String(format: "มุมจากความสูง %.1f° ต่างจากข้อ 12 (%@°) ใช้ค่าจากความสูง", t * 180 / .pi, fmt(angle)))
                }
            } else if sh != .flat {
                warnings.append("ความสูงสันต้องมากกว่าชายคา")
            }
        }
        if theta == nil, let angle, sh != .flat {
            theta = angle * .pi / 180
            assumed.append("มุมเอียงจากข้อ 12 (" + fmt(angle) + "°)")
        }
        if theta == nil && sh != .flat { return (nil, ["ความสูง i1 / i2 (ข้อ 10–11) หรือมุมเอียง (ข้อ 12)"]) }
        let t = theta ?? 0
        let eave = i2.map { $0 + o * tan(t) }
        if eave == nil { assumed.append("ไม่ทราบความสูงชายคา") }
        let s = cm(v, "measC")
        if s == nil && sh != .flat { assumed.append("ระยะแป 1.00 ม.") }
        var members: [Member] = []
        let steel = v.choice("structMaterial") == "โครงสร้างเหล็ก"
        for (name, wood, steelKey) in [("แป", "woodPurlin", "steelPurlin"), ("จันทัน", "woodRafter", "steelRafter")] {
            let size: String
            if steel {
                let dims = ["F", "G", "H"].compactMap { v.number(steelKey + $0).map { fmt($0) } }
                let type = v.text(steelKey + "Type").trimmingCharacters(in: .whitespaces)
                size = dims.isEmpty ? "" : (type.isEmpty ? "" : type + " ") + dims.joined(separator: "x") + " ซม."
            } else {
                let dims = ["F", "G"].compactMap { v.number(wood + $0).map { fmt($0) } }
                size = dims.isEmpty ? "" : "ไม้ " + dims.joined(separator: "x") + " ซม."
            }
            let at = name == "แป" ? v.number("measC") : v.number("measA")
            members.append(Member(name: name, size: size.isEmpty ? "" : size + (at.map { " @" + fmt($0) + " ซม." } ?? "")))
        }
        return checked(Input(title: "บ้าน / อาคาร", shape: sh, span: B, eave: eave, rise: run * tan(t), overhang: o,
                             purlinSpacing: s.map { min(3, max(0.2, $0)) } ?? 1.0, members: members, assumed: assumed, warnings: warnings))
    }

    /// C2: the width (ซม.) across the ridge, the eave and ridge heights (ม., the two optional fields of group อาคาร), and
    /// the purlin spacing `space1` (ซม.).
    static func roofForm(_ v: Values) -> (input: Input?, missing: [String]) {
        guard let B = cm(v, "buildingWidth") else { return (nil, ["ความกว้างอาคาร"]) }
        let sh = shape(v), E = v.number(Key.eaveHeight).flatMap { $0 > 0 ? $0 : nil }, R = v.number(Key.ridgeHeight)
        var assumed: [String] = [], warnings: [String] = []
        var rise = 0.0
        if sh != .flat {
            guard let E, let R else {
                return (nil, [E == nil ? "ความสูงชายคา" : nil, R == nil ? "ความสูงสันหลังคา" : nil].compactMap { $0 })
            }
            guard R > E else { return (nil, ["ความสูงสันหลังคา (ต้องมากกว่าชายคา)"]) }
            rise = R - E
        }
        if E == nil { assumed.append("ไม่ทราบความสูงชายคา") }
        let s = v.number("space1").flatMap { $0 > 0 ? $0 / 100 : nil }
        if s == nil && sh != .flat { assumed.append("ระยะแป 1.00 ม.") }
        var members: [Member] = []
        for (i, name) in Options.components.enumerated() {
            let size = v.text("size\(i + 1)").trimmingCharacters(in: .whitespaces), at = v.text("space\(i + 1)").trimmingCharacters(in: .whitespaces)
            guard !size.isEmpty else { continue }
            members.append(Member(name: name, size: size + " ซม." + (at.isEmpty ? "" : " @" + at + " ซม.")))
        }
        if members.isEmpty { warnings.append("ยังไม่ได้ระบุขนาดชิ้นส่วน") }
        return checked(Input(title: "หลังคาอาคาร", shape: sh, span: B, eave: E, rise: rise, overhang: 0,
                             purlinSpacing: s.map { min(3, max(0.2, $0)) } ?? 1.0, members: members, assumed: assumed, warnings: warnings))
    }

    // MARK: geometry

    /// The roof line, eave tip to eave tip, in metres (y up, tie beam at `e`).
    static func roofLine(_ i: Input, eave e: Double) -> [(x: Double, y: Double)] {
        let t = i.rise / max(i.run, 1e-9), o = i.overhang, B = i.span
        switch i.shape {
        case .gable, .hip: return [(-o, e - o * t), (B / 2, e + i.rise), (B + o, e - o * t)]
        case .shed: return [(-o, e - o * t), (B + o, e + i.rise + o * t)]
        case .flat: return [(-o, e), (B + o, e)]
        case .curved:
            // the arc through both eaves and the ridge
            let h = B / 2, r = (h * h + i.rise * i.rise) / (2 * i.rise), cy = e + i.rise - r
            let a0 = asin(min(1, h / r))
            return (0...24).map { k in
                let a = -a0 + 2 * a0 * Double(k) / 24
                return (h + r * sin(a), cy + r * cos(a))
            }
        }
    }

    /// Purlins along each slope from the eave, every `purlinSpacing`, plus one at the ridge when the last gap is over
    /// a quarter spacing (cap 200 a slope). Points in metres, with the slope's direction.
    static func purlins(_ i: Input, eave e: Double) -> [(x: Double, y: Double)] {
        guard i.shape != .flat else { return [] }
        let L = i.slopeLength, s = i.purlinSpacing, ux = i.run / L, uy = i.rise / L
        var ts: [Double] = []
        var t = 0.0
        while t <= L + 1e-9 && ts.count < 200 { ts.append(t); t += s }
        if let last = ts.last, L - last > 0.25 * s { ts.append(L) }
        if i.shape == .curved {
            let line = roofLine(Input(title: "", shape: .curved, span: i.span, eave: nil, rise: i.rise, overhang: 0, purlinSpacing: s, members: []), eave: e)
            let n = max(2, ts.count - 1)
            return (0...(2 * n)).map { k in line[min(line.count - 1, Int((Double(k) / Double(2 * n) * 24).rounded()))] }
        }
        var out = ts.map { (x: $0 * ux, y: e + $0 * uy) }
        if i.shape != .shed { out += ts.filter { $0 < L - 1e-6 }.map { (x: i.span - $0 * ux, y: e + $0 * uy) } }
        return out
    }

    // MARK: drawing

    static let ink = RGBA(hex: 0x1A1D22), dimC = RGBA(hex: 0x16325C), soil = RGBA(hex: 0x8B6F47), red = RGBA(hex: 0xD9453B)

    /// docs/specs/auto-drawing.md §6: 690 pt wide, title strip, the section fitted to `W − 128` × 220, the dimension
    /// chain under it, the members, the assumed values and warnings, and the note that it is not a construction drawing.
    public static func sketch(_ i: Input, width W: Double = 690) -> Sketch {
        let known = i.eave != nil, e = i.eave ?? 3.0, o = i.overhang, B = i.span
        let line = roofLine(i, eave: e)
        let top = line.map(\.y).max() ?? e, base = known ? 0 : e - 0.8
        let left = -o, right = B + o
        let areaW = W - 128, areaH = 210.0, y0 = 40.0
        let k = min(areaW / max(right - left, 1e-6), areaH / max(top + (i.shape == .flat ? 0.15 : 0) - base, 1e-6))
        let x0 = 64 + (areaW - (right - left) * k) / 2
        func P(_ x: Double, _ y: Double) -> Pt { Pt(x0 + (x - left) * k, y0 + (top - y) * k) }
        var o2: [DrawOp] = [.rect(Box(0, 0, W, 0), stroke: nil, fill: .white)]

        o2.append(.text("รูปตัดโครงหลังคา — " + i.title, at: Pt(16, 14), size: 10, bold: true, color: ink))
        o2.append(.text("หน่วย: ม. | มาตราส่วนโดยประมาณ", at: Pt(W - 16, 14), size: 8.5, color: .ink2, align: .right))

        // ground and columns
        let ground = P(0, 0).y
        if known {
            o2.append(.line(Pt(P(left, 0).x - 20, ground), Pt(P(right, 0).x + 20, ground), width: 1.4, color: soil))
            o2.append(.hatch(Box(P(left, 0).x - 20, ground, (right - left) * k + 40, 6), color: soil.withAlpha(0.6), spacing: 6))
        }
        let colW = max(3, 0.2 * k)
        let colTops: [(Double, Double)] = i.shape == .shed ? [(0, e), (B, e + i.rise)] : [(0, e), (B, e)]
        for (x, yTop) in colTops {
            if known { o2.append(.rect(Box(P(x, 0).x - colW / 2, P(x, yTop).y, colW, (yTop) * k), stroke: ink, fill: RGBA(hex: 0xC9CED6), width: 0.8)) }
            else { o2.append(.line(P(x, yTop), P(x, yTop - 0.6), width: 1.2, color: ink, dash: [4, 3])) }
        }
        if !known { o2.append(.text("ไม่ทราบความสูงชายคา", at: Pt(P(B / 2, e - 0.6).x, P(0, e - 0.6).y), size: 8.5, color: red, align: .center)) }

        // the frame
        if i.shape == .flat {
            let a = P(left, e + 0.15), b = P(right, e)
            o2.append(.rect(Box(a.x, a.y, b.x - a.x, b.y - a.y), stroke: ink, fill: RGBA(hex: 0xC9CED6), width: 1.2))
        } else {
            o2.append(.polyline(line.map { P($0.x, $0.y) }, width: 2.2, color: ink))
            o2.append(.line(P(0, e), P(B, e), width: 1.6, color: ink))
            switch i.shape {
            case .gable, .hip, .curved:
                let h = B / 2
                o2.append(.line(P(h, e), P(h, e + i.rise), width: 1.6, color: ink))
                if i.shape != .curved {
                    o2.append(.line(P(h, e), P(h / 2, e + i.rise / 2), width: 1.2, color: ink))
                    o2.append(.line(P(h, e), P(3 * h / 2, e + i.rise / 2), width: 1.2, color: ink))
                }
            case .shed:
                o2.append(.line(P(B, e), P(B, e + i.rise), width: 1.6, color: ink))
            case .flat: break
            }
            // fascia at each tip, 0.2 m down
            for tip in [line.first!, line.last!] { o2.append(.line(P(tip.x, tip.y), P(tip.x, tip.y - 0.2), width: 1.6, color: ink)) }
            // purlins: fixed-size markers on the rafter
            for p in purlins(i, eave: e) {
                let c = P(p.x, p.y)
                o2.append(.rect(Box(c.x - 3.5, c.y - 7.8, 7, 5), stroke: ink, fill: .white, width: 0.9))
            }
        }

        // dimensions
        func dimH(_ a: Double, _ b: Double, _ y: Double, _ label: String) {
            let pa = P(a, 0).x, pb = P(b, 0).x
            o2.append(.line(Pt(pa, y), Pt(pb, y), width: 0.6, color: dimC))
            for x in [pa, pb] { o2.append(.line(Pt(x - 3, y + 3), Pt(x + 3, y - 3), width: 0.8, color: dimC)) }
            if pb - pa > 14 { o2.append(.text(label, at: Pt((pa + pb) / 2, y - 7), size: 8.5, color: dimC, align: .center)) }
        }
        func dimV(_ x: Double, _ a: Double, _ b: Double, _ label: String, right: Bool) {
            let pa = P(0, a).y, pb = P(0, b).y
            o2.append(.line(Pt(x, pa), Pt(x, pb), width: 0.6, color: dimC))
            for y in [pa, pb] { o2.append(.line(Pt(x - 3, y + 3), Pt(x + 3, y - 3), width: 0.8, color: dimC)) }
            o2.append(.text(label, at: Pt(x + (right ? 6 : -6), (pa + pb) / 2), size: 8.5, color: dimC, align: right ? .left : .right))
        }
        let chainY = (known ? ground : P(0, e - 0.8).y) + 22
        if o > 0 { dimH(left, 0, chainY, String(format: "%.2f", o)); dimH(B, right, chainY, String(format: "%.2f", o)) }
        dimH(0, B, chainY, String(format: "%.2f", B))
        o2.append(.text("ช่วงกว้าง " + String(format: "%.2f", B), at: Pt(P(B / 2, 0).x, chainY + 12), size: 9, bold: true, color: dimC, align: .center))
        if known { dimV(P(left, 0).x - 14, 0, e, "ชายคา " + String(format: "%.2f", e), right: false) }
        if i.rise > 0 {
            let rx = P(right, 0).x + 14
            dimV(rx, e, e + i.rise, "R " + String(format: "%.2f", i.rise), right: true)
            // the pitch: an arc at the left column head, and the slope length along the first slope
            let c = P(0, e), deg = i.pitch
            let arc = (0...12).map { s -> Pt in let a = Double(s) / 12 * deg * .pi / 180; return Pt(c.x + 30 * cos(a), c.y - 30 * sin(a)) }
            o2.append(.polyline(arc, width: 0.6, color: dimC))
            o2.append(.text(fmt((deg * 10).rounded() / 10) + "°", at: Pt(c.x + 50, c.y - 5), size: 8, color: dimC))
            if i.shape != .curved {
                let m = P(i.run / 2, e + i.rise / 2)
                o2.append(.text("L = " + String(format: "%.2f", i.slopeLength) + " ม.", at: Pt(m.x, m.y - 16), size: 8.5, color: dimC,
                                align: .center, angle: -deg))
            }
        }

        // members, assumed values, warnings and the note
        var y = chainY + 30
        let rows = i.members.enumerated().map { n, m in "\(n + 1) " + m.name + " | " + (m.size.isEmpty ? "— ไม่ได้ระบุ —" : m.size) }
        let colWd = (W - 32) / 2
        for (n, t) in rows.enumerated() {
            o2.append(.text(t, at: Pt(16 + Double(n % 2) * colWd, y + Double(n / 2) * 12), size: 8.5, color: ink))
        }
        y += Double((rows.count + 1) / 2) * 12 + (rows.isEmpty ? 0 : 4)
        if !i.assumed.isEmpty { o2.append(.text("ค่าสมมติ: " + i.assumed.joined(separator: " | "), at: Pt(16, y), size: 8, color: .ink2)); y += 12 }
        for w in i.warnings { o2.append(.text(w, at: Pt(16, y), size: 8, bold: true, color: red)); y += 12 }
        o2.append(.text(TankDrawings.note, at: Pt(16, y), size: 7.5, color: .ink2))
        let H = y + 10
        o2[0] = .rect(Box(0, 0, W, H), stroke: nil, fill: .white)
        return Sketch(width: W, height: H, ops: o2)
    }
}
