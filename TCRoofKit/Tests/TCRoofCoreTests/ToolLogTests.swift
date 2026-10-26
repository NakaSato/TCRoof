import XCTest
@testable import TCRoofCore

final class ToolLogTests: XCTestCase {
    typealias E = ToolLog.Event
    let cal = MasterSchedule.calendar

    func day(_ d: Int, _ h: Int = 9, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    func ev(_ a: ToolLog.Action, _ item: String, _ at: Date, due: Date? = nil, odo: Int? = nil, fuel: Double? = nil, baht: Double? = nil) -> E {
        E(action: a, item: item, itemName: item, person: "สมชาย", personEmail: "a@x", at: at, due: due, odometer: odo, fuelLevel: fuel, baht: baht)
    }

    /// A borrowed tool is out until it comes back; a late one comes first.
    func testWhatIsOut() {
        let log = [ev(.borrow, "fluke", day(20), due: day(23)), ev(.borrow, "drone", day(26, 9)), ev(.giveBack, "drone", day(26, 11)),
                   ev(.borrow, "hioki", day(26, 8)), ev(.carOut, "dmax", day(26, 7, 40), odo: 85_034), ev(.fuel, "dmax", day(26, 8), baht: 500)]
        let outs = ToolLog.outs(log, now: day(26, 12))
        XCTAssertEqual(outs.map(\.id), ["fluke", "dmax", "hioki"])
        XCTAssertTrue(outs[0].late)
        XCTAssertFalse(outs[1].late)
        XCTAssertEqual(outs[1].kind, .car)
        XCTAssertNil(ToolLog.out("drone", in: log))
        XCTAssertEqual(ToolLog.out("hioki", in: log)?.action, .borrow)
    }

    func testDuration() {
        XCTAssertEqual(ToolLog.duration(from: day(22), to: day(26)), "4 วัน")
        XCTAssertEqual(ToolLog.duration(from: day(26, 9, 2), to: day(26, 11, 20)), "2 ชม. 18 น.")
        XCTAssertEqual(ToolLog.duration(from: day(26, 9), to: day(26, 9, 25)), "25 น.")
        XCTAssertEqual(ToolLog.duration(from: day(26, 9), to: day(26, 11)), "2 ชม.")
    }

    /// The last 7 days by day, newest first; older ones left out.
    func testDays() {
        let log = [ev(.borrow, "a", day(26, 9)), ev(.giveBack, "a", day(26, 10)), ev(.borrow, "b", day(24)), ev(.borrow, "c", day(10))]
        let days = ToolLog.days(log, now: day(26, 12))
        XCTAssertEqual(days.map(\.day), [day(26, 0), day(24, 0)])
        XCTAssertEqual(days[0].events.map(\.action), [.giveBack, .borrow])
    }

    /// Km of the month from each return's odometer less its trip out; fuel in baht.
    func testMonthFigures() {
        let log = [ev(.carOut, "v", day(28, 7, 0).addingTimeInterval(-40 * 86_400), odo: 100),   // September's trip
                   ev(.carIn, "v", day(28, 18).addingTimeInterval(-40 * 86_400), odo: 150),
                   ev(.carOut, "v", day(20, 7), odo: 1_000), ev(.carIn, "v", day(20, 18), odo: 1_212),
                   ev(.carOut, "w", day(21, 7), odo: 50), ev(.carIn, "w", day(22, 18), odo: 80),
                   ev(.fuel, "v", day(20, 17), baht: 1_450), ev(.fuel, "w", day(21, 17), baht: 1_680)]
        XCTAssertEqual(ToolLog.monthKm(log, now: day(26)), 242)
        XCTAssertEqual(ToolLog.monthFuel(log, now: day(26)), 3_130)
        let last = ToolLog.lastReading("v", in: log + [ev(.carIn, "v", day(25), odo: 1_300, fuel: 0.4)])
        XCTAssertEqual(last.odometer, 1_300)
        XCTAssertEqual(last.fuel, 0.4)
    }

    /// An older or newer event still decodes.
    func testDecodesWithDefaults() throws {
        let e = try JSONDecoder().decode(E.self, from: Data(#"{"action":"someday","item":"x"}"#.utf8))
        XCTAssertEqual(e.action, .remind)
        XCTAssertEqual(e.item, "x")
        XCTAssertEqual(e.note, "")
        let v = try JSONDecoder().decode(ToolLog.Vehicle.self, from: Data(#"{"name":"Isuzu D-Max","plate":"1กข 1234"}"#.utf8))
        XCTAssertEqual(v.title, "Isuzu D-Max · 1กข 1234")
        XCTAssertNil(v.serviceAtKm)
    }
}
