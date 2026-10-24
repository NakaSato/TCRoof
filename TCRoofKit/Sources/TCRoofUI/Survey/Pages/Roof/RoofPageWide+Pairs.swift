#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// Landscape pairs, the ridge walkway's width and `02`'s module row (docs/ui/survey-c1-iphone-pv-fix01).
extension RoofPageWide {
    /// `การเรียงแผงแนวนอน`: `วางชิดกัน | วางคู่ 2 แผ่น` with its note and, with pairs, the gap between them.
    @ViewBuilder var landscapeArrangement: some View {
        let c = mountChoice
        if c.landscape {
            VStack(alignment: .leading, spacing: 6) {
                A3Label(text: "การเรียงแผงแนวนอน")
                RoofSegments(options: ["วางชิดกัน", "วางคู่ 2 แผ่น"], selected: c.landscapePairs ? 1 : 0, minSegment: 100, height: 44) { i in
                    changeChoice { $0.landscapePairs = i == 1 }
                }
                Text(c.landscapePairs ? "วางแผงเป็นคู่ตามแนวแถว แล้วเว้นระยะระหว่างคู่" : "ทุกแถวชิดกัน")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                if c.landscapePairs { pairGapStepper }
            }
        }
    }

    /// `ระยะเว้นระหว่างคู่`: 0.20–1.00 m in 0.10 m steps.
    var pairGapStepper: some View {
        choiceStepper("ระยะเว้นระหว่างคู่", value: mountChoice.pairGapOrDefault, range: 0.20...1.00, id: "pairGap") { x in
            changeChoice { $0.pairGap = x }
        }
    }

    /// The ridge walkway's clear width: from the team's detail band (0.90 m, so the detail always fits) to 1.50 m.
    var ridgeWidthStepper: some View {
        choiceStepper("ทางเดินตามสันหลังคา กว้าง", value: mountChoice.ridgeWalkwayWidth ?? RoofWalkway.band,
                      range: RoofWalkway.band...1.50, id: "ridgeWidth") { x in
            changeChoice { $0.ridgeWalkwayWidth = x }
        }
    }

    /// A 52 pt row `title − n.nn ม. +` stepping by 0.10 m; a button at its limit is dimmed and does nothing. Each step is
    /// one undo step (`changeChoice`).
    func choiceStepper(_ title: String, value v: Double, range: ClosedRange<Double>, id: String,
                       set: @escaping (Double) -> Void) -> some View {
        let lo = range.lowerBound, hi = range.upperBound
        func step(_ d: Double) { set(min(hi, max(lo, ((v + d) * 100).rounded() / 100))) }
        return HStack(spacing: 6) {
            Text(title).font(.sarabunFixed(13)).lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            stepButton("minus", enabled: v - 0.1 >= lo - 1e-9) { step(-0.1) }
                .accessibilityIdentifier(id + "Minus")
            Text(String(format: "%.2f ม.", v)).font(.sarabunFixed(14, .bold)).monospacedDigit().frame(minWidth: 62)
                .accessibilityIdentifier(id + "Value")
            stepButton("plus", enabled: v + 0.1 <= hi + 1e-9) { step(0.1) }
                .accessibilityIdentifier(id + "Plus")
        }
        .frame(minHeight: 52)
    }

    /// `รุ่นแผง`: the catalog's name, then `<length> × <width> มม. · Voc <x> V · จากมาตรฐานโครงการ`; with no catalog match
    /// the standard's `W | L × W ม.`.
    var moduleRow: some View {
        let s = mountChoice.standardOrDefault
        let cat = RoofMountYield.catalogModule(wp: s.moduleWp, length: s.moduleLength, width: s.moduleWidth)
        return VStack(alignment: .leading, spacing: 2) {
            A3Label(text: "รุ่นแผง")
            if let cat {
                Text(cat.model).font(.sarabunFixed(14, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(Self.mm(cat.l) + " × " + Self.mm(cat.wd) + " มม. · Voc " + String(format: "%.1f", cat.voc) + " V · จากมาตรฐานโครงการ")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Text(String(format: "%.0f W | %.2f × %.2f ม.", s.moduleWp, s.moduleLength, s.moduleWidth)).font(.sarabunFixed(14, .bold))
                Text("จากมาตรฐานโครงการ").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("moduleRow")
    }

    /// 2278 → `2,278`.
    static func mm(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
#endif
