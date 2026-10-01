import Foundation
import TCRoofCore

/// B2 inverter station filled on the wide page.
extension ReportLayout {
    /// B2 filled on the wide page: area and boundary photos, the station plan, and the equipment chosen from the catalog.
    func inverterStation(_ mod: SurveyModule) -> [Unit] {
        let d = mod.values, W = Self.cw, half = W / 2, s = InverterStation(d)
        let ofBuilding = mod.name.isEmpty ? "" : " ของอาคาร" + mod.name
        var photos = two(mod.spec.reportTitle + ofBuilding, d.photo("photoArea"), "ภาพถ่ายพื้นที่ติดตั้ง Inverter Station", right: d.photo("photoDetail"), "ภาพระบุขอบเขตพื้นที่",
                         infoL: { y, o in _ = field("ขนาดพื้นที่ติดตั้ง (ก x ย x ส)", d.text("sizeLWH") + (d.text("sizeLWH").isEmpty ? "" : " ม."), x: 6, y: y + 11, valueWidth: 110, ops: &o) },
                         infoR: { y, o in _ = field("ตำแหน่งติดตั้ง", s.site.label, x: 6, y: y + 11, valueWidth: half - 90, ops: &o) })
        // the boundary drawn on the second photo, in the same fitted rect as the photo
        if let p = d.photo("photoDetail"), !d.shapes(InverterStation.Key.boundary).isEmpty {
            let area = Box(half, Self.band + 15, half, 170 - 15).inset(4).fit(Double(p.width), Double(p.height))
            photos.ops += SiteShapes.ops(d.shapes(InverterStation.Key.boundary), in: area, metersAcross: nil)
        }
        // plan
        let sk = InverterStationDrawing.sketch(s), k = (W - 16) / sk.width, planH = Self.band + sk.height * k + 8
        let planTitle = s.site == .outdoor ? "แปลน Inverter Station" : "แปลนติดตั้งในอาคาร (Top view)"
        let plan = Unit(h: planH, ops: box(planTitle + (mod.name.isEmpty ? "" : " " + mod.name), height: planH) + sk.translated(8, Self.band + 4, scale: k))
        // equipment table
        let rh = 14.0, cols: [(String, Double)] = [("ที่", 24), ("อินเวอร์เตอร์", 190), ("kW", 50), ("CB", 90), ("สาย AC", W - 354)]
        var o: [DrawOp] = [], y = Self.band
        func row(_ cells: [String], bold: Bool = false, fill: RGBA? = nil) {
            if let fill { o.append(.rect(Box(0, y, W, rh), stroke: nil, fill: fill)) }
            var x = 0.0
            for (i, c) in cells.enumerated() {
                o.append(.text(c, at: Pt(x + 5, y + rh / 2), size: 8.5, bold: bold, color: bold ? .black : .blue))
                x += cols[i].1
            }
            y += rh
            o.append(.line(Pt(0, y), Pt(W, y), width: 0.4, color: .rule))
        }
        row(cols.map(\.0), bold: true, fill: .band)
        for (i, kw) in s.sizes.enumerated() {
            let inv = s.catalog.inverter(kw: kw), cb = s.breaker(kw: kw)
            row(["\(i + 1)", [inv.brand, inv.model].filter { !$0.isEmpty }.joined(separator: " "), "\(kw)", "\(cb.at)AT / \(cb.af)AF", s.cable(kw: kw).label])
        }
        let cap = s.capacityCheck(j.number("capacity")), fd = s.feeder
        let lines: [(String, String, Bool)] = [
            ("กำลังรวม", "\(s.sizesText) = \(s.totalKW) kW" + (cap.map { " " + $0.text } ?? ""), cap?.ok ?? true),
            ("CB อินเวอร์เตอร์", s.breakerSummary, true),
            ("Feeder AC-DB → จุดเชื่อม", "\(fd.at) AT · \(fd.label)", true),
            ("Tray อินเวอร์เตอร์ → AC-DB", "\(s.trayWidth) มม. (ขั้นต่ำ \(s.trayMin))", true),
            ("Ladder ออกจาก AC-DB", "\(s.ladderWidth) มม. (ขั้นต่ำ \(fd.ladderMin))", true),
            (s.site == .outdoor ? "ห้องขั้นต่ำ" : "ผนังยาวขั้นต่ำ", s.minimumText.components(separatedBy: "ขั้นต่ำ ").last ?? "", s.fits),
            ("ทางเดินหน้าตู้", String(format: "%.2f ม. ", s.walkway) + (s.walkwayOK ? "✓" : "✗ แคบกว่า 1.2 ม."), s.walkwayOK)]
        for (label, value, ok) in lines {
            o.append(.text(label, at: Pt(6, y + rh / 2), size: 8.5))
            o.append(.text(value, at: Pt(170, y + rh / 2), size: 8.5, bold: true, color: ok ? .blue : .red))
            y += rh
        }
        o.append(.text(s.status + " · แคตตาล็อกอุปกรณ์ \(s.catalog.version)", at: Pt(W - 6, y + 6), size: 7, color: s.isOK ? .ink2 : .red, align: .right))
        y += 14
        let table = Unit(h: y, ops: box("อุปกรณ์ที่คำนวณจากแคตตาล็อก", height: y, left: true) + o)
        return [photos, plan, table]
    }
}
