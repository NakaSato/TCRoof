#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// What the shade views draw (docs/ui/survey-d1-obstacles-ipad Part B): the tank, its panels, the objects around it and
/// the moment's sun, in tank metres (x right, y down, z above the ground). The plan and the 3D view read the same one.
struct TankShadeScene {
    struct Panel { let key: String; let rect: CGRect }
    let w: Double, h: Double
    let circle: TankPoints.Circle?
    let panels: [Panel]
    let items: [TankShade.Item]
    /// The roof above the ground, and the plan's top as a compass bearing.
    let exposed: Double, planAzimuth: Double
    let moment: TankShade.Moment?

    init(_ v: Values, items: [TankShade.Item], moment: TankShade.Moment?) {
        let t = TankPoints.tankSize(v) ?? (40, 40)
        w = t.w; h = t.h
        circle = TankPoints.circle(v)
        panels = (TankLayout.current(v)?.builtTables ?? []).flatMap { t in
            t.panels.filter(\.on).map { Panel(key: $0.key, rect: CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h)) }
        }
        self.items = items
        exposed = Tank.exposed(v) ?? 0
        planAzimuth = Double(Tank.azimuth(v) ?? 0)
        self.moment = moment
    }

    var hasLayout: Bool { !panels.isEmpty }
    /// Panels without direct sun at the moment.
    var shadedKeys: Set<String> {
        guard let m = moment else { return [] }
        return m.itemShaded.values.reduce(m.rowShaded) { $0.union($1) }
    }

    /// The part of the plan to show: the tank and every object, with a margin.
    var bounds: CGRect {
        var r = CGRect(x: 0, y: 0, width: w, height: h)
        for i in items { r = r.union(CGRect(x: i.x - i.width / 2, y: i.y - i.width / 2, width: i.width, height: i.width)) }
        return r.insetBy(dx: -4, dy: -4)
    }

    /// The plan direction towards the sun (unit), nil with it down.
    var sunOnPlan: CGVector? {
        guard let m = moment, m.altitude > 0 else { return nil }
        let r = (m.azimuth + 180 - planAzimuth) * .pi / 180
        return CGVector(dx: sin(r), dy: -cos(r))
    }
    /// North on the plan (unit).
    var northOnPlan: CGVector { let r = -planAzimuth * .pi / 180; return CGVector(dx: sin(r), dy: -cos(r)) }

    func shadow(_ i: TankShade.Item, onPlane z: Double) -> [CGPoint] {
        guard let m = moment else { return [] }
        return TankShade.shadow(i, altitude: m.altitude, azimuth: m.azimuth, planAzimuth: planAzimuth, onPlane: z).map { CGPoint(x: $0.x, y: $0.y) }
    }

    static func color(_ k: TankShade.Item.Kind) -> Color {
        switch k {
        case .tree: return Theme.success
        case .building: return Theme.inkMuted
        case .tower: return Theme.navy
        }
    }
}

/// `แปลน`: the tank and its panels from above on `Theme.paper` (the A2 picture under it when the job has one), the
/// objects with their `ID | h ม.` tags, the moment's shadows (lighter for trees), the selected object's gap to the
/// wall, and the sun on the frame's edge. Drag an object to move it.
struct TankShadePlan: View {
    let scene: TankShadeScene
    let picture: UIImage?
    @Binding var selected: String?
    /// The new centre of a dragged object (m).
    let moved: (String, Double, Double) -> Void
    /// Gap to the wall of an object (m), for the selected one's chip.
    let gap: (TankShade.Item) -> Double

    @State var drag: (id: String, dx: Double, dy: Double)?

    var body: some View {
        GeometryReader { g in
            let b = scene.bounds, k = min(g.size.width / b.width, g.size.height / b.height)
            let ox = (g.size.width - b.width * k) / 2 - b.minX * k, oy = (g.size.height - b.height * k) / 2 - b.minY * k
            let map = { (x: Double, y: Double) in CGPoint(x: ox + x * k, y: oy + y * k) }
            ZStack(alignment: .topLeading) {
                Theme.paper
                if let picture {
                    Image(uiImage: picture).resizable().scaledToFill().saturation(0.6).opacity(0.85)
                        .frame(width: g.size.width, height: g.size.height).clipped()
                        .allowsHitTesting(false)
                }
                Canvas { ctx, _ in draw(&ctx, map: map, k: k) }
                    .allowsHitTesting(false)
                ForEach(items) { i in target(i, map: map, k: k) }
                sunMarker(in: g.size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .coordinateSpace(name: "shadePlan")
        }
    }

    /// The items with a drag applied.
    var items: [TankShade.Item] {
        scene.items.map { i in
            guard let d = drag, d.id == i.id else { return i }
            var j = i; j.x += d.dx; j.y += d.dy; return j
        }
    }

    func draw(_ ctx: inout GraphicsContext, map: (Double, Double) -> CGPoint, k: Double) {
        let list = items
        let moving = TankShadeScene(scene, items: list)
        // shadows on the ground
        for i in list {
            let pts = moving.shadow(i, onPlane: 0).map { map($0.x, $0.y) }
            guard pts.count > 2 else { continue }
            ctx.fill(Path { $0.addLines(pts); $0.closeSubpath() }, with: .color(Theme.navySolid.opacity(i.kind == .tree ? 0.16 : 0.3)))
        }
        // the tank
        let tank: Path = scene.circle.map { c in Path(ellipseIn: CGRect(origin: map(c.cx - c.r, c.cy - c.r), size: CGSize(width: 2 * c.r * k, height: 2 * c.r * k))) }
            ?? Path(CGRect(origin: map(0, 0), size: CGSize(width: scene.w * k, height: scene.h * k)))
        ctx.fill(tank, with: .color(Theme.paper))
        ctx.stroke(tank, with: .color(Theme.navySolid), lineWidth: 2)
        let shaded = scene.shadedKeys
        for p in scene.panels {
            let r = CGRect(origin: map(p.rect.minX, p.rect.minY), size: CGSize(width: p.rect.width * k, height: p.rect.height * k))
            ctx.fill(Path(r), with: .color(shaded.contains(p.key) ? Theme.navySolid : Theme.primary.opacity(0.75)))
        }
        if !scene.hasLayout {
            ctx.draw(Text("ยังไม่มีผังแผง | จัดแผงในขั้นที่ 3").font(.sarabunFixed(13)).foregroundColor(Theme.inkMuted),
                     at: map(scene.w / 2, scene.h / 2))
        }
        // shadows on the roof, inside the tank
        ctx.drawLayer { l in
            l.clip(to: tank)
            for i in list where i.height > scene.exposed {
                let pts = moving.shadow(i, onPlane: scene.exposed).map { map($0.x, $0.y) }
                guard pts.count > 2 else { continue }
                l.fill(Path { $0.addLines(pts); $0.closeSubpath() }, with: .color(Theme.navySolid.opacity(i.kind == .tree ? 0.16 : 0.3)))
            }
        }
        // the objects
        for i in list { symbol(&ctx, i, map: map, k: k) }
    }

    func symbol(_ ctx: inout GraphicsContext, _ i: TankShade.Item, map: (Double, Double) -> CGPoint, k: Double) {
        let c = map(i.x, i.y), r = max(i.width / 2 * k, 6), on = i.id == selected
        let col = TankShadeScene.color(i.kind), box = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        switch i.kind {
        case .tree:
            ctx.fill(Path(ellipseIn: box), with: .color(col.opacity(0.35)))
            ctx.stroke(Path(ellipseIn: box), with: .color(col), lineWidth: 1.5)
        case .building:
            ctx.fill(Path(box), with: .color(Theme.paper))
            ctx.drawLayer { l in
                l.clip(to: Path(box))
                var h = Path()
                for d in stride(from: -2 * r, through: 2 * r, by: 6) { h.move(to: CGPoint(x: box.minX + d, y: box.maxY)); h.addLine(to: CGPoint(x: box.minX + d + 2 * r, y: box.minY)) }
                l.stroke(h, with: .color(col), lineWidth: 1)
            }
            ctx.stroke(Path(box), with: .color(col), lineWidth: 1.5)
        case .tower:
            ctx.fill(Path(ellipseIn: box), with: .color(Theme.paper))
            ctx.stroke(Path(ellipseIn: box), with: .color(col), lineWidth: 1.5)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(col))
        }
        if on {
            let ring = box.insetBy(dx: -4, dy: -4)
            ctx.stroke(i.kind == .building ? Path(ring) : Path(ellipseIn: ring), with: .color(Theme.warning), lineWidth: 2.5)
        }
        // the tag above it
        let tag = Text(i.id + " | " + fmt(i.height) + " ม.").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.onMedia)
        let resolved = ctx.resolve(tag), s = resolved.measure(in: CGSize(width: 200, height: 40))
        let pill = CGRect(x: c.x - s.width / 2 - 6, y: box.minY - s.height - 8, width: s.width + 12, height: s.height + 4)
        ctx.fill(Path(roundedRect: pill, cornerRadius: 5), with: .color(on ? Theme.warning : Theme.navySolid.opacity(0.85)))
        ctx.draw(resolved, at: CGPoint(x: pill.midX, y: pill.midY))
        // the selected one's gap to the wall
        if on {
            let gapText = ctx.resolve(Text(String(format: "%.1f ม.", gap(i))).font(.system(size: 11, weight: .bold)).foregroundColor(Theme.pending))
            let gs = gapText.measure(in: CGSize(width: 200, height: 40))
            let chip = CGRect(x: c.x - gs.width / 2 - 6, y: box.maxY + 6, width: gs.width + 12, height: gs.height + 4)
            ctx.fill(Path(roundedRect: chip, cornerRadius: 5), with: .color(Theme.paper))
            ctx.stroke(Path(roundedRect: chip, cornerRadius: 5), with: .color(Theme.warning), lineWidth: 1)
            ctx.draw(gapText, at: CGPoint(x: chip.midX, y: chip.midY))
        }
    }

    /// A 44-pt target on each object: tap selects, a drag moves it (one change on release).
    func target(_ i: TankShade.Item, map: @escaping (Double, Double) -> CGPoint, k: Double) -> some View {
        let c = map(i.x, i.y), side = max(44, i.width * k)
        return Color.clear
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .position(c)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("shadePlan"))
                    .onChanged { g in
                        guard drag != nil || hypot(g.translation.width, g.translation.height) > 4 else { return }
                        selected = i.id
                        drag = (i.id, g.translation.width / k, g.translation.height / k)
                    }
                    .onEnded { _ in
                        if let d = drag, d.id == i.id {
                            let src = scene.items.first { $0.id == i.id } ?? i
                            moved(i.id, src.x + d.dx, src.y + d.dy)
                        } else { selected = i.id }
                        drag = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("\(i.id) \(TankShade.Item.name(i.kind)) สูง \(fmt(i.height)) ม.")
            .accessibilityAddTraits(i.id == selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { selected = i.id }
            .accessibilityIdentifier("shadeItem-" + i.id)
    }

    /// The sun on the frame's edge, towards it from the centre.
    @ViewBuilder func sunMarker(in size: CGSize) -> some View {
        if let v = scene.sunOnPlan {
            let half = CGSize(width: size.width / 2 - 18, height: size.height / 2 - 18)
            let t = min(abs(v.dx) > 1e-6 ? half.width / abs(v.dx) : .infinity, abs(v.dy) > 1e-6 ? half.height / abs(v.dy) : .infinity)
            Circle().fill(Theme.warning).frame(width: 18, height: 18)
                .overlay(Circle().stroke(Theme.warning.opacity(0.35), lineWidth: 6))
                .position(x: size.width / 2 + v.dx * t, y: size.height / 2 + v.dy * t)
                .accessibilityHidden(true)
        }
    }
}

extension TankShadeScene {
    /// The same scene with the objects moved (a drag in progress).
    init(_ s: TankShadeScene, items: [TankShade.Item]) {
        w = s.w; h = s.h; circle = s.circle; panels = s.panels; self.items = items
        exposed = s.exposed; planAzimuth = s.planAzimuth; moment = s.moment
    }
}
#endif
