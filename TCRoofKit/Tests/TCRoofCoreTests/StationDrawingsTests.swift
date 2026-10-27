import XCTest
@testable import TCRoofCore

/// `StationDrawing`: the station's construction drawings and their revisions (docs/ui/install-tracking-ipad-settings §5 item 6).
final class StationDrawingsTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_790_000_000)

    func testNextRevIsTwoDigits() {
        XCTAssertEqual(StationDrawing.next(after: "00"), "01")
        XCTAssertEqual(StationDrawing.next(after: "09"), "10")
        XCTAssertEqual(StationDrawing.next(after: "1"), "02")
        XCTAssertEqual(StationDrawing.next(after: ""), "00")
        var d = StationDrawing(id: "E-01", title: "SLD", ext: "PDF")
        XCTAssertEqual(d.ext, "pdf")
        XCTAssertNil(d.latest)
        XCTAssertEqual(d.nextRev, "00")
        d.revisions = [.init(rev: "00", date: day, reason: "", by: "a", file: "x"), .init(rev: "01", date: day, reason: "r", by: "a", file: "y")]
        XCTAssertEqual(d.latest?.rev, "01")
        XCTAssertEqual(d.nextRev, "02")
    }

    func testNewDrawingStartsAtZeroWithoutAReason() throws {
        let up = StationDrawings.Upload(newTitle: "ผังหลังคา", ext: "DWG")
        XCTAssertNil(StationDrawings.problem(up, in: []))
        let out = try XCTUnwrap(StationDrawings.appending(up, to: [], by: "me@tcroof.test", date: day))
        XCTAssertEqual(out.list.count, 1)
        XCTAssertEqual(out.drawing, "D-01")
        XCTAssertEqual(out.revision.rev, "00")
        XCTAssertEqual(out.revision.file, "D-01 REV 00.dwg")
        XCTAssertEqual(out.list[0].ext, "dwg")
        XCTAssertEqual(StationDrawings.newID(in: out.list), "D-02")
    }

    func testReasonRequiredFromRevOne() throws {
        let first = try XCTUnwrap(StationDrawings.appending(.init(newID: "A-01", newTitle: "Roof", ext: "pdf"), to: [], by: "a", date: day)).list
        var up = StationDrawings.Upload(drawing: "A-01", ext: "pdf")
        XCTAssertEqual(StationDrawings.rev(of: up, in: first), "01")
        XCTAssertEqual(StationDrawings.problem(up, in: first), "ใส่เหตุผลการแก้ไข")
        XCTAssertNil(StationDrawings.appending(up, to: first, by: "a", date: day))
        up.reason = "   "
        XCTAssertNotNil(StationDrawings.problem(up, in: first), "spaces are no reason")
        up.reason = "ย้ายแนวราง"
        let second = try XCTUnwrap(StationDrawings.appending(up, to: first, by: "a", date: day))
        XCTAssertEqual(second.list[0].revisions.map(\.rev), ["00", "01"], "appended, never replaced")
        XCTAssertEqual(second.revision.reason, "ย้ายแนวราง")
    }

    func testUploadNeedsAFileANameAndAFreeCode() throws {
        XCTAssertEqual(StationDrawings.problem(.init(newTitle: "x"), in: []), "เลือกไฟล์ PDF, DWG หรือรูป")
        XCTAssertEqual(StationDrawings.problem(.init(newTitle: "x", ext: "zip"), in: []), "เลือกไฟล์ PDF, DWG หรือรูป")
        XCTAssertEqual(StationDrawings.problem(.init(newTitle: " ", ext: "pdf"), in: []), "ใส่ชื่อแบบ")
        let list = try XCTUnwrap(StationDrawings.appending(.init(newID: "E-01", newTitle: "SLD", ext: "pdf"), to: [], by: "a", date: day)).list
        XCTAssertEqual(StationDrawings.problem(.init(newID: "E-01", newTitle: "อีกแบบ", ext: "pdf"), in: list), "รหัสแบบนี้มีแล้ว")
        XCTAssertEqual(StationDrawings.problem(.init(drawing: "Z-09", ext: "pdf", reason: "r"), in: list), "ไม่พบแบบนี้")
    }

    func testOldJSONDecodesAndRoundTrips() throws {
        XCTAssertEqual(StationDrawings.decode(nil), [])
        XCTAssertEqual(StationDrawings.decode("not json"), [])
        let old = StationDrawings.decode(#"[{"id":"E-01","revisions":[{"rev":"00","file":"E-01 REV 00.pdf"}]}]"#)
        XCTAssertEqual(old.first?.title, "")
        XCTAssertEqual(old.first?.revisions.first?.reason, "")
        XCTAssertNil(old.first?.revisions.first?.driveID)
        let recorded = StationDrawings.recordingDriveIDs(old, uploaded: ["E-01 REV 00.pdf": "drive-1"])
        XCTAssertEqual(recorded.first?.revisions.first?.driveID, "drive-1")
        XCTAssertEqual(StationDrawings.decode(StationDrawings.encode(recorded)), recorded)
    }
}
