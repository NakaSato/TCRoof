import Foundation
import TCRoofCore

/// The monthly travel and expense claim as a one-sheet workbook (docs/specs/calendar-travel-expenses-swift.md §B5), the
/// same lines and totals as `ClaimPages`. Amounts are numbers in baht, so the sheet can be summed again.
public enum ClaimExcel {
    public static func export(company: String, person: String, email: String, month: Date, submittedAt: Date?,
                              summary s: TravelClaim.Summary, jobNames: [String: String], receiptNumbers: [String: Int]) throws -> Data {
        typealias X = DailyReportExcel
        func job(_ id: String?) -> String { id.map { jobNames[$0] ?? "งานที่ลบแล้ว" } ?? "" }
        func baht(_ satang: Int) -> X.Cell { .number(Double(satang) / 100, .cell) }
        func time(_ d: Date?) -> String {
            guard let d else { return "" }
            let c = TravelClaim.calendar.dateComponents([.hour, .minute], from: d)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }

        var x = X.Sheet()
        x.row([.text("ใบเบิกค่าเดินทางและค่าใช้จ่าย", .title)], merge: 7)
        x.row([.text("บริษัท", .bold), .text(company)], merge: 7, from: 2)
        x.row([.text("ผู้เบิก", .bold), .text("\(person) (\(email))")], merge: 7, from: 2)
        x.row([.text("เดือน", .bold), .text(RoutineReport.thaiMonth(month))], merge: 7, from: 2)
        x.row([.text("ยื่นเบิก", .bold), .text(submittedAt.map(RoutineReport.thaiDate) ?? "ยังไม่ยื่น")], merge: 7, from: 2)
        x.blank()

        x.row([.text("1. การเดินทางรายวัน", .section)])
        x.row(["วันที่", "ยานพาหนะ", "ทะเบียน", "เส้นทาง", "สถานี (ถึง–ออก)", "กม.", "ค่าเดินทาง (บาท)"].map { .text($0, .head) })
        for d in s.days {
            let route = ([d.startPlace.isEmpty ? "สำนักงาน" : d.startPlace] + d.stops.map(\.label)).joined(separator: " → ")
            let visits = d.stops.map { "\($0.label) \(time($0.arrivedAt))–\(time($0.departedAt))" }.joined(separator: "\n")
            x.row([.text(RoutineReport.thaiDate(d.date), .cell), .text(d.vehicle.title, .cell), .text(d.plate, .cell),
                   .text(route, .cell), .text(visits, .cell), d.km.map { .number($0, .cell) } ?? .text("", .cell),
                   d.vehicle.paysMileage ? d.mileage.map(baht) ?? .text("", .cell) : .text("", .cell)])
        }
        x.row([.text("รวม", .headLeft), .empty, .empty, .empty, .empty, .number((s.km * 10).rounded() / 10, .head),
               .number(Double(s.mileage) / 100, .head)])
        x.blank()

        x.row([.text("2. รายการค่าใช้จ่าย", .section)])
        x.row(["วันที่", "ประเภท", "ร้าน", "เลขภาษี", "งาน", "จำนวนเงิน (บาท)", "ใบเสร็จ"].map { .text($0, .head) })
        for i in s.items {
            x.row([.text(RoutineReport.thaiDate(i.date), .cell), .text(i.category.title, .cell),
                   .text([i.vendor, i.note].filter { !$0.isEmpty }.joined(separator: " | "), .cell), .text(i.taxID, .cell),
                   .text(job(i.jobID), .cell), baht(i.amount), .text(receiptNumbers[i.id].map { "#\($0)" } ?? "ไม่มี", .center)])
        }
        x.row([.text("รวม", .headLeft), .empty, .empty, .empty, .empty, .number(Double(s.items.reduce(0) { $0 + $1.amount }) / 100, .head)])
        x.blank()

        x.row([.text("3. สรุปยอดเบิก", .section)])
        for c in s.byCategory { x.row([.text(c.category.title, .cell), baht(c.amount)]) }
        x.row([.text("รวมทั้งสิ้น", .headLeft), .number(Double(s.total) / 100, .head)])
        x.blank()
        x.row([.text("แยกตามงาน", .head), .text("บาท", .head)])
        for j in s.byJob { x.row([.text(j.jobID == nil ? "ไม่ระบุงาน" : job(j.jobID), .cell), baht(j.amount)]) }
        return try x.workbook(name: "ใบเบิก", widths: [16, 14, 26, 40, 40, 12, 16])
    }
}
