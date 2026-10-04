import Foundation

/// C1's PV layout in metres from the plan's top-left (x along `spansX`, y along `spansY`): tables of `nS` rows down
/// each face from the eave and `nR` modules along the ridge, `gap` apart, with blocked modules where a skylight that
/// can't be covered, an obstacle or a keep-out zone overlaps. Worked out apart from the drawing, so the panel tab and
/// the counts don't build the whole plan; `RoofPlan` draws it.
public struct RoofPV: Sendable {
    /// Modules laid, and modules dropped by an area, in the order they are drawn (face, row down the slope, column).
    public var placed: [Box] = [], blocked: [Box] = []
    /// Outlines of the tables holding at least one module, 4 cm outside them.
    public var outlines: [Box] = []
    public var kWp = 0.0
    /// Tables (ชุด) holding at least one module; 0 when the field is continuous.
    public var tables = 0
    /// The gap between two tables along the ridge (from `a1` to `a2`), dimensioned at `c` across it.
    public var alongGap: (a1: Double, a2: Double, c: Double)?
    /// The gap between two tables down the slope (from `c1` to `c2` across the ridge), dimensioned at `a` along it.
    public var acrossGap: (c1: Double, c2: Double, a: Double)?
    public var count: Int { placed.count }

    // margins (m): module gap, eave, ridge, gable ends
    static let gp = 0.02, seE = 0.5, seR = 0.3, seG = 0.5

    public init(_ v: Values, portrait: Bool? = nil, module: RoofPlan.Module = .catalogDefault) {
        let xs = Roof.spans(v, .x), ys = Roof.spans(v, .y), hor = Roof.ridge(v) == .h
        let portrait = portrait ?? Roof.pvPortrait(v)
        let Lx = xs.reduce(0, +), Ly = ys.reduce(0, +)
        let gp = Self.gp, seE = Self.seE
        let La = hor ? Lx : Ly, Lc = hor ? Ly : Lx, cs = cos(Roof.frame(v).slope * .pi / 180)
        let msl = portrait ? module.length : module.width, mwd = portrait ? module.width : module.length
        let nS = Roof.pvRows(v), nR = Roof.pvPerTable(v, portrait: portrait), gap = Roof.pvGap(v)
        let us = (Lc / 2) / cs - seE - Self.seR
        let pS = nS > 0 ? Double(nS) * (msl + gp) - gp + gap : 0, pR = nR > 0 ? Double(nR) * (mwd + gp) - gp + gap : 0
        let GS = nS > 0 ? max(0, Int(floor((us + gap) / pS))) : 0, GR = nR > 0 ? max(0, Int(floor((La - 2 * Self.seG + gap) / pR))) : 0
        let rows = nS > 0 ? GS * nS : max(0, Int(floor((us + gp) / (msl + gp))))
        let cols = nR > 0 ? GR * nR : max(0, Int(floor((La - 2 * Self.seG + gp) / (mwd + gp))))
        let rowW = nR > 0 ? Double(GR) * (pR - gap) + Double(max(0, GR - 1)) * gap : Double(cols) * (mwd + gp) - gp
        let off = (La - rowW) / 2
        func aOf(_ c: Int) -> Double { nR > 0 ? off + Double(c / nR) * pR + Double(c % nR) * (mwd + gp) : off + Double(c) * (mwd + gp) }
        func sOf(_ r: Int) -> Double { nS > 0 ? seE + Double(r / nS) * pS + Double(r % nS) * (msl + gp) : seE + Double(r) * (msl + gp) }
        // blocked areas as (a1, a2, c1, c2) along / across the ridge
        var obs: [(Double, Double, Double, Double)] = []
        for a in Roof.areas(v) where !(a.kind == Roof.skylightKind && a.canCover) {
            let e = a.kind == Roof.skylightKind ? 0.1 : 0
            obs.append(hor ? (a.x - e, a.x + a.w + e, a.y, a.y + a.h) : (a.y - e, a.y + a.h + e, a.x, a.x + a.w))
        }
        /// Along / across the ridge from down-the-slope distances on `face` (1 = the far face, measured from the far eave).
        func box(_ a1: Double, _ a2: Double, _ s1: Double, _ s2: Double, _ face: Int) -> (Double, Double, Double, Double) {
            var c1 = s1 * cs, c3 = s2 * cs
            if face == 1 { (c1, c3) = (Lc - c3, Lc - c1) }
            return (a1, a2, c1, c3)
        }
        func metres(_ b: (Double, Double, Double, Double)) -> Box {
            hor ? Box(b.0, b.2, b.1 - b.0, b.3 - b.2) : Box(b.2, b.0, b.3 - b.2, b.1 - b.0)
        }
        var used = Set<String>()
        for face in 0..<2 {
            for r in 0..<rows {
                for c in 0..<cols {
                    let a1 = aOf(c), s1 = sOf(r), b = box(a1, a1 + mwd, s1, s1 + msl, face)
                    if obs.contains(where: { b.1 > $0.0 && b.0 < $0.1 && b.3 > $0.2 && b.2 < $0.3 }) { blocked.append(metres(b)); continue }
                    placed.append(metres(b))
                    used.insert("\(face)-\(nS > 0 ? r / nS : r)-\(nR > 0 ? c / nR : 0)")
                }
            }
        }
        kWp = Double(placed.count) * module.kW
        guard nS > 0 || nR > 0 else { return }
        tables = used.count
        let rgN = nS > 0 ? GS : rows, cgN = nR > 0 ? GR : 1
        if cols > 0 && rows > 0 {
            for face in 0..<2 {
                for g in 0..<rgN {
                    for h in 0..<cgN where used.contains("\(face)-\(g)-\(h)") {
                        let s1 = nS > 0 ? seE + Double(g) * pS : sOf(g), s2 = s1 + (nS > 0 ? Double(nS) * (msl + gp) - gp : msl)
                        let a1 = nR > 0 ? off + Double(h) * pR : off, a2 = a1 + (nR > 0 ? Double(nR) * (mwd + gp) - gp : rowW)
                        outlines.append(metres(box(a1 - 0.04, a2 + 0.04, s1 - 0.04, s2 + 0.04, face)))
                    }
                }
            }
        }
        if nR > 0 && GR > 1 && rows > 0 {
            alongGap = (off + Double(nR) * (mwd + gp) - gp, off + pR, Lc - (sOf(rows - 1) + msl) * cs - 0.3)
        }
        if nS > 0 && GS > 1 {
            acrossGap = (Lc - (seE + Double(nS) * (msl + gp) - gp) * cs, Lc - (seE + pS) * cs, off + rowW + 0.3)
        }
    }
}
