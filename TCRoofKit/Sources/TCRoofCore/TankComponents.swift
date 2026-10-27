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

    /// The team's concrete hatch (AR-CONC) as their topping detail stores it, for any section that cuts concrete.
    public static var concrete: [SketchDXF.PatternLine]? {
        guard let h = shared?.components.values.flatMap(\.hatches).first(where: { $0.pattern == "AR-CONC" }) else { return nil }
        return h.lines.map { .init(angle: $0.angle, base: ($0.base[0], $0.base[1]), offset: ($0.offset[0], $0.offset[1]), dashes: $0.dashes) }
    }

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
    /// where the struts meet the rafter (m along it from the front line / the back post), measured on the team's
    /// section 1 (and `Side_View.dxf`'s nodes 1.40 / 1.00 / 1.10): the V's inner leg 0.565 m up from the front line,
    /// the back diagonal 1.40 m down from the post, the V's outer leg 0.60 m down past the front line.
    public static let post = 0.05, rafter = 0.075, brace = 0.045, braceFront = 0.565, braceBack = 1.40, strutReach = 0.60
    /// The rafter past the front (low) line and past the back (high) post, along it: 0.82 + 2.90 + 0.28 = 4.00 m on the
    /// team's section; kept 0.05 m inside the modules where a layout's modules end sooner.
    public static let rafterFront = 0.82, rafterBack = 0.28
    /// The module drawing's own length: the block is stretched along the slope to the layout's module.
    public static let moduleDrawn = 2.28
    /// The X bracing on the back post line between the team's nodes (`Back_Side.dxf`): 0.376 m above the slab and
    /// 0.108 m under the post's top (1.890 on their 1.998 m post).
    public static let xLow = 0.376, xBelowTop = 0.108
    public static func xHigh(_ p: TankLayout.Params) -> Double { max(xLow + 0.2, p.hBack - xBelowTop) }

    /// The team's frame (reference/tank-roof `Side_View.dxf`, section 1): one vertical post on the back (high) line;
    /// on the front (low) line one foot carrying a V of two struts, its inner leg to the rafter `braceFront` up the slope
    /// and its outer leg `strutReach` down it; a diagonal from the back post's foot to the rafter `braceBack` down from
    /// the post. Distances along the rafter's underside from where it passes over the front line (up the slope +), with
    /// the rafter's own ends, kept 0.05 m inside the modules where a layout's modules end sooner.
    public struct Frame: Sendable {
        public var rafter: (Double, Double)
        public var inner, outer, back: Double
    }
    public static func frame(_ p: TankLayout.Params) -> Frame {
        let along = p.postDY / cos(p.tilt * .pi / 180)
        let lowEdge = -p.frontOver, highEdge = lowEdge + 2 * p.moduleL + p.moduleGap
        let r0 = max(-rafterFront, lowEdge + 0.05), r1 = min(along + rafterBack, highEdge - 0.05)
        return Frame(rafter: (r0, r1), inner: braceFront, outer: max(-strutReach, r0 + 0.05), back: along - braceBack)
    }

    /// Defines every component's block once (an identical body is reused), or only those of `only`, and returns the
    /// names.
    @discardableResult
    public func define(_ dxf: inout SketchDXF, only: Set<String>? = nil) -> [String: String] {
        var out: [String: String] = [:]
        for (id, c) in components.sorted(by: { $0.key < $1.key }) where only?.contains(id) ?? true {
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

    /// The module rows' section from the components (the tank DXF's row section), `o` the first row's front line at
    /// the roof, as the team's frame (`frame`): on both lines the concrete topping, the side base and the M12; the back
    /// post up to the rafter; the rafter along the tilt; the front foot's V of two struts and the back diagonal; and the
    /// two modules with their rail clamps on the rafter.
    public func rowSection(_ dxf: inout SketchDXF, _ p: TankLayout.Params, origin o: (Double, Double)) {
        let t = p.tilt * .pi / 180, c = cos(t), s = sin(t), T = Self.self, f = T.frame(p)
        for row in 0..<2 {
            let x0 = o.0 + Double(row) * p.rowPitch
            // the rafter's underside runs through the post tops
            let top = (x0, o.1 + p.hFront)
            func under(_ d: Double) -> (Double, Double) { (top.0 + d * c, top.1 + d * s) }
            func over(_ d: Double) -> (Double, Double) { let q = under(d); return (q.0 - T.rafter * s, q.1 + T.rafter * c) }
            let xb = x0 + p.postDY
            for x in [x0, xb] {
                insert(&dxf, "topping", at: (x, o.1))
                insert(&dxf, "base_side", at: (x, o.1))
                insert(&dxf, "anchor_m12", at: (x, o.1))
            }
            dxf.polyline(CADLayers.pvTable, [(xb - T.post / 2, o.1 + 0.15), (xb + T.post / 2, o.1 + 0.15), (xb + T.post / 2, o.1 + p.hBack),
                                             (xb - T.post / 2, o.1 + p.hBack)], closed: true)
            dxf.polyline(CADLayers.pvRafter, [under(f.rafter.0), under(f.rafter.1), over(f.rafter.1), over(f.rafter.0)], closed: true)
            // the V from the one front foot (no post there), and the back diagonal from the post's foot
            T.member(&dxf, CADLayers.pvBrace, (x0 + T.brace / 2, o.1 + 0.15), under(f.inner), width: T.brace)
            T.member(&dxf, CADLayers.pvBrace, (x0 - T.brace / 2, o.1 + 0.15), under(f.outer), width: T.brace)
            T.member(&dxf, CADLayers.pvBrace, (xb - T.post, o.1 + 0.15), under(f.back), width: T.brace)
            // the two modules up the slope, each stretched to the layout's module length
            for m in 0..<2 {
                let d = -p.frontOver + Double(m) * (p.moduleL + p.moduleGap)
                insert(&dxf, "module_side", at: over(d), rotation: p.tilt, xScale: p.moduleL / T.moduleDrawn)
            }
        }
    }

    /// The table's back post line elevation from the components, `o` its west end at the roof and `xs` its post pairs
    /// along it: per post the topping and the front view of its base (AG2-B02) on the slab and the back post up to its
    /// top, and the X bracing as members in the bays the team braces (`TankLayout.bracedBays`), between their nodes.
    public func frontElevation(_ dxf: inout SketchDXF, _ p: TankLayout.Params, posts xs: [Double], origin o: (Double, Double)) {
        let T = Self.self
        for x in xs {
            insert(&dxf, "topping", at: (o.0 + x, o.1))
            insert(&dxf, "base_front", at: (o.0 + x, o.1))
            dxf.polyline(CADLayers.pvTable, [(o.0 + x - T.post / 2, o.1 + 0.15), (o.0 + x + T.post / 2, o.1 + 0.15),
                                             (o.0 + x + T.post / 2, o.1 + p.hBack), (o.0 + x - T.post / 2, o.1 + p.hBack)], closed: true)
        }
        for i in TankLayout.bracedBays(max(0, xs.count - 1)) {
            let a = xs[i], b = xs[i + 1]
            let lo = o.1 + T.xLow, hi = o.1 + T.xHigh(p)
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
