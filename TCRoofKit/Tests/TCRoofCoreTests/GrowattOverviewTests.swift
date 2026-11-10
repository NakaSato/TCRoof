import XCTest
@testable import TCRoofCore

/// `GrowattAPI.summary`: a Growatt plant as a row of the `บำรุงรักษา` overview.
final class GrowattOverviewTests: XCTestCase {
    private let list = Data("""
    {"error_msg":"","data":{"plants":[{"total_energy":"0","plant_id":1913,"country":"China","latitude_f":null,"city":"",
    "image_url":null,"latitude":"32.5671257","current_power":"-1.0","locale":"en-US","peak_power":20000,"user_id":1704,
    "name":"Vi Station","create_date":"2026-09-09","status":4,"longitude":"-114.9943669"},
    {"total_energy":"12.5","plant_id":1917,"country":"Canada","city":"Calgary","latitude":"61.0666922","current_power":"3.2",
    "peak_power":0.800000011920929,"name":"Test","status":1,"longitude":"-107.991707"}],"count":2},"error_code":0}
    """.utf8)

    private let overview = Data("""
    {"error_msg":"","data":{"total_energy":"0","last_update_time":"2026-09-09 15:41:34","carbon_offset":"0","efficiency":"",
    "monthly_energy":"0","peak_power_actual":20000,"timezone":"GMT+8","current_power":0,"yearly_energy":"0","today_energy":"4.5"},
    "error_code":0}
    """.utf8)

    func testSummary() throws {
        let plants = try GrowattAPI.parsePlants(list)
        let never = GrowattAPI.summary(plants[0])
        XCTAssertEqual(never.id, "growatt-1913")
        XCTAssertEqual(never.status, .offline)
        XCTAssertEqual(never.kWp, 20000)
        XCTAssertFalse(never.reportsPR)
        // plant/data gives a plant that never reported power 0: it stays offline
        let stillNever = GrowattAPI.summary(plants[0], data: try GrowattAPI.parseData(overview))
        XCTAssertEqual(stillNever.status, .offline)
        XCTAssertEqual(stillNever.note, "Growatt | ไม่มีข้อมูล ตั้งแต่ 2026-09-09 15:41")

        let live = GrowattAPI.summary(plants[1], data: try GrowattAPI.parseData(overview))
        XCTAssertEqual(live.status, .normal)
        XCTAssertEqual(live.energy, 4.5)
        XCTAssertEqual(live.note, "Growatt | 0 kW")
    }
}
