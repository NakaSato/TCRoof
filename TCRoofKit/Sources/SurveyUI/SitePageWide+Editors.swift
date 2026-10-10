#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport
import TCRoofUI

/// A2's symbol and shape editors on the picture.
extension SitePageWide {
    // MARK: editors

    @ViewBuilder func editor(_ e: Editing, rect r: CGRect) -> some View {
        switch e {
        case .mark(let id): if let m = marks.first(where: { $0.id == id }) { markEditor(m) }
        case .shape(let id): if let s = shapes.first(where: { $0.id == id }) { shapeEditor(s, rect: r) }
        }
    }

    func markBinding(_ id: UUID, _ key: WritableKeyPath<MapMark, String>) -> Binding<String> {
        Binding(get: { marks.first { $0.id == id }?[keyPath: key] ?? "" },
                set: { v in var a = marks; if let i = a.firstIndex(where: { $0.id == id }) { a[i][keyPath: key] = v; setMarks(a) } })
    }

    @ViewBuilder func markEditor(_ m: MapMark) -> some View {
        if m.kind == .zeroExport { zeroExportEditor(m) } else { ratingEditor(m) }
    }

    func ratingEditor(_ m: MapMark) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(m.kind.paletteTitle).font(.headline)
                Spacer()
                if m.kind == .trafo || m.kind == .mdb { a3LinkChip(m) }
            }
            HStack(alignment: .bottom, spacing: 10) {
                editorField("ชื่อบนภาพ", text: markBinding(m.id, \.label), placeholder: SiteMarks.defaultLabel(m, in: marks))
                if let unit = m.kind.unit {
                    editorField("ขนาด", text: markBinding(m.id, \.value), placeholder: "0", unit: unit, numeric: true).frame(width: 130)
                }
            }
            editorButtons { change { a, _ in a.removeAll { $0.id == m.id } }; editing = nil }
        }
        .padding(16).frame(width: 340)
        .foregroundStyle(Theme.navy)
    }

    /// `↔ A3 TX 1` once the symbol fills A3; tapping it takes A3's values again (the old `ดึงจาก A3`).
    func a3LinkChip(_ m: MapMark) -> some View {
        let title = SiteSync.linkTitle(job, mark: m) ?? "A3"
        return Button { SiteSync.keepA3(&job, mark: m.id) } label: {
            linkChip(title).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เชื่อมกับ \(title)").accessibilityHint("แตะเพื่อดึงค่าจาก A3")
    }

    /// Blue pill `↔ A3 TX 1` / `↔ B4`.
    func linkChip(_ title: String) -> some View {
        Text("↔ " + title).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.primary).lineLimit(1)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Theme.primarySoft, in: Capsule())
    }

    static let zeroExportChoices: [(value: String, title: String, detail: String)] = [
        ("MV", "ZERO EXPORT MV", "กันย้อนฝั่งแรงดันกลาง (22/33 kV)"),
        ("LV", "ZERO EXPORT LV", "กันย้อนฝั่งแรงดันต่ำ (400/230 V)"),
    ]

    /// กันย้อน: MV or LV, written on the symbol and sent to B4's level.
    func zeroExportEditor(_ m: MapMark) -> some View {
        let value = markBinding(m.id, \.value)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("กันย้อน · ข้อความบนภาพ").font(.headline)
                Spacer()
                if let title = SiteSync.linkTitle(job, mark: m) { linkChip(title) }
            }
            ForEach(Self.zeroExportChoices, id: \.value) { c in
                let on = value.wrappedValue.uppercased() == c.value
                Button { value.wrappedValue = c.value } label: {
                    HStack(spacing: 12) {
                        Image(systemName: on ? "record.circle.fill" : "circle")
                            .font(.system(size: 20)).foregroundStyle(on ? Theme.danger : Theme.borderControl)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.title).font(.system(size: 16, weight: .bold))
                            Text(c.detail).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 52)
                    .background(on ? Theme.danger.opacity(0.06) : Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.danger : Theme.borderSubtle, lineWidth: on ? 2 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Text("ส่งไป B4 กันย้อน: MV = \(ZeroExport.hv) · LV = \(ZeroExport.lv)")
                .font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
            editorButtons { change { a, _ in a.removeAll { $0.id == m.id } }; editing = nil }
        }
        .padding(16).frame(width: 340)
        .foregroundStyle(Theme.navy)
    }

    func shapeEditor(_ s: SiteShape, rect r: CGRect) -> some View {
        let names: [ShapeKind: String] = [.panelArea: "พื้นที่ติดตั้งแผง", .cableRoute: "แนวสายไฟ", .measure: "วัดระยะ", .craneEntry: "ทางเข้าเครน", .shade: "ร่มเงา"]
        let aspect = r.height > 0 ? Double(r.width / r.height) : 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(names[s.kind] ?? "").font(.headline)
                Spacer()
                if s.kind == .measure, let m = metersAcross, let l = SiteShapes.length(s, aspect: aspect, metersAcross: m) {
                    Text(SiteShapes.meters(l)).font(.headline).monospacedDigit().foregroundStyle(Theme.primary)
                }
            }
            if s.kind == .shade || s.kind == .craneEntry {
                editorField("ข้อความบนภาพ", text: Binding(
                    get: { shapes.first { $0.id == s.id }?.label ?? "" },
                    set: { v in var a = shapes; if let i = a.firstIndex(where: { $0.id == s.id }) { a[i].label = v; setShapes(a) } }),
                            placeholder: s.kind == .shade ? "เช่น ร่มเงาต้นไม้" : "ทางเข้าเครน")
            }
            if s.kind == .measure {
                editorField(metersAcross == nil ? "ระยะจริง (ตั้งมาตราส่วนของภาพ)" : "ระยะจริง (แก้มาตราส่วน)", text: $realLength, placeholder: "0", unit: "ม.", numeric: true)
            }
            editorButtons {
                change { _, a in a.removeAll { $0.id == s.id } }; editing = nil
            } done: {
                if s.kind == .measure, let real = NumberInput.value(realLength), real > 0,
                   let across = SiteShapes.length(s, aspect: aspect, metersAcross: 1), across > 0 {
                    job.values[SiteShapes.scaleKey] = .text(String(format: "%.2f", real / across))
                }
            }
        }
        .padding(16).frame(width: 340)
        .foregroundStyle(Theme.navy)
    }

    func editorField(_ title: String, text: Binding<String>, placeholder: String, unit: String? = nil, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            HStack(spacing: 6) {
                TextField(placeholder, text: text).font(.system(size: 17, weight: .semibold))
                    .keyboardType(numeric ? .decimalPad : .default)
                if let unit { Text(unit).font(.system(size: 14)).foregroundStyle(Theme.inkMuted) }
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderControl.opacity(0.7)))
        }
    }

    func editorButtons(delete: @escaping () -> Void, done: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 10) {
            Button(role: .destructive, action: delete) {
                Text("ลบ").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.danger))
            }
            Button { done(); editing = nil } label: {
                Text("เสร็จ").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
