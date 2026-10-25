import SwiftUI
import PDFKit
import TCRoofUI
import TCRoofCore

/// `ดู PDF`: page 1 of the R1 form as it prints, `แชร์`, `ปิด` and `บันทึก PDF`.
struct RequestPDFSheet: View {
    let job: Job
    let request: RoutineReport.WeeklyRequest
    let week: Int
    let demo: Bool
    let share: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var page: UIImage?
    @State private var pages = 0
    @State private var saved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("คำขอปฏิบัติงาน สัปดาห์ที่ \(week).pdf").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                    Text("A4 | \(max(pages, 1)) หน้า | " + status).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                ZStack {
                    Theme.paper
                    if let page { Image(uiImage: page).resizable().scaledToFit() } else { ProgressView() }
                }
                .aspectRatio(210.0 / 297.0, contentMode: .fit)
                .overlay(Rectangle().stroke(Theme.borderSubtle))
                .shadow(color: Theme.navySolid.opacity(0.12), radius: 6, y: 2)
                .accessibilityIdentifier("requestPDFPage")
                HStack(spacing: 10) {
                    Button { if let url = WeeklyRequestStore.pdfURL(job, request) { dismiss(); share(url) } } label: {
                        Label("แชร์", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                    Button {
                        if !demo { RoutineReportFiles.file(RoutineReportFiles.request(job, request), job: job, context: context); try? context.save() }
                        saved = true
                    } label: { Label(saved ? "บันทึกแล้ว" : "บันทึก PDF", systemImage: saved ? "checkmark" : "tray.and.arrow.down").frame(maxWidth: .infinity) }
                    .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
                }
            }
            .padding(20)
            .navigationTitle("ดู PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } } }
            .task { render() }
        }
        .presentationDetents([.large])
    }

    private var status: String {
        switch request.status {
        case .draft: "ร่าง"
        case .sent: "ส่งแล้ว"
        case .approved: "อนุมัติแล้ว"
        }
    }

    private func render() {
        guard let doc = PDFDocument(data: RoutineReportFiles.request(job, request).data), let first = doc.page(at: 0) else { return }
        pages = doc.pageCount
        page = first.thumbnail(of: CGSize(width: 1240, height: 1754), for: .mediaBox)
    }
}
