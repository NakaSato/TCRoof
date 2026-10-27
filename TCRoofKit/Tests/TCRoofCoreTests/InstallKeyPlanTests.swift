import XCTest
@testable import TCRoofCore

final class InstallKeyPlanTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_790_000_000)

    private func row(_ task: MasterSchedule.Task, percent: Double = 0, subs: [InstallGantt.Sub] = []) -> InstallGantt.Row {
        .init(id: task.rawValue, code: task.code, title: task.title, status: .current, start: day, end: day, percent: percent, subs: subs)
    }

    private var plan: InstallKeyPlan {
        var s = RoutineReport.Settings()
        s.keyPoints = ["หลังคา 1": [0.2, 0.3], "หลังคา 3": [0.5, 0.5]]
        let rows = [
            row(.structure, subs: [.init("หลังคา 1", percent: 100), .init("หลังคา 3", percent: 70), .init("หลังคา 5", percent: 0)]),
            row(.dcSide, subs: [.init("หลังคา 3", percent: 60), .init("ไม่ระบุตำแหน่ง", percent: 10)]),
            row(.inverter, percent: 0),
        ]
        return InstallKeyPlan(rows: rows, planned: [MasterSchedule.Task.structure.rawValue: 80, MasterSchedule.Task.dcSide.rawValue: 60], settings: s)
    }

    func testPointsPerTaskAndLocation() {
        let p = plan
        XCTAssertEqual(p.points.map(\.label), ["2.1-1", "2.1-2", "2.1-3", "2.2-1", "2.2-2", "2.5-1"])
        XCTAssertEqual(p.points.map(\.location), ["หลังคา 1", "หลังคา 3", "หลังคา 5", "หลังคา 3", nil, nil])
        XCTAssertEqual(p.placedCount, 3)
        XCTAssertEqual(p.points.count, 6)
        XCTAssertEqual(p.points[1].at?.x, 0.5)
        XCTAssertEqual(p.groups[0].average, 170.0 / 3, accuracy: 0.001)
    }

    func testStates() {
        XCTAssertEqual(plan.points.map(\.state), [.done, .late, .late, .onPlan, .late, .notStarted])
        XCTAssertEqual(InstallKeyPlan.state(actual: 0, planned: 0), .notStarted)
        XCTAssertEqual(InstallKeyPlan.state(actual: 10, planned: 0), .onPlan)
        XCTAssertEqual(InstallKeyPlan.state(actual: 60, planned: 60), .onPlan)
        XCTAssertEqual(InstallKeyPlan.state(actual: 59, planned: 60), .late)
        XCTAssertEqual(InstallKeyPlan.state(actual: 100, planned: 100), .done)
    }

    func testNextUnplacedSkipsPointsWithoutLocation() {
        let p = plan
        XCTAssertEqual(p.nextUnplaced(after: nil)?.label, "2.1-3")
        // 2.1-3 is the only placeable point left: nothing after it
        XCTAssertNil(p.nextUnplaced(after: p.points[2].id))
        XCTAssertEqual(p.sharing(p.points[1]).map(\.label), ["2.2-1"])
    }

    func testFanOut() {
        let o = plan.fanOffsets(spacing: 26)
        XCTAssertEqual(o[plan.points[0].id]?.dx, 0)
        let a = o[plan.points[1].id]!, b = o[plan.points[3].id]!
        XCTAssertEqual(hypot(a.dx - b.dx, a.dy - b.dy), 26, accuracy: 0.001)
        for n in 3...6 {
            let p0 = InstallKeyPlan.fan(index: 0, count: n, spacing: 26), p1 = InstallKeyPlan.fan(index: 1, count: n, spacing: 26)
            XCTAssertEqual(hypot(p0.dx - p1.dx, p0.dy - p1.dy), 26, accuracy: 0.001)
        }
    }
}
