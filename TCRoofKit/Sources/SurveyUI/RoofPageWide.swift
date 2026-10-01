#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// C1 roof on iPad landscape (docs/ui/survey-c1): the interactive roof plan above section A-A on the left; the roof
/// info, member sizes 1–7 and the six photo angles on the right, on one screen. Field ids, choices and Excel cells are
/// unchanged; the page's own answers are hidden optional fields (`Roof.Key`). iPad portrait and iPhone keep `groupPage`.
struct RoofPageWide: View {
    @Binding var job: Job
    let moduleID: UUID
    /// Width of the page's content.
    let width: CGFloat
    /// One column (plan and section on top, the cards below, scrolling): portrait or a free width under 1100 pt.
    var stacked = false
    /// false lays the stacked column out without its ScrollView (DEBUG offscreen render).
    var scrolls = true
    @Environment(SurveyModel.self) var model

    struct SpanRef: Hashable { var axis: Roof.Axis; var index: Int }
    enum Tool { case keepOut, skylight }

    @State var mode: RoofPlan.Mode = .structure
    @State var span: SpanRef?
    @State var editPosts = false
    @State var tool: Tool?
    /// The rectangle being dragged out, metres (x1, y1, x2, y2).
    @State var drag: (Double, Double, Double, Double)?
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

    var gap: CGFloat { width >= 1180 ? 28 : 20 }
    /// Side by side only: the plan / section column.
    var leftWidth: CGFloat { min(720, (width - gap) * 0.58) }
    /// Width of the cards' column (photo tiles go 3 × 2 under 520 pt).
    var cardsWidth: CGFloat { stacked ? width : width - leftWidth - gap }

    var index: Int? { job.modules.firstIndex { $0.id == moduleID } }
    var values: Values { index.map { job.modules[$0].values } ?? Values() }
    func update(_ f: (inout Values) -> Void) { if let i = index { f(&job.modules[i].values) } }
    func set(_ id: String, _ v: FieldValue?) { update { $0[id] = v } }

    static let track = Color(red: 0.933, green: 0.949, blue: 0.969)
    static let soft = Color(red: 0.890, green: 0.933, blue: 0.973)
    static let red = Color(red: 0.851, green: 0.271, blue: 0.231)
    static let line = Color(red: 0.867, green: 0.894, blue: 0.929)

    var body: some View {
        VStack(spacing: 16) {
            PageStepBar(job: job, here: .module(moduleID), title: "แปลนและโครงสร้างหลังคา")
            if stacked { stackedLayout } else { wideLayout }
        }
        .foregroundStyle(Home.navy)
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
    }

    var wideLayout: some View {
        HStack(alignment: .top, spacing: gap) {
            // the section keeps the design's 262 pt on a tall screen and gives the plan room on a short one (11" landscape)
            GeometryReader { geo in
                VStack(spacing: 12) {
                    planCard.frame(maxHeight: .infinity)
                    sectionCard.frame(height: min(262, max(190, geo.size.height * 0.36)))
                }
            }
            .frame(width: leftWidth)
            // one screen when it fits (13"); a short screen (11" landscape) scrolls the cards only
            ViewThatFits(in: .vertical) {
                cardsColumn(fill: true)
                ScrollView { cardsColumn(fill: false).padding(.bottom, 4) }.scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    func cardsColumn(fill: Bool) -> some View {
        VStack(spacing: 10) {
            infoCard
            membersCard.frame(maxHeight: fill ? .infinity : nil)
            photosCard
        }
    }

    /// Portrait or narrow: the drawings at full width keep their aspect, the cards follow; one scrolling column.
    @ViewBuilder var stackedLayout: some View {
        if scrolls { ScrollView { stackedColumn }.scrollIndicators(.hidden) } else { stackedColumn }
    }

    var stackedColumn: some View {
            VStack(spacing: 12) {
                planCard.frame(height: min(620, width * RoofPlan.height / RoofPlan.width) + 64)
                sectionCard.frame(height: min(340, width * RoofSection.height / RoofSection.width) + 72)
                infoCard
                membersCard
                photosCard
            }
            .padding(.bottom, 4)
    }

    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.2)))
    }

    func cardTitle(_ t: String, trailing: String? = nil, trailingColor: Color = Home.muted, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            (Text(t) + Text(" *").foregroundColor(Home.danger)).font(.system(size: 17, weight: .bold)).lineLimit(1)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.system(size: 12.5, weight: bold ? .bold : .regular)).foregroundStyle(trailingColor).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: roof info

    var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle("ข้อมูลหลังคา", trailing: "ตามแผนงาน ข้อ 1–3")
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    dropdownField("รูปแบบหลังคา", key: Roof.Key.shape, list: Roof.shapes).gridCellColumns(3)
                    dropdownField("วัสดุมุง", key: Roof.Key.material, list: Roof.materials).gridCellColumns(3)
                }
                GridRow {
                    panelsField.gridCellColumns(2)
                    ridgeField.gridCellColumns(2)
                    structureField.gridCellColumns(2)
                }
                GridRow {
                    VStack(alignment: .leading, spacing: 3) {
                        A3Label(text: "ชนิดโครงหลังคา")
                        RoofSegments(options: RoofFrame.ordered.map(\.label), selected: RoofFrame.ordered.firstIndex(of: Roof.frame(values)), minSegment: 84) { i in
                            update { Roof.setFrame(&$0, RoofFrame.ordered[i]) }
                        }
                    }
                    .gridCellColumns(6)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.2)))
    }

    var panelsField: some View {
        VStack(alignment: .leading, spacing: 3) {
            A3Label(text: "จำนวนแผง")
            HStack(spacing: 4) {
                TextField("", text: Binding(get: { values.text(Roof.Key.panels) }, set: { set(Roof.Key.panels, $0.isEmpty ? nil : .text($0)) }))
                    .keyboardType(.numberPad)
                Text("แผง").font(.system(size: 14)).foregroundStyle(Home.muted).lineLimit(1)
            }
            .inputBox(minHeight: 44, trailing: 10)
        }
        .frame(maxWidth: .infinity)
    }

    var ridgeField: some View {
        VStack(alignment: .leading, spacing: 3) {
            A3Label(text: "แนวสันหลังคา")
            RoofSegments(options: ["นอน", "ตั้ง"], selected: Roof.ridge(values) == .h ? 0 : 1, minSegment: 52) { i in
                update { Roof.setRidge(&$0, i == 0 ? .h : .v) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    var structureField: some View {
        let wood = values.choice(Roof.Key.structure)
        return VStack(alignment: .leading, spacing: 3) {
            A3Label(text: "วัสดุโครงสร้าง")
            RoofSegments(options: ["ไม้", "เหล็ก"], selected: wood == "ไม้" ? 0 : wood == "โครงเหล็ก" ? 1 : nil, minSegment: 52) { i in
                set(Roof.Key.structure, .choice(Options.structure[i], other: ""))
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
                    Text(shown ?? "เลือก").font(.system(size: 17)).foregroundStyle(shown == nil ? Home.muted : Home.navy).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(Home.primary)
                }
                .inputBox(focused: open, minHeight: 44, trailing: 12)
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
                            Text(o.name).font(.system(size: 16, weight: on ? .bold : .regular))
                            Text(o.sub).font(.system(size: 12)).foregroundStyle(Home.muted)
                        }
                        Spacer(minLength: 8)
                        if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Home.primary) }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .background(on ? Self.soft : Color.white)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Divider()
            Button { otherText = values.other(key); otherKey = key; dropdown = nil } label: {
                HStack {
                    Text(other ? "อื่นๆ: " + (Roof.shown(values, key, in: list) ?? "") : "อื่นๆ (ระบุเอง)").font(.system(size: 15, weight: other ? .bold : .regular))
                    Spacer()
                    if other { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Home.primary) }
                }
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(other ? Self.soft : Color.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Home.navy)
        .frame(width: 300)
        .padding(.vertical, 6)
    }
}

/// The design's segmented control: a grey track, the chosen segment white with a soft shadow and bold navy text.
/// When the segments can't get `minSegment` each, it falls back to a menu with the same values.
struct RoofSegments: View {
    let options: [String]
    let selected: Int?
    var minSegment: CGFloat = 56
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
                    Text(o).font(.system(size: 15, weight: on ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundStyle(on ? Home.navy : Home.muted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 8).fill(Color.white).shadow(color: Home.navy.opacity(0.25), radius: 1.5, y: 1) }
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
                Text(selected.map { options[$0] } ?? "เลือก").font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(selected == nil ? Home.muted : Home.navy)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Home.primary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoofPageWide.track, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
#endif
