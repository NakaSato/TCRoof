import Foundation
import TCRoofCore

/// The monthly travel and expense claim (docs/specs/calendar-travel-expenses-swift.md §B5) as A4 pages: the header,
/// the day-by-day trips, the expenses, the totals with the signature lines, then every receipt two per page numbered as
/// in the table, and the odometer photos after them. The company's own layout (decided 2026-10-19: no form to copy).
public struct ClaimPages {
    public struct Header: Sendable {
        public var company: String
        public var person: String
        public var email: String
        /// The first day of the claimed month.
        public var month: Date
        public var submittedAt: Date?
        public init(company: String, person: String, email: String, month: Date, submittedAt: Date? = nil) {
            self.company = company; self.person = person; self.email = email; self.month = month; self.submittedAt = submittedAt
        }
    }

    /// A picture printed in the appendix.
    public struct Picture: Sendable {
        public var photo: Photo
        public var caption: String
        public init(photo: Photo, caption: String) { self.photo = photo; self.caption = caption }
    }

    public let header: Header
    public let summary: TravelClaim.Summary
    /// "TC-0412 สถานีผลิตน้ำโคราช" per job sync id.
    public let jobNames: [String: String]
    /// Receipt photos by expense id.
    public let receipts: [String: Photo]
    public let odometers: [Picture]
    public let signature: Photo?
    let base: RoutineReportPages

    public init(header: Header, summary: TravelClaim.Summary, jobNames: [String: String], receipts: [String: Photo] = [:],
                odometers: [Picture] = [], signature: Photo? = nil, measure: TextMeasuring = ApproxMeasure()) {
        self.header = header; self.summary = summary; self.jobNames = jobNames; self.receipts = receipts
        self.odometers = odometers; self.signature = signature
        base = RoutineReportPages(station: .init(name: "", code: "", mpNumber: nil, capacityKWp: 0, settings: .init()), measure: measure)
    }

    typealias Flow = RoutineReportPages.Flow
    typealias Column = RoutineReportPages.Column
    static let margin = RoutineReportPages.margin
    static var cw: Double { RoutineReportPages.cw }

    /// The receipt number printed in the table and on its picture: the expenses with a receipt, in table order.
    public var receiptNumbers: [String: Int] {
        var out: [String: Int] = [:]
        for item in summary.items where receipts[item.id] != nil { out[item.id] = out.count + 1 }
        return out
    }

    func job(_ id: String?) -> String {
        guard let id else { return "—" }
        return jobNames[id] ?? "งานที่ลบแล้ว"
    }

    static func time(_ d: Date?) -> String {
        guard let d else { return "–" }
        let c = TravelClaim.calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func km(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "–" }

    public func pages() -> [ReportLayout.Page] {
        let month = RoutineReport.thaiMonth(header.month)
        var f = Flow(title: "ใบเบิกค่าเดินทางและค่าใช้จ่าย", subtitle: "\(header.company) · \(month)")
        let vehicles = Set(summary.days.map(\.vehicle)).sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", ")
        let plates = Set(summary.days.map(\.plate).filter { !$0.isEmpty }).sorted().joined(separator: ", ")
        base.facts(&f, [("ผู้เบิก", header.person), ("อีเมล", header.email), ("เดือน", month),
                        ("ยื่นเบิก", header.submittedAt.map(RoutineReport.thaiDate) ?? "ยังไม่ยื่น"),
                        ("ยานพาหนะ", vehicles.isEmpty ? "–" : vehicles), ("ทะเบียน", plates.isEmpty ? "–" : plates)])

        base.heading(&f, "1. การเดินทางรายวัน")
        if summary.days.isEmpty {
            base.note(&f, "ไม่มีการเดินทางในเดือนนี้")
        } else {
            var rows: [[String]] = []
            for d in summary.days {
                let route = ([d.startPlace.isEmpty ? "สำนักงาน" : d.startPlace] + d.stops.map(\.label)).joined(separator: " → ")
                let visits = d.stops.map { s in
                    "\(s.label) \(Self.time(s.arrivedAt))–\(Self.time(s.departedAt))" + (s.legEdited ? " (แก้ระยะเอง: \(s.legNote))" : "")
                }.joined(separator: "\n")
                var km = Self.km(d.km)
                if let odo = d.odometerKm { km += "\nไมล์ \(odo)" }
                if d.odometerDiffers, !d.odoReason.isEmpty { km += "\n" + d.odoReason }
                rows.append([RoutineReport.thaiDate(d.date), route, visits.isEmpty ? "–" : visits, km,
                             d.vehicle.paysMileage ? d.mileage.map(TravelClaim.baht) ?? "–" : "–"])
            }
            rows.append(["รวม", "", "", Self.km(summary.km), TravelClaim.baht(summary.mileage)])
            base.table(&f, [Column(title: "วันที่", width: 62), Column(title: "เส้นทาง", width: 150),
                            Column(title: "สถานี (ถึง–ออก)", width: 150), Column(title: "กม.", width: 50, align: .right),
                            Column(title: "ค่าเดินทาง (บาท)", width: 66, align: .right)], rows, bold: [rows.count - 1], size: 8.5)
            if summary.mileage > 0 {
                let rates = Set(summary.days.filter(\.vehicle.paysMileage).map(\.rate)).sorted().map { RoutineReportPages.num($0) }
                base.note(&f, "ค่าเดินทางรถส่วนตัวคิด กม. × \(rates.joined(separator: ", ")) บาท/กม. ระยะทางจากเส้นทางถนน รวมเที่ยวกลับ")
            }
        }

        base.heading(&f, "2. รายการค่าใช้จ่าย")
        let numbers = receiptNumbers
        if summary.items.isEmpty {
            base.note(&f, "ไม่มีรายการค่าใช้จ่าย")
        } else {
            var rows: [[String]] = []
            for i in summary.items {
                let vendor = [i.vendor, i.taxID.isEmpty ? "" : "เลขภาษี \(i.taxID)", i.note].filter { !$0.isEmpty }.joined(separator: "\n")
                rows.append([RoutineReport.thaiDate(i.date), i.category.title, vendor.isEmpty ? "–" : vendor, job(i.jobID),
                             TravelClaim.baht(i.amount), numbers[i.id].map { "#\($0)" } ?? "ไม่มี"])
            }
            let itemsTotal = summary.items.reduce(0) { $0 + $1.amount }
            rows.append(["รวม", "", "", "", TravelClaim.baht(itemsTotal), ""])
            base.table(&f, [Column(title: "วันที่", width: 60), Column(title: "ประเภท", width: 62), Column(title: "ร้าน / รายละเอียด", width: 140),
                            Column(title: "งาน", width: 118), Column(title: "จำนวนเงิน", width: 62, align: .right),
                            Column(title: "ใบเสร็จ", width: 40, align: .center)], rows, bold: [rows.count - 1], size: 8.5)
        }

        base.heading(&f, "3. สรุปยอดเบิก")
        var totals = summary.byCategory.map { [$0.category.title, TravelClaim.baht($0.amount)] }
        totals.append(["รวมทั้งสิ้น", TravelClaim.baht(summary.total)])
        base.table(&f, [Column(title: "ประเภท", width: 300), Column(title: "บาท", width: 100, align: .right)], totals, bold: [totals.count - 1])
        let jobs = summary.byJob.map { [$0.jobID == nil ? "ไม่ระบุงาน" : job($0.jobID), TravelClaim.baht($0.amount)] }
        if !jobs.isEmpty {
            base.table(&f, [Column(title: "แยกตามงาน", width: 300), Column(title: "บาท", width: 100, align: .right)], jobs)
        }
        signatures(&f)

        // one page count for the claim and its appendix: each flow numbers its own pages, so number them again
        let all = (f.finish() + appendix(numbers)).map { ReportLayout.Page(ops: Array($0.ops.dropLast(2)), width: $0.width, height: $0.height) }
        let m = Self.margin, h = RoutineReportPages.pageH
        return all.enumerated().map { i, p in
            ReportLayout.Page(ops: p.ops + [
                .text("สร้างจาก TCRoof", at: Pt(m, h - m + 4), size: 7.5, color: RoutineReportPages.muted),
                .text("หน้า \(i + 1)/\(all.count)", at: Pt(RoutineReportPages.pageW - m, h - m + 4), size: 7.5,
                      color: RoutineReportPages.muted, align: .right),
            ], width: p.width, height: p.height)
        }
    }

    /// ผู้เบิก with the drawn signature over its line, and a blank ผู้อนุมัติ.
    func signatures(_ f: inout Flow) {
        let w = Self.cw / 2
        var o: [DrawOp] = []
        for (i, role) in ["ผู้เบิก", "ผู้อนุมัติ"].enumerated() {
            let cx = Self.margin + w * (Double(i) + 0.5)
            if i == 0, let signature { o.append(.photo(signature, Box(cx - 70, 0, 140, 40))) }
            o.append(.line(Pt(cx - 80, 42), Pt(cx + 80, 42), width: 0.6, color: .black))
            let name = i == 0 ? header.person : ""
            o.append(.text("(\(name.isEmpty ? "                              " : name))", at: Pt(cx, 54), size: 9, align: .center))
            o.append(.text(role, at: Pt(cx, 68), size: 9, color: RoutineReportPages.muted, align: .center))
            let date = i == 0 ? header.submittedAt.map(RoutineReport.thaiDate) ?? "วันที่ ........................" : "วันที่ ........................"
            o.append(.text(date, at: Pt(cx, 82), size: 9, color: RoutineReportPages.muted, align: .center))
        }
        f.need(100)
        f.y += 10
        f.place(92, o)
    }

    /// Receipts two per page in table order, then the odometer photos.
    func appendix(_ numbers: [String: Int]) -> [ReportLayout.Page] {
        var pictures: [Picture] = []
        for item in summary.items {
            guard let photo = receipts[item.id], let n = numbers[item.id] else { continue }
            pictures.append(Picture(photo: photo, caption: "#\(n) · \(RoutineReport.thaiDate(item.date)) · \(item.category.title) · \(TravelClaim.baht(item.amount)) บาท"))
        }
        pictures += odometers
        guard !pictures.isEmpty else { return [] }
        var f = Flow(title: "ภาคผนวก: ใบเสร็จและเลขไมล์", subtitle: "\(header.person) · \(RoutineReport.thaiMonth(header.month))")
        let h = (RoutineReportPages.pageH - 2 * Self.margin - 50 - 20 - 2 * 30) / 2
        for (i, p) in pictures.enumerated() {
            if i > 0, i % 2 == 0 { f.newPage() }
            f.place(h + 30, [.rect(Box(Self.margin, 0, Self.cw, h), stroke: RoutineReportPages.line, fill: nil, width: 0.5),
                             .photo(p.photo, Box(Self.margin + 4, 4, Self.cw - 8, h - 8)),
                             .text(p.caption, at: Pt(Self.margin, h + 12), size: 9.5, bold: true, color: RoutineReportPages.navy)])
        }
        return f.finish()
    }
}
