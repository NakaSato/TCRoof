import SwiftUI
import TCRoofUI
import TCRoofCore
import ExcelExport

/// `ทดสอบระบบ IEC 62446` (docs/ui/iec62446-test screen 1): how complete each inverter is before and after the grid
/// connection, and what is still missing before the export. An inverter's band opens its string table (screen 2).
/// Opened from the install tracking page's tab.
struct IECTestScreen: View {
    @Bindable var job: Job
    @State private var setup = false
    @State private var grid: GridTarget?
    @State private var exported: ExportedFile?
    @State private var exportError: String?
    @Environment(\.modelContext) private var context

    struct ExportedFile: Identifiable { let url: URL; var id: URL { url } }

    /// The string table of one inverter and phase.
    struct GridTarget: Hashable { let inverter: Int; let phase: IECReport.Phase; var page: IECStringGrid.Page = .table }

    var body: some View {
        let report = job.iecReport
        VStack(spacing: 0) {
            IECHeader(title: "ทดสอบระบบ IEC 62446", subtitle: (report?.stationLine).flatMap { $0.isEmpty ? nil : $0 } ?? job.stationName) {
                IECHeaderButton(title: report == nil ? "ตั้งค่าการทดสอบ" : "ตั้งค่า", symbol: "slider.horizontal.3") { setup = true }
                if report?.inverters.isEmpty == false { IECHeaderButton(title: "ส่งออก", symbol: "square.and.arrow.up") { exportExcel() } }
            }
            if let report, !report.inverters.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        stats(report)
                        inverterCards(report)
                        missingCard(report)
                    }
                    .padding(24)
                }
                .scrollIndicators(.hidden)
                bottomBar(report)
            } else {
                emptyState
            }
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $setup) { IECSetupSheet(report: job.iecReport ?? job.newIECReport) { r in job.updateIEC(context) { $0 = r } } }
        .sheet(item: $exported) { ActivitySheet(items: [$0.url]) }
        .alert("ส่งออกไม่ได้", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("ตกลง", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .navigationDestination(item: $grid) { IECStringGrid(job: job, inverter: $0.inverter, phase: $0.phase, page: $0.page) }
        #if DEBUG
        .task {
            if Debug.demo { job.seedIECDemo() }
            // after the seed, so the sheet starts from it, and after the push, which a sheet would cut short
            try? await Task.sleep(for: .milliseconds(700))
            if Debug.setup { setup = true }
            if let n = Debug.inverter, (job.iecReport?.inverters.count ?? 0) >= n { grid = GridTarget(inverter: n - 1, phase: Debug.phase, page: Debug.page) }
        }
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.badge.checkmark").font(.system(size: 44)).foregroundStyle(Theme.primary)
            Text("ยังไม่ได้ตั้งค่า inverter และสตริง").font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy)
            Text("ใส่ inverter แต่ละเครื่อง และจำนวนแผงของแต่ละช่องสตริง ตามแผ่น Excel ของ กปภ.")
                .font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
            Button { setup = true } label: { Label("ตั้งค่าการทดสอบ", systemImage: "slider.horizontal.3") }
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        .accessibilityElement(children: .combine)
    }

    // MARK: inverters

    private func inverterCards(_ r: IECReport) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
            ForEach(Array(r.inverters.enumerated()), id: \.offset) { i, inv in inverterCard(r, i, inv) }
        }
    }

    /// `16 สตริง · 4 × 16 + 4 × 12 แผง`: strings grouped by their module count, in slot order.
    static func stringSummary(_ inv: IECReport.Inverter) -> String {
        var order: [Int] = [], count: [Int: Int] = [:]
        for s in inv.strings.map(\.value.modules) { if count[s] == nil { order.append(s) }; count[s, default: 0] += 1 }
        return "\(inv.strings.count) สตริง · " + order.map { "\(count[$0] ?? 0) × \($0)" }.joined(separator: " + ") + " แผง"
    }

    private func inverterCard(_ r: IECReport, _ i: Int, _ inv: IECReport.Inverter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Inverter \(i + 1) · \(IECFormat.kW(inv.ratedKW))").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
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
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    /// The green band of a phase and its bars; tapped, it opens that phase's string table.
    private func phaseBand<Content: View>(_ title: String, target: GridTarget, @ViewBuilder _ content: () -> Content) -> some View {
        Button { grid = target } label: {
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

    // MARK: missing

    private func missingCard(_ r: IECReport) -> some View {
        let missing = r.missing
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("ยังขาดก่อนส่งออก").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                if !missing.isEmpty {
                    Text("● \(missing.count) รายการ").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.warningInk)
                        .padding(.horizontal, 10).frame(height: 26).background(Theme.pendingSoft, in: Capsule())
                }
            }
            if missing.isEmpty {
                Label("ครบทุกรายการ", systemImage: "checkmark.circle.fill").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.successInk)
            }
            ForEach(Array(missing.enumerated()), id: \.offset) { _, m in missingRow(r, m) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    /// Where `ไปกรอก` leads: a string table for readings, the performance page for the energy, the conditions page,
    /// and the set-up for the module area and the record.
    private func go(_ r: IECReport, _ m: IECReport.Missing) -> (() -> Void)? {
        func firstShort(_ reading: IECReport.Reading, _ phase: IECReport.Phase) -> (() -> Void)? {
            guard let i = r.inverters.firstIndex(where: { !r.tally($0, reading).isComplete }) else { return nil }
            return { grid = .init(inverter: i, phase: phase) }
        }
        switch m {
        case .insulation: return firstShort(.insulation, .before)
        case .vocAndCurrent: return firstShort(.vocAndCurrent, .before)
        case .vmpAndImp: return firstShort(.vmpAndImp, .after)
        case .checks: return { grid = .init(inverter: 0, phase: .before) }
        case .moduleArea, .testRecord: return { setup = true }
        case .energy: return { grid = .init(inverter: r.inverters.firstIndex { $0.energy7dKWh == nil } ?? 0, phase: .after, page: .performance) }
        case .conditions: return { grid = .init(inverter: 0, phase: .before, page: .conditions) }
        }
    }

    private func missingRow(_ r: IECReport, _ m: IECReport.Missing) -> some View {
        let action = go(r, m)
        return Button { action?() } label: {
            HStack(spacing: 10) {
                Circle().fill(Theme.pending).frame(width: 8, height: 8)
                Text(m.title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Spacer(minLength: 8)
                if action != nil { Text("ไปกรอก ›").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary) }
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(Theme.pendingSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    // MARK: bottom bar

    private func bottomBar(_ r: IECReport) -> some View {
        HStack(spacing: 12) {
            IECRing(fraction: r.completion, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("บันทึกอัตโนมัติ").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Text("ความคืบหน้ารวม \(Int((r.completion * 100).rounded()))%").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            if !r.missing.isEmpty {
                Text("ยังขาด \(r.missing.count) รายการ · ส่งออกได้ ช่องที่ยังไม่มีค่าจะว่างไว้").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            Button { exportExcel() } label: { Label("ส่งออก Excel IEC 62446", systemImage: "tablecells") }
                .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    // MARK: export

    /// The PWA's own workbook with this test typed in (`IECExcel`): kept in the job's documents under `IEC 62446`
    /// (so it goes to Drive with them), then offered to the share sheet; both are the same file.
    private func exportExcel() {
        guard let r = job.iecReport else { return }
        do {
            let data = try IECExcel.export(r)
            let name = IECExcel.fileName(station: job.stationName, date: r.testDate ?? .now)
            for old in job.documents where old.name == name { context.delete(old) }
            let doc = DocumentAsset(name: name, data: data)
            doc.folderPath = "IEC 62446"
            context.insert(doc)
            doc.job = job
            try? context.save()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            exported = ExportedFile(url: url)
        } catch let f as IECExcel.Failure {
            exportError = f.message
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: DEBUG

    /// `-iecDemo YES` seeds the sample, `-iecSetup YES` opens the set-up, `-iecInverter n -iecPhase before|after`
    /// opens a string table (`-iecPage performance|conditions|photos` another page of it), `-iecSlot n` selects its
    /// slot and `-iecEntry YES` opens that string in `กรอกทีละสตริง`.
    enum Debug {
        #if DEBUG
        static let demo = UserDefaults.standard.bool(forKey: "iecDemo")
        static let setup = UserDefaults.standard.bool(forKey: "iecSetup")
        static let inverter: Int? = UserDefaults.standard.object(forKey: "iecInverter") == nil ? nil : UserDefaults.standard.integer(forKey: "iecInverter")
        static let phase = UserDefaults.standard.string(forKey: "iecPhase").flatMap(IECReport.Phase.init) ?? .before
        static let slot: Int? = UserDefaults.standard.object(forKey: "iecSlot") == nil ? nil : UserDefaults.standard.integer(forKey: "iecSlot")
        static let page: IECStringGrid.Page = switch UserDefaults.standard.string(forKey: "iecPage") {
        case "performance": .performance
        case "conditions": .conditions
        case "photos": .photos
        default: .table
        }
        static let entry = UserDefaults.standard.bool(forKey: "iecEntry")
        #else
        static let entry = false
        static let setup = false
        static let slot: Int? = nil
        #endif
    }
}
