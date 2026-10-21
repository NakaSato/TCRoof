import SwiftUI
import TCRoofUI
import SwiftData

/// Step-by-step installation checklist (ICL), ending with customer sign-off. The team fills and signs it; a member who
/// may only view it (`icl.checklist`: an external member) sees the submitted report, never a form: their device
/// doesn't send the ICL (`CloudSync`), so anything typed there would be lost.
struct InspectionView: View {
    let job: Job

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.permissions) private var permissions
    @AppStorage("userName") private var userName = ""

    @State private var inspection: Inspection?
    @State private var step = 0
    @State private var toast: String?

    private let steps = InspectionStep.all

    var body: some View {
        VStack(spacing: 0) {
            header
            if !canEdit {
                readOnly
            } else if let inspection {
                if inspection.submittedAt != nil {
                    InspectionReportScreen(inspection: inspection) {
                        inspection.submittedAt = nil
                        step = steps.count
                    }
                } else {
                    progress(inspection)
                    if step < steps.count {
                        InspectionStepForm(inspection: inspection, index: step)
                            .id(step)
                    } else {
                        InspectionSignOff(inspection: inspection, jumpTo: { step = $0 }, submit: { submit(inspection) })
                    }
                    bottomBar(inspection)
                }
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .tcPageBackground()
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.sarabun(15, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.teal, in: Capsule())
                    .padding(.top, 90)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { save(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.sarabun(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("ปิด")
            VStack(alignment: .leading, spacing: 2) {
                // one line, scaled down on the phone rather than broken mid-word
                Text("ใบตรวจรับงานติดตั้งระบบโซลาร์รูฟ").font(.sarabun(20, .bold, relativeTo: .title3)).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(job.code) | \(job.projectName)").font(.sarabun(15, relativeTo: .subheadline))
            }
            .foregroundStyle(Theme.onPrimary)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Theme.headerGradient.ignoresSafeArea(edges: .top))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    private func progress(_ inspection: Inspection) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(step < steps.count ? "\(step + 1)/\(steps.count)" : "สรุปผล").font(.sarabun(15, .bold, relativeTo: .subheadline))
                Spacer()
                Text(step < steps.count ? steps[step].short : "ลงนามรับงาน").font(.sarabun(15, relativeTo: .subheadline))
            }
            .foregroundStyle(Theme.navy)
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? AnyShapeStyle(Theme.headerGradient)
                                        : AnyShapeStyle(inspection.isComplete(i) ? Theme.mint : Theme.track))
                        .frame(height: 8)
                        .onTapGesture { step = i }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func bottomBar(_ inspection: Inspection) -> some View {
        HStack(spacing: 16) {
            Button {
                save()
                flash("บันทึกแบบร่างแล้ว")
            } label: {
                Text("บันทึก")
                    .font(.sarabun(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy.opacity(0.6)))
            }
            navButton("chevron.left", disabled: step == 0) { step -= 1; save() }
            navButton("chevron.right", disabled: step >= steps.count) { step += 1; save() }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Theme.surface.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2)))
    }

    private func navButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.sarabun(20, .bold, relativeTo: .title3))
                .frame(width: 84, height: 56)
        }
        .buttonStyle(TCButtonStyle(.primaryGradient, size: .bar))
        .disabled(disabled)
    }

    private var canEdit: Bool { permissions.can(.iclChecklist, on: job.access) }

    /// View only: the submitted report without its edit button, or a line that there is none yet.
    @ViewBuilder private var readOnly: some View {
        if let done = job.inspection, done.submittedAt != nil {
            InspectionReportScreen(inspection: done, reopen: nil)
        } else {
            Spacer()
            TCEmptyState("ยังไม่มีใบตรวจรับที่ส่งแล้ว", systemImage: "checkmark.seal",
                         description: Text("ใบตรวจรับงาน (ICL) กรอกและลงนามโดยทีมภายใน | ดูได้เมื่อทีมส่งแล้ว"))
            Spacer()
        }
    }

    private func load() {
        guard inspection == nil, canEdit else { return }
        if let existing = job.inspection {
            inspection = existing
            step = min(existing.currentStep, steps.count)
        } else {
            let created = Inspection(inspector: userName, customerName: job.customerName)
            context.insert(created)
            created.job = job
            inspection = created
        }
    }

    private func save() {
        guard let inspection else { return }
        inspection.currentStep = step
        inspection.updatedAt = .now
        try? context.save()
    }

    private func submit(_ inspection: Inspection) {
        inspection.submittedAt = .now
        inspection.inspector = userName
        job.status = .completed
        save()
        flash("ส่งใบตรวจรับงานเรียบร้อย")
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if toast == text { toast = nil } }
        }
    }
}

// MARK: - One step

private struct InspectionStepForm: View {
    @Bindable var inspection: Inspection
    let index: Int

    @Environment(\.modelContext) private var context

    private var step: InspectionStep { InspectionStep.all[index] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TCFieldLabel("\(index + 1).\(step.title)", required: true)
                Label(step.hint, systemImage: "info.circle")
                    .font(.sarabun(15, relativeTo: .subheadline))
                    .foregroundStyle(Theme.muted)

                if step.needsInstrument {
                    VStack(alignment: .leading, spacing: 8) {
                        TCFieldLabel("Serial No. เครื่องวัด", required: true)
                        TextField("ระบุหมายเลขเครื่องวัด", text: $inspection.results[index].instrumentSerial)
                            .textFieldStyle(OutlinedFieldStyle())
                            .textInputAutocapitalization(.characters)
                    }
                }

                if let unit = step.unit {
                    VStack(alignment: .leading, spacing: 8) {
                        TCFieldLabel("ค่าที่วัดได้", required: true)
                        TCTextField("0", text: $inspection.results[index].value, unit: unit, keyboard: .decimalPad)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    TCFieldLabel("รูปถ่าย", required: true)
                    let photos = inspection.photos(for: step.id)
                    PhotoPickerSection(images: photos.map(\.data), onAdd: addPhoto, onDelete: { i in
                        context.delete(photos[i])
                    })
                }

                VStack(alignment: .leading, spacing: 8) {
                    TCFieldLabel("ผลการตรวจ", required: true)
                    HStack(spacing: 16) {
                        TCChoiceChip("ผ่าน", selected: inspection.results[index].passed == true) {
                            inspection.results[index].passed = true
                        }
                        TCChoiceChip("ไม่ผ่าน", selected: inspection.results[index].passed == false, negative: true) {
                            inspection.results[index].passed = false
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    TCFieldLabel("หมายเหตุ")
                    TextField("รายละเอียดเพิ่มเติม / สิ่งที่ต้องแก้ไข", text: $inspection.results[index].note, axis: .vertical)
                        .lineLimit(2...6)
                        .textFieldStyle(OutlinedFieldStyle())
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func addPhoto(_ data: Data) {
        let photo = PhotoAsset(data: data, tag: step.id)
        context.insert(photo)
        photo.inspection = inspection
    }
}

// MARK: - Summary & sign-off

private struct InspectionSignOff: View {
    @Bindable var inspection: Inspection
    let jumpTo: (Int) -> Void
    let submit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("สรุปผลการตรวจ").font(.sarabun(22, .bold, relativeTo: .title2)).foregroundStyle(Theme.navy)
                VStack(spacing: 0) {
                    ForEach(InspectionStep.all.indices, id: \.self) { i in
                        Button { jumpTo(i) } label: { StepSummaryRow(inspection: inspection, index: i) }
                            .buttonStyle(.plain)
                        if i < InspectionStep.all.count - 1 { Divider() }
                    }
                }
                .cardStyle(padding: 8)

                VStack(alignment: .leading, spacing: 8) {
                    TCFieldLabel("ชื่อผู้รับงาน (ลูกค้า)", required: true)
                    TextField("ชื่อ-นามสกุล", text: $inspection.customerName)
                        .textFieldStyle(OutlinedFieldStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TCFieldLabel("ลายมือชื่อผู้รับงาน", required: true)
                        Spacer()
                        Button("ล้าง") { inspection.signature = nil }.disabled(inspection.signature == nil)
                    }
                    SignaturePad(signature: $inspection.signature)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy.opacity(0.45)))
                        .overlay(alignment: .bottomLeading) {
                            if inspection.signature == nil {
                                Text("เซ็นชื่อด้วย Apple Pencil หรือนิ้ว")
                                    .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted).padding(12)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Button(action: submit) {
                    Label("ส่งใบตรวจรับงาน", systemImage: "paperplane.fill")
                        .font(.sarabun(17, .semibold, relativeTo: .headline))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(TCButtonStyle(.tealGradient, size: .bar, fullWidth: true))
                .disabled(!canSubmit)
                if !inspection.allComplete {
                    Text("กรอกข้อมูลที่มี * ให้ครบทุกขั้นตอนก่อนส่ง (\(inspection.completedCount)/\(InspectionStep.all.count))")
                        .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.danger)
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private var canSubmit: Bool {
        inspection.allComplete && inspection.signature != nil
            && !inspection.customerName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

private struct StepSummaryRow: View {
    let inspection: Inspection
    let index: Int

    var body: some View {
        let step = InspectionStep.all[index]
        let result = inspection.results[index]
        HStack(spacing: 12) {
            Image(systemName: icon(result, complete: inspection.isComplete(index)))
                .font(.sarabun(20, relativeTo: .title3))
                .foregroundStyle(color(result, complete: inspection.isComplete(index)))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(index + 1). \(step.title)").font(.sarabun(15, .semibold, relativeTo: .subheadline))
                if let unit = step.unit, !result.value.isEmpty {
                    Text("ค่าที่วัดได้ \(result.value) \(unit)").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.navy)
        .padding(12)
        .contentShape(Rectangle())
    }

    private func icon(_ r: InspectionResult, complete: Bool) -> String {
        guard complete else { return "circle.dashed" }
        return r.passed == true ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private func color(_ r: InspectionResult, complete: Bool) -> Color {
        guard complete else { return Theme.muted }
        return r.passed == true ? Theme.success : Theme.danger
    }
}

// MARK: - Submitted report

private struct InspectionReportScreen: View {
    let inspection: Inspection
    /// `แก้ไขใบตรวจรับ`; nil for a member who may only view it.
    let reopen: (() -> Void)?

    @State private var pdfURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                InspectionReport(inspection: inspection, fitted: true)
                    .background(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 10)
                    .padding(isPhone ? 16 : 24)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 16) {
                if let reopen {
                    Button(action: reopen) {
                        Label("แก้ไขใบตรวจรับ", systemImage: "pencil")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
                }
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("ส่งออก PDF", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(TCButtonStyle(.primary, size: .card))
                }
            }
            .font(.sarabun(17, .semibold, relativeTo: .headline))
            .padding(.horizontal, isPhone ? 16 : 24)
            .padding(.vertical, 16)
            .background(Theme.paper)
        }
        .task { pdfURL = InspectionReport.renderPDF(inspection) }
    }
}

/// Printable A4-width report, also rendered to PDF.
struct InspectionReport: View {
    let inspection: Inspection
    /// On screen the paper narrows to fit an iPhone; the PDF keeps the A4 width.
    var fitted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ใบตรวจรับงานติดตั้งระบบโซลาร์รูฟ").font(.sarabun(20, .bold, relativeTo: .title3))
                    Text("Installation Checklist (ICL)").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Text(inspection.allPassed ? "ผ่าน" : "ไม่ผ่าน")
                    .font(.sarabun(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(inspection.allPassed ? Theme.success : Theme.danger, in: Capsule())
            }
            Divider()
            if let job = inspection.job {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text("รหัสโครงการ").foregroundStyle(Theme.inkMuted); Text(job.code) }
                    GridRow { Text("โครงการ").foregroundStyle(Theme.inkMuted); Text(job.projectName) }
                    GridRow { Text("ที่อยู่").foregroundStyle(Theme.inkMuted); Text("\(job.address) \(job.province)") }
                    GridRow { Text("ขนาดระบบ").foregroundStyle(Theme.inkMuted); Text("\(job.capacityKW.kw) | แผง \(job.devices.filter { $0.kind == .panel }.count) แผง") }
                    GridRow { Text("ทีมติดตั้ง").foregroundStyle(Theme.inkMuted); Text(job.team.rawValue) }
                }
                .font(.sarabun(15, relativeTo: .subheadline))
            }
            Divider()
            ForEach(InspectionStep.all.indices, id: \.self) { i in
                let step = InspectionStep.all[i]
                let r = inspection.results[i]
                HStack(alignment: .top) {
                    Text("\(i + 1). \(step.title)")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(r.passed == true ? "ผ่าน" : r.passed == false ? "ไม่ผ่าน" : "-")
                            .bold()
                            .foregroundStyle(r.passed == true ? Theme.success : Theme.danger)
                        if let unit = step.unit {
                            Text("\(r.value) \(unit)").font(.sarabun(12, relativeTo: .caption))
                        }
                        if !r.instrumentSerial.isEmpty {
                            Text("เครื่องวัด \(r.instrumentSerial)").font(.sarabun(11, relativeTo: .caption2)).foregroundStyle(Theme.inkMuted)
                        }
                        if !r.note.isEmpty {
                            Text(r.note).font(.sarabun(11, relativeTo: .caption2)).foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
                .font(.sarabun(15, relativeTo: .subheadline))
            }
            Divider()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ผู้ตรวจ: \(inspection.inspector)")
                    Text("วันที่: \((inspection.submittedAt ?? .now).thaiLongTime)")
                }
                .font(.sarabun(15, relativeTo: .subheadline))
                Spacer()
                VStack(spacing: 4) {
                    if let data = inspection.signature, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 200, height: 80)
                    }
                    Rectangle().frame(width: 200, height: 1)
                    Text("(\(inspection.customerName))").font(.sarabun(15, relativeTo: .subheadline))
                    Text("ผู้รับงาน").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .foregroundStyle(Color.black)
        .padding(fitted ? 20 : 32)
        .frame(width: fitted ? nil : 595)
        .frame(maxWidth: 595)
    }

    @MainActor
    static func renderPDF(_ inspection: Inspection) -> URL? {
        let name = "ICL-\(inspection.job?.code ?? "report").pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let renderer = ImageRenderer(content: InspectionReport(inspection: inspection).background(Theme.paper))
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
