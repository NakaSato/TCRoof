import Foundation

/// The team's tank mounting components (docs/specs/cad-export-dxf, Tank mounting components), taken one by one from
/// their section drawings (`reference/Tank mounting Section 1.dxf`, `Section 2.dxf`) by `tools/cad-details/components.py`
/// into `Resources/tank-components.json`: true size in metres, each with its base point at (0, 0). The tank DXF defines
/// each as one block (`TK_…`), so every component is edited on its own (BEDIT changes every place it is used), and puts
/// the row section, the table's front elevation, the footings and the details together from them.
public struct TankComponents: Decodable, Sendable {
    public struct Poly: Decodable, Sendable { public var points: [[Double]]; public var closed: Bool? }
    public struct Line: Decodable, Sendable {
        public var angle: Double; public var base: [Double]; public var offset: [Double]; public var dashes: [Double]
    }
    public struct Hatch: Decodable, Sendable { public var loops: [[[Double]]]; public var pattern: String; public var lines: [Line] }
    public struct Component: Decodable, Sendable {
        public var note: String
        public var source: String
        /// x1, y1, x2, y2 (metres).
        public var lines: [[Double]]
        public var polylines: [Poly]
        public var hatches: [Hatch]
        /// x0, y0, x1, y1 around the base point.
        public var box: [Double]
    }
    public var components: [String: Component]

    /// The components the app ships.
    public static let shared: TankComponents? = {
        guard let url = Bundle.module.url(forResource: "tank-components", withExtension: "json"), let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TankComponents.self, from: d)
    }()

    /// Each component's block name and the layer its INSERTs go on.
    public static let names: [String: (block: String, layer: SketchDXF.Layer)] = [
        "module_side": ("TK_MODULE_SIDE", CADLayers.pvModule), "rail_clamp": ("TK_RAIL_CLAMP", CADLayers.pvRail),
        "rail_section": ("TK_RAIL_SECTION", CADLayers.pvRail), "base_side": ("TK_BASE_SIDE", CADLayers.pvFooting),
        "base_front": ("TK_BASE_FRONT", CADLayers.pvFooting), "anchor_m12": ("TK_ANCHOR_M12", CADLayers.pvFooting),
        "base_plan": ("TK_BASE_PLAN", CADLayers.pvFooting), "topping_plan": ("TK_TOPPING_PLAN", CADLayers.pvFooting),
        "topping": ("TK_TOPPING", CADLayers.pvFooting), "topping_detail": ("TK_TOPPING_DETAIL", CADLayers.pvFooting),
        "module_plan": ("TK_MODULE_PLAN", CADLayers.pvModule),
    ]
    /// The module on plan as the team's PV panel block draws it (portrait, cells and busbars): stretched to each module.
    public static let modulePlanDrawn = (w: 0.992, h: 1.956)

    /// The members drawn as closed polylines (stretched in CAD by their grips): post, rafter and brace widths (m), and
    /// where the braces meet the rafter (m along it from the front / back post), as the team's section draws them.
    public static let post = 0.05, rafter = 0.075, brace = 0.045, braceFront = 1.10, braceBack = 1.40
    /// The rafter past the front post (down the slope) and past the back post (up), along it: 4.00 m for the standard.
    public static let rafterFront = 0.40, rafterBack = 0.70
    /// The module drawing's own length: the block is stretched along the slope to the layout's module.
    public static let moduleDrawn = 2.28

    /// Defines every component's block once (an identical body is reused) and returns the names.
    @discardableResult
    public func define(_ dxf: inout SketchDXF) -> [String: String] {
        var out: [String: String] = [:]
        for (id, c) in components.sorted(by: { $0.key < $1.key }) {
            guard let n = Self.names[id] else { continue }
            // once per file: every later call only names them
            if dxf.hasBlock(n.block) { out[id] = n.block; continue }
            out[id] = dxf.block(n.block) { d in
                d.fine = true
                let l = n.layer
                for s in c.lines where s.count >= 4 { d.line(l, (s[0], s[1]), (s[2], s[3])) }
                for p in c.polylines { d.polyline(l, p.points.map { ($0[0], $0[1]) }, closed: p.closed ?? false) }
                for h in c.hatches {
                    d.patternHatch(l, loops: h.loops.map { $0.map { ($0[0], $0[1]) } }, name: h.pattern,
                                   lines: h.lines.map { .init(angle: $0.angle, base: ($0.base[0], $0.base[1]), offset: ($0.offset[0], $0.offset[1]), dashes: $0.dashes) })
                }
                d.fine = false
            }
        }
        return out
    }

    /// An INSERT of component `id` (its block defined on first use).
    func insert(_ dxf: inout SketchDXF, _ id: String, at p: (Double, Double), rotation: Double = 0, scale: Double = 1, xScale: Double? = nil) {
        guard let n = Self.names[id] else { return }
        define(&dxf)
        if let xs = xScale, abs(xs - scale) > 1e-9 {
            dxf.insert(n.layer, n.block, at: p, rotation: rotation, xScale: xs, yScale: scale)
        } else {
            dxf.insert(n.layer, n.block, at: p, rotation: rotation, scale: scale)
        }
    }

    /// A member `w` wide along a → b as a closed polyline.
    static func member(_ dxf: inout SketchDXF, _ l: SketchDXF.Layer, _ a: (Double, Double), _ b: (Double, Double), width w: Double) {
        let L = hypot(b.0 - a.0, b.1 - a.1)
        guard L > 1e-6 else { return }
        let nx = -(b.1 - a.1) / L * w / 2, ny = (b.0 - a.0) / L * w / 2
        dxf.polyline(l, [(a.0 + nx, a.1 + ny), (b.0 + nx, b.1 + ny), (b.0 - nx, b.1 - ny), (a.0 - nx, a.1 - ny)], closed: true)
    }

    /// The module rows' section from the components (the tank DXF's row section), `o` the first row's front post at the
    /// roof: per post the concrete topping and the side base on the slab and the post up to the rafter; the rafter along
    /// the tilt over the post tops; the two braces; and the two modules with their rail clamps on the rafter.
    public func rowSection(_ dxf: inout SketchDXF, _ p: TankLayout.Params, origin o: (Double, Double)) {
        let t = p.tilt * .pi / 180, c = cos(t), s = sin(t), T = Self.self
        let along = p.postDY / c
        for row in 0..<2 {
            let x0 = o.0 + Double(row) * p.rowPitch
            // the rafter's underside runs through the post tops
            let top = (x0, o.1 + p.hFront)
            func under(_ d: Double) -> (Double, Double) { (top.0 + d * c, top.1 + d * s) }
            func over(_ d: Double) -> (Double, Double) { let q = under(d); return (q.0 - T.rafter * s, q.1 + T.rafter * c) }
            for (x, h) in [(x0, p.hFront), (x0 + p.postDY, p.hBack)] {
                insert(&dxf, "topping", at: (x, o.1))
                insert(&dxf, "base_side", at: (x, o.1))
                insert(&dxf, "anchor_m12", at: (x, o.1))
                dxf.polyline(CADLayers.pvTable, [(x - T.post / 2, o.1 + 0.15), (x + T.post / 2, o.1 + 0.15), (x + T.post / 2, o.1 + h), (x - T.post / 2, o.1 + h)], closed: true)
            }
            let r0 = -T.rafterFront, r1 = along + T.rafterBack
            dxf.polyline(CADLayers.pvRafter, [under(r0), under(r1), over(r1), over(r0)], closed: true)
            T.member(&dxf, CADLayers.pvBrace, (x0 + T.post, o.1 + 0.15), under(T.braceFront), width: T.brace)
            T.member(&dxf, CADLayers.pvBrace, (x0 + p.postDY - T.post, o.1 + 0.15), under(along - T.braceBack), width: T.brace)
            // the two modules up the slope, each stretched to the layout's module length
            for m in 0..<2 {
                let d = -p.frontOver + Double(m) * (p.moduleL + p.moduleGap)
                insert(&dxf, "module_side", at: over(d), rotation: p.tilt, xScale: p.moduleL / T.moduleDrawn)
            }
        }
    }

    /// The table's front elevation from the components, `o` its west end at the roof and `xs` its post pairs along it:
    /// per post the topping and the front base on the slab and the front post up to its top, and the X bracing in every
    /// bay as members.
    public func frontElevation(_ dxf: inout SketchDXF, _ p: TankLayout.Params, posts xs: [Double], origin o: (Double, Double)) {
        let T = Self.self
        for x in xs {
            insert(&dxf, "topping", at: (o.0 + x, o.1))
            insert(&dxf, "base_front", at: (o.0 + x, o.1))
            dxf.polyline(CADLayers.pvTable, [(o.0 + x - T.post / 2, o.1 + 0.15), (o.0 + x + T.post / 2, o.1 + 0.15),
                                             (o.0 + x + T.post / 2, o.1 + p.hFront), (o.0 + x - T.post / 2, o.1 + p.hFront)], closed: true)
        }
        for (a, b) in zip(xs, xs.dropFirst()) {
            let lo = o.1 + 0.25, hi = o.1 + p.hFront - 0.1
            T.member(&dxf, CADLayers.pvBrace, (o.0 + a + T.post, lo), (o.0 + b - T.post, hi), width: 0.04)
            T.member(&dxf, CADLayers.pvBrace, (o.0 + a + T.post, hi), (o.0 + b - T.post, lo), width: 0.04)
        }
    }

    /// The footing details beside the sections, at `scale` (5: 1:10 beside the 1:50 drawings), `o` their top-left:
    /// DETAIL CONCRETE TOPPING (the plan, 0.30 each way) and DETAIL 1 (the section: topping, base, expansion bolt M12),
    /// each with its dimensions (reading true metres) and labels.
    public func details(_ dxf: inout SketchDXF, origin o: (Double, Double), footing f: Double, scale k: Double = 5) {
        let h = 0.05 * k
        // the plan
        let pc = (o.0 + 0.15 * k + 0.6, o.1 - 0.15 * k - 0.9)
        insert(&dxf, "topping_plan", at: pc, scale: k)
        let a = (pc.0 - 0.15 * k, pc.1 + 0.15 * k), b = (pc.0 + 0.15 * k, pc.1 + 0.15 * k), cc = (pc.0 - 0.15 * k, pc.1 - 0.15 * k)
        dxf.dimension(CADLayers.dim, a, b, at: (0, a.1 + 0.4), vertical: false, text: String(format: "%.2f", 0.30), height: h)
        dxf.dimension(CADLayers.dim, cc, a, at: (a.0 - 0.4, 0), vertical: true, text: String(format: "%.2f", 0.30), height: h)
        dxf.text(CADLayers.text, (pc.0, pc.1 - 0.15 * k - 0.5), height: h * 1.2, "DETAIL CONCRETE TOPPING", align: .center)
        dxf.text(CADLayers.text, (pc.0, pc.1 - 0.15 * k - 0.5 - 1.8 * h), height: h * 0.8, "SCALE 1:10", align: .center)
        // the section
        let sc = (pc.0 + 0.15 * k + 2.4 + 0.22 * k, pc.1 - 0.15 * k)
        insert(&dxf, "topping_detail", at: sc, scale: k)
        let l0 = (sc.0 - 0.15 * k, sc.1), r0 = (sc.0 + 0.15 * k, sc.1), t0 = (sc.0 - 0.15 * k, sc.1 + 0.15 * k)
        dxf.dimension(CADLayers.dim, l0, r0, at: (0, sc.1 - 0.07 * k - 0.4), vertical: false, text: String(format: "%.2f", f), height: h)
        dxf.dimension(CADLayers.dim, l0, t0, at: (l0.0 - 0.4, 0), vertical: true, text: "0.15", height: h)
        let tags: [(String, (Double, Double))] = [("CONCRETE TOPPING %.0fx%.0fx150 mm.", (0.12, 0.10)), ("BASE: Aluminium Grade", (0.0, 0.06)),
                                                  ("EXPANSION BOLT M12", (0.0, -0.04))]
        for (i, (s, q)) in tags.enumerated() {
            let p0 = (sc.0 + q.0 * k, sc.1 + q.1 * k), lx = sc.0 + 0.3 * k + 0.4, ly = sc.1 + (0.22 - 0.12 * Double(i)) * k
            dxf.line(CADLayers.text, p0, (lx, ly)); dxf.line(CADLayers.text, (lx, ly), (lx + 0.3, ly))
            let words = s.contains("%") ? String(format: s, f * 1000, f * 1000) : s
            dxf.text(CADLayers.text, (lx + 0.4, ly), height: h, words, middle: true)
        }
        dxf.text(CADLayers.text, (sc.0, sc.1 - 0.07 * k - 1.1), height: h * 1.2, "DETAIL 1", align: .center)
        dxf.text(CADLayers.text, (sc.0, sc.1 - 0.07 * k - 1.1 - 1.8 * h), height: h * 0.8, "SCALE 1:10", align: .center)
    }
}
