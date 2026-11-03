#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// C1's แผงบนหลังคา tab (docs/specs/roof-pv-layout.md §5): the automatic layout on purlins with its controls, the
/// selected item's details, the quantities, the standard, and the row section in the section card. The layout runs off
/// the main thread (`refreshMount`) and its choices live on the job (`RoofMount.Choice`).
extension RoofPageWide {
    enum MountSelection: Equatable { case slot(RoofMountLayout.SlotRef), area(Int) }

    var latitude: Double? { RoofMount.latitude(gps: job.values.text("gps")) }
    /// With a latitude only, so the faces in use come from the hourly engine near the bundled weather (`PlaneYield`).
    var longitude: Double? { RoofMount.site(job).longitude }

    /// The layout on screen; the offscreen render (no task runs there) works it out in place.
    var shownMount: RoofMountLayout? {
        if let mount { return mount }
        return scrolls || mode != .pv ? nil : RoofMount.layout(values, latitude: latitude, longitude: longitude).layout
    }
    var mountChoice: RoofMount.Choice { RoofMount.choice(values) }

    /// What the layout depends on, so the task runs again when any of it changes.
    var mountKey: String {
        mode == .pv ? RoofMount.digest(RoofMount.input(values, latitude: latitude), choice: mountChoice) + values.text(RoofMount.Key.choice) : ""
    }

    /// Lays the roof out (the best layout when the inputs changed), keeps a fresh search's placements on the job.
    func refreshMount() async {
        guard mode == .pv else { return }
        let v = values, lat = latitude, lon = longitude
        mountBusy = true
        let result = await Task.detached(priority: .userInitiated) { RoofMount.layout(v, latitude: lat, longitude: lon) }.value
        guard !Task.isCancelled else { return }
        if result.fresh {
            mountTried = (result.layout.faces.map(\.tried).reduce(0, +), result.layout.quantities.modules)
            mountArrangements = []
            var cleared = false
            update { cleared = RoofMount.remember(result.layout, in: &$0, latitude: lat) }
            if cleared { mountNote = "ผังเปลี่ยน จึงล้างแผงที่เอาออกเอง" }
        }
        mount = result.layout
        mountBusy = false
        // จำนวนแผงก่อนเข้าสำรวจ starts from the layout; the surveyor may still type another count
        let n = result.layout.quantities.modules
        if n > 0, values.text(Roof.Key.panels).trimmingCharacters(in: .whitespaces).isEmpty { set(Roof.Key.panels, .text(String(n))) }
    }

    /// `หาผังที่ได้แผงมากที่สุด`: every module and rail direction searched off the main thread, the one with the most
    /// modules kept (an undo step), so the rows may leave the purlins for rails across them.
    func searchMostModules() async {
        let v = values, lat = latitude, lon = longitude, before = mountChoice
        mountBusy = true
        let r = await Task.detached(priority: .userInitiated) { RoofMount.mostModules(v, latitude: lat, longitude: lon) }.value
        mountBusy = false
        let n = r.layout.quantities.modules, old = mount?.quantities.modules
        mountTried = (r.tried, n)
        mountArrangements = r.arrangements
        changeChoice { $0 = r.choice }
        mount = r.layout
        if r.choice.landscape != before.landscape || r.choice.railsAcross != before.railsAcross {
            mountNote = "เปลี่ยนเป็น" + RoofMount.arrangement(r.layout.options) + " | ได้ \(n) แผง" + (old.map { " (เดิม \($0))" } ?? "")
        } else {
            mountNote = nil
        }
    }

    /// Changes the tab's choices, with an undo step.
    func changeChoice(_ f: (inout RoofMount.Choice) -> Void) {
        let old = mountChoice
        var c = old
        f(&c)
        guard c != old else { return }
        mountUndo.append(old)
        if mountUndo.count > 50 { mountUndo.removeFirst() }
        update { RoofMount.setChoice(&$0, c) }
    }

    func undoMount() {
        guard let last = mountUndo.popLast() else { return }
        update { RoofMount.setChoice(&$0, last) }
    }

    /// The slots of the run holding `ref` (a module), or `ref` alone.
    func runSlots(_ ref: RoofMountLayout.SlotRef) -> Set<RoofMountLayout.SlotRef> {
        guard let m = mount, let f = m.faces.first(where: { $0.face.id == ref.face }),
              let run = f.run(row: ref.row, column: ref.column) else { return [ref] }
        if run.across { return Set(run.rows.map { RoofMountLayout.SlotRef(face: ref.face, row: $0, column: ref.column) }) }
        return Set(run.columns.map { RoofMountLayout.SlotRef(face: ref.face, row: ref.row, column: $0) })
    }

    var selectedSlots: Set<RoofMountLayout.SlotRef> {
        if case .slot(let ref) = mountSelection { return runSlots(ref) }
        return []
    }

    // MARK: plan taps

    /// Obstacles first (they sit under the slots), then slots; in remove mode a tap takes a module out or puts it back.
    func mountTap(_ L: RoofPlan.Layout, _ fit: SketchFit) -> some View {
        Color.clear.contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { p in
                let s = fit.sketch(p)
                if let arrow = L.shedArrow, arrow.contains(s) { turnShed(); return }
                if let a = L.areas.first(where: { $0.box.inset(-4).contains(s) }) {
                    mountSelection = mountSelection == .area(a.area.index) ? nil : .area(a.area.index)
                    return
                }
                guard let hit = L.slots.first(where: { Self.inside($0.outline, s) }) else { if !editModules { mountSelection = nil }; return }
                if editModules {
                    // `แก้แผง`: a module goes out, a removed slot comes back; other slots do nothing
                    guard hit.module || mountChoice.removed.contains(hit.ref) else { return }
                    mountSelection = nil
                    changeChoice { c in
                        if let i = c.removed.firstIndex(of: hit.ref) { c.removed.remove(at: i) } else { c.removed.append(hit.ref) }
                    }
                    return
                }
                mountSelection = mountSelection == .slot(hit.ref) ? nil : .slot(hit.ref)
                if hit.module, let fi = mount?.faces.firstIndex(where: { $0.face.id == hit.ref.face }) { sectionRow = (fi, hit.ref.row) }
            }
            .accessibilityLabel("แตะแผงหรือสิ่งกีดขวางเพื่อดูรายละเอียด")
    }

    /// Turns a shed roof's low side to the opposite edge.
    func turnShed() {
        let on = RoofMount.shedLowAtStart(values)
        update { RoofMount.setShedLowAtStart(&$0, !on) }
        mountSelection = nil
    }

    static func inside(_ poly: [Pt], _ p: Pt) -> Bool {
        var sign: Bool?
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let c = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if abs(c) < 1e-9 { continue }
            if let s = sign, s != (c > 0) { return false }
            sign = c > 0
        }
        return true
    }

    // MARK: the tab

    @ViewBuilder var mountTab: some View {
        if let s = RoofDesign.summary(values), s.open > 0 {
            DesignCheckBanner(open: s.open, unit: "รายการ") { withAnimation { mode = .structure } }
        }
        if RoofMount.shape(values) == nil {
            Label("วางแผงอัตโนมัติใช้ได้กับหลังคาจั่ว ปั้นหยา และเพิงหมาแหงน | หลังคานี้คิดเป็นทรงจั่ว", systemImage: "info.circle")
                .font(.sarabunFixed(12.5)).foregroundStyle(Self.amber)
        }
        if !narrow { mountSummary }
        if let note = mountNote {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(Theme.primary)
                Text(note).font(.sarabunFixed(12.5)).foregroundStyle(Theme.navy)
                Spacer(minLength: 4)
                Button("ย้อนกลับ") { undoMount(); mountNote = nil }.font(.sarabunFixed(13, .bold)).frame(minHeight: 44)
                    .disabled(mountUndo.isEmpty)
            }
        }
        mountInfo
        if narrow {
            mountSettingsPhone
            mountSummaryPhone
            mountMorePhone
        } else {
            // docs/ui board step 10: the summary, the fixing choices as one-line switches, the landscape arrangement and
            // the two layout buttons. Walkways (ridge on, cleaning off), faces (both, by yield) and shade (avoided) keep
            // their defaults; energy, BOQ and the module rules stay in the PDF and Excel.
            mountFixing
            mountShedSide
            mountBearing
            mountActions
        }
    }

    /// The layout's count and kWp on one line, the module on the right, and the count the report takes.
    var mountSummary: some View {
        let q = shownMount?.quantities
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(q?.modules ?? 0)").font(.sarabunFixed(26, .bold)).monospacedDigit()
                Text("แผง").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                Text("|").font(.sarabunFixed(18)).foregroundStyle(Theme.inkMuted)
                Text(String(format: "%.1f", q?.kWp ?? 0)).font(.sarabunFixed(26, .bold)).monospacedDigit()
                Text("kWp").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 6)
                Text(mountBusy ? "กำลังจัดผัง…" : "แผง \(Int(mountChoice.standardOrDefault.moduleWp)) W")
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            panelsField(q?.modules ?? 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.track, in: RoundedRectangle(cornerRadius: 10))
    }

    func summaryTile(_ value: String, _ unit: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.sarabunFixed(narrow ? 20 : 24, .bold)).monospacedDigit()
                Text(unit).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    // MARK: controls

    /// วิธียึด, แนวแผง and แนวราง in one card. A choice with one option is a line of text, not a control, and the rails'
    /// control appears only when the rails sit on purlins.
    var mountFixing: some View {
        let c = mountChoice, metal = (values.choice(Roof.Key.material) ?? values.text(Roof.Key.material)).contains("เมทัลชีท")
        let tile = RoofMount.tileRoof(values)
        let onPurlins = !tile && !c.ribClamp
        return VStack(alignment: .leading, spacing: 8) {
            if tile {
                fixingLine("วิธียึด", "ขอเกี่ยวกระเบื้องยึดจันทัน")
                standardStepper("จันทันห่าง (ม.)", \.rafterSpacing, step: 0.05)
            } else if metal {
                fixingRow("method", selected: c.ribClamp ? 1 : 0) { i in changeChoice { $0.ribClamp = i == 1 } }
            } else {
                fixingLine("วิธียึด", "ยึดเข้าแป")
            }
            // iPhone has the direction, the arrangement and the edge in `02 แผงและการวาง`
            if !narrow {
                fixingRow("orientation", selected: c.landscape ? 1 : 0) { i in changeChoice { $0.landscape = i == 1 } }
            }
            if onPurlins {
                fixingRow("rails", selected: c.railsAcross ? 1 : 0) { i in changeChoice { $0.railsAcross = i == 1 } }
            }
            if !narrow { landscapeArrangement }
            mountDirectionNotes
            if narrow {
                Toggle(isOn: Binding(get: { c.avoidShade }, set: { on in changeChoice { $0.avoidShade = on } })) {
                    Text("เว้นเงาสิ่งกีดขวาง 09:00–15:00 ทั้งปี").font(.sarabunFixed(14))
                }
                .tint(Theme.primary).frame(minHeight: 44)
            } else {
                edgeStepper
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.track.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    /// One choice of `Resources/roof-fixing-options.json` as tiles.
    @ViewBuilder func fixingChoice(_ id: String, selected: Int, _ pick: @escaping (Int) -> Void) -> some View {
        if let choice = FixingChoice.all[id] {
            VStack(alignment: .leading, spacing: 6) {
                A3Label(text: choice.title)
                FixingTiles(options: choice.options, selected: selected, pick: pick)
            }
        }
    }

    /// One choice on one line: its title on the left, its options as a 44 pt switch on the right.
    @ViewBuilder func fixingRow(_ id: String, selected: Int, _ pick: @escaping (Int) -> Void) -> some View {
        if let choice = FixingChoice.all[id] {
            HStack(spacing: 10) {
                Text(choice.title).font(.sarabunFixed(14)).foregroundStyle(Theme.navy).lineLimit(1).frame(width: 72, alignment: .leading)
                RoofSegments(options: choice.options.map(\.title), selected: selected, minSegment: 110, height: 44, set: pick)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(choice.title)
        }
    }

    /// จัดแผงใหม่ (the automatic layout again: no moved rows, no removed modules) and หาผังที่ได้แผงมากที่สุด, with
    /// what the search tried.
    var mountActions: some View {
        let c = mountChoice, edited = !c.placements.isEmpty || !c.removed.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    changeChoice { $0.placements = [:]; $0.removed = [] }
                } label: {
                    Label("จัดแผงใหม่", systemImage: "arrow.clockwise").font(.sarabunFixed(15, .bold)).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
                .disabled(mountBusy || !edited)
                Button {
                    Task { await searchMostModules() }
                } label: {
                    Label("หาผังที่ได้แผงมากที่สุด", systemImage: "wand.and.stars").font(.sarabunFixed(15, .bold))
                        .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(TCButtonStyle(.primary, size: .card))
                .disabled(mountBusy)
            }
            .id("most")
            if let t = mountTried {
                Text("ลองทุกแนวแผงและแนวราง | ลอง \(t.tried.formatted()) แบบ | ดีที่สุด \(t.best) แผง")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    func fixingLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            A3Label(text: title)
            Text(value).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
        }
        .frame(minHeight: 28)
    }

    /// What the choices mean: a landscape module on rails along the purlins that don't reach, and the clamped side.
    @ViewBuilder var mountDirectionNotes: some View {
        let c = mountChoice, tile = RoofMount.tileRoof(values)
        let onPurlins = !tile && !c.ribClamp
        if onPurlins {
            let spacing = Roof.purlinSpacing(values)
            if c.landscape && !c.railsAcross && !RoofMountLayout.purlinsHoldLandscape(c.standardOrDefault, purlinSpacing: spacing) {
                Text(String(format: "แปห่าง %.2f ม. รางตามแปรับแผงด้านยาวตามแปไม่ได้ (รางทั้ง 2 เส้นต้องตกแปในช่วงจับด้านสั้น) | เลือก รางตัดแป", spacing))
                    .font(.sarabunFixed(12.5)).foregroundStyle(Self.amber).fixedSize(horizontal: false, vertical: true)
            }
        } else if c.railsAcross {
            Text(tile ? "ขอเกี่ยวกระเบื้องใช้รางตามแนวชายคา" : "จับสันลอนใช้รางตามแนวชายคา")
                .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        }
        // rails parallel to the module's long side hold it by its short sides
        if c.landscape != (c.railsAcross && onPurlins) {
            Text("รางวางขนานด้านยาวของแผง: ตัวจับยึดด้านสั้น ตรวจคู่มือแผงว่ารับได้")
                .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        }
    }

    // MARK: plan footer and section

    /// The plan's tool buttons: ย้อน and the drawing menu.
    @ViewBuilder var mountButtons: some View {
        undoButton
        drawMenu
    }

    var undoButton: some View {
        footerButton("ย้อน", icon: "arrow.uturn.backward") { undoMount() }
            .disabled(mountUndo.isEmpty).opacity(mountUndo.isEmpty ? 0.45 : 1)
            .accessibilityLabel("ย้อนกลับ")
    }

    var drawMenu: some View {
        Menu {
            Button { tool = .keepOut } label: { Label("เขตห้ามติด", systemImage: "nosign") }
            ForEach([RoofObstacleKind.turbine, .stack, .pipe, .other], id: \.self) { k in
                Button { tool = .obstacle(k) } label: { Text(k.title) }
            }
        } label: {
            Label(tool == nil ? "วาด" : "เสร็จ", systemImage: tool == nil ? "plus.square.dashed" : "checkmark")
                .font(.sarabunFixed(14, .bold)).foregroundStyle(Self.red)
                .padding(.horizontal, 10).frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.red.opacity(0.5)))
        } primaryAction: {
            if tool != nil { tool = nil } else { tool = .keepOut }
        }
        .accessibilityLabel(tool == nil ? "วาดเขตห้ามติดหรือสิ่งกีดขวาง" : "เสร็จการวาด")
    }

    /// The selected row's section along the slope (row 1 of the first face until one is tapped).
    var rowSectionStage: some View {
        GeometryReader { geo in
            let sk = shownMount.map { RoofMountDrawings.rowSection($0, face: sectionRow.face, row: sectionRow.row) }
                ?? Sketch(width: RoofMountDrawings.width, height: RoofMountDrawings.height)
            let fit = SketchFit(RoofMountDrawings.width, RoofMountDrawings.height, in: geo.size)
            SketchCanvas(ops: sk.ops, fit: fit)
                .accessibilityLabel("รูปตัดแถวแผงตามแนวลาด")
        }
    }
}

extension Box {
    func contains(_ p: Pt) -> Bool { p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY }
}
#endif
