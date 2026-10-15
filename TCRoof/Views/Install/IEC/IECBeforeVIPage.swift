import SwiftUI
import TCRoofUI
import TCRoofCore

/// Step 2/7 `ก่อนออน · แรงดัน / กระแส` on iPad (docs/ui/iec62446-step2-before-vi-ipad): the inverters, the DC input
/// map of one inverter, the selected string's two photos and values, and its table. Values are typed in the entry
/// dialog (`IECBeforeVIEntry`), photo first; continuous mode walks the unfinished strings. iPhone and the after phase
/// keep `IECStringGrid` / `IECStringEntry`.
struct IECBeforeVIPage: View {
    @Bindable var job: Job
    @State var inverter: Int
    /// The selected slot, 1-based (an empty slot can be selected).
    @State var slot: Int
    /// Another step's screen, opened by the overview (`IECTestScreen.open`), which owns the navigation.
    let openStage: (IECReport.Stage) -> Void

    @State var filter: Filter = .all
    @State var entry: IECBeforeVIEntry.Target?
    /// The photo being taken: the slot and kind, then the dialog to open after it (nil = stay on the page).
    @State var shooting: Shot?
    @State var setup = false
    /// The slot whose string is about to be removed (it has values): asked first.
    @State var confirmEmpty: Int?
    @State var savedFlash = false
    /// Readings of photos already read, by photo id (`nil` value: read, nothing found).
    @State var readings: [String: Double?] = [:]
    @State var debugApplied = false
    @Environment(\.modelContext) var context

    enum Filter: Hashable { case all, todo, failed }

    struct Shot: Identifiable, Equatable {
        let slot: Int
        let kind: IECReport.PhotoKind
        var then: IECBeforeVIEntry.Target?
        var id: String { "\(slot)-\(kind.rawValue)" }
    }

    var report: IECReport { job.iecReport ?? job.newIECReport }

    var body: some View {
        let r = report
        let i = min(inverter, max(r.inverters.count - 1, 0))
        VStack(spacing: 0) {
            IECHeader(title: "IEC 62446 · ก่อนออนระบบ · แรงดัน / กระแส", subtitle: stationLine(r)) { EmptyView() }
            if r.inverters.indices.contains(i) {
                IECStepProgress(current: .beforeVoltage, report: r, open: go)
                    .padding(.horizontal, 24).padding(.top, 14)
                HStack(alignment: .top, spacing: 24) {
                    ScrollView { leftColumn(r, i).padding(.bottom, 16) }
                        .scrollIndicators(.hidden)
                        .frame(width: 420)
                    tableCard(r, i)
                }
                .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 16)
                .frame(maxWidth: 1290, maxHeight: .infinity, alignment: .top)
                bottomBar(r)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay { entryOverlay(r) }
        .modifier(IECShutter(shot: $shooting, job: job, stubReading: stubReading) { shot, data in stored(shot, data) })
        .sheet(isPresented: $setup) { IECSetupSheet(report: job.iecReport ?? job.newIECReport) { new in job.updateIEC(context) { $0 = new } } }
        .confirmationDialog("ตั้งช่องนี้เป็นว่าง", isPresented: Binding(get: { confirmEmpty != nil }, set: { if !$0 { confirmEmpty = nil } }),
                            titleVisibility: .visible) {
            Button("ลบสตริงและค่าที่วัด", role: .destructive) { if let s = confirmEmpty { setEmpty(s) } }
            Button("ยกเลิก", role: .cancel) {}
        } message: { Text("สตริงในช่องนี้มีค่าหรือรูปแล้ว ค่าและรูปจะถูกลบ และคอลัมน์ใน Excel จะว่าง") }
        #if DEBUG
        .task { applyDebugState() }
        #endif
    }

    /// Step 1 is the set-up sheet here until its page is built; the other steps belong to the overview.
    func go(_ stage: IECReport.Stage) { openStage(stage) }

    func stationLine(_ r: IECReport) -> String {
        let line = r.stationLine.isEmpty ? job.stationName : r.stationLine
        return line
    }

    // MARK: left column

    @ViewBuilder func leftColumn(_ r: IECReport, _ i: Int) -> some View {
        let inv = r.inverters[i]
        VStack(alignment: .leading, spacing: 14) {
            inverterCards(r)
            banner(i)
            IECDCInputMap(report: r, inverter: i, selected: slot, select: { slot = $0 }, toggleEmpty: { toggleEmpty($0) })
                .disabled(r.isLocked)
            selectedBar(r, inv, i)
            if let s = inv.slots[slot - 1] {
                flowLine(r, inv, s, i)
                failAlert(r, inv)
                photoCards(r, inv, s, i)
            } else {
                emptyNote(inv)
            }
        }
    }

    func inverterCards(_ r: IECReport) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(r.inverters.enumerated()), id: \.offset) { k, inv in inverterCard(r, k, inv) }
            }
            .padding(2)
        }
        .scrollIndicators(.hidden)
    }

    func inverterCard(_ r: IECReport, _ k: Int, _ inv: IECReport.Inverter) -> some View {
        let t = r.beforeVITally(inv), on = k == inverter
        return Button { inverter = k; slot = inv.strings.first?.slot ?? 1; filter = .all } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("INV\(k + 1)").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                    Spacer()
                    Text(t.isComplete ? "✓ ครบ \(t.done)/\(t.total)" : "วัดแล้ว \(t.done)/\(t.total)").font(.sarabunFixed(13, .bold))
                        .foregroundStyle(t.isComplete ? Theme.okText : on ? Theme.primary : Theme.warningInk)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(Theme.stepDone).frame(width: g.size.width * (t.total > 0 ? Double(t.done) / Double(t.total) : 0))
                    }
                }
                .frame(height: 5)
                Text("\(IECFormat.number(inv.ratedKW)) kW · \(inv.slotsInUse) ช่อง" + (inv.serial.isEmpty ? "" : " · S/N \(inv.serial)"))
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 12).frame(width: 228, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Theme.primary : Theme.borderSubtle, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("INV\(k + 1) วัดแล้ว \(t.done) จาก \(t.total)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func banner(_ i: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("!").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.onPrimary)
                .frame(width: 30, height: 30).background(Theme.warning, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("ระบบยังไม่ออน · วัดให้ครบทุกอินเวอร์เตอร์ก่อนออน").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.warningText)
                Text("วงจรเปิด กระแสต้องเป็น 0 A · เติม INV \(String(format: "%02d", i + 1))-ก่อน แถว 12, 16, 18")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.warningText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// `INV1ST1  MPPT 1 · ช่อง 1 · 16 แผง · คอลัมน์ E  ‹ ›`.
    func selectedBar(_ r: IECReport, _ inv: IECReport.Inverter, _ i: Int) -> some View {
        let s = inv.slots[slot - 1], seq = inv.strings.first { $0.slot == slot }?.seq
        let chip = seq.map { IECReport.label(inverter: i + 1, seq: $0) } ?? "ช่อง \(slot)"
        let meta = "MPPT \(IECReport.mppt(slot: slot)) · ช่อง \(slot) · " + (s.map { "\($0.modules) แผง" } ?? "ว่าง") + " · คอลัมน์ \(IECReport.excelColumn(slot: slot))"
        return HStack(spacing: 12) {
            Text(chip).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 12).frame(height: 38).background(Theme.primary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(meta).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            Spacer(minLength: 4)
            stepButton("chevron.left", "ช่องก่อนหน้า", enabled: slot > 1) { slot -= 1 }
            stepButton("chevron.right", "ช่องถัดไป", enabled: slot < inv.slotsInUse) { slot += 1 }
        }
    }

    func stepButton(_ symbol: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderControl))
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    /// `✓ ① ถ่ายรูป → ✓ ② ป้อนค่าจากรูป`, `ถ่ายแล้ว n/2`, and the continuous-mode button.
    func flowLine(_ r: IECReport, _ inv: IECReport.Inverter, _ s: IECReport.Slot, _ i: Int) -> some View {
        let shots = [s.photo(.voltageBefore), s.photo(.currentBefore)].compactMap { $0 }.count
        let typed = s.vocV != nil && s.iBeforeA != nil
        let left = unfinished(r, i).count
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    flowStep("①", "ถ่ายรูป", done: shots == 2)
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
                    flowStep("②", "ป้อนค่าจากรูป", done: typed)
                }
                Text("ถ่ายแล้ว \(shots)/2").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 6)
            Button { startContinuous(r, i) } label: {
                Label(left > 0 ? "วัดต่อเนื่อง · เหลือ \(left)" : "ครบทุกสตริง", systemImage: "play.fill")
                    .font(.sarabunFixed(15, .bold)).padding(.horizontal, 16).frame(height: 44)
                    .foregroundStyle(left > 0 ? Theme.onPrimary : Theme.okText)
                    .background(left > 0 ? AnyShapeStyle(Theme.actionGradient) : AnyShapeStyle(Theme.okSoft), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            // done: green and inactive, not faded
            .allowsHitTesting(left > 0 && !r.isLocked)
            .accessibilityAddTraits(left > 0 ? [] : .isStaticText)
        }
    }

    func flowStep(_ n: String, _ title: String, done: Bool) -> some View {
        HStack(spacing: 3) {
            if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.okText) }
            Text(n + " " + title).font(.sarabunFixed(14, .bold)).foregroundStyle(done ? Theme.okText : Theme.primary)
        }
    }

    @ViewBuilder func failAlert(_ r: IECReport, _ inv: IECReport.Inverter) -> some View {
        let reasons = r.beforeVIFailures(inv, slot: slot)
        if !reasons.isEmpty {
            HStack(spacing: 12) {
                Text("!").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.onPrimary).frame(width: 30, height: 30).background(Theme.danger, in: Circle())
                Text(reasons.joined(separator: " · ") + " · รูปเดิมเก็บไว้เทียบ").font(.sarabunFixed(13)).foregroundStyle(Theme.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("วัดซ้ำ") { shooting = Shot(slot: slot, kind: reasons.first?.hasPrefix("กระแส") == true ? .currentBefore : .voltageBefore,
                                                    then: .init(slot: slot, kind: reasons.first?.hasPrefix("กระแส") == true ? .current : .voltage)) }
                    .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 14).frame(minHeight: 44).background(Theme.danger, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .buttonStyle(.plain).disabled(r.isLocked)
            }
            .padding(12)
            .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.dangerLine))
        }
    }

    func photoCards(_ r: IECReport, _ inv: IECReport.Inverter, _ s: IECReport.Slot, _ i: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IECValuePhotoCard(kind: .voltage, asset: job.iecPhoto(s.photo(.voltageBefore)), value: s.vocV,
                              cell: IECReport.excelColumn(slot: slot) + "16", hint: vocHint(r, inv)) { open(.voltage, s) }
            IECValuePhotoCard(kind: .current, asset: job.iecPhoto(s.photo(.currentBefore)), value: s.iBeforeA,
                              cell: IECReport.excelColumn(slot: slot) + "18", hint: currentHint(s)) { open(.current, s) }
        }
        .disabled(r.isLocked)
    }

    /// `✓ ต่างจากมัธยฐาน +0.3%` / `✗ ต่างจากมัธยฐาน −5.4%`.
    func vocHint(_ r: IECReport, _ inv: IECReport.Inverter) -> (text: String, ok: Bool)? {
        guard let pass = r.vocPasses(inv, slot: slot) else { return nil }
        let d = r.vocDeviation(inv, slot: slot)
        return ((pass ? "✓ " : "× ") + (d.map { "ต่างจากมัธยฐาน " + IECReport.signedPercent($0) } ?? "ไม่มีสตริงขนาดเดียวกันให้เทียบ"), pass)
    }

    func currentHint(_ s: IECReport.Slot) -> (text: String, ok: Bool)? {
        guard let a = s.iBeforeA else { return nil }
        let ok = IECReport.currentPassesBefore(a)
        return (ok ? "✓ วงจรเปิด 0 A" : "× ก่อนออนต้องเป็น 0 A", ok)
    }

    func emptyNote(_ inv: IECReport.Inverter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ช่อง String \(slot) · MPPT \(IECReport.mppt(slot: slot)) ว่าง").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
            Text("ไม่มีสตริงต่อเข้าช่องนี้ ใน Excel คอลัมน์ \(IECReport.excelColumn(slot: slot)) จะเว้นว่างทั้งคอลัมน์ และไม่นับในผลรวม")
                .font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            Button { toggleEmpty(slot) } label: { Label("มีสตริงต่อในช่องนี้", systemImage: "plus") }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                .disabled(report.isLocked)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
    }

    // MARK: right column

    func tableCard(_ r: IECReport, _ i: Int) -> some View {
        IECBeforeVITable(report: r, inverter: i, selected: slot, filter: $filter) { slot = $0 }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: bottom bar

    func bottomBar(_ r: IECReport) -> some View {
        let failed = r.inverters.reduce(0) { $0 + r.beforeVITally($1).failed }
        let all = r.inverters.allSatisfy { r.beforeVITally($0).isComplete }
        let summary = r.inverters.enumerated().map { k, inv in let t = r.beforeVITally(inv); return "INV\(k + 1) \(t.done)/\(t.total)" }.joined(separator: " · ")
        let text = r.isLocked ? "ปิดการทดสอบแล้ว · ดูได้อย่างเดียว"
            : failed > 0 ? "มีค่าไม่ผ่าน \(failed) สตริง" : "วัดก่อนออน " + summary + " · ครบทุกอินเวอร์เตอร์แล้วจึงออนระบบ"
        let ok = !r.isLocked && failed == 0 && all
        return HStack(spacing: 14) {
            Image(systemName: ok ? "checkmark" : "exclamationmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                .frame(width: 28, height: 28).background(ok ? Theme.success : failed > 0 ? Theme.danger : Theme.warning, in: Circle())
            Text(text).font(.sarabunFixed(14)).foregroundStyle(ok ? Theme.okText : Theme.navy).lineLimit(2)
            Spacer(minLength: 8)
            Button { try? context.save(); savedFlash = true; Task { try? await Task.sleep(for: .seconds(1.5)); savedFlash = false } } label: {
                Text(savedFlash ? "บันทึกแล้ว ✓" : "บันทึกร่างตอนนี้").frame(minWidth: 140)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .bar))
            .accessibilityLabel("บันทึกร่างตอนนี้")
            twoLine("ก่อนหน้า 1/7", IECReport.Stage.setup.title, leading: true, primary: false) { openStage(.setup) }
            twoLine("ถัดไป 3/7", IECReport.Stage.beforeInsulation.title, leading: false, primary: true) { openStage(.beforeInsulation) }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    func twoLine(_ small: String, _ big: String, leading: Bool, primary: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if leading { Image(systemName: "chevron.left") }
                VStack(alignment: leading ? .leading : .trailing, spacing: 0) {
                    Text(small).font(.sarabunFixed(12))
                    Text(big).font(.sarabunFixed(16, .bold)).lineLimit(1)
                }
                if !leading { Image(systemName: "chevron.right") }
            }
            .foregroundStyle(primary ? Theme.onPrimary : Theme.navy)
            .padding(.horizontal, 18).frame(minWidth: 210, minHeight: 53)
            .background(primary ? AnyShapeStyle(Theme.actionGradient) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(primary ? Color.clear : Theme.borderControl))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(small + " " + big)
    }
}
