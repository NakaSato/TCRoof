import Foundation

/// D1 "ส่งออก DXF" (docs/specs/cad-export-dxf phase 3): the clear-water tank's roof plan (`TankPlan`) at real scale in
/// metres (`millimetres` for 1 unit = 1 mm), from the tank's top-left corner with Y up, with the printed sheet's beams, size and
/// volume summary and note (`details`), plus the sub-step 3 panel layout (`TankLayout.current`) when
/// there is one. Layer colours carry the meaning, so ops keep no colour of their own.
public enum TankDXF {
    /// The plan's tags → the team's standard layers (`CADLayers`).
    static let layers: [String: SketchDXF.Layer] = [
        "grid": CADLayers.grid, "out": CADLayers.tankOutline, "dim": CADLayers.dim, "dimtxt": CADLayers.dim,
        "obst": CADLayers.obstacle, "north": CADLayers.north, "txt": CADLayers.text,
        "beam": CADLayers.tankBeam,
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
        // the span chains are DIMENSIONs, not their lines and texts; the 1–1 / 2–2 cut marks are left out with the
        // tank sections they point to (the PDF keeps both)
        var drawnDims: Set<String> = plan.dimensions.isEmpty ? ["sect"] : ["dim", "dimtxt", "sect"]
        // the team's north arrow block where the sketch draws its own, at the same size
        if NorthArrow.shared != nil, let az = Tank.azimuth(v) {
            drawnDims.insert("north")
            NorthArrow.place(&dxf, at: tf(Pt(plan.sketch.width - 24, 36)), north: Double(az), radius: 12 / f.k)
        }
        dxf.add(plan.sketch.ops, layer: { i, _ in plan.tags[i].flatMap { drawnDims.contains($0) ? nil : layers[$0] } }, transform: tf, pointsPerMetre: f.k)
        dxf.add(plan.dimensions, layer: layers["dim"]!, transform: tf, pointsPerMetre: f.k)

        // the panel layout is in tank metres from the same corner (TankLayoutPlan draws it on the plan's frame)
        if let l = TankLayout.current(v) {
            func p(_ x: Double, _ y: Double) -> (Double, Double) { (x, TH - y) }
            let m = moduleBlock(&dxf, l.params)
            for t in l.builtTables {
                dxf.polyline(pvGroup, [p(t.x, t.y), p(t.x + t.w, t.y), p(t.x + t.w, t.y + t.h), p(t.x, t.y + t.h)], closed: true)
                // each module an INSERT of the team's module block (`moduleBlock`), turned where the slope runs up the plan
                for q in t.panels where q.on {
                    let (a, b) = (p(q.x, q.y + q.h), p(q.x + q.w, q.y + q.h))
                    if abs(q.w - m.length) < 1e-3 && abs(q.h - m.width) < 1e-3 {
                        dxf.insert(pv, m.name, at: a)
                    } else if abs(q.h - m.length) < 1e-3 && abs(q.w - m.width) < 1e-3 {
                        dxf.insert(pv, m.name, at: b, rotation: 90)
                    } else {
                        // a module of another size (none today): a frame on its WIPEOUT of its own size
                        let name = dxf.block(String(format: "PV_MODULE_%.0fx%.0f", q.w * 1000, q.h * 1000)) { d in
                            let r = [(0.0, 0.0), (q.w, 0), (q.w, q.h), (0, q.h)]
                            d.wipeout(pv, r); d.polyline(pv, r, closed: true)
                        }
                        dxf.insert(pv, name, at: a)
                    }
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

        // to the right of the plans: the roof beam plan (B1 / B2 on the grid) and its schedule, line A level with the plan's
        do {
            let e = dxf.extents
            TankFraming.draw(&dxf, v, origin: (e.max.x / (millimetres ? 1000 : 1) + 10, TH))
        }
        // under the plan, to scale and in metres: the module rows' section and the back post line's elevation, each with
        // its zero (a row's front line, the table's west end) at x = 0. The tank's own sections 1–1 and 2–2 stay in the
        // PDF only.
        let tables: [TankDrawings.SectionCAD] =
            TankLayout.current(v).map { [TankDrawings.tableSectionCAD($0.params)] + [TankDrawings.tableFrontCAD($0)].compactMap { $0 } } ?? []
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

    /// The module on plan as the team's `PV_570W.dxf` (reference/) draws it: one block `PV_<W>W` (`PV_570W`), a frame on
    /// a WIPEOUT that hides the beams and grid under it, its lower-left corner the base point, the slope along x. Its
    /// size is the layout's module projected on plan: the length down the slope times cos(tilt) by the width (2.278 m
    /// at 15° → 2.200 × 1.134, the team's block 2.199 × 1.134), so a module's block measures what it covers on the
    /// roof.
    static func moduleBlock(_ dxf: inout SketchDXF, _ p: TankLayout.Params) -> (name: String, length: Double, width: Double) {
        let L = p.cellH, W = p.cellW
        let name = dxf.block(String(format: "PV_%.0fW", p.moduleKW * 1000)) { d in
            // to a micrometre, so the frame measures the module exactly
            d.fine = true
            let r = [(0.0, 0.0), (L, 0), (L, W), (0, W)]
            d.wipeout(pv, r)
            d.polyline(pv, r, closed: true)
            d.fine = false
        }
        return (name, L, W)
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
    /// per table the rafters (50 mm members up the slope at each post pair), the four rails and the X braces on the
    /// back post line in every other bay and the last (`TankLayout.bracedBays`), each on a WIPEOUT, the footing block at every post, a dimension chain along
    /// each table (cantilever, bays, cantilever) beyond its low edge, and one across the post lines from wall to wall.
    /// The two members of an X brace on plan, centre to centre (the team's `Top.dxf`).
    static let braceGap = 0.152

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
            // the X braces on the back (high) line in the bays the team braces, each X seen from above as the team's
            // pair of members 40 mm wide, 152 mm apart either side of the post line
            let front = stride(from: 0, to: t.posts.count, by: 2).map { t.posts[$0] }, back = stride(from: 1, to: t.posts.count, by: 2).map { t.posts[$0] }
            for i in TankLayout.bracedBays(max(0, back.count - 1)) {
                let a = at(back[i]), b = at(back[i + 1]), L = hypot(b.0 - a.0, b.1 - a.1)
                guard L > 1e-6 else { continue }
                let n = (-(b.1 - a.1) / L * braceGap / 2, (b.0 - a.0) / L * braceGap / 2)
                for side in [1.0, -1.0] {
                    member(CADLayers.pvBrace, (a.0 + side * n.0, a.1 + side * n.1), (b.0 + side * n.0, b.1 + side * n.1), width: 0.04)
                }
            }
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
        let g = TankMountGrid(l)
        mountGrid(&dxf, l, g, at: at)
        footingSchedule(&dxf, l, g, at: (dx + l.size.w + 2.5, TH))
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
