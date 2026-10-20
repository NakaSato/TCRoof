import SwiftUI
import SwiftData
import FirebaseFirestore
import TCRoofUI
import TCRoofCore

/// `ตรวจใบเบิกของทีม` (docs/specs/calendar-travel-expenses-swift.md §B5): for managers, every submitted month with its
/// decision, and each one's days, expenses, totals and receipts, approved or sent back with a note. The records are read
/// from Firestore while the screen is open and not kept on this device (`ClaimReviewModel`).
struct ClaimReviewScreen: View {
    @State private var model = ClaimReviewModel()
    @State private var filter = Filter.waiting

    enum Filter: String, CaseIterable, Identifiable {
        case waiting = "รออนุมัติ", returned = "ส่งกลับ", approved = "อนุมัติแล้ว"
        var id: String { rawValue }
    }

    private var shown: [ClaimReviewModel.Entry] {
        model.entries.filter { e in
            switch (filter, e.status) {
            case (.waiting, .submitted), (.returned, .returned), (.approved, .approved): true
            default: false
            }
        }
    }

    var body: some View {
        PadForm(maxWidth: 820) {
            Picker("สถานะ", selection: $filter) {
                ForEach(Filter.allCases) { f in Text(f.rawValue + count(f)).tag(f) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("review.filter")
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.dangerText).font(.sarabun(14, relativeTo: .subheadline))
            }
            PadSection(filter.rawValue) {
                if model.loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                } else if shown.isEmpty {
                    Text(filter == .waiting ? "ไม่มีใบเบิกรออนุมัติ" : "ไม่มีรายการ").foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                ForEach(shown) { e in
                    NavigationLink { ClaimReviewDetail(model: model, entryID: e.id) } label: { row(e) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("ตรวจใบเบิกของทีม")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        #if DEBUG
        .task { if let f = UserDefaults.standard.string(forKey: "claimReviewFilter").flatMap(Filter.init(rawValue:)) { filter = f } }
        #endif
    }

    private func count(_ f: Filter) -> String {
        let n = model.entries.filter { e in
            switch (f, e.status) { case (.waiting, .submitted), (.returned, .returned), (.approved, .approved): true; default: false }
        }.count
        return n > 0 ? " \(n)" : ""
    }

    private func row(_ e: ClaimReviewModel.Entry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.person + (Permissions.normalized(e.owner) == Permissions.normalized(MemberRole.shared.permissions.email) ? " (ของฉัน)" : ""))
                    .font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Text((TravelClaim.monthStart(e.month).map(RoutineReport.thaiMonth) ?? e.month)
                     + (e.submittedAt.map { " | ยื่น " + ClaimExport.stamp($0) } ?? ""))
                    .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted)
                if case .returned(let r) = e.status {
                    Text(r.note).font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.pending).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let t = e.total { Text(TravelClaim.baht(t) + " บาท").font(.sarabun(15, .bold, relativeTo: .subheadline)).monospacedDigit() }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.chevron)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One person's submitted month, with the decision.
struct ClaimReviewDetail: View {
    @Environment(GoogleSession.self) private var session
    @Query(sort: \Job.installStart) private var jobs: [Job]
    let model: ClaimReviewModel
    let entryID: String

    @State private var month: ClaimReviewModel.Month?
    @State private var asking: TravelClaim.Decision?
    @State private var note = ""
    @State private var saving = false
    @State private var notice: String?
    @State private var receipt: ReceiptImage?

    struct ReceiptImage: Identifiable { let id = UUID(); let image: UIImage }

    private var entry: ClaimReviewModel.Entry? { model.entries.first { $0.id == entryID } }
    private var me: String { MemberRole.shared.permissions.email }

    var body: some View {
        PadForm(maxWidth: 820) {
            if let e = entry {
                header(e)
                if let m = month {
                    totals(m.summary)
                    if !m.summary.warnings.isEmpty { warnings(m.summary) }
                    days(m.summary)
                    expenses(m)
                    if let link = e.driveFolderURL, let url = URL(string: link) {
                        Link(destination: url) { Label("เปิดโฟลเดอร์ใบเบิกใน Drive", systemImage: "folder") }
                            .buttonStyle(TCButtonStyle(.text, fullWidth: true))
                    }
                    actions(e, m)
                } else {
                    ProgressView("กำลังโหลด…").frame(maxWidth: .infinity, minHeight: 80)
                }
            } else {
                Text("ใบเบิกนี้ไม่อยู่แล้ว").foregroundStyle(Theme.muted)
            }
        }
        .navigationTitle(entry?.person ?? "ใบเบิก")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entryID) {
            guard let e = entry else { return }
            month = await model.load(e)
        }
        .alert(asking == .returned ? "ส่งกลับให้แก้" : "อนุมัติใบเบิก", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
            TextField(asking == .returned ? "เหตุผลที่ส่งกลับ (ต้องใส่)" : "หมายเหตุ (ไม่ต้องใส่ก็ได้)", text: $note)
            Button(asking == .returned ? "ส่งกลับ" : "อนุมัติ") { if let d = asking { decide(d) } }
            Button("ยกเลิก", role: .cancel) { note = "" }
        } message: {
            Text(asking == .returned ? "ผู้เบิกจะเห็นเหตุผลนี้ แล้วถอนการยื่นเพื่อแก้" : month.map { "ยอดรวม \(TravelClaim.baht($0.summary.total)) บาท" } ?? "")
        }
        .sheet(item: $receipt) { r in
            NavigationStack {
                ScrollView { Image(uiImage: r.image).resizable().scaledToFit().padding(12) }
                    .navigationTitle("ใบเสร็จ").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { receipt = nil } } }
            }
        }
        .tcToast($notice, duration: 3)
    }

    // MARK: cards

    private func header(_ e: ClaimReviewModel.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TravelClaim.monthStart(e.month).map(RoutineReport.thaiMonth) ?? e.month)
                .font(.sarabun(20, .bold, relativeTo: .title3)).foregroundStyle(Theme.navy)
            Text(e.owner).font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted)
            Text(e.status.title).font(.sarabun(15, .bold, relativeTo: .subheadline))
                .foregroundStyle(e.status == .submitted || e.status.isApproved ? Theme.successText : Theme.pending)
            if case .approved(let r) = e.status { decisionLine(r) }
            if case .returned(let r) = e.status { decisionLine(r) }
            if !e.log.isEmpty { Text(e.log).font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .tcCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review.header")
    }

    private func decisionLine(_ r: TravelClaim.Review) -> some View {
        Text("\(r.who) | \(ClaimExport.stamp(Date(millis: r.reviewedAt)))" + (r.note.isEmpty ? "" : " | \(r.note)"))
            .font(.sarabun(14, relativeTo: .subheadline)).fixedSize(horizontal: false, vertical: true)
    }

    private func totals(_ s: TravelClaim.Summary) -> some View {
        PadSection("สรุปยอด") {
            ForEach(s.byCategory, id: \.category) { line in LabeledContent(line.category.title, value: TravelClaim.baht(line.amount)) }
            if s.km > 0 { LabeledContent("ระยะทางรวม", value: String(format: "%.1f กม.", s.km)) }
            HStack {
                Text("รวมทั้งสิ้น").font(.sarabun(17, .bold, relativeTo: .headline))
                Spacer()
                Text(TravelClaim.baht(s.total) + " บาท").font(.sarabun(19, .bold, relativeTo: .title3)).foregroundStyle(Theme.primary)
                    .accessibilityIdentifier("review.total")
            }
        }
    }

    private func warnings(_ s: TravelClaim.Summary) -> some View {
        PadSection("ควรตรวจ \(s.warnings.count) รายการ") {
            ForEach(Array(s.warnings.enumerated()), id: \.offset) { _, w in
                Label(w.text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.pending)
                    .font(.sarabun(14, relativeTo: .subheadline))
            }
        }
    }

    private func days(_ s: TravelClaim.Summary) -> some View {
        PadSection("การเดินทาง \(s.days.count) วัน") {
            if s.days.isEmpty { Text("ไม่มีการเดินทาง").foregroundStyle(Theme.muted) }
            ForEach(s.days) { d in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(RoutineReport.thaiDate(d.date)).font(.sarabun(15, .bold, relativeTo: .subheadline))
                        Spacer()
                        Text(d.km.map { String(format: "%.1f กม.", $0) } ?? "ยังไม่มีระยะ").monospacedDigit()
                        if let m = d.mileage, m > 0 { Text(TravelClaim.baht(m)).monospacedDigit().foregroundStyle(Theme.primary) }
                    }
                    Text(([d.startPlace] + d.stops.map(\.label)).filter { !$0.isEmpty }.joined(separator: " → ") + " | " + d.vehicle.title)
                        .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    if d.odometerDiffers, !d.odoReason.isEmpty {
                        Text("เลขไมล์ต่างจากระยะทาง: " + d.odoReason).font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.pending)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func expenses(_ m: ClaimReviewModel.Month) -> some View {
        PadSection("ค่าใช้จ่าย \(m.summary.items.count) รายการ") {
            if m.summary.items.isEmpty { Text("ไม่มีค่าใช้จ่าย").foregroundStyle(Theme.muted) }
            ForEach(m.summary.items) { i in
                Button { Task { await open(m.receipts[i.id]) } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: i.hasReceipt ? "doc.text.image" : "doc.badge.ellipsis")
                            .foregroundStyle(i.hasReceipt ? Theme.primary : Theme.muted).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.category.title + (i.vendor.isEmpty ? "" : " | \(i.vendor)")).font(.sarabun(15, relativeTo: .subheadline))
                            Text(RoutineReport.thaiDate(i.date) + (jobLabel(i.jobID).map { " | \($0)" } ?? "") + (i.hasReceipt ? "" : " | ไม่มีใบเสร็จ"))
                                .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(TravelClaim.baht(i.amount)).font(.sarabun(15, .bold, relativeTo: .subheadline)).monospacedDigit()
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(m.receipts[i.id] == nil)
            }
        }
    }

    @ViewBuilder private func actions(_ e: ClaimReviewModel.Entry, _ m: ClaimReviewModel.Month) -> some View {
        if Permissions.normalized(e.owner) == Permissions.normalized(me) {
            Text("อนุมัติใบเบิกของตัวเองไม่ได้ | ให้ผู้จัดการคนอื่นตรวจ").font(.sarabun(14, relativeTo: .subheadline))
                .foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
        } else if e.submittedAt != nil {
            VStack(spacing: 10) {
                if saving { ProgressView() }
                if !e.status.isApproved {
                    Button { note = ""; asking = .approved } label: { Label("อนุมัติ", systemImage: "checkmark.seal.fill") }
                        .buttonStyle(TCButtonStyle(.primary, fullWidth: true))
                        .accessibilityIdentifier("review.approve")
                }
                Button { note = ""; asking = .returned } label: { Label("ส่งกลับให้แก้", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(TCButtonStyle(.secondary, fullWidth: true))
                    .accessibilityIdentifier("review.return")
            }
            .disabled(saving)
        }
    }

    private func jobLabel(_ id: String?) -> String? {
        guard let id else { return nil }
        return jobs.first { $0.syncID == id }?.code
    }

    // MARK: actions

    private func decide(_ d: TravelClaim.Decision) {
        asking = nil
        guard let e = entry, let m = month else { return }
        if let why = TravelClaim.reviewRefusal(reviewer: me, owner: e.owner, submitted: e.submittedAt != nil, decision: d, note: note) {
            notice = why; return
        }
        let name = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespaces) ?? ""
        let review = TravelClaim.Review(ownerEmail: Permissions.normalized(e.owner), month: e.month, submittedAt: e.submittedAt!.millis, decision: d,
                                        note: note.trimmingCharacters(in: .whitespacesAndNewlines), total: m.summary.total,
                                        reviewedBy: Permissions.normalized(me), reviewerName: name, reviewedAt: Date.now.millis)
        note = ""
        saving = true
        Task {
            do {
                try await model.decide(review)
                notice = d == .approved ? "อนุมัติแล้ว" : "ส่งกลับให้ผู้เบิกแก้แล้ว"
            } catch {
                notice = "บันทึกไม่สำเร็จ: \(error.localizedDescription)"
            }
            saving = false
        }
    }

    /// A receipt from the claimant's Drive (readable once their month's folder is shared with this account).
    private func open(_ driveID: String?) async {
        guard let driveID else { return }
        if let image = model.demoReceipt(driveID) { receipt = ReceiptImage(image: image); return }
        guard session.survey.google.isSignedIn else { notice = "เข้าสู่ระบบ Google ก่อนจึงเปิดใบเสร็จได้"; return }
        do {
            let data = try await session.survey.driveDownload(driveID)
            if let image = UIImage(data: data) { receipt = ReceiptImage(image: image) } else { notice = "เปิดใบเสร็จไม่ได้" }
        } catch {
            notice = "เปิดใบเสร็จไม่ได้ (โฟลเดอร์อาจยังไม่ได้แชร์ให้บัญชีนี้)"
        }
    }
}

/// Every claim and decision while the review screen is open, and one month's trips and expenses on demand.
@MainActor
@Observable
final class ClaimReviewModel {
    struct Entry: Identifiable {
        var owner, month, person, log: String
        var submittedAt: Date?
        var driveFolderURL: String?
        var review: TravelClaim.Review?
        var id: String { TravelClaim.Review.id(owner: owner, month: month) }
        var status: TravelClaim.Status { TravelClaim.status(submittedAt: submittedAt?.millis, review: review) }
        /// Known once the month was opened, or from the decision.
        var total: Int?
    }
    struct Month {
        var summary: TravelClaim.Summary
        /// Expense id → its receipt's Drive id.
        var receipts: [String: String]
    }

    private(set) var entries: [Entry] = []
    private(set) var loading = true
    private(set) var error: String?
    private var claims: [String: ClaimMonth.Record] = [:]
    private var reviews: [String: TravelClaim.Review] = [:]
    private var totals: [String: Int] = [:]
    private var listeners: [ListenerRegistration] = []
    private var demo: ClaimReviewDemo?

    func start() {
        guard listeners.isEmpty, demo == nil else { return }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "claimReviewDemo") {
            demo = ClaimReviewDemo()
            claims = demo!.claims; reviews = demo!.reviews; loading = false; rebuild(); return
        }
        #endif
        let db = Firestore.firestore()
        listeners.append(db.collection(ClaimMonth.collection).addSnapshotListener { [weak self] snap, err in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let err { self.error = "อ่านใบเบิกไม่ได้: \(err.localizedDescription)"; self.loading = false; return }
                self.claims = Dictionary((snap?.documents ?? []).compactMap { d in
                    (try? d.data(as: ClaimMonth.Record.self)).map { (TravelClaim.Review.id(owner: $0.ownerEmail, month: $0.month), $0) }
                }, uniquingKeysWith: { a, b in (a.submittedAt ?? 0) >= (b.submittedAt ?? 0) ? a : b })
                self.loading = false
                self.rebuild()
            }
        })
        listeners.append(db.collection(ClaimReviews.collection).addSnapshotListener { [weak self] snap, err in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let err { return print("ClaimReview: claimReviews: \(err.localizedDescription)") }
                self.reviews = Dictionary((snap?.documents ?? []).compactMap { d in
                    (try? d.data(as: TravelClaim.Review.self)).map { ($0.id, $0) }
                }, uniquingKeysWith: { a, _ in a })
                self.rebuild()
            }
        })
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
    }

    /// Submitted months, and the ones decided on (a withdrawn one stays only while its decision is shown), newest first.
    private func rebuild() {
        let people = Dictionary(TeamDirectory.shared.people.map { (Permissions.normalized($0.email), $0.label) }, uniquingKeysWith: { a, _ in a })
        entries = claims.values.filter { $0.submittedAt != nil }.map { c in
            let id = TravelClaim.Review.id(owner: c.ownerEmail, month: c.month)
            return Entry(owner: c.ownerEmail, month: c.month, person: people[Permissions.normalized(c.ownerEmail)] ?? (demo != nil ? ClaimReviewDemo.name(c.ownerEmail) : nil) ?? c.ownerEmail, log: c.log,
                         submittedAt: c.submittedAt.map(Date.init(millis:)), driveFolderURL: c.driveFolderURL, review: reviews[id],
                         total: totals[id] ?? reviews[id]?.total)
        }
        .sorted { ($0.submittedAt ?? .distantPast) > ($1.submittedAt ?? .distantPast) }
    }

    /// The month's trips and expenses, read from Firestore (managers read everyone's).
    func load(_ e: Entry) async -> Month {
        if let demo { let m = demo.month(e.owner); totals[e.id] = m.summary.total; rebuild(); return m }
        let db = Firestore.firestore()
        let owner = e.owner
        async let t = try? db.collection(Trip.collection).whereField("ownerEmail", isEqualTo: owner).getDocuments()
        async let x = try? db.collection(Expense.collection).whereField("ownerEmail", isEqualTo: owner).getDocuments()
        let trips = (await t)?.documents.compactMap { try? $0.data(as: Trip.Record.self) } ?? []
        let expenses = (await x)?.documents.compactMap { d in (try? d.data(as: Expense.Record.self)).map { (d.documentID, $0) } } ?? []
        let days: [TravelClaim.Day] = trips.filter { TravelClaim.monthKey(Date(millis: $0.date)) == e.month }.enumerated().map { i, r in
            let stops = (try? JSONDecoder().decode([TravelClaim.Stop].self, from: Data(r.stops.utf8))) ?? []
            return TravelClaim.Day(id: "d\(i)", date: Date(millis: r.date), vehicle: TravelClaim.Vehicle(rawValue: r.vehicle) ?? .company,
                                   plate: r.plate, startPlace: r.startPlace, stops: stops, backKm: r.backKm, rate: r.rate,
                                   odoStart: r.odoStart, odoEnd: r.odoEnd, odoReason: r.odoReason,
                                   hasOdoPhotos: r.odoStartDrive != nil || r.odoEndDrive != nil)
        }
        var receipts: [String: String] = [:]
        let items: [TravelClaim.Item] = expenses.filter { TravelClaim.monthKey(Date(millis: $0.1.date)) == e.month }.map { id, r in
            if let d = r.receiptDrive { receipts[id] = d }
            return TravelClaim.Item(id: id, date: Date(millis: r.date), category: TravelClaim.Category(rawValue: r.category) ?? .other,
                                    amount: r.amount, vendor: r.vendor, taxID: r.taxID, note: r.note, jobID: r.jobID,
                                    hasReceipt: r.receiptDrive != nil, fromReceipt: r.fillSource == "receipt")
        }
        let m = Month(summary: TravelClaim.Summary(days: days, items: items), receipts: receipts)
        totals[e.id] = m.summary.total
        rebuild()
        return m
    }

    func decide(_ r: TravelClaim.Review) async throws {
        if demo != nil { reviews[r.id] = r; rebuild(); return }
        try await ClaimReviews.decide(r)
    }

    func demoReceipt(_ id: String) -> UIImage? { demo?.receipt(id) }
}
