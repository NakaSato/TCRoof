import SwiftUI
import SwiftData
import PDFKit
import TCRoofUI
import TCRoofCore

/// รายงานประจำสัปดาห์ R3 / รายงานประจำเดือน R4 (§4.4–4.5): read-only, built from the daily reports and the MP plan;
/// the page shown is the PDF itself, so what is checked on screen is what gets sent.
struct RoutineSummaryScreen: View {
    enum Period { case week, month }

    @Bindable var job: Job
    let period: Period
    @Environment(\.modelContext) private var context
    @State private var anchor: Date
    @State private var pdf: Data?
    @State private var share: ReportShare?
    @State private var filed = false

    init(job: Job, period: Period, anchor: Date = .now) {
        self.job = job; self.period = period
        _anchor = State(initialValue: anchor)
    }

    private var built: RoutineReportFiles.Built {
        period == .week ? RoutineReportFiles.weekly(job, week: anchor) : RoutineReportFiles.monthly(job, month: anchor)
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
                Text(label).font(.headline).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: touchMin, height: touchMin) }
                    .accessibilityLabel(period == .week ? "สัปดาห์ถัดไป" : "เดือนถัดไป")
                Spacer()
                Button(period == .week ? "สัปดาห์นี้" : "เดือนนี้") { anchor = .now }.font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(.bar)
            if let pdf {
                PDFPreview(data: pdf)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .sheet(item: $share) { ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large]) }
        .task(id: anchor) { pdf = built.data; filed = false }
    }

    private func shift(_ n: Int) {
        let cal = RoutineReport.calendar
        anchor = period == .week ? cal.date(byAdding: .day, value: 7 * n, to: anchor)! : cal.date(byAdding: .month, value: n, to: anchor)!
    }

    private func fileIt() {
        RoutineReportFiles.file(built, job: job, context: context)
        try? context.save()
        filed = true
    }

    private func exportPDF() {
        if let url = try? RoutineReportFiles.temporaryURL(built, data: pdf) { share = ReportShare(url: url) }
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
