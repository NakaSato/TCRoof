#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// A1 on iPad: the cover as cards (docs/ui/survey-a1) — two columns that fit one screen in landscape (location on the left),
/// one column in portrait.
/// Every field keeps its `Schema.info` id and label, so Excel, PDF and completion are unchanged.
struct InfoPageWide: View {
    @Binding var job: Job
    /// Width of the editor's detail area; the location column narrows when the sidebar is open.
    let width: CGFloat
    var twoColumns = true
    @Environment(SurveyModel.self) var model
    @Environment(\.openURL) var openURL
    @FocusState var focus: String?
    @State var showDate = false
    @State var areaChange: AreaChange?
    @State var locator = GPSLocator()
    @State var locating = false
    @State var fix: (accuracy: Double, time: Date)?
    @State var gpsFailure: String?

    struct AreaChange: Identifiable { let id = UUID(); let losing: [SurveyModule] }

    /// Filled from the linked TCRoof job (`SurveyModel.fill`), shown on the mint "calc" background.
    static let prefilled: Set<String> = ["projectName", "capacity", "coordinator", "phone", "address", "date"]

    /// The location card (~620 of the design's 1240); narrower when the sidebar is open.
    var locationWidth: CGFloat { min(620, max(360, (width - 28) * 0.5)) }
    /// Width of the column holding the document, project and area boxes.
    var mainWidth: CGFloat { twoColumns ? width - 28 - locationWidth : width }
    /// iPhone width: the document row splits in two and the GPS button keeps only its icon.
    var phone: Bool { width < 500 }

    var body: some View {
        VStack(spacing: 16) {
            stepBar
            if twoColumns {
                HStack(alignment: .top, spacing: 28) {
                    locationBox.frame(width: locationWidth)
                    VStack(spacing: 16) { documentBox; projectBox; coordinatorBox; areasBox }
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 16) { locationBox; documentBox; projectBox; coordinatorBox; areasBox }
            }
        }
        .foregroundStyle(Home.navy)
        .confirmationDialog("ลบหัวข้อที่กรอกข้อมูลแล้ว?", isPresented: Binding(get: { areaChange != nil }, set: { if !$0 { areaChange = nil } }),
                            titleVisibility: .visible, presenting: areaChange) { c in
            Button("ลบ \(c.losing.count) หัวข้อ", role: .destructive) { remove(c.losing) }
            Button("ยกเลิก", role: .cancel) { areaChange = nil }
        } message: { c in
            Text((c.losing.map(sectionName) + ["ข้อมูลและรูปภาพในหัวข้อเหล่านี้จะถูกลบ"]).joined(separator: "\n"))
        }
    }

    // MARK: step bar

    var stepBar: some View { PageStepBar(job: job, here: .info) }

    // MARK: right column

    var documentBox: some View {
        A1Card(title: "เอกสาร") {
            if phone {
                RatioRow(weights: [1, 0.7]) {
                    field("docNo") { textInput("docNo", keyboard: .numbersAndPunctuation) }
                    field("rev") { textInput("rev", keyboard: .numbersAndPunctuation) }
                }
                field("date") { dateInput }
                field("engineer") { engineerInput }
            } else {
                RatioRow(weights: [1, 0.7, 1.2, 1.6]) {
                    field("docNo") { textInput("docNo", keyboard: .numbersAndPunctuation) }
                    field("rev") { textInput("rev", keyboard: .numbersAndPunctuation) }
                    field("date") { dateInput }
                    field("engineer") { engineerInput }
                }
            }
        }
    }

    var projectBox: some View {
        A1Card(title: "โครงการ") {
            field("projectName") { textInput("projectName") }
            RatioRow(weights: [1, 1]) {
                field("capacity") { capacityInput }
                field("internet") { internetInput }
            }
        }
    }

    var coordinatorBox: some View {
        A1Card(title: "ผู้ประสานงาน") {
            if phone {
                field("coordinator") { textInput("coordinator") }
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

    var dateInput: some View {
        let t = job.values.text("date")
        return Button { showDate = true } label: {
            HStack(spacing: 6) {
                Text(t.isEmpty ? "เลือกวันที่" : ISODate.thai(t)).foregroundStyle(t.isEmpty ? Home.muted : Home.navy).lineLimit(1)
                Spacer(minLength: 4)
                A2Icon(name: "ui-calendar", fallback: "calendar", size: 20).foregroundStyle(Home.primary)
            }
            .inputBox(calc: calc("date"), focused: showDate)
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
                    .font(.footnote.weight(.semibold)).foregroundStyle(Home.primary).frame(minHeight: 44).fixedSize()
            }
        }
        .inputBox(focused: focus == "engineer")
    }

    var capacityInput: some View {
        let bad = !NumberInput.isValid(job.values.text("capacity"))
        return HStack(spacing: 6) {
            TextField("0", text: Binding(get: { job.values.text("capacity") }, set: {
                let c = NumberInput.clean($0)
                job.values["capacity"] = c.isEmpty ? nil : .text(c)
            }))
            .keyboardType(.decimalPad).focused($focus, equals: "capacity")
            Text(unit("capacity")).font(.system(size: 16)).foregroundStyle(Home.muted)
        }
        .inputBox(calc: calc("capacity"), focused: focus == "capacity", error: bad)
    }

    var internetInput: some View {
        let chosen = job.values.choice("internet")
        return HStack(spacing: 10) {
            ForEach(Options.yesNo, id: \.self) { o in
                let on = chosen == o
                Button {
                    job.values["internet"] = on ? nil : .choice(o, other: "")
                } label: {
                    Text(o).font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(on ? Home.mint : Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(on ? 0.2 : 0.5)))
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
                A2Icon(name: "ui-phone", fallback: "phone", size: 20).foregroundStyle(Home.primary).frame(width: 40, height: 44)
            }
            .disabled(digits.isEmpty)
            .accessibilityLabel("โทรหาผู้ประสานงาน")
        }
        .inputBox(calc: calc("phone"), focused: focus == "phone", trailing: 4)
    }

    func textInput(_ id: String, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder(id), text: text(id))
            .keyboardType(keyboard).focused($focus, equals: id)
            .inputBox(calc: calc(id), focused: focus == id)
    }

    // MARK: fields

    func spec(_ id: String) -> FieldSpec { Schema.info.fields.first { $0.id == id }! }

    /// Label as on the sheet: `*` for required, "สำคัญ" for `**` fields, "ยังขาด" while a required field is empty.
    func field<C: View>(_ id: String, @ViewBuilder control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(spec: spec(id), filled: spec(id).isFilled(job.values))
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
    var body: some View {
        let important = spec.label.hasPrefix("**")
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(important ? String(spec.label.dropFirst(2)) : spec.label)
                .font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
            if !spec.optional { Text("*").font(.system(size: 17, weight: .semibold)).foregroundStyle(Home.danger) }
            if important {
                Text("สำคัญ").font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 1)
                    .background(Home.sun, in: Capsule())
            }
            Spacer(minLength: 4)
            // narrow columns keep the label and drop the words (the dot stays)
            if spec.optional {
                ViewThatFits { Text("ไม่บังคับ").font(.footnote).foregroundStyle(Home.muted).fixedSize(); Color.clear.frame(width: 0, height: 0) }
            } else if !filled {
                let dot = Circle().fill(Home.pending).frame(width: 7, height: 7)
                ViewThatFits {
                    HStack(spacing: 4) { dot; Text("ยังขาด").font(.footnote.weight(.semibold)).foregroundStyle(Home.pending) }.fixedSize()
                    dot
                }
                .accessibilityLabel("ยังขาด")
            }
        }
        .foregroundStyle(Home.navy)
    }
}

/// White box with an 18-pt title, 12-pt corners and a light navy border.
struct A1Card<Content: View>: View {
    let title: String
    var required = false
    var trailing: String? = nil
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.system(size: 18, weight: .bold))
                if required { Text("*").font(.system(size: 18, weight: .bold)).foregroundStyle(Home.danger) }
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(.footnote).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.8) }
            }
            content
        }
        .padding(.vertical, 16).padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.2)))
    }
}

/// "2/13 … ภาพสถานที่ติดตั้ง" and one bar per step, the open one in blue (card pages A1, A2).
struct PageStepBar: View {
    let job: Job
    let here: MissingGroup.Target
    /// Shown on the right in place of the step's title (B1: "ตู้ไฟฟ้าอาคาร · 3 อาคาร").
    var title: String? = nil

    var body: some View {
        let steps = job.steps
        let i = steps.firstIndex { $0.page == here } ?? 0
        VStack(spacing: 10) {
            HStack {
                Text("\(i + 1)/\(steps.count)").bold()
                Spacer()
                Text(title ?? steps[safe: i]?.title ?? "")
            }
            .font(.system(size: 15))
            HStack(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { n, s in
                    Capsule().fill(n == i ? AnyShapeStyle(LinearGradient(colors: [Home.primary, Home.primaryLight], startPoint: .leading, endPoint: .trailing))
                                   : s.completion.total > 0 && s.completion.isComplete ? AnyShapeStyle(Home.mint) : AnyShapeStyle(Color.gray.opacity(0.25)))
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

extension View {
    /// Outlined input: 50 high, 10-pt corners, navy 45% border (2-pt primary when focused), mint when filled from the job.
    func inputBox(calc: Bool = false, focused: Bool = false, error: Bool = false, minHeight: CGFloat = 50, trailing: CGFloat = 14) -> some View {
        font(.system(size: 17)).foregroundStyle(Home.navy)
            .padding(.leading, 14).padding(.trailing, trailing)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(calc ? Home.mint.opacity(0.3) : Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(error ? Home.danger : focused ? Home.primary : Home.navy.opacity(0.45), lineWidth: error || focused ? 2 : 1))
    }
}
#endif
