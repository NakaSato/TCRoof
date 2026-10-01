import Foundation

/// Lines and areas drawn on the site picture (A2), next to the placed symbols.
public enum ShapeKind: String, Codable, CaseIterable, Sendable {
    /// Where the panels go: closed polygon, red outline.
    case panelArea
    /// AC/DC cable route (underground or pipe rack): open polyline.
    case cableRoute
    /// Two points and the distance between them.
    case measure
    /// Crane entrance: dashed orange arrow from the first point to the second.
    case craneEntry
    /// Something shading the panels: closed polygon, orange hatching, with a label.
    case shade
    /// B2 inverter area drawn on its boundary photo: closed polygon, dashed teal, a length chip on each edge.
    case boundary

    /// Points needed before the shape is complete; nil = as many as the engineer taps (at least `minPoints`).
    public var fixedPoints: Int? { self == .measure || self == .craneEntry ? 2 : nil }
    public var minPoints: Int { self == .cableRoute || fixedPoints != nil ? 2 : 3 }
    public var isClosed: Bool { self == .panelArea || self == .shade || self == .boundary }
    /// The LIST item (`Options.list`) drawing this shape ticks.
    public var listItem: String? {
        switch self {
        case .panelArea: return Options.list[0]
        case .cableRoute: return Options.list[5]
        default: return nil
        }
    }
    public var color: RGBA {
        switch self {
        case .panelArea: return RGBA(hex: 0xD62828)
        case .cableRoute: return RGBA(hex: 0x16325C)
        case .measure: return RGBA(hex: 0x16325C)
        case .craneEntry, .shade: return RGBA(hex: 0xE36414)
        case .boundary: return RGBA(hex: 0x27A99A)
        }
    }
}

/// A point as fractions (0…1) of the picture's width and height, like `MapMark`.
public struct ShapePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = min(max(x, 0), 1); self.y = min(max(y, 0), 1) }
}

public struct SiteShape: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ShapeKind
    public var points: [ShapePoint]
    /// Text drawn with the shape ("ร่มเงาต้นไม้", "ทางเข้าเครน"); measurements show their length instead.
    public var label: String
    /// Typed length (m) of each edge, edge i running from point i to i + 1 (B2 boundary); "" where not typed.
    public var edges: [String]
    public init(id: UUID = UUID(), kind: ShapeKind, points: [ShapePoint], label: String = "", edges: [String] = []) {
        self.id = id; self.kind = kind; self.points = points; self.label = label; self.edges = edges
    }
    enum CodingKeys: String, CodingKey { case id, kind, points, label, edges }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(ShapeKind.self, forKey: .kind)
        points = try c.decodeIfPresent([ShapePoint].self, forKey: .points) ?? []
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        edges = try c.decodeIfPresent([String].self, forKey: .edges) ?? []
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind); try c.encode(points, forKey: .points); try c.encode(label, forKey: .label)
        if !edges.isEmpty { try c.encode(edges, forKey: .edges) }
    }
    /// Midpoint of edge i (closed shapes wrap to the first point).
    public func edgeMid(_ i: Int) -> ShapePoint? {
        guard points.count >= 2, i >= 0, i < (kind.isClosed ? points.count : points.count - 1) else { return nil }
        let a = points[i], b = points[(i + 1) % points.count]
        return ShapePoint((a.x + b.x) / 2, (a.y + b.y) / 2)
    }
}

public enum SiteShapes {
    /// Values key of the drawn shapes; not a schema field, so A2's completion is unchanged.
    public static let key = "siteShapes"
    /// Values key of the metres the picture's full width covers (from the map zoom, or set by measuring a drone photo).
    public static let scaleKey = "siteScale"
    /// Values key of where the picture came from: "google" or "drone".
    public static let sourceKey = "siteSource"

    /// Length of a measure line in metres, given the picture's aspect (width / height) and the metres across its width.
    public static func length(_ s: SiteShape, aspect: Double, metersAcross: Double) -> Double? {
        guard s.points.count >= 2, aspect > 0, metersAcross > 0 else { return nil }
        let a = s.points[0], b = s.points[1]
        return hypot(b.x - a.x, (b.y - a.y) / aspect) * metersAcross
    }

    /// "38.8 ม." (one decimal below 100 m).
    public static func meters(_ m: Double) -> String {
        m < 100 ? String(format: "%.1f ม.", m) : String(format: "%.0f ม.", m)
    }

    /// Drawing of the shapes over a picture occupying `box`; `metersAcross` labels measurements.
    public static func ops(_ shapes: [SiteShape], in box: Box, metersAcross: Double?) -> [DrawOp] {
        let w = max(1.2, box.w * 0.004), fs = max(6, box.w * 0.016)
        func P(_ p: ShapePoint) -> Pt { Pt(box.x + p.x * box.w, box.y + p.y * box.h) }
        var o: [DrawOp] = []
        // areas first, lines on top
        for s in shapes.sorted(by: { $0.kind.isClosed && !$1.kind.isClosed }) {
            let pts = s.points.map(P)
            guard pts.count >= 2 else { continue }
            let col = s.kind.color
            switch s.kind {
            case .panelArea:
                o.append(.polygon(pts, stroke: col, fill: RGBA(col.r, col.g, col.b, 0.08), width: w * 1.3))
            case .shade:
                o += hatch(pts, color: RGBA(col.r, col.g, col.b, 0.75), spacing: fs * 0.7, width: w * 0.7)
                o.append(.polygon(pts, stroke: col, fill: nil, width: w))
                if !s.label.isEmpty { o += SiteMarks.nameTag(s.label, at: centroid(pts), size: fs * 0.8, color: col) }
            case .cableRoute:
                o += zip(pts, pts.dropFirst()).map { .line($0, $1, width: w * 1.2, color: col) }
            case .craneEntry:
                o += zip(pts, pts.dropFirst()).map { .line($0, $1, width: w * 1.4, color: col, dash: [w * 4, w * 2.5]) }
                o.append(arrowHead(from: pts[pts.count - 2], to: pts[pts.count - 1], size: fs * 1.1, color: col))
                o += SiteMarks.nameTag(s.label.isEmpty ? "ทางเข้าเครน" : s.label, at: Pt(pts[0].x, pts[0].y - fs * 1.4), size: fs * 0.75, color: col)
            case .boundary:
                o.append(.polygon(pts, stroke: nil, fill: RGBA(col.r, col.g, col.b, 0.10)))
                for (a, b) in zip(pts, pts.dropFirst() + [pts[0]]) { o.append(.line(a, b, width: w * 1.4, color: col, dash: [w * 5, w * 3])) }
                for i in pts.indices {
                    guard let e = s.edges[safe: i]?.trimmingCharacters(in: .whitespaces), !e.isEmpty, let m = s.edgeMid(i) else { continue }
                    let t = e + " ม.", tw = ApproxText.width(t, size: fs * 0.85, bold: true) + fs, th = fs * 1.5
                    let mid = Pt(box.x + m.x * box.w, box.y + m.y * box.h)
                    o.append(.rect(Box(mid.x - tw / 2, mid.y - th / 2, tw, th), stroke: nil, fill: col))
                    o.append(.text(t, at: mid, size: fs * 0.85, bold: true, color: .white, align: .center))
                }
            case .measure:
                let a = pts[0], b = pts[1]
                o.append(.line(a, b, width: w, color: col))
                // end ticks across the line
                let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 0.001), nx = -dy / len * fs * 0.5, ny = dx / len * fs * 0.5
                for e in [a, b] { o.append(.line(Pt(e.x - nx, e.y - ny), Pt(e.x + nx, e.y + ny), width: w, color: col)) }
                if let m = metersAcross, let l = length(s, aspect: box.h > 0 ? box.w / box.h : 1, metersAcross: m) {
                    let t = meters(l), tw = ApproxText.width(t, size: fs * 0.8, bold: true) + fs, th = fs * 1.4
                    let mid = Pt((a.x + b.x) / 2, (a.y + b.y) / 2 - th * 0.7)
                    o.append(.rect(Box(mid.x - tw / 2, mid.y - th / 2, tw, th), stroke: nil, fill: col))
                    o.append(.text(t, at: mid, size: fs * 0.8, bold: true, color: .white, align: .center))
                }
            }
        }
        return o
    }

    static func centroid(_ pts: [Pt]) -> Pt {
        Pt(pts.map(\.x).reduce(0, +) / Double(pts.count), pts.map(\.y).reduce(0, +) / Double(pts.count))
    }

    static func arrowHead(from a: Pt, to b: Pt, size s: Double, color: RGBA) -> DrawOp {
        let ang = atan2(b.y - a.y, b.x - a.x), spread = 0.45
        return .polygon([b, Pt(b.x - s * cos(ang - spread), b.y - s * sin(ang - spread)), Pt(b.x - s * cos(ang + spread), b.y - s * sin(ang + spread))],
                        stroke: nil, fill: color)
    }

    /// Diagonal hatching inside a polygon: each 45° line is cut where it crosses the outline (even-odd).
    static func hatch(_ pts: [Pt], color: RGBA, spacing: Double, width: Double) -> [DrawOp] {
        guard pts.count >= 3, spacing > 0 else { return [] }
        // lines x - y = t; t runs over the polygon's range
        let ts = pts.map { $0.x - $0.y }
        guard let lo = ts.min(), let hi = ts.max() else { return [] }
        var o: [DrawOp] = []
        var t = lo + spacing / 2
        while t < hi {
            var xs: [Double] = []
            for (a, b) in zip(pts, pts.dropFirst() + [pts[0]]) {
                let fa = a.x - a.y - t, fb = b.x - b.y - t
                if (fa < 0) != (fb < 0) {
                    let k = fa / (fa - fb)
                    xs.append(a.x + (b.x - a.x) * k)
                }
            }
            xs.sort()
            var i = 0
            while i + 1 < xs.count {
                o.append(.line(Pt(xs[i], xs[i] - t), Pt(xs[i + 1], xs[i + 1] - t), width: width, color: color))
                i += 2
            }
            t += spacing
        }
        return o
    }
}
