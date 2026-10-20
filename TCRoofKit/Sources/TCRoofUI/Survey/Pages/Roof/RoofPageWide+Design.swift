#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// C1's standard building roof (docs/specs/standard-designs.md §7): start from a design the team saved, check each item
/// on site (`ตรงแบบ`, or it differs once its answers change), and save a checked roof as a design (team only,
/// `design.library`). None is seeded: the first station of each building type saves one.
extension RoofPageWide {
    @ViewBuilder var roofDesignSection: some View {
        let current = RoofDesign.current(values)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("แบบมาตรฐาน").font(.sarabunFixed(15, .bold))
                Spacer(minLength: 6)
                if let s = RoofDesign.summary(values) {
                    Text(s.open > 0 ? "ยังไม่ตรวจ \(s.open)" : "ตรวจครบ").font(.sarabunFixed(12.5, .bold))
                        .foregroundStyle(s.open > 0 ? Theme.pending : Theme.okText)
                }
            }
            if let current, let s = RoofDesign.summary(values) {
                Text("แบบ: " + current.name + " rev \(current.revision)").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                Text(s.counts).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                ForEach(RoofDesign.items(values)) { item in roofDesignRow(item) }
                if RoofDesign.items(values).contains(where: { $0.state == .open }) {
                    designButton("ยืนยันที่เหลือว่าตรงแบบ", icon: "checkmark.circle") { update { RoofDesign.confirmRest(&$0) } }
                }
            }
            designButton(current == nil ? "เริ่มจากแบบมาตรฐาน" : "เปลี่ยนแบบมาตรฐาน", icon: "square.grid.3x3") { roofDesignPick = true }
                .disabled(RoofDesign.ranked(values).isEmpty)
            if RoofDesign.ranked(values).isEmpty {
                Text("ยังไม่มีแบบหลังคาในคลัง | งานแรกของอาคารแบบนี้บันทึกเป็นแบบได้").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            if roofPermissions.can(.designLibrary) && (current == nil || RoofDesign.done(values)) {
                designButton("บันทึกเป็นแบบมาตรฐาน", icon: "square.and.arrow.down.on.square") {
                    roofDesignName = (current.map { $0.name + " | " } ?? "") + job.projectName
                    roofDesignSave = true
                }
            }
            if let saved = roofDesignSaved {
                Text("บันทึกลงคลังแล้ว: " + saved).font(.sarabunFixed(12.5, .bold)).foregroundStyle(Theme.okText)
            }
        }
        .padding(.top, 6)
        .confirmationDialog("เริ่มจากแบบมาตรฐาน", isPresented: $roofDesignPick, titleVisibility: .visible) {
            ForEach(RoofDesign.ranked(values), id: \.design.id) { m in
                let line = m.difference.map { m.matches ? " | ตรงกับขนาดที่วัด" : " | ต่างจากที่วัด " + fmt(($0 * 100).rounded() / 100) + " ม." } ?? ""
                Button(m.design.name + " (" + m.design.size + ")" + line) { update { RoofDesign.apply(&$0, m.design) } }
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("แทนขนาด โครงหลังคา ระยะแป และสิ่งกีดขวางบนแปลนด้วยแบบที่เลือก แล้วตรวจทีละรายการ")
        }
        .alert("บันทึกเป็นแบบมาตรฐาน", isPresented: $roofDesignSave) {
            TextField("ชื่อแบบ", text: $roofDesignName)
            Button("บันทึก") {
                let name = roofDesignName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let d = RoofDesign.from(values, name: name, job: job.docNo.isEmpty ? job.projectName : job.docNo,
                                        by: roofPermissions.email.isEmpty ? nil : roofPermissions.email)
                DesignLibrary.shared.saveRoof(d)
                roofDesignSaved = d.name
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("เก็บขนาด โครงหลังคา ระยะแป ความสูง ขนาดชิ้นส่วน และสิ่งกีดขวางบนแปลนของหลังคานี้เป็นแบบในคลัง")
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
