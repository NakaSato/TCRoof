import SwiftUI
import TCRoofUI
import TCRoofCore

/// One inverter's strings before or after the grid connection, laid out as the PWA's Excel sheet (docs/ui/iec62446-test
/// screen 2): 10 MPPT × 2 slots, one row per test item. A reading is typed by tapping its cell; polarity and the
/// inverter-wide checks toggle in place. The side list switches inverter and phase.
struct IECStringGrid: View {
    @Bindable var job: Job
    @State var inverter: Int
    @State var phase: IECReport.Phase
    /// The selected slot, 1…20.
    @State var selected: Int? = IECTestScreen.Debug.slot
    @State var editing: Cell?
    @State private var page: Page
    /// The string opened in `กรอกทีละสตริง`.
    @State var entry: EntryTarget?
    /// `-iecEntry` opens the string once, not again when the cover closes.
    @State private var debugApplied = false
    @Environment(\.modelContext) private var context

    /// What the side list shows: an inverter's table or its performance, or the station's conditions or photos.
    enum Page: Hashable { case table, performance, conditions, photos, install }

    struct EntryTarget: Identifiable { let slot: Int; var id: Int { slot } }

    init(job: Job, inverter: Int, phase: IECReport.Phase, page: Page = .table) {
        self.job = job
        _inverter = State(initialValue: inverter)
        _phase = State(initialValue: phase)
        _page = State(initialValue: page)
    }

    enum Row: Hashable { case label, modules, polarity, testV, voltage, current, photos, insulation }

    /// A cell being typed into.
    struct Cell: Hashable { let row: Row; let slot: Int }

    func rows(_ p: IECReport.Phase) -> [Row] {
        p == .before ? [.label, .modules, .polarity, .testV, .voltage, .current, .photos, .insulation]
                     : [.label, .modules, .voltage, .current, .photos]
    }

    func title(_ row: Row) -> String {
        switch row {
        case .label: "ป้ายรูป (Word)"
        case .modules: "จำนวนแผง"
        case .polarity: "Polarity"
        case .testV: "Test Voltage (V)"
        case .voltage: phase == .before ? "String Voltage (V)" : "Vmp (V)"
        case .current: phase == .before ? "String Current (A)" : "Imp (A)"
        case .photos: "รูป V + I"
        case .insulation: "IR +E / −E (MΩ)"
        }
    }

    var body: some View {
        let report = job.iecReport ?? job.newIECReport
        let index = min(inverter, max(report.inverters.count - 1, 0))
        VStack(spacing: 0) {
            if report.inverters.indices.contains(index) {
                let inv = report.inverters[index]
                header(report, inv, index)
                HStack(spacing: 0) {
                    sidebar(report)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if report.isLocked { lockedNotice(report) }
                            Group {
                                switch page {
                                case .table:
                                    summary(report, inv)
                                    table(report, inv, index)
                                    legend
                                case .performance: IECPerformancePage(job: job, inverter: index)
                                case .conditions: IECConditionsPage(job: job)
                                case .photos: IECStationPhotosPage(job: job)
                                case .install: IECInstallPhotosPage(job: job, readOnly: report.isLocked)
                                }
                            }
                            // a closed test is read only; the side list still switches pages (and report 9 still makes its PDF)
                            .disabled(report.isLocked && page != .install)
                        }
                        .padding(20)
                    }
                    .scrollIndicators(.hidden)
                }
                switch page {
                case .table: bottomBar(inv, index).disabled(report.isLocked)
                case .performance: performanceBar(report, index)
                case .conditions, .photos, .install: EmptyView()
                }
            }
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // a cover, not a push: a fourth push in a row (install page → test → table → string) is dropped by SwiftUI
        .fullScreenCover(item: $entry) { IECStringEntry(job: job, inverter: inverter, phase: phase, slot: $0.slot) }
        #if DEBUG
        .task {
            guard !debugApplied else { return }
            debugApplied = true
            try? await Task.sleep(for: .milliseconds(1200))
            if IECTestScreen.Debug.entry, let s = selected { entry = EntryTarget(slot: s) }
        }
        #endif
    }

    @ViewBuilder private func header(_ r: IECReport, _ inv: IECReport.Inverter, _ index: Int) -> some View {
        switch page {
        case .table:
            IECHeader(title: "Inverter \(index + 1) | \(IECFormat.kW(inv.ratedKW))",
                      subtitle: [inv.serial.isEmpty ? nil : "S/N " + inv.serial, "\(inv.strings.count) สตริง",
                                 "\(IECFormat.number(r.installedKWp(inv))) kWp"].compactMap { $0 }.joined(separator: " | ")) {
                IECPhaseSwitch(phase: $phase)
            }
        case .performance:
            IECHeader(title: "System Performance | Inverter \(index + 1)",
                      subtitle: "หลังการเชื่อมต่อระบบ | \(IECFormat.number(r.installedKWp(inv))) kWp") { EmptyView() }
        case .conditions:
            IECHeader(title: "สภาพการทดสอบและเครื่องมือ", subtitle: r.stationLine) { EmptyView() }
        case .photos:
            IECHeader(title: "ความเข้มแสงและภาพความร้อน", subtitle: r.stationLine) { EmptyView() }
        case .install:
            IECHeader(title: "9 ภาพถ่ายติดตั้งระบบ", subtitle: "รายงานภาพถ่ายติดตั้งระบบผลิตไฟฟ้า | " + job.stationName) { EmptyView() }
        }
    }

    private func lockedNotice(_ r: IECReport) -> some View {
        Label((r.lockedLine ?? "") + (r.result != nil ? " กด แก้ไข ที่หน้าภาพรวมเพื่อเปิดให้แก้" : ""), systemImage: "lock.fill")
            .font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.successInk)
            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// `Inverter 2 ›` to the next inverter's performance.
    private func performanceBar(_ r: IECReport, _ index: Int) -> some View {
        HStack(spacing: 12) {
            Text("กรอกพลังงาน 7 วันและค่าแสง แอปคำนวณ Yf, PR และประสิทธิภาพให้").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            Spacer()
            if index + 1 < r.inverters.count {
                Button("Inverter \(index + 2) ›") { inverter = index + 1 }.buttonStyle(TCButtonStyle(.primary, size: .card))
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    func save(_ change: @escaping (inout IECReport.Inverter) -> Void) {
        let i = inverter
        job.updateIEC(context) { r in if r.inverters.indices.contains(i) { change(&r.inverters[i]) } }
    }

    // MARK: side list

    private func sidebar(_ r: IECReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(r.inverters.enumerated()), id: \.offset) { i, inv in
                    Text("Inverter \(i + 1) | \(IECFormat.kW(inv.ratedKW))").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
                        .padding(.top, i == 0 ? 0 : 12).padding(.horizontal, 8)
                    sideItem(i, .before, "ตารางสตริง ก่อนเชื่อมต่อ", r.tally(inv, .vocAndCurrent), r.tally(inv, .insulation))
                    sideItem(i, .after, "ตารางสตริง หลังเชื่อมต่อ", r.tally(inv, .vmpAndImp), nil)
                    performanceItem(r, i, inv)
                }
                Text("ทั้งสถานี").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted).padding(.top, 12).padding(.horizontal, 8)
                stationItem(.conditions, "สภาพ", "สภาพการทดสอบ เครื่องมือ", done: conditionsDone(r), total: 7)
                stationItem(.photos, "รูป", "ความเข้มแสง ภาพความร้อน",
                            done: (r.irradiancePhoto == nil ? 0 : 1) + (r.thermalPhotos.isEmpty ? 0 : 1), total: 2)
                stationItem(.install, "9", "ภาพถ่ายติดตั้งระบบ", done: r.installTally.done, total: r.installTally.total)
            }
            .padding(12)
        }
        .frame(width: 268)
        .background(Theme.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }

    /// Before counts Voc, current and IR a string (3 each); after counts Vmp and Imp (2 each).
    private func sideItem(_ i: Int, _ p: IECReport.Phase, _ title: String, _ a: IECReport.Tally, _ b: IECReport.Tally?) -> some View {
        let done = a.done * 2 + (b?.done ?? 0), total = a.total * 2 + (b?.total ?? 0)
        let on = page == .table && i == inverter && p == phase
        return Button { inverter = i; phase = p; selected = nil; page = .table } label: {
            HStack(spacing: 10) {
                IECRing(fraction: total > 0 ? Double(done) / Double(total) : 0)
                Text(p == .before ? "ก่อน" : "หลัง").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).frame(width: 34, alignment: .leading)
                Text(title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
                Spacer(minLength: 4)
                Text("\(done)/\(total)").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            }
            .padding(.horizontal, 10).frame(minHeight: 56)
            .background(on ? Theme.primarySoft.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// `ผลการผลิต x/6`: energy, Yr, array temperature, module area, the inverter check, and every Vmp / Imp.
    private func performanceItem(_ r: IECReport, _ i: Int, _ inv: IECReport.Inverter) -> some View {
        let done = [inv.energy7dKWh != nil, r.yrKWhM2Day != nil, r.arrayTempC != nil, r.module.areaM2 != nil,
                    inv.functionalAfter != nil, r.tally(inv, .vmpAndImp).isComplete].filter { $0 }.count
        let on = page == .performance && i == inverter
        return listItem(on: on, short: "PR", title: "ผลการผลิต", done: done, total: 6) { inverter = i; page = .performance }
    }

    /// The weather of both phases, the test date, the tester and three instruments.
    private func conditionsDone(_ r: IECReport) -> Int {
        [r.before.isComplete, r.after.isComplete, r.testDate != nil, !r.tester.isEmpty, !r.instruments.multimeterClamp.isEmpty,
         !r.instruments.insulationTester.isEmpty, !r.instruments.irradianceMeter.isEmpty].filter { $0 }.count
    }

    private func stationItem(_ p: Page, _ short: String, _ title: String, done: Int, total: Int) -> some View {
        listItem(on: page == p, short: short, title: title, done: done, total: total) { page = p }
    }

    private func listItem(on: Bool, short: String, title: String, done: Int, total: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IECRing(fraction: total > 0 ? Double(done) / Double(total) : 0)
                Text(short).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8).frame(width: 34, alignment: .leading)
                Text(title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
                Spacer(minLength: 4)
                Text("\(done)/\(total)").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            }
            .padding(.horizontal, 10).frame(minHeight: 56)
            .background(on ? Theme.primarySoft.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: summary line

    private func summary(_ r: IECReport, _ inv: IECReport.Inverter) -> some View {
        let c = phase == .before ? r.before : r.after
        let conditions = [c.ambientC.map { "อากาศ \(IECFormat.number($0, digits: 1)) °C" }, c.irradianceWm2.map { "\(IECFormat.number($0, digits: 0)) W/m²" },
                          c.time].compactMap { $0 }
        return HStack(spacing: 8) {
            if phase == .before {
                let voc = r.tally(inv, .vocAndCurrent)
                pill(voc.isComplete ? "✓ Voc ครบ \(voc.done)/\(voc.total)" : "Voc \(voc.done)/\(voc.total)", voc.isComplete ? .ok : .warn)
                let outliers = r.vocOutliers(inv)
                let worst = inv.strings.compactMap { r.vocDeviation(inv, slot: $0.slot) }.map(abs).max()
                if !outliers.isEmpty {
                    pill("Voc ต่างจากค่ากลางเกิน 5% | \(outliers.count) สตริง", .danger)
                } else if let worst {
                    pill("ต่างจากค่ากลางไม่เกิน \(IECFormat.number(worst * 100, digits: 1))%", .ok)
                }
                let ir = r.tally(inv, .insulation)
                switch r.irSummary(inv) {
                case .normal?: pill("IR ผ่านทุกสตริง", .ok)
                case .abnormal?: pill("IR ต่ำกว่า 1 MΩ", .danger)
                case nil: pill("● IR MΩ ยังขาด \(ir.total - ir.done)", .warn)
                }
            } else {
                let t = r.tally(inv, .vmpAndImp)
                pill(t.isComplete ? "✓ Vmp / Imp ครบ \(t.done)/\(t.total)" : "● Vmp / Imp ยังขาด \(t.total - t.done)", t.isComplete ? .ok : .warn)
            }
            Spacer(minLength: 8)
            if !conditions.isEmpty { Text(conditions.joined(separator: " | ")).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted) }
        }
    }

    private enum Tone { case ok, warn, danger }

    private func pill(_ text: String, _ tone: Tone) -> some View {
        let (ink, fill): (Color, Color) = switch tone {
        case .ok: (Theme.successInk, Theme.successSoft)
        case .warn: (Theme.warningInk, Theme.pendingSoft)
        case .danger: (Theme.dangerText, Theme.dangerSoft)
        }
        return Text(text).font(.sarabunFixed(13, .bold)).foregroundStyle(ink).padding(.horizontal, 10).frame(height: 28).background(fill, in: Capsule())
    }
}
