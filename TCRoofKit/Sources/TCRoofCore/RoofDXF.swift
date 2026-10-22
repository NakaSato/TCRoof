import Foundation

/// C1 "ส่งออก CAD" (docs/ui/survey-c1 `cadBuild`): the roof plan, section A-A, member table and PV layout as a plain
/// DXF R2000 drawing (LINE / CIRCLE / TEXT on named layers) that any CAD program opens. Coordinates are metres from the
/// plan's bottom-left corner, written in metres (1 unit = 1 m, the default) or millimetres; the section sits under the plan and the table to
/// its right. Thai text is written in TIS-620 (`$DWGCODEPAGE` ANSI_874).
public enum RoofDXF {
    public enum Part: String, CaseIterable, Sendable { case plan, section, table, pv }

    public struct Output: Sendable {
        public let data: Data
        /// Entities written, and the layers they use in order of first use.
        public let entities: Int
        public let layers: [String]
    }

    /// The design's layer keys (`LY`) → the team's standard layers (`CADLayers`).
    public static let standard: [String: SketchDXF.Layer] = [
        "GRID": CADLayers.grid, "OUTLINE": CADLayers.roofOutline, "RIDGE": CADLayers.roofRidge, "TRUSS": CADLayers.roofTruss,
        "POST": CADLayers.roofPost, "PURLIN": CADLayers.roofPurlin, "SKYLIGHT": CADLayers.roofSkylight, "OBSTACLE": CADLayers.obstacle,
        "SECTION_MARK": CADLayers.sectionMark, "DIM": CADLayers.dim, "TEXT": CADLayers.text, "PV": CADLayers.pvModule,
        "PV_RAIL": CADLayers.pvRail, "PV_FOOT": CADLayers.pvFoot, "PV_CUT": CADLayers.pvCut, "KEEPOUT": CADLayers.pvKeepout,
        "SECTION": CADLayers.roofSection, "TABLE": CADLayers.roofTable,
    ]
    static func layer(_ key: String) -> SketchDXF.Layer { standard[key] ?? CADLayers.text }
    /// The plan's path keys (`RoofPlan.tags`) → layers.
    static let planLayers: [String: String] = ["grid": "GRID", "bub": "GRID", "out": "OUTLINE", "ridge": "RIDGE", "tbd": "TRUSS",
                                               "truss": "TRUSS", "t2": "TRUSS", "raft": "TRUSS", "eave": "TRUSS", "post": "POST",
                                               "purl": "PURLIN", "sky": "SKYLIGHT", "obst": "OBSTACLE", "sec": "SECTION_MARK", "dim": "DIM",
                                               "txt": "TEXT", "dimtxt": "DIM"]
    static let pvLayers: [String: String] = ["pv": "PV", "rail": "PV_RAIL", "foot": "PV_FOOT", "cut": "PV_CUT", "kz": "KEEPOUT"]

    /// One walkway band on plan (metres, y up from the plan's bottom edge `ly`) as the team's top view draws it: the cross
    /// rails every 1.20 m under the whole band, the cable tray dotted, the grating panels cross-hatched with their inner frame, both on WIPEOUTs, the PPR pipe, the rail
    /// solid, the L-feet, the wire-rope lifeline with its supports, the band's width and a tag.
    static func walkway(_ dxf: inout SketchDXF, _ w: RoofWalkway, ly: Double, text h: Double) {
        func at(_ a: Double, _ v: Double) -> (Double, Double) { let p = w.plan(a, v); return (p.x, ly - p.y) }
        func box(_ a0: Double, _ a1: Double, _ v0: Double, _ v1: Double) -> [(Double, Double)] { [at(a0, v0), at(a1, v0), at(a1, v1), at(a0, v1)] }
        typealias W = RoofWalkway
        // the cross rails under the whole band (the tray and the grating cover them): a hat section, grey
        for v in w.feet {
            let r = W.railWidth / 2
            dxf.polyline(CADLayers.walkRail, box(0, W.band, v - r, v + r), closed: true)
            for d in [-r / 3, r / 3] { dxf.line(CADLayers.walkRail, at(0, v + d), at(W.band, v + d)) }
        }
        let tray = box(W.tray.0, W.tray.1, w.v0, w.v1)
        dxf.wipeout(CADLayers.pvCableTray, tray); dxf.polyline(CADLayers.pvCableTray, tray, closed: true)
        dxf.dotsHatch(CADLayers.pvCableTray, tray, spacing: 0.05, aci: CADLayers.pvCableTray.aci)
        for (a, b) in w.panels {
            let outer = box(W.grating.0, W.grating.1, a, b)
            dxf.wipeout(CADLayers.pvWalkway, outer); dxf.polyline(CADLayers.pvWalkway, outer, closed: true)
            let f = min(W.gratingFrame, (b - a) / 4)
            let inner = box(W.grating.0 + f, W.grating.1 - f, a + f, b - f)
            dxf.polyline(CADLayers.pvWalkway, inner, closed: true)
            dxf.crossHatch(CADLayers.pvWalkway, inner, spacing: 0.025, aci: CADLayers.pvWalkway.aci)
        }
        dxf.line(CADLayers.pvCableTray, at(W.pipe, w.v0), at(W.pipe, w.v1))
        dxf.solid(CADLayers.lifeRail, box(W.rail.0, W.rail.1, w.v0, w.v1))
        for v in w.feet {
            for a in [W.grating.0 + 0.014, W.grating.1 - 0.014] {
                dxf.polyline(CADLayers.walkFoot, box(a - 0.02, a + 0.02, v - 0.02, v + 0.02), closed: true)
            }
        }
        dxf.line(CADLayers.pvLifeline, at(W.lifeline, w.v0), at(W.lifeline, w.v1))
        for v in w.supports {
            dxf.polyline(CADLayers.lifeSupport, box(W.lifeline - 0.02, W.lifeline + 0.02, v - 0.02, v + 0.02), closed: true)
        }
        // the band's width across the walkway's free end (its start, or its end when the ridge access is at the start),
        // when the gap runs along a plan axis
        let ridgeAccess = w.ridge && w.access, tail = ridgeAccess && w.accessAtStart ? w.v1 : w.v0
        let out: Double = ridgeAccess && w.accessAtStart ? 1 : -1
        let a = at(0, tail), b = at(W.band, tail), up = at(0, tail - out)
        let across = (b.0 - a.0, b.1 - a.1), along = (up.0 - a.0, up.1 - a.1)
        let back = (w.access && !w.ridge ? W.ladderOut + 0.4 : 0.5) / max(1e-9, hypot(along.0, along.1))
        let o = (a.0 - along.0 * back, a.1 - along.1 * back)
        if w.ridge || !w.access, abs(across.1) < 1e-6 || abs(across.0) < 1e-6 {
            dxf.dimension(CADLayers.dim, a, b, at: o, vertical: abs(across.0) < 1e-6, text: String(format: "%.2f", W.band), height: h)
        }
        // a short tag beyond that end, reading left to right across the walkway (the detail sheet has the rest)
        var angle = atan2(across.1, across.0) * 180 / .pi
        if angle > 90 { angle -= 180 } else if angle <= -90 { angle += 180 }
        guard w.access, !w.ridge else {
            dxf.text(CADLayers.text, at(W.band / 2, tail + out * 0.9), height: h, W.tag, align: .center, middle: true, angle: angle)
            if ridgeAccess { ridgeAccessLadder(&dxf, w, ly: ly, text: h) }
            return
        }
        // the way up, one side only: a cat ladder under the grating out past the eave, its rungs, an UP arrow and the tag
        let c = (W.grating.0 + W.grating.1) / 2, l0 = c - W.ladderWidth / 2, l1 = c + W.ladderWidth / 2, foot = w.v0 - W.ladderOut
        dxf.wipeout(CADLayers.pvAccess, box(l0, l1, foot, w.v0))
        for x in [l0, l1] { dxf.polyline(CADLayers.pvAccess, box(x - 0.025, x + 0.025, foot, w.v0), closed: true) }
        for v in stride(from: foot + W.rung / 2, to: w.v0, by: W.rung) { dxf.line(CADLayers.pvAccess, at(l0 + 0.025, v), at(l1 - 0.025, v)) }
        let tip = w.v0 + 0.6
        dxf.line(CADLayers.pvAccess, at(c, foot + 0.15), at(c, tip))
        dxf.polyline(CADLayers.pvAccess, [at(c - 0.08, tip - 0.2), at(c, tip), at(c + 0.08, tip - 0.2)])
        dxf.text(CADLayers.pvAccess, at(c, foot - 0.15), height: h, "UP", align: .center, middle: true, angle: angle)
        // the tag beside the ladder on its right-hand (or upper) side on plan, two lines, the first one away from the roof
        let mid = (foot + w.v0) / 2, l = at(-0.25, mid), r = at(W.band + 0.25, mid)
        let side = (abs(r.0 - l.0) > abs(r.1 - l.1) ? r.0 > l.0 : r.1 > l.1) ? W.band + 0.25 : -0.25
        let outward = at(side, foot).1 - at(side, w.v0).1, first = outward > 0 ? foot + 0.6 * h : foot + 1.4 * h
        dxf.text(CADLayers.text, at(side, first), height: h, W.accessTag, align: .left, middle: true)
        dxf.text(CADLayers.text, at(side, outward > 0 ? first + 1.6 * h : first - 1.6 * h), height: h, W.accessNote, align: .left, middle: true)
    }

    /// The team's roof access top view as a block, in metres: the gable wall at the origin, the roof up +y. Below the wall
    /// the cat ladder's stiles 0.60 m apart and its cage (two lines each side and a semicircle R 0.30 / 0.31) 0.90 m out
    /// with its brackets; above it the landing grating 0.60 × 0.98 m, framed 0.05 m and cross-hatched, the stile posts at
    /// the wall and the top rungs.
    static func accessBlock(_ dxf: inout SketchDXF) -> String {
        dxf.block("TC_ROOF_ACCESS") { d in
            typealias W = RoofWalkway
            let l = CADLayers.pvAccess, r = W.cageRadius, x = W.gableLadder / 2, c = -(W.cageOut - r - 0.015)
            func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) { d.polyline(l, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], closed: true) }
            // the cage: straight sides from the wall down to the hoop's centre, then the semicircle, inner and outer
            for rr in [r, r + 0.01] {
                let arc = (0...24).map { i -> (Double, Double) in let t = Double.pi + Double(i) / 24 * .pi; return (rr * cos(t), c + rr * sin(t)) }
                d.polyline(l, [(-rr, 0)] + arc + [(rr, 0)])
            }
            // its brackets on the sides and at the bottom
            rect(-x - 0.018, c - 0.245, -x - 0.01, c - 0.295 + 0.1); rect(x + 0.01, c - 0.245, x + 0.018, c - 0.295 + 0.1)
            rect(-0.025, c - r - 0.02, 0.025, c - r - 0.01)
            // the stiles' posts at the wall and the top rungs between them
            rect(-x, -0.05, -x + 0.052, 0); rect(x - 0.052, -0.05, x, 0)
            d.line(l, (-x + 0.052, -0.013), (x - 0.052, -0.013)); d.line(l, (-x + 0.052, -0.038), (x - 0.052, -0.038))
            // the landing grating on the roof
            let f = W.landingFrame, outer = [(-x, 0.0), (x, 0.0), (x, W.landing), (-x, W.landing)]
            let inner = [(-x + f, f), (x - f, f), (x - f, W.landing - f), (-x + f, W.landing - f)]
            d.wipeout(l, outer); d.polyline(l, outer, closed: true); d.polyline(l, inner, closed: true)
            d.crossHatch(l, inner, spacing: 0.05, aci: l.aci)
        }
    }

    /// The ridge walkway's way up, one side only: the access block at the gable wall on the ridge, turned so the
    /// landing lies along the walkway, and its tag outside the wall.
    static func ridgeAccessLadder(_ dxf: inout SketchDXF, _ w: RoofWalkway, ly: Double, text h: Double) {
        typealias W = RoofWalkway
        func at(_ a: Double, _ s: Double) -> (Double, Double) { let p = w.plan(a, s); return (p.x, ly - p.y) }
        let inward: Double = w.accessAtStart ? 1 : -1, s = w.wallS
        let p = at(W.band / 2, s), q = at(W.band / 2, s + inward)
        let rot = atan2(q.1 - p.1, q.0 - p.0) * 180 / .pi - 90
        dxf.insert(CADLayers.pvAccess, accessBlock(&dxf), at: p, rotation: rot)
        // the tag beyond the cage, on the far side from the roof, reading left to right
        let tip = at(W.band / 2, s - inward * (W.cageOut + 0.25)), dx = p.0 - q.0, dy = p.1 - q.1
        let e = at(W.band / 2, w.accessAtStart ? w.v1 : w.v0)
        let side = (abs(p.0 - e.0) > 1e-6 ? p.0 < e.0 : p.1 < e.1) ? "LEFT" : "RIGHT"
        let note = String(format: W.ridgeAccessNote, side)
        guard abs(dx) >= abs(dy) else {
            // a ridge drawn up the sheet: the tag centred beyond the cage
            let off: Double = dy < 0 ? -1 : 1
            dxf.text(CADLayers.text, (tip.0, tip.1 + off * (0.3 + 1.6 * h)), height: h, W.ridgeAccessTag, align: .center, middle: true)
            dxf.text(CADLayers.text, (tip.0, tip.1 + off * 0.3), height: h, note, align: .center, middle: true)
            return
        }
        // across the sheet: the tag past the plan's grid bubbles and dimension chains on that side, with a leader to the cage
        let ext = dxf.extents, unit = dxf.unit, x = dx < 0 ? min(tip.0, ext.min.x / unit - 0.4) : max(tip.0, ext.max.x / unit + 0.4)
        if abs(x - tip.0) > 1e-6 { dxf.line(CADLayers.pvAccess, (tip.0 + (dx < 0 ? 0.15 : -0.15), tip.1), (x, tip.1)) }
        let tx = x + (dx < 0 ? -0.15 : 0.15), align: TextAlign = dx < 0 ? .right : .left
        dxf.text(CADLayers.text, (tx, tip.1 + 0.8 * h), height: h, W.ridgeAccessTag, align: align, middle: true)
        dxf.text(CADLayers.text, (tx, tip.1 - 0.8 * h), height: h, note, align: align, middle: true)
    }

    /// "G-GRID | S-COLS-E | S-ROOF-FRAM-E | …", the sheet's layer line.
    public static func layerSummary(_ parts: Set<Part>) -> String {
        let keys = (parts.contains(.plan) ? ["GRID", "POST", "TRUSS", "PURLIN"] : []) + (parts.contains(.section) ? ["SECTION"] : [])
            + (parts.contains(.pv) ? ["PV"] : []) + (parts.isEmpty ? [] : ["DIM", "TEXT"]) + (parts.contains(.table) ? ["TABLE"] : [])
        return keys.map { layer($0).name }.joined(separator: " | ")
    }

    /// `latitude` (A1's GPS) places the PV layout's shade; nil takes `RoofMount.defaultLatitude`. `longitude` picks the
    /// faces in use as the page does (`PlaneYield`).
    public static func build(_ v: Values, parts: Set<Part>, millimetres: Bool = false, latitude: Double? = nil,
                             longitude: Double? = nil) -> Output {
        var o = SketchDXF.Options(); o.millimetres = millimetres
        var dxf = SketchDXF(options: o)
        func layer(_ key: String) -> SketchDXF.Layer { Self.layer(key) }
        func TEXT(_ l: String, _ p: (Double, Double), _ h: Double, _ t: String, mid: Bool) {
            dxf.text(layer(l), p, height: h, t, align: mid ? .center : .left, middle: mid)
        }
        /// Writes one sketch op on a layer, mapped to metres by `tf` (`scale` sketch points per metre).
        func write(_ op: DrawOp, _ l: String, _ tf: (Pt) -> (Double, Double), _ scale: Double, text h: Double) {
            dxf.options.fixedTextHeight = h
            dxf.add([op], layer: { _, _ in layer(l) }, transform: tf, pointsPerMetre: scale)
        }

        let plan = RoofPlan(v, mode: .structure)
        let L = plan.layout, th = 0.3
        let tp: (Pt) -> (Double, Double) = { p in ((p.x - L.origin.x) / L.k, L.ly - (p.y - L.origin.y) / L.k) }
        let f = Roof.frame(v), xs = Roof.spans(v, .x), ys = Roof.spans(v, .y)
        let mount = parts.contains(.pv) ? RoofMount.layout(v, latitude: latitude, longitude: longitude).layout : nil
        let walkways = mount.map(RoofWalkway.walkways) ?? []
        // a roof access ladder standing out past the plan's bottom edge pushes the title and the section down
        let drop = walkways.contains { w in w.access && !w.ridge && L.ly - w.plan(0, w.v0 - RoofWalkway.ladderOut).y < -0.1 } ? RoofWalkway.ladderOut + 1.4 : 0
        if parts.contains(.plan) {
            for (op, tag) in zip(plan.sketch.ops, plan.tags) {
                // the dimension chains are DIMENSIONs, not their lines and texts
                guard let tag, let l = planLayers[tag], L.dimensions.isEmpty || (tag != "dim" && tag != "dimtxt") else { continue }
                write(op, l, tp, L.k, text: tag == "dimtxt" ? th * 0.8 : th)
            }
            dxf.options.fixedTextHeight = th * 0.8
            dxf.add(L.dimensions, layer: layer("DIM"), transform: tp, pointsPerMetre: L.k)
            TEXT("TEXT", (0, -1.2 - drop), th * 1.4, "แปลนโครงหลังคา | " + f.label + " | " + fmt(xs.reduce(0, +)) + " × " + fmt(ys.reduce(0, +))
                 + " ม. | แป @" + String(format: "%.2f", Roof.purlinSpacing(v)), mid: false)
        }
        if let mount {
            let pv = RoofPlan(v, mode: .pv, mount: mount)
            for (op, tag) in zip(pv.sketch.ops, pv.tags) {
                guard let tag, let l = pvLayers[tag] else { continue }
                // a module hides the purlins and grid under it
                if tag == "pv", case let .polygon(pts, _, _, _) = op { dxf.wipeout(layer(l), pts.map(tp)) }
                write(op, l, tp, L.k, text: th)
            }
            // the walkways in their gaps, as the team's walkway detail draws them
            for w in walkways { walkway(&dxf, w, ly: L.ly, text: th * 0.5) }
        }
        if parts.contains(.section) {
            // to scale, the ground at the clear height, so its measures are live DIMENSIONs (not the sketch's lines)
            let s = RoofSection(v, trueScale: true), top = parts.contains(.plan) ? -2.5 - drop : 0
            let ts: (Pt) -> (Double, Double) = { p in ((p.x - 380) / s.scale + L.lx / 2, top - p.y / s.scale) }
            for (i, (op, tag)) in zip(s.sketch.ops, s.tags).enumerated() {
                guard let tag, !s.dimensionOps.contains(i) else { continue }
                write(op, tag, ts, s.scale, text: th)
            }
            dxf.options.fixedTextHeight = th * 0.8
            dxf.add(s.dimensions, layer: layer("DIM"), transform: ts, pointsPerMetre: s.scale)
            TEXT("TEXT", (L.lx / 2 - s.span / 2, top - (s.sketch.height + 2) / s.scale - 0.8), th * 1.4,
                 "รูปตัด A-A | " + f.label + " | ช่วง " + fmt(s.span) + " ม. | ลาด " + Roof.slopeText(v), mid: false)
        }
        if parts.contains(.table) {
            let tx = L.lx + 4
            var ty = L.ly
            TEXT("TABLE", (tx, ty), th * 1.3, "ขนาดชิ้นส่วน 1–7 | " + f.label, mid: false); ty -= 0.8
            for (i, m) in f.members.enumerated() {
                let size = Roof.memberSize(v, i + 1)
                TEXT("TABLE", (tx, ty), th, "\(i + 1)  " + m.name, mid: false)
                TEXT("TABLE", (tx + 4, ty), th, size.isEmpty ? m.defaultSize : size, mid: false)
                dxf.line(layer("TABLE"), (tx, ty - 0.2), (tx + 10, ty - 0.2))
                ty -= 0.6
            }
        }

        // beside the drawing, with walkways: the team's walkway detail (top view, elevations, detail 1) at the plot scale
        if !walkways.isEmpty, let d = CADDetail.walkway {
            let unit = millimetres ? 1000.0 : 1, e = dxf.extents, scale = dxf.plotScale
            let name = dxf.detailBlock(d, name: "TC_DETAIL_WALKWAY")
            let h = d.size[1] * scale / 1000
            dxf.insert(CADLayers.detail, name, at: (e.max.x / unit + 3, e.max.y / unit - h), scale: scale * unit / 1000)
        }
        return dxf.output
    }

    static func num(_ x: Double) -> String { SketchDXF.num(x) }
    static func tis620(_ s: String) -> Data { SketchDXF.tis620(s) }
}
