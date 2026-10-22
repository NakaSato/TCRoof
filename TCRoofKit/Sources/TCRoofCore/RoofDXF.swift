import Foundation

/// C1 "ส่งออก CAD" (docs/ui/survey-c1 `cadBuild`): the roof plan, section A-A, member table and PV layout as a plain
/// DXF R12 drawing (LINE / CIRCLE / TEXT on named layers) that any CAD program opens. Coordinates are metres from the
/// plan's bottom-left corner, written in millimetres (1:1) or metres; the section sits under the plan and the table to
/// its right. Thai text is written in TIS-620 (`$DWGCODEPAGE` ANSI_874).
public enum RoofDXF {
    public enum Part: String, CaseIterable, Sendable { case plan, section, table, pv }

    public struct Output: Sendable {
        public let data: Data
        /// Entities written, and the layers they use in order of first use.
        public let entities: Int
        public let layers: [String]
    }

    /// AutoCAD colour index per layer (the design's `LY`).
    public static let colors: [String: Int] = ["GRID": 8, "OUTLINE": 7, "RIDGE": 1, "TRUSS": 5, "POST": 7, "PURLIN": 30, "SKYLIGHT": 4,
                                               "OBSTACLE": 1, "SECTION_MARK": 1, "DIM": 3, "TEXT": 7, "PV": 150, "PV_RAIL": 8, "PV_FOOT": 250, "PV_CUT": 1,
                                               "KEEPOUT": 1, "SECTION": 7, "TABLE": 7]
    /// The plan's path keys (`RoofPlan.tags`) → layers.
    static let planLayers: [String: String] = ["grid": "GRID", "bub": "GRID", "out": "OUTLINE", "ridge": "RIDGE", "tbd": "TRUSS",
                                               "truss": "TRUSS", "t2": "TRUSS", "raft": "TRUSS", "eave": "TRUSS", "post": "POST",
                                               "purl": "PURLIN", "sky": "SKYLIGHT", "obst": "OBSTACLE", "sec": "SECTION_MARK", "dim": "DIM",
                                               "txt": "TEXT", "dimtxt": "DIM"]
    static let pvLayers: [String: String] = ["pv": "PV", "rail": "PV_RAIL", "foot": "PV_FOOT", "cut": "PV_CUT", "kz": "KEEPOUT"]

    /// "GRID | POST | TRUSS | PURLIN | SECTION | DIM | TEXT | TABLE", the sheet's layer line.
    public static func layerSummary(_ parts: Set<Part>) -> String {
        [parts.contains(.plan) ? "GRID | POST | TRUSS | PURLIN" : "", parts.contains(.section) ? "SECTION" : "", parts.contains(.pv) ? "PV" : "",
         parts.isEmpty ? "" : "DIM | TEXT", parts.contains(.table) ? "TABLE" : ""].filter { !$0.isEmpty }.joined(separator: " | ")
    }

    /// `latitude` (A1's GPS) places the PV layout's shade; nil takes `RoofMount.defaultLatitude`. `longitude` picks the
    /// faces in use as the page does (`PlaneYield`).
    public static func build(_ v: Values, parts: Set<Part>, millimetres: Bool = true, latitude: Double? = nil,
                             longitude: Double? = nil) -> Output {
        var o = SketchDXF.Options(); o.millimetres = millimetres
        var dxf = SketchDXF(options: o)
        func layer(_ name: String) -> SketchDXF.Layer { .init(name, aci: colors[name] ?? 7) }
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
        if parts.contains(.plan) {
            for (op, tag) in zip(plan.sketch.ops, plan.tags) {
                guard let tag, let l = planLayers[tag] else { continue }
                write(op, l, tp, L.k, text: tag == "dimtxt" ? th * 0.8 : th)
            }
            TEXT("TEXT", (0, -1.2), th * 1.4, "แปลนโครงหลังคา | " + f.label + " | " + fmt(xs.reduce(0, +)) + " × " + fmt(ys.reduce(0, +))
                 + " ม. | แป @" + String(format: "%.2f", Roof.purlinSpacing(v)), mid: false)
        }
        if parts.contains(.pv) {
            let pv = RoofPlan(v, mode: .pv, mount: RoofMount.layout(v, latitude: latitude, longitude: longitude).layout)
            for (op, tag) in zip(pv.sketch.ops, pv.tags) {
                guard let tag, let l = pvLayers[tag] else { continue }
                write(op, l, tp, L.k, text: th)
            }
        }
        if parts.contains(.section) {
            let s = RoofSection(v), top = parts.contains(.plan) ? -2.5 : 0
            let ts: (Pt) -> (Double, Double) = { p in ((p.x - 380) / s.scale + L.lx / 2, top - p.y / s.scale) }
            for (op, tag) in zip(s.sketch.ops, s.tags) {
                guard let tag else { continue }
                write(op, tag, ts, s.scale, text: th)
            }
            TEXT("DIM", ts(Pt(380, 226)), th, fmt(s.span), mid: true)
            TEXT("TEXT", (L.lx / 2 - s.span / 2, top - 252 / s.scale - 0.8), th * 1.4,
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

        return dxf.output
    }

    static func num(_ x: Double) -> String { SketchDXF.num(x) }
    static func tis620(_ s: String) -> Data { SketchDXF.tis620(s) }
}
