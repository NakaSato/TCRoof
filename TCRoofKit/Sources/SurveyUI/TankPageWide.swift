#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// D1 clear-water tank (docs/ui/survey-d1-size): four sub-steps in a tab bar. Sub-step 1 "ขนาดถัง"
/// is the designed page (the tank plan on the left, the tank's data on the right); sub-steps 2–4 show the section's
/// generic groups until their designs arrive. Field ids, labels and Excel cells are unchanged; the page's own answers
/// are hidden optional fields (`Tank.Key`). iPad portrait and iPhone use the one-column layout.
struct TankPageWide: View {
    @Binding var job: Job
    let moduleID: UUID
    /// Width of the page's content.
    let width: CGFloat
    /// One column (the plan on top, the card below, scrolling): portrait, iPhone or a free width under 1100 pt.
    var stacked = false
    /// iPhone: the sub-step tabs two to a row, a taller plan.
    var narrow: Bool { width < 600 }
    @Environment(SurveyModel.self) var model

    /// The sub-step shown (view state only, never stored in the job).
    @State var tab = 1
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

    var gap: CGFloat { width >= 1180 ? 20 : 16 }
    static let cardWidth: CGFloat = 330
    static let track = Color(red: 0.933, green: 0.949, blue: 0.969)
    static let teal = Color(red: 0.624, green: 0.890, blue: 0.827)

    var index: Int? { job.modules.firstIndex { $0.id == moduleID } }
    var values: Values { index.map { job.modules[$0].values } ?? Values() }
    func update(_ f: (inout Values) -> Void) { if let i = index { f(&job.modules[i].values) } }
    func set(_ id: String, _ v: FieldValue?) { update { $0[id] = v } }

    var body: some View {
        VStack(spacing: 14) {
            PageStepBar(job: job, here: .module(moduleID), title: narrow ? "ถังน้ำใส" : "ถังน้ำใส · ขนาด สิ่งกีดขวาง/เงาบัง จัดแผง ภาพ")
            tabBar
            if tab == 1 { sizeStep } else { formStep }
        }
        .foregroundStyle(Home.navy)
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
        let obst = v.obstacles(Roof.Key.obstacles).count
        let panels = v.text("panelsBefore").trimmingCharacters(in: .whitespaces)
        func status(_ done: Bool, _ s: String) -> String { done ? s + " · เสร็จ" : "ยังไม่เสร็จ" }
        return [
            Step(title: "ขนาดถัง", status: status(Tank.sizeDone(v), size), done: Tank.sizeDone(v), statusOK: Tank.sizeDone(v)),
            Step(title: "สิ่งกีดขวาง · เงาบัง", status: status(shade.isComplete, "\(obst) จุด"), done: shade.isComplete, statusOK: shade.isComplete),
            Step(title: "จัดแผง", status: status(!panels.isEmpty, panels + " แผง"), done: !panels.isEmpty, statusOK: !panels.isEmpty),
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
                    Text(s.title).font(.system(size: 15, weight: .bold)).foregroundStyle(on ? Home.navy : Home.muted).lineLimit(1).minimumScaleFactor(0.7)
                    Text(s.status).font(.system(size: 12, weight: .semibold)).foregroundStyle(s.statusOK ? Home.ok : Home.orange).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if on { RoundedRectangle(cornerRadius: 10).fill(Color.white).shadow(color: Home.navy.opacity(0.2), radius: 1.5, y: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ขั้นที่ \(n) \(s.title) \(s.status)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder func stepCircle(_ n: Int, done: Bool, current: Bool) -> some View {
        if done {
            A2Icon(name: "d1-step-done", fallback: "checkmark.circle.fill", size: 24).foregroundStyle(Home.ok)
        } else {
            Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(current ? Color.white : Home.muted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(current ? Home.primary : Color.white))
                .overlay(Circle().stroke(current ? Color.clear : Home.navy.opacity(0.25)))
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
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.2)))
    }

    // MARK: sub-steps 2–4 (the section's generic groups until their designs arrive)

    var formFields: [(title: String, ids: [String])] {
        switch tab {
        case 2: return [("สิ่งกีดขวางบนถัง", ["obst", "plan"]), ("เงาบัง", ["shade", "shadeFrom", "shadeDir", "shadeNote"])]
        case 3: return [("จัดแผง", ["panelsBefore", "panelsCut", "planPhoto"])]
        default: return [("ภาพถ่าย", ["obstPhotos", "aerialPhoto", "sidePhotos"])]
        }
    }

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
                    if tab < 4 {
                        HStack {
                            Spacer()
                            nextButton(tab == 2 ? "ถัดไป · จัดแผง ›" : "ถัดไป · ภาพถ่าย ›") { tab += 1 }.frame(maxWidth: Self.cardWidth)
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
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Home.primary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
extension TankPageWide {
    /// `-surveyD1 <state>` seeds the design's example tank (40 × 40, ค.ส.ล., กึ่งฝัง, 4.50 / 1.20, คอนกรีต, 12°) and
    /// opens a state of docs/ui/survey-d1-size/states: default, size, t64, t30, t20, above, buried, custom (typed azimuth
    /// and surface), compass, span, empty.
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
        case "span": span = RoofPageWide.SpanRef(axis: .x, index: 2)
        case "empty": update { $0[Roof.Key.spansX] = nil; $0[Roof.Key.spansY] = nil }
        default: break
        }
    }
}
#endif
#endif
