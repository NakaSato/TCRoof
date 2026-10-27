import Foundation

/// B2 `ส่งออก DXF`: the inverter station at real scale in metres, after the team's drawings
/// (`docs/specs/cad-export-dxf/reference/inverter-station`: `Inverter.dxf` one inverter outdoors, `Inverter_EXL-HV.dxf`
/// two, `Internal_Inverter_Station_EXL-LV.dxf` on a building's wall, `Part_1.dxf` the post's base plate).
///
/// - TOP VIEW: the B2 page's plan (`InverterStationDrawing`'s positions): outdoors the grid of columns (1, 2 … along the
///   length, A on the front / door line, B at the back), each column on its base plate, the door, the rack band at the
///   back with its AC tray, and the equipment row in front of it; indoors the existing wall, the measured area and the
///   rack against the wall. Chains: the spans and the length, the width, the row's widths and gaps, the rack's depth and
///   the walkway.
/// - FRONT VIEW (under it, the same x): outdoors the columns of line A, the edge beam, the rafters' ends, the front
///   purlin and the roof sheet, a T8 LED lamp on each inside column line; the rack (posts on their pads, the top rail at
///   2.00 m, the trays' rails), the AC tray at 0.50 m and the DC tray at 0.90 m, each cabinet with its top at 2.00 m and
///   each inverter with its top at 2.10 m, as the team hangs them, the cable ladder rising from AC-DB-01 and the DC tray
///   from each DC-DB. Chains: the row on top, the column spans, the heights.
/// - SIDE VIEW (right of the front view, seen from the station's right end): the mono-pitch roof, 0.25 m lower at the
///   back (the team's 3.00 / 2.75 m), its rafter, purlins and sheet over the tie beam; the rack's section with its
///   arms and trays and the equipment in front, nearer items hiding farther ones; indoors the wall behind.
/// - Right of the plan: the equipment schedule and the notes; and the base plate DETAIL (□75×75 post, 150×150 plate,
///   four bolts) at 5 : 1, the same block every column and rack post stands on in the plan.
///
/// Layers are the standard's (`CADLayers.station…`), every object ByLayer; the equipment, plates and posts are blocks
/// with a WIPEOUT, so what stands in front hides what is behind.
public enum InverterStationDXF {
    /// The team's heights (m): the rack's top, the AC and DC trays' bottoms, the inverters' tops, the roof's fall from
    /// the front line to the back one, and the pads under the posts.
    public static let rackTop = 2.00, acTray = 0.50, dcTray = 0.90, inverterTop = 2.10, roofFall = 0.25, pad = 0.10
    /// Post (□75×75) and base plate (150×150) sides, bolt spacing (m), and the roof's members' depths.
    public static let post = 0.075, plate = 0.15, boltSpacing = 0.105, beamDepth = 0.10, purlin = 0.05
    /// The roof past the front line, past the back line and past the end columns (m).
    public static let overFront = 0.40, overBack = 0.55, overEnd = 0.50
    /// The longest span between rack posts (m), as the team's racks keep.
    public static let maxRackSpan = 1.40
    /// The outdoor station's front post height when B2 has no measured height (m).
    public static let defaultHeight = 3.00
    /// Text heights (m).
    static let dimH = 0.10, labelH = 0.08, titleH = 0.25

    static let L = (col: CADLayers.stationColumn, beam: CADLayers.stationBeam, purlin: CADLayers.stationPurlin,
                    roof: CADLayers.stationRoof, rack: CADLayers.stationRack, pad: CADLayers.stationFooting,
                    eq: CADLayers.stationEquipment, tray: CADLayers.stationTray, light: CADLayers.stationLight,
                    door: CADLayers.stationDoor, wall: CADLayers.stationWall, area: CADLayers.stationArea,
                    ground: CADLayers.tankSoil, grid: CADLayers.grid, dim: CADLayers.dim, text: CADLayers.text,
                    table: CADLayers.roofTable)

    /// The station of a B2 section's answers as DXF.
    public static func build(_ v: Values, millimetres: Bool = false) -> RoofDXF.Output {
        build(InverterStation(v), millimetres: millimetres)
    }

    public static func build(_ s: InverterStation, millimetres: Bool = false) -> RoofDXF.Output {
        var o = SketchDXF.Options(); o.millimetres = millimetres
        var dxf = SketchDXF(options: o)
        let g = Geometry(s)
        topView(&dxf, g)
        frontView(&dxf, g)
        sideView(&dxf, g)
        schedule(&dxf, g)
        return dxf.output
    }

    // MARK: - geometry

    /// Where everything is, in station metres: x along the length from grid line 1 (outdoors) or the measured wall's
    /// left end (indoors), `y` from the back line B / the wall's face towards the front, heights from the ground.
    struct Geometry {
        let s: InverterStation
        let outdoor: Bool
        let length, width, drawn: Double
        /// The column lines along the length (outdoors).
        let grid: [Double]
        /// The front posts' height and the back ones' (outdoors).
        let high, low: Double
        /// The rack: from x0 to x1, from its back y0 to its front y1, its posts' x.
        let rack: (x0: Double, x1: Double, y0: Double, y1: Double)
        let rackPosts: [Double]
        /// Each item and its left end; where the equipment's back stands.
        let items: [(item: InverterStation.Item, x: Double)]
        let gaps: [Double]
        let equipmentY: Double
        /// The front view's ground and the side view's left end (line A).
        let groundF: Double, sideX: Double

        init(_ s: InverterStation) {
            self.s = s
            outdoor = s.site == .outdoor
            length = s.planLength; width = s.planWidth
            drawn = max(s.planLength, s.minLength)
            grid = s.planSpans.reduce(into: [0.0]) { $0.append($0[$0.count - 1] + $1) }
            high = max(2.60, s.height ?? InverterStationDXF.defaultHeight); low = high - InverterStationDXF.roofFall
            let (list, gaps) = s.row
            self.gaps = gaps
            var x: Double, posts: [Double]
            if outdoor {
                let r0 = InverterStation.bandX, r1 = r0 + s.bandLength
                rack = (r0, r1, InverterStation.bandY, InverterStation.bandY + s.bandDepth)
                let n = max(3, Int(((r1 - r0) / 1.2).rounded()) + 1)
                let step: Double = (r1 - r0 - 0.1) / Double(n - 1)
                posts = (0..<n).map { i -> Double in r0 + 0.05 + Double(i) * step }
                x = r0 + 0.10
                equipmentY = rack.y1
            } else {
                let f0 = 0.30, used = s.used
                rack = (f0 - 0.05, f0 + used + 0.05, 0.05, 0.25)
                posts = [f0 - 0.05]
                var px = f0
                for (i, it) in list.enumerated() {
                    px += it.w
                    if i < gaps.count { if it.kind != .inverter { posts.append(px + gaps[i] / 2) }; px += gaps[i] }
                }
                posts.append(f0 + used + 0.05)
                x = f0
                equipmentY = 0.28
            }
            // a post's square inside the rack's ends
            let h = InverterStationDXF.post / 2
            let lo: Double = rack.x0 + h, hi: Double = rack.x1 - h
            // no span longer than the team's 1.40 m: a long one is split evenly
            var split: [Double] = []
            for q in posts.map({ min(max($0, lo), hi) }).sorted() {
                if let last = split.last, q - last > InverterStationDXF.maxRackSpan + 1e-9 {
                    let n = Int(((q - last) / InverterStationDXF.maxRackSpan).rounded(.up))
                    for i in 1..<n { split.append(last + (q - last) * Double(i) / Double(n)) }
                }
                if split.last.map({ q - $0 > 0.05 }) ?? true { split.append(q) }
            }
            rackPosts = split
            var placed: [(InverterStation.Item, Double)] = []
            for (i, it) in list.enumerated() { placed.append((it, x)); x += it.w + (i < gaps.count ? gaps[i] : 0) }
            items = placed
            // the front view under the plan (its door and chains), the side view right of the front view
            let planLow = width + (outdoor ? 1.30 : 0) + 1.2
            groundF = -planLow - 0.8 - (outdoor ? high + 1.0 : InverterStationDXF.rackTop + 1.3)
            sideX = max(drawn, grid.last ?? 0) + 3.5
        }

        /// An item's bottom and top: cabinets hang with their top at the rack's top, inverters with theirs 0.10 m above.
        func heights(_ it: InverterStation.Item) -> (Double, Double) {
            let top = it.kind == .inverter ? InverterStationDXF.inverterTop : InverterStationDXF.rackTop
            return (max(InverterStationDXF.pad, top - it.h), top)
        }
        var inverters: [(item: InverterStation.Item, x: Double)] { items.filter { $0.item.kind == .inverter } }
        var cabinets: [(item: InverterStation.Item, x: Double)] { items.filter { $0.item.kind == .cabinet } }
        var deepest: Double { items.map(\.item.d).max() ?? 0.45 }
        /// Where the risers stop: under the roof's back half outdoors, 0.60 m over the rack indoors.
        var riserTop: Double { outdoor ? min(low - 0.15, InverterStationDXF.rackTop + 0.80) : InverterStationDXF.rackTop + 0.60 }
    }

    // MARK: - the team's components

    /// Inserts the library's component `name` with its box's lower-left corner at `p`, stretched to `w` × `h` when
    /// given; false when the library has no such component (the caller draws its own).
    @discardableResult
    static func place(_ dxf: inout SketchDXF, _ name: String, _ l: SketchDXF.Layer, at p: (Double, Double), w: Double? = nil, h: Double? = nil,
                      wipeout: Bool = false) -> Bool {
        guard let (n, b) = StationComponents.shared?.define(&dxf, name, layer: l, wipeout: wipeout) else { return false }
        let sx = w.map { $0 / b.width } ?? 1, sy = h.map { $0 / b.height } ?? 1
        dxf.insert(l, n, at: (p.0 - b.box[0] * sx, p.1 - b.box[1] * sy), xScale: sx, yScale: sy)
        return true
    }

    /// A tray or ladder run of the library's modules (`TCR_TRAY_…` 1.0 m, `TCR_LADDER_…` 1.2 m) from `a` along x,
    /// or up y when `vertical` (turned 90°, its width `width` to the right of `a`); the last module is shortened.
    @discardableResult
    static func run(_ dxf: inout SketchDXF, _ name: String, _ l: SketchDXF.Layer, from a: (Double, Double), length: Double,
                    vertical: Bool = false, width: Double = 0) -> Bool {
        guard length > 0.01, let (n, b) = StationComponents.shared?.define(&dxf, name, layer: l) else { return false }
        let module = b.width
        var done = 0.0
        while done < length - 1e-6 {
            let piece = min(module, length - done), k = piece / module
            if vertical { dxf.insert(l, n, at: (a.0 + width, a.1 + done), rotation: 90, xScale: k, yScale: 1) }
            else { dxf.insert(l, n, at: (a.0 + done, a.1), xScale: k, yScale: 1) }
            done += piece
        }
        return true
    }

    /// A column or rack post on plan at its centre: the library's 150 plate with the 75 tube, else this file's plate.
    static func column(_ dxf: inout SketchDXF, _ l: SketchDXF.Layer, at c: (Double, Double)) {
        if !place(&dxf, "TCR_STEEL_COLUMN_150_PLAN", l, at: (c.0 - plate / 2, c.1 - plate / 2)) { dxf.insert(l, basePlate(&dxf), at: c) }
    }

    /// The pad under a post in a view, centred on `x` on the ground `g`: the 200×100 concrete footing and the 200×10
    /// base plate on it; the post starts at the plate's top.
    static func footing(_ dxf: inout SketchDXF, x: Double, ground g: Double) {
        if place(&dxf, "TCR_CONCRETE_FOOTING_200X100_ELEVATION", L.pad, at: (x - 0.10, g)) {
            place(&dxf, "TCR_BASE_PLATE_200_ELEVATION", L.pad, at: (x - 0.10, g + pad))
        } else {
            dxf.polyline(L.pad, rect(x - 0.10, g, 0.20, pad), closed: true)
        }
    }
    static let postFoot = pad + 0.01

    /// The library's front view of an item, by its name and the inverter's model; nil for one it lacks.
    static func frontComponent(_ s: InverterStation, _ it: InverterStation.Item) -> String? {
        if let kw = it.kw {
            let m = s.catalog.inverter(kw: kw).model.uppercased()
            return m.contains("125") ? "TCR_GROWATT_MAX_125KTL3_LV_FRONT" : m.contains("40") ? "TCR_GROWATT_40KTL3_X_FRONT" : "TCR_GROWATT_MAX_80KTL3_LV_FRONT"
        }
        if it.name.hasPrefix("AC-DB") { return "TCR_SOLAR_AC_DB_FRONT" }
        if it.name.hasPrefix("DC-DB") { return "TCR_SOLAR_DC_DB_FRONT" }
        return "TCR_ENCLOSURE_630X750_FRONT"
    }
    /// The library's inverter on plan and where its body starts in the block (its handles stand out on the left).
    static func topComponent(_ s: InverterStation, _ it: InverterStation.Item) -> (name: String, body: (x: Double, w: Double))? {
        guard let kw = it.kw else { return nil }
        let m = s.catalog.inverter(kw: kw).model.uppercased()
        if m.contains("125") { return ("TCR_GROWATT_MAX_125KTL3_LV_TOP", (0.086, 0.97)) }
        if m.contains("40") { return nil }
        return ("TCR_GROWATT_MAX_80KTL3_LV_TOP", (0, 0.86))
    }

    // MARK: - blocks

    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [(Double, Double)] {
        [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    }
    static func mm(_ m: Double) -> String { String(format: "%.0f", m * 1000) }

    /// The team's base plate (`Part_1.dxf`), base point at the post's centre: the 150×150 plate, the □75×75 post (its
    /// 2.4 mm wall), and the four bolts 105 mm apart, each a washer, a hexagon nut and the bolt.
    static func basePlate(_ dxf: inout SketchDXF) -> String {
        dxf.block("IS_BASE_PLATE") { d in
            d.fine = true
            let p = plate / 2, q = post / 2, t = 0.0024
            d.wipeout(L.pad, rect(-p, -p, plate, plate))
            d.polyline(L.pad, rect(-p, -p, plate, plate), closed: true)
            d.polyline(L.col, rect(-q, -q, post, post), closed: true)
            d.polyline(L.col, rect(-q + t, -q + t, post - 2 * t, post - 2 * t), closed: true)
            let b = boltSpacing / 2
            for (x, y) in [(-b, -b), (b, -b), (b, b), (-b, b)] {
                d.circle(L.pad, (x, y), r: 0.009)
                d.polyline(L.pad, (0..<6).map { i in let a = Double(i) * .pi / 3; return (x + 0.00866 * cos(a), y + 0.00866 * sin(a)) }, closed: true)
                d.circle(L.pad, (x, y), r: 0.0045)
            }
        }
    }

    /// A cabinet seen from the front (`w` × `h`, base point at its bottom-left): the body, the door 20 mm in, the
    /// nameplate at the top and the handle, as the team's cabinet block draws them.
    static func cabinetFront(_ dxf: inout SketchDXF, w: Double, h: Double) -> String {
        dxf.block("IS_CAB_F_\(mm(w))x\(mm(h))") { d in
            d.wipeout(L.eq, rect(0, 0, w, h))
            d.polyline(L.eq, rect(0, 0, w, h), closed: true)
            d.polyline(L.eq, rect(0.02, 0.02, w - 0.04, h - 0.04), closed: true)
            d.polyline(L.eq, rect(0.04, h - 0.13, w - 0.08, 0.087), closed: true)
            d.polyline(L.eq, rect(w - 0.07, h * 0.45, 0.018, 0.09), closed: true)
        }
    }

    /// An inverter seen from the front: the body with eased corners, its display panel, the connectors along the
    /// bottom and the mounting lugs.
    static func inverterFront(_ dxf: inout SketchDXF, w: Double, h: Double) -> String {
        dxf.block("IS_INV_F_\(mm(w))x\(mm(h))") { d in
            let c = 0.03
            let body = [(c, 0.0), (w - c, 0), (w, c), (w, h - c), (w - c, h), (c, h), (0, h - c), (0, c)]
            d.wipeout(L.eq, body)
            d.polyline(L.eq, body, closed: true)
            let px = 0.07, pw = w - 0.14, py = h * 0.55, ph = h * 0.28, r = ph / 2
            d.polyline(L.eq, [(px + r, py), (px + pw - r, py), (px + pw, py + r), (px + pw - r, py + ph), (px + r, py + ph), (px, py + r)], closed: true)
            let n = max(3, Int(w / 0.06))
            for i in 0..<n {
                let x = 0.12 + Double(i) * (w - 0.24) / Double(n - 1)
                d.polyline(L.eq, rect(x - 0.008, -0.03, 0.016, 0.03), closed: true)
            }
            for x in [0.0, w - 0.06] { d.polyline(L.eq, rect(x, -0.02, 0.06, 0.02), closed: true) }
        }
    }

    /// An item seen from the side (`d` deep × `h`, base point at its bottom back corner, its front towards −x): a
    /// cabinet's body and door; an inverter's body, its heat sink at the back and the bracket.
    static func itemSide(_ dxf: inout SketchDXF, _ it: InverterStation.Item) -> String {
        let d0 = it.d, h = it.h
        return dxf.block("IS_\(it.kind == .inverter ? "INV" : "CAB")_S_\(mm(d0))x\(mm(h))") { d in
            d.wipeout(L.eq, rect(-d0, 0, d0, h))
            d.polyline(L.eq, rect(-d0, 0, d0, h), closed: true)
            if it.kind == .inverter {
                d.polyline(L.eq, rect(-d0 * 0.45, 0.04, d0 * 0.45 - 0.03, h - 0.08), closed: true)
                d.line(L.eq, (-d0 * 0.45, h * 0.15), (-d0 * 0.45, h * 0.85))
                d.polyline(L.eq, rect(-0.03, h * 0.1, 0.03, h * 0.8), closed: true)
            } else {
                d.line(L.eq, (-d0 + 0.02, 0.02), (-d0 + 0.02, h - 0.02))
                d.polyline(L.eq, rect(-d0 - 0.015, h * 0.45, 0.015, 0.09), closed: true)
            }
        }
    }

    /// An item on plan (`w` × `d`, base point at its back-left corner, its front towards −y): a cabinet's body and door
    /// line; an inverter's body with its bracket behind it.
    static func itemPlan(_ dxf: inout SketchDXF, _ it: InverterStation.Item) -> String {
        let w = it.w, d0 = it.d
        return dxf.block("IS_\(it.kind == .inverter ? "INV" : "CAB")_P_\(mm(w))x\(mm(d0))") { d in
            d.wipeout(L.eq, rect(0, -d0, w, d0))
            d.polyline(L.eq, rect(0, -d0, w, d0), closed: true)
            if it.kind == .inverter {
                d.line(L.eq, (0, -d0 * 0.25), (w, -d0 * 0.25))
                d.polyline(L.eq, rect(0.06, -d0 - 0.02, w - 0.12, 0.02), closed: true)
            } else {
                d.line(L.eq, (0.02, -d0 + 0.02), (w - 0.02, -d0 + 0.02))
            }
        }
    }

    /// A short zigzag across a riser's top: it goes on up.
    static func breakMark(_ dxf: inout SketchDXF, _ l: SketchDXF.Layer, x0: Double, x1: Double, y: Double) {
        let m = (x0 + x1) / 2
        dxf.polyline(l, [(x0 - 0.06, y), (m - 0.02, y), (m, y + 0.03), (m + 0.01, y - 0.03), (m + 0.03, y), (x1 + 0.06, y)])
    }

    static func label(_ dxf: inout SketchDXF, _ p: (Double, Double), _ lines: [String], h: Double = labelH, align: TextAlign = .left) {
        for (i, t) in lines.enumerated() { dxf.text(L.text, (p.0, p.1 - Double(i) * h * 1.5), height: h, t, align: align, middle: true) }
    }

    /// A label over a riser: a leader from the riser's top `a` up to the label's first line at `top`.
    static func riserLabel(_ dxf: inout SketchDXF, _ a: (Double, Double), top: Double, _ lines: [String]) {
        let y = top - Double(lines.count - 1) * labelH * 1.5
        dxf.line(L.text, a, (a.0, y - labelH))
        label(&dxf, (a.0 + 0.04, top), lines)
    }

    static func title(_ dxf: inout SketchDXF, _ p: (Double, Double), _ t: String, _ sub: String) {
        dxf.text(L.text, p, height: titleH, "%%U" + t)
        dxf.text(L.text, (p.0, p.1 - titleH * 1.4), height: labelH * 1.2, sub)
    }

    // MARK: - top view

    static func topView(_ dxf: inout SketchDXF, _ g: Geometry) {
        let s = g.s, W = g.width
        func p(_ x: Double, _ y: Double) -> (Double, Double) { (x, -y) }
        dxf.text(L.text, (0, g.outdoor ? 2.4 : 1.6), height: 0.32,
                 "INVERTER STATION | \(s.sizesText) = \(s.totalKW) kW | \(s.site.label)")

        if g.outdoor {
            // the grid: number lines across, A (front) and B (back) along, bubbles past them
            let r = 0.22, xs = g.grid, top = 1.45
            for (i, x) in xs.enumerated() {
                dxf.line(L.grid, p(x, -top + r), p(x, W + 0.35))
                TankDXF.bubble(&dxf, p(x, -top), r: r, "\(i + 1)")
            }
            for (name, y) in [("B", 0.0), ("A", W)] {
                dxf.line(L.grid, p(-1.25 + r, y), p((xs.last ?? 0) + 0.35, y))
                TankDXF.bubble(&dxf, p(-1.25, y), r: r, name)
            }
            for x in xs { for y in [0.0, W] { column(&dxf, L.col, at: p(x, y)) } }
            for (a, b) in zip(xs, xs.dropFirst()) {
                dxf.dimension(L.dim, p(a, 0), p(b, 0), at: p(0, -0.55), vertical: false, text: String(format: "%.2f", b - a), height: dimH)
            }
            dxf.dimension(L.dim, p(0, 0), p(g.length, 0), at: p(0, -0.85), vertical: false, text: String(format: "%.2f", g.length), height: dimH)
            dxf.dimension(L.dim, p(0, 0), p(0, W), at: p(-0.7, 0), vertical: true, text: String(format: "%.2f", W), height: dimH)
            // the door on line A by column 1, swinging out: the team's door block (its opening line 1.06 m up it, the
            // hinge 0.04 m in), else a 1.30 m leaf and its swing
            let hx = 0.15
            if !place(&dxf, "TCR_DOOR_SWING_1100_PLAN", L.door, at: (hx - 0.04, -W - 1.0596)) {
                let dr = 1.30
                dxf.polyline(L.door, rect(hx - 0.02, -W - dr, 0.04, dr), closed: true)
                dxf.polyline(L.door, (0...16).map { i in let a = -Double.pi / 2 + Double(i) / 16 * Double.pi / 2; return (hx + dr * cos(a), -W + dr * sin(a)) })
            }
            dxf.text(L.text, p(hx + 0.12, W + 0.45), height: labelH, "ประตู / DOOR")
        } else {
            // the existing wall along the back, the measured area in front of it
            let wall = rect(-0.3, 0, g.length + 0.6, 0.12)
            dxf.polyline(L.wall, wall, closed: true)
            dxf.hatch(L.wall, wall, spacing: 0.05)
            dxf.text(L.text, (0, 0.24), height: labelH, "EXISTING WALL / ผนังเดิม")
            dxf.polyline(L.area, [p(0, 0), p(0, W), p(g.length, W), p(g.length, 0)])
            dxf.dimension(L.dim, (0, 0.12), (g.length, 0.12), at: (0, 0.6), vertical: false,
                          text: String(format: "%.2f", g.length), height: dimH)
            dxf.dimension(L.dim, p(0, 0), p(0, W), at: p(-0.5, 0), vertical: true, text: String(format: "%.2f", W), height: dimH)
        }

        // the rack band: its outline, its posts on their plates, the AC tray inside
        let k = g.rack
        dxf.polyline(L.rack, [p(k.x0, k.y0), p(k.x1, k.y0), p(k.x1, k.y1), p(k.x0, k.y1)], closed: true)
        let h = post / 2
        for x in g.rackPosts { for y in [k.y0 + h, k.y1 - h] { column(&dxf, L.rack, at: p(x, y)) } }
        let tw = min(Double(s.trayWidth) / 1000, k.y1 - k.y0 - 0.1), ty = (k.y0 + k.y1 - tw) / 2
        let t0 = (g.items.first.map { $0.x + $0.item.w } ?? k.x0) - 0.10, t1 = (g.inverters.last.map { $0.x + $0.item.w } ?? k.x1)
        if !run(&dxf, "TCR_TRAY_PLAN_COVER_W\(s.trayWidth)", L.tray, from: p(t0, ty + tw), length: t1 - t0) {
            dxf.polyline(L.tray, [p(t0, ty), p(t1, ty), p(t1, ty + tw), p(t0, ty + tw)], closed: true)
        }
        dxf.text(L.text, p((t0 + t1) / 2, ty + tw / 2), height: labelH * 0.8, "AC PERFORATED TRAY \(s.trayWidth)x100 WITH COVER", align: .center, middle: true)
        dxf.dimension(L.dim, p(k.x0, k.y0), p(k.x0, k.y1), at: p(k.x0 - 0.25, 0), vertical: true, text: String(format: "%.2f", k.y1 - k.y0), height: dimH)

        // the equipment in front of the rack, its names and the row's chain
        for (it, x) in g.items {
            // the team's inverter on plan (its front at the block's base), else this file's outline
            if let c = topComponent(s, it), let b = StationComponents.shared?.blocks[c.name] {
                let sx = it.w / c.body.w
                place(&dxf, c.name, L.eq, at: (x - c.body.x * sx, -(g.equipmentY + it.d)), w: b.width * sx, h: it.d, wipeout: true)
            } else {
                dxf.insert(L.eq, itemPlan(&dxf, it), at: p(x, g.equipmentY))
            }
            let cx = x + it.w / 2, cy = g.equipmentY + it.d / 2
            if it.kind == .inverter {
                if let m = InverterStationDrawing.model(s, it, brand: true) { dxf.text(L.text, p(cx, cy), height: labelH * 0.7, m, align: .center, middle: true) }
                dxf.text(L.text, p(cx, g.equipmentY + it.d + 0.12), height: labelH, it.name, align: .center, middle: true)
            } else {
                label(&dxf, p(cx, cy - 0.04), ["SOLAR", it.name], h: labelH * 0.8, align: .center)
            }
        }
        let chainY = g.equipmentY + g.deepest + 0.35
        for (i, (it, x)) in g.items.enumerated() {
            dxf.dimension(L.dim, p(x, g.equipmentY), p(x + it.w, g.equipmentY), at: p(0, chainY), vertical: false, text: String(format: "%.2f", it.w), height: dimH * 0.8)
            if i < g.gaps.count {
                let a = x + it.w, b = a + g.gaps[i]
                dxf.dimension(L.dim, p(a, g.equipmentY), p(b, g.equipmentY), at: p(0, chainY), vertical: false, text: String(format: "%.2f", b - a), height: dimH * 0.8)
            }
        }
        // the walkway in front of the equipment, to line A / the area's edge
        let front = g.outdoor ? k.y1 + 0.45 : 0.85, x = (g.items.first?.x ?? k.x0) + 0.15
        if W - front > 0.05 {
            dxf.dimension(L.dim, p(x, front), p(x, W), at: p(x, 0), vertical: true, text: String(format: "ทางเดิน %.2f", W - front), height: dimH)
        }
        let low = W + (g.outdoor ? 1.30 : 0) + 0.7
        title(&dxf, (0, -low), "TOP VIEW / แปลน", "หน่วย ม. | มาตราส่วนจริง")
    }

    // MARK: - the shelter's members

    /// A member of the outdoor shelter as the member schedule lists it: its mark, what it is, its size, how many and
    /// their length together (m, centre to centre; the columns from their base plates).
    public struct Member: Hashable, Sendable {
        public var mark: String
        public var name: String
        public var size: String
        public var count: Int
        public var length: Double
    }
    /// The members' sizes until the team names them: the column as the library's base plate detail draws it, the rest
    /// at the depth the station drawings show.
    public static let columnSize = "□75×75×2.4 (รอยืนยัน)", beamSize = "ลึก 0.10 ม. ตามแบบ", purlinSize = "0.05 ม. ตามแบบ"
    /// A mark's circle (m).
    static let markR = 0.13

    /// The purlins on each rafter, about 1 m apart over its length.
    static func purlinCount(_ g: Geometry) -> Int {
        let len: Double = g.width + overFront + overBack
        return max(2, Int((len / 1.0).rounded(.up))) + 1
    }
    /// One rafter along its slope, from 0.40 m past A to 0.55 m past B.
    static func rafterLength(_ g: Geometry) -> Double {
        let len: Double = g.width + overFront + overBack
        return hypot(len, roofFall * len / g.width)
    }

    /// The shelter's members: C1 the columns, B1 the edge beams on lines A and B, TB a tie beam on each column line,
    /// R1 a rafter on each column line, P1 the purlins; none for a station on a wall.
    public static func members(_ s: InverterStation) -> [Member] { members(Geometry(s)) }
    static func members(_ g: Geometry) -> [Member] {
        guard g.outdoor, let first = g.grid.first, let last = g.grid.last else { return [] }
        let n = g.grid.count, run = last - first, np = purlinCount(g)
        let columns: Double = Double(n) * (g.high - postFoot) + Double(n) * (g.low - postFoot)
        return [
            Member(mark: "C1", name: "เสา / Column", size: columnSize, count: 2 * n, length: columns),
            Member(mark: "B1", name: "คานขอบ แนว A, B / Edge beam", size: beamSize, count: 2, length: 2 * run),
            Member(mark: "TB", name: "คานยึดหัวเสา / Tie beam", size: beamSize, count: n, length: Double(n) * g.width),
            Member(mark: "R1", name: "จันทัน / Rafter", size: beamSize, count: n, length: Double(n) * rafterLength(g)),
            Member(mark: "P1", name: "แป / Purlin", size: purlinSize, count: np, length: Double(np) * (run + 2 * overEnd)),
        ]
    }

    /// A member's mark: its name in a circle at `c` and a leader from the circle to the member at `a`.
    static func tag(_ dxf: inout SketchDXF, _ mark: String, at c: (Double, Double), to a: (Double, Double)) {
        let d = hypot(a.0 - c.0, a.1 - c.1)
        if d > markR + 0.01 { dxf.line(L.text, (c.0 + (a.0 - c.0) / d * markR, c.1 + (a.1 - c.1) / d * markR), a) }
        dxf.circle(L.text, c, r: markR)
        dxf.text(L.text, c, height: markR * 0.9, mark, align: .center, middle: true)
    }

    // MARK: - front view

    static func frontView(_ dxf: inout SketchDXF, _ g: Geometry) {
        let s = g.s, G = g.groundF
        func p(_ x: Double, _ h: Double) -> (Double, Double) { (x, G + h) }
        let x0 = g.outdoor ? -overEnd - 0.4 : g.rack.x0 - 0.6, x1 = max(g.outdoor ? (g.grid.last ?? 0) + overEnd + 0.4 : g.rack.x1 + 0.6, g.rack.x1 + 0.6)
        dxf.line(L.ground, p(x0, 0), p(x1, 0))
        dxf.line(L.ground, p(x0, -0.10), p(x1, -0.10))
        let h = post / 2

        if g.outdoor {
            let xs = g.grid, H = g.high, end = xs.last ?? 0
            for x in xs {
                footing(&dxf, x: x, ground: G)
                dxf.polyline(L.col, [p(x - h, postFoot), p(x - h, H), p(x + h, H), p(x + h, postFoot)])
            }
            // the edge beam under the post tops, the rafters' ends on them, the front purlin and the sheet
            dxf.polyline(L.beam, rect(xs[0] + h, G + H - beamDepth, end - xs[0] - post, beamDepth), closed: true)
            for x in xs { dxf.polyline(L.beam, rect(x - 0.025, G + H, 0.05, beamDepth), closed: true) }
            dxf.polyline(L.purlin, rect(-overEnd, G + H + beamDepth, end + 2 * overEnd, purlin), closed: true)
            dxf.polyline(L.roof, rect(-overEnd - 0.05, G + H + beamDepth + purlin, end + 2 * overEnd + 0.1, 0.02), closed: true)
            // the lamps on the inside column lines (mid-span when there is none)
            let lamps = xs.count > 2 ? Array(xs.dropFirst().dropLast()) : [end / 2]
            for x in lamps {
                dxf.line(L.light, p(x, H - beamDepth), p(x, H - beamDepth - 0.08))
                dxf.polyline(L.light, rect(x - 0.30, G + H - beamDepth - 0.14, 0.60, 0.06), closed: true)
                dxf.text(L.text, p(x, H + 0.32), height: labelH, "T8 LED LAMP", align: .center, middle: true)
            }
            dxf.dimension(L.dim, p(-0.35, 0), p(-0.35, H), at: p(-0.35, 0), vertical: true, text: String(format: "%.2f", H), height: dimH)
            for (a, b) in zip(xs, xs.dropFirst()) {
                dxf.dimension(L.dim, p(a, 0), p(b, 0), at: p(0, -0.45), vertical: false, text: String(format: "%.2f", b - a), height: dimH)
            }
            dxf.dimension(L.dim, p(0, 0), p(end, 0), at: p(0, -0.75), vertical: false, text: String(format: "%.2f", end), height: dimH)
            for (i, x) in xs.enumerated() {
                dxf.line(L.grid, p(x, -0.10), p(x, -1.03))
                TankDXF.bubble(&dxf, p(x, -1.25), r: 0.22, "\(i + 1)")
            }
            // the members' marks in a column right of the last column line
            let tx = end + overEnd + 0.35
            tag(&dxf, "C1", at: p(end + 0.45, 1.6), to: p(end + h, 1.6))
            tag(&dxf, "B1", at: p(tx, H - 0.30), to: p(end - h - 0.10, H - beamDepth / 2))
            tag(&dxf, "R1", at: p(tx, H + 0.03), to: p(end + 0.025, H + beamDepth / 2))
            tag(&dxf, "P1", at: p(tx, H + 0.35), to: p(end + overEnd - 0.05, H + beamDepth + purlin / 2))
        }

        // the rack: posts on their pads, the top rail, the trays' rails and a rail under each item
        let k = g.rack
        for x in g.rackPosts {
            footing(&dxf, x: x, ground: G)
            dxf.polyline(L.rack, rect(x - h, G + postFoot, post, rackTop - postFoot), closed: true)
        }
        dxf.polyline(L.rack, rect(k.x0, G + rackTop - 0.05, k.x1 - k.x0, 0.05), closed: true)
        dxf.polyline(L.rack, rect(k.x0, G + acTray - 0.05, k.x1 - k.x0, 0.05), closed: true)
        let firstInv = g.inverters.first?.x ?? k.x0
        dxf.polyline(L.rack, rect(firstInv - 0.05, G + dcTray - 0.05, k.x1 - firstInv + 0.05, 0.05), closed: true)
        for (it, x) in g.items {
            let (b, _) = g.heights(it)
            if b - 0.05 > acTray + 0.1 { dxf.polyline(L.rack, rect(x - 0.05, G + b - 0.05, it.w + 0.1, 0.05), closed: true) }
        }
        // the trays, labelled right of the rack
        let ac0 = (g.items.first.map { $0.x + $0.item.w } ?? k.x0) - 0.10, ac1 = g.inverters.last.map { $0.x + $0.item.w } ?? k.x1
        let dc1 = g.cabinets.last.map { $0.x + $0.item.w } ?? k.x1
        for (a, b, y) in [(ac0, ac1, acTray), (firstInv, dc1, dcTray)] where !run(&dxf, "TCR_TRAY_SIDE_PERF_H100", L.tray, from: p(a, y), length: b - a) {
            dxf.polyline(L.tray, rect(a, G + y, b - a, 0.10), closed: true)
        }
        let lx = k.x1 + 0.35
        for (y, t) in [(acTray + 0.05, ["TO SOLAR AC-DB-01", "AC PERFORATED TRAY \(s.trayWidth)x100 (WITH COVER)"]),
                       (dcTray + 0.05, ["DC PERFORATED TRAY 100x100 (WITH COVER)"])] {
            dxf.line(L.text, p(min(ac1, dc1), y), p(lx - 0.05, y))
            label(&dxf, p(lx, y + (t.count > 1 ? 0.06 : 0)), t)
        }
        // the equipment in front of the rack, hiding it; names on the plates and over the inverters
        // (the team's blocks stretched to the catalog's size; this file's own where the library has none)
        for (it, x) in g.items {
            let (b, top) = g.heights(it)
            let lib = frontComponent(s, it).map { place(&dxf, $0, L.eq, at: p(x, b), w: it.w, h: top - b, wipeout: true) } ?? false
            if !lib {
                dxf.insert(L.eq, it.kind == .inverter ? inverterFront(&dxf, w: it.w, h: top - b) : cabinetFront(&dxf, w: it.w, h: top - b), at: p(x, b))
            }
            if it.kind == .inverter {
                dxf.text(L.text, p(x + it.w / 2, top + 0.08), height: labelH, it.name, align: .center, middle: true)
            } else {
                // on the cabinet's nameplate (the team's blocks: DC-DB's at 0.904 of its height, the meter's at 0.911);
                // the AC-DB's plate carries its own label, so its name goes in the clear lower part
                let hh = top - b
                let y = !lib ? top - 0.0865 : it.name.hasPrefix("AC-DB") ? b + 0.2 * hh : it.name.hasPrefix("DC-DB") ? b + 0.904 * hh : b + 0.911 * hh
                dxf.text(L.text, p(x + it.w / 2, y), height: 0.045, "SOLAR " + it.name, align: .center, middle: true)
            }
            if it.kind == .inverter, !lib, let m = InverterStationDrawing.model(s, it, brand: true) {
                dxf.text(L.text, p(x + it.w / 2, b + (top - b) * 0.3), height: labelH * 0.7, m, align: .center, middle: true)
            }
        }
        // the ladder up from AC-DB-01 and the DC trays up from each DC-DB
        let rt = g.riserTop, lw = Double(s.ladderWidth) / 1000
        // the risers' labels over the roof (outdoors) or over the risers, a leader down to each
        let labelsTop = g.outdoor ? g.high + 0.72 : rt + 0.42
        if let ac = g.items.first {
            let a = ac.x + 0.08, b = a + lw
            if !run(&dxf, "TCR_LADDER_PLAN_W\(s.ladderWidth)", L.tray, from: p(a, rackTop), length: rt - rackTop, vertical: true, width: lw) {
                dxf.polyline(L.tray, [p(a, rackTop), p(a, rt)]); dxf.polyline(L.tray, [p(b, rackTop), p(b, rt)])
                var y = rackTop + 0.15
                while y < rt - 0.05 { dxf.line(L.tray, p(a, y), p(b, y)); y += 0.25 }
            }
            breakMark(&dxf, L.tray, x0: a, x1: b, y: G + rt)
            riserLabel(&dxf, p((a + b) / 2, rt), top: G + labelsTop, ["TO INJECTION POINT", "AC CABLE LADDER \(s.ladderWidth)x100 (NON COVER)"])
        }
        for (it, x) in g.cabinets where it.name.hasPrefix("DC-DB") {
            let a = x + it.w / 2 - 0.05
            if !run(&dxf, "TCR_TRAY_PLAN_COVER_W100", L.tray, from: p(a, rackTop), length: rt - rackTop, vertical: true, width: 0.10) {
                dxf.polyline(L.tray, rect(a, G + rackTop, 0.10, rt - rackTop), closed: true)
            }
            breakMark(&dxf, L.tray, x0: a, x1: a + 0.1, y: G + rt)
        }
        if let last = g.cabinets.last(where: { $0.item.name.hasPrefix("DC-DB") }) {
            riserLabel(&dxf, p(last.x + last.item.w / 2, rt), top: G + labelsTop, ["FROM PV PANEL", "DC PERFORATED TRAY 100x100 WITH COVER"])
        }

        // the team's scale figure left of the station
        place(&dxf, "TCR_SCALE_FIGURE_ELEVATION", L.text, at: p((g.outdoor ? -overEnd : k.x0) - 1.6, 0))

        // the row on top, the rack's heights on its left
        let chainH = inverterTop + 0.30
        for (i, (it, x)) in g.items.enumerated() {
            dxf.dimension(L.dim, p(x, inverterTop), p(x + it.w, inverterTop), at: p(0, chainH), vertical: false, text: String(format: "%.2f", it.w), height: dimH * 0.8)
            if i < g.gaps.count {
                let a = x + it.w, b = a + g.gaps[i]
                dxf.dimension(L.dim, p(a, inverterTop), p(b, inverterTop), at: p(0, chainH), vertical: false, text: String(format: "%.2f", b - a), height: dimH * 0.8)
            }
        }
        let hx = k.x0 - 0.30
        var last = 0.0
        for y in [acTray, dcTray, rackTop] {
            dxf.dimension(L.dim, p(k.x0, last), p(k.x0, y), at: p(hx, 0), vertical: true, text: String(format: "%.2f", y - last), height: dimH)
            last = y
        }
        if let ac = g.items.first {
            let (b, _) = g.heights(ac.item)
            dxf.dimension(L.dim, p(ac.x, 0), p(ac.x, b), at: p(hx - 0.25, 0), vertical: true, text: String(format: "%.2f", b), height: dimH)
        }
        if !g.outdoor {
            dxf.dimension(L.dim, p(k.x0, 0), p(k.x1, 0), at: p(0, -0.45), vertical: false, text: String(format: "%.2f", k.x1 - k.x0), height: dimH)
            for (a, b) in zip(g.rackPosts, g.rackPosts.dropFirst()) {
                dxf.dimension(L.dim, p(a, 0), p(b, 0), at: p(0, -0.25), vertical: false, text: String(format: "%.2f", b - a), height: dimH * 0.8)
            }
        }
        title(&dxf, (0, G - (g.outdoor ? 1.9 : 0.9)), "FRONT VIEW / รูปด้านหน้า", "ตู้ขอบบน \(fmt(rackTop)) ม. | อินเวอร์เตอร์ขอบบน \(fmt(inverterTop)) ม.")
    }

    // MARK: - side view

    static func sideView(_ dxf: inout SketchDXF, _ g: Geometry) {
        let s = g.s, W = g.width, G = g.groundF, X = g.sideX
        // u from line A (the front, left) to line B / the wall (right): seen from the station's right end
        func p(_ u: Double, _ h: Double) -> (Double, Double) { (X + u, G + h) }
        let h = post / 2
        dxf.line(L.ground, p(-overFront - 0.4, 0), p(W + overBack + 0.4, 0))
        dxf.line(L.ground, p(-overFront - 0.4, -0.10), p(W + overBack + 0.4, -0.10))

        // the rack's back and front, from line A
        let ub = W - g.rack.y0, uf = W - g.rack.y1
        if g.outdoor {
            let Hf = g.high, Hb = g.low
            for (u, top) in [(0.0, Hf), (W, Hb)] {
                footing(&dxf, x: X + u, ground: G)
                dxf.polyline(L.col, rect(X + u - h, G + postFoot, post, top - postFoot), closed: true)
            }
            // the edge beams' sections at the post tops, the tie beam at the back's height
            dxf.polyline(L.beam, rect(X + h, G + Hf - beamDepth, 0.05, beamDepth), closed: true)
            dxf.polyline(L.beam, rect(X + W - h - 0.05, G + Hb - beamDepth, 0.05, beamDepth), closed: true)
            dxf.polyline(L.beam, rect(X + h, G + Hb - beamDepth, W - post, beamDepth), closed: true)
            // the rafter on the post tops, the purlins on it and the sheet
            let slope = (Hb - Hf) / W
            func under(_ u: Double) -> Double { Hf + slope * u }
            let u0 = -overFront, u1 = W + overBack
            dxf.polyline(L.beam, [p(u0, under(u0)), p(u1, under(u1)), p(u1, under(u1) + beamDepth), p(u0, under(u0) + beamDepth)], closed: true)
            let len = u1 - u0, n = max(2, Int((len / 1.0).rounded(.up))) + 1
            let a = atan(slope), (c, sn) = (cos(a), sin(a))
            for i in 0..<n {
                let u = u0 + 0.03 + Double(i) * (len - 0.06 - purlin) / Double(n - 1)
                let b = (u, under(u) + beamDepth)
                let q = [(0.0, 0.0), (purlin, 0), (purlin, purlin), (0, purlin)].map { (b.0 + $0.0 * c - $0.1 * sn, b.1 + $0.0 * sn + $0.1 * c) }
                dxf.polyline(L.purlin, q.map { p($0.0, $0.1) }, closed: true)
            }
            let off = beamDepth + purlin
            dxf.polyline(L.roof, [p(u0 - 0.05, under(u0 - 0.05) + off), p(u1 + 0.05, under(u1 + 0.05) + off),
                                  p(u1 + 0.05, under(u1 + 0.05) + off + 0.02), p(u0 - 0.05, under(u0 - 0.05) + off + 0.02)], closed: true)
            dxf.dimension(L.dim, p(-overFront - 0.2, 0), p(-overFront - 0.2, Hf), at: p(-overFront - 0.2, 0), vertical: true, text: String(format: "%.2f", Hf), height: dimH)
            dxf.dimension(L.dim, p(W + overBack + 0.2, 0), p(W + overBack + 0.2, Hb), at: p(W + overBack + 0.2, 0), vertical: true, text: String(format: "%.2f", Hb), height: dimH)
            dxf.dimension(L.dim, p(0, 0), p(W, 0), at: p(0, -0.45), vertical: false, text: String(format: "%.2f", W), height: dimH)
            for (name, u) in [("A", 0.0), ("B", W)] {
                dxf.line(L.grid, p(u, -0.10), p(u, -0.78))
                TankDXF.bubble(&dxf, p(u, -1.0), r: 0.22, name)
            }
            // the members' marks: the column and edge beam left of line A, the tie beam over the rack, the rafter and
            // the last purlin over the roof
            tag(&dxf, "C1", at: p(-0.35, 1.2), to: p(-h, 1.2))
            tag(&dxf, "B1", at: p(-0.35, Hf - 0.18), to: p(h + 0.025, Hf - beamDepth / 2))
            let tu = W - 0.35
            tag(&dxf, "TB", at: p(tu, Hb - 0.36), to: p(tu, Hb - beamDepth))
            tag(&dxf, "R1", at: p(W / 2, under(W / 2) + 0.55), to: p(W / 2, under(W / 2) + beamDepth / 2))
            let pu = u1 - 0.03 - purlin
            tag(&dxf, "P1", at: p(pu, under(pu) + 0.55), to: p(pu + purlin / 2, under(pu) + beamDepth + purlin))
        } else {
            let wall = rect(X + W, G, 0.12, rackTop + 1.0)
            dxf.polyline(L.wall, wall, closed: true)
            dxf.hatch(L.wall, wall, spacing: 0.05)
            dxf.text(L.text, p(W + 0.3, rackTop + 0.7), height: labelH, "EXISTING WALL", angle: 90)
            dxf.dimension(L.dim, p(W - g.equipmentY - g.deepest, 0), p(W, 0), at: p(0, -0.45), vertical: false,
                          text: String(format: "%.2f", g.equipmentY + g.deepest), height: dimH)
        }

        // the rack's section: posts, the arms under the trays and at the top, the trays cut
        for u in [uf + h, ub - h] {
            footing(&dxf, x: X + u, ground: G)
            dxf.polyline(L.rack, rect(X + u - h, G + postFoot, post, rackTop - postFoot), closed: true)
        }
        for y in [acTray, dcTray, rackTop] { dxf.polyline(L.rack, rect(X + uf + post, G + y - 0.075, ub - uf - 2 * post, 0.075), closed: true) }
        let tw = min(Double(s.trayWidth) / 1000, ub - uf - 2 * post - 0.02)
        for (u, w, y, name) in [((uf + ub - tw) / 2, tw, acTray, "TCR_TRAY_SECTION_\(s.trayWidth)X100"), (uf + post + 0.01, 0.10, dcTray, "TCR_TRAY_SECTION_100X100")]
            where !place(&dxf, name, L.tray, at: p(u, y)) {
            dxf.polyline(L.tray, rect(X + u, G + y, w, 0.10), closed: true)
            dxf.line(L.tray, p(u, y), p(u + w, y + 0.10)); dxf.line(L.tray, p(u, y + 0.10), p(u + w, y))
        }
        dxf.dimension(L.dim, p(uf, 0.30), p(ub, 0.30), at: p(0, 0.30), vertical: false, text: String(format: "%.2f", ub - uf), height: dimH * 0.8)
        // the equipment in front of the rack, the far end first so nearer items hide it
        let eFront = W - g.equipmentY
        // (the team's side blocks, their front at the block's base point, stretched to each item's depth and height)
        for (it, _) in g.items {
            let (b, top) = g.heights(it)
            let name = it.kind == .inverter ? "TCR_INVERTER_GENERIC_SIDE" : "TCR_DB_ENCLOSURE_SIDE"
            if !place(&dxf, name, L.eq, at: p(eFront - it.d, b), w: it.d, h: top - b, wipeout: true) {
                var side = it; side.h = top - b
                dxf.insert(L.eq, itemSide(&dxf, side), at: p(eFront, b))
            }
        }
        // the ladder and the DC tray rising
        let rt = g.riserTop
        let la = eFront - min(0.30, g.deepest - 0.05)
        if !run(&dxf, "TCR_LADDER_SIDE_H100", L.tray, from: p(la, rackTop), length: rt - rackTop, vertical: true, width: 0.10) {
            dxf.polyline(L.tray, rect(X + la, G + rackTop, 0.10, rt - rackTop), closed: true)
        }
        breakMark(&dxf, L.tray, x0: X + la, x1: X + la + 0.10, y: G + rt)
        label(&dxf, p(la - 0.12, rt - 0.05), ["TO INJECTION POINT", "AC CABLE LADDER \(s.ladderWidth)x100 (NON COVER)"], align: .right)
        let da = eFront - 0.16
        if !run(&dxf, "TCR_TRAY_SIDE_PERF_H100", L.tray, from: p(da, rackTop), length: rt - 0.12 - rackTop, vertical: true, width: 0.10) {
            dxf.polyline(L.tray, rect(X + da, G + rackTop, 0.10, rt - 0.12 - rackTop), closed: true)
        }
        let hx = g.outdoor ? W + overBack + 0.55 : W + 0.55
        var last = 0.0
        for y in [acTray, dcTray, rackTop] {
            dxf.dimension(L.dim, p(ub, last), p(ub, y), at: p(hx, 0), vertical: true, text: String(format: "%.2f", y - last), height: dimH)
            last = y
        }
        if let inv = g.inverters.first {
            label(&dxf, p(eFront - inv.item.d - 0.08, inverterTop - 0.08), ["INVERTER"], align: .right)
        }
        // the scale figure in the walkway
        place(&dxf, "TCR_SCALE_FIGURE_ELEVATION", L.text, at: p(max(g.outdoor ? 0.15 : -0.9, eFront - g.deepest - 0.95), 0))
        title(&dxf, (X - overFront, G - (g.outdoor ? 1.7 : 0.9)), "SIDE VIEW / รูปด้านข้าง",
              g.outdoor ? "มองจากด้านขวาของสถานี | หลังคาลาดลงด้านหลัง \(fmt(roofFall)) ม." : "ติดผนังอาคาร | โครงลึก \(fmt(g.rack.y1 - g.rack.y0)) ม.")
    }

    // MARK: - schedule, notes and the base plate detail

    static let scheduleCols: [Double] = [0, 2.0, 5.4, 7.6, 9.4]

    static func schedule(_ dxf: inout SketchDXF, _ g: Geometry) {
        let s = g.s, x0 = g.sideX, y0 = g.outdoor ? 1.6 : 1.2, rh = 0.32, th = 0.12, cols = scheduleCols, w = cols[cols.count - 1]
        dxf.text(L.text, (x0, y0 + 0.3), height: 0.2, "ตารางอุปกรณ์ / EQUIPMENT SCHEDULE")
        var rows = [["อุปกรณ์", "รุ่น / รายละเอียด", "กว้าง×สูง×ลึก (มม.)", "ระดับล่าง–บน (ม.)"]]
        for (it, _) in g.items {
            let (b, top) = g.heights(it)
            var what = ""
            if let kw = it.kw {
                let inv = s.catalog.inverter(kw: kw), cb = s.breaker(kw: kw)
                what = [inv.brand, inv.model].filter { !$0.isEmpty }.joined(separator: " ") + " | CB \(cb.at)AT"
            } else if it.name.hasPrefix("AC-DB") {
                let ac = s.catalog.acCabinet(inverters: s.sizes.count)
                what = "\(s.breakerSummary) | busbar \(ac.busbar)"
            } else if it.name.hasPrefix("DC-DB"), let n = Int(it.name.suffix(2)), n <= s.sizes.count {
                what = "\(s.catalog.dcCabinet(mppt: s.catalog.inverter(kw: s.sizes[n - 1]).mppt).strings) strings"
            } else {
                what = it.name.hasPrefix("METER") ? "มิเตอร์ / Meter" : "Smart energy meter"
            }
            rows.append([(it.kind == .inverter ? "" : "SOLAR ") + it.name, what, "\(mm(it.w))×\(mm(it.h))×\(mm(it.d))",
                         String(format: "%.2f – %.2f", b, top)])
        }
        let fd = s.feeder
        rows.append(["AC TRAY", "Perforated \(s.trayWidth)x100 มีฝา", "", String(format: "%.2f", acTray)])
        rows.append(["DC TRAY", "Perforated 100x100 มีฝา", "", String(format: "%.2f", dcTray)])
        rows.append(["CABLE LADDER", "\(s.ladderWidth)x100 ไม่มีฝา | \(fd.at)AT \(fd.label)", "", "ไปจุดเชื่อม"])
        for (r, cells) in rows.enumerated() {
            let y = y0 - Double(r) * rh
            dxf.line(L.table, (x0, y), (x0 + w, y))
            for (c, t) in cells.enumerated() where !t.isEmpty {
                dxf.text(L.table, (x0 + cols[c] + 0.08, y - rh / 2), height: th, t, middle: true)
            }
        }
        let bottom = y0 - Double(rows.count) * rh
        dxf.line(L.table, (x0, bottom), (x0 + w, bottom))
        for x in cols { dxf.line(L.table, (x0 + x, y0), (x0 + x, bottom)) }

        var notes = ["หมายเหตุ / Notes",
                     "1. หน่วยเป็นเมตร มาตราส่วนจริง (DETAIL ขยาย 5 เท่า) / Metres, real scale.",
                     "2. เสาเหล็ก □75×75 บนแผ่นเหล็ก 150×150 พุก 4 ตัว ตาม DETAIL ทุกต้น ตั้งบนฐานคอนกรีต 0.20 × \(fmt(pad)) ม.",
                     "3. ตู้ไฟฟ้าแขวนขอบบนที่ \(fmt(rackTop)) ม. อินเวอร์เตอร์ขอบบนที่ \(fmt(inverterTop)) ม. ขนาดตามแคตตาล็อก \(s.catalog.version)"]
        if g.outdoor {
            notes.append("4. หลังคาเมทัลชีทลาดหน้า \(fmt(g.high)) → หลัง \(fmt(g.low)) ม. คาน จันทัน ลึก \(fmt(beamDepth)) ม. แป \(fmt(purlin)) ม. ชิ้นส่วนตาม MEMBER SCHEDULE")
        }
        if !s.measured { notes.append("\(notes.count). ยังไม่ได้วัดพื้นที่ ก × ย: แสดงขนาดขั้นต่ำ \(s.minimumText)") }
        if s.measured && !s.fits { notes.append("\(notes.count). พื้นที่จริงสั้นไป \(String(format: "%.2f", s.shortfall)) ม. สำหรับ \(s.sizes.count) เครื่อง") }
        if !s.walkwayOK { notes.append("\(notes.count). ทางเดินหน้าตู้ \(String(format: "%.2f", s.walkway)) ม. แคบกว่า \(fmt(InverterStation.minWalkway)) ม.") }
        for (i, n) in notes.enumerated() {
            dxf.text(L.text, (x0, bottom - 0.45 - Double(i) * 0.26), height: i == 0 ? 0.15 : 0.12, n)
        }

        // the base plate at 5 : 1 beside the schedule, its sizes in millimetres
        let k = 5.0, c = (x0 + w + 1.6, y0 - 0.9), half = plate / 2 * k, b = boltSpacing / 2 * k
        if !place(&dxf, "TCR_COLUMN_BASE_PLATE_DETAIL_PLAN", L.pad, at: (c.0 - half, c.1 - half), w: plate * k, h: plate * k) {
            dxf.insert(L.pad, basePlate(&dxf), at: c, scale: k)
        }
        dxf.dimension(L.dim, (c.0 - half, c.1 + half), (c.0 + half, c.1 + half), at: (0, c.1 + half + 0.45), vertical: false, text: mm(plate), height: dimH)
        dxf.dimension(L.dim, (c.0 - b, c.1 + half), (c.0 + b, c.1 + half), at: (0, c.1 + half + 0.22), vertical: false, text: mm(boltSpacing), height: dimH)
        dxf.dimension(L.dim, (c.0 + half, c.1 - half), (c.0 + half, c.1 + half), at: (c.0 + half + 0.45, 0), vertical: true, text: mm(plate), height: dimH)
        dxf.dimension(L.dim, (c.0 + half, c.1 - b), (c.0 + half, c.1 + b), at: (c.0 + half + 0.22, 0), vertical: true, text: mm(boltSpacing), height: dimH)
        dxf.dimension(L.dim, (c.0 - post / 2 * k, c.1 - half), (c.0 + post / 2 * k, c.1 - half), at: (0, c.1 - half - 0.25), vertical: false, text: mm(post), height: dimH)
        label(&dxf, (c.0 - half, c.1 - half - 0.6), ["เสาเหล็ก □75×75 (หนา 2.4 มม.)", "แผ่นเหล็กฐาน 150×150", "พุก / ANCHOR BOLT 4 ตัว ระยะ 105 มม."], h: 0.1)
        title(&dxf, (c.0 - half, c.1 - half - 1.25), "DETAIL ฐานเสา / BASE PLATE", "ขยาย 5 เท่า | หน่วย มม.")

        memberSchedule(&dxf, g, at: (x0 + w + 5.8, y0))
    }

    static let memberCols: [Double] = [0, 0.6, 3.8, 6.6, 7.6, 9.0]

    /// MEMBER SCHEDULE: each of the shelter's marks, what it is, its size, how many and their length together; its
    /// notes under it. Nothing for a station on a wall.
    static func memberSchedule(_ dxf: inout SketchDXF, _ g: Geometry, at o: (Double, Double)) {
        let list = members(g)
        guard !list.isEmpty else { return }
        let rh = 0.32, th = 0.12, cols = memberCols, w = cols[cols.count - 1]
        dxf.text(L.text, (o.0, o.1 + 0.3), height: 0.2, "ตารางชิ้นส่วนโครงสร้าง / MEMBER SCHEDULE")
        let rows = [["", "ชิ้นส่วน / Member", "ขนาด / Size", "จำนวน", "ยาวรวม (ม.)"]]
            + list.map { [$0.mark, $0.name, $0.size, "\($0.count)", String(format: "%.2f", $0.length)] }
        for (r, cells) in rows.enumerated() {
            let y = o.1 - Double(r) * rh
            dxf.line(L.table, (o.0, y), (o.0 + w, y))
            for (c, t) in cells.enumerated() where !t.isEmpty {
                dxf.text(L.table, (o.0 + cols[c] + 0.08, y - rh / 2), height: th, t, middle: true)
            }
        }
        let bottom = o.1 - Double(rows.count) * rh
        dxf.line(L.table, (o.0, bottom), (o.0 + w, bottom))
        for x in cols { dxf.line(L.table, (o.0 + x, o.1), (o.0 + x, bottom)) }
        let notes = ["1. ยาวรวมคิดจากศูนย์กลางถึงศูนย์กลาง เสาคิดจากแผ่นเหล็กฐาน / Lengths centre to centre; columns from their base plates.",
                     "2. ขนาดเหล็กตามแบบ: รอทีมออกแบบยืนยัน / Sections per the design, to be confirmed."]
        for (i, n) in notes.enumerated() { dxf.text(L.text, (o.0, bottom - 0.35 - Double(i) * 0.24), height: 0.11, n) }
    }
}
