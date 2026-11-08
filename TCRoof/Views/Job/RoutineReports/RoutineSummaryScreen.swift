import SwiftUI
import SwiftData
import PDFKit
import TCRoofUI
import TCRoofCore

/// รายงานประจำสัปดาห์ R3 / รายงานประจำเดือน R4 (§4.4–4.5): read-only, built from the daily reports and the MP plan;
/// the page shown is the PDF itself, so what is checked on screen is what gets sent. R3 also exports as PowerPoint.
struct RoutineSummaryScreen: View {
    enum Period { case week, month }

    @Bindable var job: Job
    let period: Period
    @Environment(\.modelContext) private var context
    @Environment(\.permissions) private var permissions
    @State private var anchor: Date
    /// The period's PDF, built once per period (and after an acknowledgement); filing and sharing reuse it.
    @State private var made: RoutineReportFiles.Ready?
    private var pdf: Data? { made?.data }
    @State private var share: ReportShare?
    @State private var filed = false
    @State private var slidesError: String?
    @State private var ackingAll = false

    init(job: Job, period: Period, anchor: Date = .now) {
        self.job = job; self.period = period
        _anchor = State(initialValue: anchor)
    }

    private var built: RoutineReportFiles.Built {
        period == .week ? RoutineReportFiles.weekly(job, week: anchor) : RoutineReportFiles.monthly(job, month: anchor)
    }

    /// The job's records are read here, on the main thread; the PDF is drawn off it (`Built.rendered`).
    private func make() async -> RoutineReportFiles.Ready {
        let b = built
        return RoutineReportFiles.Ready(name: b.name, folder: b.folder, data: await b.rendered())
    }

    /// Builds the period's PDF again; one finishing after the period changed (or the screen left) is dropped.
    private func remake() async {
        let ready = await make()
        guard !Task.isCancelled else { return }
        made = ready
        filed = false
    }

    private var pendingInPeriod: [InstallLog] {
        let cal = RoutineReport.calendar
        switch period {
        case .week:
            let range = RoutineReport.week(of: anchor)
            return job.pendingAckLogs.filter { range.contains(cal.startOfDay(for: $0.date)) }
        case .month:
            return job.pendingAckLogs.filter { cal.isDate($0.date, equalTo: anchor, toGranularity: .month) }
        }
    }

    private var label: String {
        switch period {
        case .week:
            let r = RoutineReport.week(of: anchor)
            return "\(RoutineReport.thaiDate(r.lowerBound)) – \(RoutineReport.thaiDate(r.upperBound))"
        case .month: return RoutineReport.thaiMonth(anchor)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: touchMin, height: touchMin) }
                    .accessibilityLabel(period == .week ? "สัปดาห์ก่อน" : "เดือนก่อน")
                Text(label).font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: touchMin, height: touchMin) }
                    .accessibilityLabel(period == .week ? "สัปดาห์ถัดไป" : "เดือนถัดไป")
                Spacer()
                Button(period == .week ? "สัปดาห์นี้" : "เดือนนี้") { anchor = .now }.font(.sarabun(15, .semibold, relativeTo: .subheadline))
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Theme.surface)
            let pending = pendingInPeriod
            if !pending.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.pending)
                    Text("มีรายงานประจำวันรอรับทราบ \(pending.count) วัน — ความคืบหน้าจะยังไม่ถูกนับเข้าแผนหลักจนกว่าจะรับทราบ")
                        .font(.sarabun(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.navy)
                    Spacer()
                    if permissions.can(.dailySign, on: job.access) {
                        Button("รับทราบทั้งหมด (\(pending.count) วัน)") { ackingAll = true }
                            .font(.sarabun(14, .bold, relativeTo: .subheadline))
                            .foregroundStyle(Theme.onPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.pending, in: Capsule())
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.warningSoft)
            }
            if let pdf {
                PDFPreview(data: pdf)
            } else {
                pageSkeleton
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .navigationTitle(period == .week ? "รายงานประจำสัปดาห์" : "รายงานประจำเดือน")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: fileIt) { Label(filed ? "เก็บแล้ว" : "เก็บในเอกสาร", systemImage: filed ? "checkmark" : "tray.and.arrow.down") }
                    .disabled(pdf == nil || filed)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: exportPDF) { Label("PDF", systemImage: "square.and.arrow.up") }.disabled(pdf == nil)
            }
            if period == .week {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: exportSlides) { Label("PowerPoint", systemImage: "rectangle.on.rectangle") }
                        .accessibilityIdentifier("weeklySlides")
                }
            }
        }
        .tcPadNavBar(period == .week ? "รายงานประจำสัปดาห์" : "รายงานประจำเดือน", trail: ["หน้าหลัก", job.code]) {
            HStack(spacing: 12) {
                TCButton(filed ? "เก็บแล้ว" : "เก็บในเอกสาร", systemImage: filed ? "checkmark" : "tray.and.arrow.down", kind: .secondary, action: fileIt)
                    .disabled(pdf == nil || filed)
                TCButton("PDF", systemImage: "square.and.arrow.up", kind: .secondary, action: exportPDF).disabled(pdf == nil)
                if period == .week {
                    TCButton("PowerPoint", systemImage: "rectangle.on.rectangle", kind: .secondary, action: exportSlides)
                }
            }
        }
        .alert("สร้าง PowerPoint ไม่สำเร็จ", isPresented: Binding(get: { slidesError != nil }, set: { if !$0 { slidesError = nil } })) {
            Button("ตกลง", role: .cancel) {}
        } message: { Text(slidesError ?? "") }
        .sheet(item: $share) { ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $ackingAll) {
            let pending = pendingInPeriod
            InspectorAckSheet(title: "รับทราบทั้งหมด (\(pending.count) วัน)", name: job.routineSettings.inspector, date: .now, signs: true) { name, when, drawn in
                job.recordInspectorAckAll(pending, name: name, at: when, signature: drawn, context: context)
                // the acknowledgements change the pages: drawn again, the old one gone meanwhile
                made = nil
                Task { await remake() }
            }
        }
        // another period clears the page at once, so the previous one's PDF is never filed or shared as this one
        .task(id: anchor) { made = nil; await remake() }
    }

    /// The page being drawn, in its shape: an A4 sheet with a heading, lines and a picture.
    private var pageSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            TCSkeletonBlock(width: 180, height: 16)
            TCSkeletonBlock()
            TCSkeletonBlock()
            TCSkeletonBlock(height: 140, radius: 6)
            TCSkeletonBlock()
            TCSkeletonBlock(width: 220)
            Spacer(minLength: 0)
        }
        .padding(24)
        .aspectRatio(210.0 / 297.0, contentMode: .fit)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(maxWidth: 640)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tcShimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("กำลังสร้างรายงาน")
    }

    private func shift(_ n: Int) {
        let cal = RoutineReport.calendar
        anchor = (period == .week ? cal.date(byAdding: .day, value: 7 * n, to: anchor) : cal.date(byAdding: .month, value: n, to: anchor)) ?? anchor
    }

    private func fileIt() {
        guard let made else { return }
        RoutineReportFiles.file(made, job: job, context: context)
        try? context.save()
        filed = true
    }

    private func exportPDF() {
        guard let made else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(made.name)
        if (try? made.data.write(to: url, options: .atomic)) != nil { share = ReportShare(url: url) }
    }

    /// The week as PowerPoint for the meeting (`WeeklySlides`): the same content as the PDF, every text editable.
    private func exportSlides() {
        do { share = ReportShare(url: try RoutineReportFiles.weeklySlides(job, week: anchor)) }
        catch { slidesError = error.localizedDescription }
    }
}

struct PDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .secondarySystemBackground
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        guard context.coordinator.shown != data else { return }
        context.coordinator.shown = data
        v.document = PDFDocument(data: data)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var shown: Data? }
}
