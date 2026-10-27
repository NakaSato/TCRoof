#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// `3 มิติ`: the same scene as the plan, orthographic from one of eight sides, drawn back to front with `Canvas`: the
/// ground and its shadows, the tank as a slab with its panels and the shadows on its roof, then the objects.
struct TankShade3D: View {
    let scene: TankShadeScene
    /// 0–7: the side the view looks from, in 45° steps of the plan (6 = from the plan's lower left).
    let turn: Int
    let selected: String?

    /// "ตต.เฉียงใต้": the compass side the view looks from.
    static func sideName(turn: Int, planAzimuth: Double) -> String {
        let th = Double(turn) * .pi / 4
        // the viewer sits along (1, 1) in the turned frame
        let xr = 1.0, yr = 1.0
        let x = xr * cos(th) + yr * sin(th), y = -xr * sin(th) + yr * cos(th)
        let compass = (atan2(x, -y) * 180 / .pi + planAzimuth + 720).truncatingRemainder(dividingBy: 360)
        let names = ["เหนือ", "ตอ.เฉียงเหนือ", "ตะวันออก", "ตอ.เฉียงใต้", "ใต้", "ตต.เฉียงใต้", "ตะวันตก", "ตต.เฉียงเหนือ"]
        return names[Int((compass / 45).rounded()) % 8]
    }

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size) }
            .background(LinearGradient(colors: [Theme.primarySoft, Theme.paper], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement()
            .accessibilityLabel("ภาพ 3 มิติของถังและสิ่งบัง " + scene.items.map(\.id).joined(separator: " "))
    }

    // MARK: projection

    struct Proj {
        let cx, cy, th, k, ox, oy: Double
        func turned(_ x: Double, _ y: Double) -> (Double, Double) {
            let X = x - cx, Y = y - cy
            return (X * cos(th) - Y * sin(th), X * sin(th) + Y * cos(th))
        }
        func raw(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
            let (a, b) = turned(x, y)
            return CGPoint(x: (a - b) * 0.866, y: (a + b) * 0.5 - z)
        }
        func callAsFunction(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
            let p = raw(x, y, z)
            return CGPoint(x: ox + p.x * k, y: oy + p.y * k)
        }
        func depth(_ x: Double, _ y: Double) -> Double { let (a, b) = turned(x, y); return a + b }
    }

    func projection(_ size: CGSize) -> Proj {
        let b = scene.bounds, th = Double(turn) * .pi / 4
        let base = Proj(cx: scene.w / 2, cy: scene.h / 2, th: th, k: 1, ox: 0, oy: 0)
        var pts = [(b.minX, b.minY), (b.maxX, b.minY), (b.minX, b.maxY), (b.maxX, b.maxY)].map { base.raw($0.0, $0.1, 0) }
        for i in scene.items { pts.append(base.raw(i.x, i.y, i.height)) }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let w = (xs.max()! - xs.min()!), h = (ys.max()! - ys.min()!)
        let k = min(size.width * 0.92 / max(w, 1), size.height * 0.88 / max(h, 1))
        return Proj(cx: base.cx, cy: base.cy, th: th, k: k,
                    ox: size.width / 2 - (xs.min()! + w / 2) * k, oy: size.height / 2 - (ys.min()! + h / 2) * k + size.height * 0.03)
    }

    /// The tank's outline on the plan (a 48-gon for a round tank).
    var outline: [(Double, Double)] {
        if let c = scene.circle {
            return (0..<48).map { let a = Double($0) / 48 * 2 * .pi; return (c.cx + c.r * cos(a), c.cy + c.r * sin(a)) }
        }
        return [(0, 0), (scene.w, 0), (scene.w, scene.h), (0, scene.h)]
    }

    func poly(_ pts: [CGPoint]) -> Path { Path { $0.addLines(pts); $0.closeSubpath() } }

    /// A vertical prism: its sides back to front, then its top.
    func prism(_ ctx: inout GraphicsContext, _ p: Proj, _ base: [(Double, Double)], z0: Double, z1: Double, side: Color, top: Color) {
        let n = base.count
        let faces = (0..<n).map { i -> (Double, [CGPoint]) in
            let a = base[i], b = base[(i + 1) % n]
            return (p.depth((a.0 + b.0) / 2, (a.1 + b.1) / 2), [p(a.0, a.1, z0), p(b.0, b.1, z0), p(b.0, b.1, z1), p(a.0, a.1, z1)])
        }
        for f in faces.sorted(by: { $0.0 < $1.0 }) {
            ctx.fill(poly(f.1), with: .color(side))
            ctx.stroke(poly(f.1), with: .color(Theme.navySolid.opacity(0.15)), lineWidth: 0.5)
        }
        ctx.fill(poly(base.map { p($0.0, $0.1, z1) }), with: .color(top))
    }

    func ring(_ x: Double, _ y: Double, _ r: Double, _ n: Int = 20) -> [(Double, Double)] {
        (0..<n).map { let a = Double($0) / Double(n) * 2 * .pi; return (x + r * cos(a), y + r * sin(a)) }
    }

    // MARK: drawing

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let p = projection(size), b = scene.bounds
        // the ground
        let ground = [(b.minX, b.minY), (b.maxX, b.minY), (b.maxX, b.maxY), (b.minX, b.maxY)].map { p($0.0, $0.1, 0) }
        ctx.fill(poly(ground), with: .color(Theme.success.opacity(0.14)))
        for i in scene.items {
            let s = scene.shadow(i, onPlane: 0)
            if s.count > 2 { ctx.fill(poly(s.map { p($0.x, $0.y, 0) }), with: .color(Theme.navySolid.opacity(i.kind == .tree ? 0.14 : 0.26))) }
        }
        // the objects behind the tank first, then the tank, then the ones in front
        let tankDepth = p.depth(scene.w / 2, scene.h / 2)
        let sorted = scene.items.sorted { p.depth($0.x, $0.y) < p.depth($1.x, $1.y) }
        for i in sorted where p.depth(i.x, i.y) < tankDepth { item(&ctx, p, i) }
        tank(&ctx, p)
        for i in sorted where p.depth(i.x, i.y) >= tankDepth { item(&ctx, p, i) }
    }

    func tank(_ ctx: inout GraphicsContext, _ p: Proj) {
        let z = scene.exposed
        prism(&ctx, p, outline, z0: 0, z1: max(z, 0.3), side: Theme.inkFaint, top: Theme.borderOutdoor)
        let roof = poly(outline.map { p($0.0, $0.1, max(z, 0.3)) })
        let shaded = scene.shadedKeys
        ctx.drawLayer { l in
            l.clip(to: roof)
            for panel in scene.panels {
                let r = panel.rect, zz = max(z, 0.3) + 0.05
                let q = [p(r.minX, r.minY, zz), p(r.maxX, r.minY, zz), p(r.maxX, r.maxY, zz), p(r.minX, r.maxY, zz)]
                l.fill(poly(q), with: .color(shaded.contains(panel.key) ? Theme.navySolid : Theme.primary.opacity(0.8)))
            }
            for i in scene.items where i.height > z {
                let s = scene.shadow(i, onPlane: z)
                if s.count > 2 { l.fill(poly(s.map { p($0.x, $0.y, max(z, 0.3) + 0.06) }), with: .color(Theme.navySolid.opacity(i.kind == .tree ? 0.16 : 0.3))) }
            }
        }
    }

    func item(_ ctx: inout GraphicsContext, _ p: Proj, _ i: TankShade.Item) {
        let col = TankShadeScene.color(i.kind), on = i.id == selected
        switch i.kind {
        case .building:
            let r = i.width / 2
            prism(&ctx, p, [(i.x - r, i.y - r), (i.x + r, i.y - r), (i.x + r, i.y + r), (i.x - r, i.y + r)], z0: 0, z1: i.height,
                  side: col.opacity(0.55), top: col.opacity(0.35))
        case .tower:
            let tank = 0.75 * i.height
            prism(&ctx, p, ring(i.x, i.y, max(0.15 * i.width, 0.3) / 2, 12), z0: 0, z1: tank, side: col.opacity(0.8), top: col)
            prism(&ctx, p, ring(i.x, i.y, i.width / 2, 24), z0: tank, z1: i.height, side: col.opacity(0.75), top: col.opacity(0.55))
        case .tree:
            var trunk = Path(); trunk.move(to: p(i.x, i.y, 0)); trunk.addLine(to: p(i.x, i.y, 0.45 * i.height))
            ctx.stroke(trunk, with: .color(Theme.warningText), lineWidth: max(2, 0.3 * p.k))
            let c = p(i.x, i.y, 0.7 * i.height), rx = i.width / 2 * 1.22 * p.k, ry = max(i.width / 2 * 0.707, 0.3 * i.height) * p.k
            let crown = Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry))
            ctx.fill(crown, with: .color(on ? Theme.warning.opacity(0.75) : col.opacity(0.7)))
        }
        // the tag over the top
        let top = p(i.x, i.y, i.height)
        let tag = ctx.resolve(Text(i.id + " | " + fmt(i.height) + " ม.").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.onMedia))
        let s = tag.measure(in: CGSize(width: 200, height: 40))
        let pill = CGRect(x: top.x - s.width / 2 - 6, y: top.y - s.height - 10, width: s.width + 12, height: s.height + 4)
        ctx.fill(Path(roundedRect: pill, cornerRadius: 5), with: .color(on ? Theme.warning : Theme.navySolid.opacity(0.8)))
        ctx.draw(tag, at: CGPoint(x: pill.midX, y: pill.midY))
    }
}
#endif
