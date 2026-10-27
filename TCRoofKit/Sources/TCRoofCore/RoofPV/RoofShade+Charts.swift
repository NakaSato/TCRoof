import Foundation

/// The shade card's three charts as `Sketch`es, drawn the same on C1's card and on the report's shade pages
/// (docs/ui/survey-c1-ipad-shade): the sun path with the obstacles' silhouettes, the monthly sun access and shading,
/// and the hour × month heat map. The core draws without the UI's theme, so the colours are `Theme`'s values.
extension RoofShade {
    /// `Theme.navy`, `Theme.inkMuted`, `Theme.borderSubtle` and the chart inks.
    static let navy = RGBA(hex: 0x16325C), muted = RGBA(hex: 0x7A8BA3), grid = RGBA(hex: 0xDDE4ED), axis = RGBA(hex: 0xC9D3DF)
    /// The three days' curves: June orange, the equinoxes amber, December blue (`Theme.primary`).
    static func ink(_ k: SunPathDay.Kind) -> RGBA {
        switch k {
        case .june: RGBA(hex: 0xE8833A)
        case .equinox: RGBA(hex: 0xD9A400)
        case .december: RGBA(hex: 0x1F6FB5)
        }
    }
    static let accessInk = RGBA(hex: 0x5B9BD5), shadingInk = RGBA(hex: 0xE8833A)
    /// The heat map's bands, low to high: `Theme.danger`, `Theme.warning`, yellow, light green, `Theme.success`.
    public static let bands: [(below: Double, label: String, color: RGBA)] = [
        (0.60, "<60%", RGBA(hex: 0xD9453B)), (0.80, "60–80", RGBA(hex: 0xF08C00)), (0.90, "80–90", RGBA(hex: 0xF2C94C)),
        (0.97, "90–97", RGBA(hex: 0xA8D5A2)), (2, "≥97%", RGBA(hex: 0x2E9E5B)),
    ]
    static let monthShort = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."]

    public static let sunPathSize = (w: 160.0, h: 166.0)
    public static let monthlySize = (w: 214.0, h: 130.0)
    public static let hourMonthSize = (w: 214.0, h: 132.0)

    /// The sun path, N up: rings at 0°, 30° and 60°, the three days with their hour dots, and each obstacle as the grey
    /// silhouette the group's modules see.
    public func sunPathSketch(_ g: Group) -> Sketch {
        let (W, H) = Self.sunPathSize, c = Pt(80, 80), R = 64.0
        func at(_ az: Double, _ el: Double) -> Pt {
            let r = R * (90 - min(90, max(0, el))) / 90, a = az * .pi / 180
            return Pt(c.x + r * sin(a), c.y - r * cos(a))
        }
        var o: [DrawOp] = []
        for el in [60.0, 30, 0] { o.append(.circle(c, r: R * (90 - el) / 90, stroke: Self.grid, fill: nil, width: 0.8)) }
        o.append(.line(Pt(c.x, c.y - R), Pt(c.x, c.y + R), width: 0.8, color: Self.grid))
        o.append(.line(Pt(c.x - R, c.y), Pt(c.x + R, c.y), width: 0.8, color: Self.grid))
        for s in g.silhouettes {
            // each edge in a few steps, so a wide obstacle follows the rings
            var pts: [Pt] = []
            for k in s.indices {
                let a = s[k], b = s[(k + 1) % s.count]
                for t in 0..<6 { let f = Double(t) / 6; pts.append(at(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f)) }
            }
            o.append(.polygon(pts, stroke: Self.muted, fill: Self.muted.withAlpha(0.35), width: 0.8))
        }
        for d in sunPath {
            let ink = Self.ink(d.kind)
            if d.points.count > 1 { o.append(.polyline(d.points.map { at($0.x, $0.y) }, width: 1.6, color: ink)) }
            for h in d.hours { o.append(.circle(at(h.x, h.y), r: 1.6, stroke: nil, fill: ink)) }
        }
        for (t, p) in [("N", Pt(80, 10)), ("S", Pt(80, 153)), ("E", Pt(151, 81)), ("W", Pt(9, 81))] {
            o.append(.text(t, at: p, size: 9, bold: true, color: Self.navy, align: .center))
        }
        o.append(.text("60°", at: Pt(83, 44.5), size: 7, color: Self.muted))
        o.append(.text("30°", at: Pt(83, 65.8), size: 7, color: Self.muted))
        // the legend under it
        var x = 6.0
        for d in sunPath {
            o.append(.circle(Pt(x + 3, 162), r: 3, stroke: nil, fill: Self.ink(d.kind)))
            o.append(.text(d.label, at: Pt(x + 9, 162), size: 8, color: Self.ink(d.kind)))
            x += 14 + Double(d.label.count) * 5.2
        }
        return Sketch(width: W, height: H, ops: o)
    }

    /// The shading bars' scale: the smallest of 1, 2, 4 and 10 that keeps the largest month inside the chart.
    public static func shadingScale(_ g: Group) -> Double {
        let top = g.monthlyShading.max() ?? 0
        return [10.0, 4, 2].first { top * $0 <= 1 } ?? 1
    }

    /// Two bars a month: sun access and shading, 0–100 %.
    public func monthlySketch(_ g: Group) -> Sketch {
        let (W, H) = Self.monthlySize, left = 22.0, base = 110.0, top = 30.0, slot = (W - 2 - left) / 12
        let k = Self.shadingScale(g)
        var o: [DrawOp] = [.line(Pt(left, base), Pt(W - 2, base), width: 0.8, color: Self.axis), .line(Pt(left, top), Pt(left, base), width: 0.8, color: Self.axis)]
        o.append(.text("100%", at: Pt(19, top + 1), size: 6.5, color: Self.muted, align: .right))
        o.append(.text("0%", at: Pt(19, base + 1), size: 6.5, color: Self.muted, align: .right))
        o.append(.rect(Box(24, 6, 7, 7), stroke: nil, fill: Self.accessInk))
        o.append(.text("Sun Access", at: Pt(34, 9.5), size: 7.5, color: RGBA(hex: 0x3B4A60)))
        o.append(.rect(Box(86, 6, 7, 7), stroke: nil, fill: Self.shadingInk))
        o.append(.text("Shading", at: Pt(96, 9.5), size: 7.5, color: RGBA(hex: 0x3B4A60)))
        if k > 1 { o.append(.text(String(format: "Shading ×%.0f", k), at: Pt(W - 2, 9.5), size: 6, color: Self.muted, align: .right)) }
        let h = base - top, bw = slot * 0.32
        for m in 0..<12 {
            let cx = left + (Double(m) + 0.5) * slot
            let a = min(1, max(0, g.monthlySunAccess[m])) * h, s = min(1, max(0, g.monthlyShading[m] * k)) * h
            o.append(.rect(Box(cx - bw - 0.5, base - a, bw, a), stroke: nil, fill: Self.accessInk))
            if s > 0 { o.append(.rect(Box(cx + 0.5, base - s, bw, s), stroke: nil, fill: Self.shadingInk)) }
            o.append(.text(Self.monthShort[m], at: Pt(cx, base + 10), size: 6, color: Self.muted, align: .center))
        }
        return Sketch(width: W, height: H, ops: o)
    }

    /// Sun access by month (down) and local hour (across), in the five bands.
    public func hourMonthSketch(_ g: Group) -> Sketch {
        let (W, H) = Self.hourMonthSize, x0 = 30.0, y0 = 18.0, rowH = 8.5
        let cols = max(1, hours.count), cw = (W - 2 - x0) / Double(cols)
        var o: [DrawOp] = []
        for (m, row) in g.hourMonth.enumerated() {
            let y = y0 + Double(m) * rowH
            o.append(.text(Self.monthShort[m], at: Pt(26, y + rowH / 2), size: 6.5, color: Self.muted, align: .right))
            for (j, v) in row.enumerated() {
                let fill = v.map { x in Self.bands.first { x < $0.below }?.color ?? Self.bands[4].color } ?? Self.grid.withAlpha(0.6)
                o.append(.rect(Box(x0 + Double(j) * cw + 0.4, y + 0.4, cw - 0.8, rowH - 0.8), stroke: nil, fill: fill))
            }
        }
        for (j, h) in hours.enumerated() where h % 3 == 0 {
            o.append(.text("\(h)", at: Pt(x0 + (Double(j) + 0.5) * cw, 12), size: 6.5, color: Self.muted, align: .center))
        }
        var x = x0
        for b in Self.bands {
            o.append(.rect(Box(x, 124, 8, 5), stroke: nil, fill: b.color))
            o.append(.text(b.label, at: Pt(x + 10, 126.5), size: 6.5, color: RGBA(hex: 0x5B6B82)))
            x += 36
        }
        return Sketch(width: W, height: H, ops: o)
    }
}
