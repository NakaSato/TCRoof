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

    // MARK: the iPad ledger (docs/ui/tools-log-ipad)

    func ev(_ a: ToolLog.Action, _ item: String, _ name: String, _ who: String, _ job: String, _ at: Date, due: Date? = nil, odo: Int? = nil,
            litres: Double? = nil, baht: Double? = nil, note: String = "") -> E {
        E(id: item + "-\(Int(at.timeIntervalSince1970))", action: a, item: item, itemName: name, person: who, personEmail: "", job: job, at: at,
          due: due, odometer: odo, litres: litres, baht: baht, note: note)
    }

    func sep(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))! }

    /// The board's log around Wed 30 Sep: a trip of the Commuter, a fuel stop and tools borrowed and given back.
    var ledger: [E] {
        [ev(.borrow, "t376", "Fluke 376 FC แคลมป์มิเตอร์", "วิชัย", "NO.098", sep(26, 8, 15), due: sep(29, 17)),
         ev(.carOut, "v2", "Toyota Commuter · 2กค 5678", "ธนพล", "NO.212", sep(29, 7, 15), odo: 120_243),
         ev(.giveBack, "hioki", "Hioki CM4375 แคลมป์มิเตอร์", "วิชัย", "NO.215", sep(29, 16, 5), note: "สภาพปกติ"),
         ev(.fuel, "v2", "Toyota Commuter · 2กค 5678", "ธนพล", "", sep(29, 17, 30), litres: 45.2, baht: 1_450),
         ev(.carIn, "v2", "Toyota Commuter · 2กค 5678", "ธนพล", "NO.212", sep(29, 18, 10), odo: 120_455),
         ev(.carOut, "v1", "Isuzu D-Max · 1กข 1234", "สมชาย", "NO.224", sep(30, 7, 40), odo: 85_034),
         ev(.borrow, "drone", "DJI Mavic 3 Thermal", "สมชาย", "NO.224", sep(30, 9, 2)),
         ev(.remind, "t376", "Fluke 376 FC แคลมป์มิเตอร์", "ธนพล", "NO.098", sep(30, 9, 30), note: "ทวงคืนจาก วิชัย"),
         ev(.giveBack, "f1587", "Fluke 1587 FC เครื่องวัดฉนวน", "ธนพล", "NO.212", sep(30, 10, 24), note: "สภาพปกติ"),
         ev(.carIn, "v3", "Toyota Revo · 3กง 9012", "ธนพล", "NO.226", sep(1, 18), odo: 42_980)]
    }

    var noon30: Date { sep(30, 12) }

    /// A return's km come from its own trip out; nothing for a trip with no way out or for another action.
    func testDriven() {
        let log = ledger
        let commuterIn = log.first { $0.item == "v2" && $0.action == .carIn }!
        XCTAssertEqual(ToolLog.driven(commuterIn, in: log), 212)
        XCTAssertEqual(ToolLog.driven(commuterIn, in: log.filter { $0.action != .fuel }), 212, "a fuel stop on the way doesn't break the trip")
        XCTAssertNil(ToolLog.driven(log.first { $0.item == "v3" }!, in: log), "no trip out recorded")
        XCTAssertNil(ToolLog.driven(log.first { $0.action == .carOut }!, in: log))
        XCTAssertEqual(ToolLog.driven(in: log), [commuterIn.id: 212])
        // the event itself need not be in the log it is paired against
        XCTAssertEqual(ToolLog.driven(commuterIn, in: log.filter { $0.id != commuterIn.id }), 212)
        // a second trip pairs with its own way out
        let out = ev(.carOut, "v2", "Toyota Commuter · 2กค 5678", "ธนพล", "", noon30, odo: 120_455)
        let back = ev(.carIn, "v2", "Toyota Commuter · 2กค 5678", "ธนพล", "", noon30.addingTimeInterval(3_600), odo: 120_500)
        XCTAssertEqual(ToolLog.driven(back, in: log + [out, back]), 45)
        XCTAssertEqual(ToolLog.monthKm(log + [out, back], now: noon30), 257, "monthKm still pairs the same way")
    }

    /// Kind, range, action, person, job and search combine; newest first; `ทวงคืน` only under every action.
    func testFilter() {
        let log = ledger, now = noon30
        XCTAssertEqual(ToolLog.filter(log, now: now).count, 10)
        XCTAssertEqual(ToolLog.filter(log, now: now).first?.item, "f1587", "newest first")
        XCTAssertEqual(ToolLog.filter(log, kind: .car, now: now).count, 5)
        XCTAssertEqual(ToolLog.filter(log, kind: .tool, now: now).count, 5, "a reminder is a tool's")
        XCTAssertEqual(ToolLog.filter(log, range: .today, now: now).count, 4)
        XCTAssertEqual(ToolLog.filter(log, range: .week, now: now).count, 9, "26 Sep is within 7 days of the 30th, 1 Sep is not")
        XCTAssertEqual(ToolLog.filter(log, range: .month, now: now).count, 10)
        XCTAssertEqual(ToolLog.filter(log, action: .giveBack, now: now).map(\.item), ["f1587", "hioki"])
        for a in ToolLog.Action.allCases where a != .remind {
            XCTAssertFalse(ToolLog.filter(log, action: a, now: now).contains { $0.action == .remind }, "\(a)")
        }
        XCTAssertTrue(ToolLog.filter(log, range: .today, action: .fuel, now: now).isEmpty, "the board's state 06")
        XCTAssertEqual(ToolLog.filter(log, person: "สมชาย", now: now).count, 2)
        XCTAssertEqual(ToolLog.filter(log, job: "NO.212", now: now).count, 3)
        XCTAssertEqual(ToolLog.filter(log, person: "วิชัย", job: "NO.215", now: now).count, 1)
        XCTAssertEqual(ToolLog.filter(log, query: "2กค 5678", now: now).count, 3, "a plate finds its vehicle's events")
        XCTAssertEqual(ToolLog.filter(log, query: "  fluke ", now: now).count, 3, "ignores case and spaces around")
        XCTAssertEqual(ToolLog.filter(log, query: "no.224", now: now).count, 2, "the job")
        XCTAssertEqual(ToolLog.filter(log, query: "ธนพล", now: now).count, 6, "the person")
        XCTAssertEqual(ToolLog.filter(log, kind: .car, range: .all, query: "2กค 5678", now: now).count, 3, "`ประวัติ` of a vehicle")
    }

    static let csvHeader = "\u{FEFF}\"วันที่\",\"เวลา\",\"ประเภท\",\"รายการ\",\"ผู้ใช้\",\"งาน\",\"ไมล์\",\"วิ่ง (กม.)\",\"ลิตร\",\"บาท\",\"หมายเหตุ\"\r\n"

    /// One header, then a quoted row per event, with the trip's km from the whole log.
    func testCSV() {
        let log = ledger
        let rows = ToolLog.filter(log, action: .carIn, now: noon30)
        let csv = ToolLog.csv(rows, log: log)
        XCTAssertTrue(csv.hasPrefix(Self.csvHeader))
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[1], #""2026-09-29","18:10","คืนรถ","Toyota Commuter · 2กค 5678","ธนพล","NO.212","120455","212","","","""#)
        XCTAssertEqual(lines[2], #""2026-09-01","18:00","คืนรถ","Toyota Revo · 3กง 9012","ธนพล","NO.226","42980","","","","""#)
        XCTAssertFalse(ToolLog.csv(rows).contains("\"212\""), "without the log the trip out is missing")
        let fuel = ToolLog.csv(log.filter { $0.action == .fuel }).components(separatedBy: "\r\n")[1]
        XCTAssertEqual(fuel, #""2026-09-29","17:30","เติมน้ำมัน","Toyota Commuter · 2กค 5678","ธนพล","","","","45.2","1450","""#)
        // quotes inside a field are doubled; commas and line breaks stay inside the quotes
        let odd = ev(.giveBack, "x", "Clamp \"A\", 2", "ก", "", noon30, note: "line 1\nline 2")
        XCTAssertTrue(ToolLog.csv([odd]).contains(#""Clamp ""A"", 2""#))
        XCTAssertTrue(ToolLog.csv([odd]).contains("\"line 1\nline 2\""))
        XCTAssertEqual(ToolLog.csv([]), Self.csvHeader)
        XCTAssertEqual(Array(ToolLog.csv([]).utf8.prefix(3)), [0xEF, 0xBB, 0xBF], "UTF-8 BOM")
    }

    /// Days late count from the due day; a tool given back damaged stays `งดใช้ / ซ่อม` until it goes out again.
    func testLateDamagedAndService() {
        let log = ledger, borrow = log[0]
        XCTAssertEqual(ToolLog.daysLate(borrow, now: noon30), 1)
        XCTAssertEqual(ToolLog.daysLate(borrow, now: borrow.due!.addingTimeInterval(-60)), 0)
        XCTAssertEqual(ToolLog.daysLate(log[6], now: noon30), 0, "no due date")
        var broken = log
        broken.append(ev(.giveBack, "t376", "Fluke 376 FC แคลมป์มิเตอร์", "วิชัย", "NO.098", noon30, note: "ชำรุด / ต้องซ่อม · จอแตก"))
        XCTAssertEqual(ToolLog.damaged(broken).map(\.item), ["t376"])
        broken.append(ev(.borrow, "t376", "Fluke 376 FC แคลมป์มิเตอร์", "วิชัย", "NO.099", noon30.addingTimeInterval(3_600)))
        XCTAssertTrue(ToolLog.damaged(broken).isEmpty, "out again: repaired")
        let commuter = ToolLog.Vehicle(id: "v2", name: "Toyota Commuter", plate: "2กค 5678", serviceAtKm: 120_955)
        XCTAssertEqual(ToolLog.serviceLeft(commuter, in: log), 500)
        XCTAssertNil(ToolLog.serviceLeft(ToolLog.Vehicle(id: "v2", name: "x", plate: ""), in: log))
        XCTAssertNil(ToolLog.serviceLeft(commuter, in: []))
    }
}
