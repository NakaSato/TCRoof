#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport
import TCRoofUI

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
    @State var rowAsk = false
    @State var rowCount = 3
    @State var rowSpacing = 4.0
    @State var deleteAsk = false
    /// iPhone sub-step 3: `แก้แผง` (else `เลื่อนผัง`), the plan full screen and its zoom, the question before a new
    /// layout, the max search running, the B1-C3 drawing.
    @State var layoutEditing = false
    @State var layoutFull = false
    @State var layoutZoom: CGFloat = 1
    @State var layoutAsk: LayoutRun?
    @State var layoutSearching = false
    @State var drawingOpen = false
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
                    tabBar
                    switch tab {
                    case 1: sizeStep
                    case 2: padObstacleStep
                    case 3: padLayoutStep
                    default: formStep
                    }
                }
            }
        }
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
                    : checked.total > 0 ? "ตรวจแล้ว \(checked.n)/\(checked.total)" : "ยังไม่เสร็จ",
                 done: points, statusOK: points),
            // a layout whose checks all pass
            Step(title: "จัดแผง", status: laid ? "\(layout?.count ?? 0) แผง · เสร็จ" : layout.map { "ตรวจผ่าน \($0.checks.passed)/3" } ?? "ยังไม่เสร็จ",
                 done: laid, statusOK: laid),
            Step(title: "ภาพถ่าย", status: "บังคับ \(photos.filled)/\(photos.total)", done: photos.isComplete, statusOK: photos.isComplete),
        ]
    }

    var tabBar: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: narrow ? 2 : 4), spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in tabSegment(i + 1, s) }
        }
        .padding(4)
        .background(Self.track, in: RoundedRectangle(cornerRadius: 14))
    }

    func tabSegment(_ n: Int, _ s: Step) -> some View {
        let on = tab == n
        return Button { withAnimation(.easeOut(duration: 0.15)) { tab = n; span = nil } } label: {
            HStack(spacing: 10) {
                stepCircle(n, done: s.done, current: on)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.title).font(.system(size: 15, weight: .bold)).foregroundStyle(on ? Theme.navy : Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
                    Text(s.status).font(.system(size: 12, weight: .semibold)).foregroundStyle(s.statusOK ? Theme.success : Theme.pending).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if on { RoundedRectangle(cornerRadius: 10).fill(Theme.surface).shadow(color: Theme.navy.opacity(0.2), radius: 1.5, y: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ขั้นที่ \(n) \(s.title) \(s.status)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder func stepCircle(_ n: Int, done: Bool, current: Bool) -> some View {
        if done {
            A2Icon(name: "d1-step-done", fallback: "checkmark.circle.fill", size: 24).foregroundStyle(Theme.success)
        } else {
            Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(current ? Theme.onPrimary : Theme.inkMuted)
                .frame(width: 24, height: 24)
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

    // MARK: sub-step 4 (the section's generic group until its design arrives)

    var formFields: [(title: String, ids: [String])] { [("ภาพถ่าย", ["obstPhotos", "aerialPhoto", "sidePhotos"])] }

    @ViewBuilder var formStep: some View {
        if let i = index {
            let fields = Schema.spec(.tank).fields
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(formFields, id: \.title) { g in
                        PaperBox(title: g.title) {
                            ForEach(g.ids.compactMap { id in fields.first { $0.id == id } }) { f in
                                if f.isVisible(job.modules[i].values) {
                                    FieldView(spec: f, values: $job.modules[i].values, jobID: job.id, moduleType: .tank, gps: job.values.text("gps"))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.onPrimary)
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
    /// and surface), compass, span, empty; tab2 opens sub-step 2. obst opens sub-step 2 as docs/ui/survey-d1-obstacles-iphone
    /// (obstbottom scrolled to the end, obstshade the shading view, obstrow the row question, obstfull the plan full screen, obstadded a hatch added
    /// on site, obstdelete the delete question). layout opens sub-step 3 as docs/ui/survey-d1-layout-iphone with every point of
    /// 2/4 checked and the automatic layout (layoutbottom scrolled to the end, layoutedit แก้แผง with a panel off and a table
    /// removed, layoutask the question before จัดแผงใหม่, layoutfull the plan full screen, layoutmax หาผังแผงมากสุด,
    /// layoutdrawing the B1-C3 sheet).
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
        case "tab2": tab = 2
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
        case "layout", "layoutbottom", "layoutedit", "layoutfull", "layoutask", "layoutmax", "layoutdrawing":
            // docs/ui/survey-d1-layout-iphone: the standard points of 2/4 all checked, sub-step 3 with its automatic layout
            update { v in
                v[Roof.Key.obstacles] = nil
                TankPoints.seed(&v)
                for o in TankPoints.points(v) { TankPoints.setStatus(&v, o.id, TankPoints.ok) }
                for k in [TankLayout.Key.orient, TankLayout.Key.offX, TankLayout.Key.offY, TankLayout.Key.off] { v[k] = nil }
                TankLayout.save(&v, TankLayout.auto(v), off: [])
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
            case "layoutdrawing": drawingOpen = true
            default: break
            }
        default: break
        }
    }
}
#endif
#endif
