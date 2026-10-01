import Foundation
import TCRoofCore

/// Survey sections (B, C, D) as report units.
extension ReportLayout {
    // MARK: sections

    func two(_ title: String, _ l: Photo?, _ lt: String, right r: Photo?, _ rt: String, detail: String? = nil,
             infoL: ((Double, inout [DrawOp]) -> Void)?, infoR: ((Double, inout [DrawOp]) -> Void)?, photoH: Double = 170, infoH: Double = 36) -> Unit {
        let W = Self.cw, half = W / 2, hasInfo = infoL != nil || infoR != nil
        let h = Self.band + photoH + (hasInfo ? infoH : 0)
        var o = box(title, height: h)
        o += photoCell(l, label: lt, x: 0, y: Self.band, w: half, h: photoH)
        if r != nil || detail == nil { o += photoCell(r, label: rt, x: half, y: Self.band, w: half, h: photoH) }
        else {
            o.append(.textBox(rt, Box(half + 4, Self.band + 2, half - 8, 12), size: 7.5))
            o.append(.line(Pt(half, Self.band + 15), Pt(W, Self.band + 15), width: 0.5, color: .black))
            o.append(.textBox(detail ?? "", Box(half + 6, Self.band + 20, half - 12, photoH - 24), size: 8.5, color: .blue))
        }
        o.append(.line(Pt(half, Self.band), Pt(half, h), width: 0.5, color: .black))
        if hasInfo {
            let y = Self.band + photoH
            o.append(.line(Pt(0, y), Pt(W, y), width: 0.5, color: .black))
            var a: [DrawOp] = [], b: [DrawOp] = []
            infoL?(y, &a); infoR?(y, &b)
            o += a; o += translate(b, dx: half, dy: 0)
        }
        return Unit(h: h, ops: o)
    }

    func moduleUnits(_ mod: SurveyModule) -> [Unit] {
        let d = mod.values, spec = mod.spec, half = Self.cw / 2
        let named = mod.name.isEmpty ? "" : " " + mod.name
        let ofBuilding = mod.name.isEmpty ? "" : " ของอาคาร" + mod.name
        let firstDetail = Fill.lines(d.text("detail")).first ?? ""
        let detailLine: (Double, inout [DrawOp]) -> Void = { y, o in _ = field("รายละเอียดเพิ่มเติม", firstDetail, x: 6, y: y + 12, valueWidth: half - 90, ops: &o) }
        switch mod.type {
        case .panel:
            let link = BuildingPanels.linked(mod, in: job)
            var unit = two(spec.reportTitle + named, d.photo("photoBreaker"), "ภาพถ่ายเบรกเกอร์เมนของตู้ไฟฟ้า", right: d.photo("photoWide"), "ภาพถ่ายมุมกว้างของตู้ไฟฟ้า (เพื่อพิจารณาจุดเชื่อมต่อระบบโซล่าเซลล์)",
                        infoL: { y, o in
                            _ = field("ขนาดเบรกเกอร์เมน", d.text("breakerAT") + (d.text("breakerAT").isEmpty ? "" : " AT"), x: 6, y: y + 11, valueWidth: 90, ops: &o)
                            let nx = field("ปริมาณการใช้ไฟ (kW)", d.text("loadKW"), x: 6, y: y + 26, valueWidth: 60, ops: &o)
                            _ = field("เวลา", d.text("loadTime"), x: nx, y: y + 26, valueWidth: 50, ops: &o) },
                        infoR: { y, o in
                            detailLine(y, &o)
                            if let link { _ = field("ตู้ใน A3", "\(link.boardName) · \(link.cbText)", x: 6, y: y + 26, valueWidth: half - 60, ops: &o) } })
            // the PV connection point marked on the wide photo, in the same fitted rect as the photo
            if let p = d.photo(BuildingPanels.Key.photoWide), var pt = d.shapes(BuildingPanels.Key.pvPoint).first {
                pt.label = BuildingPanels.pointLabel(d)
                let area = Box(half, Self.band + 15, half, 170 - 15).inset(4).fit(Double(p.width), Double(p.height))
                unit.ops += SiteShapes.ops([pt], in: area, metersAcross: nil)
            }
            return [unit]
        case .inverter where InverterStation.isDesigned(d):
            return inverterStation(mod)
        case .inverter:
            let n = d.number("inverterCount")
            let need = n.map { "\(fmt($0)) เครื่อง → \(String(format: "%.2f", 1.5 * $0 + 1.5)) x 2.00 ม." } ?? ""
            return [two(spec.reportTitle + ofBuilding, d.photo("photoArea"), "ภาพถ่ายพื้นที่ติดตั้ง Inverter Station", right: d.photo("photoDetail"), "รายละเอียด", detail: d.text("detail"),
                        infoL: { y, o in
                            _ = field("ขนาดพื้นที่ติดตั้ง (ก x ย x ส)", d.text("sizeLWH"), x: 6, y: y + 11, valueWidth: 100, ops: &o)
                            o.append(.textBox("**ยาว = (1.5 x จำนวนอินเวอร์เตอร์) + 1.5 เมตร กว้าง 2 เมตร", Box(6, y + 19, half - 12, 14), size: 7)) },
                        infoR: { y, o in _ = field("พื้นที่ที่ต้องการ", need, x: 6, y: y + 11, valueWidth: half - 80, ops: &o)
                            if d.photo("photoDetail") != nil { o.append(.textBox(firstDetail, Box(6, y + 20, half - 12, 14), size: 8, color: .blue)) } })]
        case .water:
            return [two(spec.reportTitle + ofBuilding, d.photo("photoArea"), "ภาพถ่ายพื้นที่ติดตั้ง", right: d.photo("photoWide"), "ภาพถ่ายมุมกว้างของพื้นที่ติดตั้ง",
                        infoL: { y, o in o += checks(["ติดตั้งระบบน้ำใหม่", "ติดตั้งร่วมกับระบบน้ำเดิม"], chosen: { d.choice("waterMode") == $0 }, x: 6, y: y + 4, width: half - 12).0 },
                        infoR: detailLine)] + waterPointUnit(mod)
        case .backfeed:
            return [two(spec.reportTitle + ofBuilding, d.photo("photoArea"), "ภาพถ่ายพื้นที่ติดตั้ง", right: d.photo("photoDetail"), "รายละเอียด", detail: d.text("detail"),
                        infoL: { y, o in
                            o += checks(["กันย้อนที่แรงต่ำ", "กันย้อนที่แรงสูง"], chosen: { d.choice("level") == $0 }, x: 6, y: y + 2, width: half - 12).0
                            o += checks(["เสาเดิม", "เสาใหม่"], chosen: { d.choice("pole") == $0 }, x: 6, y: y + 18, width: half - 12).0 },
                        infoR: { y, o in _ = field("รายละเอียดเพิ่มเติม", d.photo("photoDetail") != nil ? firstDetail : "", x: 6, y: y + 12, valueWidth: half - 90, ops: &o) },
                        photoH: 240)]
        case .fts:
            return [two(spec.reportTitle + ofBuilding, d.photo("photoFTS"), "ภาพถ่ายพื้นที่ติดตั้งตู้ FTS", right: d.photo("photoEmg"), "ภาพถ่ายพื้นที่ติดตั้งปุ่ม Emergency",
                        infoL: d.text("detail").isEmpty ? nil : detailLine, infoR: nil, photoH: 150)] + emergencyPointUnit(mod)
        case .roof, .tank: return planSection(mod)
        case .sed: return sed(mod)
        case .house, .roofForm: return formSection(mod)
        }
    }

    /// B3's water point on the A2 picture, with A2's drawings and symbols, ringed and named by the water mode.
    func waterPointUnit(_ mod: SurveyModule) -> [Unit] {
        guard let m = WaterPoint.mark(job, module: mod.id) else { return [] }
        return pointUnit(mod, m, title: "ตำแหน่งจุดจ่ายน้ำ (ภาพ A2)", label: WaterPoint.mode(mod.values)?.pinLabel ?? "จุดจ่ายน้ำ", color: Self.waterBlue)
    }
    /// B5's FTS switch on the A2 picture.
    func emergencyPointUnit(_ mod: SurveyModule) -> [Unit] {
        guard let m = EmergencyButton.mark(job, module: mod.id) else { return [] }
        return pointUnit(mod, m, title: "ตำแหน่งปุ่ม FTS switch (ภาพ A2)", label: "FTS switch", color: MarkKind.emergency.color)
    }
    /// A section's point on the A2 picture, ringed, with its name in a pill below.
    func pointUnit(_ mod: SurveyModule, _ m: MapMark, title: String, label: String, color: RGBA) -> [Unit] {
        guard let p = j.photo("siteMap") else { return [] }
        let W = Self.cw, picH = 260.0, h = Self.band + picH + 8
        var o = box(title + (mod.name.isEmpty ? "" : " " + mod.name), height: h)
        let pic = Box(6, Self.band + 4, W - 12, picH).fit(Double(p.width), Double(p.height))
        o.append(.photo(p, pic))
        o += siteDrawing(in: pic)
        let c = Pt(pic.x + m.x * pic.w, pic.y + m.y * pic.h), R = max(6, pic.w * 0.019)
        o.append(.circle(c, r: R * 1.6, stroke: color, fill: nil, width: 2))
        let fs = 7.5, tw = ApproxText.width(label, size: fs, bold: true) + 10
        let tag = Box(c.x - tw / 2, c.y + R * 1.8, tw, 12)
        o.append(.rect(tag, stroke: nil, fill: color))
        o.append(.text(label, at: Pt(c.x, tag.y + 6), size: fs, bold: true, color: .white, align: .center))
        return [Unit(h: h, ops: o)]
    }
    static let waterBlue = RGBA(hex: 0x1F6FB5)

    /// C1 section A-A across the full width, titled with the frame type; replaces the generic truss diagram.
    func roofSectionUnit(_ d: Values) -> Unit {
        let W = Self.cw, sec = RoofSection(d).sketch, k = (W - 16) / sec.width, h = Self.band + 6 + sec.height * k + 4
        var o = box("รูปตัด A-A · " + Roof.frame(d).title + " (หน่วย ม.)", height: h)
        o += sec.translated(8, Self.band + 6, scale: k)
        return Unit(h: h, ops: o)
    }

    func planSection(_ mod: SurveyModule) -> [Unit] {
        let d = mod.values, tank = mod.type == .tank, W = Self.cw
        let title = mod.spec.reportTitle + (mod.name.isEmpty ? "" : " " + mod.name)
        var U: [Unit] = []
        // plan
        var body: [DrawOp] = [], bh: Double
        if let p = d.photo("planPhoto") { bh = 260; body.append(.photo(p, Box(8, 0, W - 16, bh))) }
        else if let sk = Drawings.plan(d, tank: tank, width: 690) {
            let k = (W - 16) / sk.width; bh = sk.height * k
            body += sk.translated(8, 0, scale: k)
        } else { bh = 90; body.append(.text("— ยังไม่ได้กรอกระยะ —", at: Pt(W / 2, 45), size: 9, color: .faint, align: .center)) }
        let panelsH = 32.0, tankH = tank ? 36.0 : 0
        let h = Self.band + panelsH + bh + 10 + tankH
        var o = box(title, height: h)
        let pb = d.text("panelsBefore"), pc = d.text("panelsCut")
        o.append(.text("จำนวนแผงก่อนเข้าสำรวจ \(pb.isEmpty ? "-" : pb) แผง", at: Pt(W / 2, Self.band + 9), size: 9, bold: true, align: .center))
        o.append(.text("จำนวนแผงที่ตัดออกหลังสำรวจ \(pc.isEmpty ? "-" : pc) แผง", at: Pt(W / 2, Self.band + 23), size: 9, bold: true, align: .center))
        o += translate(body, dx: 0, dy: Self.band + panelsH)
        if tank {
            let y = h - tankH
            o.append(.line(Pt(0, y), Pt(W, y), width: 0.5, color: .black))
            var x = field("ความสูงของถังน้ำใส", d.text("tankHeight").isEmpty ? "" : d.text("tankHeight") + " M", x: 6, y: y + 10, valueWidth: 50, ops: &o)
            x = field("ผิวของถังน้ำใส", d.text("surface"), x: x, y: y + 10, valueWidth: 70, ops: &o)
            _ = field("กรณีมีดินกลบ ชั้นดินลึก", d.text("soilDepth").isEmpty ? "" : d.text("soilDepth") + " M", x: x, y: y + 10, valueWidth: 50, ops: &o)
            let ty = d.choice("tankType").map { $0 == "อื่นๆ" ? d.other("tankType") : $0 } ?? ""
            x = field("ชนิดถัง", ty, x: 6, y: y + 26, valueWidth: 50, ops: &o)
            x = field("ตำแหน่งถัง", d.choice("tankPos") ?? "", x: x, y: y + 26, valueWidth: 50, ops: &o)
            _ = field("เงาบัง", Schema.shadeText(d).map { $0 == "ไม่มีเงาบัง" ? "ไม่มี" : String($0.dropFirst("เงาบัง".count)).trimmingCharacters(in: CharacterSet(charactersIn: ": ")) } ?? "", x: x, y: y + 26, valueWidth: W - x - 60, ops: &o)
        }
        o.append(.text(tank ? "* ระบุตำแหน่งสิ่งกีดขวางบนถังน้ำใส เช่น ปล่องระบายอากาศ ช่องเซอร์วิส ท่อ เสาสัญญาณ" : "* ระบุตำแหน่งเสาและระยะสำหรับโครงสร้างหลังคา", at: Pt(0, h + 8), size: 7.5, color: .tag))
        U.append(Unit(h: h + 14, ops: o))

        if !tank && Roof.hasFrame(d) {
            U.append(roofSectionUnit(d))
        }
        if !tank {
            // structure: truss + component table + option rows (a C1 frame type names the rows and draws section A-A above)
            let framed = Roof.hasFrame(d), names = framed ? Roof.frame(d).members.map(\.name) : Options.components
            let tableW = 250.0, rowH = 15.0, th = Self.band + 10 + rowH * 8 + 8
            var s = box("โครงสร้าง", height: th)
            let tx = framed ? (W - tableW) / 2 : W - tableW - 8, ty = Self.band + 8
            if !framed {
                s.append(.text("แนะนำองค์ประกอบของหลังคา", at: Pt(8, Self.band + 10), size: 7.5))
                let tr = Drawings.truss(width: W - tableW - 30)
                s += tr.translated(8, Self.band + 18)
            }
            let cols: [Double] = [22, 60, tableW - 82]
            for r in 0...7 {
                let y = ty + Double(r) * rowH
                var x = tx
                for (ci, cwid) in cols.enumerated() {
                    s.append(.rect(Box(x, y, cwid, rowH), stroke: .black, fill: r == 0 ? .band : nil, width: 0.5))
                    let txt: String
                    if r == 0 { txt = ["", "องค์ประกอบ", "รายละเอียด"][ci] }
                    else { let v = d.text("comp\(r)"); txt = [String(r), names[r - 1], v.isEmpty ? "-" : v][ci] }
                    s.append(.textBox(txt, Box(x + 2, y + 2, cwid - 4, rowH - 2), size: 7.5, bold: ci == 2 && r > 0, align: .center))
                    x += cwid
                }
            }
            U.append(Unit(h: th, ops: s))
            var c: [DrawOp] = [], cy = 0.0
            for (label, id, opts) in [("**1.รูปแบบหลังคา", "roofShape", Options.roofShape), ("**2.วัสดุมุงหลังคา", "roofMaterial", Options.roofMaterial), ("**3.ชนิดโครงสร้างหลังคา", "roofStructure", Options.structure)] {
                c.append(.text(label, at: Pt(0, cy + 7), size: 8.5, bold: true))
                let (ops, hh) = checks(opts, chosen: { d.choice(id) == $0 }, extra: { $0 == "อื่นๆ" ? d.other(id) : "" }, x: 120, y: cy - 1.5, width: W - 120)
                c += ops; cy += hh
            }
            U.append(Unit(h: cy, ops: c))
            if let a = d.photo("aerialPhoto") { U += grid(title, [(a, nil)], cellH: 330, columns: 1) }
            U += grid("โครงสร้าง", d.photos("structPhotos").map { ($0, nil) })
            U += grid(title + " — ภาพเพิ่มเติม", d.photos("generalPhotos").map { ($0, nil) })
        } else {
            let ob = d.photos("obstPhotos"), list = d.obstacles("obst")
            let imgH = ob.isEmpty ? 90.0 : 250, tableH = list.isEmpty ? 0 : Double(list.count + 1) * 15 + 8
            let h2 = Self.band + 15 + imgH + tableH
            var s = box("สิ่งกีดขวาง", height: h2)
            s.append(.text("สำหรับวาดขนาดของสิ่งกีดขวาง", at: Pt(8, Self.band + 8), size: 8, bold: true))
            if let p = ob.first { s.append(.photo(p, Box(60, Self.band + 16, W - 120, imgH - 8))) }
            if !list.isEmpty {
                let cols: [Double] = [W - 16 - 240, 120, 120], y0 = Self.band + 15 + imgH
                for r in 0...list.count {
                    var x = 8.0
                    for (ci, cwid) in cols.enumerated() {
                        let y = y0 + Double(r) * 15
                        s.append(.rect(Box(x, y, cwid, 15), stroke: .black, fill: r == 0 ? .band : nil, width: 0.5))
                        let t: String
                        if r == 0 { t = ["สิ่งกีดขวาง", "ตำแหน่ง X, Y (ม.)", "ขนาด ก x ย (ม.)"][ci] }
                        else { let q = list[r - 1]; t = [q.label.isEmpty ? "-" : q.label, "\(q.x), \(q.y)", "\(q.w) x \(q.h)"][ci] }
                        s.append(.textBox(t, Box(x + 2, y + 2, cwid - 4, 13), size: 7.5, align: ci == 0 ? .left : .center))
                        x += cwid
                    }
                }
            }
            s.append(.text("รูปภาพเพิ่มเติม: *รูปมุมสูง/รูปโดรน  *รูปสิ่งกีดขวาง  *รูปข้างถัง (สำหรับทางเดินรางสายไฟ)", at: Pt(0, h2 + 9), size: 8))
            U.append(Unit(h: h2 + 16, ops: s))
            if let a = d.photo("aerialPhoto") { U += grid(title, [(a, nil)], cellH: 330, columns: 1) }
            U += grid("สิ่งกีดขวาง", ob.dropFirst().map { ($0, nil) })
            U += grid(title + " — รูปข้างถัง / รูปเพิ่มเติม", d.photos("sidePhotos").map { ($0, nil) })
        }
        return U
    }

    func sed(_ mod: SurveyModule) -> [Unit] {
        let d = mod.values, W = Self.cw, named = mod.name.isEmpty ? "" : " " + mod.name
        let title = mod.spec.reportTitle + named
        var U = grid("ภาพบ่อตกตะกอน (Google Earth/Google Map)" + named, d.photos("sitePhotos").map { ($0, nil) })
        let rowH = 15.0, imgH = 270.0, h = Self.band + imgH + rowH * 7 + 6
        var o = box("โครงสร้างบ่อตกตะกอน" + named, height: h)
        if let p = d.photo("drawing") { o.append(.photo(p, Box(8, Self.band + 6, W - 16, imgH - 12))) }
        let cols: [Double] = [30, W / 2 - 90, 60, 30, W / 2 - 90, 60], y0 = Self.band + imgH
        for r in 0...6 {
            var x = 0.0
            for (ci, cwid) in cols.enumerated() {
                let y = y0 + Double(r) * rowH
                o.append(.rect(Box(x, y, cwid, rowH), stroke: .black, fill: r == 0 ? .band : nil, width: 0.5))
                var t = ""
                if r == 0 { t = ["ระยะ", "องค์ประกอบ", "ซม.", "ระยะ", "องค์ประกอบ", "ซม."][ci] }
                else if let dim = Options.sedDims[safe: (ci < 3 ? r - 1 : r + 5)] { t = [dim.0, dim.1, d.text("dist" + dim.0)][ci % 3] }
                o.append(.textBox(t, Box(x + 2, y + 2, cwid - 4, rowH - 2), size: 7.5, bold: ci % 3 == 2 && r > 0, align: ci % 3 == 1 ? .left : .center))
                x += cwid
            }
        }
        U.append(Unit(h: h, ops: o))
        U += grid(title + " — ภาพถ่ายมุมสูง", [(d.photo("aerialPhoto"), nil)], cellH: 330, columns: 1)
        U += grid(title + " — ภาพถ่ายแต่ละด้าน", [(d.photo("pFront"), "ด้านหน้า"), (d.photo("pBack"), "ด้านหลัง"), (d.photo("pLeft"), "ด้านซ้าย"), (d.photo("pRight"), "ด้านขวา")])
        U += grid("ภาพถ่ายสิ่งกีดขวางหรือบริเวณที่ไม่สามารถติดตั้งระบบได้", [(d.photo("obstPhoto"), nil)])
        return U
    }

    /// House / roof-form sections: numbered question tables like the paper form, then all photos.
    func formSection(_ mod: SurveyModule) -> [Unit] {
        let d = mod.values, W = Self.cw, labelW = 190.0, unitW = 44.0, valW = W - labelW - unitW
        var U: [Unit] = [], photos: [(Photo?, String?)] = []
        for g in mod.spec.groups {
            for f in g.fields { if case .photo = f.kind, let p = d.photo(f.id) { photos.append((p, (g.no.map { "ข้อ \($0) · " } ?? "") + f.label)) } }
            let rows = g.fields.filter { f in
                guard f.countable, f.isVisible(d) else { return false }
                switch f.kind { case .photo, .photos, .signature: return false; default: return true }
            }
            if rows.isEmpty { continue }
            var o: [DrawOp] = [], y = Self.band
            for f in rows {
                var cell: [DrawOp] = [], rh: Double
                var unit = ""
                switch f.kind {
                case .choice(let opts, _):
                    let (ops, hh) = checks(opts, chosen: { d.choice(f.id) == $0 }, extra: { $0 == "อื่นๆ" ? d.other(f.id) : "" }, x: labelW + 6, y: y + 1, width: valW - 12, size: 8)
                    cell = ops; rh = hh + 2
                case .number(let u):
                    unit = u; rh = 17
                    cell = [.text(d.text(f.id).isEmpty ? "—" : d.text(f.id), at: Pt(labelW + 6, y + 8.5), size: 8.5, bold: true, color: d.text(f.id).isEmpty ? .faint : .blue)]
                default:
                    let t = f.displayText(d)
                    rh = max(17, m.height(t.isEmpty ? "—" : t, width: valW - 12, size: 8.5, bold: true) + 5)
                    cell = [.textBox(t.isEmpty ? "—" : t, Box(labelW + 6, y + 3, valW - 12, rh - 4), size: 8.5, bold: true, color: t.isEmpty ? .faint : .blue)]
                }
                let lh = m.height(f.label, width: labelW - 10, size: 8, bold: false) + 5
                rh = max(rh, lh)
                o.append(.rect(Box(0, y, labelW, rh), stroke: .black, fill: RGBA(hex: 0xF4F8F1), width: 0.5))
                o.append(.rect(Box(labelW, y, valW, rh), stroke: .black, fill: nil, width: 0.5))
                o.append(.rect(Box(labelW + valW, y, unitW, rh), stroke: .black, fill: nil, width: 0.5))
                o.append(.textBox(f.label, Box(5, y + 3, labelW - 10, rh - 4), size: 8))
                o += cell
                o.append(.text(unit, at: Pt(labelW + valW + unitW / 2, y + rh / 2), size: 8, align: .center))
                y += rh
            }
            let title = (g.no.map { $0 + ". " } ?? "") + (g.title ?? "") + (mod.name.isEmpty ? "" : " — " + mod.name)
            U.append(Unit(h: y, ops: box(title, height: y, left: true) + o))
        }
        if mod.type == .house, let n = d.number("inverterCount"), n > 0 {
            U.append(Unit(h: 12, ops: [.text("ข้อ 18: อินเวอร์เตอร์ \(fmt(n)) เครื่อง ต้องการพื้นที่ยาว \(String(format: "%.2f", 1.5 * n + 1.5)) ม. กว้าง 2.00 ม.", at: Pt(0, 6), size: 8, color: .tag)]))
        }
        U += grid("ภาพถ่ายประกอบ — " + mod.spec.reportTitle + (mod.name.isEmpty ? "" : " " + mod.name), photos)
        return U
    }
}
