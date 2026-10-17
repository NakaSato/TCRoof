#if DEBUG
import SwiftUI
import SwiftData
import TCRoofCore

extension Job {
    /// Station settings, the MP plan and signed daily reports for the last two weeks of working days (today left
    /// empty), unless the job has daily reports already. For `-screen daily|dailies|request|weekly|monthly`.
    func seedRoutineDemo(_ context: ModelContext) {
        seedMPDemo()
        guard dailyLogs.isEmpty else {
            if routineSettings.keyPoints.isEmpty, !routineSettings.locations.isEmpty {
                var s = routineSettings
                for (i, l) in s.locations.enumerated() { s.keyPoints[l] = [0.2 + 0.15 * Double(i % 5), 0.3 + 0.2 * Double(i % 3)] }
                routineSettings = s
            }
            return
        }
        var s = routineSettings
        s.contractName = "โครงการติดตั้งระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์บนหลังคา สถานีผลิตน้ำ กปภ."
        s.locations = ["หลังคา 1", "หลังคา 2", "หลังคา 3", "ถังน้ำใส 1", "ห้องอินเวอร์เตอร์"]
        s.siteEngineer = "วิศวกร สนาม"; s.inspector = "ผู้ตรวจ กฟภ."
        s.keyPoints = ["หลังคา 1": [0.3, 0.35], "หลังคา 2": [0.55, 0.3], "หลังคา 3": [0.7, 0.55],
                       "ถังน้ำใส 1": [0.25, 0.7], "ห้องอินเวอร์เตอร์": [0.5, 0.75]]
        routineSettings = s
        let cal = RoutineReport.calendar, today = cal.startOfDay(for: .now)
        let days = RoutineReport.workingDays(settings: s, from: cal.date(byAdding: .day, value: -14, to: today)!, to: today.adding(days: -1))
            .enumerated().filter { $0.offset != 3 }.map(\.element)     // one missing day
        var previous: RoutineReport.Daily?
        for (i, d) in days.enumerated() {
            var r = RoutineReport.nextDay(from: previous, date: d, settings: s)
            if previous == nil { r.crew = [.init(name: "ผู้ควบคุมงาน", count: 1), .init(name: "หัวหน้างาน", count: 1), .init(name: "ผู้ปฏิบัติงาน", count: 7)]
                                 r.tools = [.init(name: "สว่านไฟฟ้า", count: 2), .init(name: "บันได", count: 2)] }
            r.crewConfirmed = true
            r.weather = RoutineReport.weatherHours.map { h in i % 4 == 2 && h >= 14 && h < 18 ? .rain : h >= 17 ? .cloudy : .fine }
            func line(_ t: MasterSchedule.Task, _ loc: String, _ pct: Double) {
                if let k = r.progress.firstIndex(where: { $0.task == t && $0.location == loc }) { r.progress[k].percent = pct }
                else { r.progress.append(.init(task: t, description: "", location: loc, percent: pct)) }
            }
            line(.structure, "หลังคา 1", min(100, Double(i + 1) * 15))
            if i >= 3 { line(.structure, "หลังคา 2", min(100, Double(i - 2) * 20)) }
            line(.inverter, "ห้องอินเวอร์เตอร์", min(100, Double(i + 1) * 10))
            if i == 2 { r.problems.append(.init(description: "รางอะลูมิเนียมส่งมาไม่ครบ 12 เส้น", solution: "แจ้งผู้ขายส่งเพิ่ม", since: d)) }
            if i == 6, let k = r.problems.indices.first { r.problems[k].closed = true }
            if i == 5 { r.materials = [.init(name: "แผงโซลาร์ 550 W", location: "หน้าสถานี", qty: 84, unit: "แผง")] }
            let log = InstallLog(date: d, recorder: "วิศวกร สนาม", details: "")
            context.insert(log)
            log.job = self
            log.report = r
            log.engineerSignedAt = d.addingTimeInterval(17.5 * 3600)
            if i < days.count - 2 { log.inspectorAckAt = d.adding(days: 1) }
            previous = r
        }
        status = .installing
        feedMP()
        try? context.save()
    }
}

/// `-screen daily|dailies|request|weekly|monthly` with the seeded station.
struct RoutineDebugScreen: View {
    let job: Job
    let screen: String
    @Environment(\.modelContext) private var context
    @State private var seeded = false

    var body: some View {
        ZStack {
            Color.clear
            if seeded {
                switch screen {
                case "daily": DailyReportScreen(job: job, date: UserDefaults.standard.string(forKey: "routineDay").flatMap(ISODate.date) ?? .now)
                case "dailies": DailyReportListView(job: job)
                case "request": WeeklyRequestScreen(job: job)
                case "weekly": RoutineSummaryScreen(job: job, period: .week, anchor: Date().adding(days: -7))
                case "monthly": RoutineSummaryScreen(job: job, period: .month)
                default: RoutineReportCard(job: job).padding()
                }
            }
        }
        .onAppear {
            job.seedRoutineDemo(context)
            // `-jobTeam a@x,b@y` names the job's team members (no supervisor), `none` clears both; for good
            if let team = UserDefaults.standard.string(forKey: "jobTeam") {
                job.teamMembers = team == "none" ? [] : team.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                job.supervisorEmail = nil
                try? context.save()
            }
            seeded = true
        }
    }
}
#endif
