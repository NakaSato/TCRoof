#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport
import ModuleRules

/// C1 roof (docs/ui/survey-c1): the interactive roof plan above section A-A on the left; the roof /
/// PV-layout tabs, member sizes 1–7 and the six photo angles on the right, on one screen. Field ids, choices and Excel
/// cells are unchanged; the page's own answers are hidden optional fields (`Roof.Key`). Portrait and iPhone stack it.
struct RoofPageWide: View {
    @Binding var job: Job
    let moduleID: UUID
    /// Width of the page's content.
    let width: CGFloat
    /// One column (plan and section on top, the cards below, scrolling): portrait or a free width under 1100 pt.
    var stacked = false
    /// false lays the stacked column out without its ScrollView (DEBUG offscreen render).
    var scrolls = true
    /// A gap the bottom bar sent us to (`Roof.Gap.key`).
    var request: Binding<String?> = .constant(nil)
    @Environment(SurveyModel.self) var model

    struct SpanRef: Hashable { var axis: Roof.Axis; var index: Int }
    enum Tool: Equatable { case keepOut, skylight, obstacle(RoofObstacleKind) }

    /// โครงสร้าง / จัดแผง: the plan's mode and the right card's tab (หลังคา / การจัดแผง) are one choice.
    @State var mode: RoofPlan.Mode = Self.startMode
    @State var span: SpanRef?
    @State var editPosts = false
    @State var tool: Tool?
    /// The rectangle being dragged out, metres (x1, y1, x2, y2).
    @State var drag: (Double, Double, Double, Double)?
    /// An area being dragged to its site position on a roof filled from a design: its `obst` index and the finger's offset.
    @State var moving: (index: Int, offset: CGSize)?
    /// The member row picked (1…7): its size list is open and its lines are red on the plan and the section.
    @State var member: Int?
    @State var dropdown: String?
    @State var otherKey: String?
    @State var otherText = ""
    @State var lengthKey: String?
    @State var typingMember: Int?
    @State var memberText = ""
    @State var sketchPicker = false
    @State var sketchCamera = false
    @State var viewingSketch: Photo?
    @State var savingStandard = false
    @State var showCAD = false
    @State var sectionBig = false
    /// รายละเอียด A / B and the member schedule (`RoofTruss`).
    @State var trussOpen = false
    /// A photo tile the bottom bar pointed at (pulses).
    @State var flashShot: Roof.Shot?
    @State var panelsFocused = false
    /// A card the stacked column scrolls to (DEBUG state checks, bottom-bar gaps).
    @State var scrollTarget: String?
    /// Roofs the team saved (`RoofStandards`).
    @State var saved: [Roof.Standard] = RoofStandards.load()
    // แผงบนหลังคา (RoofPageWide+Mount)
    @State var mount: RoofMountLayout?
    @State var mountBusy = false
    @State var mountSelection: MountSelection?
    @State var mountUndo: [RoofMount.Choice] = []
    /// The layout's yearly energy from the hourly engine, or SolarModel's (RoofPageWide+Energy).
    @State var mountYield: RoofMountYield.Estimate?
    @State var mountYieldBusy = false
    @State var energyOpen = false
    @State var rowSectionOpen = false
    @State var boqOpen = false
    @State var mountYieldFor: RoofMountYield.Inputs?
    /// The name of the roof design just saved to the team's library (RoofPageWide+Design).
    @State var roofDesignSaved: String?
    @Environment(\.permissions) var roofPermissions
    @State var mountNote: String?
    @State var mountFace = "S"
    /// Layouts the last search tried, and its best count.
    @State var mountTried: (tried: Int, best: Int)?
    /// The directions the last `หาผังที่ได้แผงมากที่สุด` tried, with their module counts.
    @State var mountArrangements: [RoofMount.Arrangement] = []
    /// The row the section card shows (face index, row).
    @State var sectionRow: (face: Int, row: Int) = (0, 0)

    /// จัดแผง for the `-surveyC1 pv` checks (also the offscreen render), else โครงสร้าง.
    static var startMode: RoofPlan.Mode {
        #if DEBUG
        if ["pv", "landscape", "keepout"].contains(UserDefaults.standard.string(forKey: "surveyC1") ?? "") { return .pv }
        #endif
        return .structure
    }

    var gap: CGFloat { width >= 1180 ? 28 : 20 }
    /// iPhone: the legend under the plan, footers on two lines, two roof fields per row.
    var narrow: Bool { width < 600 }
    /// Side by side only: the plan / section column (720 of 1240 in the design).
    var leftWidth: CGFloat { min(720, (width - gap) * 0.594) }
    /// Width of the cards' column (photo tiles go 3 × 2 under 440 pt).
    var cardsWidth: CGFloat { stacked ? width : width - leftWidth - gap }

    var index: Int? { job.modules.firstIndex { $0.id == moduleID } }
    var values: Values { index.map { job.modules[$0].values } ?? Values() }
    func update(_ f: (inout Values) -> Void) { if let i = index { f(&job.modules[i].values) } }
    func set(_ id: String, _ v: FieldValue?) { update { $0[id] = v } }

    static let track = Theme.hairline
    static let soft = Theme.primarySoft
    static let red = Theme.danger
    static let line = Theme.borderSubtle
    static let amber = Theme.pending

    /// The page's view type is erased in a few places (`AnyView`): written out in full it nests so deep that a Debug
    /// build on a device runs out of stack working it out (SIGSEGV in swift_getTypeByMangledName on opening C1).
    var body: some View {
        presented(page)
    }

    private var page: some View {
        VStack(spacing: 16) {
            PageStepBar(job: job, here: .module(moduleID), title: "แปลนและโครงสร้างหลังคา")
            if stacked { AnyView(stackedLayout) } else { AnyView(wideLayout) }
        }
        .foregroundStyle(Theme.navy)
        #if DEBUG
        .task { await openDebugState() }
        #endif
        .onChange(of: request.wrappedValue) { _, k in if let k { open(gap: k); request.wrappedValue = nil } }
        .task(id: mountKey) { await refreshMount() }
        .task(id: mountYieldInputs) { await refreshYield() }
    }

    /// The page's alerts and sheets.
    private func presented<V: View>(_ page: V) -> some View {
        page
        .alert("ระบุ" + (otherKey == Roof.Key.material ? "วัสดุมุง" : "รูปแบบหลังคา"), isPresented: Binding(get: { otherKey != nil }, set: { if !$0 { otherKey = nil } })) {
            TextField("พิมพ์ชื่อ", text: $otherText)
            Button("ตกลง") { if let k = otherKey, !otherText.trimmingCharacters(in: .whitespaces).isEmpty { update { Roof.chooseOther(&$0, k, text: otherText) } } }
            Button("ยกเลิก", role: .cancel) {}
        }
        .alert("ขนาดชิ้นส่วน (พิมพ์เอง)", isPresented: Binding(get: { typingMember != nil }, set: { if !$0 { typingMember = nil } })) {
            TextField("เช่น C-125x50x20x2.3", text: $memberText)
            Button("ตกลง") {
                let t = memberText.trimmingCharacters(in: .whitespaces)
                if let n = typingMember, !t.isEmpty { update { Roof.setMember(&$0, n, size: t) } }
            }
            Button("ยกเลิก", role: .cancel) {}
        }
        .sheet(isPresented: $savingStandard) { saveStandardSheet }
        .fullScreenCover(isPresented: $sectionBig) { sectionZoom.presentationBackground(.black.opacity(0.45)) }
        .sheet(isPresented: $trussOpen) { trussSheet }
    }

    /// Opens what a bottom-bar gap names.
    func open(gap key: String) {
        span = nil; editPosts = false; tool = nil
        if key.hasPrefix("shot-"), let n = Int(key.dropFirst(5)), let s = Roof.Shot(rawValue: n) {
            scrollTarget = "photos"; flashShot = s
            Task { try? await Task.sleep(nanoseconds: 1_600_000_000); if flashShot == s { flashShot = nil } }
            return
        }
        switch key {
        case "spans": mode = .structure; span = SpanRef(axis: .x, index: 0)
        case Roof.Key.panels: mode = .pv; scrollTarget = "info"; panelsFocused = true
        case Roof.Key.shape, Roof.Key.material: mode = .structure; scrollTarget = "info"; dropdown = key
        case Roof.Key.structure: mode = .structure; scrollTarget = "info"
        default:
            if key.hasPrefix("comp"), let n = Int(key.dropFirst(4)) { mode = .structure; scrollTarget = "members"; member = n }
        }
    }

    var wideLayout: some View {
        HStack(alignment: .top, spacing: gap) {
            // the section keeps the design's 297 pt on a tall screen and gives the plan room on a short one (11" landscape)
            GeometryReader { geo in
                VStack(spacing: 12) {
                    AnyView(planCard).frame(maxHeight: .infinity)
                    AnyView(sectionCard).frame(height: sectionHeight(min(297, max(200, geo.size.height * 0.375))))
                }
            }
            .frame(width: leftWidth)
            // one screen when it fits (13"); a short screen (11" landscape) scrolls the cards only
            Group {
                if scrolls {
                    ViewThatFits(in: .vertical) {
                        cardsColumn(fill: true)
                        ScrollView { cardsColumn(fill: false).padding(.bottom, 4) }.scrollIndicators(.hidden)
                    }
                } else { cardsColumn(fill: true) }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    func cardsColumn(fill: Bool) -> some View {
        VStack(spacing: 12) {
            // the panel layout doesn't edit the members, so their card stays with the structure
            if mode == .pv {
                AnyView(roofCard).frame(maxHeight: fill ? .infinity : nil)
            } else {
                AnyView(roofCard)
                AnyView(membersCard).frame(maxHeight: fill ? .infinity : nil)
            }
            AnyView(photosCard)
        }
    }

    /// Portrait or narrow: the drawings at full width keep their aspect, the cards follow; one scrolling column.
    @ViewBuilder var stackedLayout: some View {
        if scrolls {
            ScrollViewReader { proxy in
                ScrollView { stackedColumn }.scrollIndicators(.hidden)
                    .onChange(of: scrollTarget) { _, t in if let t { withAnimation { proxy.scrollTo(t, anchor: .top) }; scrollTarget = nil } }
            }
        } else { stackedColumn }
    }

    var stackedColumn: some View {
            VStack(spacing: 12) {
                // iPhone: the legend and footer sit under the plan, so the plan gets the full width
                AnyView(planCard).frame(height: narrow ? width * RoofPlan.height / RoofPlan.width + 290
                                              : min(620, (width - 170) * RoofPlan.height / RoofPlan.width) + 64)
                AnyView(sectionCard).frame(height: sectionHeight(min(340, width * RoofSection.height / RoofSection.width) + (narrow ? 124 : 72)))
                AnyView(roofCard).id("info")
                if mode != .pv { AnyView(membersCard).id("members") }
                AnyView(photosCard).id("photos")
            }
            .padding(.bottom, 4)
    }

    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
    }

    func cardTitle(_ t: String, trailing: String? = nil, trailingColor: Color = Theme.inkMuted, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            (Text(t) + Text(" *").foregroundColor(Theme.danger)).font(.sarabunFixed(17, .bold)).lineLimit(1)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.sarabunFixed(12.5, bold ? .bold : .regular)).foregroundStyle(trailingColor).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: roof / PV card

    var roofCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoofSegments(options: ["หลังคา *", "แผงบนหลังคา"], selected: mode == .pv ? 1 : 0, minSegment: 100, height: 44) { i in
                setMode(i == 1 ? .pv : .structure)
            }
            if mode == .structure { AnyView(VStack(alignment: .leading, spacing: 10) { roofTab; roofDesignSection }) } else { AnyView(mountTab) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
    }

    func setMode(_ m: RoofPlan.Mode) {
        mode = m; editPosts = false; tool = nil; span = nil; member = nil; dropdown = nil; mountSelection = nil
    }

    @ViewBuilder var roofTab: some View {
        if narrow { roofTabNarrow } else { roofTabWide }
    }

    /// iPhone: two fields per row.
    var roofTabNarrow: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow { standardField; dropdownField("รูปแบบหลังคา", key: Roof.Key.shape, list: Roof.shapes) }
            GridRow { dropdownField("วัสดุมุง", key: Roof.Key.material, list: Roof.materials); purlinField }
            GridRow { ridgeField; structureField }
            GridRow { frameField.gridCellColumns(2) }
        }
    }

    var frameField: some View {
        VStack(alignment: .leading, spacing: 3) {
            A3Label(text: "ชนิดโครงหลังคา")
            RoofSegments(options: RoofFrame.ordered.map(\.label), selected: RoofFrame.ordered.firstIndex(of: Roof.frame(values)), minSegment: 66) { i in
                update { Roof.setFrame(&$0, RoofFrame.ordered[i]) }
            }
        }
    }

    var roofTabWide: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                standardField.gridCellColumns(2)
                dropdownField("รูปแบบหลังคา", key: Roof.Key.shape, list: Roof.shapes).gridCellColumns(2)
                dropdownField("วัสดุมุง", key: Roof.Key.material, list: Roof.materials).gridCellColumns(2)
            }
            GridRow {
                purlinField.gridCellColumns(2)
                ridgeField.gridCellColumns(2)
                structureField.gridCellColumns(2)
            }
            GridRow { frameField.gridCellColumns(6) }
        }
    }

    var ridgeField: some View {
        VStack(alignment: .leading, spacing: 3) {
            A3Label(text: "แนวสันหลังคา")
            RoofSegments(options: ["นอน", "ตั้ง"], selected: Roof.ridge(values) == .h ? 0 : 1, minSegment: 44) { i in
                update { Roof.setRidge(&$0, i == 0 ? .h : .v) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    var structureField: some View {
        let wood = values.choice(Roof.Key.structure)
        return VStack(alignment: .leading, spacing: 3) {
            A3Label(text: "วัสดุโครงสร้าง")
            RoofSegments(options: ["ไม้", "เหล็ก"], selected: wood == "ไม้" ? 0 : wood == "โครงเหล็ก" ? 1 : nil, minSegment: 44) { i in
                set(Roof.Key.structure, .choice(Options.structure[i], other: ""))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// ระยะแป: the value opens a ± 0.05 popover.
    var purlinField: some View {
        let p = Roof.purlinSpacing(values), open = dropdown == "purlin"
        return VStack(alignment: .leading, spacing: 3) {
            A3Label(text: "ระยะแป")
            Button { dropdown = open ? nil : "purlin" } label: {
                HStack(spacing: 4) {
                    Text(String(format: "%.2f", p)).font(.sarabunFixed(18, .bold)).foregroundStyle(Self.amber).monospacedDigit()
                    Text("ม.").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 2)
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(Theme.primary)
                }
                .inputBox(focused: open, minHeight: 44, trailing: 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ระยะแป " + String(format: "%.2f", p) + " เมตร วัดตามแนวลาด")
            .popover(isPresented: Binding(get: { dropdown == "purlin" }, set: { if !$0 { dropdown = nil } }), arrowEdge: .top) {
                purlinEditor.presentationCompactAdaptation(.popover)
            }
        }
        .frame(maxWidth: .infinity)
    }

    func dropdownField(_ label: String, key: String, list: [Roof.Option]) -> some View {
        let shown = Roof.shown(values, key, in: list), open = dropdown == key
        return VStack(alignment: .leading, spacing: 3) {
            A3Label(text: label)
            Button { dropdown = open ? nil : key } label: {
                HStack {
                    Text(shown ?? "เลือก").font(.sarabunFixed(16)).foregroundStyle(shown == nil ? Theme.inkMuted : Theme.navy).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 2)
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(Theme.primary)
                }
                .inputBox(focused: open, minHeight: 44, trailing: 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label + " " + (shown ?? "ยังไม่เลือก"))
            .popover(isPresented: Binding(get: { dropdown == key }, set: { if !$0 { dropdown = nil } }), arrowEdge: .top) {
                dropdownList(key: key, list: list).presentationCompactAdaptation(.popover)
            }
        }
        .frame(maxWidth: .infinity)
    }

    func dropdownList(key: String, list: [Roof.Option]) -> some View {
        let cur = Roof.option(values, key, in: list)
        let other = cur == nil && values.choice(key) != nil
        return VStack(spacing: 0) {
            ForEach(list, id: \.name) { o in
                let on = cur == o
                Button { update { Roof.choose(&$0, key, o) }; dropdown = nil } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(o.name).font(.sarabunFixed(16, on ? .bold : .regular))
                            Text(o.sub).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer(minLength: 8)
                        if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary) }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .background(on ? Self.soft : Theme.surface)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Divider()
            Button { otherText = values.other(key); otherKey = key; dropdown = nil } label: {
                HStack {
                    Text(other ? "อื่นๆ: " + (Roof.shown(values, key, in: list) ?? "") : "อื่นๆ (ระบุเอง)").font(.sarabunFixed(15, other ? .bold : .regular))
                    Spacer()
                    if other { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary) }
                }
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(other ? Self.soft : Theme.surface)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.navy)
        .frame(width: narrow ? 280 : 300)
        .padding(.vertical, 6)
    }

    // MARK: panels field

    /// จำนวนแผงก่อนเข้าสำรวจ (required, the report's count): typed, or taken from the layout. The line under the box says
    /// whether it matches the layout, and offers the layout's count when it doesn't.
    func panelsField(_ count: Int) -> some View {
        let cur = values.text(Roof.Key.panels).trimmingCharacters(in: .whitespaces)
        let same = cur == String(count)
        return VStack(alignment: .leading, spacing: 4) {
            (Text("จำนวนแผงก่อนเข้าสำรวจ") + Text(" *").foregroundColor(Theme.danger)).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    TextField("", text: Binding(get: { cur }, set: { set(Roof.Key.panels, $0.isEmpty ? nil : .text($0)) }))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    Text("แผง").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                .inputBox(focused: panelsFocused && cur.isEmpty, minHeight: 44, trailing: 8)
                .frame(width: 120)
                .accessibilityLabel("จำนวนแผงก่อนเข้าสำรวจ")
                if count > 0 && !cur.isEmpty && same {
                    Label("ตรงกับผัง", systemImage: "checkmark.circle.fill").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.okText)
                } else if count > 0 {
                    Text("ผังได้ \(count) แผง").font(.sarabunFixed(13)).foregroundStyle(cur.isEmpty ? Theme.inkMuted : Self.amber)
                    Button { set(Roof.Key.panels, .text(String(count))); panelsFocused = false } label: {
                        Text("ใช้ \(count)").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ใช้จำนวนแผงจากการจัดแผง \(count) แผง")
                }
                Spacer(minLength: 0)
            }
        }
    }
}

#if DEBUG
extension RoofPageWide {
    /// `-surveyC1 <state>` seeds the design's example roof (19 × 16, Pratt, ridge นอน, two skylights) and opens one of the
    /// states in docs/ui/survey-c1: span, spany, posts, pv, keepout, landscape, ridgev, frame-n|w|c|r|k, picker, shape,
    /// material, wood, bays12, std, save, purlin, zoom, cad, member; pvyield / pvyieldfar set A1's GPS for the energy card.
    func openDebugState() async {
        guard let state = UserDefaults.standard.string(forKey: "surveyC1") else { return }
        update { v in
            Roof.setSpans(&v, .x, [1.5, 4, 4, 4, 4, 1.5]); Roof.setSpans(&v, .y, [1.5, 4.5, 4, 4.5, 1.5])
            Roof.setRidge(&v, .h); Roof.setFrame(&v, .pratt); Roof.setBays(&v, nil)
            v[Roof.Key.pvOrientation] = nil; v[Roof.Key.structure] = .choice("โครงเหล็ก", other: ""); v[Roof.Key.posts] = nil
            v[Roof.Key.obstacles] = .obstacles([Obstacle(label: "แผ่นใส", x: "6.4", y: "1", w: "0.8", h: "6.6", kind: Roof.skylightKind),
                                                Obstacle(label: "แผ่นใส", x: "11.8", y: "8.4", w: "0.8", h: "6.6", kind: Roof.skylightKind, canCover: true)])
            v[Roof.Key.panels] = .text("312")
            Roof.choose(&v, Roof.Key.material, Roof.materials[0])
            for n in 1...7 where Roof.memberSize(v, n).isEmpty { Roof.setMember(&v, n, size: RoofFrame.pratt.members[n - 1].defaultSize) }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        switch state {
        case "span": span = SpanRef(axis: .x, index: 2)
        case "spany": span = SpanRef(axis: .y, index: 1)
        case "posts": editPosts = true
        case "pv": set(Roof.Key.shape, .choice("หลังคาทรงจั่ว", other: "")); mode = .pv
        case "keepout":
            update { v in
                Roof.addArea(&v, kind: Roof.keepOutKind, x1: 2.4, y1: 9.2, x2: 6.6, y2: 12.2)
                Roof.addArea(&v, kind: Roof.keepOutKind, x1: 13, y1: 2.2, x2: 15.4, y2: 4.4)
            }
            mode = .pv; tool = .keepOut
        case "landscape": mode = .pv
        // แผงบนหลังคา: the tab in view, a module's or an obstacle's details, remove mode, the standard, a hip roof
        case "pvtab": mode = .pv; scrollTarget = "info"
        // the walkway along the ridge alone (a new layout's default) on the demo gable, its switch in view
        case "pvridge":
            update { v in
                v[Roof.Key.shape] = .choice("หลังคาทรงจั่ว", other: ""); v[Roof.Key.material] = .choice("เมทัลชีท", other: "")
                RoofMount.setShedLowAtStart(&v, false)
                var c = RoofMount.choice(v); c.walkwayRidge = true; c.walkwayCentre = false; c.walkwayEvery = 0; c.removed = []
                RoofMount.setChoice(&v, c)
            }
            mode = .pv
            for _ in 0..<40 where mount == nil || mountBusy { try? await Task.sleep(nanoseconds: 250_000_000) }
            scrollTarget = "walkway"
        // หาผังที่ได้แผงมากที่สุด run on the demo roof (every direction tried), its button and list in view
        case "pvmost":
            update { v in
                v[Roof.Key.shape] = .choice("หลังคาทรงจั่ว", other: ""); v[Roof.Key.material] = .choice("เมทัลชีท", other: "")
                RoofMount.setShedLowAtStart(&v, false)
                var c = RoofMount.choice(v); c.landscape = false; c.railsAcross = false; c.removed = []; RoofMount.setChoice(&v, c)
            }
            mode = .pv
            for _ in 0..<40 where mount == nil || mountBusy { try? await Task.sleep(nanoseconds: 250_000_000) }
            await searchMostModules()
            scrollTarget = "most"
        // the yearly energy card: A1's GPS in Bangkok (the hourly engine) or in Chiang Mai (no weather: SolarModel)
        case "pvyield", "pvyieldfar":
            job.values["gps"] = .text(state == "pvyield" ? "13.7563, 100.5018" : "18.7883, 98.9853")
            update { v in
                v[Roof.Key.shape] = .choice("หลังคาทรงจั่ว", other: ""); v[Roof.Key.material] = .choice("เมทัลชีท", other: "")
                RoofMount.setShedLowAtStart(&v, false)
            }
            mode = .pv; scrollTarget = "info"
        // pvrules: the installation checks card (ModuleRules) (information only)
        case "pvrules":
            update { v in
                v[Roof.Key.shape] = .choice("หลังคาทรงจั่ว", other: ""); v[Roof.Key.material] = .choice("เมทัลชีท", other: "")
                RoofMount.setChoice(&v, RoofMount.Choice())
            }
            mode = .pv
            for _ in 0..<40 where mount == nil || mountBusy { try? await Task.sleep(nanoseconds: 250_000_000) }
            try? await Task.sleep(nanoseconds: 500_000_000)
            scrollTarget = "rules"
        case "pvinfo", "pvobst", "pvhip", "pvshed", "pvtile", "pvacross", "pvland", "pvlandalong":
            // the demo job keeps its answers: each state sets its own shape, material, low side and walkway
            let shape = state == "pvhip" ? "หลังคาทรงปั้นหยา" : state == "pvshed" ? "หลังคาเพิงหมาแหงน" : "หลังคาทรงจั่ว"
            update { v in
                v[Roof.Key.shape] = .choice(shape, other: "")
                v[Roof.Key.material] = .choice(state == "pvtile" ? "กระเบื้องซีแพค" : "เมทัลชีท", other: "")
                RoofMount.setShedLowAtStart(&v, state == "pvshed")
                var c = RoofMount.choice(v)
                c.walkwayEvery = state == "pvtile" ? 6 : 0
                // pvacross: rails across the purlins; pvland: landscape on them; pvlandalong: landscape on rails along (the hint)
                c.landscape = ["pvland", "pvlandalong"].contains(state)
                c.railsAcross = ["pvacross", "pvland"].contains(state)
                if c.landscape || c.railsAcross { c.ribClamp = false }
                RoofMount.setChoice(&v, c)
            }
            if state == "pvobst" {
                update { v in
                    Roof.addArea(&v, kind: RoofObstacleKind.stack.rawValue, x1: 15.2, y1: 2.0, x2: 15.8, y2: 2.6)
                    Roof.addArea(&v, kind: RoofObstacleKind.turbine.rawValue, x1: 4.0, y1: 10.8, x2: 4.6, y2: 11.4)
                }
            }
            mode = .pv
            for _ in 0..<40 where mount == nil || mountBusy { try? await Task.sleep(nanoseconds: 250_000_000) }
            switch state {
            case "pvinfo", "pvacross", "pvland":
                if let f = mount?.faces.first, let r = f.rows.indices.first,
                   let c = f.rows[r].slots.firstIndex(where: \.isModule) {
                    mountSelection = .slot(.init(face: f.face.id, row: r, column: c))
                }
            case "pvobst": mountSelection = Roof.areas(values).last.map { .area($0.index) }
            default: break
            }
            // the hip roof and the obstacles keep the plan in view
            if !["pvhip", "pvobst", "pvshed", "pvacross", "pvland"].contains(state) { scrollTarget = "info" }
        case "design", "designpv", "designlist":
            // docs/specs/standard-designs.md §7: the demo roof saved as a design, picked, its purlins changed and two items confirmed
            update { v in v[Roof.Key.shape] = .choice("หลังคาทรงจั่ว", other: "") }
            let name = "อาคารตัวอย่าง " + RoofDesign.from(values, name: "", job: "", by: nil).size
            // saved once per simulator, so the dropdown doesn't list a copy per launch
            let d = DesignLibrary.shared.roofs.first { $0.name == name && !$0.archived }
                ?? RoofDesign.from(values, name: name, job: "DEMO", by: nil)
            if !DesignLibrary.shared.roofs.contains(where: { $0.id == d.id }) { DesignLibrary.shared.saveRoof(d) }
            update { v in
                RoofDesign.apply(&v, d)
                Roof.setPurlinSpacing(&v, 1.2)
                RoofDesign.toggle(&v, "size"); RoofDesign.toggle(&v, "frame")
            }
            scrollTarget = "info"
            // designpv: the แผงบนหลังคา tab, with its ยังตรวจแบบไม่ครบ banner
            if state == "designpv" { mode = .pv }
            // designlist: the หลังคามาตรฐาน dropdown open, the design's card ticked
            if state == "designlist" { try? await Task.sleep(nanoseconds: 800_000_000); dropdown = "std" }
        case "ridgev": update { Roof.setRidge(&$0, .v) }
        case "frame-n": update { Roof.setFrame(&$0, .normal) }
        case "frame-h": update { Roof.setFrame(&$0, .howe) }
        case "truss": update { Roof.setFrame(&$0, .howe) }; try? await Task.sleep(nanoseconds: 500_000_000); trussOpen = true
        case "frame-w": update { Roof.setFrame(&$0, .warren) }
        case "frame-c": update { Roof.setFrame(&$0, .rafterTie) }
        case "frame-r": update { Roof.setFrame(&$0, .rafterTruss) }
        case "frame-k": update { Roof.setFrame(&$0, .eaveCeiling) }
        case "bays12": update { Roof.setBays(&$0, 12) }
        case "picker", "member": scrollTarget = "members"; try? await Task.sleep(nanoseconds: 700_000_000); member = 2
        case "shape": scrollTarget = "info"; try? await Task.sleep(nanoseconds: 700_000_000); dropdown = Roof.Key.shape
        case "material": scrollTarget = "info"; try? await Task.sleep(nanoseconds: 700_000_000); dropdown = Roof.Key.material
        case "std": scrollTarget = "info"; try? await Task.sleep(nanoseconds: 700_000_000); dropdown = "std"
        case "save": savingStandard = true
        case "purlin": scrollTarget = "info"; try? await Task.sleep(nanoseconds: 700_000_000); dropdown = "purlin"
        case "zoom": sectionBig = true
        case "cad": showCAD = true
        case "wood": set(Roof.Key.structure, .choice("ไม้", other: "")); scrollTarget = "info"
        default: break
        }
    }
}
#endif

/// The design's segmented control: a grey track, the chosen segment white with a soft shadow and bold navy text.
/// When the segments can't get `minSegment` each, it falls back to a menu with the same values.
struct RoofSegments: View {
    let options: [String]
    let selected: Int?
    var minSegment: CGFloat = 56
    var height: CGFloat = 38
    let set: (Int) -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            track.frame(minWidth: minSegment * CGFloat(options.count) + 6)
            menu
        }
    }

    var track: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                let on = selected == i
                Button { set(i) } label: {
                    Text(o).font(.sarabunFixed(15, on ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 8).fill(Theme.surface).shadow(color: Theme.navy.opacity(0.25), radius: 1.5, y: 1) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(minHeight: 44)
        .background(RoofPageWide.track, in: RoundedRectangle(cornerRadius: 10))
    }

    var menu: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                Button { set(i) } label: { if selected == i { Label(o, systemImage: "checkmark") } else { Text(o) } }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selected.map { options[$0] } ?? "เลือก").font(.sarabunFixed(15, .bold)).lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(selected == nil ? Theme.inkMuted : Theme.navy)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.primary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoofPageWide.track, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
#endif
