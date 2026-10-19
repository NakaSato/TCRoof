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
                        photoH: 240)] + backfeedMoreUnit(mod)
        case .fts:
            return [two(spec.reportTitle + ofBuilding, d.photo("photoFTS"), "ภาพถ่ายพื้นที่ติดตั้งตู้ FTS", right: d.photo("photoEmg"), "ภาพถ่ายพื้นที่ติดตั้งปุ่ม Emergency",
                        infoL: d.text("detail").isEmpty ? nil : detailLine, infoR: nil, photoH: 150)] + emergencyPointUnit(mod)
        case .roof, .tank: return planSection(mod)
        case .sed: return sed(mod)
        case .house, .roofForm: return formSection(mod)
        }
    }

    /// B4's third and fourth photos (docs/ui/survey-b4), labelled by the level; nothing for a job without them.
    func backfeedMoreUnit(_ mod: SurveyModule) -> [Unit] {
        let d = mod.values, keys = Array(ZeroExport.photoKeys.dropFirst(2))
        guard keys.contains(where: { d.photo($0) != nil }) else { return [] }
        let hv = ZeroExport.isHV(d), board = ZeroExport.boardName(SingleLine.build(job))
        let ofBuilding = mod.name.isEmpty ? "" : " ของอาคาร" + mod.name
        return [two(mod.spec.reportTitle + ofBuilding + " (ต่อ)", d.photo(keys[0]), ZeroExport.photoLabel(2, hv: hv, board: board),
                    right: d.photo(keys[1]), ZeroExport.photoLabel(3, hv: hv, board: board), infoL: nil, infoR: nil, photoH: 200)]
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

    /// แปลนวางแผงบนหลังคา (docs/specs/roof-pv-layout.md §7): the automatic layout on the C1 plan with its summary, the
    /// faces, the BOQ and the assumptions, then the first row's section as detail A.
    func roofPVUnits(_ d: Values) -> [Unit] {
        guard RoofMount.printable(d) else { return [] }
        let lat = RoofMount.latitude(gps: j.text("gps"))
        let m = RoofMount.layout(d, latitude: lat).layout, q = m.quantities
        guard q.modules > 0 else { return [] }
        let W = Self.cw, plan = RoofPlan(d, mode: .pv, mount: m).sketch, k = (W - 16) / plan.width
        let used = m.faces
        let lineH = 11.0, faceRows = Double(used.count)
        let assumed = RoofMount.assumptions(d, latitude: lat)
        let textH = 10 + lineH * (3 + faceRows) + (assumed.isEmpty ? 0 : lineH) + lineH + 6
        let h = Self.band + 6 + plan.height * k + textH
        var o = box("แปลนวางแผงบนหลังคา (หน่วย ม.)", height: h)
        o += plan.translated(8, Self.band + 6, scale: k)
        var y = Self.band + 6 + plan.height * k + 10
        o.append(.text(RoofMount.summaryLine(m), at: Pt(8, y), size: 8.5, bold: true)); y += lineH
        for f in used {
            let face = f.face
            let t = "ด้าน\(RoofFace.direction(face.azimuth)) \(Int(face.azimuth.rounded()))° · ลาด " + String(format: "%.0f°", face.tilt * 180 / .pi)
                + " · \(Int(f.yield.rounded())) kWh/kWp · \(f.modules) แผง" + (f.used ? "" : " (ไม่วาง)") + (f.cuts > 0 ? " · ตัด \(f.cuts)" : "")
            o.append(.text(t, at: Pt(14, y), size: 8, color: f.used ? .black : .tag)); y += lineH
        }
        o.append(.text(RoofMount.boqLine(q), at: Pt(8, y), size: 8)); y += lineH
        o.append(.text(RoofMount.loadLine(q), at: Pt(8, y), size: 8, bold: q.overLoad, color: q.overLoad ? .tag : .black)); y += lineH
        if !assumed.isEmpty { o.append(.text("ค่าสมมติ: " + assumed.joined(separator: " · "), at: Pt(8, y), size: 7.5, color: .tag)); y += lineH }
        o.append(.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง · ตรวจน้ำหนักบรรทุกของโครงหลังคากับวิศวกรโครงสร้าง", at: Pt(8, y), size: 7.5, color: .faint))
        var out = [Unit(h: h, ops: o)]
        // detail A: the first row of the first face in use, along the slope
        if let fi = m.faces.firstIndex(where: { $0.used && !$0.rows.isEmpty }) {
            let sec = RoofMountDrawings.rowSection(m, face: fi, row: 0), ks = (W - 16) / sec.width
            let sh = Self.band + 6 + sec.height * ks + 4
            var s = box("รายละเอียด A · รูปตัดแถวแผงตามแนวลาด (หน่วย ม.)", height: sh)
            s += sec.translated(8, Self.band + 6, scale: ks)
            out.append(Unit(h: sh, ops: s))
        }
        return out
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
        if !tank { U += roofPVUnits(d) }
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
            // a standard design has up to 40 points: two tables side by side past 16
            let halves = list.count > 16 ? 2 : 1, perHalf = (list.count + halves - 1) / halves
            let imgH = ob.isEmpty ? 90.0 : 250, tableH = list.isEmpty ? 0 : Double(perHalf + 1) * 15 + 8
            let h2 = Self.band + 15 + imgH + tableH
            var s = box("สิ่งกีดขวาง", height: h2)
            s.append(.text("สำหรับวาดขนาดของสิ่งกีดขวาง", at: Pt(8, Self.band + 8), size: 8, bold: true))
            if let p = ob.first { s.append(.photo(p, Box(60, Self.band + 16, W - 120, imgH - 8))) }
            if !list.isEmpty {
                let tw = (W - 16) / Double(halves), side = halves == 1 ? 120.0 : 92
                let cols: [Double] = [tw - 2 * side, side, side], y0 = Self.band + 15 + imgH
                for half in 0..<halves {
                    let part = Array(list.dropFirst(half * perHalf).prefix(perHalf))
                    for r in 0...part.count {
                        var x = 8.0 + Double(half) * tw
                        for (ci, cwid) in cols.enumerated() {
                            let y = y0 + Double(r) * 15
                            s.append(.rect(Box(x, y, cwid, 15), stroke: .black, fill: r == 0 ? .band : nil, width: 0.5))
                            let t: String
                            if r == 0 { t = ["สิ่งกีดขวาง", "ตำแหน่ง X, Y (ม.)", "ขนาด ก x ย (ม.)"][ci] }
                            else {
                                let q = part[r - 1], name = q.label.isEmpty ? "-" : q.label + (q.note.isEmpty ? "" : " " + q.note)
                                t = [name, q.isAbsent ? "ไม่มีจริง" : "\(q.x), \(q.y)", q.isAbsent ? "-" : "\(q.w) x \(q.h)"][ci]
                            }
                            s.append(.textBox(t, Box(x + 2, y + 2, cwid - 4, 13), size: halves == 1 ? 7.5 : 6.5, align: ci == 0 ? .left : .center))
                            x += cwid
                        }
                    }
                }
            }
            s.append(.text("รูปภาพเพิ่มเติม: *รูปมุมสูง/รูปโดรน  *รูปสิ่งกีดขวาง  *รูปข้างถัง (สำหรับทางเดินรางสายไฟ)", at: Pt(0, h2 + 9), size: 8))
            U.append(Unit(h: h2 + 16, ops: s))
            if TankDesign.current(d) != nil, let sum = TankDesign.summary(d) { U.append(designUnit(sum)) }
            U += tankLayoutUnits(d)
            if let a = d.photo("aerialPhoto") { U += grid(title, [(a, nil)], cellH: 330, columns: 1) }
            // each photo's opening tag and note under it (D1 sub-step 4)
            U += grid("สิ่งกีดขวาง", ob.dropFirst().map { ($0, $0.caption) })
            U += grid(title + " — รูปข้างถัง / รูปเพิ่มเติม", d.photos("sidePhotos").map { ($0, $0.caption) })
            // sub-step 4's optional groups
            func named(_ p: Photo, _ t: String) -> (Photo?, String?) { (p, p.caption.map { t + " · " + $0 } ?? t) }
            let extra: [(Photo?, String?)] = d.photos(Tank.Key.roofPhotos).map { named($0, "หลังคาถัง") }
                + [d.photo(Tank.Key.shadePhoto).map { named($0, "เงาบัง (จากกลางหลังคา)") }, d.photo(Tank.Key.cablePhoto).map { named($0, "ทางเดินสายไฟ") }].compactMap { $0 }
            U += grid(title + " — หลังคา · เงาบัง · ทางเดินสายไฟ", extra)
        }
        return U
    }

    /// D1's stored panel layout (docs/specs/tank-drawing-swift.md §5): the layout on the plan with its figures, BOQ,
    /// checks and assumptions, the standard row section, then the tank sections 1–1 and 2–2.
    func tankLayoutUnits(_ d: Values) -> [Unit] {
        let W = Self.cw, lat = RoofMount.latitude(gps: j.text("gps"))
        var out: [Unit] = []
        if let l = TankLayout.current(d), l.count > 0, let plan = TankDrawings.layoutPlan(d, l) {
            let k = (W - 16) / plan.width, lineH = 11.0
            let assumed = TankLayout.assumptions(d, latitude: lat)
            let h = Self.band + 6 + plan.height * k + 10 + lineH * (assumed.isEmpty ? 4 : 5) + 6
            var o = box("ผังจัดแผงบนหลังคาถัง (หน่วย ม.)", height: h)
            o += plan.translated(8, Self.band + 6, scale: k)
            var y = Self.band + 6 + plan.height * k + 10
            o.append(.text(l.summaryLine(latitude: lat ?? RoofMount.defaultLatitude, facing: TankLayout.facing(d)), at: Pt(8, y), size: 8.5, bold: true)); y += lineH
            o.append(.text(l.boqLine, at: Pt(8, y), size: 8)); y += lineH
            o.append(.text(l.checksLine, at: Pt(8, y), size: 8, color: l.checks.allOK ? .black : .tag)); y += lineH
            if !assumed.isEmpty { o.append(.text("ค่าสมมติ: " + assumed.joined(separator: " · "), at: Pt(8, y), size: 7.5, color: .tag)); y += lineH }
            o.append(.text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง · ตรวจน้ำหนักบนพื้นหลังคาถังกับวิศวกรโครงสร้าง", at: Pt(8, y), size: 7.5, color: .faint))
            out.append(Unit(h: h, ops: o))
            if let sh = TankShade(d, latitude: lat ?? RoofMount.defaultLatitude) { out.append(tankShadeUnit(d, l, sh)) }
            let sec = TankDrawings.tableSection(l.params), ks = (W - 16) / sec.width, sh = Self.band + 6 + sec.height * ks + 4
            var s = box("ภาพตัดโต๊ะแผง", height: sh)
            s += sec.translated(8, Self.band + 6, scale: ks)
            out.append(Unit(h: sh, ops: s))
        }
        for across in [false, true] {
            guard let sec = TankDrawings.section(d, across: across) else { continue }
            let ks = (W - 16) / sec.width, sh = Self.band + 6 + sec.height * ks + 4
            var s = box(across ? "รูปตัดถัง 2–2" : "รูปตัดถัง 1–1", height: sh)
            s += sec.translated(8, Self.band + 6, scale: ks)
            out.append(Unit(h: sh, ops: s))
        }
        return out
    }

    /// `เงาบัง`: the losses, the recommendation, the month × hour map and the plan on 21 ธ.ค. at 09:00 and 15:00.
    func tankShadeUnit(_ d: Values, _ l: TankLayout, _ sh: TankShade) -> Unit {
        let W = Self.cw, map = TankDrawings.heatMap(sh), km = (W - 16) / map.width
        let snaps = sh.snapshots.filter { $0.title.hasPrefix("21 ธ.ค.") }
        let plans = snaps.compactMap { s in TankDrawings.layoutPlan(d, l, shaded: s.shaded).map { (s.title, $0) } }
        let pw = (W - 24) / 2, kp = plans.first.map { pw / $0.1.width } ?? 0, ph = plans.first.map { $0.1.height * kp } ?? 0
        let h = Self.band + 8 + 24 + map.height * km + 8 + (plans.isEmpty ? 0 : ph + 16) + 6
        var o = box("เงาบัง (จำลองทั้งปี)", height: h)
        var y = Self.band + 10
        o.append(.text(sh.summaryLine, at: Pt(8, y), size: 8.5, bold: true)); y += 12
        o.append(.text(sh.recommendation(d), at: Pt(8, y), size: 8, color: sh.objectLoss >= 0.01 ? .tag : .black)); y += 12
        o += map.translated(8, y, scale: km); y += map.height * km + 8
        for (i, p) in plans.enumerated() {
            let x = 8 + Double(i) * (pw + 8)
            o.append(.text("เงาบนแผง " + p.0 + " (สีส้ม)", at: Pt(x, y + 4), size: 8, bold: true))
            o += p.1.translated(x, y + 12, scale: kp)
        }
        return Unit(h: h, ops: o)
    }

    /// D1 from a standard design (docs/specs/standard-designs.md §6): the design, the counts and where the site differs.
    func designUnit(_ sum: TankDesign.Summary) -> Unit {
        // a difference with a photo gets a thumbnail row (docs/specs/standard-designs.md §6)
        let lineH = 11.0, thumbH = 46.0
        let rowH = sum.differences.indices.map { (sum.photos[safe: $0] ?? nil) == nil ? lineH : thumbH + 4 }
        let h = Self.band + 34 + max(lineH, rowH.reduce(0, +)) + 6
        var s = box("เทียบกับแบบมาตรฐาน", height: h)
        s.append(.text("เริ่มจากแบบมาตรฐาน: " + sum.design, at: Pt(8, Self.band + 9), size: 8.5, bold: true))
        s.append(.text(sum.counts, at: Pt(8, Self.band + 22), size: 8))
        if sum.differences.isEmpty { s.append(.text("• ไม่มีจุดที่ต่างจากแบบ", at: Pt(14, Self.band + 36), size: 7.5)) }
        var y = Self.band + 31
        for (i, t) in sum.differences.enumerated() {
            if let p = sum.photos[safe: i] ?? nil {
                s.append(.photoFill(p, Box(14, y, thumbH * 4 / 3, thumbH)))
                s.append(.text("• " + t, at: Pt(20 + thumbH * 4 / 3, y + thumbH / 2), size: 7.5))
            } else {
                s.append(.text("• " + t + " (ไม่มีรูป)", at: Pt(14, y + lineH / 2), size: 7.5))
            }
            y += rowH[i]
        }
        return Unit(h: h + 8, ops: s)
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
