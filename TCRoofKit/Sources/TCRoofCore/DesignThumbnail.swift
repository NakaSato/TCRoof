import Foundation

/// A standard design's small plan for its card in the pickers (docs/specs/standard-designs.md §3.1): the outline, the
/// bays and each item as a mark, without numbers. The long side is `size` units.
public enum DesignThumbnail {
    public struct Mark: Sendable {
        public enum Kind: Sendable { case vent, hatch, ladder, pipe, skylight, obstacle }
        public var kind: Kind
        public var box: Box
        public init(_ kind: Kind, _ box: Box) { self.kind = kind; self.box = box }
    }

    static let outline = RGBA(hex: 0x1F3A5F), grid = RGBA(hex: 0xC9D3E0)

    public static func sketch(xs: [Double], ys: [Double], marks: [Mark], size: Double = 120) -> Sketch? {
        let tw = xs.reduce(0, +), th = ys.reduce(0, +)
        guard tw > 0, th > 0 else { return nil }
        let pad = 4.0, k = (size - 2 * pad) / max(tw, th)
        let w = tw * k, h = th * k
        func P(_ x: Double, _ y: Double) -> Pt { Pt(pad + x * k, pad + y * k) }
        var o: [DrawOp] = [.rect(Box(0, 0, w + 2 * pad, h + 2 * pad), stroke: nil, fill: .white)]
        var x = 0.0
        for s in xs.dropLast() { x += s; o.append(.line(P(x, 0), P(x, th), width: 0.4, color: grid)) }
        var y = 0.0
        for s in ys.dropLast() { y += s; o.append(.line(P(0, y), P(tw, y), width: 0.4, color: grid)) }
        for m in marks {
            // at least 2 units, so a pipe on a 64 m tank still shows
            let b = Box(pad + m.box.x * k, pad + m.box.y * k, max(2, m.box.w * k), max(2, m.box.h * k))
            switch m.kind {
            case .vent: o.append(.rect(b, stroke: nil, fill: outline))
            case .hatch: o.append(.rect(b, stroke: outline, fill: RGBA(hex: 0x9CC3E6), width: 0.6))
            case .ladder: o.append(.rect(b, stroke: nil, fill: RGBA(hex: 0xE08A1E)))
            case .pipe: o.append(.circle(Pt(b.x + b.w / 2, b.y + b.h / 2), r: max(b.w, b.h) / 2, stroke: nil, fill: RGBA(hex: 0x2E7D32)))
            case .skylight: o.append(.rect(b, stroke: RGBA(hex: 0x5B9BD5), fill: RGBA(hex: 0xD6E8F7), width: 0.6))
            case .obstacle: o.append(.rect(b, stroke: nil, fill: RGBA(hex: 0xB42318)))
            }
        }
        o.append(.rect(Box(pad, pad, w, h), stroke: outline, fill: nil, width: 1.2))
        return Sketch(width: w + 2 * pad, height: h + 2 * pad, ops: o)
    }

    /// The marks of a plan's obstacles (metres from its top-left).
    public static func marks(_ list: [Obstacle]) -> [Mark] {
        list.compactMap { o in
            guard let x = NumberInput.value(o.x), let y = NumberInput.value(o.y), let w = NumberInput.value(o.w), let h = NumberInput.value(o.h) else { return nil }
            let kind: Mark.Kind = switch o.kind {
            case TankPoints.vent: .vent
            case TankPoints.hatch: .hatch
            case TankPoints.ladder: .ladder
            case TankPoints.pipe: .pipe
            case Roof.skylightKind: .skylight
            default: .obstacle
            }
            return Mark(kind, Box(x, y, w, h))
        }
    }
}
