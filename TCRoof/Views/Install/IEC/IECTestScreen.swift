import SwiftUI
import TCRoofUI
import TCRoofCore
import ExcelExport

/// `ทดสอบระบบ IEC 62446` (docs/ui/iec62446-test screen 1): how complete each inverter is before and after the grid
/// connection, and what is still missing before the export. An inverter's band opens its string table (screen 2).
/// Opened from the install tracking page's tab.
struct IECTestScreen: View {
    @Bindable var job: Job
    /// Embedded in the install page's tabs: use that page's shared header instead of drawing a second blue header.
    var embedded = false
    @State var setup = false
    @State var grid: GridTarget?
    /// Step 2's designed page (iPad): the inverter it opens on.
    @State var step2: Step2Target?
    @Environment(\.horizontalSizeClass) var sizeClass
    /// Step 1's designed page (iPad); the iPhone keeps the set-up sheet.
    @State var step1 = false
    /// The sheet preview (iPad): the inverter and phase whose sheet it opens on.
    @State var sheetPreview: SheetTarget?
    struct SheetTarget: Hashable { let inverter: Int; var phase: IECReport.Phase = .before }
    @Environment(\.dismiss) var dismiss
    @State var exported: ExportedFile?
    /// The file the station-line question is about.
    @State var exportKind: IECReport.ExportRecord.Kind = .excel
    /// The Word appendix is being made (its photos are shrunk first).
    @State var makingWord = false
    @State var exportError: String?
    /// The station line names another station: asked before exporting.
    @State var confirmExport = false
    /// `ส่งกลับให้แก้` asks what to fix first.
    @State var sendingBack = false
    @State var sendBackNote = ""
    /// `แก้ไข` on a closed test asks first: it reopens it.
    @State var confirmReopen = false
    /// The debug flags apply once: `.task` runs again each time the screen reappears (back from a table).
    @State var debugApplied = false
    @Environment(\.modelContext) var context
    /// The contractor sends (`iec.fill_submit`); only the internal team closes, sends back or reopens (`iec.close`).
    @Environment(\.permissions) var permissions

    struct ExportedFile: Identifiable { let url: URL; var id: URL { url } }

    /// The string table of one inverter and phase.
    struct GridTarget: Hashable { let inverter: Int; let phase: IECReport.Phase; var page: IECStringGrid.Page = .table }
    /// Step 2 (before) or step 4 (after)'s designed page.
    struct Step2Target: Hashable { let inverter: Int; var slot = 1; var phase: IECReport.Phase = .before }

    var body: some View {
        let report = job.iecReport
        VStack(spacing: 0) {
            if !embedded {
                IECHeader(title: "ทดสอบระบบ IEC 62446", subtitle: (report?.stationLine).flatMap { $0.isEmpty ? nil : $0 } ?? job.stationName) {
                    if report?.isLocked != true {
                        IECHeaderButton(title: report == nil ? "ตั้งค่าการทดสอบ" : "ตั้งค่า", symbol: "slider.horizontal.3") { showSetup() }
                    }
                    if report?.inverters.isEmpty == false, sizeClass == .regular {
                        IECHeaderButton(title: "ดูชีต Excel", symbol: "tablecells") { sheetPreview = SheetTarget(inverter: 0) }
                    }
                    if report?.inverters.isEmpty == false { IECHeaderButton(title: "ส่งออก", symbol: "square.and.arrow.up") { startExport() } }
                }
            }
            if let report, !report.inverters.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        if embedded { embeddedOverview(report) }
                        resultNotice(report)
                        stationNotice(report)
                        stats(report)
                        inverterCards(report)
                        stagesCard(report)
                        if embedded { embeddedFooter(report) }
                    }
                    .padding(Space.xl)
                }
                .scrollIndicators(.hidden)
                if !embedded { bottomBar(report) }
            } else {
                emptyState
            }
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $setup) { IECSetupSheet(report: job.iecReport ?? job.newIECReport) { r in job.updateIEC(context) { $0 = r } } }
        .sheet(item: $exported) { ActivitySheet(items: [$0.url]) }
        .confirmationDialog("บรรทัดสถานีในแผ่นงานไม่ตรงกับชื่องาน", isPresented: $confirmExport, titleVisibility: .visible) {
            Button("ใช้ชื่อของงานแล้วส่งออก") { useJobName(); export(exportKind) }
            Button("ส่งออกตามเดิม") { export(exportKind) }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("แผ่นงานเขียนว่า “\(job.iecReport?.stationLine ?? "")” แต่งานนี้คือ “\(job.stationName)”")
        }
        .confirmationDialog("เปิดผลทดสอบให้แก้ไข", isPresented: $confirmReopen, titleVisibility: .visible) {
            Button("แก้ไข") { job.updateIEC(context, evenWhenLocked: true) { $0.reopen() } }
            Button("ยกเลิก", role: .cancel) {}
        } message: { Text("ผลที่สรุปไว้จะถูกยกเลิก ต้องส่งผลให้ทีมและให้ทีมภายในปิดอีกครั้งหลังแก้") }
        .alert("ส่งกลับให้ผู้รับเหมาแก้", isPresented: $sendingBack) {
            TextField("สิ่งที่ต้องแก้", text: $sendBackNote)
            Button("ส่งกลับ") {
                let note = sendBackNote
                job.updateIEC(context, evenWhenLocked: true) { _ = $0.sendBack(by: job.iecActor, note: note) }
                sendBackNote = ""
            }
            Button("ยกเลิก", role: .cancel) { sendBackNote = "" }
        } message: { Text("ผลที่ส่งมาจะเปิดให้แก้อีกครั้ง แผน MP ยังไม่นับ 3.1") }
        .alert("ส่งออกไม่ได้", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("ตกลง", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .navigationDestination(item: $grid) { IECStringGrid(job: job, inverter: $0.inverter, phase: $0.phase, page: $0.page) }
        .navigationDestination(item: $step2) { IECVIPage(job: job, phase: $0.phase, inverter: $0.inverter, slot: $0.slot, openStage: open) }
        .navigationDestination(item: $sheetPreview) { IECSheetPreview(job: job, inverter: $0.inverter, phase: $0.phase, open: openFromSheet) }
        .navigationDestination(isPresented: $step1) { IECSetupPage(job: job, openStage: open, leave: leaveFromSetup) }
        #if DEBUG
        .task {
            guard !debugApplied else { return }
            debugApplied = true
            // `-iecClear YES`: the station starts with no test, its photos removed (for good)
            if Debug.clear { for p in job.iecPhotos where p.tag != Job.keyPlanTag { context.delete(p) }; job.iecReport = nil; try? context.save() }
            if Debug.step2 { job.seedIECStep2Demo(context: context) }
            else if Debug.step4 { job.seedIECStep4Demo(context: context) }
            else if Debug.praek { job.seedIECDemo(replacing: true); job.seedIECStep1Demo(context: context) }
            else if Debug.demo { job.seedIECDemo(replacing: Debug.demoReset || Debug.demoFull, full: Debug.demoFull ? context : nil); try? context.save() }
            if let line = Debug.stationLine { job.updateIEC(context) { $0.stationLine = line; $0.sampleName = nil } }  // a real test with that line
            // after the seed, so the sheet starts from it, and after the push, which a sheet would cut short
            try? await Task.sleep(for: .milliseconds(700))
            if Debug.setup { setup = true }
            if Debug.step2 { step2 = Step2Target(inverter: 0) }
            if Debug.step4 { step2 = Step2Target(inverter: 0, phase: .after) }
            if Debug.step1 { step1 = true }
            if let s = Debug.sheet {
                // after the install page and this screen have settled: a third push at once is dropped
                try? await Task.sleep(for: .milliseconds(900))
                sheetPreview = s
            }
            if let n = Debug.inverter, (job.iecReport?.inverters.count ?? 0) >= n { grid = GridTarget(inverter: n - 1, phase: Debug.phase, page: Debug.page) }
        }
        #endif
    }

    /// The install-page version: status, progress and setup actions inside the content, with no second screen header.
    private func embeddedOverview(_ report: IECReport) -> some View {
        let complete = IECReport.Stage.allCases.filter { $0 != .review && report.isDone($0) }.count
        let (status, kind): (String, TCStatusChip.Kind) = if report.resultIsStale {
            ("נדרש עדכון", .pending)
        } else if report.result != nil {
            ("ปิดการทดสอบแล้ว", .done)
        } else if report.isAwaitingClose {
            ("รอทีมภายในปิด", .active)
        } else {
            ("กำลังตรวจ", .pending)
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ภาพรวมการทดสอบ").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                        .accessibilityAddTraits(.isHeader)
                    Text(report.stationLine.isEmpty ? job.stationName : report.stationLine)
                        .font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                    Text("\(report.inverters.count) Inverter · \(report.stringCount) สตริง · \(IECFormat.number(report.installedKWp)) kWp")
                        .font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.primary)
                }
                Spacer(minLength: 8)
                TCProgressRing(.percent(report.completion), size: 58)
            }
            HStack(spacing: 10) {
                TCStatusChip(status, kind: kind)
                Text("ครบ \(complete)/6 ขั้น").font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 8)
                if !report.isLocked {
                    Button { showSetup() } label: { Label("ตั้งค่า", systemImage: "slider.horizontal.3") }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card))
                }
                if sizeClass == .regular {
                    Button { sheetPreview = SheetTarget(inverter: 0) } label: { Label("ดูชีต Excel", systemImage: "tablecells") }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card))
                }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tcCard()
    }

    /// Embedded submit/export actions scroll with the report, leaving the app's dock as the only pinned bottom bar.
    private func embeddedFooter(_ report: IECReport) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: report.result != nil ? "checkmark.seal.fill" : report.isAwaitingClose ? "paperplane.fill" : "square.and.pencil")
                    .foregroundStyle(report.result != nil ? Theme.successInk : Theme.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(report.result != nil ? "ผลทดสอบสรุปแล้ว" : report.isAwaitingClose ? "ส่งผลให้ทีมแล้ว" : "บันทึกอัตโนมัติ")
                        .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    Text(report.result.map { Self.stamp($0.completedAt, $0.by) }
                         ?? report.submission.map { Self.stamp($0.submittedAt, $0.by) }
                         ?? "ความคืบหน้า \(Int((report.completion * 100).rounded()))%")
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 8)
                if let result = report.result {
                    TCStatusChip(result.passed ? "ผ่าน" : "ไม่ผ่าน",
                                 fill: result.passed ? Theme.successSoft : Theme.dangerSoft,
                                 text: result.passed ? Theme.successInk : Theme.dangerText)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                Button { startExport(.word) } label: { Label(makingWord ? "กำลังทำ Word…" : "ส่งออก Word ภาพถ่าย", systemImage: "doc.richtext").frame(maxWidth: .infinity) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).disabled(makingWord)
                Button { startExport(.excel) } label: { Label("ส่งออก Excel IEC 62446", systemImage: "tablecells").frame(maxWidth: .infinity) }
                    .buttonStyle(TCButtonStyle(report.isLocked || !report.isDone(.review) ? .primary : .secondary, size: .card))
                if !report.isLocked, permissions.can(.iecFillSubmit, on: job.access) {
                    Button(action: submit) { Label("ส่งผลให้ทีม", systemImage: "paperplane").frame(maxWidth: .infinity) }
                        .buttonStyle(TCButtonStyle(.primary, size: .card))
                        .disabled(!report.isDone(.review))
                        .accessibilityHint(report.isDone(.review) ? "ส่งผลให้ทีมภายในตรวจและปิด" : "ทำขั้นที่ 1–6 ให้ครบก่อน")
                } else if report.isAwaitingClose, permissions.can(.iecClose, on: job.access) {
                    Button { sendingBack = true } label: { Label("ส่งกลับให้แก้", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card))
                    Button(action: complete) { Label("ปิดการทดสอบ", systemImage: "checkmark.seal").frame(maxWidth: .infinity) }
                        .buttonStyle(TCButtonStyle(.primary, size: .card)).disabled(report.submissionIsStale)
                } else if report.result != nil, permissions.can(.iecClose, on: job.access) {
                    Button { confirmReopen = true } label: { Label("แก้ไขผลทดสอบ", systemImage: "lock.open").frame(maxWidth: .infinity) }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card))
                }
            }
        }
        .padding(Space.l)
        .tcCard()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.badge.checkmark").font(.system(size: 44)).foregroundStyle(Theme.primary)
            Text("ยังไม่ได้ตั้งค่า inverter และสตริง").font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy)
            Text("ใส่ inverter แต่ละเครื่อง และจำนวนแผงของแต่ละช่องสตริง ตามแผ่น Excel ของ กปภ.")
                .font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
            Button { showSetup() } label: { Label("ตั้งค่าการทดสอบ", systemImage: "slider.horizontal.3") }
                .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: stats

    private func stats(_ r: IECReport) -> some View {
        HStack(spacing: 12) {
            stat("กำลังติดตั้ง", IECFormat.number(r.installedKWp), unit: "kWp",
                 note: r.module.brand.isEmpty ? "\(r.moduleCount) แผง" : "\(r.module.brand) \(IECFormat.number(r.module.powerW, digits: 0)) W × \(r.moduleCount) แผง")
            stat("Inverter / สตริง", "\(r.inverters.count) / \(r.stringCount)", unit: nil,
                 note: r.inverters.map { IECFormat.kW($0.ratedKW) }.joined(separator: " + "))
            stat("ค่าที่วัดแล้ว", "\(r.readings.done) / \(r.readings.total)", unit: nil, note: "Voc, I, IR, Vmp, Imp")
            stat("รูปถ่าย", "\(r.photos.done) / \(r.photos.total)", unit: nil, note: "สตริงละ 5 รูป + ความเข้มแสง")
        }
    }

    private func stat(_ label: String, _ value: String, unit: String?, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.sarabunFixed(26, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                if let unit { Text(unit).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy) }
            }
            Text(note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tcCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: inverters

    private func inverterCards(_ r: IECReport) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
            ForEach(Array(r.inverters.enumerated()), id: \.offset) { i, inv in inverterCard(r, i, inv) }
        }
    }

    /// `16 สตริง | 4 × 16 + 4 × 12 แผง`: strings grouped by their module count, in slot order.
    static func stringSummary(_ inv: IECReport.Inverter) -> String {
        var order: [Int] = [], count: [Int: Int] = [:]
        for s in inv.strings.map(\.value.modules) { if count[s] == nil { order.append(s) }; count[s, default: 0] += 1 }
        return "\(inv.strings.count) สตริง | " + order.map { "\(count[$0] ?? 0) × \($0)" }.joined(separator: " + ") + " แผง"
    }

    private func inverterCard(_ r: IECReport, _ i: Int, _ inv: IECReport.Inverter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Inverter \(i + 1) | \(IECFormat.kW(inv.ratedKW))").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                if !inv.serial.isEmpty { Text("S/N " + inv.serial).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted) }
                Spacer(minLength: 6)
                Text("\(IECFormat.number(r.installedKWp(inv))) kWp").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                    .padding(.horizontal, 10).frame(height: 26).background(Theme.primarySoft, in: Capsule())
            }
            Text(Self.stringSummary(inv)).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            phaseBand("ก่อนการเชื่อมต่อระบบ", target: .init(inverter: i, phase: .before)) {
                IECBar(title: "Voc / กระแส", tally: r.tally(inv, .vocAndCurrent))
                IECBar(title: "IR (MΩ)", tally: r.tally(inv, .insulation))
            }
            phaseBand("หลังการเชื่อมต่อระบบ", target: .init(inverter: i, phase: .after)) {
                IECBar(title: "Vmp / Imp", tally: r.tally(inv, .vmpAndImp))
                let pr = r.pr(inv)
                IECBar(title: "PR (คำนวณ)", tally: .init(pr == nil ? 0 : 1, 1), value: pr.map { IECFormat.number($0) } ?? "—")
            }
        }
        .padding(Space.l)
        .tcCard()
    }

    /// The green band of a phase and its bars; tapped, it opens that phase's string table.
    private func phaseBand<Content: View>(_ title: String, target: GridTarget, @ViewBuilder _ content: () -> Content) -> some View {
        Button { show(target) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primary)
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(Theme.paperBand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                content().padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("เปิดตารางสตริง")
    }

    // MARK: steps

    /// The 7 steps of the board: what each lacks, who confirmed it, and the files exported (step 7).
    private func stagesCard(_ r: IECReport) -> some View {
        let open = IECReport.Stage.allCases.filter { $0 != .review && !r.isDone($0) }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("ขั้นตอนการทดสอบ").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                Text(open == 0 ? "ครบ 6/6" : "● ยังขาด \(open) ขั้น").font(.sarabunFixed(13, .bold))
                    .foregroundStyle(open == 0 ? Theme.successInk : Theme.warningInk)
                    .padding(.horizontal, 10).frame(height: 26).background(open == 0 ? Theme.successSoft : Theme.pendingSoft, in: Capsule())
            }
            ForEach(IECReport.Stage.allCases) { stageRow(r, $0) }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tcCard()
    }

    /// The before phase's table is step 2's page on iPad; the rest, and the iPhone, open the string table.
    private func show(_ target: GridTarget) {
        if target.page == .table, sizeClass == .regular {
            step2 = Step2Target(inverter: target.inverter, slot: job.iecReport?.inverters[safe: target.inverter]?.strings.first?.slot ?? 1, phase: target.phase)
        } else {
            grid = target
        }
    }

    /// Another step from step 2's page: back to this overview first, then that step's screen (a push on top of the
    /// page would be the fourth in a row, which SwiftUI drops).
    private func open(_ stage: IECReport.Stage) {
        let inverter = step2?.inverter ?? 0
        let fromSetup = step1
        step2 = nil
        step1 = false
        let target: GridTarget? = switch stage {
        case .beforeInsulation: .init(inverter: inverter, phase: .before)
        case .afterVoltage: nil
        case .energy: .init(inverter: inverter, phase: .after, page: .performance)
        case .thermal: .init(inverter: inverter, phase: .after, page: .photos)
        case .setup, .beforeVoltage, .review: nil
        }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if stage == .setup { showSetup() }
            else if stage == .beforeVoltage, fromSetup { show(.init(inverter: 0, phase: .before)) }
            // step 4 is the after phase's page on iPad, the after table on iPhone
            else if stage == .afterVoltage { show(.init(inverter: inverter, phase: .after)) }
            else if let target { grid = target }
        }
    }

    /// A tinted cell or a legend swatch of the sheet preview: off the preview, then that step at its inverter (and the
    /// string, for a column cell). Steps without a page yet open their existing screen.
    private func openFromSheet(_ stage: IECReport.Stage, _ inverter: Int, _ slot: Int?) {
        sheetPreview = nil
        let first = job.iecReport?.inverters[safe: inverter]?.strings.first?.slot ?? 1
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            switch stage {
            case .setup: showSetup()
            case .beforeVoltage: step2 = Step2Target(inverter: inverter, slot: slot ?? first, phase: .before)
            case .afterVoltage: step2 = Step2Target(inverter: inverter, slot: slot ?? first, phase: .after)
            case .beforeInsulation: grid = GridTarget(inverter: inverter, phase: .before)
            case .energy: grid = GridTarget(inverter: inverter, phase: .after, page: .performance)
            case .thermal: grid = GridTarget(inverter: inverter, phase: .after, page: .photos)
            case .review: break
            }
        }
    }

    /// Step 1: the page on iPad, the sheet on iPhone.
    func showSetup() {
        if sizeClass == .regular { step1 = true } else { setup = true }
    }

    /// Step 1's `‹ กลับ งานติดตั้ง`: off the page and the overview, back to the install page.
    private func leaveFromSetup() {
        step1 = false
        Task { try? await Task.sleep(for: .milliseconds(450)); dismiss() }
    }

    /// Where `แก้ ›` leads for a step.
    private func go(_ r: IECReport, _ stage: IECReport.Stage) -> (() -> Void)? {
        func first(_ reading: IECReport.Reading?, _ phase: IECReport.Phase, page: IECStringGrid.Page = .table) -> () -> Void {
            let i = reading.flatMap { k in r.inverters.firstIndex { !r.tally($0, k).isComplete } } ?? 0
            return { grid = .init(inverter: i, phase: phase, page: page) }
        }
        let readingsDone: (IECReport.Reading) -> Bool = { k in r.inverters.allSatisfy { r.tally($0, k).isComplete } }
        switch stage {
        case .setup: return { showSetup() }
        case .beforeVoltage:
            if readingsDone(.vocAndCurrent) && !r.before.isComplete { return first(nil, .before, page: .conditions) }
            let i = r.inverters.firstIndex { !r.beforeVITally($0).isComplete } ?? 0
            return { show(.init(inverter: i, phase: .before)) }
        case .beforeInsulation: return first(.insulation, .before)
        case .afterVoltage:
            if readingsDone(.vmpAndImp) && !r.after.isComplete { return first(nil, .after, page: .conditions) }
            let i = r.inverters.firstIndex { !r.viTally($0, .after).isComplete } ?? 0
            return { show(.init(inverter: i, phase: .after)) }
        case .energy: return { grid = .init(inverter: r.inverters.firstIndex { $0.energy7dKWh == nil } ?? 0, phase: .after, page: .performance) }
        case .thermal: return first(nil, .after, page: .photos)
        case .review: return nil
        }
    }

    private func stageRow(_ r: IECReport, _ stage: IECReport.Stage) -> some View {
        let missing = r.missing(stage), done = missing.isEmpty, confirmed = r.record(stage)
        let detail: String = if stage == .review {
            done ? exportLine(r) : missing.joined(separator: " | ")
        } else if let confirmed {
            "ยืนยันแล้ว " + Self.stamp(confirmed.confirmedAt, confirmed.by)
        } else {
            done ? "ครบ | ยังไม่ได้ยืนยัน" : "ขาด " + missing.joined(separator: " | ")
        }
        let action = done ? nil : go(r, stage)
        return HStack(spacing: 12) {
            // ✓ once confirmed (or the closed step 7); a done step still waiting keeps its number in green
            let sealed = confirmed != nil || (stage == .review && r.isLocked)
            Text(sealed ? "✓" : "\(stage.rawValue)").font(.sarabunFixed(15, .bold))
                .foregroundStyle(sealed ? Theme.onPrimary : done ? Theme.successInk : Theme.warningInk)
                .frame(width: 32, height: 32).background(sealed ? Theme.success : done ? Theme.successSoft : Theme.pendingSoft, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(stage.title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Text(detail).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            Spacer(minLength: 8)
            if stage == .review, sizeClass == .regular {
                Button("ดูชีต Excel") { sheetPreview = SheetTarget(inverter: 0) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
            }
            if done, confirmed == nil, stage != .review, !r.isLocked {
                Button("ยืนยัน") { job.updateIEC(context) { _ = $0.confirm(stage, by: job.iecActor) } }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                    .accessibilityLabel("ยืนยันขั้น \(stage.title)")
            } else if let action, !r.isLocked {
                Button("แก้ ›", action: action).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("ไปกรอก \(stage.title)")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 56)
        .background(done ? Theme.surface : Theme.pendingSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// Step 7's line: the last Excel and Word, and whether the values changed since.
    private func exportLine(_ r: IECReport) -> String {
        let parts = [(IECReport.ExportRecord.Kind.excel, "Excel"), (.word, "Word")].map { kind, name -> String in
            guard let last = r.lastExport(kind) else { return "ยังไม่ได้ส่งออก \(name)" }
            return "\(name) " + Self.stamp(last.record.at, "") + (last.current ? " ✓" : " | ข้อมูลเปลี่ยนแล้ว ควรส่งออกใหม่")
        }
        return parts.joined(separator: " | ")
    }
}
