import XCTest
@testable import ExcelExport

/// `StationList` on `Fixtures/station-list.xlsx`: the tracking workbook's layout (the header in row 2 merged over row 3,
/// stations from row 5, a totals row) with made-up values, behind a sheet that mentions `สถานที่ติดตั้ง` and isn't the list.
final class StationListTests: XCTestCase {
    func fixture() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/station-list.xlsx"))
    }

    func testReadsTheStations() throws {
        let s = try StationList.read(fixture())
        XCTAssertEqual(s.count, 5, "the totals row has no station")
        XCTAssertEqual(s[0], StationList.Station(row: 5, phase: 3, order: 1, name: "สถานีผลิตจ่ายน้ำแม่ข่ายชัยบาดาล",
                                                 branch: "การประปาส่วนภูมิภาคสาขาชัยบาดาล", kWp: 163.02, inverterKW: 160,
                                                 latitude: 15.20843, longitude: 101.14031,
                                                 address: "460 ม.8 ต.ลำนารายณ์ อ.ชัยบาดาล จ.ลพบุรี 15130", province: "ลพบุรี"))
        XCTAssertEqual(s[1].latitude, 15.04596, "a coordinate typed as text")
        XCTAssertEqual(s[3].phase, 4)
        XCTAssertEqual(s[3].order, 1, "ลำดับ starts again in each phase")
        XCTAssertNil(s[4].latitude)
        XCTAssertEqual(s[4].address, "ต.ควนโดน อ.ควนโดน จ.สตูล 91160", "a line break in the address is a space")
        XCTAssertEqual(s[4].province, "สตูล")
    }

    func testOtherFilesAreRefused() {
        XCTAssertThrowsError(try StationList.read(Data("not a zip".utf8))) { XCTAssertEqual($0 as? StationList.Failure, .notWorkbook) }
    }

    func testProvince() {
        XCTAssertEqual(StationList.province(in: "216 ถ.นารายณ์มหาราช ต.ทะเลชุบศร อ.เมืองลพบุรี จ.ลพบุรี 15000"), "ลพบุรี")
        XCTAssertEqual(StationList.province(in: "ต.บางไทร อ.บางไทร จังหวัดพระนครศรีอยุธยา"), "พระนครศรีอยุธยา")
        XCTAssertEqual(StationList.province(in: "เขตบางเขน กรุงเทพมหานคร"), "")
    }

    /// The same name in two branches goes by the branch; an unknown station is new; a near name with no clear best asks.
    func testMatchesByNameBranchAndKWp() throws {
        let s = try StationList.read(fixture())
        let existing = [
            StationList.Existing(id: "a", name: "สถานีผลิตน้ำแม่ข่ายชัยบาดาล", kWp: 163.02),
            StationList.Existing(id: "sb", name: "สถานีผลิตน้ำศูนย์ราชการ", branch: "กปภ.สาขาสระบุรี"),
            StationList.Existing(id: "sk", name: "สถานีผลิตน้ำศูนย์ราชการ", branch: "กปภ.สาขาสงขลา"),
        ]
        let rows = StationList.rows(s, existing: existing)
        XCTAssertEqual(rows.map(\.match), ["a", nil, "sb", "sk", nil])
        XCTAssertEqual(rows[1].ranked, [], "บ้านหมี่ is new")
    }

    func testTwoRowsDoNotTakeOneStation() {
        let s = [StationList.Station(row: 5, name: "สถานีผลิตน้ำบ้านนา", kWp: 88.92),
                 StationList.Station(row: 6, name: "สถานีผลิตน้ำบ้านนา")]
        let rows = StationList.rows(s, existing: [StationList.Existing(id: "n", name: "สถานีผลิตน้ำบ้านนา", kWp: 88.92)])
        XCTAssertEqual(rows.map(\.match), ["n", nil], "the row with the kWp too wins")
        XCTAssertEqual(rows[1].ranked, ["n"], "the other still lists it")
    }

    /// `สถานีจ่ายน้ำ กปภ.เขต 7` is all generic words: it matches its own name, so a second import doesn't add it again.
    func testANameWithNoKeyMatchesItself() {
        let s = [StationList.Station(row: 5, name: "สถานีจ่ายน้ำ กปภ.เขต 7")]
        XCTAssertEqual(MPWorkbook.stationKey(s[0].name), "")
        let rows = StationList.rows(s, existing: [StationList.Existing(id: "z", name: "สถานีจ่ายน้ำ  กปภ.เขต 7"),
                                                  StationList.Existing(id: "o", name: "สถานีจ่ายน้ำ กปภ.เขต 8")])
        XCTAssertEqual(rows[0].match, "z")
        XCTAssertEqual(rows[0].ranked, ["z"])
    }

    func testFillsOnlyEmptyFieldsAndShowsDifferences() {
        let row = StationList.Station(row: 5, name: "สถานีผลิตน้ำบ้านนา", branch: "การประปาส่วนภูมิภาคสาขาบ้านนา", kWp: 88.92,
                                      inverterKW: 80, latitude: 14.25748, longitude: 101.0725, address: "53 ม.6 ต.บ้านนา อ.บ้านนา จ.นครนายก 26110")
        let blank = StationList.Existing(id: "n", name: "สถานีผลิตน้ำบ้านนา")
        XCTAssertEqual(StationList.fills(row, blank), StationList.Field.allCases)
        XCTAssertEqual(StationList.differs(row, blank), [])

        let kept = StationList.Existing(id: "n", name: "สถานีผลิตน้ำบ้านนา", branch: "กปภ.สาขาบ้านนา", kWp: 90, inverterKW: 80,
                                        address: "53 ม.6  ต.บ้านนา อ.บ้านนา จ.นครนายก 26110", province: "นครนายก", latitude: 14.25748)
        XCTAssertEqual(StationList.fills(row, kept), [.coordinates], "a half-set position takes the sheet's")
        XCTAssertEqual(StationList.differs(row, kept), [.kWp], "the same branch and address in other words don't differ")
    }
}
