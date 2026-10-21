import Foundation

/// Drawings of the roof PV layout beyond the plan (docs/specs/roof-pv-layout.md §4 and §5.4).
public enum RoofMountDrawings {
    public static let width = 760.0, height = 250.0
    static let ink = RGBA(hex: 0x111111), muted = RGBA(hex: 0x6B7280), module = RGBA(hex: 0x1F4F8F), rail = RGBA(hex: 0x334155)
    static let purlin = RGBA(hex: 0x9CA3AF), ok = RGBA(hex: 0x2E7D32), bad = RGBA(hex: 0xB42318), dim = RGBA(hex: 0x1D4ED8)

    /// Whether a row passes the standard: both rails on a purlin (or rib clamps), each inside the clamping zone.
    public static func rowPasses(_ row: RoofMountLayout.Row, in layout: RoofMountLayout) -> Bool {
        let s = layout.standard, l = s.moduleLength
        let zone = (s.clampMin - 1e-6)...(s.clampMax + 1e-6)
        if layout.options.freeRows { return true }
        let onPurlins = layout.purlins.contains { abs($0 - row.rails.0) < 1e-6 } && layout.purlins.contains { abs($0 - row.rails.1) < 1e-6 }
        return onPurlins && zone.contains(row.rails.0 - row.v) && zone.contains(row.v + l - row.rails.1)
    }

    /// One row along the slope (§5.4): the sheet, purlins, L-feet, rails and module, with the module length, both
    /// clamp distances, rail to rail and the purlin spacing dimensioned, and the check line.
    public static func rowSection(_ layout: RoofMountLayout, face: Int, row r: Int) -> Sketch {
        var o: [DrawOp] = []
        guard layout.faces.indices.contains(face), layout.faces[face].rows.indices.contains(r) else {
            o.append(.text("ยังไม่มีแถวแผงบนด้านนี้", at: Pt(width / 2, height / 2), size: 15, color: muted, align: .center))
            return Sketch(width: width, height: height, ops: o)
        }
        let f = layout.faces[face], row = f.rows[r], s = layout.standard, l = s.moduleLength
        let from = row.v - 0.7, to = row.v + l + 0.7
        let k = (width - 80) / (to - from)
        func x(_ v: Double) -> Double { 40 + (v - from) * k }
        let sheetY = 150.0, footH = 18.0, railH = 8.0, modH = 9.0
        let railTop = sheetY - footH - railH, modY = railTop - modH

        // sheet and purlins
        o.append(.line(Pt(x(from), sheetY), Pt(x(to), sheetY), width: 2.4, color: ink))
        for p in layout.purlins where p >= from && p <= to {
            o.append(.rect(Box(x(p) - 7, sheetY + 1.5, 14, 22), stroke: purlin, fill: RGBA(hex: 0xE5E7EB), width: 1))
        }
        // feet, rails, module
        for at in [row.rails.0, row.rails.1] {
            o.append(.rect(Box(x(at) - 3, sheetY - footH, 6, footH), stroke: nil, fill: RGBA(hex: 0x64748B)))
            o.append(.rect(Box(x(at) - 7, railTop, 14, railH), stroke: rail, fill: RGBA(hex: 0xCBD5E1), width: 1))
        }
        o.append(.rect(Box(x(row.v), modY, l * k, modH), stroke: RGBA(hex: 0xDCE6F2), fill: module, width: 1))

        // dimensions
        func dimension(_ a: Double, _ b: Double, _ y: Double, _ label: String) {
            o.append(.line(Pt(x(a), y), Pt(x(b), y), width: 1, color: dim))
            for v in [a, b] { o.append(.line(Pt(x(v), y - 5), Pt(x(v), y + 5), width: 1, color: dim)) }
            o.append(.text(label, at: Pt((x(a) + x(b)) / 2, y - 9), size: 12, bold: true, color: dim, align: .center))
        }
        func m(_ d: Double) -> String { String(format: "%.2f", d) }
        dimension(row.v, row.v + l, modY - 26, "แผงยาว " + m(l))
        dimension(row.v, row.rails.0, modY - 4, m(row.rails.0 - row.v))
        dimension(row.rails.1, row.v + l, modY - 4, m(row.v + l - row.rails.1))
        dimension(row.rails.0, row.rails.1, sheetY + 40, "รางห่าง " + m(row.rails.1 - row.rails.0))
        let ps = layout.purlins.filter { $0 >= from && $0 <= to }
        if !layout.options.freeRows, ps.count >= 2 {
            dimension(ps[0], ps[1], sheetY + 64, "แป @" + m(ps[1] - ps[0]))
        }

        // captions
        let face0 = f.face
        o.append(.text("รูปตัดแถว \(r + 1) | ด้าน\(RoofFace.direction(face0.azimuth)) | ตามแนวลาด (หน่วย ม.)", at: Pt(40, 18), size: 13,
                       bold: true, color: ink))
        let pass = rowPasses(row, in: layout)
        let how = layout.options.tileHooks ? "ขอเกี่ยวกระเบื้องยึดจันทัน @" + m(s.rafterSpacing) + " | รางที่ ¼ และ ¾ ของแผง"
            : layout.options.ribClamp ? "จับสันลอนที่ ¼ และ ¾ ของแผง"
            : "รางตกแปทั้ง 2 เส้น | ช่วงจับ \(m(s.clampMin))–\(m(s.clampMax)) ม. จากปลายแผง"
        o.append(.text((pass ? "ถูกต้องตามมาตรฐาน | " : "ไม่ผ่าน | ") + how, at: Pt(40, height - 18), size: 12.5, bold: true,
                       color: pass ? ok : bad))
        return Sketch(width: width, height: height, ops: o)
    }
}
