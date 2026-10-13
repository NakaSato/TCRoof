#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// Place symbols on the site picture (portrait and iPhone; landscape iPad uses `SitePageWide`).
/// Pick a symbol, tap the picture to drop it, drag to move, tap a symbol to select it for removal.
/// Lines and areas drawn on the iPad page are shown but not edited here.
struct SiteMarksEditor: View {
    @Binding var marks: [MapMark]
    let photo: Photo?
    var trafos: [Transformer] = []
    let jobID: UUID
    var shapes: [SiteShape] = []
    var metersAcross: Double? = nil
    @Environment(SurveyModel.self) private var model

    /// The design's palette; the retired water point and B5's FTS switch only while a job has one (they are placed from B3 / B5).
    var kinds: [MarkKind] { MarkKind.palette + [MarkKind.water, .emergency].filter { k in marks.contains { $0.kind == k } } }
    @State private var armed: MarkKind?
    @State private var selected: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(kinds) { k in
                    Button { armed = armed == k ? nil : k; selected = nil } label: { chip(k) }.buttonStyle(.plain)
                }
            }
            Text(hint).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(armed == nil ? Theme.inkMuted : Theme.primary)
            if let p = photo, let img = model.image(p, in: jobID), img.size.height > 0 {
                stage(img)
                HStack {
                    Text("วางแล้ว \(marks.count) จุด").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    if let sel = selected, let i = marks.firstIndex(where: { $0.id == sel }), let unit = marks[i].kind.unit {
                        Text(marks[i].kind == .trafo ? "ขนาดหม้อแปลง" : "ขนาดเบรกเกอร์ MDB").font(.sarabun(12, relativeTo: .caption))
                        TextField("0", text: Binding(get: { marks.indices.contains(i) ? marks[i].value : "" },
                                                     set: { v in if marks.indices.contains(i) { marks[i].value = v } }))
                            .keyboardType(.numberPad).textFieldStyle(OutlinedFieldStyle(dense: true)).frame(width: 90)
                        Text(unit).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    }
                    if let sel = selected, let m = marks.first(where: { $0.id == sel }) {
                        Button(role: .destructive) { marks.removeAll { $0.id == sel }; selected = nil } label: {
                            Label("ลบ \(SiteMarks.labels(marks)[m.id] ?? m.kind.title)", systemImage: "trash")
                        }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card))
                    }
                    if !marks.isEmpty {
                        Menu {
                            Button("ลบสัญลักษณ์ทั้งหมด", role: .destructive) { marks = []; selected = nil }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            } else {
                Text("ถ่ายหรือเลือก ภาพสถานที่ติดตั้ง ด้านบนก่อน แล้วจึงวางสัญลักษณ์").font(.sarabun(16, relativeTo: .callout)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    var hint: String {
        if let a = armed { return "แตะบนภาพเพื่อวาง \(a.title)" }
        return "เลือกสัญลักษณ์ แล้วแตะบนภาพเพื่อวาง · ลากเพื่อย้าย · แตะสัญลักษณ์เพื่อเลือกแล้วลบ"
    }

    func chip(_ k: MarkKind) -> some View {
        let on = armed == k
        return HStack(spacing: 6) {
            ToolIcon(tool: .mark(k)).frame(width: 24, height: 24)
            Text(k.paletteTitle).font(.sarabun(12, .semibold, relativeTo: .caption)).foregroundStyle(on ? Theme.onPrimary : Theme.navy)
        }
        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
        .background(on ? Theme.primary : Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(on ? Theme.primary : Theme.borderControl, lineWidth: 1.2))
    }

    func stage(_ img: UIImage) -> some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Image(uiImage: img).resizable().frame(width: size.width, height: size.height)
                Canvas { ctx, sz in
                    let box = Box(0, 0, Double(sz.width), Double(sz.height))
                    let ops = SiteShapes.ops(shapes, in: box, metersAcross: metersAcross) + SiteMarks.ops(marks, in: box)
                    ctx.withCGContext { cg in PDFRenderer.draw(ops, in: cg, photo: { _ in nil }) }
                }
                .allowsHitTesting(false)
                ForEach(marks) { m in
                    Circle().fill(Color.white.opacity(0.001))
                        .overlay { if selected == m.id { Circle().stroke(Color.yellow, lineWidth: 3).padding(6) } }
                        .frame(width: 44, height: 44)
                        .position(x: m.x * size.width, y: m.y * size.height)
                        .onTapGesture { selected = selected == m.id ? nil : m.id; armed = nil }
                        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("siteStage"))
                            .onChanged { g in move(m.id, to: g.location, in: size) })
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .coordinateSpace(name: "siteStage")
            .onTapGesture { loc in place(at: loc, in: size) }
        }
        .aspectRatio(img.size.width / img.size.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(armed == nil ? Theme.borderControl : Theme.primary, lineWidth: armed == nil ? 1 : 2))
    }

    func place(at p: CGPoint, in size: CGSize) {
        guard let k = armed, size.width > 0, size.height > 0 else { selected = nil; return }
        var m = MapMark(kind: k, x: Double(p.x / size.width), y: Double(p.y / size.height),
                        value: SiteMarks.suggestedValue(k, existing: marks, trafos: trafos))
        if [.trafo, .mdb, .roofLabel].contains(k) { m.label = SiteMarks.defaultLabel(m, in: marks + [m]) }
        marks.append(m)
        armed = nil
        selected = m.id
    }

    func move(_ id: UUID, to p: CGPoint, in size: CGSize) {
        guard let i = marks.firstIndex(where: { $0.id == id }), size.width > 0, size.height > 0 else { return }
        marks[i].x = min(max(Double(p.x / size.width), 0), 1)
        marks[i].y = min(max(Double(p.y / size.height), 0), 1)
        selected = id
    }

    func color(_ c: RGBA) -> Color { Color(c) }
}
#endif
