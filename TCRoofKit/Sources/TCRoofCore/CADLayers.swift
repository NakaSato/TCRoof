import Foundation

/// The team's CAD layer standard (docs/specs/cad-export-dxf, Layers): every layer the DXF exports write, named
/// `TC-<area>-<item>` (shared layers `TC-<item>`), each with its colour, linetype, lineweight, whether it plots and a
/// description in Thai and English (the layer manager's Description column). The C1 roof, the D1 tank, the A2 site
/// plan and the single line diagram all take their layers from here, so the same thing is on the same layer in every
/// file.
public enum CADLayers {

    // shared
    public static let grid = SketchDXF.Layer("TC-GRID", aci: 8, linetype: .center, lineweight: 18, description: "เส้นกริดและหัวกริด / Grid lines and bubbles")
    public static let dim = SketchDXF.Layer("TC-DIM", aci: 3, lineweight: 18, description: "ระยะ / Dimensions")
    public static let text = SketchDXF.Layer("TC-TEXT", aci: 7, lineweight: 25, description: "ข้อความและหัวแบบ / Text and captions")
    public static let north = SketchDXF.Layer("TC-NORTH", aci: 7, lineweight: 25, description: "ลูกศรทิศเหนือ / North arrow")
    public static let sectionMark = SketchDXF.Layer("TC-SECTION-MARK", aci: 1, lineweight: 25, description: "เครื่องหมายรูปตัด / Section marks")
    public static let obstacle = SketchDXF.Layer("TC-OBSTACLE", aci: 1, lineweight: 25, description: "สิ่งกีดขวางและช่องเปิด / Obstacles and openings")

    // C1 roof
    public static let roofOutline = SketchDXF.Layer("TC-ROOF-OUTLINE", aci: 7, lineweight: 50, description: "ขอบหลังคา / Roof outline")
    public static let roofRidge = SketchDXF.Layer("TC-ROOF-RIDGE", aci: 1, lineweight: 35, description: "สันหลังคา / Ridge")
    public static let roofTruss = SketchDXF.Layer("TC-ROOF-TRUSS", aci: 5, lineweight: 35, description: "โครงถัก จันทัน ชายคา / Trusses, rafters, eaves")
    public static let roofPost = SketchDXF.Layer("TC-ROOF-POST", aci: 7, lineweight: 35, description: "เสา / Posts")
    public static let roofPurlin = SketchDXF.Layer("TC-ROOF-PURLIN", aci: 30, lineweight: 18, description: "แป / Purlins")
    public static let roofSkylight = SketchDXF.Layer("TC-ROOF-SKYLIGHT", aci: 4, lineweight: 25, description: "แผ่นโปร่งแสง / Skylights")
    public static let roofSection = SketchDXF.Layer("TC-ROOF-SECTION", aci: 7, lineweight: 35, description: "รูปตัด A-A / Section A-A")
    public static let roofTable = SketchDXF.Layer("TC-ROOF-TABLE", aci: 7, lineweight: 18, description: "ตารางขนาดชิ้นส่วน / Member schedule")

    // PV, on the roof and on the tank
    public static let pvModule = SketchDXF.Layer("TC-PV-MODULE", aci: 150, lineweight: 25, description: "แผงโซลาร์ / PV modules")
    public static let pvRail = SketchDXF.Layer("TC-PV-RAIL", aci: 2, lineweight: 18, description: "รางยึดแผง / Mounting rails")
    public static let pvFoot = SketchDXF.Layer("TC-PV-FOOT", aci: 250, lineweight: 18, description: "ขายึดราง / Rail feet")
    public static let pvCut = SketchDXF.Layer("TC-PV-CUT", aci: 1, lineweight: 18, description: "จุดตัดราง / Rail cuts")
    public static let pvKeepout = SketchDXF.Layer("TC-PV-KEEPOUT", aci: 1, linetype: .hidden, lineweight: 18, description: "ระยะห้ามวางแผง / Keep-out zones")
    public static let pvTable = SketchDXF.Layer("TC-PV-TABLE", aci: 170, lineweight: 25, description: "โต๊ะแผงและฐานราก / Module tables and footings")
    public static let pvRafter = SketchDXF.Layer("TC-PV-RAFTER", aci: 1, lineweight: 25, description: "คานเอียงรับราง / Rafters")
    public static let pvBrace = SketchDXF.Layer("TC-PV-BRACE", aci: 4, lineweight: 18, description: "ค้ำยันระหว่างเสา / Bracing between posts")
    public static let pvWalkway = SketchDXF.Layer("TC-PV-WALKWAY", aci: 10, lineweight: 25, description: "ทางเดิน HDG 0.30×2.40 ม. ขาตั้ง L-Feet / Walkway grating and L-feet")
    public static let pvLifeline = SketchDXF.Layer("TC-PV-LIFELINE", aci: 130, lineweight: 25, description: "สลิงกันตก 6 มม. เสารับ และราง / Lifeline wire rope, supports and rail")
    public static let pvCableTray = SketchDXF.Layer("TC-PV-CABLETRAY", aci: 3, lineweight: 25, description: "รางเคเบิลและท่อ PPR / Cable tray and PPR pipe")
    public static let detail = SketchDXF.Layer("TC-DETAIL", aci: 7, lineweight: 18, description: "แบบรายละเอียดของทีม / Team detail sheets")
    public static let pvFooting = SketchDXF.Layer("TC-PV-FOOTING", aci: 3, lineweight: 25, description: "ฐานรากและฐานเสา / Footings and post bases")

    // D1 tank
    public static let tankOutline = SketchDXF.Layer("TC-TANK-OUTLINE", aci: 7, lineweight: 50, description: "ขอบถังน้ำใส / Tank outline")
    public static let tankBeam = SketchDXF.Layer("TC-TANK-BEAM", aci: 8, linetype: .hidden, lineweight: 25, description: "คานหลังคาถัง / Tank roof beams")
    public static let tankSection = SketchDXF.Layer("TC-TANK-SECTION", aci: 7, lineweight: 35, description: "รูปตัดถัง พื้น ผนัง เสา ฐานราก / Tank sections, slabs, walls, columns, footings")
    public static let tankSoil = SketchDXF.Layer("TC-TANK-SOIL", aci: 32, lineweight: 25, description: "ดินและระดับดิน / Soil and ground line")

    // A2 site plan
    public static let siteFrame = SketchDXF.Layer("TC-SITE-FRAME", aci: 8, lineweight: 18, plot: false, description: "กรอบภาพผังบริเวณ (ไม่พิมพ์) / Site picture frame (no plot)")
    public static let siteBuilding = SketchDXF.Layer("TC-SITE-BUILDING", aci: 4, lineweight: 35, description: "อาคาร / Buildings")
    public static let sitePVArea = SketchDXF.Layer("TC-SITE-PV-AREA", aci: 5, lineweight: 25, description: "พื้นที่ติดตั้งแผงบนอาคาร / PV area on buildings")
    public static let sitePanelArea = SketchDXF.Layer("TC-SITE-PANEL-AREA", aci: 1, lineweight: 25, description: "พื้นที่วางแผงที่วาด / Drawn panel areas")
    public static let siteCable = SketchDXF.Layer("TC-SITE-CABLE", aci: 5, linetype: .hidden, lineweight: 25, description: "แนวสายไฟ / Cable routes")
    public static let siteMeasure = SketchDXF.Layer("TC-SITE-MEASURE", aci: 3, lineweight: 18, description: "ระยะที่วัด / Measurements")
    public static let siteCrane = SketchDXF.Layer("TC-SITE-CRANE", aci: 30, linetype: .hidden, lineweight: 25, description: "ทางเข้ารถเครน / Crane access")
    public static let siteShade = SketchDXF.Layer("TC-SITE-SHADE", aci: 30, lineweight: 18, description: "เงาบัง / Shading")
    public static let siteShape = SketchDXF.Layer("TC-SITE-SHAPE", aci: 4, lineweight: 25, description: "ขอบเขตและจุดติดตั้ง / Boundaries and PV points")
    public static let siteSymbol = SketchDXF.Layer("TC-SITE-SYMBOL", aci: 7, lineweight: 25, description: "สัญลักษณ์อุปกรณ์ / Equipment symbols")

    // single line diagram, by what a colour means on the diagram (`SingleLineLayout.color`)
    public static let sldLine = SketchDXF.Layer("TC-SLD-LINE", aci: 7, lineweight: 35, description: "อุปกรณ์และสายที่ทราบค่า / Known equipment and wiring")
    public static let sldNew = SketchDXF.Layer("TC-SLD-NEW", aci: 5, lineweight: 35, description: "อุปกรณ์ติดตั้งใหม่ / New equipment")
    public static let sldOK = SketchDXF.Layer("TC-SLD-OK", aci: 3, lineweight: 25, description: "ผ่านการตรวจ / Checked OK")
    public static let sldWarn = SketchDXF.Layer("TC-SLD-WARN", aci: 30, lineweight: 25, description: "ควรตรวจสอบ / To check")
    public static let sldMissing = SketchDXF.Layer("TC-SLD-MISSING", aci: 1, lineweight: 25, description: "ค่าที่ยังไม่มี / Missing values")
    public static let sldPole = SketchDXF.Layer("TC-SLD-POLE", aci: 8, lineweight: 25, description: "เสาไฟฟ้า / Utility poles")
    public static let sldAssumed = SketchDXF.Layer("TC-SLD-ASSUMED", aci: 8, lineweight: 18, description: "ค่าที่สมมติ / Assumed values")
    public static let sldText = SketchDXF.Layer("TC-SLD-TEXT", aci: 7, lineweight: 25, description: "ข้อความแผนภาพ / Diagram text")
    public static let sldOther = SketchDXF.Layer("TC-SLD-OTHER", aci: 7, lineweight: 25, description: "อื่น ๆ / Other")

    /// Every layer of the standard, in the order the spec lists them.
    public static let all: [SketchDXF.Layer] = [
        grid, dim, text, north, sectionMark, obstacle,
        roofOutline, roofRidge, roofTruss, roofPost, roofPurlin, roofSkylight, roofSection, roofTable,
        pvModule, pvRail, pvFoot, pvCut, pvKeepout, pvTable, pvRafter, pvBrace, pvFooting, pvWalkway, pvLifeline, pvCableTray, detail,
        tankOutline, tankBeam, tankSection, tankSoil,
        siteFrame, siteBuilding, sitePVArea, sitePanelArea, siteCable, siteMeasure, siteCrane, siteShade, siteShape, siteSymbol,
        sldLine, sldNew, sldOK, sldWarn, sldMissing, sldPole, sldAssumed, sldText, sldOther,
    ]

    /// The standard layer of that name.
    public static func named(_ name: String) -> SketchDXF.Layer? { all.first { $0.name == name } }
}
