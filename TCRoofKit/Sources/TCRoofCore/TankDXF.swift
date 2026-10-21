import Foundation

/// D1 "ส่งออก DXF" (docs/specs/cad-export-dxf phase 3): the clear-water tank's roof plan (`TankPlan`) at real scale in
/// millimetres, from the tank's top-left corner with Y up, with the printed sheet's beams, section marks, size and
/// volume summary and note (`details`), plus the sub-step 3 panel layout (`TankLayout.current`) when
/// there is one. Layer colours carry the meaning, so ops keep no colour of their own.
public enum TankDXF {
    static let layers: [String: SketchDXF.Layer] = [
        "grid": .init("GRID", aci: 8), "out": .init("OUTLINE", aci: 7), "dim": .init("DIM", aci: 3), "dimtxt": .init("DIM", aci: 3),
        "obst": .init("OBSTACLE", aci: 1), "north": .init("NORTH", aci: 7), "txt": .init("TEXT", aci: 7),
        "beam": .init("BEAM", aci: 8), "sect": .init("SECTION_MARK", aci: 5),
    ]
    static let pv = SketchDXF.Layer("PV", aci: 150), pvGroup = SketchDXF.Layer("PV_GROUP", aci: 170)

    /// nil without spans (no `TankPlan`).
    public static func build(_ v: Values) -> RoofDXF.Output? {
        guard let plan = TankPlan(v, details: true) else { return nil }
        let f = plan.frame, TH = TankPoints.tankSize(v)?.h ?? 0
        var o = SketchDXF.Options()
        o.dashes = true; o.textBoxes = true; o.hatches = true; o.outlineBoxes = true; o.skipFillOnly = true; o.centreText = false
        var dxf = SketchDXF(options: o)
        dxf.add(plan.sketch.ops, layer: { i, _ in plan.tags[i].flatMap { layers[$0] } },
                transform: { p in ((p.x - f.ox) / f.k, TH - (p.y - f.oy) / f.k) }, pointsPerMetre: f.k)

        // the panel layout is in tank metres from the same corner (TankLayoutPlan draws it on the plan's frame)
        if let l = TankLayout.current(v) {
            func p(_ x: Double, _ y: Double) -> (Double, Double) { (x, TH - y) }
            func box(_ layer: SketchDXF.Layer, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
                let c = [p(x, y), p(x + w, y), p(x + w, y + h), p(x, y + h)]
                for i in 0..<4 { dxf.line(layer, c[i], c[(i + 1) % 4]) }
            }
            for t in l.builtTables {
                box(pvGroup, t.x, t.y, t.w, t.h)
                for q in t.panels where q.on { box(pv, q.x, q.y, q.w, q.h) }
                for q in t.posts { dxf.circle(pvGroup, p(q.x, q.y), r: l.params.footing / 2) }
            }
        }
        return dxf.output
    }
}
