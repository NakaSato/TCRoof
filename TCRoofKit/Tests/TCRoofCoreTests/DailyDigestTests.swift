import XCTest
@testable import TCRoofCore

/// `สรุปโดย AI` on the feed's daily summary: the day's facts the model words, and the request sent.
final class DailyDigestTests: XCTestCase {
    private let cal = FeedBuilder.calendar

    private func d(_ day: Int, _ hour: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func daily(_ day: Int, _ percent: Double, crew: Int = 0, rain: Int = 0, stop: String = "",
                       problems: [RoutineReport.Problem] = []) -> RoutineReport.Daily {
        var r = RoutineReport.Daily(date: d(day))
        r.progress = [.init(task: .panels, description: "", location: "หลังคา 1", percent: percent)]
        if crew > 0 { r.crew = [.init(name: "ช่าง", count: crew)] }
        for h in 0..<rain { r.weather[h] = .rain }
        r.stopReason = stop
        r.problems = problems
        return r
    }

    /// A PWA station installing 5–16 ต.ค., every day a working day.
    private func station(_ id: String, mp: Int, reports: [FeedBuilder.Report]) -> FeedBuilder.Station {
        var s = FeedBuilder.Station(id: id, code: "TC-" + id, name: "สถานี \(id)", project: .pwa, team: "TCR01", mpNumber: mp,
                                    installStart: d(5), installDays: 12)
        s.settings.workingWeekdays = [1, 2, 3, 4, 5, 6, 7]
        s.reports = reports
        return s
    }

    func testFactsCarryEachStationsDay() throws {
        let problem = RoutineReport.Problem(description: "รางเคเบิลยังไม่มา", since: d(12))
        let sent = station("a", mp: 189, reports: [
            .init(daily(11, 30), signedAt: d(11, 17)),
            .init(daily(12, 38, crew: 6, rain: 2, stop: "ฝนตกบ่าย", problems: [problem]), signedAt: d(12, 17)),
        ])
        let missing = station("b", mp: 190, reports: [.init(daily(11, 20), signedAt: d(11, 17))])
        let f = try XCTUnwrap(Assistant.DailyDigest.facts([sent, missing], day: d(12), now: d(12, 19)))

        XCTAssertEqual(f.day, "2026-10-12")
        XCTAssertEqual(f.reportsSent, 1)
        XCTAssertEqual(f.reportsDue, 2)
        XCTAssertEqual(f.openIssues, 1)
        XCTAssertEqual(f.issues.count, 1)
        XCTAssertTrue(f.issues[0].contains("รางเคเบิลยังไม่มา"))

        let a = try XCTUnwrap(f.stations.first { $0.station.hasPrefix("MP 189") })
        XCTAssertTrue(a.reportSent)
        XCTAssertEqual(a.crew, 6)
        XCTAssertEqual(a.rainHours, 2)
        XCTAssertEqual(a.stopReason, "ฝนตกบ่าย")
        XCTAssertEqual(a.newProblems, ["รางเคเบิลยังไม่มา"])
        XCTAssertEqual(a.work.count, 1)
        XCTAssertTrue(a.work[0].hasSuffix("38%"))

        let b = try XCTUnwrap(f.stations.first { $0.station.hasPrefix("MP 190") })
        XCTAssertFalse(b.reportSent)
        XCTAssertNil(b.crew)
        XCTAssertTrue(b.work.isEmpty)
    }

    func testNoFactsOnADayWithoutASummary() {
        // installing from 5 ต.ค.: nothing is due on the 1st and nothing is open
        let s = station("a", mp: 189, reports: [])
        XCTAssertNil(Assistant.DailyDigest.facts([s], day: d(1), now: d(1, 19)))
    }

    func testTheRequestHasNoToolsAndCountsAsAQuestion() throws {
        let s = station("a", mp: 189, reports: [.init(daily(12, 38), signedAt: d(12, 17))])
        let f = try XCTUnwrap(Assistant.DailyDigest.facts([s], day: d(12), now: d(12, 19)))
        let r = Assistant.DailyDigest.request(f)
        XCTAssertTrue(r.tools.isEmpty)
        XCTAssertTrue(r.isNewQuestion)
        XCTAssertEqual(r.messages.map(\.role), [.system, .user])
        XCTAssertTrue(r.messages[0].content!.contains("Thai"))
        XCTAssertEqual(r.messages[1].content, Assistant.DailyDigest.json(f))
        // the same day's facts give the same JSON, so an unchanged day isn't asked again
        XCTAssertEqual(Assistant.DailyDigest.json(f), Assistant.DailyDigest.json(try XCTUnwrap(Assistant.DailyDigest.facts([s], day: d(12), now: d(12, 20)))))
        let body = try Assistant.OpenAI.body(r, model: "m")
        let sent = try XCTUnwrap(JSONValue.parse(String(decoding: body, as: UTF8.self)))
        XCTAssertNil(sent["tools"])
        XCTAssertNil(sent["tool_choice"])
    }
}
