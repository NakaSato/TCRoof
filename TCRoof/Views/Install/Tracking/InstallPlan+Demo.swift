import Foundation
import TCRoofCore

#if DEBUG
extension InstallPlan {
    /// The board's crew, links, baseline and make-ready, for screenshots only.
    static func demo(gantt: InstallGantt, nonWorking: Set<Date>, tracking: InstallTracking?, day: Date) -> InstallPlan {
        func d(_ i: Int) -> Date { day.adding(days: i - 6) }
        let stageCrew = [6, 8, 8, 7, 4, 3, 4]
        let subCrew = [[6, 2, 2, 2], [2, 4, 4, 4, 2], [8, 3, 3, 2, 2], [4, 3, 3, 2, 2], [2, 2, 2, 2, 1], [3, 2, 2, 2, 1], [2, 4, 2, 2, 2]]
        var x = InstallPlan(gantt: gantt, nonWorking: nonWorking, tracking: tracking,
                            milestones: [.init(title: "เริ่มงานหน้างาน", date: d(0)), .init(title: "ติดตั้งแผงครบ 164 แผง", date: d(4)),
                                         .init(title: "ทดสอบ IEC 62446-1", date: d(9)), .init(title: "ขนานไฟ · ส่งมอบ กปภ.", date: d(12))],
                            crew: [:])
        for i in x.stages.indices {
            x.stages[i].row.crew = stageCrew[i]
            x.stages[i].row.after = i == 0 ? nil : "\(i)"
            for k in x.stages[i].subs.indices {
                x.stages[i].subs[k].crew = subCrew[i][k]
                x.stages[i].subs[k].after = k > 0 ? "\(i + 1).\(k)" : i > 0 ? "\(i)" : nil
            }
        }
        x.crew = Dictionary(uniqueKeysWithValues: x.days.map { day in
            (day, x.stages.enumerated().reduce(0) { $0 + ($1.element.row.start <= day && day <= $1.element.row.end ? stageCrew[$1.offset] : 0) })
        })
        x.teamSize = 8
        x.baseline = Baseline(revision: "Baseline REV 01", approved: d(-2), by: "ผู้ควบคุมงาน กปภ.")
        x.ready = Ready(stage: "ขั้น 5 · อินเวอร์เตอร์ · ระบบ AC",
                        items: [.init("วัสดุ", ok: false, note: "ตู้ AC รออนุมัติ MA-05"), .init("ใบอนุญาต", ok: true, note: "WP-02 งานไฟฟ้า"),
                                .init("ทีม", ok: true, note: "TCR02 · 4 คน")])
        return x
    }
}
#endif
