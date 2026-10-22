#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// C1's แผงบนหลังคา tab (docs/specs/roof-pv-layout.md §5): the automatic layout on purlins with its controls, the
/// selected item's details, the quantities, the standard, and the row section in the section card. The layout runs off
/// the main thread (`refreshMount`) and its choices live on the job (`RoofMount.Choice`).
extension RoofPageWide {
    enum MountTool { case inspect, remove }
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
                if mountTool == .inspect, let a = L.areas.first(where: { $0.box.inset(-4).contains(s) }) {
                    mountSelection = mountSelection == .area(a.area.index) ? nil : .area(a.area.index)
                    return
                }
                guard let hit = L.slots.first(where: { Self.inside($0.outline, s) }) else { mountSelection = nil; return }
                if mountTool == .remove {
                    toggleRemoved(hit.ref, module: hit.module)
                } else {
                    mountSelection = mountSelection == .slot(hit.ref) ? nil : .slot(hit.ref)
                    if hit.module, let fi = mount?.faces.firstIndex(where: { $0.face.id == hit.ref.face }) { sectionRow = (fi, hit.ref.row) }
                }
            }
            .accessibilityLabel(mountTool == .remove ? "แตะแผงเพื่อเอาออกหรือใส่คืน" : "แตะแผงหรือสิ่งกีดขวางเพื่อดูรายละเอียด")
    }

    /// Turns a shed roof's low side to the opposite edge.
    func turnShed() {
        let on = RoofMount.shedLowAtStart(values)
        update { RoofMount.setShedLowAtStart(&$0, !on) }
        mountSelection = nil
    }

    func toggleRemoved(_ ref: RoofMountLayout.SlotRef, module: Bool) {
        let removed = mountChoice.removed.contains(ref)
        guard module || removed else {
            mountSelection = .slot(ref)   // a blocked slot shows its reason instead
            return
        }
        changeChoice { c in
            if removed { c.removed.removeAll { $0 == ref } } else { c.removed.append(ref) }
        }
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
        mountSummary
        mountEnergy
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
        mountFixing
        mountShedSide
        mountWalkway
        mountFaces
        mountAlign
        mountBearing
        mountQuantities
        mountRules.id("rules")
        mountStandard
        mountFooter
    }

    var mountSummary: some View {
        let q = shownMount?.quantities, big: CGFloat = narrow ? 22 : 26
        let figures = VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(q?.modules ?? 0)").font(.sarabunFixed(big, .bold)).monospacedDigit()
                    Text("แผง").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    Text(String(format: "%.1f", q?.kWp ?? 0)).font(.sarabunFixed(big, .bold)).monospacedDigit().padding(.leading, 6)
                    Text("kWp").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    Text(String(format: "%.1f", shownEnergy ?? q?.energy ?? 0)).font(.sarabunFixed(big, .bold)).monospacedDigit().padding(.leading, 6)
                    Text("MWh/ปี").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    if mountBusy { ProgressView().controlSize(.small) }
                    Text(mountBusy ? "กำลังจัดผัง…" : "แผง \(Int(mountChoice.standardOrDefault.moduleWp)) W | ขาไม่ชนสิ่งกีดขวาง")
                        .font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        // iPhone: the figures above the panels field
        let layout = narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            figures
            if !narrow { Spacer(minLength: 6) }
            panelsField(q?.modules ?? 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.track, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: selection

    @ViewBuilder var mountInfo: some View {
        if let sel = mountSelection, let text = infoLines(sel) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(text.title).font(.sarabunFixed(14, .bold))
                    Spacer(minLength: 6)
                    Button { mountSelection = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 44, height: 32)
                    }
                    .buttonStyle(.plain).accessibilityLabel("ปิดรายละเอียด")
                }
                ForEach(Array(text.lines.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.sarabunFixed(12.5)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(text.pills.enumerated()), id: \.offset) { _, p in
                    Text(p.text).font(.sarabunFixed(12, .bold)).foregroundStyle(p.ok ? Theme.okText : Theme.dangerText)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(p.ok ? Theme.okSoft : Theme.dangerSoft, in: Capsule())
                }
                if case .area(let i) = sel { obstacleEditor(i) }
            }
            .padding(10)
            .background(Self.soft, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    struct InfoText { var title: String; var lines: [String]; var pills: [(text: String, ok: Bool)] }

    func infoLines(_ sel: MountSelection) -> InfoText? {
        guard let m = shownMount else { return nil }
        let s = m.standard
        switch sel {
        case .area(let index):
            guard let a = Roof.areas(values).first(where: { $0.index == index }) else { return nil }
            let input = RoofMount.input(values, latitude: latitude)
            guard let o = input.obstacles.first(where: { $0.x == a.x && $0.y == a.y && $0.w == a.w && $0.h == a.h }) else { return nil }
            let tall = o.heightOrDefault > 0
            let hulls = m.faces.reduce(0) { $0 + ($1.shade.isEmpty ? 0 : 1) }
            var pills: [(String, Bool)] = [(tall ? "เว้นแผงจากเงา 09:00–15:00" : "ไม่สูงพอจะทอดเงา", !tall)]
            if tall && hulls == 0 { pills = [("เงาไม่ตกบนแผง", true)] }
            return InfoText(title: o.title,
                            lines: [String(format: "%.2f × %.2f ม. | สูง %.2f ม.", o.w, o.h, o.heightOrDefault)
                                    + (o.height == nil && o.kind.defaultHeight > 0 ? " (ตามชนิด)" : ""),
                                    String(format: "แผงเว้น %.2f ม. | ขาเว้น %.2f ม.", o.coverable ? 0 : o.kind.moduleClearance, o.footClearance)
                                    + (o.coverable ? " | วางทับได้" : "")],
                            pills: pills)
        case .slot(let ref):
            guard let f = m.faces.first(where: { $0.face.id == ref.face }), f.rows.indices.contains(ref.row),
                  f.rows[ref.row].slots.indices.contains(ref.column) else { return nil }
            let row = f.rows[ref.row], slot = row.slots[ref.column]
            let place = "ด้าน\(RoofFace.direction(f.face.azimuth)) | แถว \(ref.row + 1) | ช่อง \(ref.column + 1)"
            if let why = slot.blocked {
                return InfoText(title: "ช่องว่าง | " + place, lines: [], pills: [(why, false)])
            }
            guard let run = f.run(row: ref.row, column: ref.column) else { return nil }
            let k = run.count
            let bay = run.feet.flatMap { feet in zip(feet, feet.dropFirst()).map { $1 - $0 } }.max() ?? 0
            var pills: [(String, Bool)] = [("ขาไม่ชนสิ่งกีดขวาง", true)]
            pills.append((m.options.tileHooks ? "ขอเกี่ยวกระเบื้องยึดจันทัน" : m.options.ribClamp ? "จับสันลอน ¼ และ ¾ ของแผง"
                          : m.options.acrossPurlins ? "รางตัดแป | ขาตกทุกแป" : "รางตกแปทั้ง 2 เส้น",
                          RoofMountDrawings.rowPasses(row, in: m)))
            if run.moved { pills.append((m.options.tileHooks ? "ข้ามจันทันที่ชนสิ่งกีดขวาง" : "จัดระยะ L-foot ใหม่เพื่อหลบสิ่งกีดขวาง", true)) }
            return InfoText(title: "แผง | " + place,
                            lines: [String(format: "ชุดราง %d แผง (%.2f kWp) | รางยาว %.2f ม.", k, Double(k) * s.moduleKW, run.railLength),
                                    (m.options.tileHooks ? "ขอเกี่ยว " : "L-foot ")
                                    + "\(run.feet.map(\.count).map(String.init).joined(separator: " / ")) ตัวต่อราง | ห่างมากสุด "
                                    + String(format: "%.2f ม.", bay)],
                            pills: pills)
        }
    }

    /// The kind and height of an obstacle on the plan, for its shade.
    @ViewBuilder func obstacleEditor(_ index: Int) -> some View {
        let list = values.obstacles(Roof.Key.obstacles)
        if list.indices.contains(index), list[index].kind != Roof.skylightKind, list[index].kind != Roof.keepOutKind {
            let o = list[index]
            let kinds: [RoofObstacleKind] = [.turbine, .stack, .pipe, .other]
            let current = RoofObstacleKind(rawValue: o.kind) ?? .other
            HStack(spacing: 8) {
                Menu {
                    ForEach(kinds, id: \.self) { k in
                        Button(k.title) { editObstacle(index) { $0.kind = k.rawValue; if $0.label.isEmpty || kinds.map(\.title).contains($0.label) { $0.label = k.title } } }
                    }
                } label: {
                    Label(current.title, systemImage: "chevron.down").font(.sarabunFixed(13, .bold)).frame(minHeight: 44)
                }
                Spacer(minLength: 4)
                Text("สูง").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                let h = NumberInput.value(o.height) ?? current.defaultHeight
                stepButton("minus", enabled: h > 0) { editObstacle(index) { $0.height = fmt(max(0, h - 0.1)) } }
                Text(String(format: "%.1f ม.", h)).font(.sarabunFixed(15, .bold)).monospacedDigit().frame(minWidth: 56)
                stepButton("plus", enabled: h < 10) { editObstacle(index) { $0.height = fmt(min(10, h + 0.1)) } }
            }
        }
    }

    func editObstacle(_ index: Int, _ f: (inout Obstacle) -> Void) {
        update { v in
            var list = v.obstacles(Roof.Key.obstacles)
            guard list.indices.contains(index) else { return }
            f(&list[index])
            v[Roof.Key.obstacles] = .obstacles(list)
        }
    }

    // MARK: controls

    var mountFixing: some View {
        let c = mountChoice, metal = (values.choice(Roof.Key.material) ?? values.text(Roof.Key.material)).contains("เมทัลชีท")
        let tile = RoofMount.tileRoof(values)
        return VStack(alignment: .leading, spacing: 6) {
            A3Label(text: "วิธียึด")
            if tile {
                RoofSegments(options: ["ขอเกี่ยวกระเบื้องยึดจันทัน"], selected: 0, minSegment: 90) { _ in }
                standardStepper("จันทันห่าง (ม.)", \.rafterSpacing, step: 0.05)
            } else {
                RoofSegments(options: metal ? ["ยึดเข้าแป", "จับสันลอน"] : ["ยึดเข้าแป"], selected: c.ribClamp && metal ? 1 : 0, minSegment: 90) { i in
                    changeChoice { $0.ribClamp = i == 1 }
                }
            }
            mountDirection
            Toggle(isOn: Binding(get: { c.avoidShade }, set: { on in changeChoice { $0.avoidShade = on } })) {
                Text("เว้นเงาสิ่งกีดขวาง 09:00–15:00 ทั้งปี").font(.sarabunFixed(14))
            }
            .tint(Theme.primary).frame(minHeight: 44)
        }
    }

    /// The modules' direction on the purlins (ด้านยาวตัดแป: portrait, or ตามแป: landscape) and, with L-feet on purlins,
    /// the rails' (ตามแป on the purlins, or ตัดแป up the slope with a foot on each purlin).
    @ViewBuilder var mountDirection: some View {
        let c = mountChoice, tile = RoofMount.tileRoof(values)
        let onPurlins = !tile && !c.ribClamp
        A3Label(text: "แนวแผง")
        RoofSegments(options: ["ด้านยาวตัดแป", "ด้านยาวตามแป"], selected: c.landscape ? 1 : 0, minSegment: 90) { i in
            changeChoice { $0.landscape = i == 1 }
        }
        if onPurlins {
            A3Label(text: "แนวราง")
            RoofSegments(options: ["รางตามแป", "รางตัดแป"], selected: c.railsAcross ? 1 : 0, minSegment: 90) { i in
                changeChoice { $0.railsAcross = i == 1 }
            }
            let spacing = Roof.purlinSpacing(values)
            if c.landscape && !c.railsAcross && !RoofMountLayout.purlinsHoldLandscape(c.standardOrDefault, purlinSpacing: spacing) {
                HStack(spacing: 8) {
                    Text(String(format: "แปห่าง %.2f ม. รางตามแปรับแผงด้านยาวตามแปไม่ได้ (รางทั้ง 2 เส้นต้องตกแปในช่วงจับด้านสั้น)", spacing))
                        .font(.sarabunFixed(12.5)).foregroundStyle(Self.amber)
                    Spacer(minLength: 4)
                    Button("ใช้รางตัดแป") { changeChoice { $0.railsAcross = true } }
                        .font(.sarabunFixed(13, .bold)).frame(minHeight: 44)
                }
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

    /// A shed roof's low side, also turned by a tap on the plan's arrow.
    @ViewBuilder var mountShedSide: some View {
        if RoofMount.shape(values) == .shed {
            let alongX = Roof.ridge(values) == .h, start = RoofMount.shedLowAtStart(values)
            VStack(alignment: .leading, spacing: 6) {
                A3Label(text: "ด้านต่ำของหลังคาเพิง (ชายคา)")
                RoofSegments(options: alongX ? ["ขอบล่างแปลน", "ขอบบนแปลน"] : ["ขอบขวาแปลน", "ขอบซ้ายแปลน"], selected: start ? 1 : 0,
                             minSegment: 90) { i in
                    if (i == 1) != start { turnShed() }
                }
                Text("แตะลูกศร ด้านต่ำ บนแปลนเพื่อสลับได้").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    /// A walkway one module wide down the middle of each face (most roofs, the default once on) or after every n
    /// columns, for cleaning (off by default).
    var mountWalkway: some View {
        let n = mountChoice.walkwayEvery, centre = mountChoice.walkwayCentre
        return VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { n > 0 || centre }, set: { on in changeChoice { $0.walkwayCentre = on; $0.walkwayEvery = 0 } })) {
                Text("เว้นทางเดินล้างแผง").font(.sarabunFixed(14))
            }
            .tint(Theme.primary).frame(minHeight: 44)
            if n > 0 || centre {
                Picker("ตำแหน่งทางเดิน", selection: Binding(get: { centre ? 0 : 1 }, set: { pick in
                    changeChoice { $0.walkwayCentre = pick == 0; $0.walkwayEvery = pick == 0 ? 0 : max(2, n == 0 ? 8 : n) }
                })) {
                    Text("กลางหลังคา").tag(0)
                    Text("ทุก n แผง").tag(1)
                }
                .pickerStyle(.segmented).frame(minHeight: 44)
            }
            if centre { mountAccessSide }
            if n > 0 {
                HStack(spacing: 6) {
                    Text("ทางเดินกว้าง 1 แผง ทุก").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 4)
                    stepButton("minus", enabled: n > 2) { changeChoice { $0.walkwayEvery = max(2, n - 1) } }
                    Text("\(n) แผง").font(.sarabunFixed(14, .bold)).monospacedDigit().frame(minWidth: 56)
                    stepButton("plus", enabled: n < 40) { changeChoice { $0.walkwayEvery = min(40, n + 1) } }
                }
            }
        }
    }

    /// Down the middle the roof is reached up the gable wall at one end of the ridge walkway (the CAD file's cat ladder
    /// and landing): which end, as the plan shows it.
    var mountAccessSide: some View {
        HStack(spacing: 8) {
            Text("ทางขึ้นหลังคา (บันไดลิง)").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            Spacer(minLength: 4)
            Picker("ทางขึ้นหลังคา", selection: Binding(get: { mountChoice.accessRight ? 1 : 0 }, set: { pick in
                changeChoice { $0.accessRight = pick == 1 }
            })) {
                Text("ซ้าย").tag(0)
                Text("ขวา").tag(1)
            }
            .pickerStyle(.segmented).frame(width: 140, height: 44)
        }
    }

    var mountFaces: some View {
        let faces = shownMount?.faces ?? [], c = mountChoice
        let best = faces.map(\.yield).max() ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            A3Label(text: "ด้านหลังคาที่วางแผง")
            ForEach(faces, id: \.face.id) { f in
                let auto = c.faceUse[f.face.id] == nil
                Button {
                    changeChoice { $0.faceUse[f.face.id] = !f.used }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: f.used ? "checkmark.square.fill" : "square").font(.system(size: 20))
                            .foregroundStyle(f.used ? Theme.primary : Theme.inkMuted)
                        Text("\(RoofFace.direction(f.face.azimuth)) \(Int(f.face.azimuth.rounded()))° | ลาด \(String(format: "%.0f", f.face.tilt * 180 / .pi))°")
                            .font(.sarabunFixed(14)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Int(f.yield.rounded()).formatted()) kWh/kWp | \(f.modules) แผง")
                            .font(.sarabunFixed(12.5).monospacedDigit()).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(f.used ? .isSelected : [])
                .accessibilityHint(auto ? "ตั้งอัตโนมัติ" : "ตั้งเอง")
            }
            if faces.contains(where: { $0.yield < best * mountChoice.standardOrDefault.faceMinShare }) {
                Text("ด้านที่ได้พลังงานต่ำกว่า \(Int(mountChoice.standardOrDefault.faceMinShare * 100))% ของด้านที่ดีที่สุดไม่วางแผง (ค่าสมมติ) | แตะเพื่อเปิดเอง")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    var mountAlign: some View {
        let faces = shownMount?.faces ?? [], c = mountChoice
        let face = faces.first { $0.face.id == mountFace } ?? faces.first
        let maxOffset = (c.landscape ? c.standardOrDefault.moduleLength : c.standardOrDefault.moduleWidth) + c.standardOrDefault.moduleGap
        return VStack(alignment: .leading, spacing: 6) {
            A3Label(text: "จัดแนวผัง")
            if faces.count > 1 {
                RoofSegments(options: faces.map { RoofFace.direction($0.face.azimuth) }, selected: faces.firstIndex { $0.face.id == face?.face.id },
                             minSegment: 60) { i in mountFace = faces[i].face.id }
            }
            if let face {
                let off = face.placement.columnOffset
                HStack(spacing: 8) {
                    Text("เลื่อนแนวแผงตามชายคา").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 4)
                    Text(String(format: "%.2f ม.", off)).font(.sarabunFixed(14, .bold)).monospacedDigit()
                }
                Slider(value: Binding(get: { off }, set: { new in
                    let snapped = (new / 0.05).rounded() * 0.05
                    guard abs(snapped - off) > 1e-9 else { return }
                    changeChoice { ch in
                        var p = ch.placements[face.face.id] ?? face.placement
                        p.columnOffset = snapped
                        ch.placements[face.face.id] = p
                    }
                }), in: 0...maxOffset)
                .tint(Theme.primary)
                .accessibilityLabel("เลื่อนแนวแผงตามชายคา")
                .accessibilityValue(String(format: "%.2f เมตร", off))
            }
            Button {
                changeChoice { $0.placements = [:]; $0.digest = "" }
                mountNote = nil
            } label: {
                Label("หาผังที่ได้แผงมากที่สุด", systemImage: "wand.and.stars").font(.sarabunFixed(15, .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card))
            .disabled(mountBusy)
            if let t = mountTried {
                Text("ลอง \(t.tried.formatted()) แบบ | ดีที่สุด \(t.best) แผง").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    var mountBearing: some View {
        let b = RoofMount.bearing(values)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ทิศของขอบบนแปลน").font(.sarabunFixed(14))
                Text(b.map { "หันทิศ" + RoofFace.direction($0) } ?? "ยังไม่ระบุ | คิดเป็นทิศเหนือ (ค่าสมมติ)")
                    .font(.sarabunFixed(12)).foregroundStyle(b == nil ? Self.amber : Theme.inkMuted)
            }
            Spacer(minLength: 6)
            stepButton("minus", enabled: true) { update { RoofMount.setBearing(&$0, (b ?? 0) - 5) } }
            Text(b.map { "\(Int($0))°" } ?? "—").font(.sarabunFixed(18, .bold)).monospacedDigit().frame(minWidth: 52)
            stepButton("plus", enabled: true) { update { RoofMount.setBearing(&$0, (b ?? 0) + 5) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ทิศของขอบบนแปลน " + (b.map { "\(Int($0)) องศา" } ?? "ยังไม่ระบุ"))
    }

    /// The walkways' BOQ cells, when the layout has walkways.
    func walkwayCells(_ w: RoofWalkwayQuantities?) -> [(String, String)] {
        guard let w, w.walkways > 0 else { return [] }
        var cells: [(String, String)] = [
            ("ทางเดิน", String(format: "%d แนว %.1f ม.", w.walkways, w.length)), ("ตะแกรง HDG", "\(w.gratings) แผ่น"),
            ("รางขวาง | L-feet", "\(w.crossRails) | \(w.lFeet)"), ("สลิงกันตก", String(format: "%.1f ม. | %d เสา", w.lifeline, w.supports)),
            ("รางเคเบิล + PPR", String(format: "%.1f ม.", w.tray)),
        ]
        if w.ladders > 0 { cells.append(("บันไดลิง", w.cagedLadders > 0 ? "\(w.ladders) (กรง + ชานพัก)" : "\(w.ladders)")) }
        return cells
    }

    var mountQuantities: some View {
        let q = shownMount?.quantities
        let cells: [(String, String)] = [
            ("ราง", String(format: "%.1f ม.", q?.railLength ?? 0)), ("ต่อราง", "\(q?.splices ?? 0)"),
            (q.map(RoofMount.footName) ?? "L-foot", "\(q?.feet ?? 0)"),
            ("ตัวจับกลาง", "\(q?.midClamps ?? 0)"), ("ตัวจับปลาย", "\(q?.endClamps ?? 0)"), ("ชุดราง", "\(q?.runs ?? 0)"),
            ("ตัดแผง", "\(q?.cuts ?? 0)"), ("ขาชนสิ่งกีดขวาง", "0"),
        ] + walkwayCells(q?.walkway)
        return VStack(alignment: .leading, spacing: 4) {
            A3Label(text: "ปริมาณวัสดุ (BOQ)")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: narrow ? 2 : 4), spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.1).font(.sarabunFixed(16, .bold)).monospacedDigit()
                        Text(c.0).font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Self.track, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
                }
            }
            if let q, q.modules > 0 {
                let over = q.overLoad
                Label(RoofMount.loadLine(q), systemImage: over ? "exclamationmark.triangle.fill" : "scalemass")
                    .font(.sarabunFixed(12.5, over ? .bold : .regular)).foregroundStyle(over ? Theme.dangerText : Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One value of the job's standard with − and + buttons.
    func standardStepper(_ title: String, _ kp: WritableKeyPath<RoofMountStandard, Double>, step: Double, fmt f: String = "%.2f") -> some View {
        let s = mountChoice.standardOrDefault
        return HStack(spacing: 6) {
            Text(title).font(.sarabunFixed(13)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            stepButton("minus", enabled: s[keyPath: kp] - step > 0) { setStandard { $0[keyPath: kp] = max(step, $0[keyPath: kp] - step) } }
            Text(String(format: f, s[keyPath: kp])).font(.sarabunFixed(14, .bold)).monospacedDigit().frame(minWidth: 48)
            stepButton("plus", enabled: true) { setStandard { $0[keyPath: kp] += step } }
        }
    }

    var mountStandard: some View {
        let s = mountChoice.standardOrDefault
        func field(_ title: String, _ kp: WritableKeyPath<RoofMountStandard, Double>, step: Double, fmt f: String = "%.2f") -> some View {
            standardStepper(title, kp, step: step, fmt: f)
        }
        return DisclosureGroup(isExpanded: $showStandard) {
            VStack(spacing: 2) {
                field("แผงยาว (ม.)", \.moduleLength, step: 0.01)
                field("แผงกว้าง (ม.)", \.moduleWidth, step: 0.01)
                field("กำลังแผง (W)", \.moduleWp, step: 5, fmt: "%.0f")
                field("น้ำหนักแผง (กก.)", \.moduleKg, step: 0.5, fmt: "%.1f")
                field("ช่วงจับจากปลาย ต่ำสุด", \.clampMin, step: 0.01)
                field("ช่วงจับจากปลาย สูงสุด", \.clampMax, step: 0.01)
                if s.clampFollowsModule {
                    Text("ช่วงจับคิดจากความยาวแผง (15–30%) | แก้เองได้").font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                field("L-foot ห่างไม่เกิน", \.footSpacing, step: 0.05)
                field("ร่นชายคา", \.setEave, step: 0.05)
                field("ร่นสัน", \.setRidge, step: 0.05)
                field("ร่นขอบจั่ว / ตะเข้", \.setVerge, step: 0.05)
                field("เกณฑ์น้ำหนัก (กก./ม²)", \.loadLimit, step: 1, fmt: "%.0f")
                Button("คืนค่ามาตรฐาน") { changeChoice { $0.standard = nil } }
                    .font(.sarabunFixed(14, .bold)).frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(mountChoice.standard == nil)
            }
            .padding(.top, 4)
        } label: {
            Text("มาตรฐานการยึดแผง" + (mountChoice.standard == nil ? "" : " | แก้ในงานนี้")).font(.sarabunFixed(14, .bold))
        }
        .tint(Theme.navy)
    }

    /// Edits the job's standard; the clamping zone follows a new module length until it was edited itself.
    func setStandard(_ f: (inout RoofMountStandard) -> Void) {
        changeChoice { c in
            var s = c.standardOrDefault
            let follows = s.clampFollowsModule, length = s.moduleLength
            f(&s)
            if follows && abs(s.moduleLength - length) > 1e-9 { (s.clampMin, s.clampMax) = s.clampFromModule }
            c.standard = s
        }
    }

    var mountFooter: some View {
        let assumed = RoofMount.assumptions(values, latitude: latitude)
        return VStack(alignment: .leading, spacing: 2) {
            if !assumed.isEmpty {
                Text("ค่าสมมติ: " + assumed.joined(separator: " | ")).font(.sarabunFixed(11.5)).foregroundStyle(Self.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง | ตรวจน้ำหนักบรรทุกของโครงหลังคากับวิศวกรโครงสร้าง")
                .font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: plan footer and section

    @ViewBuilder var mountButtons: some View {
        RoofSegments(options: ["ดูรายละเอียด", "เอาแผงออก"], selected: mountTool == .remove ? 1 : 0, minSegment: 92) { i in
            mountTool = i == 1 ? .remove : .inspect; tool = nil
        }
        .frame(minWidth: 150, maxWidth: 210)
        footerButton("ย้อน", icon: "arrow.uturn.backward") { undoMount() }
            .disabled(mountUndo.isEmpty).opacity(mountUndo.isEmpty ? 0.45 : 1)
            .accessibilityLabel("ย้อนกลับ")
        Menu {
            Button { tool = .keepOut; mountTool = .inspect } label: { Label("เขตห้ามติด", systemImage: "nosign") }
            ForEach([RoofObstacleKind.turbine, .stack, .pipe, .other], id: \.self) { k in
                Button { tool = .obstacle(k); mountTool = .inspect } label: { Text(k.title) }
            }
        } label: {
            Label(tool == nil ? "วาด" : "เสร็จ", systemImage: tool == nil ? "plus.square.dashed" : "checkmark")
                .font(.sarabunFixed(14, .bold)).foregroundStyle(Self.red)
                .padding(.horizontal, 10).frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.red.opacity(0.5)))
        } primaryAction: {
            if tool != nil { tool = nil } else { tool = .keepOut; mountTool = .inspect }
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
