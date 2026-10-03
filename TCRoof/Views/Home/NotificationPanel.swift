import SwiftUI
import TCRoofCore
import SurveyUI

/// One notification of the bell. `id` stays the same while the event does, so "read" survives relaunches.
struct AppNotification: Identifiable {
    enum Kind { case survey, install, syncPending, saved }
    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let date: Date
    /// The job of a survey appointment, for the iPhone row's tap action.
    var job: Job? = nil
    /// "อีก 9 ชม." for an appointment still ahead; otherwise the time (today) or date and time (earlier).
    var timeText: String {
        if kind == .survey, date > .now {
            let mins = Int(date.timeIntervalSinceNow / 60)
            return mins >= 60 ? "อีก \(mins / 60) ชม." : "อีก \(max(mins, 1)) นาที"
        }
        return date.isToday ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            : ThaiFormat.dayMonthTime.string(from: date)
    }
    var isToday: Bool { date.isToday || kind == .survey || kind == .install || kind == .syncPending }

    /// Today's survey appointments and install days, survey reports still waiting to sync,
    /// and Drive saves of the last 7 days.
    @MainActor static func list(jobs: [Job], survey: SurveyModel) -> [AppNotification] {
        let day = ISODate.string(.now)
        var out: [AppNotification] = []
        for job in jobs {
            let key = job.syncID ?? job.code
            if job.surveyDate.isToday {
                out.append(.init(id: "survey-\(key)-\(day)", kind: .survey,
                                 title: "นัดสำรวจ " + job.surveyDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)),
                                 detail: [job.code, job.projectName, job.address].filter { !$0.isEmpty }.joined(separator: " · "),
                                 date: job.surveyDate, job: job))
            }
            if let d = job.installDay(on: .now) {
                out.append(.init(id: "install-\(key)-\(day)", kind: .install, title: "ติดตั้ง Day \(d)/\(job.installDays)",
                                 detail: "\(job.code) · ทีม \(job.team.rawValue) · \(job.capacityKW.plain) kWp · จ.\(job.province)",
                                 date: Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: job.installStart),
                                                             minute: Calendar.current.component(.minute, from: job.installStart), second: 0, of: .now) ?? .now))
            }
        }
        let pending = survey.jobsToSync
        if let latest = pending.map(\.updated).max() {
            // a new id whenever the count changes, so a fresh backlog shows as unread again
            out.append(.init(id: "sync-\(day)-\(pending.count)", kind: .syncPending, title: "รอซิงก์ \(pending.count) งาน",
                             detail: "ยังไม่ได้บันทึกขึ้นคลาวด์ · แตะเพื่อซิงก์ตอนมีสัญญาณ", date: latest))
        }
        let weekAgo = Date.now.adding(days: -7)
        for j in survey.jobs {
            guard let saved = j.drive?.lastSaved, saved > weekAgo else { continue }
            let name = [j.docNo.isEmpty ? "" : "NO.\(j.docNo)", j.projectName].filter { !$0.isEmpty }.joined(separator: " ")
            out.append(.init(id: "saved-\(j.id.uuidString)-\(saved.millis)", kind: .saved, title: "บันทึกขึ้น Drive แล้ว",
                             detail: "\(name.isEmpty ? "งานสำรวจ" : name) · \(j.photoCount) ภาพ", date: saved))
        }
        return out.sorted { a, b in a.isToday != b.isToday ? a.isToday : a.date > b.date }
    }
}
