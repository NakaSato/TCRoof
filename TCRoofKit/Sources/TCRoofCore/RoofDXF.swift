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
                                               "OBSTACLE": 1, "SECTION_MARK": 1, "DIM": 3, "TEXT": 7, "PV": 150, "PV_GROUP": 170,
                                               "KEEPOUT": 1, "SECTION": 7, "TABLE": 7]
    /// The plan's path keys (`RoofPlan.tags`) → layers.
    static let planLayers: [String: String] = ["grid": "GRID", "bub": "GRID", "out": "OUTLINE", "ridge": "RIDGE", "tbd": "TRUSS",
                                               "truss": "TRUSS", "t2": "TRUSS", "raft": "TRUSS", "eave": "TRUSS", "post": "POST",
                                               "purl": "PURLIN", "sky": "SKYLIGHT", "obst": "OBSTACLE", "sec": "SECTION_MARK", "dim": "DIM",
                                               "txt": "TEXT", "dimtxt": "DIM"]
    static let pvLayers: [String: String] = ["pv": "PV", "tbl": "PV_GROUP", "kz": "KEEPOUT"]

    /// "GRID · POST · TRUSS · PURLIN · SECTION · DIM · TEXT · TABLE", the sheet's layer line.
    public static func layerSummary(_ parts: Set<Part>) -> String {
        [parts.contains(.plan) ? "GRID · POST · TRUSS · PURLIN" : "", parts.contains(.section) ? "SECTION" : "", parts.contains(.pv) ? "PV" : "",
         parts.isEmpty ? "" : "DIM · TEXT", parts.contains(.table) ? "TABLE" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    public static func build(_ v: Values, parts: Set<Part>, millimetres: Bool = true, module: RoofPlan.Module = .catalogDefault) -> Output {
        let u = millimetres ? 1000.0 : 1
        var ents: [String] = [], count: [String: Int] = [:], order: [String] = []
        func use(_ l: String) { if count[l] == nil { order.append(l) }; count[l, default: 0] += 1 }
        func q(_ m: Double) -> String { num((m * u * 1000).rounded() / 1000) }
        func LINE(_ l: String, _ a: (Double, Double), _ b: (Double, Double)) {
            guard hypot(b.0 - a.0, b.1 - a.1) > 1e-6 else { return }
            use(l); ents += ["0", "LINE", "8", l, "10", q(a.0), "20", q(a.1), "30", "0", "11", q(b.0), "21", q(b.1), "31", "0"]
        }
        func CIRCLE(_ l: String, _ c: (Double, Double), _ r: Double) {
            use(l); ents += ["0", "CIRCLE", "8", l, "10", q(c.0), "20", q(c.1), "30", "0", "40", q(r)]
        }
        func TEXT(_ l: String, _ p: (Double, Double), _ h: Double, _ t: String, mid: Bool) {
            use(l); ents += ["0", "TEXT", "8", l, "10", q(p.0), "20", q(p.1), "30", "0", "40", q(h), "1", t]
            if mid { ents += ["72", "1", "73", "2", "11", q(p.0), "21", q(p.1), "31", "0"] }
        }
        /// Writes one sketch op on a layer, mapped to metres by `tf` (`scale` sketch points per metre).
        func write(_ op: DrawOp, _ l: String, _ tf: (Pt) -> (Double, Double), _ scale: Double, text h: Double) {
            switch op {
            case let .line(a, b, _, _, _): LINE(l, tf(a), tf(b))
            case let .rect(b, _, _, _):
                let c = [Pt(b.x, b.y), Pt(b.maxX, b.y), Pt(b.maxX, b.maxY), Pt(b.x, b.maxY)]
                for i in 0..<4 { LINE(l, tf(c[i]), tf(c[(i + 1) % 4])) }
            case let .circle(c, r, _, _, _): CIRCLE(l, tf(c), r / scale)
            case let .polygon(p, _, _, _): for i in p.indices { LINE(l, tf(p[i]), tf(p[(i + 1) % p.count])) }
            case let .polyline(p, _, _, _): for i in 0..<max(0, p.count - 1) { LINE(l, tf(p[i]), tf(p[i + 1])) }
            case let .text(t, at, _, _, _, _, _): TEXT(l, tf(at), h, t, mid: true)
            default: break
            }
        }

        let plan = RoofPlan(v, mode: .structure, module: module)
        let L = plan.layout, th = 0.3
        let tp: (Pt) -> (Double, Double) = { p in ((p.x - L.origin.x) / L.k, L.ly - (p.y - L.origin.y) / L.k) }
        let f = Roof.frame(v), xs = Roof.spans(v, .x), ys = Roof.spans(v, .y)
        if parts.contains(.plan) {
            for (op, tag) in zip(plan.sketch.ops, plan.tags) {
                guard let tag, let l = planLayers[tag] else { continue }
                write(op, l, tp, L.k, text: tag == "dimtxt" ? th * 0.8 : th)
            }
            TEXT("TEXT", (0, -1.2), th * 1.4, "แปลนโครงหลังคา · " + f.label + " · " + fmt(xs.reduce(0, +)) + " × " + fmt(ys.reduce(0, +))
                 + " ม. · แป @" + String(format: "%.2f", Roof.purlinSpacing(v)), mid: false)
        }
        if parts.contains(.pv) {
            let pv = RoofPlan(v, mode: .pv, module: module)
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
                 "รูปตัด A-A · " + f.label + " · ช่วง " + fmt(s.span) + " ม. · ลาด " + fmt(f.slope) + "°", mid: false)
        }
        if parts.contains(.table) {
            let tx = L.lx + 4
            var ty = L.ly
            TEXT("TABLE", (tx, ty), th * 1.3, "ขนาดชิ้นส่วน 1–7 · " + f.label, mid: false); ty -= 0.8
            for (i, m) in f.members.enumerated() {
                let size = Roof.memberSize(v, i + 1)
                TEXT("TABLE", (tx, ty), th, "\(i + 1)  " + m.name, mid: false)
                TEXT("TABLE", (tx + 4, ty), th, size.isEmpty ? m.defaultSize : size, mid: false)
                LINE("TABLE", (tx, ty - 0.2), (tx + 10, ty - 0.2))
                ty -= 0.6
            }
        }

        var out = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1009", "9", "$DWGCODEPAGE", "3", "ANSI_874",
                   "9", "$INSUNITS", "70", millimetres ? "4" : "6", "0", "ENDSEC",
                   "0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LTYPE", "70", "1",
                   "0", "LTYPE", "2", "CONTINUOUS", "70", "0", "3", "Solid line", "72", "65", "73", "0", "40", "0.0", "0", "ENDTAB",
                   "0", "TABLE", "2", "LAYER", "70", String(order.count)]
        for l in order { out += ["0", "LAYER", "2", l, "70", "0", "62", String(colors[l] ?? 7), "6", "CONTINUOUS"] }
        out += ["0", "ENDTAB", "0", "ENDSEC", "0", "SECTION", "2", "ENTITIES"] + ents + ["0", "ENDSEC", "0", "EOF"]
        let text = out.joined(separator: "\r\n") + "\r\n"
        return Output(data: tis620(text), entities: count.values.reduce(0, +), layers: order)
    }

    /// The design's `String(number)`: integers without a decimal point, others without trailing zeros.
    static func num(_ x: Double) -> String {
        if x == x.rounded() && abs(x) < 1e15 { return String(Int(x)) }
        var s = String(format: "%.3f", x)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    /// Thai to TIS-620 bytes; a few symbols to their CAD codes, anything else outside ASCII to "?".
    static func tis620(_ s: String) -> Data {
        let swap: [Character: String] = ["·": "-", "×": "x", "□": "SHS ", "–": "-", "°": "%%d", "Ø": "%%c", "½": "1/2", "¼": "1/4"]
        var bytes: [UInt8] = []
        bytes.reserveCapacity(s.utf8.count)
        for ch in s {
            if ch == "\r\n" { bytes += [13, 10]; continue }
            for u in ch.unicodeScalars {
                let v = u.value
                if v >= 0x20 && v <= 0x7E || v == 10 || v == 13 { bytes.append(UInt8(v)) }
                else if v >= 0x0E01 && v <= 0x0E5B { bytes.append(UInt8(v - 0x0D60)) }
                else if let r = swap[Character(u)] { bytes += Array(r.utf8) }
                else { bytes.append(UInt8(ascii: "?")) }
            }
        }
        return Data(bytes)
    }
}
