#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// A standard design in a picker (docs/specs/standard-designs.md §3.1): its small plan, the name, the size and what it
/// holds, how it matches the measured size, and where it came from.
struct DesignCard: View {
    let name: String
    let detail: String
    /// `ตรงกับขนาดที่วัด` or how far it differs; nil without a measured size.
    let line: String?
    let matches: Bool
    let source: String
    let sketch: Sketch?
    var selected = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
                Text(detail).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                if let line {
                    Text(line).font(.sarabunFixed(12.5, .bold)).foregroundStyle(matches ? Theme.okText : Theme.dangerText)
                }
                if !source.isEmpty {
                    Text(source).font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if selected {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.success)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(selected ? Theme.primary.opacity(0.06) : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.primary : Theme.borderSubtle, lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var thumbnail: some View {
        GeometryReader { geo in
            if let sketch {
                SketchCanvas(ops: sketch.ops, fit: SketchFit(sketch.width, sketch.height, in: geo.size))
            }
        }
        .frame(width: 76, height: 60)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderSubtle))
        .accessibilityHidden(true)
    }
}

/// D1's `เริ่มจากแบบมาตรฐาน กปภ.`: the library's tank designs as cards, closest to the measured size first.
struct TankDesignPicker: View {
    let matches: [TankDesign.Match]
    let current: String?
    let pick: (TankDesign.Match) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("แทนขนาดช่วงเสาและจุดบนหลังคาทั้งหมดด้วยแบบที่เลือก จุดที่ตรวจแล้วต้องตรวจใหม่")
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    ForEach(matches) { m in
                        Button { pick(m); dismiss() } label: {
                            DesignCard(name: m.design.name, detail: m.design.size + " | " + m.design.contents + (m.turned ? " | หมุนตามที่วัด" : ""),
                                       line: m.line, matches: m.matches, source: m.design.source,
                                       sketch: m.design.thumbnail(turned: m.turned), selected: m.design.id == current)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("เริ่มจากแบบมาตรฐาน กปภ.")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
