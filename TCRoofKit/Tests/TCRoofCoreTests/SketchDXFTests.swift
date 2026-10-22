import XCTest
@testable import TCRoofCore

/// docs/specs/cad-export-dxf phase 1: the shared `Sketch` → DXF R2000 writer, and `RoofDXF` unchanged on top of it.
final class SketchDXFTests: XCTestCase {
    var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures") }
    func lines(_ d: Data) -> [String] { String(data: d, encoding: .isoLatin1)!.components(separatedBy: "\r\n") }
    /// The entities as written (code, value pairs).
    func rawEntities(_ d: Data) -> [[(String, String)]] { records(d) }
    /// Every record of the ENTITIES section.
    func records(_ d: Data) -> [[(String, String)]] {
        let l = lines(d)
        let start = l.firstIndex(of: "ENTITIES")! + 1, end = l[start...].firstIndex(of: "ENDSEC")! - 1
        var out: [[(String, String)]] = []
        var i = start
        while i + 1 < end {
            if l[i] == "0" { out.append([]) }
            out[out.count - 1].append((l[i], l[i + 1])); i += 2
        }
        return out
    }
    /// The entities with each LWPOLYLINE as the LINEs it draws (its layer, linetype and colour on each), so geometry
    /// checks read every segment the same way.
    func entities(_ d: Data) -> [[(String, String)]] {
        var out: [[(String, String)]] = []
        for r in records(d) {
            guard r.first?.1 == "LWPOLYLINE" else { out.append(r); continue }
            let xs = r.filter { $0.0 == "10" }.map(\.1), ys = r.filter { $0.0 == "20" }.map(\.1), pts = Array(zip(xs, ys))
            let keep = r.filter { ["8", "6", "62"].contains($0.0) }, closed = (Int(value(r, "70") ?? "0") ?? 0) & 1 == 1
            let n = closed ? pts.count : pts.count - 1
            for k in 0..<max(0, n) {
                let a = pts[k], b = pts[(k + 1) % pts.count]
                out.append([("0", "LINE")] + keep + [("10", a.0), ("20", a.1), ("30", "0"), ("11", b.0), ("21", b.1), ("31", "0")])
            }
        }
        return out
    }
    /// The value of the first group `code` after line `i`.
    func after(_ l: [String], _ i: Int, _ code: String) -> String? {
        var k = i + 1
        while k + 1 < l.count { if l[k] == code { return l[k + 1] }; k += 2 }
        return nil
    }
    /// A table's record count.
    func tableCount(_ l: [String], _ name: String) -> Int? {
        guard let i = l.indices.first(where: { l[$0] == name && l[$0 - 1] == "2" && l[$0 - 2] == "TABLE" }) else { return nil }
        return after(l, i, "70").flatMap(Int.init)
    }
    func value(_ e: [(String, String)], _ code: String) -> String? { e.first { $0.0 == code }?.1 }
    func double(_ e: [(String, String)], _ code: String) -> Double { Double(value(e, code)!)! }

    func testGoldenUnchanged() throws {
        let v = RoofDXFTests().roof()
        let cases: [(String, Data)] = [
            ("roof-plan-section-table-mm.dxf", RoofDXF.build(v, parts: [.plan, .section, .table]).data),
            ("roof-plan-m.dxf", RoofDXF.build(v, parts: [.plan], millimetres: false).data),
            ("roof-pv-mm.dxf", RoofDXF.build(v, parts: [.pv]).data),
        ]
        for (name, data) in cases {
            XCTAssertEqual(data, try Data(contentsOf: fixtures.appendingPathComponent(name)), name)
        }
    }

    /// Every CAD program shows the text in the team's Thai SHX font, and the drawing opens framed.
    func testTextStyleExtentsAndView() throws {
        let d = dxf(ops).data(), l = lines(d)
        // the STYLE table: STANDARD and CORDIA (cordia.shx, width 0.85); $TEXTSTYLE names it
        let style = try XCTUnwrap(l.indices.first { l[$0] == "STYLE" && l[$0 - 1] == "0" && after(l, $0, "2") == "CORDIA" })
        XCTAssertEqual(after(l, style, "41"), "0.85")
        XCTAssertEqual(l[l.firstIndex(of: "cordia.shx")! - 1], "3")
        XCTAssertTrue(l.indices.contains { l[$0] == "STYLE" && l[$0 - 1] == "0" && after(l, $0, "2") == "Standard" })
        XCTAssertEqual(l[l.firstIndex(of: "$TEXTSTYLE")! + 2], "CORDIA")
        // every TEXT uses it, at its width
        let texts = entities(d).filter { $0.first?.1 == "TEXT" }
        XCTAssertFalse(texts.isEmpty)
        XCTAssertTrue(texts.allSatisfy { value($0, "7") == "CORDIA" && value($0, "41") == "0.85" })
        // extents cover every line end, and the active viewport is centred on them
        let ext = (Double(l[l.firstIndex(of: "$EXTMIN")! + 2])!, Double(l[l.firstIndex(of: "$EXTMIN")! + 4])!,
                   Double(l[l.firstIndex(of: "$EXTMAX")! + 2])!, Double(l[l.firstIndex(of: "$EXTMAX")! + 4])!)
        for e in entities(d) where e.first?.1 == "LINE" {
            for (x, y) in [("10", "20"), ("11", "21")] {
                XCTAssertTrue(double(e, x) >= ext.0 - 1e-6 && double(e, x) <= ext.2 + 1e-6 && double(e, y) >= ext.1 - 1e-6 && double(e, y) <= ext.3 + 1e-6)
            }
        }
        let vp = try XCTUnwrap(l.firstIndex(of: "*Active"))
        XCTAssertEqual(Double(after(l, vp, "12")!)!, (ext.0 + ext.2) / 2, accuracy: 1e-3)
        XCTAssertEqual(Double(after(l, vp, "22")!)!, (ext.1 + ext.3) / 2, accuracy: 1e-3)
    }

    /// Shapes are LWPOLYLINEs and marked symbols are INSERTs of BLOCKs, so CAD edits them as objects.
    func testPolylinesBlocksAndInserts() throws {
        var d = SketchDXF(options: Self.all)
        let sym: [DrawOp] = [.rect(Box(0, 0, 10, 10), stroke: .black, fill: nil), .line(Pt(0, 0), Pt(10, 10), width: 1, color: .black)]
        let moved = sym.map { op -> DrawOp in
            if case let .rect(b, s, f, w) = op { return .rect(Box(b.x + 50, b.y, b.w, b.h), stroke: s, fill: f, width: w) }
            if case let .line(a, b, w, c, dash) = op { return .line(Pt(a.x + 50, a.y), Pt(b.x + 50, b.y), width: w, color: c, dash: dash) }
            return op
        }
        let bigger: [DrawOp] = [.rect(Box(100, 0, 20, 20), stroke: .black, fill: nil)]
        let ops = sym + moved + bigger + [.polyline([Pt(0, 50), Pt(10, 60), Pt(20, 50)], width: 1, color: .black)]
        d.add(ops, layer: { _, _ in .init("A", aci: 7) }, transform: { ($0.x / 10, (100 - $0.y) / 10) }, pointsPerMetre: 10,
              symbols: [.init("BOX", origin: Pt(0, 0), range: 0..<2), .init("BOX", origin: Pt(50, 0), range: 2..<4),
                        .init("BOX", origin: Pt(100, 0), range: 4..<5)])
        let data = d.data(), l = lines(data)
        // one BLOCKS section between TABLES and ENTITIES: BOX once (the moved copy is the same), BOX-2 for the bigger one
        let blocks = try XCTUnwrap(l.firstIndex(of: "BLOCKS")), ents = try XCTUnwrap(l.firstIndex(of: "ENTITIES"))
        XCTAssertLessThan(blocks, ents)
        XCTAssertEqual(l.indices.filter { l[$0] == "BLOCK" && l[$0 - 1] == "0" }.map { after(l, $0, "2")! }, ["*Model_Space", "*Paper_Space", "BOX", "BOX-2"])
        // block bodies sit on layer 0 in colour BYBLOCK
        let body = Array(l[blocks..<ents])
        XCTAssertTrue(zip(body, body.dropFirst()).contains { $0.0 == "62" && $0.1 == "0" })
        let raw = rawEntities(data)
        let inserts = raw.filter { $0.first?.1 == "INSERT" }
        XCTAssertEqual(inserts.map { value($0, "2")! }, ["BOX", "BOX", "BOX-2"])
        XCTAssertEqual(inserts.map { double($0, "10") }, [0, 5000, 10000])
        // the free polyline: one open LWPOLYLINE of 3 vertices
        let poly = try XCTUnwrap(raw.first { $0.first?.1 == "LWPOLYLINE" })
        XCTAssertEqual(value(poly, "70"), "0")
        XCTAssertEqual(value(poly, "90"), "3")
        XCTAssertEqual(poly.filter { $0.0 == "10" }.count, 3)
        // the extents cover the inserted blocks
        XCTAssertEqual(Double(l[l.firstIndex(of: "$EXTMAX")! + 2])!, 12000, accuracy: 1e-6)
        // a rectangle outside a symbol is one closed polyline
        var r = SketchDXF(options: Self.all)
        r.add([.rect(Box(0, 0, 10, 10), stroke: .black, fill: nil)], layer: { _, _ in .init("A", aci: 7) }, transform: { ($0.x, $0.y) }, pointsPerMetre: 1)
        let rp = rawEntities(r.data())
        XCTAssertEqual(rp.count, 1)
        XCTAssertEqual(value(rp[0], "70"), "1")
        // with both off, the old LINEs
        var o = Self.all; o.polylines = false; o.blocks = false
        var p = SketchDXF(options: o)
        p.add(ops, layer: { _, _ in .init("A", aci: 7) }, transform: { ($0.x, $0.y) }, pointsPerMetre: 1, symbols: [.init("BOX", origin: Pt(0, 0), range: 0..<2)])
        XCTAssertTrue(rawEntities(p.data()).allSatisfy { $0.first?.1 == "LINE" })
        let pl = lines(p.data())
        XCTAssertEqual(pl.indices.filter { pl[$0] == "BLOCK" && pl[$0 - 1] == "0" }.count, 2, "the two spaces only")
    }

    /// The symbols the app's texts use reach CAD as codes or ASCII, never "?".
    func testSymbolsAreCADSafe() {
        let t = String(data: SketchDXF.tis620("1,600 ม² | 432 ม³ | ±5 → ≥ 2 — ok…"), encoding: .isoLatin1)!
        XCTAssertFalse(t.contains("?"))
        XCTAssertTrue(t.contains("%%p5 -> >= 2 - ok..."))
        // a diameter however it was typed
        XCTAssertEqual(String(data: SketchDXF.tis620("ø20 φ25 ⌀32 Ø40"), encoding: .isoLatin1), "%%c20 %%c25 %%c32 %%c40")
        XCTAssertEqual(String(data: SketchDXF.tis620("ม²"), encoding: .isoLatin1), String(data: SketchDXF.tis620("ตร.ม."), encoding: .isoLatin1))
    }

    /// R2000: every object has a unique handle below $HANDSEED, and every entity names its owner.
    func testHandlesAndOwners() throws {
        var d = dxf(ops)
        d.block("M") { b in b.wipeout(.init("A", aci: 7), [(0, 0), (1, 0), (1, 2), (0, 2)]); b.polyline(.init("A", aci: 7), [(0, 0), (1, 0), (1, 2), (0, 2)], closed: true) }
        d.insert(.init("A", aci: 7), "M", at: (3, 3))
        let l = lines(d.data())
        XCTAssertEqual(l[l.firstIndex(of: "$ACADVER")! + 2], "AC1015")
        var handles: [Int] = []
        for i in stride(from: l.firstIndex(of: "ENDSEC")! + 1, to: l.count - 1, by: 2) where l[i] == "5" || l[i] == "105" { handles.append(Int(l[i + 1], radix: 16)!) }
        XCTAssertEqual(Set(handles).count, handles.count, "unique")
        let seed = Int(l[l.firstIndex(of: "$HANDSEED")! + 2], radix: 16)!
        XCTAssertTrue(handles.allSatisfy { $0 < seed })
        // every record of ENTITIES is owned by *Model_Space's record
        let ms = try XCTUnwrap(l.indices.first { l[$0] == "*Model_Space" && l[$0 - 1] == "2" && l[$0 - 10] == "BLOCK_RECORD" })
        let msHandle = l[ms - 8]
        XCTAssertTrue(records(d.data()).allSatisfy { value($0, "330") == msHandle })
        // the wipeout: the module's frame, a closed 5-point boundary, its class and its frame off
        let w = try XCTUnwrap(l.lastIndex(of: "AcDbWipeout"))
        XCTAssertEqual(after(l, w, "11"), "1000"); XCTAssertEqual(after(l, w, "22"), "2000"); XCTAssertEqual(after(l, w, "91"), "5")
        XCTAssertTrue(l.contains("ACAD_WIPEOUT_VARS"))
        XCTAssertTrue(l.indices.contains { l[$0] == "WIPEOUT" && l[$0 - 1] == "1" })
        // the wipeout comes before the outline in the block
        XCTAssertLessThan(l.indices.first { l[$0] == "WIPEOUT" && l[$0 - 1] == "0" }!, l.lastIndex(of: "LWPOLYLINE")!)
        XCTAssertFalse(lines(dxf(ops).data()).contains("ACAD_WIPEOUT_VARS"))
    }

    /// A dimension is a DIMENSION with its look in an anonymous block, a style of its text height, and its measured
    /// length live.
    func testDimensions() throws {
        var d = SketchDXF()
        let l = SketchDXF.Layer("DIM", aci: 3)
        d.dimension(l, (0, 0), (4, 0), at: (2, -1), vertical: false, text: "4.00", height: 0.25)
        d.dimension(l, (5, 0), (5, 3.5), at: (6, 0), vertical: true, text: "Ø 3.50", height: 0.25)
        d.dimension(l, (0, 0), (2, 0), at: (1, 1), vertical: false, text: "ไม่ระบุ", height: 0.3)
        d.dimension(l, (0, 0), (1.5, 0), at: (1, 2), vertical: false, text: "1.5", height: 0.25)
        let data = d.data(), lines = lines(data)
        let dims = rawEntities(data).filter { $0.first?.1 == "DIMENSION" }
        XCTAssertEqual(dims.count, 4)
        XCTAssertEqual(dims.map { value($0, "2")! }, ["*D1", "*D2", "*D3", "*D4"])
        // `1.5` is live too, in a style that drops trailing zeros
        XCTAssertEqual(dims.map { value($0, "3")! }, ["TC_250", "TC_250", "TC_300", "TC_250_Z"])
        XCTAssertEqual(dims.map { value($0, "1")! }, ["", "%%c <>", String(data: SketchDXF.tis620("ไม่ระบุ"), encoding: .isoLatin1)!, ""])
        XCTAssertEqual(dims.map { value($0, "50")! }, ["0", "90", "0", "0"])
        XCTAssertEqual(double(dims[1], "13"), 5000); XCTAssertEqual(double(dims[1], "24"), 3500)
        // the anonymous blocks, flagged 1, each with 2 extension lines, the dimension line, 2 ticks and the text
        let b = try XCTUnwrap(lines.indices.first { lines[$0] == "*D1" && lines[$0 - 1] == "2" && lines[$0 - 2] == "AcDbBlockBegin" })
        XCTAssertEqual(lines[b + 2], "1")
        let end = lines[b...].firstIndex(of: "ENDBLK")!
        XCTAssertEqual(lines[b..<end].filter { $0 == "AcDbLine" }.count, 5)
        XCTAssertTrue(lines[b..<end].contains("4.00"))
        // the styles: ticks, two decimals in metres, CORDIA text
        let st = try XCTUnwrap(lines.indices.first { lines[$0] == "TC_250" && lines[$0 - 1] == "2" && lines[$0 - 2] == "AcDbDimStyleTableRecord" })
        XCTAssertEqual(after(lines, st, "140"), "250"); XCTAssertEqual(after(lines, st, "142"), "100")
        XCTAssertEqual(after(lines, st, "144"), "0.001"); XCTAssertEqual(after(lines, st, "271"), "2")
        let cordia = try XCTUnwrap(lines.indices.first { lines[$0] == "CORDIA" && lines[$0 - 1] == "2" && lines[$0 - 2] == "AcDbTextStyleTableRecord" })
        XCTAssertEqual(after(lines, st, "340"), lines[cordia - 8])
        XCTAssertEqual(tableCount(lines, "DIMSTYLE"), 4)
        let z = try XCTUnwrap(lines.indices.first { lines[$0] == "TC_250_Z" && lines[$0 - 1] == "2" && lines[$0 - 2] == "AcDbDimStyleTableRecord" })
        XCTAssertEqual(after(lines, z, "78"), "8"); XCTAssertEqual(after(lines, st, "78"), "0")
        // the extents take in the dimensions
        XCTAssertEqual(Double(lines[lines.firstIndex(of: "$EXTMAX")! + 2])!, 6200, accuracy: 300)
    }

    static var all: SketchDXF.Options {
        var o = SketchDXF.Options()
        o.dashes = true; o.opColours = true; o.textBoxes = true; o.hatches = true; o.outlineBoxes = true; o.skipFillOnly = true; o.centreText = false
        return o
    }
    let ops: [DrawOp] = [
        .line(Pt(0, 0), Pt(10, 0), width: 1, color: SingleLineLayout.red, dash: [4, 2]),
        .rect(Box(0, 0, 10, 10), stroke: .black, fill: nil),
        .hatch(Box(20, 20, 30, 10), color: .red),
        .circle(Pt(5, 5), r: 2, stroke: .black, fill: nil),
        .polygon([Pt(0, 0), Pt(5, 0), Pt(5, 5)], stroke: .black, fill: .white),
        .polyline([Pt(0, 0), Pt(5, 5), Pt(10, 0)], width: 1, color: .black),
        .text("ก", at: Pt(1, 1), size: 10),
        .textBox("ทดสอบ", Box(0, 0, 50, 20), size: 10),
        .photo(Photo(fileName: "a.jpg", width: 4, height: 3), Box(0, 0, 40, 30)),
        .checkbox(Box(0, 0, 6, 6), on: true),
    ]
    func dxf(_ ops: [DrawOp], _ o: SketchDXF.Options = all, layer: String = "A") -> SketchDXF {
        var d = SketchDXF(options: o)
        d.add(ops, layer: { _, _ in .init(layer, aci: 7) }, transform: { ($0.x / 10, (100 - $0.y) / 10) }, pointsPerMetre: 10)
        return d
    }

    func testEveryOpWritesValidPairs() {
        var d = dxf(ops)
        d.add([.line(Pt(0, 0), Pt(0, 9), width: 1, color: .black)], layer: { _, _ in .init("B", aci: 3) }, transform: { ($0.x, $0.y) }, pointsPerMetre: 10)
        let l = lines(d.data())
        XCTAssertEqual(l.last, "")
        XCTAssertEqual((l.count - 1) % 2, 0, "even number of lines")
        XCTAssertEqual(Array(l.suffix(3)), ["0", "EOF", ""])
        XCTAssertEqual(d.layers, ["A", "B"])
        // layer 0 and the two
        XCTAssertEqual(tableCount(l, "LAYER"), 3)
        XCTAssertEqual(l.filter { $0 == "DASHED" }.count, 2, "declared once, used once")
        XCTAssertEqual(tableCount(l, "LTYPE"), 4)
        XCTAssertEqual(d.entityCount, rawEntities(d.data()).count)
        // red line on a black layer keeps its colour
        XCTAssertEqual(value(entities(d.data())[0], "62"), "1")

        let plain = lines(dxf([.line(Pt(0, 0), Pt(10, 0), width: 1, color: .black)]).data())
        XCTAssertFalse(plain.contains("DASHED"))
        XCTAssertEqual(tableCount(plain, "LTYPE"), 3)
    }

    func testFillOnlyRectWritesNothing() throws {
        XCTAssertEqual(dxf([.rect(Box(0, 0, 10, 10), stroke: nil, fill: .white)]).entityCount, 0)
        XCTAssertEqual(dxf([.circle(Pt(0, 0), r: 2, stroke: nil, fill: .white)]).entityCount, 0)
        // a junction dot: its circle and a SOLID HATCH inside it
        let dot = dxf([.circle(Pt(0, 0), r: 2, stroke: nil, fill: .black)])
        XCTAssertEqual(dot.entityCount, 2)
        let solid = try XCTUnwrap(rawEntities(dot.data()).first { $0.first?.1 == "HATCH" })
        XCTAssertEqual(value(solid, "2"), "SOLID"); XCTAssertEqual(value(solid, "70"), "1"); XCTAssertEqual(value(solid, "40"), "200")
        // a translucent tint is no solid
        XCTAssertEqual(dxf([.circle(Pt(0, 0), r: 2, stroke: nil, fill: RGBA(1, 0, 0, 0.3))]).entityCount, 1)
    }

    func testTextAlignAndAngle() {
        var d = SketchDXF()
        d.text(.init("T", aci: 7), (1, 2), height: 0.5, "x", align: .right, angle: 90)
        let e = entities(d.data())[0]
        XCTAssertEqual(value(e, "72"), "2")
        XCTAssertEqual(value(e, "50"), "90")
        XCTAssertEqual(double(e, "11"), 1000)
        // a sketch text turned −90° (reading upwards) is +90° in DXF
        let up = entities(dxf([.text("x", at: Pt(0, 0), size: 10, angle: -90)]).data())[0]
        XCTAssertEqual(value(up, "50"), "90")
        XCTAssertEqual(value(up, "73"), "2")
    }

    func testTextBoxWrapsInsideBox() {
        let box = Box(10, 10, 60, 60)
        let d = dxf([.textBox(String(repeating: "สร้างจากข้อมูลสำรวจ ", count: 4), box, size: 8)])
        let texts = entities(d.data()).filter { $0[0].1 == "TEXT" }
        XCTAssertGreaterThanOrEqual(texts.count, 2)
        for t in texts {
            // back to sketch points: x = X·10/1000, y = 100 − Y·10/1000
            let x = double(t, "10") / 100, y = 100 - double(t, "20") / 100
            XCTAssertTrue(x >= box.x - 0.01 && x <= box.maxX + 0.01 && y >= box.y && y <= box.maxY + 1, "\(x), \(y)")
        }
    }

    /// A hatch is one HATCH entity: ANSI31 in the box, its lines as far apart as the sketch's.
    func testHatchIsAnEntity() throws {
        let box = Box(20, 20, 30, 10)
        let h = try XCTUnwrap(rawEntities(dxf([.hatch(box, color: .red, spacing: 4)]).data()).first)
        XCTAssertEqual(h.first?.1, "HATCH")
        XCTAssertEqual(value(h, "2"), "ANSI31"); XCTAssertEqual(value(h, "70"), "0"); XCTAssertEqual(value(h, "93"), "4")
        // the boundary: the box in drawing units (x·100, (100 − y)·100)
        let xs = h.filter { $0.0 == "10" }.dropFirst().map { Double($0.1)! }, ys = h.filter { $0.0 == "20" }.dropFirst().map { Double($0.1)! }
        XCTAssertEqual(Set(xs), [2000, 5000]); XCTAssertEqual(Set(ys), [7000, 8000])
        // 4 pt along x at 10 pt/m is 0.4 m, so 400 / √2 mm across the 45° lines
        let across = 400 / 2.squareRoot()
        XCTAssertEqual(double(h, "41"), across / 3.175, accuracy: 1e-3)
        XCTAssertEqual(double(h, "46"), across / 2.squareRoot(), accuracy: 1e-3)
    }

    func testHatchLinesStayInBox() {
        let box = Box(20, 20, 30, 10)
        var o = Self.all; o.hatchEntities = false
        let d = dxf([.hatch(box, color: .red, spacing: 4)], o)
        let ls = entities(d.data())
        XCTAssertGreaterThan(ls.count, 5)
        for e in ls {
            for (cx, cy) in [("10", "20"), ("11", "21")] {
                let x = double(e, cx) / 100, y = 100 - double(e, cy) / 100
                XCTAssertTrue(x >= box.x - 1e-6 && x <= box.maxX + 1e-6 && y >= box.y - 1e-6 && y <= box.maxY + 1e-6, "\(x), \(y)")
            }
        }
    }

    func testYFlip() {
        let H = 7.5
        var d = SketchDXF()
        d.add([.line(Pt(0, 0), Pt(1, 0), width: 1, color: .black)], layer: { _, _ in .init("L", aci: 7) },
              transform: { ($0.x, H - $0.y) }, pointsPerMetre: 1)
        let e = entities(d.data())[0]
        XCTAssertEqual(double(e, "10"), 0)
        XCTAssertEqual(double(e, "20"), H * 1000)
    }

    func testACI() {
        XCTAssertEqual(SketchDXF.aci(SingleLineLayout.red), 1)
        XCTAssertEqual(SketchDXF.aci(SingleLineLayout.ink), 7)
        XCTAssertEqual(SketchDXF.aci(SingleLineLayout.blue), 5)
        XCTAssertEqual(SketchDXF.aci(SingleLineLayout.green), 3)
        XCTAssertEqual(SketchDXF.aci(SingleLineLayout.amber), 30)
        XCTAssertEqual(SketchDXF.aci(SingleLineLayout.grey), 8)
        XCTAssertEqual(SketchDXF.aci(.white), 7)
    }
}
