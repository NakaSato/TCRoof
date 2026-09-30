#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import TCRoofCore
import PDFReport
import DriveSync

/// Sidebar status: empty circle, partial ring with count, or a green check.
struct StatusMark: View {
    let completion: Completion
    var body: some View {
        let c = completion
        if c.total == 0 {
            EmptyView()
        } else if c.isComplete {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Paper.tick)
        } else if c.filled == 0 {
            Circle().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1.5).frame(width: 17, height: 17)
        } else {
            HStack(spacing: 5) {
                Text("\(c.filled)/\(c.total)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
                    Circle().trim(from: 0, to: c.fraction).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                .frame(width: 15, height: 15)
            }
        }
    }
}

/// Photos a job refers to that this device doesn't have, and why.
struct PhotoGap {
    let missing: Int
    /// Saved to Drive by the iPad that took them, so they can be downloaded here.
    let onDrive: Int
    @MainActor init(model: SurveyModel, job: Job) {
        missing = model.missingPhotos(job).count
        onDrive = model.downloadablePhotos(job).count
    }
    var message: String {
        var s = "มีรูป \(missing) รูปที่ยังไม่อยู่ในเครื่องนี้ รายงานจะไม่มีรูปเหล่านี้"
        if missing > onDrive { s += "\n\(missing - onDrive) รูปยังไม่ได้บันทึกขึ้น Google Drive — ให้เครื่องที่ถ่ายบันทึกรูปภาพลง Drive ก่อน" }
        return s
    }
}

struct BusyOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) { ProgressView().controlSize(.large); Text(text) }
                .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct PDFPreviewItem: Identifiable { let id = UUID(); let url: URL; let title: String }

struct PDFPreview: View {
    let item: PDFPreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false
    var body: some View {
        NavigationStack {
            PDFKitView(url: item.url)
                .navigationTitle("รายงาน " + item.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button { sharing = true } label: { Label("แชร์", systemImage: "square.and.arrow.up") } }
                }
                .sheet(isPresented: $sharing) { ShareSheet(items: [item.url]) }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .secondarySystemBackground
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}
#endif
