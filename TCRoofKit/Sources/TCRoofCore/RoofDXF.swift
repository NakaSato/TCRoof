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
            dxf.polyline(CADLayers.pvRail, box(0, W.band, v - r, v + r), closed: true, aci: 8)
            for d in [-r / 3, r / 3] { dxf.line(CADLayers.pvRail, at(0, v + d), at(W.band, v + d), aci: 8) }
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
        dxf.solid(CADLayers.pvLifeline, box(W.rail.0, W.rail.1, w.v0, w.v1), aci: 80)
        for v in w.feet {
            for a in [W.grating.0 + 0.014, W.grating.1 - 0.014] {
                dxf.polyline(CADLayers.pvWalkway, box(a - 0.02, a + 0.02, v - 0.02, v + 0.02), closed: true, aci: 6)
            }
        }
        dxf.line(CADLayers.pvLifeline, at(W.lifeline, w.v0), at(W.lifeline, w.v1))
        for v in w.supports {
            dxf.polyline(CADLayers.pvLifeline, box(W.lifeline - 0.02, W.lifeline + 0.02, v - 0.02, v + 0.02), closed: true, aci: 3)
        }
        // the band's width across the walkway's start, when the gap runs along a plan axis
        let a = at(0, w.v0), b = at(W.band, w.v0), up = at(0, w.v0 + 1)
        let across = (b.0 - a.0, b.1 - a.1), along = (up.0 - a.0, up.1 - a.1), back = (w.access ? W.ladderOut + 0.4 : 0.5) / max(1e-9, hypot(along.0, along.1))
        let o = (a.0 - along.0 * back, a.1 - along.1 * back)
        if !w.access, abs(across.1) < 1e-6 || abs(across.0) < 1e-6 {
            dxf.dimension(CADLayers.dim, a, b, at: o, vertical: abs(across.0) < 1e-6, text: String(format: "%.2f", W.band), height: h)
        }
        // a short tag before the start, reading left to right across the walkway (the detail sheet has the rest)
        var angle = atan2(across.1, across.0) * 180 / .pi
        if angle > 90 { angle -= 180 } else if angle <= -90 { angle += 180 }
        guard w.access else {
            dxf.text(CADLayers.text, at(W.band / 2, w.v0 - 0.9), height: h, W.tag, align: .center, middle: true, angle: angle)
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

    /// "TC-GRID | TC-ROOF-POST | TC-ROOF-TRUSS | …", the sheet's layer line.
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
        let drop = walkways.contains { w in w.access && L.ly - w.plan(0, w.v0 - RoofWalkway.ladderOut).y < -0.1 } ? RoofWalkway.ladderOut + 1.4 : 0
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
