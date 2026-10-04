#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

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

    func markEditor(_ m: MapMark) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(m.kind.paletteTitle).font(.headline)
                Spacer()
                if m.kind == .trafo || m.kind == .mdb {
                    Button("ดึงจาก A3") {
                        // the n-th transformer / MDB on the picture takes the n-th one's size from A3
                        let same = marks.filter { $0.kind == m.kind }
                        let before = Array(same.prefix(same.firstIndex { $0.id == m.id } ?? 0))
                        markBinding(m.id, \.value).wrappedValue = SiteMarks.suggestedValue(m.kind, existing: before, trafos: job.values.transformers("trafos"))
                    }
                    .font(.system(size: 13)).frame(minHeight: 44)
                }
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
        .foregroundStyle(Home.navy)
    }

    func shapeEditor(_ s: SiteShape, rect r: CGRect) -> some View {
        let names: [ShapeKind: String] = [.panelArea: "พื้นที่ติดตั้งแผง", .cableRoute: "แนวสายไฟ", .measure: "วัดระยะ", .craneEntry: "ทางเข้าเครน", .shade: "ร่มเงา"]
        let aspect = r.height > 0 ? Double(r.width / r.height) : 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(names[s.kind] ?? "").font(.headline)
                Spacer()
                if s.kind == .measure, let m = metersAcross, let l = SiteShapes.length(s, aspect: aspect, metersAcross: m) {
                    Text(SiteShapes.meters(l)).font(.headline).monospacedDigit().foregroundStyle(Home.primary)
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
        .foregroundStyle(Home.navy)
    }

    func editorField(_ title: String, text: Binding<String>, placeholder: String, unit: String? = nil, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(Home.muted)
            HStack(spacing: 6) {
                TextField(placeholder, text: text).font(.system(size: 17, weight: .semibold))
                    .keyboardType(numeric ? .decimalPad : .default)
                if let unit { Text(unit).font(.system(size: 14)).foregroundStyle(Home.muted) }
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Home.borderControl.opacity(0.7)))
        }
    }

    func editorButtons(delete: @escaping () -> Void, done: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 10) {
            Button(role: .destructive, action: delete) {
                Text("ลบ").font(.system(size: 16, weight: .semibold)).foregroundStyle(Home.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.danger))
            }
            Button { done(); editing = nil } label: {
                Text("เสร็จ").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Home.primary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
