import Foundation

/// The team's CAD layer standard (docs/specs/cad-export-dxf, Layers), in the US National CAD Standard's format (AIA CAD
/// Layer Guidelines): `Discipline-Major[-Minor]-Status`, fields split by a dash, the discipline one letter (`G` general,
/// `A` architectural, `S` structural, `E` electrical, `C` civil, and the office's own `P` for the PV system: modules,
/// mounting, walkways, lifeline, access), the major and minor groups four letters, and the status
/// last: `E` existing (the roof, the tank, what the survey found), `N` new (what we install), `T` temporary (crane access).
/// So `*-N` filters everything we build, `P-*` the PV system and `S-*` the building's structure, in any CAD program's layer filter. Each layer carries
/// its colour, linetype, lineweight, plot flag and a description in Thai and English (the layer manager's Description
/// column). Every object is ByLayer: a part drawn in another colour has its own layer. Hatches go on the layer's `HATC`
/// minor group (`hatch(of:)`), placed by the writer itself. Layer 0 holds only block contents, and Defpoints nothing
/// but what AutoCAD puts there. The C1 roof, the D1 tank, the A2 site plan and the single line diagram all take their
/// layers from here, so the same thing is on the same layer in every file.
public enum CADLayers {

    // general: grid and annotation
    public static let grid = SketchDXF.Layer("G-GRID", aci: 8, linetype: .center, lineweight: 18, description: "เส้นกริดและหัวกริด / Grid lines and bubbles")
    public static let dim = SketchDXF.Layer("G-ANNO-DIMS", aci: 3, lineweight: 18, description: "ระยะ / Dimensions")
    public static let text = SketchDXF.Layer("G-ANNO-TEXT", aci: 7, lineweight: 25, description: "ข้อความและหัวแบบ / Text and captions")
    public static let north = SketchDXF.Layer("G-ANNO-NRTH", aci: 7, lineweight: 25, description: "ลูกศรทิศเหนือ / North arrow")
    public static let sectionMark = SketchDXF.Layer("G-ANNO-SYMB", aci: 1, lineweight: 25, description: "เครื่องหมายรูปตัด / Section marks")
    public static let roofTable = SketchDXF.Layer("G-ANNO-SCHD", aci: 7, lineweight: 18, description: "ตารางขนาดชิ้นส่วน / Member schedule")
    public static let siteMeasure = SketchDXF.Layer("G-ANNO-MEAS", aci: 3, lineweight: 18, description: "ระยะที่วัด / Measurements")
    public static let siteFrame = SketchDXF.Layer("G-ANNO-NPLT", aci: 8, lineweight: 18, plot: false, description: "กรอบภาพผังบริเวณ (ไม่พิมพ์) / Site picture frame (no plot)")
    public static let detail = SketchDXF.Layer("G-DETL", aci: 7, lineweight: 18, description: "แบบรายละเอียดของทีม / Team detail sheets")

    // existing building: the roof, its openings and obstacles
    public static let obstacle = SketchDXF.Layer("A-OPNG-E", aci: 1, lineweight: 25, description: "สิ่งกีดขวางและช่องเปิด (เดิม) / Obstacles and openings (existing)")
    public static let roofSkylight = SketchDXF.Layer("A-ROOF-SKYL-E", aci: 4, lineweight: 25, description: "แผ่นโปร่งแสง (เดิม) / Skylights (existing)")
    public static let roofOutline = SketchDXF.Layer("S-ROOF-OTLN-E", aci: 7, lineweight: 50, description: "ขอบหลังคา (เดิม) / Roof outline (existing)")
    public static let roofRidge = SketchDXF.Layer("S-ROOF-RIDG-E", aci: 1, lineweight: 35, description: "สันหลังคา (เดิม) / Ridge (existing)")
    public static let roofTruss = SketchDXF.Layer("S-ROOF-FRAM-E", aci: 5, lineweight: 35, description: "โครงถัก จันทัน ชายคา (เดิม) / Trusses, rafters, eaves (existing)")
    public static let roofPost = SketchDXF.Layer("S-COLS-E", aci: 7, lineweight: 35, description: "เสา (เดิม) / Columns (existing)")
    public static let roofPurlin = SketchDXF.Layer("S-ROOF-PURL-E", aci: 30, lineweight: 18, description: "แป (เดิม) / Purlins (existing)")
    public static let roofSection = SketchDXF.Layer("S-ROOF-SECT-E", aci: 7, lineweight: 35, description: "รูปตัด A-A (เดิม) / Section A-A (existing)")

    // new PV system (discipline P), on the roof and on the tank
    public static let pvModule = SketchDXF.Layer("P-MODL-N", aci: 150, lineweight: 25, description: "แผงโซลาร์ (ใหม่) / PV modules (new)")
    public static let pvKeepout = SketchDXF.Layer("P-MODL-KEEP-N", aci: 1, linetype: .hidden, lineweight: 18, description: "ระยะห้ามวางแผง / Keep-out zones")
    public static let pvCableTray = SketchDXF.Layer("P-CTRY-N", aci: 3, lineweight: 25, description: "รางเคเบิลและท่อ PPR (ใหม่) / Cable tray and PPR pipe (new)")
    public static let pvRail = SketchDXF.Layer("P-RAIL-N", aci: 2, lineweight: 18, description: "รางยึดแผง (ใหม่) / Mounting rails (new)")
    public static let pvCut = SketchDXF.Layer("P-RAIL-CUTS-N", aci: 1, lineweight: 18, description: "จุดตัดราง / Rail cuts")
    public static let pvFoot = SketchDXF.Layer("P-FOOT-N", aci: 250, lineweight: 18, description: "ขายึดราง (ใหม่) / Rail feet (new)")
    public static let pvTable = SketchDXF.Layer("P-TABL-N", aci: 170, lineweight: 25, description: "โต๊ะแผงและเสา (ใหม่) / Module tables and posts (new)")
    public static let pvRafter = SketchDXF.Layer("P-RAFT-N", aci: 1, lineweight: 25, description: "คานเอียงรับราง (ใหม่) / Rafters (new)")
    public static let pvBrace = SketchDXF.Layer("P-BRAC-N", aci: 4, lineweight: 18, description: "ค้ำยันระหว่างเสา (ใหม่) / Bracing between posts (new)")
    public static let pvFooting = SketchDXF.Layer("P-FTNG-N", aci: 3, lineweight: 25, description: "ฐานรากและฐานเสา (ใหม่) / Footings and post bases (new)")
    public static let pvWalkway = SketchDXF.Layer("P-WALK-N", aci: 10, lineweight: 25, description: "ทางเดิน HDG 0.30×2.40 ม. (ใหม่) / Walkway grating (new)")
    public static let walkRail = SketchDXF.Layer("P-WALK-RAIL-N", aci: 8, lineweight: 18, description: "รางขวางใต้ทางเดิน / Cross rails under the walkway")
    public static let walkFoot = SketchDXF.Layer("P-WALK-FOOT-N", aci: 6, lineweight: 18, description: "ขาตั้ง L-Feet ของทางเดิน / Walkway L-feet")
    public static let pvLifeline = SketchDXF.Layer("P-LIFE-N", aci: 130, lineweight: 25, description: "สลิงกันตก 6 มม. (ใหม่) / Lifeline wire rope (new)")
    public static let lifeRail = SketchDXF.Layer("P-LIFE-RAIL-N", aci: 80, lineweight: 18, description: "รางสลิงกันตก / Lifeline rail")
    public static let lifeSupport = SketchDXF.Layer("P-LIFE-SUPT-N", aci: 3, lineweight: 18, description: "เสารับสลิงกันตก / Lifeline supports")
    public static let pvAccess = SketchDXF.Layer("P-LADD-N", aci: 6, lineweight: 35, description: "ทางขึ้นหลังคา บันไดลิง (ด้านเดียว) / Roof access ladder (one side)")

    // existing tank
    public static let tankOutline = SketchDXF.Layer("S-TANK-OTLN-E", aci: 7, lineweight: 50, description: "ขอบถังน้ำใส (เดิม) / Tank outline (existing)")
    public static let tankBeam = SketchDXF.Layer("S-TANK-BEAM-E", aci: 8, linetype: .hidden, lineweight: 25, description: "คานหลังคาถัง (เดิม) / Tank roof beams (existing)")
    public static let tankSection = SketchDXF.Layer("S-TANK-SECT-E", aci: 7, lineweight: 35, description: "รูปตัดถัง พื้น ผนัง เสา ฐานราก (เดิม) / Tank sections (existing)")
    public static let tankSoil = SketchDXF.Layer("C-TOPO-E", aci: 32, lineweight: 25, description: "ดินและระดับดิน / Soil and ground line")

    // A2 site plan
    public static let siteBuilding = SketchDXF.Layer("A-BLDG-E", aci: 4, lineweight: 35, description: "อาคาร (เดิม) / Buildings (existing)")
    public static let sitePVArea = SketchDXF.Layer("P-AREA-N", aci: 5, lineweight: 25, description: "พื้นที่ติดตั้งแผงบนอาคาร / PV area on buildings")
    public static let sitePanelArea = SketchDXF.Layer("P-AREA-DRAW-N", aci: 1, lineweight: 25, description: "พื้นที่วางแผงที่วาด / Drawn panel areas")
    public static let siteCable = SketchDXF.Layer("E-CABL-N", aci: 5, linetype: .hidden, lineweight: 25, description: "แนวสายไฟ (ใหม่) / Cable routes (new)")
    public static let siteSymbol = SketchDXF.Layer("E-EQPM-E", aci: 7, lineweight: 25, description: "สัญลักษณ์อุปกรณ์ / Equipment symbols")
    public static let siteCrane = SketchDXF.Layer("C-ACCS-T", aci: 30, linetype: .hidden, lineweight: 25, description: "ทางเข้ารถเครน (ชั่วคราว) / Crane access (temporary)")
    public static let siteShade = SketchDXF.Layer("C-SHAD-E", aci: 30, lineweight: 18, description: "เงาบัง / Shading")
    public static let siteShape = SketchDXF.Layer("C-BNDY-E", aci: 4, lineweight: 25, description: "ขอบเขตและจุดติดตั้ง / Boundaries and PV points")

    // single line diagram, by what a colour means on the diagram (`SingleLineLayout.color`)
    public static let sldLine = SketchDXF.Layer("E-SLDG-E", aci: 7, lineweight: 35, description: "อุปกรณ์และสายที่ทราบค่า (เดิม) / Known equipment and wiring (existing)")
    public static let sldNew = SketchDXF.Layer("E-SLDG-N", aci: 5, lineweight: 35, description: "อุปกรณ์ติดตั้งใหม่ / New equipment")
    public static let sldOK = SketchDXF.Layer("E-SLDG-OKAY", aci: 3, lineweight: 25, description: "ผ่านการตรวจ / Checked OK")
    public static let sldWarn = SketchDXF.Layer("E-SLDG-WARN", aci: 30, lineweight: 25, description: "ควรตรวจสอบ / To check")
    public static let sldMissing = SketchDXF.Layer("E-SLDG-MISS", aci: 1, lineweight: 25, description: "ค่าที่ยังไม่มี / Missing values")
    public static let sldPole = SketchDXF.Layer("E-SLDG-POLE-E", aci: 8, lineweight: 25, description: "เสาไฟฟ้า (เดิม) / Utility poles (existing)")
    public static let sldAssumed = SketchDXF.Layer("E-SLDG-ASSM", aci: 8, lineweight: 18, description: "ค่าที่สมมติ / Assumed values")
    public static let sldText = SketchDXF.Layer("E-SLDG-TEXT", aci: 7, lineweight: 25, description: "ข้อความแผนภาพ / Diagram text")
    public static let sldOther = SketchDXF.Layer("E-SLDG-OTHR", aci: 7, lineweight: 25, description: "อื่น ๆ / Other")

    /// Every layer of the standard, in the order the spec lists them.
    public static let all: [SketchDXF.Layer] = [
        grid, dim, text, north, sectionMark, roofTable, siteMeasure, siteFrame, detail,
        obstacle, roofSkylight, roofOutline, roofRidge, roofTruss, roofPost, roofPurlin, roofSection,
        pvModule, pvKeepout, pvCableTray, pvRail, pvCut, pvFoot, pvTable, pvRafter, pvBrace, pvFooting,
        pvWalkway, walkRail, walkFoot, pvLifeline, lifeRail, lifeSupport, pvAccess,
        tankOutline, tankBeam, tankSection, tankSoil,
        siteBuilding, sitePVArea, sitePanelArea, siteCable, siteSymbol, siteCrane, siteShade, siteShape,
        sldLine, sldNew, sldOK, sldWarn, sldMissing, sldPole, sldAssumed, sldText, sldOther,
    ]

    /// The standard layer of that name (a hatch layer too).
    public static func named(_ name: String) -> SketchDXF.Layer? {
        everyLayer.first { $0.name == name } ?? all.first { hatch(of: $0).name == name }.map(hatch(of:))
    }

    /// The layer a hatch of `l` goes on: its `HATC` minor group before the status (`P-FTNG-N` → `P-FTNG-HATC-N`), in its
    /// colour, thin (0.13 mm), with "hatch" in its description.
    public static func hatch(of l: SketchDXF.Layer) -> SketchDXF.Layer {
        guard !l.name.contains("-HATC"), l.name != "0", l.name != "Defpoints" else { return l }
        var parts = l.name.split(separator: "-").map(String.init)
        if let last = parts.last, last.count == 1, parts.count > 1 { parts.insert("HATC", at: parts.count - 1) } else { parts.append("HATC") }
        return SketchDXF.Layer(parts.joined(separator: "-"), aci: l.aci, lineweight: 13, plot: l.plot, description: l.description + " | ลายแรเงา / hatch")
    }

    /// The layer an annotation of `l` goes on: its `TEXT` minor group before the status (`E-SLDG-MISS` →
    /// `E-SLDG-MISS-TEXT`), in its colour, so a text that means something by its colour is ByLayer too.
    public static func annotation(of l: SketchDXF.Layer) -> SketchDXF.Layer {
        guard !l.name.contains("-TEXT"), l.name != "0" else { return l }
        var parts = l.name.split(separator: "-").map(String.init)
        if let last = parts.last, last.count == 1, parts.count > 1 { parts.insert("TEXT", at: parts.count - 1) } else { parts.append("TEXT") }
        return SketchDXF.Layer(parts.joined(separator: "-"), aci: l.aci, lineweight: 25, plot: l.plot, description: l.description + " | ข้อความ / text")
    }

    /// The layers that carry hatches in the exports (their `HATC` layers are in the standards file too).
    public static let hatched: [SketchDXF.Layer] = [obstacle, roofSection, pvModule, pvCableTray, pvFooting, pvWalkway, lifeRail, pvAccess,
                                                     tankSection, tankSoil, siteBuilding, sitePVArea, siteShade, sldNew, sldLine, sldText, detail]

    /// The layers whose texts take their own `TEXT` layer (the single line diagram's meanings).
    public static let annotated: [SketchDXF.Layer] = [sldNew, sldOK, sldWarn, sldMissing, sldPole, sldAssumed]

    /// Every layer the exports can write: the standard, its hatch layers and its text layers.
    public static var everyLayer: [SketchDXF.Layer] { all + hatched.map(hatch(of:)) + annotated.map(annotation(of:)) }

    /// The names before the NCS format (the TC- standard, until 2026-10-22) → today's, for LAYTRANS on older drawings.
    public static let legacy: [String: String] = [
        "TC-GRID": grid.name, "TC-DIM": dim.name, "TC-TEXT": text.name, "TC-NORTH": north.name, "TC-SECTION-MARK": sectionMark.name,
        "TC-OBSTACLE": obstacle.name, "TC-ROOF-OUTLINE": roofOutline.name, "TC-ROOF-RIDGE": roofRidge.name, "TC-ROOF-TRUSS": roofTruss.name,
        "TC-ROOF-POST": roofPost.name, "TC-ROOF-PURLIN": roofPurlin.name, "TC-ROOF-SKYLIGHT": roofSkylight.name,
        "TC-ROOF-SECTION": roofSection.name, "TC-ROOF-TABLE": roofTable.name, "TC-PV-MODULE": pvModule.name, "TC-PV-RAIL": pvRail.name,
        "TC-PV-FOOT": pvFoot.name, "TC-PV-CUT": pvCut.name, "TC-PV-KEEPOUT": pvKeepout.name, "TC-PV-TABLE": pvTable.name,
        "TC-PV-RAFTER": pvRafter.name, "TC-PV-BRACE": pvBrace.name, "TC-PV-WALKWAY": pvWalkway.name, "TC-PV-LIFELINE": pvLifeline.name,
        "TC-PV-ACCESS": pvAccess.name, "TC-PV-CABLETRAY": pvCableTray.name, "TC-DETAIL": detail.name, "TC-PV-FOOTING": pvFooting.name,
        "TC-TANK-OUTLINE": tankOutline.name, "TC-TANK-BEAM": tankBeam.name, "TC-TANK-SECTION": tankSection.name, "TC-TANK-SOIL": tankSoil.name,
        "TC-SITE-FRAME": siteFrame.name, "TC-SITE-BUILDING": siteBuilding.name, "TC-SITE-PV-AREA": sitePVArea.name,
        "TC-SITE-PANEL-AREA": sitePanelArea.name, "TC-SITE-CABLE": siteCable.name, "TC-SITE-MEASURE": siteMeasure.name,
        "TC-SITE-CRANE": siteCrane.name, "TC-SITE-SHADE": siteShade.name, "TC-SITE-SHAPE": siteShape.name, "TC-SITE-SYMBOL": siteSymbol.name,
        "TC-SLD-LINE": sldLine.name, "TC-SLD-NEW": sldNew.name, "TC-SLD-OK": sldOK.name, "TC-SLD-WARN": sldWarn.name,
        "TC-SLD-MISSING": sldMissing.name, "TC-SLD-POLE": sldPole.name, "TC-SLD-ASSUMED": sldAssumed.name, "TC-SLD-TEXT": sldText.name,
        "TC-SLD-OTHER": sldOther.name,
    ]

    /// Whether a name follows the format: a discipline letter (P the office's PV), four-letter groups, an optional
    /// one-letter status.
    public static func conforms(_ name: String) -> Bool {
        name.range(of: #"^[GASECP]-[A-Z]{4}(-[A-Z]{4})*(-[NET])?$"#, options: .regularExpression) != nil
    }

    /// The standards file: every layer of the standard (with the hatch layers), a sample line on each with its name and
    /// description, and the old names' map; open it in AutoCAD and save it as a .dws for CHECKSTANDARDS and LAYTRANS,
    /// or as the .dwt new drawings start from.
    public static func standardsFile(millimetres: Bool = false) -> Data {
        var o = SketchDXF.Options(); o.millimetres = millimetres
        var dxf = SketchDXF(options: o)
        var y = 0.0
        dxf.text(text, (0, 2), height: 0.6, "TCRoof CAD layer standard (NCS: Discipline-Major-Minor-Status; E existing, N new, T temporary)")
        for l in everyLayer {
            dxf.line(l, (0, y), (3, y))
            dxf.text(text, (3.5, y), height: 0.3, l.name, middle: true)
            dxf.text(text, (9, y), height: 0.3, l.description, middle: true)
            y -= 0.6
        }
        y -= 1
        dxf.text(text, (0, y), height: 0.45, "Old name -> new name (LAYTRANS)"); y -= 0.8
        for (old, new) in legacy.sorted(by: { $0.key < $1.key }) {
            dxf.text(text, (0, y), height: 0.3, old, middle: true); dxf.text(text, (5, y), height: 0.3, new, middle: true); y -= 0.5
        }
        return dxf.data()
    }
}
