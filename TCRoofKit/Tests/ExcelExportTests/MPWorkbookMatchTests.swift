import XCTest
@testable import ExcelExport

/// Matching plan files to stations when many are imported at once.
final class MPWorkbookMatchTests: XCTestCase {
    let project = "โครงการจัดการพลังงานไฟฟ้าจากระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์ที่ติดตั้งบนหลังคา (Solar Rooftop) ภายใน สถานีผลิตน้ำประปาบางไทร การประปาส่วนภูมิภาคสาขาพระนครศรีอยุธยา ขนาดกำลังผลิต 414.96 kWp"
    let file = "37. Master Plan Weekly PWA  สถานีผลิตน้ำประปาบางไทร การประปาส่วนภูมิภาคสาขาพระนครศรีอยุธยา.xlsx"

    func testReadsTheStationFromTheProjectLine() {
        let s = MPWorkbook.station(project: project, fileName: file)
        XCTAssertEqual(s.name, "สถานีผลิตน้ำประปาบางไทร")
        XCTAssertEqual(s.kWp, 414.96)
        XCTAssertEqual(s.mpNumber, 37)
        XCTAssertEqual(MPWorkbook.station(project: nil, fileName: "MP 189 สถานีผลิตน้ำทุ่งน้อย กปภ.สาขาเมืองพล 92.34 kWp.xlsx"),
                       .init(name: "สถานีผลิตน้ำทุ่งน้อย", kWp: 92.34, mpNumber: 189))
    }

    func testKeysDropTheCommonWords() {
        XCTAssertEqual(MPWorkbook.stationKey("สถานีผลิตน้ำประปาบางไทร"), "บางไทร")
        XCTAssertEqual(MPWorkbook.stationKey("สถานีผลิตน้ำ บางไทร กปภ.สาขาพระนครศรีอยุธยา"), "บางไทร")
        XCTAssertEqual(MPWorkbook.stationKey("สถานีจ่ายน้ำทุ่งน้อย (กปภ.เมืองพล)"), "ทุ่งน้อย")
    }

    func testPicksTheStation() {
        let f = MPWorkbook.station(project: project, fileName: file)
        let stations: [MPWorkbook.Candidate] = [
            .init(id: "a", name: "สถานีผลิตน้ำทุ่งน้อย กปภ.สาขาเมืองพล", mpNumber: 189, kWp: 92.34),
            .init(id: "b", name: "สถานีผลิตน้ำ บางไทร กปภ.สาขาพระนครศรีอยุธยา", mpNumber: nil, kWp: 414.96),
            .init(id: "c", name: "สถานีผลิตน้ำบางปะอิน", mpNumber: 37, kWp: 120),
        ]
        let m = MPWorkbook.match(f, among: stations)
        XCTAssertEqual(m.pick, "b")
        XCTAssertEqual(m.ranked.first, "b")
    }

    func testTwoAsCloseAreLeftToTheTeam() {
        let f = MPWorkbook.station(project: project, fileName: "plan.xlsx")
        let stations: [MPWorkbook.Candidate] = [
            .init(id: "a", name: "สถานีผลิตน้ำบางไทร 1", mpNumber: nil, kWp: nil),
            .init(id: "b", name: "สถานีผลิตน้ำบางไทร 2", mpNumber: nil, kWp: nil),
        ]
        let m = MPWorkbook.match(f, among: stations)
        XCTAssertNil(m.pick)
        XCTAssertEqual(Set(m.ranked), ["a", "b"])
        XCTAssertNil(MPWorkbook.match(f, among: [.init(id: "x", name: "คุณสมศักดิ์ ใจดี", mpNumber: nil, kWp: 5)]).pick)
    }
}
