import XCTest
@testable import TCRoofCore

final class TravelClaimTests: XCTestCase {
    let cal = TravelClaim.calendar
    func at(_ h: Int, _ m: Int = 0, day: Int = 15) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    // MARK: stamps

    func testArriveThenDepart() {
        var stops: [TravelClaim.Stop] = []
        let loc = TravelClaim.Location(lat: 13.7, lon: 100.5, accuracy: 8)
        guard case .stamped = TravelClaim.stamp(.arrive, jobID: "A", label: "TC-1", at: at(9), location: loc, stops: &stops) else { return XCTFail() }
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops[0].lat, 13.7)
        XCTAssertTrue(stops[0].isOpen)
        guard case .stamped = TravelClaim.stamp(.depart, jobID: "A", label: "TC-1", at: at(10, 30), location: nil, stops: &stops) else { return XCTFail() }
        XCTAssertEqual(stops[0].onSite, 90 * 60)
    }

    func testSecondTapWithinTwoMinutesUndoes() {
        var stops: [TravelClaim.Stop] = []
        _ = TravelClaim.stamp(.arrive, jobID: "A", label: "", at: at(9), location: nil, stops: &stops)
        guard case .undone = TravelClaim.stamp(.arrive, jobID: "A", label: "", at: at(9, 1), location: nil, stops: &stops) else { return XCTFail() }
        XCTAssertTrue(stops.isEmpty)

        // ออก right after ถึง (the same button, turned) takes the arrival back
        _ = TravelClaim.stamp(.arrive, jobID: "A", label: "", at: at(9), location: nil, stops: &stops)
        guard case .undone = TravelClaim.stamp(.depart, jobID: "A", label: "", at: at(9, 1), location: nil, stops: &stops) else { return XCTFail() }
        XCTAssertTrue(stops.isEmpty)

        _ = TravelClaim.stamp(.arrive, jobID: "A", label: "", at: at(9), location: nil, stops: &stops)
        _ = TravelClaim.stamp(.depart, jobID: "A", label: "", at: at(10), location: nil, stops: &stops)
        guard case .undone = TravelClaim.stamp(.depart, jobID: "A", label: "", at: at(10, 1), location: nil, stops: &stops) else { return XCTFail() }
        XCTAssertNil(stops[0].departedAt)
    }

    func testLaterTapKeepsFirstArrivalAndArrivingElsewhereClosesTheOpenStop() {
        var stops: [TravelClaim.Stop] = []
        _ = TravelClaim.stamp(.arrive, jobID: "A", label: "", at: at(9), location: nil, stops: &stops)
        _ = TravelClaim.stamp(.arrive, jobID: "A", label: "", at: at(9, 30), location: nil, stops: &stops)
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops[0].arrivedAt, at(9))
        _ = TravelClaim.stamp(.arrive, jobID: "B", label: "", at: at(11), location: nil, stops: &stops)
        XCTAssertEqual(stops.count, 2)
        XCTAssertEqual(stops[0].departedAt, at(11))
        XCTAssertEqual(TravelClaim.stamp(.depart, jobID: "C", label: "", at: at(12), location: nil, stops: &stops), .nothingToClose)
    }

    func testJobAtReceiptTime() {
        let stops = [TravelClaim.Stop(jobID: "A", label: "", arrivedAt: at(9), departedAt: at(10)),
                     TravelClaim.Stop(jobID: "B", label: "", arrivedAt: at(11))]
        XCTAssertEqual(TravelClaim.jobAt(at(9, 30), stops: stops), "A")
        XCTAssertNil(TravelClaim.jobAt(at(10, 30), stops: stops))
        XCTAssertEqual(TravelClaim.jobAt(at(13), stops: stops), "B")
    }

    // MARK: distance and money

    func testRouteMileageAndOdometer() {
        XCTAssertEqual(TravelClaim.routeKm(legs: [12.34, 20.0], back: 30.04), 62.4)
        XCTAssertNil(TravelClaim.routeKm(legs: [12, nil], back: 3))
        XCTAssertEqual(TravelClaim.mileage(km: 62.4, rate: 5), 31_200)
        XCTAssertFalse(TravelClaim.odometerDiffers(start: 1000, end: 1065, routeKm: 62.4))
        XCTAssertTrue(TravelClaim.odometerDiffers(start: 1000, end: 1100, routeKm: 62.4))
    }

    func testFuelSplitAddsUpToTheReceipt() {
        let parts = TravelClaim.split(100_001, by: [("A", 10), ("B", 20), ("C", 30)])
        XCTAssertEqual(parts.map(\.amount).reduce(0, +), 100_001)
        XCTAssertEqual(parts[0].amount, 16_667)
        XCTAssertEqual(parts[1].amount, 33_334)
        XCTAssertEqual(parts[2].amount, 50_000)
        let even = TravelClaim.split(1000, by: [("A", 0), ("B", 0), ("C", 0)])
        XCTAssertEqual(even.map(\.amount), [333, 333, 334])
    }

    func testBaht() {
        XCTAssertEqual(TravelClaim.baht(123_450), "1,234.50")
        XCTAssertEqual(TravelClaim.baht(5), "0.05")
    }

    // MARK: month

    func day(_ id: String, vehicle: TravelClaim.Vehicle = .personal, legs: [(String?, Double?)], back: Double? = 10) -> TravelClaim.Day {
        TravelClaim.Day(id: id, date: at(8), vehicle: vehicle,
                        stops: legs.map { TravelClaim.Stop(jobID: $0.0, label: $0.0 ?? "", legKm: $0.1) }, backKm: back, rate: 5)
    }

    func testSummaryTotalsByCategoryAndJob() {
        let days = [day("d1", legs: [("A", 20), ("B", 10)], back: 30)]   // 60 km × 5 = 300 baht
        let items = [
            TravelClaim.Item(id: "1", date: at(9), category: .fuel, amount: 120_000, vendor: "PTT", jobID: nil),
            TravelClaim.Item(id: "2", date: at(10), category: .toll, amount: 5_000, vendor: "ทางพิเศษ", jobID: "A"),
        ]
        let s = TravelClaim.Summary(days: days, items: items)
        XCTAssertEqual(s.mileage, 30_000)
        XCTAssertEqual(s.total, 155_000)
        XCTAssertEqual(s.byCategory.map(\.category), [.fuel, .toll, .mileage])
        // A takes its 20 km leg, B its 10 km plus the 30 km back
        let byJob = Dictionary(uniqueKeysWithValues: s.byJob.map { ($0.jobID ?? "-", $0.amount) })
        XCTAssertEqual(byJob["A"], 10_000 + 5_000)
        XCTAssertEqual(byJob["B"], 20_000)
        XCTAssertEqual(byJob["-"], 120_000)
        XCTAssertEqual(byJob.values.reduce(0, +), s.total)
        XCTAssertTrue(s.warnings.isEmpty)
    }

    func testWarnings() {
        let days = [day("d1", legs: [("A", nil)]),
                    TravelClaim.Day(id: "d2", date: at(8, day: 16), vehicle: .personal, stops: [TravelClaim.Stop(jobID: "A", label: "", legKm: 40)],
                                    backKm: 40, odoStart: 1000, odoEnd: 1200)]
        let items = [
            TravelClaim.Item(id: "1", date: at(9), category: .parking, amount: 0),
            TravelClaim.Item(id: "2", date: at(9), category: .fuel, amount: 50_000, vendor: "PTT Station"),
            TravelClaim.Item(id: "3", date: at(17), category: .fuel, amount: 50_000, vendor: "ptt station"),
        ]
        let w = TravelClaim.Summary(days: days, items: items).warnings
        XCTAssertTrue(w.contains(.noAmount(itemID: "1")))
        XCTAssertTrue(w.contains(.duplicate(itemID: "2")))
        XCTAssertTrue(w.contains(.duplicate(itemID: "3")))
        XCTAssertTrue(w.contains(.noDistance(dayID: "d1")))
        XCTAssertTrue(w.contains(.odometerReason(dayID: "d2")))
        // a company car claims no mileage, so no distance is needed
        XCTAssertTrue(TravelClaim.Summary(days: [day("c", vehicle: .company, legs: [("A", nil)])], items: []).warnings.isEmpty)
    }

    func testJobCostAndMonthKey() {
        let days = [day("d1", legs: [("A", 20)], back: 20)]
        let items = [TravelClaim.Item(id: "1", date: at(9), category: .toll, amount: 4_500, jobID: "A")]
        let cost = TravelClaim.jobCost("A", days: days, items: items)
        XCTAssertEqual(cost.amount, 20_000 + 4_500)
        XCTAssertEqual(cost.visits, 1)
        XCTAssertEqual(TravelClaim.monthKey(at(9)), "2026-10")
        XCTAssertEqual(TravelClaim.monthStart("2026-10").map(TravelClaim.monthKey), "2026-10")
    }

    // MARK: receipts

    let parser = ReceiptParser()

    func testFuelReceipt() {
        let text = """
        บริษัท ปตท. น้ำมันและการค้าปลีก จำกัด (มหาชน)
        สถานีบริการ PTT สาขาโคราช
        เลขประจำตัวผู้เสียภาษี 0107561000013
        ใบเสร็จรับเงิน/ใบกำกับภาษีอย่างย่อ
        15/10/2569 09:42
        ดีเซล B7  32.50 ลิตร
        ราคา/ลิตร 31.94
        รวมเงิน 1,038.05
        ภาษีมูลค่าเพิ่ม 7% 67.91
        เงินสด 1,100.00
        เงินทอน 61.95
        """
        let p = parser.parse(text)
        XCTAssertEqual(p.amount, 103_805)
        XCTAssertEqual(p.taxID, "0107561000013")
        XCTAssertEqual(p.category, .fuel)
        XCTAssertEqual(p.date.map(TravelClaim.monthKey), "2026-10")
        XCTAssertEqual(p.date.map { cal.component(.day, from: $0) }, 15)
        XCTAssertEqual(p.vendor, "บริษัท ปตท. น้ำมันและการค้าปลีก จำกัด (มหาชน)")
    }

    func testTollReceiptAmountUnderItsLabel() {
        let text = """
        การทางพิเศษแห่งประเทศไทย
        ด่านเก็บเงินบางนา
        วันที่ 03-09-26
        จำนวนเงิน
        50.00 บาท
        """
        let p = parser.parse(text)
        XCTAssertEqual(p.amount, 5_000)
        XCTAssertEqual(p.category, .toll)
        XCTAssertEqual(p.date.map { cal.dateComponents([.year, .month, .day], from: $0) }, DateComponents(year: 2026, month: 9, day: 3))
    }

    func testHotelReceiptThaiMonthAndGrandTotal() {
        let text = """
        โรงแรมสบายดี
        TAX ID: 0-1055-12345-67-8
        วันที่ 2 ต.ค. 69
        ค่าห้องพัก 1 คืน 850.00
        Grand Total 850.00
        """
        let p = parser.parse(text)
        XCTAssertEqual(p.amount, 85_000)
        XCTAssertEqual(p.taxID, "0105512345678")
        XCTAssertEqual(p.category, .lodging)
        XCTAssertEqual(p.date.map { cal.dateComponents([.year, .month, .day], from: $0) }, DateComponents(year: 2026, month: 10, day: 2))
    }

    func testParkingWithoutLabelTakesTheLargestMoney() {
        let p = parser.parse("ลานจอดรถ เซ็นทรัล\nเข้า 09:10 ออก 11:25\nค่าจอด 40.00\nรหัส 88213")
        XCTAssertEqual(p.amount, 4_000)
        XCTAssertEqual(p.category, .parking)
        XCTAssertNil(p.taxID)
        XCTAssertTrue(parser.parse("").isEmpty)
    }

    func testOdometer() {
        XCTAssertEqual(ReceiptParser.odometer("ODO 128,540 km\nTRIP 42.3"), 128_540)
        XCTAssertNil(ReceiptParser.odometer("12:30"))
    }
}
