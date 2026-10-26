import Foundation

/// The mounting structure of each table on plan, for the printed plan (docs/specs/tank-mounting-layout.md §5, the
/// prototype's A3 sheet): a rafter (คานเอียง) up the slope at every post pair, four rails across the table, a rail
/// clamp where each rail crosses a rafter and one ground lug per table. The counts are the quantities' (`TableBOM`):
/// rafters = pairs, rail clamps = 4 × pairs, one lug.
extension TankLayout {
    public struct Structure: Sendable {
        /// Up the slope at each post pair, over the table's depth (tank metres).
        public var rafters: [(Pt, Pt)]
        /// Across the table, two per module row at ¼ and ¾ of the module, upper rail first.
        public var rails: [(Pt, Pt)]
        public var clamps: [Pt]
        /// At the upper rail's west end (the end of the first column).
        public var lug: Pt
    }

    /// Where the rails sit on a module, from its upper edge (share of its length on plan).
    static let railShares = [0.25, 0.75]

    public func structure(_ t: Table) -> Structure {
        let p = params, fr = Frame(q: turn, W: size.w, H: size.h)
        // the table in the layout's frame: the row runs along x, the slope down towards +y
        let b = fr.rect(TankPoints.Rect(x: t.x, y: t.y, w: t.w, h: t.h))
        let ys = (0..<2).flatMap { k in
            Self.railShares.map { b.y + Double(k) * (p.cellH + p.moduleGap * p.cosT) + $0 * p.cellH }
        }
        // one x per pair (front and back posts share it)
        let xs = stride(from: 0, to: t.posts.count, by: 2).map { fr.to(t.posts[$0].x, t.posts[$0].y).0 }
        func plan(_ x: Double, _ y: Double) -> Pt { let q = fr.from(x, y); return Pt(q.0, q.1) }
        return Structure(rafters: xs.map { (plan($0, b.y), plan($0, b.y + b.h)) },
                         rails: ys.map { (plan(b.x, $0), plan(b.x + b.w, $0)) },
                         clamps: ys.flatMap { y in xs.map { plan($0, y) } },
                         lug: plan(b.x, ys[0]))
    }
}
