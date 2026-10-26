import SwiftUI
import UniformTypeIdentifiers
import TCRoofUI
import TCRoofCore

/// Step 1/7 `ตั้งค่าระบบ` on iPad (docs/ui/iec62446-step1-setup-ipad): the SLD, the test record (date, tester,
/// conditions, instruments) and the string list of each inverter, with the add and delete sheets. It replaces
/// `IECSetupSheet` in regular width; the iPhone keeps the sheet.
struct IECSetupPage: View {
    @Bindable var job: Job
    /// Another step's screen, opened by the overview (`IECTestScreen`), which owns the navigation.
    let openStage: (IECReport.Stage) -> Void
    /// `‹ กลับ งานติดตั้ง`: back to where the test was opened.
    let leave: () -> Void

    @State var inverter = 0
    @State var adding = false
    @State var deleting: Int?
    @State var editingSerial = false
    @State var importing = false
    @State var viewing: DocumentAsset?
    @State var history = false
    @State var scan: ScanTarget?
    @State var scanning = false
    @State var notRead = false
    @State var savedFlash = false
    @State var debugApplied = false
    @State var module = false
    /// The add sheet's S/N, so a scan can fill it.
    @State var newSerial = ""
    @Environment(\.modelContext) var context

    enum ScanTarget: Equatable { case serial(Int), instrument(WritableKeyPath<IECReport.Instruments, String>), newInverter }

    var report: IECReport { job.iecReport ?? job.newIECReport }

    var body: some View {
        let r = report
        VStack(spacing: 0) {
            IECHeader(title: "IEC 62446 | ตั้งค่าระบบ", subtitle: r.stationLine.isEmpty ? job.stationName : r.stationLine) { EmptyView() }
            IECStepProgress(current: .setup, report: r) { s in if s != .setup { openStage(s) } }
                .padding(.horizontal, 24).padding(.top, 14)
            HStack(alignment: .top, spacing: 24) {
                ScrollView { leftColumn(r).padding(.bottom, 16) }
                    .scrollIndicators(.hidden).frame(width: 420)
                stringList(r)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 16)
            .frame(maxWidth: 1290, maxHeight: .infinity, alignment: .top)
            .disabled(r.isLocked)
            bottomBar(r)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay { sheets(r) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in importSLD(result) }
        .fullScreenCover(item: $viewing) { SLDViewer(doc: $0) }
        .sheet(isPresented: $history) { historySheet }
        .sheet(isPresented: $module) { IECModuleSheet(job: job) }
        .modifier(IECSerialScanner(active: $scanning) { serial in scanned(serial) })
        .alert("อ่าน S/N จากรูปไม่ได้", isPresented: $notRead) { Button("ตกลง", role: .cancel) {} } message: { Text("พิมพ์ S/N เองในช่อง") }
        .onAppear(perform: prefillTester)
        #if DEBUG
        .task { applyDebug() }
        #endif
    }

    /// `ผู้ทดสอบ` defaults to the signed-in user.
    func prefillTester() {
        guard report.tester.trimmingCharacters(in: .whitespaces).isEmpty, !report.isLocked else { return }
        let name = UserDefaults.standard.string(forKey: GoogleSession.userNameKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        if !name.isEmpty { job.updateIEC(context) { $0.tester = name } }
    }

    // MARK: left column

    func leftColumn(_ r: IECReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            banner
            diagramCard(r)
            recordFields(r)
            conditions(r)
            instruments(r)
        }
    }

    var banner: some View {
        HStack(spacing: 12) {
            Text("!").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.onPrimary).frame(width: 30, height: 30).background(Theme.warning, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("ระบบยังไม่ออน | ตั้งค่าก่อนเริ่มวัด").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.warningText)
                Text("แนบแบบ SLD และตรวจรายการสตริง | เติม E5, O5, แถว 8–9").font(.sarabunFixed(12)).foregroundStyle(Theme.warningText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder func diagramCard(_ r: IECReport) -> some View {
        let doc = job.iecSLD, versions = job.iecSLDVersions.count
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagram").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
            Button { viewing = doc } label: { sldPreview(doc) }
                .buttonStyle(.plain).disabled(doc == nil)
                .accessibilityLabel(doc == nil ? "ยังไม่มีแบบ SLD" : "ดูแบบ SLD เต็มจอ")
            if let doc {
                HStack(spacing: 8) {
                    Text(SLDFile.isPDF(doc.data) ? "PDF" : "รูป").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.dangerText)
                        .padding(.horizontal, 6).frame(height: 20).background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 4))
                    Text(doc.name).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text("v\(versions) | " + IECTestScreen.stamp(doc.addedAt, "") + " น.").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                if versions > 1 {
                    Button("ประวัติ \(versions) ครั้ง") { history = true }.font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary).frame(minHeight: 32)
                }
            }
            HStack(spacing: 8) {
                Button("ดูแบบ") { viewing = doc }.buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true)).disabled(doc == nil)
                Button("อัปโหลด PDF") { importing = true }.buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                // no reader for strings in an SLD yet (open question 1): shown, not working
                Button("อ่านรายการสตริง") {}.buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true)).disabled(true)
                    .accessibilityHint("ยังอ่านรายการสตริงจากแบบไม่ได้")
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    @ViewBuilder func sldPreview(_ doc: DocumentAsset?) -> some View {
        ZStack(alignment: .bottomLeading) {
            Theme.paper
            if let doc, let img = SLDFile.preview(doc.data) {
                Image(uiImage: img).resizable().scaledToFit().padding(8)
                HStack(spacing: 6) {
                    chip("หน้า 1/\(SLDFile.pageCount(doc.data)) | Inverter \(inverter + 1)", bold: true)
                    chip("แตะเพื่อดูเต็มจอ | ซูมได้", bold: false)
                }
                .padding(8)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 28))
                    Text("ยังไม่มีแบบ SLD | อัปโหลด PDF หรือรูป").font(.sarabunFixed(14))
                }
                .foregroundStyle(Theme.warningInk).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(doc == nil ? Theme.warning : Theme.borderSubtle, style: StrokeStyle(lineWidth: 1.2, dash: doc == nil ? [5, 4] : [])))
    }

    func chip(_ text: String, bold: Bool) -> some View {
        Text(text).font(.sarabunFixed(12, bold ? .bold : .regular)).foregroundStyle(bold ? Theme.navy : Theme.inkMuted)
            .padding(.horizontal, 8).frame(height: 24).background(Theme.surface.opacity(0.95), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderSubtle))
    }

    var historySheet: some View {
        NavigationStack {
            List(job.iecSLDVersions.reversed()) { doc in
                Button { history = false; Task { try? await Task.sleep(for: .milliseconds(400)); viewing = doc } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.name).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                        Text(IECTestScreen.stamp(doc.addedAt, "") + " น.").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            .navigationTitle("ประวัติแบบ SLD").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ปิด") { history = false } } }
        }
    }

    func importSLD(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        job.storeSLD(data, name: url.lastPathComponent, context: context)
    }

    // MARK: record

    func recordFields(_ r: IECReport) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                required("วันที่ทดสอบ")
                IECDateField(date: r.testDate) { d in job.updateIEC(context) { $0.testDate = d } }
            }
            VStack(alignment: .leading, spacing: 6) {
                required("ผู้ทดสอบ")
                IECDashedTextField(placeholder: "ชื่อ-นามสกุล", text: r.tester) { t in job.updateIEC(context) { $0.tester = t } }
            }
        }
    }

    func required(_ title: String) -> some View {
        (Text(title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy) + Text("  *").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.dangerText))
    }

    func conditions(_ r: IECReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("สภาพการทดสอบ").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("ก่อนออน | INV 01 ลิงก์ไปทุกแผ่น").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            HStack(spacing: 10) {
                IECConditionTile(label: "อากาศ | E29", unit: "°C", text: r.before.ambientC.map { IECFormat.number($0, digits: 1) } ?? "", keyboard: .decimalPad) { t in
                    job.updateIEC(context) { $0.before.ambientC = Double(t) }
                }
                IECConditionTile(label: "แสง | E30", unit: "W/m²", text: r.before.irradianceWm2.map { IECFormat.number($0, digits: 0) } ?? "", keyboard: .numberPad) { t in
                    job.updateIEC(context) { $0.before.irradianceWm2 = Double(t) }
                }
                IECConditionTile(label: "เวลา | AA30", unit: "น.", text: r.before.time ?? "", keyboard: .numbersAndPunctuation) { t in
                    job.updateIEC(context) { $0.before.time = t.isEmpty ? nil : t }
                }
                // no Excel cell: the string test's expected Voc (ZN-132) uses it, else NMOT's estimate
                IECConditionTile(label: "แผง | ไม่มีใน Excel", unit: "°C", text: r.before.moduleTempC.map { IECFormat.number($0, digits: 1) } ?? "", keyboard: .decimalPad) { t in
                    job.updateIEC(context) { $0.before.moduleTempC = Double(t) }
                }
            }
        }
    }

    func instruments(_ r: IECReport) -> some View {
        let rows: [(String, WritableKeyPath<IECReport.Instruments, String>)] = [
            ("แคลมป์มิเตอร์", \.multimeterClamp), ("เครื่องวัดฉนวน (IR)", \.insulationTester),
            ("เครื่องวัดแสง", \.irradianceMeter), ("กล้องความร้อน", \.thermalCamera)]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("เครื่องมือวัด (S/N)").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("ฟอร์มเดิมไม่มี | แนะนำให้เก็บ").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { k, row in
                    IECInstrumentRow(title: row.0, serial: r.instruments[keyPath: row.1], tools: InstrumentStore.shared.all,
                                     set: { v in job.updateIEC(context) { $0.instruments[keyPath: row.1] = v } },
                                     scan: { scan = .instrument(row.1); scanning = true })
                    if k < rows.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
        }
    }

    /// A serial came back from the scanner.
    func scanned(_ serial: String?) {
        guard let serial, let target = scan else { notRead = scan != nil && scan != .newInverter; scan = nil; return }
        switch target {
        case .serial(let i): job.updateIEC(context) { r in if r.inverters.indices.contains(i) { r.inverters[i].serial = serial } }
        case .instrument(let k): job.updateIEC(context) { $0.instruments[keyPath: k] = serial }
        case .newInverter: newSerial = serial
        }
        scan = nil
    }

    // MARK: bottom bar

    /// `แนบแบบ SLD และตั้งรายการสตริงแล้ว | ยังไม่ได้กรอกวันที่ ผู้ทดสอบ และ S/N เครื่องมือ`.
    func status(_ r: IECReport) -> (text: String, ok: Bool) {
        var done: [String] = [], missing = r.setupBlockers.filter { $0 != "แบบ SLD" && $0 != "สตริง" }
        if r.sld != nil { done.append("แนบแบบ SLD") }
        if r.inverters.contains(where: { !$0.strings.isEmpty }) { done.append("ตั้งรายการสตริง") }
        if !r.instruments.isComplete { missing.append("S/N เครื่องมือ") }
        if r.sld == nil { return ("ยังไม่ได้แนบแบบ SLD", false) }
        let head = done.joined(separator: " และ") + "แล้ว"
        if missing.isEmpty { return (head + " | ครบ ไปวัดก่อนออนได้", true) }
        let list = missing.count > 1 ? missing.dropLast().joined(separator: " ") + " และ " + missing.last! : missing[0]
        return (head + " | ยังไม่ได้กรอก" + list, r.setupBlockers.isEmpty)
    }

    func bottomBar(_ r: IECReport) -> some View {
        let s = status(r), ready = r.setupBlockers.isEmpty
        return HStack(spacing: 14) {
            Image(systemName: s.ok ? "checkmark" : "exclamationmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                .frame(width: 28, height: 28).background(s.ok ? Theme.success : Theme.warning, in: Circle())
            Text(r.lockedLine ?? s.text).font(.sarabunFixed(14)).foregroundStyle(Theme.navy).lineLimit(2)
            Spacer(minLength: 8)
            Button { try? context.save(); savedFlash = true; Task { try? await Task.sleep(for: .seconds(1.5)); savedFlash = false } } label: {
                Text(savedFlash ? "บันทึกแล้ว ✓" : "บันทึกร่างตอนนี้").frame(minWidth: 140)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .bar)).accessibilityLabel("บันทึกร่างตอนนี้")
            IECStepButton(small: "กลับ", big: "งานติดตั้ง", forward: false, action: leave)
            IECStepButton(small: "ถัดไป 2/7", big: IECReport.Stage.beforeVoltage.title, forward: true) { openStage(.beforeVoltage) }
                .disabled(!ready).opacity(ready ? 1 : 0.5)
                .accessibilityHint(ready ? "" : "ต้องมี " + r.setupBlockers.joined(separator: " ") + " ก่อน")
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

/// `‹ กลับ / งานติดตั้ง`, `ถัดไป 2/7 / … ›`: the bottom bars' two-line step buttons.
struct IECStepButton: View {
    let small: String
    let big: String
    let forward: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if !forward { Image(systemName: "chevron.left") }
                VStack(alignment: forward ? .trailing : .leading, spacing: 0) {
                    Text(small).font(.sarabunFixed(12))
                    Text(big).font(.sarabunFixed(16, .bold)).lineLimit(1)
                }
                if forward { Image(systemName: "chevron.right") }
            }
            .foregroundStyle(forward ? Theme.onPrimary : Theme.navy)
            .padding(.horizontal, 18).frame(minWidth: 210, minHeight: 53)
            .background(forward ? AnyShapeStyle(Theme.actionGradient) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(forward ? Color.clear : Theme.borderControl))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(small + " " + big)
    }
}
