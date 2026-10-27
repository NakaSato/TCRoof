#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// A4's right column in cards (docs/ui/survey-a4-ipad-v2 §1.1–1.3): `ประวัติน้ำท่วม` with the water level stepper and
/// the `ระดับติดตั้งต่ำสุด` equation, `ความถี่ | สาเหตุ` and `จุดที่ได้รับผลกระทบ` with short display labels.
extension FloodPageWide {
    /// White card, 14-pt corners: the title and its aside on one line (17 bold / 13 muted).
    func floodCard<Content: View>(_ title: String, aside: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.sarabunFixed(17, .bold))
                Spacer(minLength: 8)
                if let aside { Text(aside).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8) }
            }
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle))
    }

    /// The sections the minimum level checks ("B2 | B4 | B5"), nil when the job has none of them.
    var checkedTags: String? {
        let t = FloodCheck.checkedTags(check)
        return t.isEmpty ? nil : t.joined(separator: " | ")
    }
    var refName: String { values.choice("floodRef") ?? Schema.floodRefs[0] }

    // MARK: ประวัติน้ำท่วม

    var historyCard: some View {
        floodCard("ประวัติน้ำท่วม", aside: checkedTags.map { "มีผลกับระดับติดตั้ง " + $0 }) {
            VStack(alignment: .leading, spacing: 6) {
                label("พื้นที่เคยมีน้ำท่วมหรือไม่", required: true)
                choiceRow(Schema.flood.fields[0].choiceOptions, id: "floodHistory", height: 50)
            }
            if state == .flooded {
                levelRow
                sourceRow
                minLevelRow
            }
        }
    }

    /// Water level first (1.3 : 1 : 1), then the year and the days; on an iPhone the stepper takes the whole width.
    @ViewBuilder var levelRow: some View {
        let year = numberBox("ปีล่าสุด (พ.ศ.)", id: "floodYear", unit: "", required: true, height: 50)
        let days = numberBox("ท่วมขัง", id: "floodDays", unit: "วัน", height: 50)
        if narrow {
            levelStepper
            RatioRow(weights: [1, 1]) { year; days }
        } else {
            RatioRow(weights: [1.3, 1, 1], spacing: 10) { levelStepper; year; days }
        }
    }

    var sourceRow: some View {
        let pair = narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return pair {
            VStack(alignment: .leading, spacing: 6) {
                label("วัดความสูงจาก", required: true)
                choiceRow(Schema.floodRefs, id: "floodRef", height: 44, fontSize: 15)
            }
            VStack(alignment: .leading, spacing: 6) {
                label("ที่มาข้อมูล", required: true)
                choiceRow(Schema.floodInfoSources, id: "floodInfoSource", height: 44, fontSize: 15)
            }
        }
    }

    // MARK: water level

    var level: Double { values.number("floodDepth") ?? 0 }
    func setLevel(_ cm: Double) { job.values["floodDepth"] = .text(FloodCheck.cmText(cm)) }
    /// ± one step, snapped to the step and kept in the stepper's range.
    func stepLevel(_ up: Bool) {
        let r = FloodCheck.levelRange, step = FloodCheck.levelStep
        let next = ((level + (up ? step : -step)) / step).rounded(up ? .down : .up) * step
        setLevel(min(max(next, r.lowerBound), r.upperBound))
    }
    var sliderLevel: Binding<Double> {
        Binding(get: { min(level, FloodCheck.levelRange.upperBound) },
                set: { setLevel(max($0, FloodCheck.levelRange.lowerBound)) })
    }

    /// 44-pt − / + on a soft fill.
    func stepButton(_ symbol: String, _ name: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.primary)
                .frame(width: 44, height: 44)
                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).accessibilityLabel(name).accessibilityIdentifier(id)
    }

    var levelStepper: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("ระดับน้ำสูงสุด", required: true)
            HStack(spacing: 6) {
                stepButton("minus", "ลด 5 ซม.", id: "a4.level.minus") { stepLevel(false) }
                levelField
                stepButton("plus", "เพิ่ม 5 ซม.", id: "a4.level.plus") { stepLevel(true) }
            }
            .padding(3).frame(minHeight: 50)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary, lineWidth: 2))
            Slider(value: sliderLevel, in: 0...FloodCheck.levelRange.upperBound, step: FloodCheck.levelStep)
                .tint(Theme.primary).frame(height: 28)
                .accessibilityLabel("ปรับระดับน้ำสูงสุด").accessibilityValue("\(FloodCheck.cmText(level)) ซม.")
            levelTicks
        }
    }

    var levelField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            TextField("0", text: text("floodDepth"))
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.navy)
                .frame(width: 64)
                .accessibilityLabel("ระดับน้ำสูงสุด ซม.").accessibilityIdentifier("a4.level")
                .accessibilityAdjustableAction { d in
                    switch d {
                    case .increment: stepLevel(true)
                    case .decrement: stepLevel(false)
                    @unknown default: break
                    }
                }
            Text("ซม.").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    /// 0 / 50 / 100 / 150 / 200 ซม. under the slider.
    var levelTicks: some View {
        let top = Int(FloodCheck.levelRange.upperBound), marks = stride(from: 0, through: top, by: top / 4).map { $0 }
        return HStack(spacing: 0) {
            ForEach(Array(marks.enumerated()), id: \.offset) { i, m in
                if i > 0 { Spacer(minLength: 0) }
                Text(i == marks.count - 1 ? "\(m) ซม." : "\(m)")
            }
        }
        .font(.sarabunFixed(11)).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.top, -4)
        .accessibilityHidden(true)
    }

    // MARK: ระดับติดตั้งต่ำสุด

    var freeboard: Double { FloodCheck.freeboardCm(values) }
    func stepFreeboard(_ up: Bool) {
        let r = FloodCheck.freeboardRange, step = FloodCheck.freeboardStep
        let next = ((freeboard + (up ? step : -step)) / step).rounded(up ? .down : .up) * step
        job.values["floodFreeboard"] = .text(FloodCheck.cmText(min(max(next, r.lowerBound), r.upperBound)))
    }

    /// `[น้ำสูงสุด] + [เผื่อเหนือน้ำ − n +] = [ติดตั้งต่ำสุด]`; on an iPhone the result goes on a row of its own.
    var minLevelRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("ระดับติดตั้งต่ำสุด", aside: "วัดจาก" + refName + (checkedTags.map { " | ใช้ตรวจ " + $0 } ?? ""))
            if narrow {
                EquationRow(weights: [1, 0, 1.5]) { levelTile; operatorSign("+"); freeboardTile }
                EquationRow(weights: [0, 1]) { operatorSign("="); resultTile }
            } else {
                EquationRow(weights: [0.8, 0, 1.25, 0, 1]) { levelTile; operatorSign("+"); freeboardTile; operatorSign("="); resultTile }
            }
        }
    }

    func operatorSign(_ s: String) -> some View {
        Text(s).font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.inkMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityHidden(true)
    }

    /// "80 ซม.": the number big, the unit small and muted.
    func tileValue(_ n: String, color: Color) -> some View {
        (Text(n).font(.sarabunFixed(22, .bold)).foregroundColor(color)
            + Text(" ซม.").font(.sarabunFixed(14)).foregroundColor(Theme.inkMuted))
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    func equationTile<Content: View>(_ title: String, fill: Color, border: Color, horizontal: CGFloat = 12,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                .padding(.leading, 12 - horizontal)
            content()
        }
        .padding(.vertical, 6).padding(.horizontal, horizontal)
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(border))
    }

    var levelTile: some View {
        equationTile("น้ำสูงสุด", fill: Theme.background, border: Theme.borderSubtle) {
            tileValue(FloodCheck.cmText(check.level), color: Theme.navy)
        }
        .accessibilityElement(children: .combine)
    }

    var freeboardTile: some View {
        equationTile("เผื่อเหนือน้ำ", fill: Theme.surface, border: Theme.navy.opacity(0.45), horizontal: 4) {
            HStack(spacing: 4) {
                stepButton("minus", "ลดระยะเผื่อ", id: "a4.freeboard.minus") { stepFreeboard(false) }
                tileValue(FloodCheck.cmText(freeboard), color: Theme.navy).frame(maxWidth: .infinity)
                    .accessibilityLabel("เผื่อเหนือน้ำ \(FloodCheck.cmText(freeboard)) ซม.")
                    .accessibilityIdentifier("a4.freeboard")
                stepButton("plus", "เพิ่มระยะเผื่อ", id: "a4.freeboard.plus") { stepFreeboard(true) }
            }
        }
    }

    var resultTile: some View {
        let rounded = FloodCheck.roundedFrom(values).map { " | ปัดขึ้นจาก " + FloodCheck.cmText($0) } ?? ""
        let metres = "+" + String(format: "%.2f", Double(check.minCm) / 100) + " ม."
        return equationTile("ติดตั้งต่ำสุด", fill: Theme.mint.opacity(0.35), border: Theme.teal) {
            tileValue("\(check.minCm)", color: Theme.teal)
            Text(metres + rounded).font(.sarabunFixed(12.5, .semibold)).foregroundStyle(Theme.teal).lineLimit(1).truncationMode(.tail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ติดตั้งต่ำสุด \(check.minCm) ซม. " + metres + rounded)
        .accessibilityIdentifier("a4.result")
    }

    // MARK: ความถี่ | สาเหตุ, จุดที่ได้รับผลกระทบ

    var frequencyCauseCard: some View {
        floodCard("ความถี่ | สาเหตุ") {
            choiceRow(Schema.flood.fields.first { $0.id == "floodFreq" }?.choiceOptions ?? [], id: "floodFreq", height: 44, fontSize: 15)
            choiceRow(Schema.floodSources, id: "floodSource", perRow: narrow ? 3 : Schema.floodSources.count, height: 44, fontSize: 14,
                      short: Schema.floodSourceShort)
            if values.choice("floodSource") == "อื่นๆ" {
                TextField("ระบุสาเหตุ", text: Binding(get: { values.other("floodSource") },
                                                     set: { job.values["floodSource"] = .choice("อื่นๆ", other: $0) })).inputBox()
            }
        }
    }

    var hitsCard: some View {
        floodCard("จุดที่ได้รับผลกระทบ", aside: "\(values.multi("floodHit").count) จุด | แสดงบนภาพ A2") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: narrow ? 2 : Schema.floodHits.count), spacing: 8) {
                ForEach(Schema.floodHits, id: \.self) { h in hitChip(h) }
            }
        }
    }

    /// Checkbox chip, 48 high, soft blue when on; writes the full option.
    func hitChip(_ h: String) -> some View {
        let on = values.multi("floodHit").contains(h)
        let title = Schema.floodHitShort[h] ?? h
        return Button {
            var a = values.multi("floodHit")
            if on { a.removeAll { $0 == h } } else { a.append(h) }
            job.values["floodHit"] = .multi(a)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(on ? Theme.onPrimary : .clear)
                    .frame(width: 22, height: 22)
                    .background(on ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(on ? Theme.primary : Theme.borderControl, lineWidth: 1.5))
                Text(title).font(.sarabunFixed(14, .semibold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(on ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy.opacity(on ? 0.2 : 0.45)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(on ? .isSelected : [])
    }

    /// `ไม่เคย`: no details to fill; the install level is the freeboard over the reference level.
    var neverNote: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ไม่เคยท่วม | ข้ามรายละเอียดได้").font(.sarabunFixed(15, .bold))
            Text("ระดับติดตั้งใช้ระยะเผื่อจากพื้น \(FloodCheck.cmText(freeboard)) ซม. → +" + String(format: "%.2f", Double(check.minCm) / 100) + " ม.")
                .font(.sarabunFixed(15))
        }
        .foregroundStyle(Theme.navy)
        .padding(.vertical, 12).padding(.horizontal, 14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.mint.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Tiles in fixed proportions with fixed-width signs between them (weight 0), all stretched to the tallest.
struct EquationRow: Layout {
    var weights: [CGFloat]
    var fixed: CGFloat = 22
    var spacing: CGFloat = 4

    func widths(_ total: CGFloat) -> [CGFloat] {
        let signs = CGFloat(weights.filter { $0 == 0 }.count) * fixed
        let free = max(0, total - signs - spacing * CGFloat(max(weights.count - 1, 0))), sum = max(weights.reduce(0, +), 1)
        return weights.map { $0 == 0 ? fixed : free * $0 / sum }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600
        let h = zip(subviews, widths(w)).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (v, w) in zip(subviews, widths(bounds.width)) {
            v.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}

#if DEBUG
extension FloodPageWide {
    /// `-surveyA4 flooded|rounded|never|unknown|gistda` (with `-surveyPage flood`) writes the states of
    /// docs/ui/survey-a4-ipad-v2/states into the opened job: `เคย` 80 cm with the default freeboard (01), 75 cm with 30 (02,
    /// `ปัดขึ้นจาก 105`), `ไม่เคย` (03), `ไม่ทราบ` with no GISTDA data (04) or with `FloodGistda.estimate` (05).
    func applyA4Debug() async {
        guard let s = UserDefaults.standard.string(forKey: "surveyA4") else { return }
        try? await Task.sleep(nanoseconds: 500_000_000)
        var v = job.values
        let history = ["never": "ไม่เคย", "unknown": "ไม่ทราบ", "gistda": "ไม่ทราบ"][s] ?? "เคย"
        v["floodHistory"] = .choice(history, other: "")
        v["floodDepth"] = .text(s == "rounded" ? "75" : "80")
        v["floodFreeboard"] = s == "rounded" ? .text("30") : nil
        v["floodYear"] = .text("2554"); v["floodDays"] = .text("7")
        v["floodRef"] = .choice(Schema.floodRefs[0], other: ""); v["floodInfoSource"] = .choice(Schema.floodInfoSources[0], other: "")
        v["floodFreq"] = .choice("นานกว่า 5 ปี", other: ""); v["floodSource"] = .choice(Schema.floodSources[1], other: "")
        v["floodHit"] = .multi([Schema.floodHits[0], Schema.floodHits[2], Schema.floodHits[4]])
        v["invFloorCm"] = .text("30")
        v["floodNote"] = .text("ปี 2554 น้ำเข้าห้อง MDB สูงประมาณครึ่งตู้ | ถนนทางเข้าถูกตัดขาด 5 วัน")
        v.setGistda(s == "gistda" ? .estimate() : nil)
        job.values = v
    }
}
#endif
#endif
