#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// A1 on iPad: the cover as cards (docs/ui/survey-a1-ipad) — two columns of equal height that fill one screen in landscape
/// (location on the left, its map taking the free height), one column in portrait.
/// Every field keeps its `Schema.info` id and label, so Excel, PDF and completion are unchanged.
struct InfoPageWide: View {
    @Binding var job: Job
    /// Width of the editor's detail area; the location column narrows when the sidebar is open.
    let width: CGFloat
    var twoColumns = true
    /// Landscape: the height the page fills (the scroll view's visible height less its padding); 0 for none.
    var fillHeight: CGFloat = 0
    @Environment(SurveyModel.self) var model
    @Environment(\.openURL) var openURL
    /// iPhone: `phoneBody` (docs/ui/survey-a1-iphone) in place of the cards.
    @Environment(\.horizontalSizeClass) var sizeClass
    @FocusState var focus: String?
    @State var showDate = false
    @State var areaChange: AreaChange?
    @State var locator = GPSLocator()
    @State var locating = false
    @State var fix: (accuracy: Double, time: Date)?
    @State var gpsFailure: String?
    /// Best accuracy so far while locating, shown on the button.
    @State var liveAccuracy: Double?

    struct AreaChange: Identifiable { let id = UUID(); let losing: [SurveyModule] }

    /// Filled from the linked TCRoof job (`SurveyModel.fill`), shown on the mint "calc" background.
    static let prefilled: Set<String> = ["projectName", "capacity", "coordinator", "phone", "address", "date"]

    /// Corners of the iPad inputs (iPhone keeps 10).
    static let inputRadius: CGFloat = 12
    static let columnGap: CGFloat = 20

    /// The location card (720 of the design's 1240); narrower when the sidebar is open.
    var locationWidth: CGFloat { min(720, max(360, (width - Self.columnGap) * 0.58)) }
    /// Width of the column holding the document, project and area boxes.
    var mainWidth: CGFloat { twoColumns ? width - Self.columnGap - locationWidth : width }
    /// iPhone width: the document row splits in two and the GPS button keeps only its icon.
    var phone: Bool { width < 500 }

    var body: some View {
        Group {
            if sizeClass == .compact { phoneBody } else { padBody }
        }
        .foregroundStyle(Theme.navy)
        .confirmationDialog("ลบหัวข้อที่กรอกข้อมูลแล้ว?", isPresented: Binding(get: { areaChange != nil }, set: { if !$0 { areaChange = nil } }),
                            titleVisibility: .visible, presenting: areaChange) { c in
            Button("ลบ \(c.losing.count) หัวข้อ", role: .destructive) { remove(c.losing) }
            Button("ยกเลิก", role: .cancel) { areaChange = nil }
        } message: { c in
            Text((c.losing.map(sectionName) + ["ข้อมูลและรูปภาพในหัวข้อเหล่านี้จะถูกลบ"]).joined(separator: "\n"))
        }
    }

    @ViewBuilder var padBody: some View {
        if twoColumns {
            MinHeight(height: fillHeight) {
                VStack(spacing: 16) {
                    stepBar
                    // both columns take the taller one's height (or the screen's): the map and the project card grow
                    HStack(alignment: .top, spacing: Self.columnGap) {
                        locationBox.frame(width: locationWidth).frame(maxHeight: .infinity)
                        VStack(spacing: 14) { documentBox; projectCoordinatorBox.frame(maxHeight: .infinity); areasBox }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        } else {
            VStack(spacing: 16) {
                stepBar
                VStack(spacing: 14) { locationBox; documentBox; projectCoordinatorBox; areasBox }
            }
        }
    }

    // MARK: step bar

    var stepBar: some View { PageStepBar(job: job, here: .info) }

    // MARK: right column

    var documentBox: some View {
        A1Card(title: "เอกสาร") {
            // narrow (iPad portrait beside the sidebar): number and REV over date and engineer
            if phone {
                RatioRow(weights: [1, 0.7], spacing: 10) {
                    field("docNo", title: "เลขที่") { textInput("docNo", keyboard: .numbersAndPunctuation) }
                    field("rev", aside: "") { textInput("rev", keyboard: .numbersAndPunctuation) }
                }
                field("date", title: "วันที่สำรวจ") { dateInput }
                field("engineer", title: "วิศวกรผู้สำรวจ") { engineerInput }
            } else {
                RatioRow(weights: [0.8, 0.6, 1.35, 1.25], spacing: 10) {
                    field("docNo", title: "เลขที่") { textInput("docNo", keyboard: .numbersAndPunctuation) }
                    field("rev", aside: "") { textInput("rev", keyboard: .numbersAndPunctuation) }
                    field("date", title: "วันที่สำรวจ") { dateInput }
                    field("engineer", title: "วิศวกรผู้สำรวจ") { engineerInput }
                }
            }
        }
    }

    /// Project and coordinator in one card; in landscape its rows spread over the height the column leaves
    /// (the design's `justify-content: space-between`, at least 14 apart).
    var projectCoordinatorBox: some View {
        A1Card(title: "โครงการ · ผู้ประสานงาน", spacing: 0) {
            let gap = Spacer(minLength: 14)
            gap
            field("projectName") { textInput("projectName") }
            gap
            RatioRow(weights: [1, 1]) {
                field("capacity", title: "ขนาดที่ต้องการติดตั้ง") { capacityInput }
                field("internet") { internetInput }
            }
            gap
            field("address") {
                TextField("", text: text("address"), axis: .vertical).lineLimit(1...3).focused($focus, equals: "address")
                    .padding(.vertical, 13)
                    .inputBox(calc: calc("address"), focused: focus == "address", radius: Self.inputRadius)
            }
            gap
            if phone {
                field("coordinator") { textInput("coordinator") }
                gap
                field("phone") { phoneInput }
            } else {
                RatioRow(weights: [1.4, 1]) {
                    field("coordinator") { textInput("coordinator") }
                    field("phone") { phoneInput }
                }
            }
        }
    }

    // MARK: inputs

    var dateInput: some View { dateButton(compact: false) }

    func dateButton(compact: Bool) -> some View {
        let t = job.values.text("date")
        return Button { showDate = true } label: {
            HStack(spacing: 6) {
                Text(t.isEmpty ? "เลือกวันที่" : ISODate.thai(t)).foregroundStyle(t.isEmpty ? Theme.inkMuted : Theme.navy).lineLimit(1)
                Spacer(minLength: 4)
                A2Icon(name: "ui-calendar", fallback: "calendar", size: compact ? 16 : 20).foregroundStyle(Theme.primary)
            }
            .inputBox(calc: calc("date"), focused: showDate, minHeight: compact ? 44 : 50, trailing: compact ? 12 : 14,
                      leading: compact ? 12 : 14, fontSize: compact ? 16 : 17, stroke: compact ? 0.35 : 0.45, radius: compact ? 10 : Self.inputRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("วันที่ " + ISODate.thai(t))
        .popover(isPresented: $showDate) {
            DatePicker("วันที่", selection: Binding(get: { ISODate.date(job.values.text("date")) ?? Date() },
                                                     set: { job.values["date"] = .text(ISODate.string($0)) }), displayedComponents: .date)
                .datePickerStyle(.graphical).labelsHidden()
                .environment(\.locale, Locale(identifier: "th_TH"))
                .environment(\.calendar, Calendar(identifier: .buddhist))
                .frame(width: 340).padding()
        }
    }

    var engineerInput: some View {
        let mine = model.settings.engineer.trimmingCharacters(in: .whitespaces)
        let value = job.values.text("engineer").trimmingCharacters(in: .whitespaces)
        return HStack(spacing: 6) {
            TextField(mine.isEmpty ? "ชื่อวิศวกร" : mine, text: text("engineer")).focused($focus, equals: "engineer")
            if !mine.isEmpty && value.isEmpty {
                Button("ใช้ชื่อฉัน") { job.values["engineer"] = .text(mine) }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.primary).frame(minHeight: 44).fixedSize()
            }
        }
        .inputBox(focused: focus == "engineer", radius: Self.inputRadius)
    }

    var capacityInput: some View {
        let bad = !NumberInput.isValid(job.values.text("capacity"))
        return HStack(spacing: 6) {
            TextField("0", text: Binding(get: { job.values.text("capacity") }, set: {
                let c = NumberInput.clean($0)
                job.values["capacity"] = c.isEmpty ? nil : .text(c)
            }))
            .keyboardType(.decimalPad).focused($focus, equals: "capacity")
            Text(unit("capacity")).font(.sarabunFixed(16)).foregroundStyle(Theme.inkMuted)
        }
        .inputBox(calc: calc("capacity"), focused: focus == "capacity", error: bad, radius: Self.inputRadius)
    }

    var internetInput: some View {
        let chosen = job.values.choice("internet")
        return HStack(spacing: 10) {
            ForEach(Options.yesNo, id: \.self) { o in
                let on = chosen == o
                Button {
                    job.values["internet"] = on ? nil : .choice(o, other: "")
                } label: {
                    Text(o).font(.sarabunFixed(17, .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(on ? Theme.mint : Theme.surface, in: RoundedRectangle(cornerRadius: Self.inputRadius))
                        .overlay(RoundedRectangle(cornerRadius: Self.inputRadius).stroke(Theme.navy.opacity(on ? 0.2 : 0.5)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    var phoneInput: some View {
        let digits = job.values.text("phone").filter { $0.isNumber || $0 == "+" }
        return HStack(spacing: 4) {
            TextField("0xx-xxx-xxxx", text: text("phone")).keyboardType(.phonePad).focused($focus, equals: "phone")
            Button { if let u = URL(string: "tel:" + digits) { openURL(u) } } label: {
                A2Icon(name: "ui-phone", fallback: "phone", size: 20).foregroundStyle(Theme.primary).frame(width: 40, height: 44)
            }
            .disabled(digits.isEmpty)
            .accessibilityLabel("โทรหาผู้ประสานงาน")
        }
        .inputBox(calc: calc("phone"), focused: focus == "phone", trailing: 4, radius: Self.inputRadius)
    }

    func textInput(_ id: String, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder(id), text: text(id))
            .keyboardType(keyboard).focused($focus, equals: id)
            .inputBox(calc: calc(id), focused: focus == id, radius: Self.inputRadius)
    }

    // MARK: fields

    func spec(_ id: String) -> FieldSpec { Schema.info.fields.first { $0.id == id }! }

    /// Label as on the sheet: `*` for required, "สำคัญ" for `**` fields, "ยังขาด" while a required field is empty.
    /// `title` is the board's shorter wording on screen (the sheet's label stays in `Schema.info`).
    func field<C: View>(_ id: String, title: String? = nil, aside: String? = nil, @ViewBuilder control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(spec: spec(id), filled: spec(id).isFilled(job.values), title: title, aside: aside)
            control()
        }
    }

    func text(_ id: String) -> Binding<String> {
        Binding(get: { job.values.text(id) }, set: { job.values[id] = $0.isEmpty ? nil : .text($0) })
    }
    func placeholder(_ id: String) -> String {
        if case .text(let ph) = spec(id).kind, !ph.isEmpty { return ph }
        return ""
    }
    func unit(_ id: String) -> String {
        if case .number(let u) = spec(id).kind { return u }
        return ""
    }
    func calc(_ id: String) -> Bool {
        job.jobSyncID != nil && Self.prefilled.contains(id) && spec(id).isFilled(job.values)
    }
}

/// Field label of the A1 layout.
struct FieldLabel: View {
    let spec: FieldSpec
    let filled: Bool
    /// iPhone (docs/ui/survey-a1-iphone): 14 pt, a red `*` only, and `aside` at the trailing edge in 12 pt
    /// ("" for none; nil keeps "ไม่บังคับ" on optional fields). `title` replaces the sheet's label on screen.
    var compact = false
    var title: String? = nil
    var aside: String? = nil
    var body: some View {
        if compact { compactBody } else { regularBody }
    }

    var compactBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title ?? spec.label.replacingOccurrences(of: "**", with: "")).font(.sarabunFixed(14, .semibold))
                .lineLimit(1).minimumScaleFactor(0.8).layoutPriority(1)
            if !spec.optional { Text("*").font(.sarabunFixed(14, .semibold)).foregroundStyle(Theme.danger) }
            Spacer(minLength: 4)
            if let aside = aside ?? (spec.optional ? "ไม่บังคับ" : nil), !aside.isEmpty {
                Text(aside).font(.sarabunFixed(12)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(Theme.navy)
        .frame(height: 18)
    }

    @ViewBuilder var regularBody: some View {
        let important = title == nil && spec.label.hasPrefix("**")
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title ?? spec.label.replacingOccurrences(of: "**", with: ""))
                .font(.sarabunFixed(17, .semibold)).lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
            if !spec.optional { Text("*").font(.sarabunFixed(17, .semibold)).foregroundStyle(Theme.danger) }
            if important {
                Text("สำคัญ").font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 1)
                    .background(Theme.sun, in: Capsule())
            }
            Spacer(minLength: 4)
            // narrow columns keep the label and drop the words (the dot stays)
            if spec.optional {
                // `aside: ""` (iPad A1's REV.) shows no "ไม่บังคับ"
                if aside != "" {
                    ViewThatFits { Text("ไม่บังคับ").font(.footnote).foregroundStyle(Theme.inkMuted).fixedSize(); Color.clear.frame(width: 0, height: 0) }
                }
            } else if !filled {
                let dot = Circle().fill(Theme.pending).frame(width: 7, height: 7)
                ViewThatFits {
                    HStack(spacing: 4) { dot; Text("ยังขาด").font(.footnote.weight(.semibold)).foregroundStyle(Theme.pending) }.fixedSize()
                    dot
                }
                .accessibilityLabel("ยังขาด")
            }
        }
        .foregroundStyle(Theme.navy)
    }
}

/// White box with an 18-pt title, 12-pt corners and a light navy border.
struct A1Card<Content: View>: View {
    let title: String
    var required = false
    var trailing: String? = nil
    var spacing: CGFloat = 14
    /// Top and bottom padding (พื้นที่ติดตั้ง: 14).
    var vertical: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.sarabunFixed(18, .bold))
                if required { Text("*").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.danger) }
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(.footnote).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8) }
            }
            content
        }
        .padding(.vertical, vertical).padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
    }
}

/// "2/13 … ภาพสถานที่ติดตั้ง" and one bar per step, the open one in blue (card pages A1, A2).
struct PageStepBar: View {
    let job: Job
    let here: MissingGroup.Target
    /// Shown on the right in place of the step's title (B1: "ตู้ไฟฟ้าอาคาร · 3 อาคาร").
    var title: String? = nil
    /// iPhone (docs/ui/survey-d1-size-iphone): the step's name in grey after the count, this chip on the right,
    /// 6-pt bars with done steps green.
    var compact = false
    var chip: (text: String, ok: Bool)? = nil

    /// iPhone: pages that don't ask for `compact` get it anyway, with the step's own completion as the chip.
    @Environment(\.horizontalSizeClass) var sizeClass

    var body: some View {
        if compact || sizeClass == .compact { compactBody } else { regularBody }
    }

    var compactBody: some View {
        let chip = compact ? chip : job.stepChip(here)
        let steps = job.steps
        let i = steps.firstIndex { $0.page == here } ?? 0
        return VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text("\(i + 1)/\(steps.count)").font(.sarabunFixed(14, .bold)).monospacedDigit()
                Text(title ?? steps[safe: i]?.title ?? "").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Spacer(minLength: 4)
                if let chip {
                    Text(chip.text).font(.sarabunFixed(11.5, .bold)).foregroundStyle(chip.ok ? Theme.okTick : Theme.pending)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 1)
                        .background(chip.ok ? Theme.okSoft : Theme.pendingSoft, in: Capsule())
                }
            }
            HStack(spacing: 2) {
                ForEach(Array(steps.enumerated()), id: \.offset) { n, s in
                    Capsule().fill(n == i ? Theme.primary : s.completion.total > 0 && s.completion.isComplete ? Theme.stepDone : Theme.borderSubtle)
                        .frame(height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    var regularBody: some View {
        let steps = job.steps
        let i = steps.firstIndex { $0.page == here } ?? 0
        return VStack(spacing: 10) {
            HStack {
                Text("\(i + 1)/\(steps.count)").bold()
                Spacer()
                Text(title ?? steps[safe: i]?.title ?? "")
            }
            .font(.sarabunFixed(15))
            HStack(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { n, s in
                    Capsule().fill(n == i ? AnyShapeStyle(LinearGradient(colors: [Theme.primary, Theme.primaryLight], startPoint: .leading, endPoint: .trailing))
                                   : s.completion.total > 0 && s.completion.isComplete ? AnyShapeStyle(Theme.mint) : AnyShapeStyle(Theme.track))
                        .frame(height: 8)
                }
            }
        }
    }
}

/// Columns in fixed proportions (the design's `1fr 0.7fr 1.2fr 1.6fr`), children top-aligned.
struct RatioRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = 12

    func widths(_ total: CGFloat) -> [CGFloat] {
        let free = total - spacing * CGFloat(max(weights.count - 1, 0)), sum = weights.reduce(0, +)
        return weights.map { free * $0 / sum }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600
        let h = zip(subviews, widths(w)).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (v, w) in zip(subviews, widths(bounds.width)) {
            v.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: nil))
            x += w + spacing
        }
    }
}

/// Its content at least `height` high: given the extra height, flexible children (A1's map and project card) take it.
/// A scroll view offers no height, so a plain `frame(minHeight:)` would leave them at their ideal size.
struct MinHeight: Layout {
    var height: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        return CGSize(width: proposal.width ?? s.width, height: max(s.height, height))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

extension View {
    /// Outlined input: 50 high, 10-pt corners (12 on iPad A1), navy 45% border (2-pt primary when focused), mint when filled from the job.
    /// iPhone A1 passes `minHeight: 44`, `leading: 12`, `fontSize: 16` and a 35% stroke.
    func inputBox(calc: Bool = false, focused: Bool = false, error: Bool = false, minHeight: CGFloat = 50, trailing: CGFloat = 14,
                  leading: CGFloat = 14, fontSize: CGFloat = 17, stroke: Double = 0.45, radius: CGFloat = 10) -> some View {
        font(.system(size: fontSize)).foregroundStyle(Theme.navy)
            .padding(.leading, leading).padding(.trailing, trailing)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(calc ? Theme.mint.opacity(0.3) : Theme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .stroke(error ? Theme.danger : focused ? Theme.primary : Theme.navy.opacity(stroke), lineWidth: error || focused ? 2 : 1))
    }
}
#endif
