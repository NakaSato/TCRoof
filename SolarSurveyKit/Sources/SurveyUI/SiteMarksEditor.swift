#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// Place PEA METER, TRANSFORMER, MDB, INVERTER STATION, WATER CONNECTION POINT and SITE OFFICE symbols on the site picture.
/// Pick a symbol, tap the picture to drop it, drag to move, tap a symbol to select it for removal.
struct SiteMarksEditor: View {
    @Binding var marks: [MapMark]
    let photo: Photo?
    var trafos: [Transformer] = []
    let jobID: UUID
    @Environment(SurveyModel.self) private var model
    @State private var armed: MarkKind?
    @State private var selected: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(MarkKind.allCases) { k in
                    Button { armed = armed == k ? nil : k; selected = nil } label: { chip(k) }.buttonStyle(.plain)
                }
            }
            Text(hint).font(.footnote).foregroundStyle(armed == nil ? Color.secondary : Color.accentColor)
            if let p = photo, let img = model.image(p, in: jobID), img.size.height > 0 {
                stage(img)
                HStack {
                    Text("วางแล้ว \(marks.count) จุด").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let sel = selected, let i = marks.firstIndex(where: { $0.id == sel }), let unit = marks[i].kind.unit {
                        Text(marks[i].kind == .trafo ? "ขนาดหม้อแปลง" : "ขนาดเบรกเกอร์ MDB").font(.caption)
                        TextField("0", text: Binding(get: { marks.indices.contains(i) ? marks[i].value : "" },
                                                     set: { v in if marks.indices.contains(i) { marks[i].value = v } }))
                            .keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 90)
                        Text(unit).font(.caption).foregroundStyle(.secondary)
                    }
                    if let sel = selected, let m = marks.first(where: { $0.id == sel }) {
                        Button(role: .destructive) { marks.removeAll { $0.id == sel }; selected = nil } label: {
                            Label("ลบ \(SiteMarks.labels(marks)[m.id] ?? m.kind.title)", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                    if !marks.isEmpty {
                        Menu {
                            Button("ลบสัญลักษณ์ทั้งหมด", role: .destructive) { marks = []; selected = nil }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            } else {
                Text("ถ่ายหรือเลือก ภาพสถานที่ติดตั้ง ด้านบนก่อน แล้วจึงวางสัญลักษณ์").font(.callout).foregroundStyle(.secondary)
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
            Canvas { ctx, sz in
                let ops = SiteMarks.symbol(k, at: Pt(Double(sz.width) / 2, Double(sz.height) / 2), radius: Double(min(sz.width, sz.height)) / 2 - 1)
                ctx.withCGContext { cg in PDFRenderer.draw(ops, in: cg, photo: { _ in nil }) }
            }
            .frame(width: 24, height: 24)
            Text(k.title).font(.caption.weight(.semibold)).foregroundStyle(on ? Color.white : Color.primary)
        }
        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
        .background(on ? Color.accentColor : Color(uiColor: .systemBackground), in: Capsule())
        .overlay(Capsule().stroke(on ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1.2))
    }

    func stage(_ img: UIImage) -> some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Image(uiImage: img).resizable().frame(width: size.width, height: size.height)
                Canvas { ctx, sz in
                    let ops = SiteMarks.ops(marks, in: Box(0, 0, Double(sz.width), Double(sz.height)))
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
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(armed == nil ? Color.secondary.opacity(0.3) : Color.accentColor, lineWidth: armed == nil ? 1 : 2))
    }

    func place(at p: CGPoint, in size: CGSize) {
        guard let k = armed, size.width > 0, size.height > 0 else { selected = nil; return }
        let m = MapMark(kind: k, x: Double(p.x / size.width), y: Double(p.y / size.height),
                        value: SiteMarks.suggestedValue(k, existing: marks, trafos: trafos))
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

    func color(_ c: RGBA) -> Color { Color(red: c.r, green: c.g, blue: c.b) }
}
#endif
