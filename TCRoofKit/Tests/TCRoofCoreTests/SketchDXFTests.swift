import XCTest
@testable import TCRoofCore

/// docs/specs/cad-export-dxf phase 1: the shared `Sketch` → DXF R12 writer, and `RoofDXF` unchanged on top of it.
final class SketchDXFTests: XCTestCase {
    var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures") }
    func lines(_ d: Data) -> [String] { String(data: d, encoding: .isoLatin1)!.components(separatedBy: "\r\n") }
    /// (code, value) pairs of the ENTITIES section.
    func entities(_ d: Data) -> [[(String, String)]] {
        let l = lines(d)
        let start = l.firstIndex(of: "ENTITIES")! + 1, end = l.lastIndex(of: "ENDSEC")! - 1
        var out: [[(String, String)]] = []
        var i = start
        while i + 1 < end {
            if l[i] == "0" { out.append([]) }
            out[out.count - 1].append((l[i], l[i + 1])); i += 2
        }
        return out
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
        let table = l.firstIndex(of: "LAYER")!
        XCTAssertEqual(l[table + 2], "2")
        XCTAssertEqual(l.filter { $0 == "DASHED" }.count, 2, "declared once, used once")
        XCTAssertEqual(l[l.firstIndex(of: "LTYPE")! + 2], "2")
        XCTAssertEqual(d.entityCount, entities(d.data()).count)
        // red line on a black layer keeps its colour
        XCTAssertEqual(value(entities(d.data())[0], "62"), "1")

        let plain = lines(dxf([.line(Pt(0, 0), Pt(10, 0), width: 1, color: .black)]).data())
        XCTAssertFalse(plain.contains("DASHED"))
        XCTAssertEqual(plain[plain.firstIndex(of: "LTYPE")! + 2], "1")
    }

    func testFillOnlyRectWritesNothing() {
        XCTAssertEqual(dxf([.rect(Box(0, 0, 10, 10), stroke: nil, fill: .white)]).entityCount, 0)
        XCTAssertEqual(dxf([.circle(Pt(0, 0), r: 2, stroke: nil, fill: .white)]).entityCount, 0)
        XCTAssertEqual(dxf([.circle(Pt(0, 0), r: 2, stroke: nil, fill: .black)]).entityCount, 1, "a junction dot")
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

    func testHatchLinesStayInBox() {
        let box = Box(20, 20, 30, 10)
        let d = dxf([.hatch(box, color: .red, spacing: 4)])
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
