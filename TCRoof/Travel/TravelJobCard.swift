import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// The job screen's travel card (§B2, §B5): ถึงสถานีแล้ว / ออกจากสถานี today, and what this person's travel to the job
/// has cost so far. The team's only.
struct TravelJobCard: View {
    let job: Job

    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.date) private var trips: [Trip]
    @Query(sort: \Expense.date) private var expenses: [Expense]
    @State private var busy = false
    @State private var notice: String?

    private var me: String { TravelStore.owner }
    private var todayStop: TravelClaim.Stop? {
        trips.first { $0.ownerEmail == me && TravelClaim.calendar.isDateInToday($0.date) }?.stops.last { $0.jobID == job.syncID }
    }
    private var cost: (amount: Int, visits: Int) {
        guard let id = job.syncID else { return (0, 0) }
        return TravelClaim.jobCost(id, days: trips.filter { $0.ownerEmail == me }.map(\.day),
                                   items: expenses.filter { $0.ownerEmail == me }.map(\.item))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("การเดินทาง", systemImage: "car.fill").font(.sarabun(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Spacer()
                NavigationLink { ClaimScreen() } label: {
                    Text("เบิกค่าใช้จ่าย").font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.primary)
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line).font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                    let c = cost
                    if c.amount > 0 || c.visits > 0 {
                        Text("ค่าเดินทางงานนี้ \(TravelClaim.baht(c.amount)) บาท | \(c.visits) ครั้ง")
                            .font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                    }
                }
                Spacer(minLength: 8)
                if busy {
                    ProgressView().frame(width: 44, height: 44)
                } else if todayStop?.isOpen == true {
                    Button("ออกจากสถานี") { Task { await stamp(.depart) } }.buttonStyle(TCButtonStyle(.secondary, size: .card))
                } else {
                    Button("ถึงสถานีแล้ว") { Task { await stamp(.arrive) } }.buttonStyle(TCButtonStyle(.primary, size: .card))
                        .accessibilityIdentifier("travel.arrive")
                }
            }
        }
        .padding(16)
        .tcCard()
        .tcToast($notice, duration: 3)
    }

    private var line: String {
        guard let s = todayStop else { return "วันนี้ยังไม่ได้บันทึกเวลาถึงสถานีนี้" }
        var parts = ["วันนี้ถึง \(ClaimPagesTime.format(s.arrivedAt))"]
        if s.departedAt != nil { parts.append("ออก \(ClaimPagesTime.format(s.departedAt))") }
        return parts.joined(separator: " | ")
    }

    private func stamp(_ kind: TravelClaim.StampKind) async {
        busy = true
        let result = await TravelStore.stamp(kind, job: job, context: context)
        busy = false
        switch result {
        case .undone?: notice = "ยกเลิกเวลาที่เพิ่งบันทึกแล้ว"
        case .stamped?: notice = kind == .arrive ? "บันทึกเวลาถึงแล้ว | กดอีกครั้งภายใน 2 นาทีเพื่อยกเลิก" : "บันทึกเวลาออกแล้ว"
        case .nothingToClose?: notice = "ยังไม่ได้บันทึกเวลาถึงสถานีนี้"
        case nil: notice = "เดือนนี้ยื่นเบิกแล้ว ถอนการยื่นก่อนจึงบันทึกได้"
        }
    }
}

#if DEBUG
/// `-screen travel -travelDemo YES`: three days to three stations and five receipts this month, for simulator checks.
/// Kept (for good) on the device's own account; seeded once per month.
@MainActor
enum TravelDemo {
    static func seed(_ context: ModelContext, jobs: [Job]) {
        let month = TravelClaim.monthKey(.now)
        guard TravelStore.trips(context, month: month).isEmpty, jobs.count >= 2 else { return }
        let cal = TravelClaim.calendar
        let today = cal.startOfDay(for: .now)
        let first = cal.dateInterval(of: .month, for: today)?.start ?? today
        let days = (0..<3).compactMap { cal.date(byAdding: .day, value: $0 * 2, to: first) }.filter { $0 <= today }
        for (i, day) in days.enumerated() {
            let t = Trip(date: day, ownerEmail: TravelStore.owner, person: TravelStore.person, vehicle: i == 1 ? .company : .personal,
                         plate: "1กข 1234", startPlace: TravelSettings.office, rate: TravelSettings.rate)
            let a = jobs[i % jobs.count], b = jobs[(i + 1) % jobs.count]
            func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day)! }
            t.stops = [TravelClaim.Stop(jobID: a.ensureSyncID(), label: TravelStore.label(a), arrivedAt: at(9, 10), departedAt: at(11, 40), legKm: 42.5),
                       TravelClaim.Stop(jobID: b.ensureSyncID(), label: TravelStore.label(b), arrivedAt: at(13, 20), departedAt: at(15, 5), legKm: 18.2)]
            t.backKm = i == 2 ? nil : 51.3
            context.insert(t)
        }
        let receipts: [(Int, TravelClaim.Category, Int, String)] = [
            (0, .fuel, 103_805, "PTT สาขาโคราช"), (0, .toll, 5_000, "การทางพิเศษ"), (1, .parking, 4_000, "ลานจอดรถ"),
            (2, .lodging, 85_000, "โรงแรมสบายดี"), (2, .fuel, 0, ""),
        ]
        for (i, (d, c, amount, vendor)) in receipts.enumerated() where d < days.count {
            let date = cal.date(bySettingHour: 10 + i, minute: 0, second: 0, of: days[d])!
            let e = Expense(date: date, ownerEmail: TravelStore.owner, person: TravelStore.person, category: c, amount: amount)
            e.vendor = vendor
            e.jobID = i == 1 ? jobs[0].syncID : nil
            e.receipt = ReceiptImage.stub(i)
            e.fillSource = amount > 0 ? "receipt" : "typed"
            context.insert(e)
        }
        try? context.save()
    }
}
#endif
