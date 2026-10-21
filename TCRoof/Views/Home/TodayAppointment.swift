import Foundation
import TCRoofCore
import TCRoofUI

/// One of today's survey appointments on the iPhone hero card, with the NO.224 report linked to its job.
struct TodayAppointment: Identifiable {
    let job: Job
    /// The job's most recently edited linked report; nil until a report is started.
    let report: TCRoofCore.Job?

    var id: String { job.syncID ?? job.code }

    /// Today's survey appointments still ahead, earliest first (the rule behind the header's "งานถัดไป").
    @MainActor static func list(jobs: [Job], survey: SurveyModel) -> [TodayAppointment] {
        jobs.filter { $0.surveyDate.isToday && $0.surveyDate > .now }
            .sorted { $0.surveyDate < $1.surveyDate }
            .map { job in
                let report = job.syncID.flatMap { survey.jobs(linkedTo: $0).max { $0.updated < $1.updated } }
                return TodayAppointment(job: job, report: report)
            }
    }

    var time: String { ThaiFormat.time.string(from: job.surveyDate) }
    /// "อีก 49 นาที" / "อีก 2 ชม.", as on the notification row.
    var countdown: String { countdown(to: job.surveyDate) }

    func countdown(to date: Date) -> String {
        let mins = Int(date.timeIntervalSinceNow / 60)
        return mins >= 60 ? "อีก \(mins / 60) ชม." : "อีก \(max(mins, 1)) นาที"
    }

    var name: String {
        let doc = report.map(\.docNo).flatMap { $0.isEmpty ? nil : "NO.\($0)" }
        let project = report.map(\.projectName).flatMap { $0.isEmpty ? nil : $0 } ?? job.projectName
        return [doc ?? job.code, project].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "ต.หนองบัว อ.เมือง": sub-district and district from the address, else the province.
    var area: String {
        let parts = job.address.split(separator: " ").map(String.init)
            .filter { p in ["ต.", "อ.", "แขวง", "เขต"].contains { p.hasPrefix($0) } }
        return parts.isEmpty ? (job.province.isEmpty ? "" : "จ.\(job.province)") : parts.joined(separator: " ")
    }

    /// "ต.หนองบัว อ.เมือง | 120 kWp"
    var place: String {
        let size = job.capacityKW > 0 ? "\(job.capacityKW.plain) kWp" : ""
        return [area, size].filter { !$0.isEmpty }.joined(separator: " | ")
    }

    var percent: Int { report?.completion.percent ?? 0 }
    var fraction: Double { report.map { $0.completion.fraction } ?? 0 }
    var nextStep: SurveyStep? { report?.nextStep }

    /// "D1 ถังน้ำใส"
    var nextStepLabel: String? { nextStep.map { "\($0.code) \($0.title)" } }

    /// Primary button: continue a started report, or start one at A1.
    var actionTitle: String {
        guard report != nil else { return "เริ่มสำรวจ A1 ›" }
        return nextStepLabel.map { "ทำต่อ \($0) ›" } ?? "เปิดแบบสำรวจ ›"
    }

    /// A1 GPS of the report, for Apple Maps.
    var coordinate: (lat: Double, lon: Double)? {
        guard let r = report, GPS.check(r.values.text("gps")) == .ok else { return nil }
        return GPS.parse(r.values.text("gps"))
    }

    /// The report's coordinator phone, else the customer's phone on the job.
    var phone: String {
        let p = report?.values.text("phone").trimmingCharacters(in: .whitespaces) ?? ""
        return p.isEmpty ? job.phone.trimmingCharacters(in: .whitespaces) : p
    }

    var contactName: String {
        let c = report?.values.text("coordinator").trimmingCharacters(in: .whitespaces) ?? ""
        return c.isEmpty ? job.customerName : c
    }
}
