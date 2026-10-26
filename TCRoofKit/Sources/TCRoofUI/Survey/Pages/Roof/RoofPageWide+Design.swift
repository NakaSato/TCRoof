#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// C1's standard building roof (docs/specs/standard-designs.md §7): a design the team saved, picked from the
/// `หลังคามาตรฐาน` dropdown, is checked here item by item on site (`ตรงแบบ`, or it differs once its answers change).
extension RoofPageWide {
    /// The checklist of the design C1 was filled from. Picking and saving a design is the `หลังคามาตรฐาน` dropdown's
    /// (RoofPageWide+Sheets), so this card only shows once a design is in use or one was just saved.
    @ViewBuilder var roofDesignSection: some View {
        let current = RoofDesign.current(values)
        if current != nil || roofDesignSaved != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let current, let s = RoofDesign.summary(values) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("แบบมาตรฐาน").font(.sarabunFixed(15, .bold))
                        Spacer(minLength: 6)
                        Text(s.open > 0 ? "ยังไม่ตรวจ \(s.open)" : "ตรวจครบ").font(.sarabunFixed(12.5, .bold))
                            .foregroundStyle(s.open > 0 ? Theme.pending : Theme.okText)
                    }
                    Text("แบบ: " + current.name + " rev \(current.revision)").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                    Text(s.counts).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    ForEach(RoofDesign.items(values)) { item in roofDesignRow(item) }
                    if RoofDesign.items(values).contains(where: { $0.state == .open }) {
                        designButton("ยืนยันที่เหลือว่าตรงแบบ", icon: "checkmark.circle") { update { RoofDesign.confirmRest(&$0) } }
                    }
                }
                if let saved = roofDesignSaved {
                    Text("บันทึกลงคลังแล้ว: " + saved).font(.sarabunFixed(12.5, .bold)).foregroundStyle(Theme.okText)
                }
            }
            .padding(.top, 6)
        }
    }

    func roofDesignRow(_ item: RoofDesign.Item) -> some View {
        let chip: (String, Color, Color) = {
            switch item.state {
            case .open: return ("ยังไม่ตรวจ", Theme.pending, Theme.pendingSoft)
            case .matches: return ("ตรงแบบ", Theme.okText, Theme.okSoft)
            case .differs: return ("ต่างจากแบบ", Theme.pending, Theme.warning.opacity(0.15))
            case .missing: return ("ไม่มีจริง", Theme.dangerText, Theme.dangerSoft)
            case .added: return ("เพิ่มหน้างาน", Theme.teamPurple, Theme.teamPurple.opacity(0.12))
            }
        }()
        return HStack(spacing: 8) {
            Text(item.title).font(.sarabunFixed(14)).lineLimit(1)
            Spacer(minLength: 6)
            Text(chip.0).font(.sarabunFixed(12, .bold)).foregroundStyle(chip.1)
                .padding(.horizontal, 8).padding(.vertical, 2).background(chip.2, in: Capsule())
            if item.state == .open || item.state == .matches {
                Button { update { RoofDesign.toggle(&$0, item.id) } } label: {
                    Image(systemName: item.state == .matches ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20)).foregroundStyle(item.state == .matches ? Theme.success : Theme.inkMuted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.state == .matches ? "ยกเลิกตรงแบบ \(item.title)" : "ตรงแบบ \(item.title)")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .accessibilityElement(children: .contain)
    }

    func designButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }
}
#endif
