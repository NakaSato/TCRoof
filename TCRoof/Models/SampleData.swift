import Foundation
import SwiftData

enum SampleData {
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Job>())) ?? 0
        guard count == 0 else { return }
        seed(context)
    }

    /// Deletes the demo jobs seeded by earlier versions, once, so they never reach the team's shared data.
    static func removeSamples(_ context: ModelContext) {
        let key = "sampleData.removed"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let samples = Set(seeds.map { "\($0.project)|\($0.customer)|\($0.phone)" })
        for job in (try? context.fetch(FetchDescriptor<Job>())) ?? []
        where samples.contains("\(job.projectName)|\(job.customerName)|\(job.phone)") {
            context.delete(job)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    static func newJobCode() -> String {
        "TCR\(ThaiFormat.year.string(from: .now))-\(Int.random(in: 10000...99999))"
    }

    private struct Seed {
        let project, customer, phone, address, province: String
        let kw: Double
        let team: Team
        let status: JobStatus
        let surveyOffset, installOffset, days: Int
    }

    private static let seeds: [Seed] = [
        .init(project: "คุณดารา ภัทรปรีดา", customer: "คุณดารา ภัทรปรีดา", phone: "0812345678",
              address: "99/12 ซ.ลาดพร้าว 71 แขวงลาดพร้าว เขตลาดพร้าว", province: "กรุงเทพมหานคร",
              kw: 14.08, team: .t1, status: .installing, surveyOffset: -14, installOffset: -1, days: 4),
        .init(project: "บริษัท คิดดี จำกัด", customer: "บริษัท คิดดี จำกัด", phone: "038123456",
              address: "88 ม.3 ต.บ้านสวน อ.เมือง", province: "ชลบุรี",
              kw: 49.5, team: .t2, status: .confirmed, surveyOffset: -10, installOffset: 1, days: 5),
        .init(project: "คุณนพพร วีระโชติ", customer: "คุณนพพร วีระโชติ", phone: "0891112222",
              address: "12 ถ.งามวงศ์วาน ต.บางกระสอ อ.เมือง", province: "นนทบุรี",
              kw: 5.5, team: .t3, status: .interested, surveyOffset: 0, installOffset: 16, days: 2),
        .init(project: "คุณรยา จุลพัฒน์", customer: "คุณรยา จุลพัฒน์", phone: "0865554444",
              address: "45/8 ซ.สุขุมวิท 101 แขวงบางจาก เขตพระโขนง", province: "กรุงเทพมหานคร",
              kw: 10.23, team: .t1, status: .interested, surveyOffset: 1, installOffset: 20, days: 3),
        .init(project: "โรงงานสยามแพ็คกิ้ง", customer: "บริษัท สยามแพ็คกิ้ง จำกัด", phone: "025551234",
              address: "234 นิคมอุตสาหกรรมบางปู", province: "สมุทรปราการ",
              kw: 199.8, team: .t4, status: .confirmed, surveyOffset: -21, installOffset: 3, days: 12),
        .init(project: "คุณสมศักดิ์ ใจดี", customer: "คุณสมศักดิ์ ใจดี", phone: "0823334444",
              address: "7 ม.5 ต.คลองหนึ่ง อ.คลองหลวง", province: "ปทุมธานี",
              kw: 8.25, team: .t3, status: .confirmed, surveyOffset: -5, installOffset: 5, days: 2),
        .init(project: "ร้านกาแฟบ้านสวน", customer: "คุณวิภาวรรณ ศรีสุข", phone: "0847778888",
              address: "19 ถ.สุขุมวิท ต.เนินพระ อ.เมือง", province: "ระยอง",
              kw: 15.4, team: .t2, status: .interested, surveyOffset: 3, installOffset: 25, days: 3),
        .init(project: "คุณปกรณ์ ศักดิ์สิทธิ์", customer: "คุณปกรณ์ ศักดิ์สิทธิ์", phone: "0810009999",
              address: "301 ซ.รามอินทรา 40 แขวงนวลจันทร์ เขตบึงกุ่ม", province: "กรุงเทพมหานคร",
              kw: 6.6, team: .t1, status: .completed, surveyOffset: -30, installOffset: -12, days: 2),
        .init(project: "หอพักกรีนเพลส", customer: "คุณอารีย์ มั่นคง", phone: "0852221111",
              address: "55 ถ.พหลโยธิน ต.คลองหนึ่ง อ.คลองหลวง", province: "ปทุมธานี",
              kw: 30.25, team: .t4, status: .interested, surveyOffset: 5, installOffset: 40, days: 4),
        .init(project: "คุณธนา วงศ์ใหญ่", customer: "คุณธนา วงศ์ใหญ่", phone: "0879990000",
              address: "8/3 ม.2 ต.บางพูด อ.ปากเกร็ด", province: "นนทบุรี",
              kw: 11.0, team: .t2, status: .confirmed, surveyOffset: -8, installOffset: 8, days: 3),
    ]

    private static func seed(_ context: ModelContext) {
        let today = Date().startOfDay
        let year = ThaiFormat.year.string(from: today)

        for (index, s) in seeds.enumerated() {
            let job = Job(code: "TCR\(year)-\(23401 + index)", projectName: s.project, customerName: s.customer,
                          phone: s.phone, address: s.address, province: s.province, capacityKW: s.kw,
                          team: s.team, status: s.status,
                          surveyDate: today.adding(days: s.surveyOffset).addingTimeInterval(9 * 3600),
                          installStart: today.adding(days: s.installOffset), installDays: s.days)
            context.insert(job)

            if s.surveyOffset < 0 {
                let survey = SurveyForm(surveyor: "สมชาย", roofType: "เมทัลชีท", roofAreaSqm: s.kw * 6,
                                        orientation: "ทิศใต้", tiltDegree: 10, shading: "ไม่มี", structureOK: true,
                                        meterPhase: s.kw > 10 ? "3 เฟส" : "1 เฟส", mainBreakerAmp: s.kw > 10 ? 63 : 32,
                                        monthlyBill: s.kw * 700, recommendedKW: s.kw, notes: "หลังคาอยู่ในสภาพดี เข้าถึงได้สะดวก")
                context.insert(survey)
                survey.job = job
                survey.createdAt = job.surveyDate
            }

            if s.status == .installing || s.status == .completed {
                for n in 0..<min(12, job.estimatedPanels) {
                    let device = ScannedDevice(kind: .panel, serial: "2180108520\(1587 + n * 7)", scannedBy: "วิชาญ")
                    context.insert(device)
                    device.job = job
                }
                let inverter = ScannedDevice(kind: .inverter, serial: "HW\(2400000 + index * 131)", scannedBy: "วิชาญ")
                context.insert(inverter)
                inverter.job = job

                let log = InstallLog(date: job.installStart, recorder: "วิชาญ",
                                     details: "งานติดตั้ง Pull Box\nเดินท่อในช่องชาร์ปไฟฟ้า\nติดตั้งรางและขาจับบนหลังคา")
                context.insert(log)
                log.job = job
                let symbols = ["shippingbox", "cable.connector", "wrench.and.screwdriver", "square.grid.3x3", "bolt"]
                for (i, symbol) in symbols.enumerated() {
                    let photo = PhotoAsset(data: ImageUtil.placeholder(symbol: symbol, hue: 0.55 + CGFloat(i) * 0.03))
                    context.insert(photo)
                    photo.log = log
                }
            }
        }
        try? context.save()
    }
}
