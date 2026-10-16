#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// D1 sub-step 2 on iPhone (docs/ui/survey-d1-obstacles-iphone): the 330 × 300 tank plan (`TankPlan.compact`) with
/// the vents and hatches drawn on it (svg/marker-*), tap to select and drag to move. While a point is selected or
/// dragged, a teal guide shows the other points on its row / column and a tag its distance from the left wall.
struct TankPointsPlan: View {
    let values: Values
    @Binding var selected: UUID?
    /// Drops a dragged point at its new top-left corner (m).
    let move: (UUID, Double, Double) -> Void

    @State var drag: (id: UUID, drop: TankPoints.Drop)?
    @State var dragStart: TankPoints.Rect?

    enum Look { case unconfirmed, confirmed, absent, selected }
    struct Mark: Identifiable {
        let id: UUID
        let point: Obstacle
        let rect: TankPoints.Rect
        let state: Look
    }

    static func color(_ s: Look) -> Color {
        switch s {
        case .unconfirmed: return Theme.primary
        case .confirmed: return Theme.navySolid
        case .absent: return Theme.danger
        case .selected: return Theme.warning
        }
    }
    static func stateName(_ s: Look) -> String {
        switch s {
        case .unconfirmed: return "ยังไม่ยืนยัน"
        case .confirmed: return "ยืนยันแล้ว"
        case .absent: return "ไม่มีจริง"
        case .selected: return "จุดที่เลือก"
        }
    }

    var marks: [Mark] {
        TankPoints.points(values).compactMap { o in
            guard var r = TankPoints.rect(o) else { return nil }
            if let d = drag, d.id == o.id { r.x = d.drop.x; r.y = d.drop.y }
            let s: Look = o.id == selected ? .selected : o.isAbsent ? .absent : o.status.isEmpty ? .unconfirmed : .confirmed
            return Mark(id: o.id, point: o, rect: r, state: s)
        }
    }

    var body: some View {
        if let sketch = TankPlan.compact(values), let f = TankPlan.compactFrame(values), let t = TankPoints.tankSize(values) {
            GeometryReader { g in
                let fit = SketchFit(sketch.width, sketch.height, in: g.size), all = marks
                ZStack(alignment: .topLeading) {
                    SketchCanvas(ops: sketch.ops, fit: fit)
                    Canvas { ctx, _ in
                        ctx.translateBy(x: fit.ox, y: fit.oy)
                        ctx.scaleBy(x: fit.s, y: fit.s)
                        draw(&ctx, all, f, t)
                    }
                    .allowsHitTesting(false)
                    ForEach(all) { m in target(m, fit: fit, f: f) }
                }
                .coordinateSpace(name: "tankPoints")
            }
            .aspectRatio(sketch.width / sketch.height, contentMode: .fit)
        }
    }

    // MARK: drawing (in the plan's 330 × 300 units)

    func centre(_ r: TankPoints.Rect, _ f: (ox: Double, oy: Double, k: Double)) -> CGPoint {
        CGPoint(x: f.ox + r.cx * f.k, y: f.oy + r.cy * f.k)
    }

    func draw(_ ctx: inout GraphicsContext, _ all: [Mark], _ f: (ox: Double, oy: Double, k: Double), _ t: (w: Double, h: Double)) {
        let sel = all.first { $0.state == .selected }
        // guides under the symbols
        if let s = sel {
            for g in guides(s, all) {
                var p = Path()
                if let x = g.x { p.move(to: CGPoint(x: f.ox + x * f.k, y: f.oy)); p.addLine(to: CGPoint(x: f.ox + x * f.k, y: f.oy + t.h * f.k)) }
                if let y = g.y { p.move(to: CGPoint(x: f.ox, y: f.oy + y * f.k)); p.addLine(to: CGPoint(x: f.ox + t.w * f.k, y: f.oy + y * f.k)) }
                ctx.stroke(p, with: .color(Theme.teal), lineWidth: 1)
            }
        }
        for m in all where m.state != .selected { symbol(&ctx, m, f) }
        if let s = sel {
            symbol(&ctx, s, f)
            // distance from the left wall, under the symbol
            let c = centre(s.rect, f), box = CGRect(x: c.x - 30, y: c.y + 12, width: 42, height: 13)
            ctx.fill(Path(roundedRect: box, cornerRadius: 6), with: .color(Theme.paper))
            ctx.stroke(Path(roundedRect: box, cornerRadius: 6), with: .color(Theme.warning), lineWidth: 1)
            ctx.draw(Text(String(format: "%.2f", s.rect.x)).font(.system(size: 8, weight: .bold)).foregroundColor(Theme.pending),
                     at: CGPoint(x: box.midX, y: box.midY))
        }
    }

    /// The selected point's guides: the drag's snapped lines, or the rows / columns it shares with other points.
    func guides(_ s: Mark, _ all: [Mark]) -> [(x: Double?, y: Double?)] {
        if let d = drag, d.id == s.id { return [(d.drop.guideX, d.drop.guideY)] }
        let others = all.filter { $0.id != s.id && $0.state != .absent }
        let x = others.contains { abs($0.rect.cx - s.rect.cx) < 0.01 } ? s.rect.cx : nil
        let y = others.contains { abs($0.rect.cy - s.rect.cy) < 0.01 } ? s.rect.cy : nil
        return [(x, y)]
    }

    /// A 12-pt symbol (vent: square + ring; hatch: hatched square) and its label pill, coloured by state.
    func symbol(_ ctx: inout GraphicsContext, _ m: Mark, _ f: (ox: Double, oy: Double, k: Double)) {
        let c = centre(m.rect, f), col = Self.color(m.state), sq = CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
        let dash: [CGFloat] = m.state == .absent ? [3, 2] : []
        if m.state == .selected {
            let halo = CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)
            ctx.fill(Path(roundedRect: halo, cornerRadius: 5), with: .color(Theme.warning.opacity(0.18)))
            ctx.stroke(Path(roundedRect: halo, cornerRadius: 5), with: .color(Theme.warning), lineWidth: 1)
        }
        if m.point.kind == TankPoints.vent {
            ctx.fill(Path(sq), with: .color(Theme.paper))
            ctx.stroke(Path(sq), with: .color(col), style: StrokeStyle(lineWidth: 1.5, dash: dash))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(col), lineWidth: 1)
        } else {
            ctx.fill(Path(sq), with: .color(Theme.paper))
            var h = Path()
            for d in stride(from: -12.0, through: 12, by: 4) {
                h.move(to: CGPoint(x: sq.minX + d, y: sq.maxY)); h.addLine(to: CGPoint(x: sq.minX + d + 12, y: sq.minY))
            }
            ctx.drawLayer { l in
                l.clip(to: Path(sq))
                l.stroke(h, with: .color(col), lineWidth: 1.2)
            }
            ctx.stroke(Path(sq), with: .color(col), style: StrokeStyle(lineWidth: 1, dash: dash))
        }
        let w: CGFloat = m.point.label.count > 2 ? 26 : 20
        let pill = CGRect(x: c.x + 8, y: c.y - 14, width: w, height: 12)
        ctx.fill(Path(roundedRect: pill, cornerRadius: 6), with: .color(col))
        ctx.draw(Text(m.point.label).font(.system(size: 8, weight: .bold)).foregroundColor(Theme.onMedia), at: CGPoint(x: pill.minX + 4, y: pill.midY), anchor: .leading)
    }

    // MARK: touch

    /// A 44-pt target on the symbol: tap selects it, a drag moves it (snapped by `TankPoints.drop`).
    func target(_ m: Mark, fit: SketchFit, f: (ox: Double, oy: Double, k: Double)) -> some View {
        let c = centre(m.rect, f), p = fit.point(Pt(c.x, c.y))
        return Color.clear
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(x: p.x, y: p.y)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("tankPoints"))
                    .onChanged { g in
                        guard drag != nil || hypot(g.translation.width, g.translation.height) > 4 else { return }
                        if dragStart == nil { dragStart = TankPoints.rect(m.point); selected = m.id }
                        guard let s = dragStart, let d = TankPoints.drop(values, m.id, x: s.x + g.translation.width / (fit.s * f.k),
                                                                          y: s.y + g.translation.height / (fit.s * f.k)) else { return }
                        // snapped: most touch events land on the same spot, and only a move needs a redraw
                        if let old = drag, old.id == m.id, old.drop.x == d.x, old.drop.y == d.y { return }
                        drag = (m.id, d)
                    }
                    .onEnded { _ in
                        if let d = drag, d.id == m.id { move(m.id, d.drop.x, d.drop.y) } else { selected = m.id }
                        drag = nil; dragStart = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("\(m.point.label) \(TankPoints.kindName(m.point.kind)) \(Self.stateName(m.state))")
            .accessibilityValue(String(format: "ห่างผนังซ้าย %.2f ม. ห่างผนังบน %.2f ม.", m.rect.x, m.rect.y))
            .accessibilityAddTraits(m.state == .selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { selected = m.id }
    }
}
#endif
