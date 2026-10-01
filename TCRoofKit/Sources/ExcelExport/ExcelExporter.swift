import Foundation
import TCRoofCore

/// Fills a copy of the company's NO.224 workbook with a job.
/// Nothing is re-laid-out: values go into the form's own cells, ticks switch a checkbox cell to its green style,
/// photos are scaled into each frame, and extra roofs/tanks/station slots get their own copy of the sheet.
public struct ExcelExporter {
    public enum Failure: Error, LocalizedError {
        case template(String)
        public var errorDescription: String? { if case .template(let s) = self { return "แม่แบบ Excel เสียหาย: \(s)" }; return nil }
    }
    public struct Result: Sendable {
        public let data: Data
        public let sheets: [String]
        public let pictures: Int
        public var fileName: String = "แบบสำรวจ.xlsx"
    }

    let template: Data
    let meta: TemplateMeta

    /// Uses the workbook bundled with the package unless another template is given.
    public init(template: Data? = nil, meta: Data? = nil) throws {
        guard let t = template ?? Self.resource("template", "xlsx"), let m = meta ?? Self.resource("template_meta", "json") else {
            throw Failure.template("missing resources")
        }
        self.template = t
        self.meta = try JSONDecoder().decode(TemplateMeta.self, from: m)
    }

    static func resource(_ name: String, _ ext: String) -> Data? {
        let u = Bundle.module.url(forResource: name, withExtension: ext)
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources")
        return u.flatMap { try? Data(contentsOf: $0) }
    }

    /// Sheet order of the original workbook.
    static let order = ["house", "roofForm", "sed", "station", "roof", "tank"]
    static let slots: [(ModuleType, Int)] = [(.panel, 3), (.inverter, 3), (.water, 4), (.backfeed, 2), (.fts, 4)]

    /// - Parameters:
    ///   - photoData: bytes of a stored photo (JPEG or PNG).
    ///   - planImage: rendered plan (PNG) for a roof or tank section without a hand-drawn plan photo.
    ///   - siteMapImage: the site picture with its symbols drawn in (made by the app); nil uses the plain photo.
    public func export(_ job: Job, photoData: @escaping (Photo) -> Data?, planImage: (SurveyModule) -> ExcelImage? = { _ in nil },
                       siteMapImage: ExcelImage? = nil) throws -> Result {
        let book = try Workbook(template: template, meta: meta)
        let img: (Photo?) -> ExcelImage? = { p in
            guard let p, let d = photoData(p) else { return nil }
            return ExcelImage(data: d, width: p.width, height: p.height, isPNG: p.isPNG)
        }
        let fill = Fill(job: job, img: img, siteMap: siteMapImage)

        var plan: [(key: String, name: String, run: (SheetFill) -> Void)] = []
        let by: (ModuleType) -> [SurveyModule] = { t in job.modules.filter { $0.type == t } }
        let nStation = max(1, Self.slots.map { t, n in (by(t).count + n - 1) / n }.max() ?? 1)
        for k in 0..<nStation {
            var sl: [ModuleType: [SurveyModule]] = [:]
            for (t, n) in Self.slots { sl[t] = Array(by(t).dropFirst(k * n).prefix(n)) }
            plan.append(("station", "ระบบไฟฟ้า" + (k > 0 ? " (\(k + 1))" : ""), { fill.station($0, sl) }))
        }
        var count: [ModuleType: Int] = [:]
        let names: [ModuleType: String] = [.house: "ระบบไฟฟ้า 2", .roofForm: "หลังคาทั่วไป", .sed: "บ่อตกตะกอน", .roof: "หลังคาทั่วไป R", .tank: "บ่อน้ำใส"]
        for m in job.modules where !m.type.isStation {
            let n = (count[m.type] ?? 0) + 1; count[m.type] = n
            let name = m.type == .roof ? "หลังคาทั่วไป R\(n)" : names[m.type]! + (n > 1 ? " (\(n))" : "")
            let key = m.type.rawValue
            switch m.type {
            case .house: plan.append((key, name, { fill.house($0, m) }))
            case .roofForm: plan.append((key, name, { fill.roofForm($0, m) }))
            case .sed: plan.append((key, name, { fill.sed($0, m) }))
            case .roof, .tank:
                let png = m.values.photo("planPhoto") == nil ? planImage(m) : nil
                plan.append((key, name, { m.type == .roof ? fill.roof($0, m, png) : fill.tank($0, m, png) }))
            default: break
            }
        }
        let sorted = plan.enumerated().sorted { a, b in
            let ia = Self.order.firstIndex(of: a.element.key) ?? 99, ib = Self.order.firstIndex(of: b.element.key) ?? 99
            return ia != ib ? ia < ib : a.offset < b.offset
        }.map(\.element)
        for p in sorted {
            let inst = try book.instance(p.key)
            book.fill(inst, name: String(p.name.prefix(31)), p.run)
        }
        let data = try book.finish()
        var r = Result(data: data, sheets: sorted.map(\.name), pictures: book.pictureCount)
        r.fileName = Self.fileName(job)
        return r
    }

    public static func fileName(_ job: Job) -> String {
        let base = "แบบสำรวจ NO.\(job.docNo.isEmpty ? "-" : job.docNo) \(job.projectName)".trimmingCharacters(in: .whitespaces)
        return base.replacingOccurrences(of: "[/\\\\:*?\"<>|]", with: "-", options: .regularExpression) + ".xlsx"
    }
}

/// Where each answer goes in the workbook (cell addresses of NO.224).
struct Fill {
    let job: Job
    let img: (Photo?) -> ExcelImage?
    var siteMap: ExcelImage? = nil
    var j: Values { job.values }

    static func lines(_ t: String) -> [String] {
        t.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func station(_ a: SheetFill, _ mods: [ModuleType: [SurveyModule]]) {
        a.txt("W2", j.text("docNo")); a.txt("W3", ISODate.thai(j.text("date"))); a.set("E4", j.text("coordinator")); a.set("O4", j.text("phone"))
        a.set("E5", j.text("address")); a.set("E6", j.text("officeAddress"))
        let cap = j.text("capacity").trimmingCharacters(in: .whitespaces); a.set("E11", cap.isEmpty ? "" : "\(cap)kWp")
        a.pic("B12:AA42", siteMap ?? img(j.photo("siteMap")))
        let L = ["C49", "C50", "C51", "C52", "C53", "I49", "I50", "I51", "I52", "I53", "R49", "R50", "R51"], sel = j.multi("siteList")
        for (i, o) in Options.list.enumerated() where i < L.count { a.tick(L[i], sel.contains(o)) }
        a.tokens["METER"] = j.text("meterNo")
        for (i, t) in j.transformers("trafos").prefix(5).enumerated() {
            a.tokens["T\(i)K"] = t.kva
            for (k, v) in t.mdb.prefix(6).enumerated() { a.tokens["T\(i)M\(k)"] = v }
        }
        func name(_ h: Int, _ m: SurveyModule) { if !m.name.isEmpty { a.label("B\(h)", m.name, append: true) } }
        func detail(_ r1: String, _ r2: String, _ l: [String]) { a.set(r1, l.first); a.set(r2, l.dropFirst().joined(separator: " ")) }
        for (i, h) in [101, 117, 133].enumerated() {
            guard let m = mods[.panel]?[safe: i] else { continue }
            let d = m.values; name(h, m)
            a.pic("B\(h + 2):N\(h + 12)", img(d.photo("photoBreaker"))); a.pic("O\(h + 2):AA\(h + 12)", img(d.photo("photoWide")))
            a.set("F\(h + 13)", d.text("breakerAT")); a.set("F\(h + 14)", d.text("loadKW")); a.set("J\(h + 14)", d.text("loadTime"))
            detail("R\(h + 13)", "R\(h + 14)", Self.lines(d.text("detail")))
        }
        for (i, h) in [150, 166, 182].enumerated() {
            guard let m = mods[.inverter]?[safe: i] else { continue }
            let d = m.values; name(h, m)
            a.pic("B\(h + 2):N\(h + 12)", img(d.photo("photoArea"))); a.pic("O\(h + 2):AA\(h + 12)", img(d.photo("photoDetail")))
            a.set("K\(h + 13)", d.text("sizeLWH"))
            var l = Self.lines(d.text("detail"))
            if InverterStation.isDesigned(d) {
                // same cell, with the B2 page's catalog equipment and minimum room / wall
                let s = InverterStation(d)
                l.insert("อินเวอร์เตอร์ \(s.sizesText) · CB \(s.breakerSummary) · \(s.minimumText) · \(s.site.label)", at: 0)
            } else if let n = d.number("inverterCount"), n > 0 { l.insert("อินเวอร์เตอร์ \(fmt(n)) เครื่อง ต้องการพื้นที่ \(String(format: "%.2f", 1.5 * n + 1.5)) x 2.00 ม.", at: 0) }
            detail("R\(h + 13)", "R\(h + 14)", l)
        }
        for (i, (h, cr)) in [(199, 13), (215, 13), (231, 13), (247, 11)].enumerated() {
            guard let m = mods[.water]?[safe: i] else { continue }
            let d = m.values; name(h, m)
            a.pic("B\(h + 2):N\(h + cr - 1)", img(d.photo("photoArea"))); a.pic("O\(h + 2):AA\(h + cr - 1)", img(d.photo("photoWide")))
            a.radio(d.choice("waterMode"), ["ติดตั้งระบบน้ำใหม่", "ติดตั้งร่วมกับระบบน้ำเดิม"], ["B\(h + cr)", "G\(h + cr)"])
            detail("R\(h + cr)", "R\(h + cr + 1)", Self.lines(d.text("detail")))
        }
        for (i, h) in [262, 294].enumerated() {
            guard let m = mods[.backfeed]?[safe: i] else { continue }
            let d = m.values; name(h, m)
            a.pic("B\(h + 2):N\(h + 27)", img(d.photo("photoArea"))); a.pic("O\(h + 2):AA\(h + 27)", img(d.photo("photoDetail")))
            a.radio(d.choice("level"), ["กันย้อนที่แรงต่ำ", "กันย้อนที่แรงสูง"], ["B\(h + 28)", "G\(h + 28)"])
            a.radio(d.choice("pole"), ["เสาเดิม", "เสาใหม่"], ["G\(h + 29)", "J\(h + 29)"])
            detail("R\(h + 28)", "R\(h + 29)", Self.lines(d.text("detail")))
        }
        for (i, h) in [327, 341, 355, 369].enumerated() {
            guard let m = mods[.fts]?[safe: i] else { continue }
            let d = m.values; name(h, m)
            a.pic("B\(h + 2):N\(h + 13)", img(d.photo("photoFTS"))); a.pic("O\(h + 2):AA\(h + 13)", img(d.photo("photoEmg")))
        }
    }

    func house(_ a: SheetFill, _ m: SurveyModule) {
        let d = m.values
        a.txt("W2", j.text("docNo")); a.txt("W3", ISODate.thai(j.text("date"))); a.set("F5", j.text("projectName")); a.set("O5", j.text("phone"))
        a.set("E6", j.text("address")); a.set("H7", j.text("gps")); a.radio(j.choice("internet"), ["มี", "ไม่มี"], ["G9", "K9"]); a.set("V10", j.text("engineer"))
        let cap = j.text("capacity").trimmingCharacters(in: .whitespaces); a.set("H13", cap.isEmpty ? "" : "\(cap) kWp")
        a.radio(d.choice("buildingType"), ["คอนกรีตเสริมเหล็ก", "ไม้", "อื่นๆ"], ["G15", "L15", "R15"]); a.set("T15", d.other("buildingType"))
        a.set("I16", d.text("floors")); a.set("O16", d.text("buildingWidth")); a.set("T16", d.text("buildingLength"))
        a.radio(d.choice("roofShape"), Options.roofShape, ["G17", "L17", "R17", "G18", "L18", "R18"]); a.set("T18", d.other("roofShape"))
        a.radio(d.choice("roofMaterial"), Options.roofMaterial, ["G20", "L20", "R20", "V20", "G22"]); a.set("I22", d.other("roofMaterial"))
        a.radio(d.choice("roofStructure"), Options.structure, ["G24", "G26"])
        a.set("I27", d.text("panelAreaWidth")); a.set("P27", d.text("panelAreaLength"))
        a.radio(d.choice("facing"), Options.facing, ["G29", "L29", "P29", "T29", "G31", "L31", "T31"]); a.set("V31", d.other("facing"))
        a.radio(d.choice("obstacle"), Options.noYes, ["J33", "M33"]); a.set("P33", d.text("obstacleDetail"))
        a.radio(d.choice("hasConstructionDrawing"), Options.yesNo, ["J37", "M37"]); a.radio(d.choice("hasElectricalDrawing"), Options.yesNo, ["J39", "M39"])
        a.tick("J41", !d.text("mainBreaker").trimmingCharacters(in: .whitespaces).isEmpty); a.set("R41", d.text("mainBreaker")); a.tick("W41", d.choice("hasCutout") == "มี")
        a.set("L43", d.text("busbarAmp")); a.set("R43", d.text("spareAmp")); a.set("W43", d.text("spaceSlots"))
        a.radio(d.choice("hasGround"), Options.yesNo, ["J45", "M45"]); a.set("T45", d.text("groundValue"))
        a.pic("B52:M59", img(d.photo("purlinPhotoF"))); a.pic("N52:AA59", img(d.photo("purlinPhotoG"))); a.pic("B61:AA71", img(d.photo("purlinPhotoS")))
        a.pic("B74:M83", img(d.photo("rafterPhotoF"))); a.pic("N74:AA83", img(d.photo("rafterPhotoG"))); a.pic("B85:AA95", img(d.photo("rafterPhotoS")))
        let blk = ["หลังคาเพิงหมาแหงน": 128, "หลังคาทรงปั้นหยา": 147][d.choice("roofShape") ?? ""] ?? 110
        for (i, k) in ["measA", "measB", "measC", "measD", "measE"].enumerated() { a.set("X\(blk + i)", d.text(k)) }
        a.radio(d.choice("structMaterial"), Options.structMaterial, ["I154", "P154"])
        a.set("F165", d.text("woodRafterF")); a.set("J165", d.text("woodRafterG")); a.set("O165", d.text("woodPurlinF")); a.set("S165", d.text("woodPurlinG"))
        a.set("F169", d.text("steelRafterType")); a.set("J169", d.text("steelRafterF")); a.set("N169", d.text("steelRafterG")); a.set("U169", d.text("steelRafterH"))
        a.set("F170", d.text("steelPurlinType")); a.set("J170", d.text("steelPurlinF")); a.set("N170", d.text("steelPurlinG")); a.set("U170", d.text("steelPurlinH"))
        a.tick("D172", !d.text("prefabRafterLength").trimmingCharacters(in: .whitespaces).isEmpty); a.set("U172", d.text("prefabRafterLength"))
        a.set("V178", d.text("measH")); a.set("V179", d.text("measI1")); a.set("V180", d.text("measI2")); a.set("V181", d.text("roofAngle"))
        a.pic("B184:AA211", img(d.photo("sketchPhoto"))); a.pic("B213:AA234", img(d.photo("underRoofPhoto"))); a.pic("B236:AA256", img(d.photo("aerialPhoto")))
        a.pic("B259:N271", img(d.photo("photoFront"))); a.pic("O259:AA271", img(d.photo("photoBack"))); a.pic("B273:N287", img(d.photo("photoLeft"))); a.pic("O273:AA287", img(d.photo("photoRight")))
        a.pic("B292:N301", img(d.photo("inverterWidePhoto"))); a.pic("O289:AA301", img(d.photo("inverterClosePhoto")))
        a.pic("B303:N316", img(d.photo("mainPanelWide"))); a.pic("O303:AA316", img(d.photo("mainPanelOpen")))
        a.label("B317", d.text("mainBreaker")); a.pic("B318:AA333", img(d.photo("breakerPhoto"))); a.pic("B335:AA347", img(d.photo("meterPhoto"))); a.pic("B349:AA359", img(d.photo("roofMatPhoto")))
        a.label("B360", d.text("userType")); a.label("B361", d.text("caNo")); a.label("O361", d.text("meterCode")); a.pic("B362:AA374", img(d.photo("billPhoto"))); a.pic("B376:AA387", img(d.photo("groundPhoto")))
    }

    func roofForm(_ a: SheetFill, _ m: SurveyModule) {
        let d = m.values
        a.set("I4", d.text("floors")); a.set("O4", d.text("buildingWidth")); a.set("T4", d.text("buildingLength"))
        a.radio(d.choice("roofShape"), Options.roofShape, ["G5", "L5", "R5", "G6", "L6", "R6"]); a.set("T6", d.other("roofShape"))
        a.radio(d.choice("roofMaterial"), Options.roofMaterial, ["G8", "L8", "R8", "V8", "G10"]); a.set("I10", d.other("roofMaterial"))
        a.radio(d.choice("roofStructure"), Options.structure, ["G12", "L12"])
        a.set("I14", d.text("panelAreaWidth")); a.set("P14", d.text("panelAreaLength"))
        a.radio(d.choice("facing"), Options.facing, ["G16", "L16", "P16", "T16", "G18", "L18", "T18"]); a.set("V18", d.other("facing"))
        a.radio(d.choice("obstacle"), Options.noYes, ["J20", "M20"]); a.set("P20", d.text("obstacleDetail"))
        a.radio(d.choice("hasConstructionDrawing"), Options.yesNo, ["J22", "M22"])
        a.pic("B29:AA44", img(d.photo("roofPhoto"))); a.pic("B47:AA79", img(d.photo("sketchPhoto")))
        for i in Options.components.indices { a.set("S\(82 + i)", d.text("size\(i + 1)")); a.set("Y\(82 + i)", d.text("space\(i + 1)")) }
        a.radio(d.choice("structMaterial"), Options.structMaterial, ["I102", "P102"])
        a.pic("B114:AA128", img(d.photo("underRoofPhoto"))); a.pic("B130:AA144", img(d.photo("aerialPhoto")))
        a.pic("B147:N158", img(d.photo("photoFront"))); a.pic("O147:AA158", img(d.photo("photoBack"))); a.pic("B160:N172", img(d.photo("photoLeft"))); a.pic("O160:AA172", img(d.photo("photoRight")))
    }

    func sed(_ a: SheetFill, _ m: SurveyModule) {
        let d = m.values
        a.txt("W2", j.text("docNo")); a.txt("W3", ISODate.thai(j.text("date"))); a.set("F4", j.text("coordinator")); a.set("O4", j.text("phone"))
        let office = j.text("officeAddress").trimmingCharacters(in: .whitespaces); a.set("E5", office.isEmpty ? j.text("address") : office)
        let sp = d.photos("sitePhotos")
        for (i, (r1, r2)) in [(10, 24), (26, 40), (42, 57), (59, 73), (75, 89), (91, 106)].enumerated() { a.pic("B\(r1):AA\(r2)", img(sp[safe: i])) }
        a.pic("B109:AA131", img(d.photo("drawing")))
        for (i, c) in "ABCDEF".enumerated() { a.set("P\(133 + i)", d.text("dist\(c)")) }
        for (i, c) in "GHIJK".enumerated() { a.set("V\(133 + i)", d.text("dist\(c)")) }
        a.pic("B162:AA177", img(d.photo("aerialPhoto")))
        a.pic("B180:N192", img(d.photo("pFront"))); a.pic("O180:AA192", img(d.photo("pBack"))); a.pic("B194:N205", img(d.photo("pLeft"))); a.pic("O194:AA205", img(d.photo("pRight")))
        a.pic("B207:AA222", img(d.photo("obstPhoto")))
    }

    private func panelsLine(_ d: Values) -> String {
        let b = d.text("panelsBefore").trimmingCharacters(in: .whitespaces), c = d.text("panelsCut").trimmingCharacters(in: .whitespaces)
        return "จำนวนแผงก่อนเข้าสำรวจ \(b.isEmpty ? "-" : b) แผง\nจำนวนแผงที่ตัดออกหลังสำรวจ \(c.isEmpty ? "-" : c) แผง"
    }

    func roof(_ a: SheetFill, _ m: SurveyModule, _ plan: ExcelImage?) {
        let d = m.values, title = "หลังคาทั่วไป" + (m.name.isEmpty ? "" : " " + m.name)
        a.raw("A2", title); a.raw("A40", title); a.raw("A3", panelsLine(d))
        a.pic("C3:X16", img(d.photo("planPhoto")) ?? plan)
        for i in Options.components.indices { a.set("T\(21 + i)", d.text("comp\(i + 1)")) }
        a.radio(d.choice("roofShape"), Options.roofShape, ["F30", "K30", "Q30", "F32", "K32", "Q32"])
        a.radio(d.choice("roofMaterial"), Options.roofMaterial, ["F34", "K34", "Q34", "U34"])
        a.radio(d.choice("roofStructure"), Options.structure, ["F36", "K36"])
        let top = [d.photo("aerialPhoto")] + d.photos("generalPhotos").map { Optional($0) }, st = d.photos("structPhotos")
        for (i, q) in ["A41:M47", "N41:Z47", "A48:M54", "N48:Z54"].enumerated() { a.pic(q, img(top[safe: i] ?? nil)) }
        for (i, q) in ["A56:M62", "N56:Z62", "A63:M69", "N63:Z69"].enumerated() { a.pic(q, img(st[safe: i])) }
    }

    func tank(_ a: SheetFill, _ m: SurveyModule, _ plan: ExcelImage?) {
        let d = m.values, title = "ถังน้ำใส" + (m.name.isEmpty ? "" : " " + m.name)
        a.raw("A2", title); a.raw("A40", title); a.raw("A3", panelsLine(d))
        a.pic("C3:X15", img(d.photo("planPhoto")) ?? plan)
        let h = d.text("tankHeight").trimmingCharacters(in: .whitespaces); if !h.isEmpty { a.set("D16", "\(h)M") }
        a.label("F16", d.text("surface"))
        let soil = d.text("soilDepth").trimmingCharacters(in: .whitespaces); a.label("J16", soil.isEmpty ? "" : soil + " M")
        // NO.224 has no cells for these — written into the blank tail of rows 16/17 beside the template labels.
        if let k = Schema.tankKind(d) { a.raw("R16", k) }
        if let sh = Schema.shadeText(d) { a.raw("R17", sh) }
        let ob = d.photos("obstPhotos"); a.pic("A20:Z32", img(ob.first))
        let top = [d.photo("aerialPhoto")] + d.photos("sidePhotos").map { Optional($0) }
        for (i, q) in ["A41:M47", "N41:Z47", "A48:M54", "N48:Z54"].enumerated() { a.pic(q, img(top[safe: i] ?? nil)) }
        for (i, q) in ["A56:M62", "N56:Z62", "A63:M69", "N63:Z69"].enumerated() { a.pic(q, img(ob[safe: i + 1])) }
    }
}


