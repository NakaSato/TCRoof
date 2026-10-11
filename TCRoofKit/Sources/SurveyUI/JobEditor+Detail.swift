#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import TCRoofCore
import PDFReport
import DriveSync
import TCRoofUI

/// The form for the selected page.
extension JobEditorView {
    @ViewBuilder var detail: some View {
        switch page {
        case .summary: summaryPage
        case .info: groupPage(Schema.info, code: "A1", title: "ข้อมูลโครงการ", subtitle: "ข้อมูลหัวกระดาษของทุกแผ่นงาน (เลขที่ วันที่ ผู้ประสานงาน ที่อยู่)")
        case .site: groupPage(Schema.site, code: "A2", title: "ภาพสถานที่ติดตั้ง", subtitle: "แผ่น ระบบไฟฟ้า — ภาพสถานที่ติดตั้ง และ LIST")
        case .electrical: groupPage(Schema.electrical, code: "A3", title: "มิเตอร์ หม้อแปลง และตู้ MDB", subtitle: "แผ่น ระบบไฟฟ้า — ผังมิเตอร์ หม้อแปลง และตู้ MDB")
        case .flood: groupPage(Schema.flood, code: "A4", title: "ประวัติน้ำท่วม", subtitle: "ใช้กำหนดความสูงติดตั้งอินเวอร์เตอร์ ตู้ SMDB/กันย้อน และแนวรางสายไฟ · แสดงในรายงาน PDF")
        case .final: groupPage(Schema.final, code: "E1", title: "สรุปผลและลงนาม", subtitle: "หน้าสุดท้ายของรายงาน PDF")
        case .photos, .revisions: EmptyView()
        case .module(let id):
            if let i = job.modules.firstIndex(where: { $0.id == id }) { modulePage(i) }
            else { TCEmptyState("เลือกหัวข้อทางซ้าย", systemImage: "sidebar.left") }
        }
    }

    var summaryPage: some View {
        let layout = ReportLayout(job: job, header: model.reportHeader, measure: PDFRenderer.Measure())
        let sheet = Sketch(width: ReportLayout.pageW, height: ReportLayout.pageH, ops: layout.summaryPage().ops)
        let jobID = job.id
        return VStack(spacing: 14) {
            Canvas { ctx, size in
                let k = size.width / CGFloat(sheet.width)
                ctx.withCGContext { cg in
                    cg.scaleBy(x: k, y: k)
                    PDFRenderer.draw(sheet.ops, in: cg, photo: { model.image($0, in: jobID) })
                }
            }
            .aspectRatio(CGFloat(sheet.width / sheet.height), contentMode: .fit)
            .background(Theme.paper)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            Button { checked { run("กำลังสร้าง PDF สรุป…") { let f = try model.exportSummaryPDF(job); preview = PDFPreviewItem(url: f.url, title: "สรุป " + job.projectName) } } } label: {
                Label("บันทึก PDF สรุป 1 หน้า", systemImage: "doc.richtext")
            }
            .buttonStyle(TCButtonStyle(.primary, size: .card)).controlSize(.large)
        }
    }

    func groupPage(_ g: GroupSpec, code: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(code + " " + title, subtitle: subtitle, completion: g.completion(job.values))
            PaperBox(title: g.title ?? "") {
                ForEach(g.fields) { f in
                    if f.isVisible(job.values) && !f.id.hasPrefix("tr") || f.id == "trafos" { FieldView(spec: f, values: $job.values, jobID: job.id, gps: job.values.text("gps")) }
                }
            }
            if page == .flood, let h = Schema.recommendedEquipHeight(job.values) {
                Label("แนะนำติดตั้งอุปกรณ์สูงจากพื้นดินอย่างน้อย \(h) ซม. (\(Schema.flooded(job.values) ? "ระดับน้ำสูงสุด" : "ระดับน้ำประเมิน GISTDA") + 50 ซม.)", systemImage: "arrow.up.to.line")
                    .font(.sarabun(15, relativeTo: .callout)).foregroundStyle(Theme.primary)
            }
            if page == .electrical, job.values.transformers("trafos").isEmpty == false || !job.values.text("meterNo").isEmpty {
                Text("ค่าที่กรอกจะลงในผัง SmartArt ของแผ่น ระบบไฟฟ้า").font(.sarabun(TypeScale.caption, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
            }
            if page == .electrical {
                Button { showSLD = true } label: { Label("สร้าง Single Line Diagram", systemImage: "bolt.horizontal").frame(minHeight: 44) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
            }
            nextButton
        }
    }

    func modulePage(_ i: Int) -> some View {
        let m = job.modules[i], spec = m.spec
        let number = job.sectionsByCategory.flatMap(\.sections).first { $0.id == m.id }?.number ?? spec.code
        return VStack(alignment: .leading, spacing: 16) {
            header(number + " " + spec.label, subtitle: "ไฟล์ Excel แผ่น \(spec.sheet) · ในรายงาน: \(spec.reportTitle)", completion: m.completion)
            HStack {
                Text("ชื่อ/อาคาร").font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.inkStrong)
                TextField(spec.namePlaceholder, text: $job.modules[i].name).textFieldStyle(OutlinedFieldStyle()).frame(maxWidth: 360)
            }
            ForEach(spec.groups) { g in
                let c = g.completion(m.values)
                let title: String = g.title ?? (m.name.isEmpty ? spec.reportTitle : spec.reportTitle + " " + m.name)
                let trailing: String? = c.total > 0 ? "\(c.filled)/\(c.total)" : nil
                let number: String? = g.no.map { $0 + "." }
                PaperBox(title: title, number: number, trailing: trailing) {
                    ForEach(g.fields) { f in
                        if f.isVisible(job.modules[i].values) { FieldView(spec: f, values: $job.modules[i].values, jobID: job.id, moduleType: m.type, gps: job.values.text("gps")) }
                    }
                }
            }
            nextButton
        }
    }

    func header(_ title: String, subtitle: String, completion c: Completion) -> some View {
        PageHeader(title: title, subtitle: subtitle, completion: c, compact: compact)
    }

    var pages: [Page] {
        [.summary] + sidebarGroups.flatMap { $0.items.map(\.page) }
    }
    var nextPage: Page? {
        guard let i = pages.firstIndex(of: page), i + 1 < pages.count else { return nil }
        return pages[i + 1]
    }
    @ViewBuilder var nextButton: some View {
        if let next = nextPage {
            HStack {
                Spacer()
                Button { withAnimation { page = next } } label: { Label("หัวข้อถัดไป", systemImage: "arrow.right") }
                    .buttonStyle(TCButtonStyle(.primary, size: .card)).controlSize(.large)
            }
        }
    }
}

/// Code and title, subtitle and the filled count over the schema form; its own view so the page's type stays short
/// (a deep expression crashes SwiftUI in Debug).
struct PageHeader: View {
    let title: String
    let subtitle: String
    let completion: Completion
    let compact: Bool

    var body: some View {
        let c = completion
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.sarabun(TypeScale.pageTitle, .bold, relativeTo: .title2)).foregroundStyle(Theme.navy)
                Text(subtitle).font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
            }
            if !compact { Spacer() }
            if c.total > 0 {
                VStack(alignment: compact ? .leading : .trailing, spacing: 2) {
                    ProgressView(value: c.fraction).frame(width: 140).tint(c.isComplete ? Paper.tick : Theme.primary)
                    Text("กรอกแล้ว \(c.filled) จาก \(c.total)").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }
}
#endif
