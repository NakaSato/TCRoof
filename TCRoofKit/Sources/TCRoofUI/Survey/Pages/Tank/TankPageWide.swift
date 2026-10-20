#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// D1 clear-water tank (docs/ui/survey-d1-size): four sub-steps in a tab bar. Sub-step 1 "ขนาดถัง"
/// is the designed page (the tank plan on the left, the tank's data on the right); sub-steps 2 "สิ่งกีดขวาง" and 3 "จัดแผง"
/// show the iPhone designs' cards in two columns (`TankPoints`, `TankLayout`); sub-step 4 shows the section's generic
/// group until its design arrives. Field ids, labels and Excel cells are unchanged; the page's own answers are hidden
/// optional fields (`Tank.Key`, `TankLayout.Key`). iPad portrait and iPhone use the one-column layout.
struct TankPageWide: View {
    @Binding var job: Job
    let moduleID: UUID
    /// Width of the page's content.
    let width: CGFloat
    /// One column (the plan on top, the card below, scrolling): portrait, iPhone or a free width under 1100 pt.
    var stacked = false
    /// The sub-step shown (view state only, never stored in the job). The editor owns it so the iPhone bottom bar's
    /// ‹ › can step through the sub-steps.
    @Binding var tab: Int
    /// iPhone: the sub-step tabs two to a row, a taller plan.
    var narrow: Bool { width < 600 }
    @Environment(SurveyModel.self) var model
    /// iPhone: the phone design (docs/ui/survey-d1-size-iphone); iPad keeps the layout below at any width.
    @Environment(\.horizontalSizeClass) var sizeClass
    var phone: Bool { phoneLayout || sizeClass == .compact }
    /// The phone layout outside a view graph (`-surveyTankRender`, where the size class isn't set).
    var phoneLayout = false

    @State var sizeOpen = false
    @State var pendingPreset: Tank.Preset?
    @State var span: RoofPageWide.SpanRef?
    @State var typeOther = false
    @State var otherText = ""
    @State var surfaceTyping = false
    @FocusState var surfaceFocus: Bool
    @State var azEntry = false
    @State var azText = ""
    @State var compass = false
    /// iPhone: the full plan with its span numbers, full screen.
    @State var planFull = false
    /// iPhone sub-step 2: the selected point, the shading view, the plan full screen and its zoom, the row and delete
    /// questions.
    @State var pointSel: UUID?
    @State var obsShade = false
    @State var obsFull = false
    @State var obsZoom: CGFloat = 1
    /// `เทียบกับแบบ` on the obstacle plan (standard designs).
    @State var obsCompare = false
    /// `บันทึกเป็นแบบมาตรฐาน`: its name question and the name saved.
    @State var saveDesignAsk = false
    @State var designName = ""
    @State var designSaved: String?
    @State var sheetOpen = false
    @Environment(\.permissions) var permissions
    @State var rowAsk = false
    @State var rowCount = 3
    @State var rowSpacing = 4.0
    @State var deleteAsk = false
    /// `เริ่มจากแบบมาตรฐาน กปภ.`: the designs, closest to the measured size first.
    @State var designAsk = false
    /// `ยืนยันที่เหลือ n จุดว่าตรงแบบ`, asked first.
    @State var bulkAsk = false
    /// iPhone sub-step 3: `แก้แผง` (else `เลื่อนผัง`), the plan full screen and its zoom, the question before a new
    /// layout, the max search running, the B1-C3 drawing.
    @State var layoutEditing = false
    @State var layoutFull = false
    @State var layoutZoom: CGFloat = 1
    @State var layoutAsk: LayoutRun?
    @State var layoutSearching = false
    /// The last `หาผังที่ได้พลังงานมากที่สุด`: the gaps tried and the one picked.
    @State var energySearch: TankLayout.EnergySearch?
    /// The true-south comparison worked out after the search (TankPageWide+South), its spinner and its sheet.
    @State var southCompare: TankLayout.SouthComparison?
    @State var southBusy = false
    @State var southOpen = false
    @State var drawingOpen = false
    /// Sub-step 3's shade card: the simulation (worked out off the main thread) and the moment shown on its plan.
    @State var shadeResult: TankShade?
    @State var shadeBusy = false
    @State var shadeMoment = 4
    /// `↶ เลิกทำ` (TankPageWide+Undo).
    @StateObject var undo = TankUndo()
    /// Sub-step 4 on iPad (TankPageWide+Photos): the selected tile, the filter, the wall shown, and where the next
    /// photo from the camera or the library goes.
    @State var photoSel: String?
    @State var photoFilter: TankPhotos.Filter = .all
    @State var photoWall = 0
    @State var photoTarget: PhotoTarget?
    @State var photoPicker = false
    @State var photoCamera = false
    /// DEBUG `photos` / `photodetails`: scroll sub-step 4 to the obstacle photos.
    @State var photoScroll = false
    /// DEBUG `layoutshade`: scroll the one-column layout to the shade card.
    @State var shadeScroll = false
    @State var dxfShare: DXFShare?
    @State var dxfError: String?

    var gap: CGFloat { width >= 1180 ? 20 : 16 }
    static let cardWidth: CGFloat = 330
    static let track = Theme.hairline
    static let teal = Theme.mint

    var index: Int? { job.modules.firstIndex { $0.id == moduleID } }
    var values: Values { index.map { job.modules[$0].values } ?? Values() }
    func update(_ f: (inout Values) -> Void) { if let i = index { f(&job.modules[i].values) } }
    func set(_ id: String, _ v: FieldValue?) { update { $0[id] = v } }

    var body: some View {
        Group {
            if phone {
                phoneBody
            } else {
                VStack(spacing: 14) {
                    PageStepBar(job: job, here: .module(moduleID), title: narrow ? "ถังน้ำใส" : "ถังน้ำใส · ขนาด สิ่งกีดขวาง/เงาบัง จัดแผง ภาพ")
                    HStack(spacing: 8) {
                        tabBar.frame(maxWidth: .infinity)
                        undoButtons()
                    }
                    switch tab {
                    case 1: sizeStep
                    case 2: padObstacleStep
                    case 3: padLayoutStep
                    default: if stacked { formStep } else { padPhotoStep }
                    }
                }
            }
        }
        .onChange(of: values) { old, _ in recordUndo(old) }
        .fullScreenCover(isPresented: $obsFull) { obstacleFullScreen }
        .fullScreenCover(isPresented: $layoutFull) { layoutFullScreen }
        .sheet(item: $dxfShare) { s in ShareSheet(items: [s.url]).presentationDetents([.medium, .large]) }
        .errorAlert($dxfError)
        .foregroundStyle(Theme.navy)
        #if DEBUG
        .task { await openDebugState() }
        #endif
    }

    // MARK: sub-step tab bar

    struct Step { let title: String; let status: String; let done: Bool; let statusOK: Bool }

    var steps: [Step] {
        let v = values, spec = Schema.spec(.tank)
        let shade = spec.groups.first { $0.title == "เงาบัง" }?.completion(v) ?? Completion()
        let photos = Tank.photoCompletion(v)
        let size = Tank.sizeLabel(v)?.name ?? ""
        let checked = TankPoints.checked(v), points = TankPoints.done(v) && shade.isComplete
        let layout = TankLayout.current(v), laid = TankLayout.done(v)
        func status(_ done: Bool, _ s: String) -> String { done ? s + " · เสร็จ" : "ยังไม่เสร็จ" }
        return [
            Step(title: "ขนาดถัง", status: status(Tank.sizeDone(v), size), done: Tank.sizeDone(v), statusOK: Tank.sizeDone(v)),
            // every standard point checked and the shading answered
            Step(title: "สิ่งกีดขวาง · เงาบัง", status: points ? "\(checked.total) จุด · เสร็จ" : TankPoints.done(v) ? "ยังไม่ตอบเงาบัง"
                    : checked.total > 0 && checked.n == checked.total && !TankPoints.missingPhotos(v).isEmpty
                        ? "ยังขาดรูป \(TankPoints.missingPhotos(v).count) จุด"
                    : checked.total > 0 ? "ตรวจแล้ว \(checked.n)/\(checked.total)" : "ยังไม่เสร็จ",
                 done: points, statusOK: points),
            // a layout whose checks all pass
            Step(title: "จัดแผง", status: laid ? "\(layout?.count ?? 0) แผง · เสร็จ" : layout.map { "ตรวจผ่าน \($0.checks.passed)/3" } ?? "ยังไม่เสร็จ",
                 done: laid, statusOK: laid),
            Step(title: "ภาพถ่าย", status: "บังคับ \(photos.filled)/\(photos.total)", done: photos.isComplete, statusOK: photos.isComplete),
        ]
    }

    /// The sub-steps (docs/ui/survey-d1-stepper-ipad): in regular width a stepper on a white card, each step hugging its
    /// content and joined by lines that take the free width (green after a done step); narrow keeps the 2 × 2 grid.
    @ViewBuilder var tabBar: some View {
        if narrow { tabGrid } else { stepperRow }
    }

    var stepperRow: some View {
        let s = steps
        return HStack(spacing: 10) {
            ForEach(Array(s.enumerated()), id: \.offset) { i, step in
                if i > 0 { stepLine(after: s[i - 1]) }
                tabSegment(i + 1, step, grid: false)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle, lineWidth: 1))
    }

    /// Narrow widths keep the 2 × 2 grid of segments on the grey track: four don't fit in a row.
    var tabGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 2), spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in tabSegment(i + 1, s, grid: true) }
        }
        .padding(4)
        .background(Self.track, in: RoundedRectangle(cornerRadius: 14))
    }

    /// The line between two steps: green once the step before it is done. It shrinks first, so the steps keep their width.
    func stepLine(after s: Step) -> some View {
        Capsule().fill(s.done ? Theme.success : Theme.hairline)
            .frame(minWidth: 16, maxWidth: .infinity).frame(height: 2)
            .layoutPriority(-1)
            .accessibilityHidden(true)
    }

    /// One step: its circle, title and status; the current one a light-blue pill with a blue inset stroke.
    func tabSegment(_ n: Int, _ s: Step, grid: Bool) -> some View {
        let on = tab == n
        return Button { withAnimation(.easeOut(duration: 0.15)) { tab = n; span = nil } } label: {
            HStack(spacing: 10) {
                stepCircle(n, done: s.done, current: on)
                stepTexts(s, on: on)
                if grid { Spacer(minLength: 0) }
            }
            .padding(.leading, 12).padding(.trailing, on && !grid ? 16 : 12)
            .frame(maxWidth: grid ? .infinity : nil, minHeight: grid ? 50 : 48)
            .background { if grid { gridSegment(on) } else { stepPill(on) } }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: !grid, vertical: false)
        .accessibilityLabel("ขั้นที่ \(n) \(s.title) \(s.status)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func stepTexts(_ s: Step, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(s.title).font(.sarabunFixed(15, .bold)).foregroundStyle(on ? Theme.navy : Theme.inkMuted).lineLimit(1)
            Text(s.status).font(.sarabunFixed(12, .semibold)).foregroundStyle(s.statusOK ? Theme.success : Theme.pending)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    /// The grid's raised white segment, as before.
    @ViewBuilder func gridSegment(_ on: Bool) -> some View {
        if on { RoundedRectangle(cornerRadius: 10).fill(Theme.surface).shadow(color: Theme.navy.opacity(0.2), radius: 1.5, y: 1) }
    }

    @ViewBuilder func stepPill(_ on: Bool) -> some View {
        if on {
            RoundedRectangle(cornerRadius: 12).fill(Theme.primarySoft)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.primary, lineWidth: 1.5))
        }
    }

    @ViewBuilder func stepCircle(_ n: Int, done: Bool, current: Bool) -> some View {
        if done {
            A2Icon(name: "d1-step-done", fallback: "checkmark.circle.fill", size: 26).foregroundStyle(Theme.success)
        } else {
            Text("\(n)").font(.sarabunFixed(13, .bold)).foregroundStyle(current ? Theme.onPrimary : Theme.inkMuted)
                .frame(width: 26, height: 26)
                .background(Circle().fill(current ? Theme.primary : Theme.surface))
                .overlay(Circle().stroke(current ? Color.clear : Theme.navy.opacity(0.25)))
        }
    }

    // MARK: sub-step 1

    @ViewBuilder var sizeStep: some View {
        if stacked {
            ScrollView {
                VStack(spacing: 14) {
                    planCard.frame(height: min(640, width * (narrow ? 0.9 : 0.72)))
                    infoCard(fill: false)
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        } else {
            HStack(alignment: .top, spacing: gap) {
                planCard.frame(maxWidth: .infinity, maxHeight: .infinity)
                // one screen when it fits; a short screen (11" landscape) scrolls the card only
                ViewThatFits(in: .vertical) {
                    infoCard(fill: true)
                    ScrollView { infoCard(fill: false) }.scrollIndicators(.hidden)
                }
                .frame(width: Self.cardWidth)
            }
            .frame(maxHeight: .infinity)
        }
    }

    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
    }

    // MARK: sub-step 4 · ภาพถ่าย (docs/specs/tank-drawing-swift.md, the designed groups)

    /// The designed photo groups; the roof, shade and cable photos are optional until the team makes them required.
    var formFields: [(title: String, ids: [String])] {
        [("ภาพมุมสูง (โดรน หรือ Google Maps) · บังคับ", ["aerialPhoto"]),
         ("ผนังถัง 4 ทิศ (ใช้วางแนวรางสายไฟ) · บังคับ · เรียง เหนือ ใต้ ตะวันออก ตะวันตก", ["sidePhotos"]),
         ("หลังคาถัง (ภาพรวม + ผิวหลังคา) · บังคับ 2 ภาพ", [Tank.Key.roofPhotos]),
         ("เงาบัง (ถ่ายจากกลางหลังคา) · ไม่บังคับ", [Tank.Key.shadePhoto]),
         ("ทางเดินสายไฟ (จากถังถึงห้อง Inverter) · บังคับ", [Tank.Key.cablePhoto]),
         ("สิ่งกีดขวาง · บังคับ · ภาพแรกลงกรอบใหญ่ในรายงาน", ["obstPhotos"])]
    }

    @ViewBuilder var formStep: some View {
        if let i = index {
            let fields = Schema.spec(.tank).fields
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(formFields, id: \.title) { g in
                        PaperBox(title: g.title) {
                            ForEach(g.ids.compactMap { id in fields.first { $0.id == id } }) { f in
                                if f.isVisible(job.modules[i].values) {
                                    FieldView(spec: f, values: $job.modules[i].values, jobID: job.id, moduleType: .tank, gps: job.values.text("gps"))
                                        .environment(\.photoDetails, photoDetails(f.id))
                                }
                            }
                        }
                        .id(g.ids.first ?? g.title)
                    }
                }
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: photoScroll) { _, on in if on { proxy.scrollTo("obstPhotos", anchor: .top); photoScroll = false } }
            }
        }
    }

    /// `ภาพที่เลือก` on every photo of the step; obstacle photos can be tied to the tank's openings.
    func photoDetails(_ id: String) -> PhotoDetailsContext {
        guard id == "obstPhotos" else { return PhotoDetailsContext() }
        let v = values
        return PhotoDetailsContext(tags: TankPoints.tagOptions(v), normalise: { TankPoints.tag($0, in: v) })
    }

    func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.onPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
extension TankPageWide {
    /// `-surveyD1 <state>` seeds the design's example tank (40 × 40, ค.ส.ล., กึ่งฝัง, 4.50 / 1.20, คอนกรีต, 12°) and
    /// opens a state of docs/ui/survey-d1-size/states: default, size, t64, t30, t20, above, buried, custom (typed azimuth
    /// and surface), compass, span, empty; tab2 opens sub-step 2. round makes it a round tank Ø 30 m (roundobst opens its
    /// standard points in sub-step 2, roundlayout checks them and opens the automatic layout in sub-step 3). obst opens sub-step 2 as docs/ui/survey-d1-obstacles-iphone
    /// (obstbottom scrolled to the end, obstshade the shading view, obstrow the row question, obstfull the plan full screen, obstadded a hatch added
    /// on site, obstdelete the delete question). layout opens sub-step 3 as docs/ui/survey-d1-layout-iphone with every point of
    /// 2/4 checked and the automatic layout (layoutbottom scrolled to the end, layoutedit แก้แผง with a panel off and a table
    /// removed, layoutask the question before จัดแผงใหม่, layoutfull the plan full screen, layoutmax หาผังที่ได้พลังงานมากที่สุด,
    /// layoutdrawing the B1-C3 sheet, layoutsouth the top wall at 12°, the search and the true-south comparison's sheet).
    func openDebugState() async {
        guard let state = UserDefaults.standard.string(forKey: "surveyD1") else { return }
        update { v in
            Tank.apply(&v, Tank.presets[0])
            v[Tank.Key.type] = .choice("ค.ส.ล.", other: "")
            Tank.setHeight(&v, 4.5)
            Tank.setPosition(&v, Tank.partly)
            Tank.setExposed(&v, 1.2)
            v[Tank.Key.surface] = .text("คอนกรีต")
            Tank.setSoil(&v, 0)
            Tank.setAzimuth(&v, 12, source: .compass, at: Date().addingTimeInterval(-3600), accuracy: 3)
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        switch state {
        case "size": sizeOpen = true
        case "t64": update { Tank.apply(&$0, Tank.presets[1]) }
        case "t30": update { Tank.apply(&$0, Tank.presets[2]) }
        case "t20": update { Tank.apply(&$0, Tank.presets[3]) }
        case "above": update { Tank.setPosition(&$0, Tank.above) }
        case "buried": update { Tank.setPosition(&$0, Tank.buried); Tank.setSoil(&$0, 0.6) }
        case "custom": update { Tank.setAzimuth(&$0, 14, source: .manual); $0[Tank.Key.surface] = .text("แผ่นยางกันซึม") }
        case "compass": compass = true
        case "span":
            // iPhone: the span numbers are on the full-screen plan
            if phone { planFull = true; try? await Task.sleep(nanoseconds: 700_000_000) }
            span = RoofPageWide.SpanRef(axis: .x, index: 2)
        case "empty": update { $0[Roof.Key.spansX] = nil; $0[Roof.Key.spansY] = nil }
        case "round", "roundobst", "roundlayout":
            // a round tank Ø 30 m: sub-step 1; roundobst its standard points (sub-step 2), roundlayout all checked and
            // the automatic layout (sub-step 3)
            update { v in
                v[Roof.Key.obstacles] = nil
                Tank.setShape(&v, .round)
                Tank.setDiameter(&v, 30)
                guard state != "round" else { return }
                TankPoints.seed(&v)
                for k in [TankLayout.Key.orient, TankLayout.Key.offX, TankLayout.Key.offY, TankLayout.Key.off, TankLayout.Key.gap, TankLayout.Key.standard] { v[k] = nil }
                if state == "roundlayout" {
                    for o in TankPoints.points(v) { TankPoints.setStatus(&v, o.id, TankPoints.ok) }
                    TankLayout.save(&v, TankLayout.auto(v), off: [])
                }
            }
            tab = state == "round" ? 1 : state == "roundobst" ? 2 : 3
        case "tab2": tab = 2
        case "design", "design64", "designcompare":
            // docs/specs/standard-designs.md: the 40 × 40 (or 64 × 40) sheet, two points checked, one moved, one absent
            update { v in
                TankDesign.apply(&v, state == "design64" ? .pwa64x40 : .pwa40x40)
                let list = TankPoints.points(v)
                TankPoints.setStatus(&v, list[0].id, TankPoints.ok)
                TankPoints.setStatus(&v, list[1].id, TankPoints.absent)
                TankPoints.move(&v, list[2].id, x: 13.7, y: nil)
                TankPoints.setStatus(&v, list[2].id, TankPoints.ok)
            }
            pointSel = TankPoints.points(values)[safe: 2]?.id
            tab = 2
            // designcompare: also a point added on site, and the เทียบกับแบบ view
            if state == "designcompare" {
                update { v in _ = TankPoints.add(&v, kind: TankPoints.vent) }
                obsCompare = true
            }
        case "obst", "obstbottom", "obstshade", "obstrow", "obstfull", "obstadded", "obstdelete":
            // docs/ui/survey-d1-obstacles-iphone: 8 of 15 checked, V6 absent, V9 moved and selected
            update { v in
                v[Roof.Key.obstacles] = nil
                TankPoints.seed(&v)
                let list = TankPoints.points(v)
                for i in [0, 1, 2, 3, 8, 10, 11] { TankPoints.setStatus(&v, list[i].id, TankPoints.ok) }
                TankPoints.setStatus(&v, list[5].id, TankPoints.absent)
                TankPoints.move(&v, list[8].id, x: 16.8, y: nil)
            }
            pointSel = TankPoints.points(values)[safe: 8]?.id
            tab = 2
            try? await Task.sleep(nanoseconds: 500_000_000)
            switch state {
            case "obstshade": obsShade = true
            case "obstrow": rowCount = 3; rowSpacing = TankPoints.rowSpacing(values); rowAsk = true
            case "obstfull": obsFull = true
            case "obstadded": addPoint(TankPoints.hatch)
            case "obstdelete": addPoint(TankPoints.vent); try? await Task.sleep(nanoseconds: 300_000_000); deleteAsk = true
            default: break
            }
        case "photo", "photomiss", "photofilter", "photodone":
            // docs/ui/survey-d1-photo-ipad states 01–04: aerial, two walls, the roof overview and the shade taken (placeholder
            // pictures, around A1's position when it has one); the surface, cable route and obstacles missing
            let site = GPS.parse(job.values.text("gps"))
            func picture(_ hue: CGFloat, _ dx: Double, _ dy: Double) -> Photo? {
                let img = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { c in
                    UIColor(hue: hue, saturation: 0.25, brightness: 0.62, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
                }
                guard var p = model.addPhoto(img, to: job.id) else { return nil }
                if let site { p.lat = site.lat + dy / 110_540; p.lon = site.lon + dx / 111_320 }
                return p
            }
            update { v in
                for k in ["aerialPhoto", "sidePhotos", Tank.Key.roofPhotos, Tank.Key.cablePhoto, Tank.Key.shadePhoto, "obstPhotos"] { v[k] = nil }
                v["aerialPhoto"] = picture(0.28, 0, 0).map { .photo($0) }
                v["sidePhotos"] = .photos([picture(0.12, 0, 26), picture(0.14, 26, 0)].compactMap { $0 })
                if var r = picture(0.6, -14, 14) { r.tag = TankPhotos.roofOverview; v[Tank.Key.roofPhotos] = .photos([r]) }
                v[Tank.Key.shadePhoto] = picture(0.33, 0, -3).map { .photo($0) }
            }
            tab = 4
            photoSel = state == "photomiss" ? TankPhotos.nextMissing(values, after: nil)?.id : "aerial"
            photoFilter = state == "photofilter" ? .missing : state == "photodone" ? .done : .all
        case "photos", "photodetails":
            // sub-step 4 with two drawn obstacle photos, the first tied to V3 with a note (photodetails opens it)
            update { v in
                v[Roof.Key.obstacles] = nil
                TankPoints.seed(&v)
                for o in TankPoints.points(v) { TankPoints.setStatus(&v, o.id, TankPoints.ok) }
            }
            let drawn = ["V3", "H1"].compactMap { name -> Photo? in
                let img = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { ctx in
                    UIColor(white: 0.55, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
                    UIColor(white: 0.35, alpha: 1).setFill(); ctx.fill(CGRect(x: 300, y: 200, width: 200, height: 200))
                    (name as NSString).draw(at: CGPoint(x: 360, y: 270), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.white])
                }
                return model.addPhoto(img, to: job.id)
            }
            update { v in
                var list = drawn
                if !list.isEmpty { list[0].tag = "V3"; list[0].note = "ฝาปล่องแตก" }
                v["obstPhotos"] = .photos(list)
            }
            if state == "photodetails" { UserDefaults.standard.set(true, forKey: "debug.openPhotoDetails") }
            tab = 4
            try? await Task.sleep(nanoseconds: 700_000_000)
            photoScroll = true
        case "layout", "layoutbottom", "layoutedit", "layoutfull", "layoutask", "layoutmax", "layoutdrawing", "layoutshade", "layoutsouth":
            // docs/ui/survey-d1-layout-iphone: the standard points of 2/4 all checked, sub-step 3 with its automatic layout
            update { v in
                v[Roof.Key.obstacles] = nil
                TankPoints.seed(&v)
                for o in TankPoints.points(v) { TankPoints.setStatus(&v, o.id, TankPoints.ok) }
                for k in [TankLayout.Key.orient, TankLayout.Key.offX, TankLayout.Key.offY, TankLayout.Key.off, TankLayout.Key.gap, TankLayout.Key.standard] { v[k] = nil }
                TankLayout.save(&v, TankLayout.auto(v), off: [])
                // layoutshade: trees 12 m high, 3 m south of the tank (the shade card); the others clear the answers
                let shade = state == "layoutshade"
                v["shade"] = shade ? .choice("มี", other: "") : nil
                v["shadeFrom"] = shade ? .multi(["ต้นไม้"]) : nil
                v["shadeDir"] = shade ? .multi(["S"]) : nil
                v[TankShade.Key.height] = shade ? .text("12") : nil
                v[TankShade.Key.distance] = shade ? .text("3") : nil
                v[Tank.Key.azimuth] = state == "layoutsouth" ? .text("12") : v[Tank.Key.azimuth]
            }
            tab = 3
            try? await Task.sleep(nanoseconds: 500_000_000)
            switch state {
            case "layoutedit", "layoutask":
                layoutEditing = true
                if let l = TankLayout.current(values) {
                    update { v in
                        TankLayout.toggle(&v, l.tables[2].panels[0].key)
                        TankLayout.removeTable(&v, row: l.tables[8].row, index: l.tables[8].index)
                    }
                }
                if state == "layoutask" { askLayout(.auto) }
            case "layoutfull": layoutFull = true
            case "layoutmax": askLayout(.max)
            case "layoutsouth":
                askLayout(.max)
                for _ in 0..<240 where southCompare == nil { try? await Task.sleep(nanoseconds: 500_000_000) }
                southOpen = southCompare != nil
            case "layoutdrawing": drawingOpen = true
            case "layoutshade": try? await Task.sleep(nanoseconds: 2_500_000_000); shadeScroll = true
            default: break
            }
        default: break
        }
    }
}
#endif
#endif
