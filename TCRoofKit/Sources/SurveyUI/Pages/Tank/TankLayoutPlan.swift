#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// D1 sub-step 3 on iPhone (docs/ui/survey-d1-layout-iphone): the 330 × 300 tank plan (`TankPlan.compact`) with the
/// panel tables of `TankLayout` (svg/README.md: blue panels, teal row guides, the slope tag). `เลื่อนผัง` drags the
/// whole layout (snapped to 5 cm, clearance kept); `แก้แผง` taps a panel on / off and long-presses a table to remove it.
struct TankLayoutPlan: View {
    let values: Values
    let layout: TankLayout
    /// true: `แก้แผง`; false: `เลื่อนผัง`.
    let editing: Bool
    /// Drops the layout at a new offset (m).
    let move: (Double, Double) -> Void
    let toggle: (String) -> Void
    let removeTable: (Int, Int) -> Void

    /// The offset while dragging, and the press being tracked for a long press.
    @State var preview: TankLayout?
    @State var press: UUID?
    @State var pressUsed = false

    var shown: TankLayout { preview ?? layout }

    var body: some View {
        if let sketch = TankPlan.compact(values), let f = TankPlan.compactFrame(values) {
            GeometryReader { g in
                let fit = SketchFit(sketch.width, sketch.height, in: g.size)
                ZStack {
                    SketchCanvas(ops: sketch.ops, fit: fit)
                    Canvas { ctx, _ in
                        ctx.translateBy(x: fit.ox, y: fit.oy)
                        ctx.scaleBy(x: fit.s, y: fit.s)
                        draw(&ctx, f)
                    }
                }
                .contentShape(Rectangle())
                .gesture(gesture(fit, f))
            }
            .aspectRatio(sketch.width / sketch.height, contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel("ผังแผง \(layout.count) แผง \(layout.builtTables.count) โต๊ะ")
            .accessibilityHint(editing ? "แตะแผงเพื่อเปิดหรือปิด กดค้างที่โต๊ะเพื่อเอาโต๊ะออก" : "ลากเพื่อเลื่อนผังทั้งหมด")
        }
    }

    // MARK: drawing (in the plan's 330 × 300 units)

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ f: (ox: Double, oy: Double, k: Double)) -> CGRect {
        CGRect(x: f.ox + x * f.k, y: f.oy + y * f.k, width: w * f.k, height: h * f.k)
    }

    func draw(_ ctx: inout GraphicsContext, _ f: (ox: Double, oy: Double, k: Double)) {
        let l = shown
        // obstacles from sub-step 2, faint: hatches and other obstacles block, vents may be covered
        for o in TankPoints.points(values) where !o.isAbsent {
            guard let r = TankPoints.rect(o) else { continue }
            let b = rect(r.x, r.y, r.w, r.h, f).insetBy(dx: -1, dy: -1)
            ctx.stroke(Path(b), with: .color(Theme.borderControl.opacity(0.6)), style: StrokeStyle(lineWidth: 0.8, dash: o.kind == TankPoints.vent ? [] : [2, 1.5]))
        }
        for t in l.tables {
            for p in t.panels {
                let b = rect(p.x, p.y, p.w, p.h, f)
                if p.on {
                    ctx.fill(Path(b), with: .color(Theme.panelBlue.opacity(0.85)))
                    ctx.stroke(Path(b), with: .color(Theme.paper), lineWidth: 0.5)
                } else {
                    ctx.stroke(Path(b.insetBy(dx: 0.4, dy: 0.4)), with: .color(Theme.panelBlue.opacity(0.5)), style: StrokeStyle(lineWidth: 0.6, dash: [2, 1.5]))
                }
            }
        }
        // columns cut so no leg touches an opening
        for c in l.cuts {
            ctx.stroke(Path(rect(c.x, c.y, c.w, c.h, f).insetBy(dx: 0.4, dy: 0.4)), with: .color(Theme.danger), style: StrokeStyle(lineWidth: 0.7, dash: [2, 1.5]))
        }
        // the row guide along each table, and its posts
        for t in l.builtTables {
            let (a, b) = t.guide
            var p = Path()
            p.move(to: CGPoint(x: f.ox + a.x * f.k, y: f.oy + a.y * f.k)); p.addLine(to: CGPoint(x: f.ox + b.x * f.k, y: f.oy + b.y * f.k))
            ctx.stroke(p, with: .color(Theme.teal), lineWidth: 0.8)
            for q in t.posts {
                ctx.fill(Path(ellipseIn: CGRect(x: f.ox + q.x * f.k - 1, y: f.oy + q.y * f.k - 1, width: 2, height: 2)), with: .color(Theme.navySolid))
            }
        }
        // slope tag at the bottom left inside the tank; the arrow points to the wall the panels face
        let pill = CGRect(x: f.ox + 1.5 * f.k, y: f.oy + (l.size.h - 0.6) * f.k - 13, width: 50, height: 12)
        ctx.fill(Path(roundedRect: pill, cornerRadius: 6), with: .color(Theme.primary))
        ctx.draw(Text(["↓", "→", "↑", "←"][l.turn] + " ลาดลงใต้").font(.system(size: 7.5, weight: .bold)).foregroundColor(Theme.onMedia), at: CGPoint(x: pill.midX, y: pill.midY))
    }

    // MARK: touch

    func metres(_ p: CGPoint, _ fit: SketchFit, _ f: (ox: Double, oy: Double, k: Double)) -> (x: Double, y: Double) {
        let s = fit.sketch(p)
        return ((s.x - f.ox) / f.k, (s.y - f.oy) / f.k)
    }

    /// The panel under a touch, or the nearest within 10 pt.
    func panel(at p: CGPoint, _ fit: SketchFit, _ f: (ox: Double, oy: Double, k: Double)) -> (TankLayout.Table, TankLayout.Panel)? {
        let m = metres(p, fit, f), tol = 10 / (fit.s * f.k)
        var best: (TankLayout.Table, TankLayout.Panel, Double)?
        for t in layout.tables {
            for q in t.panels {
                let d = hypot(max(q.x - m.x, 0, m.x - (q.x + q.w)), max(q.y - m.y, 0, m.y - (q.y + q.h)))
                if d <= tol && d < (best?.2 ?? .infinity) { best = (t, q, d) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    func gesture(_ fit: SketchFit, _ f: (ox: Double, oy: Double, k: Double)) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let moved = hypot(g.translation.width, g.translation.height)
                if press == nil {
                    let id = UUID(); press = id; pressUsed = false
                    if editing {
                        // a long press: still down and in place after 0.5 s
                        let at = g.startLocation
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            guard press == id, !pressUsed, let (t, _) = panel(at: at, fit, f) else { return }
                            pressUsed = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            removeTable(t.row, t.index)
                        }
                    }
                }
                if moved > 8 { pressUsed = pressUsed || editing }
                guard !editing, moved > 4 else { return }
                var p = layout.params
                let r = TankLayout.offsetRange(values, p)
                p.offX = TankLayout.snap(min(max(0, layout.params.offX + g.translation.width / (fit.s * f.k)), r.x))
                p.offY = TankLayout.snap(min(max(0, layout.params.offY + g.translation.height / (fit.s * f.k)), r.y))
                preview = TankLayout(values, params: p, off: TankLayout.off(values))
            }
            .onEnded { g in
                defer { press = nil; preview = nil }
                if editing {
                    guard !pressUsed, hypot(g.translation.width, g.translation.height) <= 8, let (_, q) = panel(at: g.startLocation, fit, f) else { return }
                    pressUsed = true
                    toggle(q.key)
                } else if let p = preview?.params {
                    move(p.offX, p.offY)
                }
            }
    }
}
#endif
