import Foundation
import SwiftData
import TCRoofCore

/// The daily reports' finished WBS sub-tasks (CHA-71, `RoutineReport+WBS`): what waits for the team, and the team's
/// `ยืนยัน` / `ส่งกลับ` / `ลงนามรับทราบ` on them.
extension Job {
    /// A saved daily report as the picks read it: its recorder, whether it is signed, its lines' photo counts.
    func wbsReport(_ log: InstallLog) -> RoutineReport.WBSReport? {
        guard let daily = log.report else { return nil }
        var photos: [UUID: Int] = [:]
        for line in daily.progress {
            let tag = line.id.uuidString
            photos[line.id] = log.photos.filter { $0.tag == tag }.count
        }
        return .init(daily: daily, reporter: log.recorder, signed: log.engineerSignedAt != nil, photos: photos)
    }

    /// The signed reports' picks no tick has yet and the team hasn't sent back, oldest first.
    var wbsPending: [RoutineReport.WBSPick] {
        RoutineReport.wbsPending(dailyLogs.compactMap(wbsReport), ticks: wbsTicks, items: scheduleWBS)
    }

    /// The pick's report.
    func dailyLog(for pick: RoutineReport.WBSPick) -> InstallLog? {
        dailyLogs.first { RoutineReport.calendar.isDate($0.date, inSameDayAs: pick.day) && $0.report?.progress.contains { $0.id == pick.lineID } == true }
    }

    /// `ยืนยัน`: the picks become ticks in the name of who confirms them, dated their report's day; the job books them.
    @MainActor func confirmWBS(_ picks: [RoutineReport.WBSPick], by email: String, context: ModelContext) {
        var ticks = wbsTicks
        for pick in picks where ticks[pick.code] == nil { ticks[pick.code] = RoutineReport.confirm(pick, by: email) }
        guard ticks != wbsTicks else { return }
        wbsTicks = ticks
        try? context.save()
    }

    /// `ส่งกลับ`: the pick goes back to the reporter on its line, with the reason; it no longer waits.
    @MainActor func returnWBS(_ pick: RoutineReport.WBSPick, reason: String, context: ModelContext) {
        guard let log = dailyLog(for: pick), var daily = log.report, daily.returnWBS(pick.code, line: pick.lineID, reason: reason) else { return }
        log.report = daily
        try? context.save()
    }

    /// `ลงนามรับทราบ` on reports confirms every pick still waiting in them, when the signed-in member may.
    @MainActor func confirmWBSPicks(in logs: [InstallLog]) {
        let me = MemberRole.shared.permissions
        guard me.mayConfirmWBS(on: access), !scheduleWBS.isEmpty else { return }
        var ticks = wbsTicks
        for log in logs {
            guard let r = wbsReport(log) else { continue }
            ticks = RoutineReport.confirmingAll(r, ticks: ticks, items: scheduleWBS, by: me.email)
        }
        if ticks != wbsTicks { wbsTicks = ticks }
    }

    #if DEBUG
    /// `-wbsPending YES`: two unticked sub-tasks of the first WBS task picked on the latest signed report (signing the
    /// latest report when none is), once.
    @MainActor func seedWBSPending(_ context: ModelContext) {
        guard wbsPending.isEmpty, let task = scheduleWBS.compactMap(\.task).first(where: { !DailyWBSPicks.choices(scheduleWBS, task: $0).isEmpty }),
              let log = dailyLogs.last(where: { $0.engineerSignedAt != nil }) ?? dailyLogs.last, var daily = log.report else { return }
        let codes = DailyWBSPicks.choices(scheduleWBS, task: task).filter { wbsTicks[$0.code] == nil }.prefix(2).map(\.code)
        guard !codes.isEmpty else { return }
        var line = daily.progress.first { $0.task == task } ?? RoutineReport.ProgressLine(task: task, description: "", location: "")
        line.wbsDone = Array(codes)
        if let i = daily.progress.firstIndex(where: { $0.id == line.id }) { daily.progress[i] = line } else { daily.progress.append(line) }
        log.report = daily
        if log.engineerSignedAt == nil { log.engineerSignedAt = log.date }
        try? context.save()
    }
    #endif
}
