import SwiftUI
import TCRoofUI
import SwiftData

/// Step-by-step installation checklist (ICL), ending with customer sign-off.
struct InspectionView: View {
    let job: Job

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = ""

    @State private var inspection: Inspection?
    @State private var step = 0
    @State private var toast: String?

    private let steps = InspectionStep.all

    var body: some View {
        VStack(spacing: 0) {
            header
            if let inspection {
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
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
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
                    .font(.headline)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 36, height: 36)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("ปิด")
            VStack(alignment: .leading, spacing: 2) {
                // one line, scaled down on the phone rather than broken mid-word
                Text("ใบตรวจรับงานติดตั้งระบบโซลาร์รูฟ").font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(job.code) · \(job.projectName)").font(.subheadline)
            }
            .foregroundStyle(.white)
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
                Text(step < steps.count ? "\(step + 1)/\(steps.count)" : "สรุปผล").font(.subheadline.bold())
                Spacer()
                Text(step < steps.count ? steps[step].short : "ลงนามรับงาน").font(.subheadline)
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
                    .font(.headline)
                    .foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy.opacity(0.6)))
            }
            navButton("chevron.left", disabled: step == 0) { step -= 1; save() }
            navButton("chevron.right", disabled: step >= steps.count) { step += 1; save() }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.white.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2)))
    }

    private func navButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.bold())
                .frame(width: 84, height: 56)
        }
        .buttonStyle(TCButtonStyle(.primaryGradient, size: .bar))
        .disabled(disabled)
    }

    private func load() {
        guard inspection == nil else { return }
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
                    .font(.subheadline)
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
                Text("สรุปผลการตรวจ").font(.title2.bold()).foregroundStyle(Theme.navy)
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
                                    .font(.caption).foregroundStyle(Theme.muted).padding(12)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Button(action: submit) {
                    Label("ส่งใบตรวจรับงาน", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(TCButtonStyle(.tealGradient, size: .bar, fullWidth: true))
                .disabled(!canSubmit)
                if !inspection.allComplete {
                    Text("กรอกข้อมูลที่มี * ให้ครบทุกขั้นตอนก่อนส่ง (\(inspection.completedCount)/\(InspectionStep.all.count))")
                        .font(.footnote).foregroundStyle(Theme.danger)
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
                .font(.title3)
                .foregroundStyle(color(result, complete: inspection.isComplete(index)))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(index + 1). \(step.title)").font(.subheadline.weight(.semibold))
                if let unit = step.unit, !result.value.isEmpty {
                    Text("ค่าที่วัดได้ \(result.value) \(unit)").font(.caption).foregroundStyle(Theme.muted)
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
    let reopen: () -> Void

    @State private var pdfURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                InspectionReport(inspection: inspection)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 10)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 16) {
                Button(action: reopen) {
                    Label("แก้ไขใบตรวจรับ", systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("ส่งออก PDF", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(TCButtonStyle(.primary, size: .card))
                }
            }
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.white)
        }
        .task { pdfURL = InspectionReport.renderPDF(inspection) }
    }
}

/// Printable A4-width report, also rendered to PDF.
struct InspectionReport: View {
    let inspection: Inspection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ใบตรวจรับงานติดตั้งระบบโซลาร์รูฟ").font(.title3.bold())
                    Text("Installation Checklist (ICL)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(inspection.allPassed ? "ผ่าน" : "ไม่ผ่าน")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(inspection.allPassed ? Theme.success : Theme.danger, in: Capsule())
            }
            Divider()
            if let job = inspection.job {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text("รหัสโครงการ").foregroundStyle(.secondary); Text(job.code) }
                    GridRow { Text("โครงการ").foregroundStyle(.secondary); Text(job.projectName) }
                    GridRow { Text("ที่อยู่").foregroundStyle(.secondary); Text("\(job.address) \(job.province)") }
                    GridRow { Text("ขนาดระบบ").foregroundStyle(.secondary); Text("\(job.capacityKW.kw) · แผง \(job.devices.filter { $0.kind == .panel }.count) แผง") }
                    GridRow { Text("ทีมติดตั้ง").foregroundStyle(.secondary); Text(job.team.rawValue) }
                }
                .font(.subheadline)
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
                            Text("\(r.value) \(unit)").font(.caption)
                        }
                        if !r.instrumentSerial.isEmpty {
                            Text("เครื่องวัด \(r.instrumentSerial)").font(.caption2).foregroundStyle(.secondary)
                        }
                        if !r.note.isEmpty {
                            Text(r.note).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.subheadline)
            }
            Divider()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ผู้ตรวจ: \(inspection.inspector)")
                    Text("วันที่: \((inspection.submittedAt ?? .now).thaiLongTime)")
                }
                .font(.subheadline)
                Spacer()
                VStack(spacing: 4) {
                    if let data = inspection.signature, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 200, height: 80)
                    }
                    Rectangle().frame(width: 200, height: 1)
                    Text("(\(inspection.customerName))").font(.subheadline)
                    Text("ผู้รับงาน").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(Color.black)
        .padding(32)
        .frame(width: 595)
    }

    @MainActor
    static func renderPDF(_ inspection: Inspection) -> URL? {
        let name = "ICL-\(inspection.job?.code ?? "report").pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let renderer = ImageRenderer(content: InspectionReport(inspection: inspection).background(.white))
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
