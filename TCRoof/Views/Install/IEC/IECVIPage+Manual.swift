import SwiftUI
import TCRoofUI
import TCRoofCore
import ModuleRules

/// Step 2's `ตรวจตามคู่มือแผง` card (rules phase 5, docs/specs/module-install-rules.md §7.4): the selected string's Voc
/// against the datasheet's at the module temperature (ZN-132, a warn: it doesn't fail the string). ZN-110, two strings of
/// an MPPT more than 10 V apart, is one of the string's failures (`IECReport.beforeVIFailures`).
extension IECVIPage {
    @ViewBuilder func manualCard(_ r: IECReport, _ inv: IECReport.Inverter, _ s: IECReport.Slot) -> some View {
        if phase == .before {
            let line = manualLine(r, inv, s)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: line.warn ? "exclamationmark.triangle.fill" : "book.closed")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(line.warn ? Theme.warningText : Theme.primary)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ตรวจตามคู่มือแผง" + (r.catalogModule.map { " | " + $0.id } ?? "")).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                    Text(line.main).font(.sarabunFixed(14, .bold)).foregroundStyle(line.warn ? Theme.warningText : line.ok ? Theme.okText : Theme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = line.note {
                        Text(note).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(line.warn ? Theme.warningSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(line.warn ? Color.clear : Theme.borderSubtle))
            .accessibilityElement(children: .combine)
        }
    }

    /// The card's text: what the string should read and how far off it is, or why there is nothing to compare.
    func manualLine(_ r: IECReport, _ inv: IECReport.Inverter, _ s: IECReport.Slot) -> (main: String, note: String?, ok: Bool, warn: Bool) {
        guard r.catalogModule != nil else {
            let name = [r.module.brand, r.module.powerW > 0 ? IECFormat.number(r.module.powerW) + " W" : ""].filter { !$0.isEmpty }.joined(separator: " ")
            return ("ไม่มีแผง\(name.isEmpty ? "" : " " + name)ในรายการรุ่น", "ตรวจเฉพาะ Voc สตริงที่ต่อขนานใน MPPT เดียวกัน (ต่างกันไม่เกิน 10 V)", false, false)
        }
        guard let basis = r.stringTestBasis else {
            return ("ยังคำนวณ Voc ที่คาดไม่ได้", "ใส่อุณหภูมิอากาศและความเข้มแสงในขั้นที่ 1 (หรืออุณหภูมิแผงที่วัด)", false, false)
        }
        let test = r.stringTest(inv)
        let expected = test.strings[String(slot)]?.expectedV
        let light = r.before.irradianceWm2.map { IECFormat.number($0, digits: 0) + " W/m²" } ?? "ไม่มีค่าแสง"
        let note = basis + " | " + light + " | " + String(s.modules) + " แผง"
        guard let e = expected else { return ("ยังคำนวณ Voc ที่คาดไม่ได้", note, false, false) }
        let head = "คาด " + IECFormat.number(e, digits: 1) + " V"
        guard let m = r.manualVoc(inv, slot: slot) else { return (head + " | ยังไม่มีค่าที่วัด", note, false, false) }
        let diff = IECReport.signedPercent(m.deviation)
        if !test.enoughLight { return (head + " | " + diff + " | แสงต่ำกว่า 200 W/m² ไม่ใช้เกณฑ์", note, false, false) }
        if m.flagged { return (head + " | ต่าง " + diff + " เกิน ±5% | ตรวจจุดต่อสาย", note, false, true) }
        return ("✓ " + head + " | ต่าง " + diff + " (เกณฑ์ ±5%)", note, true, false)
    }
}
