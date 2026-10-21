#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// C1's section card: the frame section, bays stepper and length editors.
extension RoofPageWide {
    // MARK: section card

    @ViewBuilder var sectionCard: some View {
        if mode == .pv { rowSectionCard } else { frameSectionCard }
    }

    /// แผงบนหลังคา: the selected row along the slope (§5.4).
    var rowSectionCard: some View {
        card {
            rowSectionStage.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            (Text("รูปตัดแถวที่เลือก").bold().underline() + Text(" | แตะแผงบนแปลนเพื่อเปลี่ยนแถว | หน่วย ม.").foregroundColor(Theme.inkMuted))
                .font(.sarabunFixed(14)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    var frameSectionCard: some View {
        let f = Roof.frame(values)
        return card {
            sectionStage(big: false).frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            let caption = (Text("รูปตัด A-A | " + f.title).bold().underline() + Text(" | หน่วย ม.").foregroundColor(Theme.inkMuted))
                .font(.sarabunFixed(14)).lineLimit(1).minimumScaleFactor(0.6).truncationMode(.tail)
            let zoom = footerButton("ขยาย", icon: "arrow.up.left.and.arrow.down.right", tint: Theme.primary) { sectionBig = true }
                .accessibilityLabel("ขยายรูปตัดเต็มจอ")
            let parts = footerButton("ชิ้นส่วน", icon: "list.bullet.rectangle", tint: Theme.primary) { trussOpen = true }
                .accessibilityLabel(f.isTruss ? "รายละเอียด A B และตารางชิ้นส่วน" : "ตารางชิ้นส่วน")
            pitchNote
            if narrow {
                // iPhone: the caption, ชิ้นส่วน and ขยาย on one line, the bays stepper under them
                HStack(spacing: 8) { caption; Spacer(minLength: 8); parts; zoom }
                if !f.isRafter { baysStepper }
            } else {
                HStack(spacing: 8) {
                    caption
                    Spacer(minLength: 8)
                    parts
                    zoom
                    if !f.isRafter { baysStepper }
                }
            }
        }
    }

    /// The pitch from the measured heights (auto-drawing §4.4), or its check; nothing for the frame type's slope.
    @ViewBuilder var pitchNote: some View {
        let p = Roof.pitch(values)
        if let w = p.warning {
            Label(w, systemImage: "exclamationmark.triangle.fill").font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.warningText)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        } else if p.measured {
            Text("มุมหลังคา " + Roof.slopeText(values) + " จากความสูงสัน " + String(format: "%.2f", Roof.ridgeHeight(values)) + " ม.")
                .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Section A-A with its overhang / clear-height buttons and the numbered callouts (a tap picks that member row).
    func sectionStage(big: Bool) -> some View {
        let f = Roof.frame(values)
        return GeometryReader { geo in
            let sec = RoofSection(values, highlight: member)
            let fit = SketchFit(RoofSection.width, RoofSection.height, in: geo.size)
            ZStack(alignment: .topLeading) {
                SketchCanvas(ops: sec.sketch.ops, fit: fit)
                    .accessibilityLabel(String(format: "รูปตัด A-A %@ ช่วง %.2f ม. มุม %@ องศา R %.2f ม.", f.title, sec.span, fmt((Roof.slope(values) * 10).rounded() / 10), sec.rise))
                if !big {
                    lengthButton(Roof.Key.overhang, "ชายคา").position(fit.point(sec.overhangLabel))
                    lengthButton(Roof.Key.clearHeight, f.isRafter ? "สูงถึงหัวเสา" : "สูงใต้ขื่อ").position(fit.point(sec.clearLabel))
                    lengthButton(Roof.Key.ridgeHeight, "สูงถึงสันหลังคา").position(fit.point(sec.riseLabel))
                }
                ForEach(sec.callouts.keys.sorted(), id: \.self) { n in
                    Button { member = member == n ? nil : n } label: { Color.clear.frame(width: 44, height: 44).contentShape(Circle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("ตำแหน่งชิ้นส่วน \(n) " + f.members[n - 1].name)
                        .accessibilityAddTraits(member == n ? .isSelected : [])
                        .position(fit.point(sec.callouts[n]!))
                }
            }
        }
    }

    var baysStepper: some View {
        let n = Roof.bays(values), auto = Roof.baysAreAuto(values), w = Roof.span(values) / 2 / Double(n)
        return HStack(spacing: 8) {
            // the whole row is labelled for VoiceOver; iPhone has no room for the word
            if !narrow { Text("ช่อง/ข้าง").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).fixedSize() }
            stepButton("minus", enabled: n > Roof.baysRange.lowerBound) { update { Roof.setBays(&$0, n - 1) } }
            Text("\(n) × " + String(format: "%.2f ม.", w)).font(.sarabunFixed(16, .bold)).monospacedDigit()
                .lineLimit(1).fixedSize()
            stepButton("plus", enabled: n < Roof.baysRange.upperBound) { update { Roof.setBays(&$0, n + 1) } }
            Button { update { Roof.setBays(&$0, nil) } } label: {
                Text("อัตโนมัติ").font(.sarabunFixed(13, .bold)).lineLimit(1).fixedSize().foregroundStyle(auto ? Theme.disabledText : Theme.primary)
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(auto ? Theme.disabledFill : Theme.primary.opacity(0.5)))
            }
            .buttonStyle(.plain).disabled(auto)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ช่องโครงถักต่อข้าง \(n) ช่อง")
    }

    func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(enabled ? Theme.primary : Theme.disabledText)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(enabled ? Theme.navy.opacity(0.3) : Theme.disabledFill))
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "เพิ่ม" : "ลด")
    }

    /// The section's overhang, clear height and ridge height: tap to step them by 0.05 m.
    func lengthButton(_ key: String, _ name: String) -> some View {
        Button { lengthKey = key } label: { Color.clear.frame(width: 88, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel(name + " แตะเพื่อแก้")
            .popover(isPresented: Binding(get: { lengthKey == key }, set: { if !$0 { lengthKey = nil } })) {
                lengthEditor(key, name).presentationCompactAdaptation(.popover)
            }
    }

    func lengthEditor(_ key: String, _ name: String) -> some View {
        let overhang = key == Roof.Key.overhang, ridge = key == Roof.Key.ridgeHeight
        let m = overhang ? Roof.overhang(values) : ridge ? Roof.ridgeHeight(values) : Roof.clearHeight(values)
        let range = overhang ? 0.0...3.0 : ridge ? 1.0...40.0 : 1.0...30.0
        let reset = overhang ? "ใช้ค่าตามแบบ (0.70)" : ridge ? "ใช้มุมตามแบบ (" + fmt(Roof.frame(values).slope) + "°)" : "ใช้ค่าตามแบบ (4.00)"
        return VStack(alignment: .leading, spacing: 10) {
            Text(name + " (ม.)").font(.sarabunFixed(15, .bold))
            HStack(spacing: 10) {
                stepButton("minus", enabled: m > range.lowerBound) { update { Roof.setLength(&$0, key, max(range.lowerBound, m - 0.05)) } }
                Text(String(format: "%.2f", m)).font(.sarabunFixed(20, .bold)).monospacedDigit().frame(minWidth: 70)
                stepButton("plus", enabled: m < range.upperBound) { update { Roof.setLength(&$0, key, min(range.upperBound, m + 0.05)) } }
            }
            Button { update { Roof.setLength(&$0, key, nil) } } label: {
                Text(reset).font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.primary).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            if ridge {
                Text("พื้นถึงหลังคาที่สัน | มุมคิดจากความสูงนี้").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
        }
        .foregroundStyle(Theme.navy)
        .padding(14)
    }
}
#endif
