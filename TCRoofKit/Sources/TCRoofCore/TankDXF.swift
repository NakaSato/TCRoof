import Foundation

/// D1 "ส่งออก DXF" (docs/specs/cad-export-dxf phase 3): the clear-water tank's roof plan (`TankPlan`) at real scale in
/// metres (`millimetres` for 1 unit = 1 mm), from the tank's top-left corner with Y up, with the printed sheet's beams, section marks, size and
/// volume summary and note (`details`), plus the sub-step 3 panel layout (`TankLayout.current`) when
/// there is one. Layer colours carry the meaning, so ops keep no colour of their own.
public enum TankDXF {
    /// The plan's tags → the team's standard layers (`CADLayers`).
    static let layers: [String: SketchDXF.Layer] = [
        "grid": CADLayers.grid, "out": CADLayers.tankOutline, "dim": CADLayers.dim, "dimtxt": CADLayers.dim,
        "obst": CADLayers.obstacle, "north": CADLayers.north, "txt": CADLayers.text,
        "beam": CADLayers.tankBeam, "sect": CADLayers.sectionMark,
    ]
    static let pv = CADLayers.pvModule, pvGroup = CADLayers.pvTable

    /// nil without spans (no `TankPlan`).
    public static func build(_ v: Values, millimetres: Bool = false) -> RoofDXF.Output? {
        guard let plan = TankPlan(v, details: true) else { return nil }
        let f = plan.frame, TH = TankPoints.tankSize(v)?.h ?? 0
        var o = SketchDXF.Options(); o.millimetres = millimetres
        o.dashes = true; o.textBoxes = true; o.hatches = true; o.outlineBoxes = true; o.skipFillOnly = true; o.centreText = false
        var dxf = SketchDXF(options: o)
        let tf: (Pt) -> (Double, Double) = { p in ((p.x - f.ox) / f.k, TH - (p.y - f.oy) / f.k) }
        // the span chains are DIMENSIONs, not their lines and texts
        let drawnDims: Set<String> = plan.dimensions.isEmpty ? [] : ["dim", "dimtxt"]
        dxf.add(plan.sketch.ops, layer: { i, _ in plan.tags[i].flatMap { drawnDims.contains($0) ? nil : layers[$0] } }, transform: tf, pointsPerMetre: f.k)
        dxf.add(plan.dimensions, layer: layers["dim"]!, transform: tf, pointsPerMetre: f.k)

        // the panel layout is in tank metres from the same corner (TankLayoutPlan draws it on the plan's frame)
        if let l = TankLayout.current(v) {
            func p(_ x: Double, _ y: Double) -> (Double, Double) { (x, TH - y) }
            for t in l.builtTables {
                dxf.polyline(pvGroup, [p(t.x, t.y), p(t.x + t.w, t.y), p(t.x + t.w, t.y + t.h), p(t.x, t.y + t.h)], closed: true)
                // each module an INSERT of one block per size on plan (its lower-left corner the base point)
                for q in t.panels where q.on {
                    let name = String(format: "PV_MODULE_%.0fx%.0f", q.w * 1000, q.h * 1000)
                    // a WIPEOUT under the outline hides the beams and grid the module covers, as on the printed plan
                    // with the team's PV panel block inside (TK_MODULE_PLAN, its cells), stretched to this module
                    let panel = TankComponents.shared.flatMap { c -> String? in c.define(&dxf); return TankComponents.names["module_plan"]?.block }
                    dxf.block(name) { d in
                        let r = [(0.0, 0.0), (q.w, 0), (q.w, q.h), (0, q.h)]
                        d.wipeout(pv, r)
                        if let panel {
                            d.insert(pv, panel, at: (0, 0), xScale: q.w / TankComponents.modulePlanDrawn.w, yScale: q.h / TankComponents.modulePlanDrawn.h)
                        } else {
                            d.polyline(pv, r, closed: true)
                        }
                    }
                    dxf.insert(pv, name, at: p(q.x, q.y + q.h))
                }
                for q in t.posts { dxf.circle(pvGroup, p(q.x, q.y), r: l.params.footing / 2) }
            }
        }
        // to the right of the plan: the mounting plan (the team's drawing: footings, rafters, rails, bracing, dimension chains)
        if let l = TankLayout.current(v) {
            let div = millimetres ? 1000.0 : 1, e = dxf.extents
            let dx = (e.max.x - e.min.x) / div + 6
            dxf.add(plan.sketch.ops, layer: { i, _ in plan.tags[i].flatMap { drawnDims.contains($0) ? nil : layers[$0] } },
                    transform: { q in let a = tf(q); return (a.0 + dx, a.1) }, pointsPerMetre: f.k)
            dxf.add(plan.dimensions, layer: layers["dim"]!, transform: { q in let a = tf(q); return (a.0 + dx, a.1) }, pointsPerMetre: f.k)
            mountingPlan(&dxf, l, dx: dx, TH: TH)
        }

        // under the plan, to scale and in metres: sections 1–1 and 2–2, then the module rows' section and the table's front
        // elevation, each with its zero (the tank's west wall, a row's front post, the table's west end) at x = 0
        let tables: [TankDrawings.SectionCAD] = [false, true].compactMap { TankDrawings.sectionCAD(v, across: $0) }
            + (TankLayout.current(v).map { [TankDrawings.tableSectionCAD($0.params)] + [TankDrawings.tableFrontCAD($0)].compactMap { $0 } } ?? [])
        let gap = 3.0
        var top = dxf.extents.min.y / (millimetres ? 1000 : 1) - gap
        // the rows' section and the front elevation take their footings, posts, braces and modules from the team's
        // components (each one block), the rest from the drawing
        let comps = TankComponents.shared, params = TankLayout.current(v)?.params
        for d in tables {
            let o = d.origin, k = d.k, h = d.sketch.height
            // the drawing's top edge at `top`; (origin) at (0, top - origin.y / k)
            let base = top - o.y / k
            let tf: (Pt) -> (Double, Double) = { p in ((p.x - o.x) / k, base + (o.y - p.y) / k) }
            let built = comps != nil && params != nil && d.role != .tank
            let skip = d.dimensionOps.union(built ? d.structureOps : [])
            dxf.add(d.sketch.ops, layer: { i, op in skip.contains(i) ? nil : sectionLayer(op) }, transform: tf, pointsPerMetre: k)
            dxf.add(d.dimensions, layer: CADLayers.dim, transform: tf, pointsPerMetre: k)
            if built, let comps, let params {
                if d.role == .rows { comps.rowSection(&dxf, params, origin: (0, base)) }
                if d.role == .front { comps.frontElevation(&dxf, params, posts: d.posts, origin: (0, base)) }
            }
            // the posts' grid bubbles under the drawing's lowest dimension, as on the mounting plan
            if let l = TankLayout.current(v), d.role != .tank {
                let g = TankMountGrid(l), r = 9 / k
                let lowest = d.dimensions.map { base + (o.y - $0.at.y) / k }.min() ?? base - 1
                let y = min(lowest, base) - 2.4 * r
                var marks: [(Double, String)] = []
                if d.role == .rows, let p = params {
                    for (i, row) in g.rows.prefix(2).enumerated() {
                        let x0 = Double(i) * p.rowPitch
                        if let f = g.letter(atW: row.front) { marks.append((x0, f)) }
                        if let b = g.letter(atW: row.back) { marks.append((x0 + p.postDY, b)) }
                    }
                }
                if d.role == .front, let t = l.builtTables.max(by: { $0.columns < $1.columns }) {
                    let fr = TankLayout.Frame(q: l.turn, W: l.size.w, H: l.size.h)
                    let a = t.panels.flatMap { [fr.to($0.x, $0.y).0, fr.to($0.x + $0.w, $0.y + $0.h).0] }.min() ?? 0
                    for x in d.posts { if let n = g.number(row: t.row, u: a + x) { marks.append((x, "\(n)")) } }
                }
                for (x, name) in marks {
                    dxf.line(CADLayers.grid, (x, base), (x, y + r))
                    bubble(&dxf, (x, y), r: r, name)
                }
            }
            top = base + (o.y - h) / k - gap
        }
        // under them, the footing details (plan and DETAIL 1) at 1:10
        if let comps, let params { comps.details(&dxf, origin: (0, top), footing: params.footing) }
        return dxf.output
    }

    /// The post base the team draws at every post (their mounting plan's block): the footing square, the base plate and
    /// the C post's flanges and the two 50 mm plates, centred on the post (metres, rows along x).
    static func footingBlock(_ dxf: inout SketchDXF, footing f: Double) -> String {
        // with the team's components: the topping square and their base plate block (TK_BASE_PLAN) inside it
        if let comps = TankComponents.shared, let base = TankComponents.names["base_plan"] {
            comps.define(&dxf)
            return dxf.block(String(format: "TC_FOOTING_%.0f", f * 1000)) { d in
                d.polyline(CADLayers.pvFooting, [(-f / 2, -f / 2), (f / 2, -f / 2), (f / 2, f / 2), (-f / 2, f / 2)], closed: true)
                d.insert(base.layer, base.block, at: (0, 0))
            }
        }
        return dxf.block(String(format: "TC_FOOTING_%.0f", f * 1000)) { d in
            let l = CADLayers.pvFooting
            func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) { d.polyline(l, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], closed: true) }
            rect(-f / 2, -f / 2, f / 2, f / 2)
            d.polyline(l, [(0.0748, 0.0415), (0.0601, 0.0562), (-0.0601, 0.0562), (-0.0748, 0.0415),
                           (-0.0748, -0.0415), (-0.0601, -0.0562), (0.0601, -0.0562), (0.0748, -0.0415)], closed: true)
            rect(0.0503, -0.0244, 0.064, 0.0244); rect(-0.064, -0.0244, -0.0503, 0.0244)
            rect(-0.025, 0.0062, 0.025, 0.0562); rect(-0.025, -0.0562, 0.025, -0.0062)
        }
    }

    /// The mounting plan beside the module plan, `dx` metres to the right (docs/specs/cad-export-dxf, Tank mounting plan):
    /// per table the rafters (50 mm members up the slope at each post pair), the four rails and the bracing between
    /// posts along the front and back lines, each on a WIPEOUT, the footing block at every post, a dimension chain along
    /// each table (cantilever, bays, cantilever) beyond its low edge, and one across the post lines from wall to wall.
    static func mountingPlan(_ dxf: inout SketchDXF, _ l: TankLayout, dx: Double, TH: Double) {
        let p = l.params, fr = TankLayout.Frame(q: l.turn, W: l.size.w, H: l.size.h)
        func at(_ q: Pt) -> (Double, Double) { (dx + q.x, TH - q.y) }
        func plan(_ u: Double, _ w: Double) -> (Double, Double) { let q = fr.from(u, w); return at(Pt(q.0, q.1)) }
        /// A member `width` wide along a → b (DXF metres), on a WIPEOUT.
        func member(_ layer: SketchDXF.Layer, _ a: (Double, Double), _ b: (Double, Double), width: Double) {
            let L = hypot(b.0 - a.0, b.1 - a.1)
            guard L > 1e-6 else { return }
            let nx = -(b.1 - a.1) / L * width / 2, ny = (b.0 - a.0) / L * width / 2
            let pts = [(a.0 + nx, a.1 + ny), (b.0 + nx, b.1 + ny), (b.0 - nx, b.1 - ny), (a.0 - nx, a.1 - ny)]
            dxf.wipeout(layer, pts)
            dxf.polyline(layer, pts, closed: true)
        }
        let footing = footingBlock(&dxf, footing: p.footing), turn = l.turn % 2 == 1 ? 90.0 : 0
        var lines: Set<Int> = []   // the post lines across the slope, in mm of the layout frame
        for t in l.builtTables {
            let s = l.structure(t)
            for r in s.rafters { member(CADLayers.pvRafter, at(r.0), at(r.1), width: 0.05) }
            for r in s.rails { member(CADLayers.pvRail, at(r.0), at(r.1), width: 0.05) }
            // bracing between neighbouring pairs, front line and back line
            let front = stride(from: 0, to: t.posts.count, by: 2).map { t.posts[$0] }, back = stride(from: 1, to: t.posts.count, by: 2).map { t.posts[$0] }
            for line in [front, back] { for (a, b) in zip(line, line.dropFirst()) { member(CADLayers.pvBrace, at(a), at(b), width: 0.04) } }
            for q in t.posts { dxf.insert(CADLayers.pvFooting, footing, at: at(q), rotation: turn) }
            // the chain along the table, beyond its low edge: from its west end over each post pair to its east end
            let b = fr.rect(TankPoints.Rect(x: t.x, y: t.y, w: t.w, h: t.h))
            let us = [b.x] + front.map { fr.to($0.x, $0.y).0 } + [b.x + b.w]
            let edge = b.y + b.h, line = edge + 0.6
            for (u0, u1) in zip(us, us.dropFirst()) where u1 - u0 > 1e-6 {
                let a = plan(u0, edge), c = plan(u1, edge), o = plan(0, line)
                dxf.dimension(CADLayers.dim, a, c, at: o, vertical: l.turn % 2 == 1, text: String(format: "%.2f", u1 - u0), height: 0.24)
            }
            for q in front + back { lines.insert(Int((fr.to(q.x, q.y).1 * 1000).rounded())) }
        }
        // across the post lines, left of the tank in the layout's frame: wall, each post line, wall
        let ws = [0.0] + lines.sorted().map { Double($0) / 1000 } + [fr.fh]
        for (w0, w1) in zip(ws, ws.dropFirst()) where w1 - w0 > 1e-6 {
            dxf.dimension(CADLayers.dim, plan(0, w0), plan(0, w1), at: plan(-1.6, 0), vertical: l.turn % 2 == 0,
                          text: String(format: "%.2f", w1 - w0), height: 0.24)
        }
        mountGrid(&dxf, l, TankMountGrid(l), at: at)
        dxf.text(CADLayers.text, at(Pt(0, -2.2)), height: 0.5, "แปลนฐานรากและโครงยึดแผง / Mounting plan")
    }

    /// A section's op → its standard layer by colour: concrete and outlines on S-TANK-SECT-E, soil on C-TOPO-E,
    /// modules, posts and bracing on the PV layers, vents as obstacles, words on G-ANNO-TEXT; nil for the white background,
    /// the module joints and translucent tints.
    static func sectionLayer(_ op: DrawOp) -> SketchDXF.Layer? {
        func same(_ a: RGBA?, _ b: RGBA) -> Bool { a.map { abs($0.r - b.r) + abs($0.g - b.g) + abs($0.b - b.b) < 0.01 } ?? false }
        switch op {
        case .text, .textBox, .runs: return CADLayers.text
        case let .rect(_, nil, f, _), let .polygon(_, nil, f, _): if (f?.a ?? 0) < 1 || f == .white { return nil }
        case let .line(_, _, _, c, _) where c == .white: return nil
        default: break
        }
        let c = SketchDXF.colour(op)
        if same(c, TankDrawings.soil) { return CADLayers.tankSoil }
        if same(c, TankDrawings.panel) || (c.map { $0.r > 0.97 && $0.g > 0.97 && $0.b > 0.97 } ?? false) { return CADLayers.pvModule }
        if same(c, TankDrawings.post) { return CADLayers.pvTable }
        if same(c, TankDrawings.vent) { return CADLayers.obstacle }
        if same(c, TankDrawings.dim) { return CADLayers.dim }
        if same(c, RGBA(hex: 0x94A3B8)) { return CADLayers.pvRail }
        return CADLayers.tankSection
    }
}
