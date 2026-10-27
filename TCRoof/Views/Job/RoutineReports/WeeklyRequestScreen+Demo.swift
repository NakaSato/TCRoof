import SwiftUI
import TCRoofUI
import TCRoofCore

/// The board's example for `-requestDemo YES` (docs/ui/weekly-request-ipad-map `assets/sample-data.json`), dated from
/// the week shown and kept in memory only. Release builds never reach it (`WeeklyRequestScreen.demo` is false there).
extension WeeklyRequestScreen {
    /// The station's settings with the board's places, placed on the drawn key plan (`Job.demoPicture`).
    static func demoSettings(_ base: RoutineReport.Settings) -> RoutineReport.Settings {
        var s = base
        s.locations = ["หลังคา 1", "หลังคา 2", "หลังคา 3", "ถังน้ำใส 1", "ห้องอินเวอร์เตอร์"]
        s.keyPoints = ["หลังคา 1": [0.30, 0.31], "หลังคา 2": [0.56, 0.26], "หลังคา 3": [0.72, 0.55],
                       "ถังน้ำใส 1": [0.25, 0.70], "ห้องอินเวอร์เตอร์": [0.50, 0.715]]
        s.siteEngineer = "นายสมชาย ใจดี"
        s.workStart = 8 * 60; s.workEnd = 17 * 60
        s.tools = ["สว่านไร้สาย", "สว่านไฟฟ้า", "เครื่องมือช่าง", "บันได"]
        return s
    }

    /// The board's MP lines of the week at their places: the three asked for and two more `+`.
    static func demoPlanned(_ week: Date) -> [RoutineReport.PlanLine] {
        [(MasterSchedule.Task.dcSide, "ติดตั้งรางเก็บสายไฟกระแสตรง", "หลังคา 1", [0, 1, 2]),
         (.acSide, "ติดตั้งรางเก็บสายไฟกระแสสลับ", "ห้องอินเวอร์เตอร์", [2, 3]),
         (.fireSwitch, "ติดตั้งตู้ Fire Fighter Switch", "ถังน้ำใส 1", [3, 4, 5]),
         (.dcSide, "ติดตั้งรางเก็บสายไฟกระแสตรง", "หลังคา 2", [3, 4]),
         (.dcSide, "ติดตั้งรางเก็บสายไฟกระแสตรง", "หลังคา 3", [4, 5])]
            .map { RoutineReport.PlanLine(task: $0.0, description: $0.1, location: $0.2, days: $0.3) }
    }

    /// The board's request: next week (offset 0) a draft of three lines, the weeks before approved.
    static func demoRequest(_ week: Date, offset: Int) -> RoutineReport.WeeklyRequest {
        var r = RoutineReport.WeeklyRequest(weekStart: week)
        r.crew = [("ผู้ควบคุมงาน", 1), ("หัวหน้างาน", 1), ("ผู้ปฏิบัติงาน", 5)].map { .init(name: $0.0, count: $0.1) }
        r.tools = [("สว่านไร้สาย", 1), ("สว่านไฟฟ้า", 1), ("เครื่องมือช่าง", 1)].map { .init(name: $0.0, count: $0.1) }
        r.work = Array(demoPlanned(week).prefix(3))
        r.workStart = 8 * 60; r.workEnd = 18 * 60
        r.assessDefaults()
        if offset < 0 {
            let at = RoutineReport.add(r.weekStart, -2)
            r.send(by: "engineer@tcroof.test", signs: true, at: at)
            r.approve(by: "วนิดา ศรีสุข", at: at)
        }
        return r
    }

    /// A drawn signature for `-requestState signed|sent|approved`.
    static var demoSignature: Data? {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 70)).image { _ in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 10, y: 50))
            for i in 1...10 { p.addQuadCurve(to: CGPoint(x: 10 + i * 22, y: i % 2 == 0 ? 50 : 30), controlPoint: CGPoint(x: i * 22, y: i % 2 == 0 ? 10 : 70)) }
            UIColor(Theme.navy).setStroke(); p.lineWidth = 3; p.stroke()
        }.pngData()
    }
}
