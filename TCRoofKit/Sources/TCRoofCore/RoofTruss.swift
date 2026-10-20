import Foundation

/// C1's truss in metres, its member schedule and the details A / B (docs/specs/auto-drawing.md §4.4: "Truss",
/// "Detail callouts", "Member schedule"). Section A-A (`RoofSection`) draws the same members to scale; the schedule
/// counts them and the details draw the support and the ridge, not to scale, labelled with the sizes entered in
/// `comp1`…`comp7`.
public enum RoofTruss {
    /// A straight member, metres: x from the left support, y up from the bottom chord.
    public struct Segment: Equatable, Sendable {
        public let a, b: Pt
        public var length: Double { hypot(b.x - a.x, b.y - a.y) }
    }

    /// The truss across the ridge, as section A-A draws it.
    public struct Geometry: Sendable {
        public let frame: RoofFrame
        /// Span, half span, rise, heel depth, overhang (m) and the slope's tangent.
        public let span, half, rise, heel, overhang, tan: Double
        public let bays: Int
        /// Interior verticals and the heel ends (not the king post).
        public var verticals: [Segment] = []
        public var diagonals: [Segment] = []
        public var kingPost: Segment?
        public var panel: Double { half / Double(bays) }
        public var cos: Double { 1 / (1 + tan * tan).squareRoot() }
        /// Slope length of one top chord from the support to the ridge.
        public var slopeLength: Double { half / cos }
        /// Top chord height at x (m above the bottom chord).
        public func top(_ x: Double) -> Double { heel + min(x, span - x) * tan }
        public var nodeX: [Double] { (0...(2 * bays)).map { Double($0) * panel } }

        /// Web ends, the supports' chord ends and the ridge, one each to the millimetre: one gusset per node.
        public var nodes: [Pt] {
            var seen = Set<String>(), out: [Pt] = []
            func add(_ p: Pt) {
                let k = "\(Int((p.x * 1000).rounded())),\(Int((p.y * 1000).rounded()))"
                if seen.insert(k).inserted { out.append(p) }
            }
            for p in [Pt(0, 0), Pt(0, heel), Pt(span, 0), Pt(span, heel), Pt(half, rise + heel)] { add(p) }
            for s in verticals + diagonals + [kingPost].compactMap({ $0 }) { add(s.a); add(s.b) }
            return out
        }

        init(frame f: RoofFrame, span B: Double, bays n: Int, slope: Double, overhang o: Double) {
            frame = f; span = B; half = B / 2; bays = n; heel = f.heel; overhang = o
            tan = Foundation.tan(slope * .pi / 180); rise = B / 2 * tan
            guard f.isTruss else { return }
            let xs = nodeX, h = half
            func bottom(_ x: Double) -> Pt { Pt(x, 0) }
            func topP(_ x: Double) -> Pt { Pt(x, top(x)) }
            func seg(_ a: Pt, _ b: Pt) -> Segment { Segment(a: a, b: b) }
            kingPost = seg(bottom(h), topP(h))
            if heel > 0 { verticals += [seg(bottom(0), topP(0)), seg(bottom(B), topP(B))] }
            switch f {
            case .normal:
                // a king post and one strut per half, from the bottom chord's quarter to the top chord
                for (q, t) in [(0.5 * h, 0.72 * h), (B - 0.5 * h, B - 0.72 * h)] { diagonals.append(seg(bottom(q), topP(t))) }
            case .warren:
                for i in 0..<(2 * n) { diagonals.append(i % 2 == 0 ? seg(bottom(xs[i]), topP(xs[i + 1])) : seg(topP(xs[i]), bottom(xs[i + 1]))) }
            default:
                // Pratt and Howe: a vertical at every node, diagonals down toward the ridge (Pratt) or up toward it (Howe)
                for i in 1..<(2 * n) where i != n { verticals.append(seg(bottom(xs[i]), topP(xs[i]))) }
                if f == .howe {
                    for i in 0..<n { diagonals.append(seg(bottom(xs[i]), topP(xs[i + 1]))) }
                    for i in n..<(2 * n) { diagonals.append(seg(topP(xs[i]), bottom(xs[i + 1]))) }
                } else {
                    for i in 1..<n { diagonals.append(seg(topP(xs[i]), bottom(xs[i + 1]))) }
                    for i in (n + 1)..<(2 * n) { diagonals.append(seg(bottom(xs[i - 1]), topP(xs[i]))) }
                }
            }
        }
    }

    public static func geometry(_ v: Values) -> Geometry? {
        let B = Roof.span(v)
        guard B > 0, B.isFinite else { return nil }
        let a = Roof.slope(v)
        guard a > 0, a <= 60 else { return nil }
        return Geometry(frame: Roof.frame(v), span: B, bays: Roof.bays(v), slope: a, overhang: Roof.overhang(v))
    }

    // MARK: schedule

    /// One line of the member schedule. `count` and `length` are for the whole roof; `perFrame` for one truss (or one
    /// pair of rafters), nil for members along the ridge.
    public struct Row: Equatable, Sendable {
        /// Member row 1…7 (`comp<n>`), nil for the gusset plates.
        public let row: Int?
        public let name: String
        /// As entered, "ไม่ระบุขนาด" when empty.
        public let size: String
        public let count: Int
        /// Total length (m); 0 for plates, which are counted.
        public let length: Double
        public let perFrameCount: Int?
        public let perFrameLength: Double?
    }
    public struct Schedule: Equatable, Sendable {
        public let rows: [Row]
        /// Trusses (T1) or rafter pairs on the roof.
        public let frames: Int
        /// "โครง T1 3 ชุด · ช่วง 16.00 ม. · ยาวตามสัน 24.00 ม. · มุม 15°"
        public let summary: String
        /// What the quantities leave out.
        public let note: String
    }

    /// The members of C1's roof by row, counted from the same geometry as section A-A and the plan: trusses on the
    /// plan's T1 lines (inside grid lines along the ridge), purlins on `Roof.purlinLines`, rafters @1.00. Lengths
    /// are centre lines, without laps, splices or waste.
    public static func schedule(_ v: Values) -> Schedule? {
        guard let g = geometry(v) else { return nil }
        let f = g.frame, names = f.members.map(\.name)
        let ridge = Roof.ridge(v), along = ridge == .h ? Roof.spans(v, .x) : Roof.spans(v, .y)
        let across = ridge == .h ? Roof.spans(v, .y) : Roof.spans(v, .x)
        let run = along.reduce(0, +)
        guard run > 0 else { return nil }
        var frames: Int, frameNote = ""
        if f.isRafter {
            var a = 0.5, n = 0
            while a < run { n += 1; a += 1 }
            frames = max(1, n)
        } else {
            frames = max(0, along.count - 1)
            if frames == 0 { frames = 1; frameNote = "แปลนไม่มีโครงช่วงกลาง คิด 1 ชุด" }
        }
        var rows: [Row] = []
        func size(_ n: Int) -> String? {
            let s = Roof.memberSize(v, n)
            return s == "-" ? nil : s.isEmpty ? "ไม่ระบุขนาด" : s
        }
        /// A member every truss has: `count` pieces of total `length` per truss.
        func perFrame(_ n: Int, _ count: Int, _ length: Double) {
            guard let s = size(n), count > 0 else { return }
            rows.append(Row(row: n, name: names[n - 1], size: s, count: count * frames, length: length * Double(frames),
                            perFrameCount: count, perFrameLength: length))
        }
        /// A member along the ridge: `lines` runs the roof's length.
        func alongRidge(_ n: Int, lines: Int) {
            guard let s = size(n), lines > 0 else { return }
            rows.append(Row(row: n, name: names[n - 1], size: s, count: lines, length: Double(lines) * run, perFrameCount: nil, perFrameLength: nil))
        }
        let chord = (g.half + g.overhang) / g.cos
        alongRidge(1, lines: Roof.purlinLines(v).count)
        switch f {
        case .rafterTie, .eaveCeiling:
            // the tie sits at half (0.55 for ชายคาฝ้า) the rise, so it spans B less that share of each half
            perFrame(2, 2, 2 * chord)
            perFrame(3, 1, g.span - 2 * (f == .eaveCeiling ? 0.55 : 0.5) * g.half)
            alongRidge(4, lines: 2)
            alongRidge(6, lines: 2)
            if f == .eaveCeiling, let s = size(7) {
                let posts = Roof.posts(v).count
                if posts > 0 { rows.append(Row(row: 7, name: names[6], size: s, count: posts, length: Double(posts) * Roof.clearHeight(v), perFrameCount: nil, perFrameLength: nil)) }
            }
        case .rafterTruss:
            // two parallel tube chords a heel apart, a diagonal and a vertical in every panel
            let diag = hypot(g.panel / g.cos, g.heel)
            perFrame(2, 2, 2 * chord)
            perFrame(3, 2, 2 * chord)
            perFrame(4, 4 * g.bays, Double(2 * g.bays) * (diag + g.heel))
            alongRidge(5, lines: max(0, across.count - 1))
            alongRidge(6, lines: 2)
            if let s = size(7) {
                let posts = Roof.posts(v).count
                if posts > 0 { rows.append(Row(row: 7, name: names[6], size: s, count: posts, length: Double(posts) * Roof.clearHeight(v), perFrameCount: nil, perFrameLength: nil)) }
            }
        default:
            perFrame(2, 2, 2 * chord)
            perFrame(3, 1, g.span)
            perFrame(4, g.verticals.count, g.verticals.map(\.length).reduce(0, +))
            perFrame(5, g.diagonals.count, g.diagonals.map(\.length).reduce(0, +))
            alongRidge(6, lines: 2)
            if let k = g.kingPost { perFrame(7, 1, k.length) }
            let plates = g.nodes.count
            rows.append(Row(row: nil, name: "แผ่นประกับ (gusset)", size: "ตามแบบวิศวกร", count: plates * frames, length: 0, perFrameCount: plates, perFrameLength: nil))
        }
        let unit = f.isRafter ? "จันทัน \(frames) คู่ @1.00" : "โครง T1 \(frames) ชุด"
        let summary = [unit, String(format: "ช่วง %.2f ม.", g.span), String(format: "ยาวตามสัน %.2f ม.", run), "มุม " + Roof.slopeText(v), frameNote]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return Schedule(rows: rows, frames: frames, summary: summary,
                        note: "ความยาวตามแนวศูนย์กลางชิ้นส่วน ไม่รวมระยะต่อทาบและเศษ · " + TankDrawings.note)
    }

    /// "12 · 31.20" for a row's per-truss cell, "-" for members along the ridge.
    public static func perFrameText(_ r: Row) -> String {
        guard let c = r.perFrameCount else { return "-" }
        return r.perFrameLength.map { String(format: "%d · %.2f", c, $0) } ?? "\(c)"
    }
    /// "36 · 93.60 ม." for the roof, or "36 แผ่น" for plates.
    public static func totalText(_ r: Row) -> String {
        r.length > 0 ? String(format: "%d · %.2f ม.", r.count, r.length) : "\(r.count) แผ่น"
    }

    // MARK: details A / B

    public static let detailWidth = 760.0, detailHeight = 270.0

    /// Details A (the left support) and B (the ridge) side by side, not to scale, for the trusses with a bottom chord
    /// (ปกติ, Pratt, Howe, Warren); nil for the rafter frames and the rafter truss.
    public static func details(_ v: Values) -> Sketch? {
        guard let g = geometry(v), g.frame.isTruss else { return nil }
        var o: [DrawOp] = [.rect(Box(0, 0, detailWidth, detailHeight), stroke: nil, fill: .white)]
        let names = g.frame.members.map(\.name)
        func label(_ n: Int) -> String? {
            let s = Roof.memberSize(v, n)
            return s == "-" ? nil : names[n - 1] + " " + (s.isEmpty ? "ไม่ระบุขนาด" : s)
        }
        let spacing = Roof.purlinSpacing(v)
        o += Panel(g, x: 0, title: "รายละเอียด A · ที่รองรับ", kind: .support, purlin: spacing, label: label).ops
        o.append(.line(Pt(380, 8), Pt(380, detailHeight - 26), width: 0.5, color: RGBA(hex: 0xC9CED6)))
        o += Panel(g, x: 385, title: "รายละเอียด B · สันหลังคา", kind: .ridge, purlin: spacing, label: label).ops
        o.append(.text("ไม่ได้มาตราส่วน · ขนาดตามที่กรอกในรายการโครงสร้าง · " + TankDrawings.note, at: Pt(10, detailHeight - 12), size: 8.5,
                       color: RGBA(hex: 0x6B7685)))
        return Sketch(width: detailWidth, height: detailHeight, ops: o)
    }

    /// One detail: the members cut to a window around the support or the ridge, the gusset and its bolts, purlins
    /// with cleats, the sheet, and labels in a column on the right with leaders.
    struct Panel {
        enum Kind { case support, ridge }
        var ops: [DrawOp] = []
        static let ink = RGBA(hex: 0x1A1D22), core = RGBA(hex: 0xD5DBE3), webCore = RGBA(hex: 0xF2F4F7), navy = RGBA(hex: 0x16325C)
        static let sheet = RGBA(hex: 0x1F4F78), red = RGBA(hex: 0xD9453B), plate = RGBA(hex: 0xEEF1F5), concrete = RGBA(hex: 0xC9CED6)

        init(_ g: Geometry, x px: Double, title: String, kind: Kind, purlin: Double, label: (Int) -> String?) {
            let W = 222.0, H = 190.0, left = px + 10, topY = 42.0
            ops.append(.text(title, at: Pt(px + 10, 16), size: 11, bold: true, color: Self.navy))
            ops.append(.text("ไม่ได้มาตราส่วน", at: Pt(px + 10, 30), size: 8.5, color: RGBA(hex: 0x6B7685)))
            // the window, metres: around the left support (the overhang to two panels in) or the ridge (a panel and a half each side)
            let pw = g.panel, o = min(g.overhang, 1.2)
            let x0, x1, y0, y1: Double
            switch kind {
            case .support:
                x0 = -o - 0.15; x1 = min(g.half, 1.7 * pw)
                y0 = -0.75; y1 = g.top(x1) + 0.35
            case .ridge:
                let reach = min(g.half, 1.4 * pw)
                x0 = g.half - reach; x1 = g.half + reach
                y0 = -0.3; y1 = g.rise + g.heel + 0.4
            }
            let k = min(W / (x1 - x0), H / (y1 - y0))
            let ox = left + (W - (x1 - x0) * k) / 2, oy = topY + (H - (y1 - y0) * k) / 2
            func P(_ x: Double, _ y: Double) -> Pt { Pt(ox + (x - x0) * k, oy + (y1 - y) * k) }
            func P(_ p: Pt) -> Pt { P(p.x, p.y) }
            /// The segment's part inside the window's x range.
            func clip(_ a: Pt, _ b: Pt) -> (Pt, Pt)? {
                var a = a, b = b
                if a.x > b.x { swap(&a, &b) }
                guard b.x >= x0, a.x <= x1 else { return nil }
                func at(_ x: Double) -> Pt { b.x == a.x ? a : Pt(x, a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)) }
                return (a.x < x0 ? at(x0) : a, b.x > x1 ? at(x1) : b)
            }
            func member(_ a: Pt, _ b: Pt, _ w: Double, _ c: Double) {
                guard let (p, q) = clip(a, b) else { return }
                ops.append(.line(P(p), P(q), width: w, color: Self.ink))
                ops.append(.line(P(p), P(q), width: c, color: w > 5 ? Self.core : Self.webCore))
            }
            var targets: [(Int?, String, Pt)] = []

            // gusset plate behind the joint, then its bolts after the members
            var bolts: [Pt] = []
            switch kind {
            case .support:
                let gx = min(0.42, 0.45 * pw)
                ops.append(.polygon([P(-0.08, -0.03), P(gx, -0.03), P(gx, 0.14), P(gx * 0.6, g.top(gx * 0.6) + 0.03), P(-0.08, g.top(-0.08) + 0.03)],
                                    stroke: Self.ink, fill: Self.plate, width: 0.9))
                bolts = [Pt(gx * 0.3, 0.05), Pt(gx * 0.75, 0.05), Pt(0.02, g.heel * 0.55), Pt(gx * 0.3, g.top(gx * 0.3) - 0.07)]
                targets.append((nil, "แผ่นประกับ + สลักเกลียว", Pt(gx * 0.85, 0.1)))
            case .ridge:
                let h = g.half, gx = min(0.35, 0.4 * pw), apex = g.rise + g.heel
                ops.append(.polygon([P(h - gx, g.top(h - gx) + 0.03), P(h, apex + 0.04), P(h + gx, g.top(h + gx) + 0.03),
                                     P(h + gx * 0.45, apex - 0.42), P(h - gx * 0.45, apex - 0.42)], stroke: Self.ink, fill: Self.plate, width: 0.9))
                bolts = [Pt(h - gx * 0.55, g.top(h - gx * 0.55) - 0.07), Pt(h + gx * 0.55, g.top(h + gx * 0.55) - 0.07), Pt(h, apex - 0.2), Pt(h, apex - 0.33)]
                targets.append((nil, "แผ่นประกับสัน + สลักเกลียว", Pt(h + gx * 0.4, apex - 0.3)))
                // the bottom chord's splice under the king post
                ops.append(.rect(Box(P(h - 0.28, 0.07).x, P(h - 0.28, 0.07).y, 0.56 * k, 0.14 * k), stroke: Self.ink, fill: Self.plate, width: 0.9))
                for bx in [h - 0.2, h - 0.08, h + 0.08, h + 0.2] { bolts.append(Pt(bx, 0)) }
                targets.append((nil, "ต่อคอร์ดล่าง แผ่นประกับ + สลักเกลียว", Pt(h + 0.26, -0.04)))
            }

            // the column and its cap plate (support only)
            if kind == .support {
                let cw = 0.12
                ops.append(.rect(Box(P(-cw / 2, -0.04).x, P(-cw / 2, -0.04).y, cw * k, (y0 + 0.1 - (-0.04)) * -k), stroke: Self.ink, fill: Self.core, width: 1))
                ops.append(.rect(Box(P(-0.13, 0).x, P(-0.13, 0).y, 0.26 * k, max(2.5, 0.04 * k)), stroke: Self.ink, fill: Self.ink, width: 0.5))
                for ax in [-0.08, 0.08] { ops.append(.line(P(ax, 0.02), P(ax, -0.16), width: 1.2, color: Self.ink)) }
                // a break line at the column's foot
                let by = y0 + 0.1
                ops.append(.polyline([P(-0.12, by), P(-0.04, by), P(-0.02, by + 0.05), P(0.02, by - 0.05), P(0.04, by), P(0.12, by)], width: 0.8, color: Self.ink))
                targets.append((nil, "แผ่นรองหัวเสา + พุกยึด", Pt(0.13, -0.02)))
            }

            // webs, chords and the king post
            for s in g.verticals { member(s.a, s.b, 3.2, 1.3) }
            for s in g.diagonals { member(s.a, s.b, 3.2, 1.3) }
            if let kp = g.kingPost { member(kp.a, kp.b, 4.4, 2) }
            member(Pt(0, 0), Pt(g.span, 0), 6, 3.6)
            let eave = -o, eaveY = g.top(0) - o * g.tan
            member(Pt(eave, eaveY), Pt(g.half, g.rise + g.heel), 6, 3.6)
            member(Pt(g.half, g.rise + g.heel), Pt(g.span + o, eaveY), 6, 3.6)
            for b in bolts where b.x >= x0 && b.x <= x1 {
                ops.append(.circle(P(b), r: max(1.6, 0.018 * k), stroke: Self.ink, fill: .white, width: 0.9))
            }

            // members to label: the first vertical and diagonal inside the window
            func inside(_ s: Segment) -> Pt? {
                let m = Pt((s.a.x + s.b.x) / 2, (s.a.y + s.b.y) / 2)
                return m.x > x0 + 0.05 && m.x < x1 - 0.05 ? m : nil
            }
            let byNear: (Segment, Segment) -> Bool = {
                let c = kind == .support ? 0 : g.half
                return abs(($0.a.x + $0.b.x) / 2 - c) < abs(($1.a.x + $1.b.x) / 2 - c)
            }
            if let s = g.verticals.sorted(by: byNear).first(where: { inside($0) != nil && $0.a.x > 0.01 && $0.a.x < g.span - 0.01 }), let m = inside(s) {
                targets.append((4, label(4) ?? "", m))
            } else if kind == .support, let s = g.verticals.first(where: { $0.a.x < 0.01 }) {
                targets.append((4, label(4) ?? "", Pt(0, s.b.y * 0.6)))
            }
            if let s = g.diagonals.sorted(by: byNear).first(where: { inside($0) != nil }), let m = inside(s) { targets.append((5, label(5) ?? "", m)) }
            if kind == .ridge, let kp = g.kingPost { targets.append((7, label(7) ?? "", Pt(kp.a.x, (kp.a.y + kp.b.y) * 0.45))) }
            let xc = kind == .support ? min(x1 * 0.75, pw * 1.2) : g.half - min(g.half, 1.4 * pw) * 0.55
            targets.append((2, label(2) ?? "", Pt(xc, g.top(xc))))
            targets.append((3, label(3) ?? "", Pt(kind == .support ? x1 * 0.8 : g.half - 0.55 * min(g.half, 1.4 * pw), 0)))

            // purlins (upright C marks with a cleat) along the slope, the sheet above them, the fascia or the ridge cap
            let pd = 0.12, lift = 0.06
            func purlinMark(_ x: Double) {
                let y = g.top(x) + lift
                ops.append(.polygon([P(x - 0.05, y - 0.05), P(x + 0.02, y - 0.05), P(x + 0.02, y + 0.01)], stroke: Self.ink, fill: Self.plate, width: 0.6))
                ops.append(.polyline([P(x + 0.04, y), P(x - 0.025, y), P(x - 0.025, y + pd), P(x + 0.04, y + pd)], width: 1.6, color: Self.ink))
            }
            let step = purlin * g.cos
            var xs: [Double] = []
            switch kind {
            case .support:
                var x = eave + 0.12
                while x < x1 - 0.05 { xs.append(x); x += step }
            case .ridge:
                var d = 0.15
                while g.half - d > x0 + 0.05 { xs += [g.half - d, g.half + d]; d += step }
            }
            for x in xs where x > x0 && x < x1 { purlinMark(x) }
            if let first = xs.first(where: { $0 > x0 && $0 < x1 }) { targets.append((1, label(1) ?? "", Pt(first, g.top(first) + lift + pd))) }
            let sOff = lift + pd + 0.03
            switch kind {
            case .support:
                ops.append(.polyline([P(eave - 0.05, eaveY + sOff - 0.05 * g.tan), P(x1, g.top(x1) + sOff)], width: 1.4, color: Self.sheet))
                ops.append(.rect(Box(P(eave - 0.03, eaveY + 0.02).x, P(eave - 0.03, eaveY + 0.02).y, max(2.5, 0.03 * k), 0.22 * k), stroke: Self.ink, fill: Self.ink))
                targets.append((6, label(6) ?? "", Pt(eave, eaveY - 0.1)))
                targets.append((nil, "แผ่นหลังคา", Pt(eave + 0.35, eaveY + 0.35 * g.tan + sOff)))
            case .ridge:
                let apexS = g.rise + g.heel + sOff
                ops.append(.polyline([P(x0, g.top(x0) + sOff), P(g.half, apexS), P(x1, g.top(x1) + sOff)], width: 1.4, color: Self.sheet))
                ops.append(.polyline([P(g.half - 0.22, apexS - 0.22 * g.tan + 0.03), P(g.half, apexS + 0.07), P(g.half + 0.22, apexS - 0.22 * g.tan + 0.03)],
                                     width: 2, color: Self.sheet))
                targets.append((nil, "ครอบสันหลังคา", Pt(g.half + 0.12, apexS + 0.03)))
            }

            // labels in a column on the right, ordered top to bottom, each with a leader to its member
            let lx = px + 10 + W + 10, shown = targets.filter { !$0.1.isEmpty }.sorted { $0.2.y > $1.2.y }
            let gap = min(20, (H + 10) / Double(max(1, shown.count)))
            for (i, t) in shown.enumerated() {
                let ly = topY + 6 + Double(i) * gap, target = P(t.2)
                ops.append(.line(Pt(lx - 4, ly), target, width: 0.6, color: Self.red))
                ops.append(.circle(target, r: 1.6, stroke: nil, fill: Self.red))
                var tx = lx
                if let n = t.0 {
                    ops.append(.circle(Pt(lx + 6, ly), r: 6, stroke: Self.red, fill: .white, width: 1))
                    ops.append(.text(String(n), at: Pt(lx + 6, ly), size: 8, bold: true, color: Self.red, align: .center))
                    tx += 15
                }
                ops.append(.textBox(t.1, Box(tx, ly - 6, px + 375 - tx, 12), size: 8, color: Self.navy))
            }
        }
    }
}
