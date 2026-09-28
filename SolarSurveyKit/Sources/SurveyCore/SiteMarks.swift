import Foundation

/// Symbols engineers place on the site picture (ภาพสถานที่ติดตั้ง).
public enum MarkKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case meter, trafo, mdb, inv, water, office
    public var id: String { rawValue }
    /// Label printed next to the symbol, as on the company's site drawings.
    public var title: String {
        switch self {
        case .meter: return "PEA METER"
        case .trafo: return "TRANSFORMER"
        case .mdb: return "MDB"
        case .inv: return "INVERTER STATION"
        case .water: return "WATER CONNECTION POINT"
        case .office: return "SITE OFFICE"
        }
    }
    /// Unit of the rating written under the symbol (transformer kVA, MDB main breaker AT); nil = no rating.
    public var unit: String? {
        switch self { case .trafo: return "kVA"; case .mdb: return "AT"; default: return nil }
    }
    /// Short code inside the round symbol.
    public var badge: String {
        switch self {
        case .meter: return "M"
        case .trafo: return "TR"
        case .mdb: return "MDB"
        case .inv: return "INV"
        case .water: return "W"
        case .office: return "SO"
        }
    }
    public var color: RGBA {
        switch self {
        case .meter: return RGBA(hex: 0x7B2CBF)
        case .trafo: return RGBA(hex: 0xD62828)
        case .mdb: return RGBA(hex: 0xE36414)
        case .inv: return RGBA(hex: 0x1D4ED8)
        case .water: return RGBA(hex: 0x0891B2)
        case .office: return RGBA(hex: 0x15803D)
        }
    }
    /// SF Symbol for the editor toolbar.
    public var symbol: String {
        switch self {
        case .meter: return "gauge.with.dots.needle.33percent"
        case .trafo: return "bolt.fill"
        case .mdb: return "rectangle.split.3x3"
        case .inv: return "bolt.batteryblock.fill"
        case .water: return "drop.fill"
        case .office: return "house.fill"
        }
    }
}

/// One symbol on the picture; x and y are fractions (0…1) of the picture's width and height.
public struct MapMark: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: MarkKind
    public var x: Double
    public var y: Double
    /// Rating shown under the symbol: kVA for a transformer, AT for an MDB.
    public var value: String = ""
    public init(id: UUID = UUID(), kind: MarkKind, x: Double, y: Double, value: String = "") {
        self.id = id; self.kind = kind; self.x = min(max(x, 0), 1); self.y = min(max(y, 0), 1); self.value = value
    }
    enum CodingKeys: String, CodingKey { case id, kind, x, y, value }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(MarkKind.self, forKey: .kind)
        x = try c.decode(Double.self, forKey: .x); y = try c.decode(Double.self, forKey: .y)
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
    }
    /// "800 kVA", "1250 AT", or "" when there is nothing to show.
    public var rating: String {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, let u = kind.unit else { return "" }
        return v.hasSuffix(u) ? v : "\(v) \(u)"
    }
}

public enum SiteMarks {
    /// "TRANSFORMER 2" when a kind is placed more than once, otherwise just the kind's title.
    public static func labels(_ marks: [MapMark]) -> [UUID: String] {
        var seen: [MarkKind: Int] = [:], out: [UUID: String] = [:]
        let totals = Dictionary(grouping: marks, by: \.kind).mapValues(\.count)
        for m in marks {
            let n = (seen[m.kind] ?? 0) + 1; seen[m.kind] = n
            out[m.id] = (totals[m.kind] ?? 0) > 1 ? "\(m.kind.title) \(n)" : m.kind.title
        }
        return out
    }

    /// Formal drawing symbols (black line work on white, IEC-style) centred on each marked point, no labels.
    /// Sizes scale with the picture's width. The names appear once, in `legend`.
    public static func ops(_ marks: [MapMark], in box: Box) -> [DrawOp] {
        let R = max(6, box.w * 0.019)
        return marks.flatMap { m -> [DrawOp] in
            let c = Pt(box.x + m.x * box.w, box.y + m.y * box.h)
            var o = symbol(m.kind, at: c, radius: R)
            let r = m.rating
            if !r.isEmpty {   // rating tag under the symbol
                let fs = R * 0.72, w = ApproxText.width(r, size: fs, bold: true) + fs * 0.8, h = fs * 1.5
                let tag = Box(c.x - w / 2, c.y + R * 1.12, w, h)
                o.append(.rect(tag, stroke: m.kind.color, fill: .white, width: max(0.5, R * 0.1)))
                o.append(.text(r, at: Pt(c.x, tag.y + h / 2), size: fs, bold: true, color: m.kind.color, align: .center))
            }
            return o
        }
    }

    /// Suggested rating for a new symbol from the job's transformer / MDB answers (n-th transformer → its kVA, n-th MDB → n-th breaker size).
    public static func suggestedValue(_ kind: MarkKind, existing: [MapMark], trafos: [Transformer]) -> String {
        let n = existing.filter { $0.kind == kind }.count
        switch kind {
        case .trafo: return n < trafos.count ? trafos[n].kva : ""
        case .mdb:
            let all = trafos.flatMap { $0.mdb }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return n < all.count ? all[n] : ""
        default: return ""
        }
    }

    public static let ink = RGBA(hex: 0x111111)

    /// One symbol on a 20-unit grid (radius 10), drawn the same way as the web version's SVG.
    public static func symbol(_ k: MarkKind, at c: Pt, radius R: Double) -> [DrawOp] {
        let u = R / 10, w = 1.7 * u, ink = k.color
        func P(_ x: Double, _ y: Double) -> Pt { Pt(c.x + x * u, c.y + y * u) }
        func circle(_ x: Double, _ r: Double, fill: RGBA? = .white, stroke: Bool = true) -> DrawOp {
            .circle(P(x, 0), r: r * u, stroke: stroke ? ink : nil, fill: fill, width: w)
        }
        func poly(_ pts: [(Double, Double)], fill: RGBA?, stroke: Bool) -> DrawOp {
            .polygon(pts.map { P($0.0, $0.1) }, stroke: stroke ? ink : nil, fill: fill, width: w)
        }
        func line(_ pts: [(Double, Double)]) -> [DrawOp] {
            zip(pts, pts.dropFirst()).map { a, b in .line(P(a.0, a.1), P(b.0, b.1), width: w, color: ink) }
        }
        switch k {
        case .meter:   // kWh meter
            return [circle(0, 10), .text("kWh", at: c, size: 6.2 * u, bold: true, color: ink, align: .center)]
        case .trafo:   // two-winding transformer
            return [circle(-3.8, 6.2, stroke: false), circle(3.8, 6.2, stroke: false),
                    circle(-3.8, 6.2, fill: nil), circle(3.8, 6.2, fill: nil)]
        case .mdb:     // distribution board
            return [poly([(-8.5, -6), (8.5, -6), (8.5, 6), (-8.5, 6)], fill: .white, stroke: true),
                    poly([(8.5, -6), (8.5, 6), (-8.5, 6)], fill: ink, stroke: false)]
        case .inv:     // inverter: DC = / AC ~
            let wave: [(Double, Double)] = [(1.6, 3.6), (2.15, 2.65), (2.7, 2.5), (3.25, 2.95), (3.8, 3.6), (4.35, 4.25), (4.9, 4.7), (5.45, 4.55), (6, 3.6)]
            return [poly([(-8, -8), (8, -8), (8, 8), (-8, 8)], fill: .white, stroke: true)]
                + line([(-8, 8), (8, -8)]) + line([(-6, -4.6), (-1.6, -4.6)]) + line([(-6, -2.2), (-1.6, -2.2)]) + line(wave)
        case .water:   // valve in a circle: water connection point
            return [circle(0, 10), poly([(-6, -4), (-6, 4), (0, 0)], fill: ink, stroke: false), poly([(6, -4), (6, 4), (0, 0)], fill: ink, stroke: false)]
                + line([(0, 0), (0, -6)]) + line([(-2.5, -6), (2.5, -6)])
        case .office:  // site office building
            return [poly([(-8, 8), (-8, -1.5), (0, -9), (8, -1.5), (8, 8)], fill: .white, stroke: true),
                    poly([(-1.8, 8), (-1.8, 3), (1.8, 3), (1.8, 8)], fill: ink, stroke: false)]
        }
    }

    /// Kinds in use, in legend order.
    public static func usedKinds(_ marks: [MapMark]) -> [MarkKind] { MarkKind.allCases.filter { k in marks.contains { $0.kind == k } } }

    /// One-line legend ("symbol NAME   symbol NAME …") across `box`, wrapping to a second line if needed.
    public static func legend(_ kinds: [MarkKind], in box: Box, size fs: Double = 7.5) -> [DrawOp] {
        guard !kinds.isEmpty else { return [] }
        var o: [DrawOp] = [.rect(box, stroke: ink, fill: .white, width: 0.5)]
        let R = fs * 0.75, lineH = fs * 2
        var x = box.x + 6, y = box.y + lineH / 2
        for k in kinds {
            let w = 2 * R + 4 + ApproxText.width(k.title, size: fs) + 12
            if x + w > box.maxX && x > box.x + 6 { x = box.x + 6; y += lineH }
            o += symbol(k, at: Pt(x + R, y), radius: R)
            o.append(.text(k.title, at: Pt(x + 2 * R + 4, y), size: fs, color: ink))
            x += w
        }
        return o
    }
    /// Height `legend` needs for these kinds at this width.
    public static func legendHeight(_ kinds: [MarkKind], width: Double, size fs: Double = 7.5) -> Double {
        guard !kinds.isEmpty else { return 0 }
        let R = fs * 0.75, lineH = fs * 2
        var x = 6.0, lines = 1
        for k in kinds {
            let w = 2 * R + 4 + ApproxText.width(k.title, size: fs) + 12
            if x + w > width && x > 6 { x = 6; lines += 1 }
            x += w
        }
        return Double(lines) * lineH
    }
}
