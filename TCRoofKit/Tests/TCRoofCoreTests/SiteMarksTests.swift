import XCTest
@testable import TCRoofCore

final class SiteMarksTests: XCTestCase {
    private func texts(_ ops: [DrawOp]) -> [String] {
        ops.compactMap { if case .text(let s, _, _, _, _, _, _) = $0 { return s } else { return nil } }
    }

    func testLabelsNumberOnlyRepeatedKinds() {
        let t1 = MapMark(kind: .trafo, x: 0.1, y: 0.1), meter = MapMark(kind: .meter, x: 0.2, y: 0.2)
        let t2 = MapMark(kind: .trafo, x: 0.3, y: 0.3)
        let labels = SiteMarks.labels([t1, meter, t2])
        XCTAssertEqual(labels[t1.id], "TRANSFORMER 1")
        XCTAssertEqual(labels[t2.id], "TRANSFORMER 2")
        XCTAssertEqual(labels[meter.id], "PEA METER")
        XCTAssertTrue(SiteMarks.labels([]).isEmpty)
    }

    func testDefaultLabelsCountWithinTheirKind() {
        let mdbs = [MapMark(kind: .mdb, x: 0, y: 0), MapMark(kind: .mdb, x: 0, y: 0)]
        let inv = MapMark(kind: .inv, x: 0, y: 0), tx = MapMark(kind: .trafo, x: 0, y: 0)
        let roofs = [MapMark(kind: .roofLabel, x: 0, y: 0), MapMark(kind: .roofLabel, x: 0, y: 0)]
        let all = mdbs + [inv, tx] + roofs
        XCTAssertEqual(SiteMarks.defaultLabel(mdbs[1], in: all), "MDB-2")
        XCTAssertEqual(SiteMarks.defaultLabel(mdbs[0], in: [mdbs[0]]), "MDB")
        XCTAssertEqual(SiteMarks.defaultLabel(inv, in: all), "INV")
        XCTAssertEqual(SiteMarks.defaultLabel(inv, in: all + [MapMark(kind: .inv, x: 0, y: 0)]), "INV 1")
        XCTAssertEqual(SiteMarks.defaultLabel(tx, in: all), "TX 1")
        XCTAssertEqual(SiteMarks.defaultLabel(roofs[1], in: all), "หลังคา 2")
        XCTAssertEqual(SiteMarks.defaultLabel(MapMark(kind: .stairs, x: 0, y: 0), in: all), "บันได")
    }

    func testSuggestedValuesFollowTheA3Answers() {
        var a = Transformer(kva: "630"); a.mdb = ["800", " ", "400", "", "", ""]
        var b = Transformer(kva: "1250"); b.mdb = ["1600", "", "", "", "", ""]
        let trafos = [a, b]
        let oneTx = [MapMark(kind: .trafo, x: 0, y: 0)]
        XCTAssertEqual(SiteMarks.suggestedValue(.trafo, existing: [], trafos: trafos), "630")
        XCTAssertEqual(SiteMarks.suggestedValue(.trafo, existing: oneTx, trafos: trafos), "1250")
        XCTAssertEqual(SiteMarks.suggestedValue(.trafo, existing: oneTx + oneTx, trafos: trafos), "", "no third transformer")
        // MDBs take the breaker sizes across transformers in order, skipping blanks
        let mdb = { (n: Int) in Array(repeating: MapMark(kind: .mdb, x: 0, y: 0), count: n) }
        XCTAssertEqual(SiteMarks.suggestedValue(.mdb, existing: mdb(0), trafos: trafos), "800")
        XCTAssertEqual(SiteMarks.suggestedValue(.mdb, existing: mdb(1), trafos: trafos), "400")
        XCTAssertEqual(SiteMarks.suggestedValue(.mdb, existing: mdb(2), trafos: trafos), "1600")
        XCTAssertEqual(SiteMarks.suggestedValue(.mdb, existing: mdb(3), trafos: trafos), "")
        XCTAssertEqual(SiteMarks.suggestedValue(.meter, existing: [], trafos: trafos), "")
    }

    func testRatingAddsTheUnitOnce() {
        XCTAssertEqual(MapMark(kind: .trafo, x: 0, y: 0, value: "800").rating, "800 kVA")
        XCTAssertEqual(MapMark(kind: .trafo, x: 0, y: 0, value: "800 kVA").rating, "800 kVA")
        XCTAssertEqual(MapMark(kind: .mdb, x: 0, y: 0, value: " 1250 ").rating, "1250 AT")
        XCTAssertEqual(MapMark(kind: .mdb, x: 0, y: 0, value: "  ").rating, "")
        XCTAssertEqual(MapMark(kind: .meter, x: 0, y: 0, value: "15(45)").rating, "", "no unit, no rating")
    }

    func testPositionsAreClampedToThePicture() {
        let m = MapMark(kind: .meter, x: -0.2, y: 1.4)
        XCTAssertEqual(m.x, 0)
        XCTAssertEqual(m.y, 1)
    }

    func testOldMarksDecodeWithDefaults() throws {
        let m = try JSONDecoder().decode(MapMark.self, from: Data(#"{"kind":"trafo","x":0.5,"y":0.25}"#.utf8))
        XCTAssertEqual(m.kind, .trafo)
        XCTAssertEqual(m.value, "")
        XCTAssertEqual(m.label, "")
        XCTAssertNil(m.module)
        XCTAssertNil(m.link)
        let round = try JSONDecoder().decode(MapMark.self, from: JSONEncoder().encode(MapMark(kind: .mdb, x: 0.1, y: 0.2, value: "800", label: "MDP-1", link: "bd:x")))
        XCTAssertEqual(round.label, "MDP-1")
        XCTAssertEqual(round.link, "bd:x")
    }

    func testDrawingTextsForEachKindOfName() {
        let box = Box(0, 0, 1000, 600)
        let tx = MapMark(kind: .trafo, x: 0.5, y: 0.5, value: "630")
        let named = MapMark(kind: .meter, x: 0.2, y: 0.2, label: "มิเตอร์หน้าโรงงาน")
        let office = MapMark(kind: .office, x: 0.8, y: 0.8)
        let roof = MapMark(kind: .roofLabel, x: 0.4, y: 0.9, label: "หลังคา A")
        let ze = MapMark(kind: .zeroExport, x: 0.1, y: 0.9, value: "lv")
        let all = texts(SiteMarks.ops([tx, named, office, roof, ze], in: box))
        XCTAssertTrue(all.contains("TX 1"), "a transformer's default name goes inside it")
        XCTAssertTrue(all.contains("630 kVA"), "and its rating in a tag")
        XCTAssertTrue(all.contains("มิเตอร์หน้าโรงงาน"), "other kinds write the engineer's name above")
        XCTAssertTrue(all.contains("Site Office"))
        XCTAssertTrue(all.contains("หลังคา A"))
        XCTAssertTrue(all.contains("LV"))
        XCTAssertEqual(SiteMarks.zeroExportLine(MapMark(kind: .zeroExport, x: 0, y: 0)), "MV", "empty is MV")
        XCTAssertEqual(texts(SiteMarks.ops([MapMark(kind: .roofLabel, x: 0, y: 0)], in: box)), ["หลังคา"])
    }

    /// Every kind needs its palette text, badge and fallback symbol; only `water` and `emergency` have no design icon.
    func testEveryKindHasItsTexts() {
        for k in MarkKind.allCases {
            XCTAssertFalse(k.paletteTitle.isEmpty, "\(k)")
            XCTAssertFalse(k.paletteDetail.isEmpty, "\(k)")
            XCTAssertFalse(k.badge.isEmpty, "\(k)")
            XCTAssertFalse(k.symbol.isEmpty, "\(k)")
            XCTAssertEqual(k.id, k.rawValue)
            XCTAssertEqual(k.assetName == nil, k == .water || k == .emergency, "\(k)")
        }
        XCTAssertEqual(Set(MarkKind.palette.map(\.paletteTitle)).count, MarkKind.palette.count, "palette names are distinct")
    }
}
