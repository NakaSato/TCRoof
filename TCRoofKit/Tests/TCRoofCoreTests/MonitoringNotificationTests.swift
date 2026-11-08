import XCTest
@testable import TCRoofCore

final class MonitoringNotificationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func station(_ id: String, read minutesAgo: Double, alarms: [Monitoring.Alarm] = []) -> Monitoring.Station {
        var s = Monitoring.Station(id: id, mpNumber: 25, name: "นครชัยศรี", kWp: 220, inverters: 2)
        s.lastReading = now.addingTimeInterval(-minutesAgo * 60)
        s.alarms = alarms
        return s
    }

    func testAnnouncesOnlyAChangeIntoAlarmOrOffline() {
        let fault = Monitoring.Alarm(id: "e", source: .growatt, code: "124", part: "INV 2", detail: "No AC Connection", since: now)
        let alarm = station("a", read: 1, alarms: [fault]), quiet = station("b", read: 90), fine = station("c", read: 1)
        let plans = MonitoringNotification.plans(previous: ["a": .normal, "b": .normal, "c": .normal],
                                                 stations: [alarm, quiet, fine], now: now, offlineAfter: 30)
        XCTAssertEqual(plans.map(\.title), ["สถานีมีปัญหา", "สถานีออฟไลน์"])
        XCTAssertEqual(plans[0].body, "MP 25 นครชัยศรี")
        XCTAssertEqual(plans[0].sub, "INV 2 | Error 124 | No AC Connection")
        XCTAssertEqual(plans[1].sub, "ไม่ได้รับข้อมูลเกิน 30 นาที")
        XCTAssertEqual(plans[0].type, .monitor)
        XCTAssertEqual(DeepLink.route(type: .monitor, action: nil, info: plans[0].info), .monitor)
    }

    func testStaysQuietWithoutAChange() {
        let quiet = station("b", read: 90)
        // already offline, first reading since launch, unpaired
        XCTAssertTrue(MonitoringNotification.plans(previous: ["b": .offline], stations: [quiet], now: now, offlineAfter: 30).isEmpty)
        XCTAssertTrue(MonitoringNotification.plans(previous: [:], stations: [quiet], now: now, offlineAfter: 30).isEmpty)
        let unpaired = Monitoring.Station.unpaired(id: "u", mpNumber: 1, name: "U", kWp: 50, inverters: 1)
        XCTAssertTrue(MonitoringNotification.plans(previous: ["u": .normal], stations: [unpaired], now: now, offlineAfter: 30).isEmpty)
    }

    func testOwnGroup() {
        XCTAssertEqual(NotificationGroup.monitor.types, [.monitor])
        XCTAssertEqual(NotificationType.monitor.level, .active)
    }
}
