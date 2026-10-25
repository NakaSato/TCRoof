import Foundation

/// The weekly request's days (docs/ui/install-tracking-ipad-weekly-request): the working days Monday–Saturday, which
/// lines are on which day, who is off, and the sums the iPad tab shows.
public extension RoutineReport.WeeklyRequest {
    /// Day 0 is the Monday after `weekStart` (a Sunday, as the MP plan's weeks), day 5 the Saturday.
    func date(ofDay d: Int) -> Date { RoutineReport.add(weekStart, d + 1) }

    /// The days 0…5 that are working weekdays in the job's settings.
    static func workingDays(_ settings: RoutineReport.Settings) -> [Int] {
        (0...5).filter { settings.workingWeekdays.contains($0 + 2) }
    }

    /// The working days of this week between two dates, both included.
    func days(from start: Date, to end: Date, settings: RoutineReport.Settings) -> [Int] {
        let s = RoutineReport.day(start), e = RoutineReport.day(end)
        return Self.workingDays(settings).filter { d in let x = date(ofDay: d); return x >= s && x <= e }
    }

    static func offKey(role: Int, day: Int) -> String { "\(role)-\(day)" }

    func isOff(role: Int, day: Int) -> Bool { crewOff.contains(Self.offKey(role: role, day: day)) }

    /// Switches a role off for a day, or back on.
    mutating func toggleOff(role: Int, day: Int) {
        let k = Self.offKey(role: role, day: day)
        if let i = crewOff.firstIndex(of: k) { crewOff.remove(at: i) } else { crewOff.append(k) }
    }

    /// Changes the risk with this id, wherever it now sits; nothing when it was removed. An edit arriving after another
    /// risk was deleted still lands on its own risk, as an index would not.
    mutating func updateRisk(_ id: UUID, _ change: (inout RoutineReport.Risk) -> Void) {
        guard let i = risks.firstIndex(where: { $0.id == id }) else { return }
        change(&risks[i])
    }

    /// Adds a day to a line, or takes it away.
    mutating func toggleDay(line id: UUID, day: Int) {
        guard let i = work.firstIndex(where: { $0.id == id }) else { return }
        if let j = work[i].days.firstIndex(of: day) { work[i].days.remove(at: j) } else { work[i].days = (work[i].days + [day]).sorted() }
    }

    /// Takes a role out, with its days off (the later roles' keys move down one).
    mutating func removeCrew(at index: Int) {
        guard crew.indices.contains(index) else { return }
        crew.remove(at: index)
        crewOff = crewOff.compactMap { k in
            let p = k.split(separator: "-").compactMap { Int($0) }
            guard p.count == 2, p[0] != index else { return nil }
            return Self.offKey(role: p[0] > index ? p[0] - 1 : p[0], day: p[1])
        }
    }

    /// Lines asked for on a day.
    func lines(on day: Int) -> Int { work.filter { $0.days.contains(day) }.count }

    /// A day has work when at least one line is on it.
    func hasWork(_ day: Int) -> Bool { work.contains { $0.days.contains(day) } }

    /// A role's people on a day: nil on a day with no work, 0 when the role is off.
    func people(role: Int, day: Int) -> Int? {
        guard crew.indices.contains(role), hasWork(day) else { return nil }
        return isOff(role: role, day: day) ? 0 : crew[role].count
    }

    /// Everyone on a day.
    func people(on day: Int) -> Int { crew.indices.reduce(0) { $0 + (people(role: $1, day: day) ?? 0) } }

    /// A role's man-days over the given days.
    func manDays(role: Int, days: [Int]) -> Int { days.reduce(0) { $0 + (people(role: role, day: $1) ?? 0) } }

    /// Everyone's man-days over the given days.
    func manDays(days: [Int]) -> Int { days.reduce(0) { $0 + people(on: $1) } }

    /// People per day as asked (every role at its count).
    var perDay: Int { crew.reduce(0) { $0 + $1.count } }

    /// Lines with no day yet.
    var linesWithoutDay: Int { work.filter(\.days.isEmpty).count }

    /// The plan's work for the week again, with the lines added outside the plan kept after it.
    func refreshed(from draft: Self) -> Self {
        var r = self
        r.work = draft.work + work.filter { $0.task == nil }
        return r
    }
}

public extension RoutineReport {
    /// When the request for the week starting `weekStart` is due: 15:00 on the Friday before, when the reminder
    /// `ยังไม่มีคำขอปฏิบัติงานสัปดาห์หน้า` fires (`NotificationPlan.request`).
    static func requestDeadline(_ weekStart: Date) -> Date {
        let friday = add(MasterSchedule.weekStart(weekStart), -2)
        return calendar.date(bySettingHour: 15, minute: 0, second: 0, of: friday) ?? friday
    }
}
