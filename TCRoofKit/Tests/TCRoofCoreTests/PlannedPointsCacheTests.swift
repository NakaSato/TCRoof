import XCTest
@testable import TCRoofCore

final class PlannedPointsCacheTests: XCTestCase {
    func testPlanEditsAndCalendarChangesDoNotReuseOldWeights() {
        let cache = PlannedPointsCache()
        var calendar = MasterSchedule.calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        let original = [MasterSchedule.PlannedTask(task: .structure, weight: 10, start: start, end: start)]
        let edited = [MasterSchedule.PlannedTask(task: .structure, weight: 20, start: start, end: start)]
        var builds = 0
        func points(_ plan: [MasterSchedule.PlannedTask], _ cal: Calendar) -> [MasterSchedule.Task: [Date: Double]] {
            cache.points(for: plan, calendar: cal) {
                builds += 1
                return MasterSchedule.plannedPoints(plan, calendar: cal)
            }
        }
        let first = points(original, calendar)
        XCTAssertEqual(points(original, calendar), first)
        XCTAssertEqual(builds, 1, "an unchanged plan reuses the weekly expansion")
        XCTAssertEqual(points(edited, calendar)[.structure]?.values.reduce(0, +), 20)
        calendar.firstWeekday = 2
        let monday = points(original, calendar)
        XCTAssertNotEqual(monday[.structure]?.keys.first, first[.structure]?.keys.first)
        XCTAssertEqual(builds, 3)
        XCTAssertEqual(points(original, MasterSchedule.calendar), first)
        XCTAssertEqual(builds, 3, "alternating stations and calendars retain their own results")
    }

    func testConcurrentReadersKeepIndependentPlans() async {
        let cache = PlannedPointsCache()
        let calendar = MasterSchedule.calendar
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let values = await withTaskGroup(of: Double.self) { group in
            for weight in 1...100 {
                group.addTask {
                    let plan = [MasterSchedule.PlannedTask(task: .structure, weight: Double(weight), start: day, end: day)]
                    let points = cache.points(for: plan, calendar: calendar) {
                        MasterSchedule.plannedPoints(plan, calendar: calendar)
                    }
                    return points[.structure]?.values.reduce(0, +) ?? 0
                }
            }
            var values: [Double] = []
            for await value in group { values.append(value) }
            return values.sorted()
        }
        XCTAssertEqual(values, (1...100).map(Double.init))
    }
}
