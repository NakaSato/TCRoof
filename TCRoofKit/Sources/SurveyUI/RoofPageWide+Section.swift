#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// C1's section card: the frame section, bays stepper and length editors.
extension RoofPageWide {
    // MARK: section card

    var sectionCard: some View {
        let f = Roof.frame(values)
        return card {
            sectionStage(big: false).frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            let caption = (Text("รูปตัด A-A · " + f.title).bold().underline() + Text(" · หน่วย ม.").foregroundColor(Home.muted))
                .font(.system(size: 14)).lineLimit(1).minimumScaleFactor(0.6).truncationMode(.tail)
            let zoom = footerButton("ขยาย", icon: "arrow.up.left.and.arrow.down.right", tint: Home.primary) { sectionBig = true }
                .accessibilityLabel("ขยายรูปตัดเต็มจอ")
            if narrow {
                // iPhone: the caption and ขยาย on one line, the bays stepper under them
                HStack(spacing: 8) { caption; Spacer(minLength: 8); zoom }
                if !f.isRafter { baysStepper }
            } else {
                HStack(spacing: 8) {
                    caption
                    Spacer(minLength: 8)
                    zoom
                    if !f.isRafter { baysStepper }
                }
            }
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
                    .accessibilityLabel(String(format: "รูปตัด A-A %@ ช่วง %.2f ม. มุม %@ องศา R %.2f ม.", f.title, sec.span, fmt(f.slope), sec.rise))
                if !big {
                    lengthButton(Roof.Key.overhang, "ชายคา").position(fit.point(sec.overhangLabel))
                    lengthButton(Roof.Key.clearHeight, f.isRafter ? "สูงถึงหัวเสา" : "สูงใต้ขื่อ").position(fit.point(sec.clearLabel))
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
            if !narrow { Text("ช่อง/ข้าง").font(.system(size: 13)).foregroundStyle(Home.muted).lineLimit(1).fixedSize() }
            stepButton("minus", enabled: n > Roof.baysRange.lowerBound) { update { Roof.setBays(&$0, n - 1) } }
            Text("\(n) × " + String(format: "%.2f ม.", w)).font(.system(size: 16, weight: .bold)).monospacedDigit()
                .lineLimit(1).fixedSize()
            stepButton("plus", enabled: n < Roof.baysRange.upperBound) { update { Roof.setBays(&$0, n + 1) } }
            Button { update { Roof.setBays(&$0, nil) } } label: {
                Text("อัตโนมัติ").font(.system(size: 13, weight: .bold)).lineLimit(1).fixedSize().foregroundStyle(auto ? Home.disabledText : Home.primary)
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(auto ? Home.disabledFill : Home.primary.opacity(0.5)))
            }
            .buttonStyle(.plain).disabled(auto)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ช่องโครงถักต่อข้าง \(n) ช่อง")
    }

    func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(enabled ? Home.primary : Home.disabledText)
                .frame(width: 44, height: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(enabled ? Home.navy.opacity(0.3) : Home.disabledFill))
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "เพิ่ม" : "ลด")
    }

    /// The section's overhang and clear height: tap to step them by 0.05 m.
    func lengthButton(_ key: String, _ name: String) -> some View {
        Button { lengthKey = key } label: { Color.clear.frame(width: 88, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel(name + " แตะเพื่อแก้")
            .popover(isPresented: Binding(get: { lengthKey == key }, set: { if !$0 { lengthKey = nil } })) {
                lengthEditor(key, name).presentationCompactAdaptation(.popover)
            }
    }

    func lengthEditor(_ key: String, _ name: String) -> some View {
        let overhang = key == Roof.Key.overhang
        let m = overhang ? Roof.overhang(values) : Roof.clearHeight(values), range = overhang ? 0.0...3.0 : 1.0...30.0
        return VStack(alignment: .leading, spacing: 10) {
            Text(name + " (ม.)").font(.system(size: 15, weight: .bold))
            HStack(spacing: 10) {
                stepButton("minus", enabled: m > range.lowerBound) { update { Roof.setLength(&$0, key, max(range.lowerBound, m - 0.05)) } }
                Text(String(format: "%.2f", m)).font(.system(size: 20, weight: .bold)).monospacedDigit().frame(minWidth: 70)
                stepButton("plus", enabled: m < range.upperBound) { update { Roof.setLength(&$0, key, min(range.upperBound, m + 0.05)) } }
            }
            Button { update { Roof.setLength(&$0, key, nil) } } label: {
                Text("ใช้ค่าตามแบบ (" + (overhang ? "0.70" : "4.00") + ")").font(.system(size: 13, weight: .semibold)).foregroundStyle(Home.primary).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Home.navy)
        .padding(14)
    }
}
#endif
