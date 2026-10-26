import SwiftUI
import SwiftData
import TCRoofCore
import TCRoofUI

/// One sheet of the site ICL: every item with its criterion, method, hold point and evidence; the result (ผ่าน /
/// ไม่ผ่าน / ไม่เกี่ยว), the measured value, the instrument, photos and a note. The contractor sends a complete sheet;
/// the engineer signs it or sends it back with what to fix; a signed sheet is read only until the team reopens it.
struct SiteICLSheetView: View {
    let job: Job
    @Bindable var model: ICLSheet

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.permissions) private var permissions
    @AppStorage("userName") private var userName = ""
    @State private var askingReturn = false
    @State private var returnNote = ""
    @State private var pdfURL: URL?

    private var sheet: SiteICL.Sheet { model.sheet }
    private var items: [SiteICL.Item] { model.items }
    private var canFill: Bool { permissions.can(.iclSiteFill, on: job.access) }
    private var canSign: Bool { permissions.can(.iclSiteSign, on: job.access) }
    /// The contractor (or the team) edits an open sheet; nobody edits a sent or signed one.
    private var editable: Bool { canFill && sheet.lockState == .open }
    private var me: String { userName.isEmpty ? permissions.email : userName }

    var body: some View {
        VStack(spacing: 0) {
            SiteICLHeader(title: sheet.title, subtitle: "\(job.code) · ICL ตรวจหน้างาน") { try? context.save(); dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    banner
                    ForEach(items) { item in
                        SiteICLItemCard(item: item, model: model, editable: editable, by: me)
                    }
                }
                .padding(isPhone ? 16 : 24)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .tcPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .alert("ส่งกลับให้แก้", isPresented: $askingReturn) {
            TextField("สิ่งที่ต้องแก้", text: $returnNote)
            Button("ยกเลิก", role: .cancel) {}
            Button("ส่งกลับ") { change { $0.returnForFix(by: me, note: returnNote) }; returnNote = "" }
        } message: {
            Text("ผรม. จะแก้และส่งใบนี้อีกครั้ง")
        }
        .task(id: model.sheetJSON) { pdfURL = sheet.lockState == .open ? nil : SiteICLReport.renderPDF(job: job, model: model) }
        .onDisappear { try? context.save() }
    }

    // MARK: banner

    @ViewBuilder private var banner: some View {
        let progress = model.progress
        VStack(alignment: .leading, spacing: 6) {
            SiteICLStatus(sheet: sheet, items: items, progress: progress)
            if let back = sheet.sendBack, sheet.lockState == .open {
                Label("วศ. ส่งกลับ: \(back.note.isEmpty ? "-" : back.note) (\(back.by))", systemImage: "arrow.uturn.backward")
                    .font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.dangerText)
            }
            if let sent = sheet.submission {
                Text("ส่งโดย \(sent.by) · \(sent.at.thaiLongTime)").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            if let signed = sheet.signoff {
                Text("ลงนามโดย \(signed.by) · \(signed.at.thaiLongTime)").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                if sheet.signoffIsStale {
                    Text("มีการแก้ค่าหลังลงนาม: เปิดแก้ไขแล้วให้ ผรม. ส่งใหม่").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.danger)
                }
            }
            if !canFill && !canSign {
                Text("ดูอย่างเดียว").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
    }

    // MARK: hand-over

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let pdfURL {
                ShareLink(item: pdfURL) {
                    Label("PDF", systemImage: "square.and.arrow.up").frame(minWidth: 88, minHeight: 50)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
            }
            actions
        }
        .font(.sarabun(17, .semibold, relativeTo: .headline))
        .padding(.horizontal, isPhone ? 16 : 24)
        .padding(.vertical, 12)
        .background(Theme.surface.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2)))
    }

    @ViewBuilder private var actions: some View {
        switch sheet.lockState {
        case .open:
            if canFill {
                let complete = sheet.isComplete(items) { model.photos(for: $0).count }
                Button { change { $0.submit(by: me) } } label: {
                    Label(complete ? "ส่งให้ วศ. ลงนาม" : "ยังไม่ครบ \(model.progress.done)/\(items.count)", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(TCButtonStyle(.tealGradient, size: .bar, fullWidth: true))
                .disabled(!complete)
            }
        case .sent:
            if canSign {
                Button { askingReturn = true } label: {
                    Label("ส่งกลับให้แก้", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
                Button { change { $0.sign(by: me) } } label: {
                    Label("ลงนามรับรอง", systemImage: "signature").frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(TCButtonStyle(.tealGradient, size: .bar, fullWidth: true))
            } else {
                Text("รอ วศ. ลงนาม").foregroundStyle(Theme.muted).frame(maxWidth: .infinity, minHeight: 50)
            }
        case .closed:
            if canSign {
                Button { change { $0.reopen() } } label: {
                    Label("แก้ไข (เปิดใบนี้อีกครั้ง)", systemImage: "pencil").frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
            } else {
                Spacer()
            }
        }
    }

    private func change(_ edit: (inout SiteICL.Sheet) -> Void) {
        var s = model.sheet
        edit(&s)
        model.sheet = s
        try? context.save()
    }
}

// MARK: - One item

struct SiteICLItemCard: View {
    let item: SiteICL.Item
    @Bindable var model: ICLSheet
    let editable: Bool
    let by: String

    @Environment(\.modelContext) private var context

    private var result: SiteICL.Result { model.sheet.result(item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading
            details
            if !result.notApplicable {
                if item.unit != nil { valueFields }
                photos
            }
            resultChips
            note
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
        .opacity(result.notApplicable ? 0.6 : 1)
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 8) {
            SiteICLHoldBadge(hold: item.hold)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.sarabun(16, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Text(item.id).font(.sarabun(11, relativeTo: .caption2)).foregroundStyle(Theme.muted)
            }
            Spacer()
            doneMark
        }
    }

    @ViewBuilder private var doneMark: some View {
        if model.sheet.isDone(item, photos: model.photos(for: item).count) {
            Image(systemName: result.passed == false ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(result.passed == false ? Theme.danger : Theme.success)
                .accessibilityLabel(result.passed == false ? "ไม่ผ่าน" : "ครบ")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            line("เกณฑ์", item.criterion, bold: true)
            line("วิธีตรวจ", item.method)
            line("หลักฐาน", item.evidence)
            if !item.reference.isEmpty { line("อ้างอิง", item.reference) }
            if item.applies != "ทุกสถานี" && item.applies != "ทุกประเภท" { line("ใช้กับ", item.applies) }
        }
    }

    private func line(_ label: String, _ text: String, bold: Bool = false) -> some View {
        (Text("\(label): ").foregroundStyle(Theme.muted) + Text(text).foregroundStyle(Theme.navy).fontWeight(bold ? .semibold : .regular))
            .font(.sarabun(14, relativeTo: .subheadline))
    }

    private var valueFields: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TCFieldLabel("ค่าที่วัดได้", required: true)
                TCTextField("0", text: binding(\.value), unit: item.unit, readOnly: !editable, keyboard: .decimalPad)
            }
            VStack(alignment: .leading, spacing: 6) {
                TCFieldLabel("เลขเครื่องมือ")
                TCTextField("S/N", text: binding(\.instrumentSerial), readOnly: !editable)
            }
        }
    }

    @ViewBuilder private var photos: some View {
        let list = model.photos(for: item)
        VStack(alignment: .leading, spacing: 6) {
            TCFieldLabel("รูปถ่าย", required: true)
            if editable {
                PhotoPickerSection(images: list.map(\.data), onAdd: addPhoto, onDelete: { i in
                    guard list.indices.contains(i) else { return }
                    context.delete(list[i])
                })
            } else if list.isEmpty {
                Text("ไม่มีรูป").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(list) { p in SiteICLThumb(data: p.data) }
                    }
                }
            }
        }
    }

    private var resultChips: some View {
        HStack(spacing: 12) {
            TCChoiceChip("ผ่าน", selected: result.passed == true && !result.notApplicable) { update { $0.passed = true; $0.notApplicable = false } }
            TCChoiceChip("ไม่ผ่าน", selected: result.passed == false && !result.notApplicable, negative: true) { update { $0.passed = false; $0.notApplicable = false } }
            TCChoiceChip("ไม่เกี่ยว", selected: result.notApplicable) { update { $0.notApplicable.toggle(); $0.passed = nil } }
        }
        .disabled(!editable)
    }

    private var note: some View {
        TextField(result.passed == false ? "สิ่งที่ต้องแก้" : "หมายเหตุ (จุดที่ตรวจ, ค่าแต่ละจุด)", text: binding(\.note), axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(OutlinedFieldStyle())
            .disabled(!editable)
    }

    private func binding(_ key: WritableKeyPath<SiteICL.Result, String>) -> Binding<String> {
        Binding(get: { result[keyPath: key] }, set: { v in update { $0[keyPath: key] = v } })
    }

    private func update(_ edit: (inout SiteICL.Result) -> Void) {
        var s = model.sheet
        var r = s.result(item)
        edit(&r)
        r.checkedAt = .now
        r.by = by
        s.results[item.id] = r
        model.sheet = s
    }

    private func addPhoto(_ data: Data) {
        let photo = PhotoAsset(data: data, tag: SiteICL.photoTag(sheet: model.sheet.id, item: item.id))
        context.insert(photo)
        photo.iclSheet = model
        model.updatedAt = .now
    }
}

struct SiteICLThumb: View {
    let data: Data
    var size: CGFloat = 96

    var body: some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.track.overlay(Image(systemName: "photo").foregroundStyle(Theme.muted))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - PDF

/// A sheet as an A4-wide page (one tall page, as the residential ICL's report), with each item's first two photos.
struct SiteICLReport: View {
    let job: Job
    let model: ICLSheet

    var body: some View {
        let sheet = model.sheet
        let items = model.items
        VStack(alignment: .leading, spacing: 10) {
            Text("ใบตรวจ ICL หน้างาน: \(sheet.title)").font(.sarabun(18, .bold))
            Text("\(job.code) \(job.projectName) · โครงการ Solar Rooftop กปภ.").font(.sarabun(12))
            Divider()
            ForEach(items) { item in itemRow(item, sheet: sheet) }
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ผู้ตรวจ (ผรม.): \(sheet.submission?.by ?? "-")")
                    Text("วันที่ส่ง: \(sheet.submission?.at.thaiLongTime ?? "-")")
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("วิศวกรผู้ลงนาม: \(sheet.signoff?.by ?? "-")")
                    Text("วันที่ลงนาม: \(sheet.signoff?.at.thaiLongTime ?? "-")")
                }
            }
            .font(.sarabun(12))
        }
        .foregroundStyle(Color.black)
        .padding(28)
        .frame(width: 595)
    }

    private func itemRow(_ item: SiteICL.Item, sheet: SiteICL.Sheet) -> some View {
        let r = sheet.result(item)
        let verdict = r.notApplicable ? "ไม่เกี่ยว" : r.passed == true ? "ผ่าน" : r.passed == false ? "ไม่ผ่าน" : "-"
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.id) [\(item.hold.rawValue)] \(item.title)").font(.sarabun(11, .semibold))
                Text("เกณฑ์: \(item.criterion)").font(.sarabun(9.5))
                if !r.value.isEmpty { Text("ค่าที่วัด: \(r.value) \(item.unit ?? "")  เครื่องมือ: \(r.instrumentSerial)").font(.sarabun(9.5)) }
                if !r.note.isEmpty { Text("หมายเหตุ: \(r.note)").font(.sarabun(9.5)) }
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(model.photos(for: item).prefix(2)) { p in SiteICLThumb(data: p.data, size: 56) }
            }
            Text(verdict).font(.sarabun(11, .bold)).frame(width: 52)
                .foregroundStyle(r.passed == false && !r.notApplicable ? Theme.danger : Color.black)
        }
    }

    @MainActor
    static func renderPDF(job: Job, model: ICLSheet) -> URL? {
        let name = "ICL \(job.code) \(model.sheet.id.replacingOccurrences(of: "/", with: " ")).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let renderer = ImageRenderer(content: SiteICLReport(job: job, model: model).background(Theme.paper))
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}
