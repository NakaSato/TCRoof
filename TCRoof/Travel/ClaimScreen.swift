import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// `เดินทางและเบิกค่าใช้จ่าย` (docs/specs/calendar-travel-expenses-swift.md §B5): one month of the signed-in person's
/// travel. Today's stations with ถึง / ออก, the days with their route and km, the expenses with their receipts, what to
/// check, the totals, and the claim's export, submit and withdraw.
struct ClaimScreen: View {
    @Environment(\.modelContext) var context
    @Environment(GoogleSession.self) var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    // the queries keep the screen up to date; the lists below filter them to this person and month
    @Query(sort: \Trip.date) private var allTrips: [Trip]
    @Query(sort: \Expense.date) private var allExpenses: [Expense]
    @Query private var allClaims: [ClaimMonth]
    @Query(sort: \Job.installStart) private var jobs: [Job]

    @State var month: String
    @State private var editingTrip: Trip?
    @State private var editingExpense: Expense?
    @State var newExpense: NewExpense?
    @State private var showCamera = false
    @State private var showSettings = false
    @State private var showSubmit = false
    @State private var showWithdraw = false
    @State private var withdrawReason = ""
    @State var share: [URL]?
    @State var notice: String?
    @State var uploading = false
    @State var stamping: String?
    @State private var pickStop = false
    @State private var sync = CloudSync.shared

    struct NewExpense: Identifiable {
        let id = UUID()
        var receipt: Data?
        var date: Date
    }

    /// `month` ("2026-10") opens that month, as a claim decision's notification does; nil opens this month.
    init(month: String? = nil) { _month = State(initialValue: month ?? TravelClaim.monthKey(.now)) }

    private var me: String { TravelStore.owner }
    private var trips: [Trip] { allTrips.filter { $0.ownerEmail == me && $0.monthKey == month } }
    var expenses: [Expense] { allExpenses.filter { $0.ownerEmail == me && $0.monthKey == month } }
    private var claim: ClaimMonth? { allClaims.first { $0.ownerEmail == me && $0.month == month } }
    private var locked: Bool { claim?.isSubmitted ?? false }
    /// The manager's decision on this submission, if any (`ClaimReviews`).
    private var status: TravelClaim.Status { ClaimReviews.shared.status(month: month, submittedAt: claim?.submittedAt) }
    private var managesTeam: Bool { MemberRole.shared.permissions.role.managesTeam }
    private var summary: TravelClaim.Summary { TravelClaim.Summary(days: trips.map(\.day), items: expenses.map(\.item)) }
    private var isThisMonth: Bool { month == TravelClaim.monthKey(.now) }
    private var isLoadingTravel: Bool { sync.isLoading("trips") || sync.isLoading("expenses") || sync.isLoading("claims") }
    private var hasTravelData: Bool { !trips.isEmpty || !expenses.isEmpty || claim != nil }

    var body: some View {
        PadForm(maxWidth: 820) {
            if managesTeam { reviewLink }
            monthBar
            if isLoadingTravel && !hasTravelData {
                DataLoadingSkeleton(lines: 3)
                DataLoadingSkeleton(lines: 2)
            } else {
                if locked { submittedBanner }
                if isThisMonth, !locked { todayCard }
                warningsCard
                daysCard
                expensesCard
                totalsCard
                actionsCard
            }
        }
        .navigationTitle("เดินทางและเบิกค่าใช้จ่าย")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("ตั้งค่าการเบิก")
            }
        }
        .sheet(item: $editingTrip) { TripEditor(trip: $0) }
        .sheet(item: $editingExpense) { ExpenseEditor(expense: $0) }
        .sheet(item: $newExpense) { ExpenseEditor(expense: nil, receipt: $0.receipt, date: $0.date) }
        .sheet(isPresented: $showSettings) { TravelSettingsSheet() }
        .sheet(isPresented: $showSubmit) {
            ClaimSubmitSheet(total: summary.total, warnings: summary.warnings.count) { signature in submit(signature) }
        }
        .sheet(isPresented: $pickStop) {
            JobPickerSheet(title: "ถึงสถานีไหน") { job in Task { await stamp(.arrive, job) } }
        }
        .sheet(item: Binding(get: { share.map(SharedFiles.init) }, set: { share = $0?.urls })) {
            ActivitySheet(items: $0.urls).presentationDetents([.medium, .large])
        }
        .task { CloudSync.shared.loadTravelRecords() }
        .fullScreenCover(isPresented: $showCamera) {
            ReceiptCamera { pages in addScanned(pages) }
        }
        .alert("ถอนการยื่นเบิก", isPresented: $showWithdraw) {
            TextField("เหตุผล", text: $withdrawReason)
            Button("ถอนการยื่น", role: .destructive) {
                ClaimExport(month: month, context: context).withdraw(reason: withdrawReason)
                withdrawReason = ""
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: { Text("เดือนนี้จะแก้ได้อีกครั้ง ไฟล์ที่ส่งขึ้น Drive แล้วยังอยู่") }
        .tcToast($notice, duration: 3)
        .task(id: month) { await downloadReceipts() }
        #if DEBUG
        .task {
            if let m = UserDefaults.standard.string(forKey: "travelMonth") { month = m }
            if UserDefaults.standard.bool(forKey: "travelDemo") { TravelDemo.seed(context, jobs: jobs) }
            if UserDefaults.standard.bool(forKey: "travelSubmit") { try? await Task.sleep(for: .seconds(1)); showSubmit = true }
            // `-travelPDF YES` writes the month's claim to Documents/claim.pdf and claim.xlsx
            if UserDefaults.standard.bool(forKey: "travelPDF") {
                try? await Task.sleep(for: .seconds(2))
                let export = ClaimExport(month: month, context: context)
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try? export.pdf().write(to: docs.appendingPathComponent("claim.pdf"))
                try? export.excel().write(to: docs.appendingPathComponent("claim.xlsx"))
            }
        }
        #endif
    }

    private struct SharedFiles: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    // MARK: cards

    private var monthBar: some View {
        HStack(spacing: 12) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("เดือนก่อน")
            VStack(spacing: 2) {
                Text(TravelClaim.monthStart(month).map(RoutineReport.thaiMonth) ?? month)
                    .font(.sarabun(20, .bold, relativeTo: .title3)).foregroundStyle(Theme.navy)
                Text(status.title).font(.sarabun(13, relativeTo: .caption))
                    .foregroundStyle(statusInk)
            }
            .frame(maxWidth: .infinity)
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel("เดือนถัดไป")
                .disabled(isThisMonth)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.primary)
        .padding(.horizontal, 6)
        .tcCard()
    }

    private var statusInk: Color {
        switch status {
        case .open: Theme.muted
        case .submitted, .approved: Theme.successText
        case .returned: Theme.pending
        }
    }

    private var submittedBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch status {
            case .approved(let r):
                Label("อนุมัติแล้ว | \(r.who) | \(ClaimExport.stamp(Date(millis: r.reviewedAt)))", systemImage: "checkmark.seal.fill")
                    .font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.successText)
                if !r.note.isEmpty { Text(r.note).font(.sarabun(14, relativeTo: .subheadline)) }
            case .returned(let r):
                Label("ส่งกลับให้แก้ | \(r.who) | \(ClaimExport.stamp(Date(millis: r.reviewedAt)))", systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.pending)
                Text(r.note).font(.sarabun(14, relativeTo: .subheadline)).fixedSize(horizontal: false, vertical: true)
                Text("ถอนการยื่นเพื่อแก้ไข แล้วยื่นเบิกอีกครั้ง").font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted)
            default:
                Label("ยื่นเบิกแล้ว | รออนุมัติ | แก้ไม่ได้จนกว่าจะถอนการยื่น", systemImage: "lock.fill")
                    .font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.successText)
            }
            if let log = claim?.log, !log.isEmpty {
                Text(log).font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(status == .submitted || status.isApproved ? Theme.successSoft : Theme.pendingSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("claim.status")
    }

    /// Managers: the team's submitted months.
    private var reviewLink: some View {
        NavigationLink { ClaimReviewScreen() } label: {
            HStack {
                Label("ตรวจใบเบิกของทีม", systemImage: "checkmark.rectangle.stack")
                    .font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.chevron)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .tcCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("claim.reviewLink")
    }

    /// Today's appointments and install days, with ถึง / ออก, and the stops already stamped.
    private var todayCard: some View {
        let trip = trips.first { TravelClaim.calendar.isDateInToday($0.date) }
        let stops = trip?.stops ?? []
        let todayJobs = jobs.filter { $0.surveyDate.isToday || $0.installDay(on: .now) != nil }
        let listed = todayJobs + stops.compactMap { s in jobs.first { $0.syncID == s.jobID } }.filter { j in !todayJobs.contains { $0 === j } }
        return PadSection("วันนี้") {
            if listed.isEmpty {
                Text("วันนี้ไม่มีนัดสำรวจหรืองานติดตั้ง").foregroundStyle(Theme.muted)
            }
            ForEach(listed) { job in todayRow(job, stop: stops.last { $0.jobID == job.syncID }) }
            Button { pickStop = true } label: { Label("ถึงสถานีอื่น", systemImage: "mappin.and.ellipse") }
            if let trip {
                Button { editingTrip = trip } label: {
                    HStack {
                        Label("การเดินทางวันนี้", systemImage: "car")
                        Spacer()
                        Text(trip.day.km.map { String(format: "%.1f กม.", $0) } ?? "กำลังคำนวณระยะ").foregroundStyle(Theme.muted)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.chevron)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func todayRow(_ job: Job, stop: TravelClaim.Stop?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(TravelStore.label(job)).font(.sarabun(16, .bold, relativeTo: .body)).lineLimit(2)
                Text(stopLine(stop)).font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            let id = job.syncID ?? job.code
            if stamping == id {
                ProgressView()
            } else if stop?.isOpen == true {
                Button("ออกจากสถานี") { Task { await stamp(.depart, job) } }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
            } else {
                Button("ถึงสถานีแล้ว") { Task { await stamp(.arrive, job) } }
                    .buttonStyle(TCButtonStyle(.primary, size: .card))
            }
        }
    }

    private func stopLine(_ stop: TravelClaim.Stop?) -> String {
        guard let stop else { return "ยังไม่ได้บันทึกเวลา" }
        var parts = ["ถึง " + ClaimPagesTime.format(stop.arrivedAt)]
        if stop.departedAt != nil { parts.append("ออก " + ClaimPagesTime.format(stop.departedAt)) }
        if let s = stop.onSite { parts.append("อยู่ \(Int(s / 60)) นาที") }
        return parts.joined(separator: " | ")
    }

    @ViewBuilder private var warningsCard: some View {
        let warnings = summary.warnings
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("ตรวจก่อนยื่น \(warnings.count) รายการ", systemImage: "exclamationmark.triangle.fill")
                    .font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.warningText)
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                    Button { open(w) } label: {
                        HStack {
                            Text("• \(where_(w)) \(w.text)").font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private func where_(_ w: TravelClaim.Warning) -> String {
        switch w {
        case .noAmount(let id), .duplicate(let id):
            return expenses.first { $0.syncID == id }.map { "\(RoutineReport.thaiDate($0.date)) \($0.category.title):" } ?? ""
        case .noDistance(let id), .odometerReason(let id):
            return trips.first { $0.syncID == id }.map { "\(RoutineReport.thaiDate($0.date)):" } ?? ""
        }
    }

    private func open(_ w: TravelClaim.Warning) {
        switch w {
        case .noAmount(let id), .duplicate(let id): editingExpense = expenses.first { $0.syncID == id }
        case .noDistance(let id), .odometerReason(let id): editingTrip = trips.first { $0.syncID == id }
        }
    }

    private var daysCard: some View {
        PadSection("การเดินทาง \(trips.count) วัน") {
            if trips.isEmpty { Text("ยังไม่มีการเดินทางในเดือนนี้").foregroundStyle(Theme.muted) }
            ForEach(trips) { trip in
                Button { editingTrip = trip } label: { dayRow(trip.day) }.buttonStyle(.plain)
            }
        }
    }

    private func dayRow(_ d: TravelClaim.Day) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(RoutineReport.thaiDate(d.date)).font(.sarabun(16, .bold, relativeTo: .body))
                Text(d.stops.isEmpty ? "ยังไม่มีสถานี" : d.stops.map { $0.label.split(separator: " ").first.map(String.init) ?? $0.label }.joined(separator: " → "))
                    .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(d.km.map { String(format: "%.1f กม.", $0) } ?? "– กม.").font(.sarabun(15, .bold, relativeTo: .subheadline))
                Text(d.vehicle.paysMileage ? (d.mileage.map { TravelClaim.baht($0) + " บาท" } ?? "ยังไม่มีระยะ") : d.vehicle.title)
                    .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.chevron).padding(.top, 4)
        }
        .contentShape(Rectangle())
    }

    private var expensesCard: some View {
        PadSection {
            if expenses.isEmpty { Text("ยังไม่มีค่าใช้จ่ายในเดือนนี้").foregroundStyle(Theme.muted) }
            ForEach(TravelClaim.Category.receipts) { c in
                let list = expenses.filter { $0.category == c }
                if !list.isEmpty {
                    Text("\(c.title) | \(TravelClaim.baht(list.reduce(0) { $0 + $1.amount })) บาท")
                        .font(.sarabun(13, .bold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    ForEach(list) { e in
                        Button { editingExpense = e } label: { expenseRow(e) }.buttonStyle(.plain)
                    }
                }
            }
            if !locked {
                HStack(spacing: 10) {
                    Button { showCamera = true } label: { Label("ถ่ายใบเสร็จ", systemImage: "doc.viewfinder") }
                        .buttonStyle(TCButtonStyle(.primary, size: .card))
                        .accessibilityIdentifier("claim.scan")
                    Button { newExpense = NewExpense(date: defaultDate) } label: { Label("เพิ่มรายการ", systemImage: "plus") }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card))
                        .accessibilityIdentifier("claim.add")
                }
            }
        } footer: {
            Text("ใบเสร็จหลายใบถ่ายต่อกันได้ แอปอ่านยอด วันที่ และร้านให้ ตรวจแล้วกดบันทึก")
        }
    }

    var defaultDate: Date {
        isThisMonth ? .now : (TravelClaim.monthStart(month).flatMap { TravelClaim.calendar.date(byAdding: .hour, value: 12, to: $0) } ?? .now)
    }

    private func expenseRow(_ e: Expense) -> some View {
        let duplicate = TravelClaim.duplicates(expenses.map(\.item)).contains(e.syncID ?? "")
        return HStack(spacing: 12) {
            Group {
                if let data = e.receipt { Thumbnail(data: data) } else {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.track)
                        .overlay(Image(systemName: e.hasReceipt ? "icloud.and.arrow.down" : e.category.symbol).foregroundStyle(Theme.muted))
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.vendor.isEmpty ? e.category.title : e.vendor).font(.sarabun(15, .bold, relativeTo: .subheadline)).lineLimit(1)
                Text([RoutineReport.thaiDate(e.date), jobLabel(e.jobID)].compactMap { $0 }.joined(separator: " | "))
                    .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(e.amount > 0 ? TravelClaim.baht(e.amount) : "ไม่มียอด").font(.sarabun(15, .bold, relativeTo: .subheadline))
                    .foregroundStyle(e.amount > 0 ? Theme.navy : Theme.dangerText)
                if duplicate { Text("อาจซ้ำ").font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.warningText) }
            }
        }
        .contentShape(Rectangle())
    }

    private func jobLabel(_ id: String?) -> String? {
        guard let id else { return nil }
        return jobs.first { $0.syncID == id }?.code ?? "งานที่ลบแล้ว"
    }

    private var totalsCard: some View {
        let s = summary
        return PadSection("สรุปยอด") {
            ForEach(s.byCategory, id: \.category) { line in
                LabeledContent(line.category.title, value: TravelClaim.baht(line.amount))
            }
            if s.km > 0 { LabeledContent("ระยะทางรวม", value: String(format: "%.1f กม.", s.km)) }
            ForEach(s.byJob, id: \.jobID) { line in
                LabeledContent(line.jobID.flatMap { id in jobs.first { $0.syncID == id }.map(TravelStore.label) } ?? (line.jobID == nil ? "ไม่ระบุงาน" : "งานที่ลบแล้ว"),
                               value: TravelClaim.baht(line.amount))
                    .font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
            HStack {
                Text("รวมทั้งสิ้น").font(.sarabun(17, .bold, relativeTo: .headline))
                Spacer()
                Text(TravelClaim.baht(s.total) + " บาท").font(.sarabun(19, .bold, relativeTo: .title3)).foregroundStyle(Theme.primary)
                    .accessibilityIdentifier("claim.total")
            }
        }
    }

    private var actionsCard: some View {
        VStack(spacing: 10) {
            Button { exportFiles() } label: { Label("ส่งออกใบเบิก (PDF + Excel)", systemImage: "square.and.arrow.up") }
                .buttonStyle(TCButtonStyle(.secondary, fullWidth: true))
            if locked {
                if uploading {
                    ProgressView("กำลังส่งขึ้น Google Drive…")
                } else if claim?.pdfDriveID == nil {
                    Button { Task { await upload() } } label: { Label("ส่งขึ้น Google Drive อีกครั้ง", systemImage: "icloud.and.arrow.up") }
                        .buttonStyle(TCButtonStyle(.secondary, fullWidth: true))
                } else if let link = claim?.driveFolderURL, let url = URL(string: link) {
                    Link(destination: url) { Label("เปิดโฟลเดอร์ใบเบิกใน Drive", systemImage: "folder") }
                        .buttonStyle(TCButtonStyle(.text, fullWidth: true))
                }
                if status.isApproved {
                    Text("อนุมัติแล้ว จึงถอนการยื่นไม่ได้ | ถ้าต้องแก้ ให้ผู้จัดการส่งกลับก่อน")
                        .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                } else {
                    Button("ถอนการยื่น") { showWithdraw = true }.buttonStyle(TCButtonStyle(.destructive, fullWidth: true))
                }
            } else {
                Button { showSubmit = true } label: { Label("ยื่นเบิก", systemImage: "paperplane.fill") }
                    .buttonStyle(TCButtonStyle(.primary, fullWidth: true))
                    .disabled(trips.isEmpty && expenses.isEmpty)
            }
        }
    }
}
