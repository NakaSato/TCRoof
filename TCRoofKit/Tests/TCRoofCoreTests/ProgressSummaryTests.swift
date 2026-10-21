import XCTest
@testable import TCRoofCore

/// Progress helpers read by the sidebar (sheet overflow) and the PDF (field text, one-line facts).
final class ProgressSummaryTests: XCTestCase {
    private func field(_ id: String) throws -> FieldSpec {
        try XCTUnwrap(Schema.jobGroups.flatMap(\.fields).first { $0.id == id })
    }

    func testStationOverflowWhenSectionsOutnumberTheSheetSlots() {
        var j = Job.new(template: JobTemplate.all[2])
        for _ in 0..<3 { j.modules.append(SurveyModule(type: .panel)) }
        for _ in 0..<2 { j.modules.append(SurveyModule(type: .backfeed)) }
        XCTAssertTrue(j.stationOverflow.isEmpty, "3 B1 and 2 B4 fill their slots exactly")

        j.modules.append(SurveyModule(type: .panel))
        j.modules.append(SurveyModule(type: .backfeed))
        j.modules.append(SurveyModule(type: .roof))   // C1 has no station slots
        XCTAssertEqual(j.stationOverflow, [.panel: 4, .backfeed: 3])
    }

    func testTransformerText() throws {
        var a = Transformer(kva: "630"); a.mdb = ["800", "", "400", "", "", ""]
        let b = Transformer(kva: "")
        var v = Values()
        v["trafos"] = .transformers([a, b])
        XCTAssertEqual(try field("trafos").displayText(v), "TR1 630kVA: MDB1=800A MDB3=400A | TR2 -kVA: ")
    }

    func testSiteMarksText() throws {
        var v = Values()
        v["siteMarks"] = .marks([MapMark(kind: .trafo, x: 0, y: 0), MapMark(kind: .meter, x: 0, y: 0), MapMark(kind: .trafo, x: 1, y: 1)])
        XCTAssertEqual(try field("siteMarks").displayText(v), "PEA METER, TRANSFORMER 1, TRANSFORMER 2")
        XCTAssertEqual(try field("siteMarks").displayText(Values()), "", "nothing placed")
    }

    func testDetailedRoofFacts() {
        let j = Job.new(template: JobTemplate.all[2])
        var m = SurveyModule(type: .roofForm)
        m.values["roofShape"] = .choice("อื่นๆ", other: "ทรงปั้นหยา")
        m.values["roofMaterial"] = .choice("เมทัลชีท", other: "")
        m.values["facing"] = .choice("ใต้", other: "")
        m.values["panelAreaWidth"] = .text("1200")
        m.values["panelAreaLength"] = .text("800")
        XCTAssertEqual(j.facts(m), "ทรงปั้นหยา | เมทัลชีท | หันทิศใต้ | พื้นที่ 1200 x 800 ซม.")

        // half an area is no area; an empty "อื่นๆ" still says อื่นๆ
        m.values["panelAreaLength"] = .text(" ")
        m.values["roofShape"] = .choice("อื่นๆ", other: "")
        m.values["facing"] = nil
        XCTAssertEqual(j.facts(m), "อื่นๆ | เมทัลชีท")
    }
}
