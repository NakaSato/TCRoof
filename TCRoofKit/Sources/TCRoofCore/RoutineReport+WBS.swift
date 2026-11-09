import Foundation

/// The WBS sub-tasks a daily report line marks finished (CHA-71): the reporter (usually the contractor) picks them on
/// the line (`ProgressLine.wbsDone`), with the line's photos as evidence. A pick doesn't count until the team confirms
/// it (`ยืนยัน`, or `ลงนามรับทราบ` on the report, which confirms all of its picks) into a `WBSTick` with source
/// `daily`, booked like any tick; `ส่งกลับ` returns it to the reporter with a reason (`ProgressLine.wbsReturned`).
public extension RoutineReport {
    /// One saved daily report, as the picks need it.
    struct WBSReport: Sendable {
        public var daily: Daily
        /// The report's recorder (a name).
        public var reporter: String
        /// Signed by the reporter: only a signed report's picks wait for the team.
        public var signed: Bool
        /// The line's photos, by `ProgressLine.id`.
        public var photos: [UUID: Int]

        public init(daily: Daily, reporter: String, signed: Bool, photos: [UUID: Int] = [:]) {
            self.daily = daily; self.reporter = reporter; self.signed = signed; self.photos = photos
        }
    }

    /// A pick waiting for the team (`รอยืนยัน · รายงานประจำวัน`).
    struct WBSPick: Identifiable, Equatable, Sendable {
        public var code: String
        /// The report's day: the tick's day once confirmed.
        public var day: Date
        public var lineID: UUID
        public var lineKey: String
        public var lineTitle: String
        public var reporter: String
        /// The line's photos: the evidence.
        public var photos: Int

        public var id: String { RoutineReport.dayKey(day) + "|" + lineID.uuidString + "|" + code }
    }

    /// The signed reports' picks with no tick yet and not sent back, oldest day first; a code picked on several days
    /// waits once, on its first. With `items`, only the plan's rows that are ticked (no heading, a row of this
    /// station) are offered.
    static func wbsPending(_ reports: [WBSReport], ticks: [String: MasterSchedule.WBSTick],
                           items: [MasterSchedule.WorkItem]? = nil) -> [WBSPick] {
        let tickable: Set<String>? = items.map { rows in
            let parents = rows.parentCodes
            return Set(rows.filter { !parents.contains($0.code) && !$0.notForThisStation }.map(\.code))
        }
        var seen = Set<String>(), out: [WBSPick] = []
        for r in reports.sorted(by: { $0.daily.date < $1.daily.date }) where r.signed {
            for line in r.daily.progress {
                for code in line.wbsDone ?? [] where ticks[code] == nil && line.wbsReturned?[code] == nil {
                    if let tickable, !tickable.contains(code) { continue }
                    guard seen.insert(code).inserted else { continue }
                    out.append(WBSPick(code: code, day: calendar.startOfDay(for: r.daily.date), lineID: line.id, lineKey: line.key,
                                       lineTitle: line.title, reporter: r.reporter, photos: r.photos[line.id] ?? 0))
                }
            }
        }
        return out
    }

    /// The tick a confirmed pick becomes: dated the report's day (its week takes the booking), by who confirmed it.
    static func confirm(_ pick: WBSPick, by email: String, at now: Date = .now) -> MasterSchedule.WBSTick {
        .init(by: email, at: pick.day, source: .daily, reportedBy: pick.reporter.isEmpty ? nil : pick.reporter, confirmedAt: now)
    }

    /// `ลงนามรับทราบ` on a report: every pick of it still waiting becomes a tick. Picks of the report already ticked
    /// another way stay as they are.
    static func confirmingAll(_ report: WBSReport, ticks: [String: MasterSchedule.WBSTick], items: [MasterSchedule.WorkItem]? = nil,
                              by email: String, at now: Date = .now) -> [String: MasterSchedule.WBSTick] {
        var out = ticks
        var signed = report
        signed.signed = true
        for pick in wbsPending([signed], ticks: ticks, items: items) { out[pick.code] = confirm(pick, by: email, at: now) }
        return out
    }
}

public extension RoutineReport.ProgressLine {
    /// The reporter's chip: picks the code, or takes the pick back. A code sent back is picked again (the reason
    /// goes), for the team to look at once more.
    mutating func toggleWBSDone(_ code: String) {
        var done = wbsDone ?? []
        if wbsReturned?[code] != nil {
            wbsReturned?[code] = nil
            if !done.contains(code) { done.append(code) }
        } else if let i = done.firstIndex(of: code) {
            done.remove(at: i)
        } else {
            done.append(code)
        }
        wbsDone = done.isEmpty ? nil : done
        if wbsReturned?.isEmpty == true { wbsReturned = nil }
    }

    /// `ส่งกลับ`: the pick stays on the line, marked with the reason, and no longer waits.
    mutating func returnWBS(_ code: String, reason: String) {
        var r = wbsReturned ?? [:]
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        r[code] = text.isEmpty ? "ส่งกลับให้แก้" : text
        wbsReturned = r
    }
}

public extension RoutineReport.Daily {
    /// Sends a pick back on the line it was made on; false when the line or the pick is gone.
    @discardableResult
    mutating func returnWBS(_ code: String, line: UUID, reason: String) -> Bool {
        guard let i = progress.firstIndex(where: { $0.id == line }), progress[i].wbsDone?.contains(code) == true else { return false }
        progress[i].returnWBS(code, reason: reason)
        return true
    }
}
