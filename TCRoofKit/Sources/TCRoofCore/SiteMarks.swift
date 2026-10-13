import Foundation

/// Symbols engineers place on the site picture (ภาพสถานที่ติดตั้ง).
/// The first six are the original set; jobs may hold any of them, so none may be removed or renamed.
public enum MarkKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case meter, trafo, mdb, inv, water, office
    case zeroExport, meterSub, weather, roofLabel, stairs
    /// B5's FTS switch (Emergency) button, placed from B5 only (`ModuleMarks`); like `water`, not in A2's palette.
    case emergency
    public var id: String { rawValue }
    /// A2's symbol palette, in the design's order. `water` isn't offered any more but still shows where a job has it;
    /// `emergency` is placed from B5.
    public static let palette: [MarkKind] = [.meter, .zeroExport, .trafo, .mdb, .inv, .meterSub, .weather, .office, .roofLabel, .stairs]
    /// Palette name and hint (docs/ui/survey-a2).
    public var paletteTitle: String {
        switch self {
        case .meter: return "PEA METER"
        case .zeroExport: return "กันย้อน"
        case .trafo: return "หม้อแปลง"
        case .mdb: return "MDB"
        case .inv: return "INV"
        case .meterSub: return "M"
        case .weather: return "Weather"
        case .office: return "Site Office"
        case .roofLabel: return "ชื่อหลังคา"
        case .stairs: return "บันได"
        case .water: return "จุดเชื่อมน้ำ"
        case .emergency: return "ปุ่ม FTS switch"
        }
    }
    public var paletteDetail: String {
        switch self {
        case .meter: return "มิเตอร์ กฟภ."
        case .zeroExport: return "Zero Export"
        case .trafo: return "TX · kVA"
        case .mdb: return "ตู้ + AT"
        case .inv: return "อินเวอร์เตอร์"
        case .meterSub: return "มิเตอร์"
        case .weather: return "สถานีอากาศ"
        case .office: return "ป้ายกรอบแดง"
        case .roofLabel: return "+ ขอบเขตแดง"
        case .stairs: return "ทางขึ้นหลังคา"
        case .water: return "WATER CONNECTION POINT"
        case .emergency: return "Emergency"
        }
    }
    /// The LIST item (`Options.list`) placing this symbol ticks.
    public var listItem: String? {
        switch self {
        case .meter: return Options.list[7]
        case .zeroExport: return Options.list[3]
        case .trafo: return Options.list[8]
        case .mdb: return Options.list[6]
        case .inv: return Options.list[1]
        case .office: return Options.list[2]
        case .stairs: return Options.list[4]
        case .meterSub, .weather, .roofLabel, .water, .emergency: return nil
        }
    }
    /// Label printed next to the symbol, as on the company's site drawings.
    public var title: String {
        switch self {
        case .meter: return "PEA METER"
        case .trafo: return "TRANSFORMER"
        case .mdb: return "MDB"
        case .inv: return "INVERTER STATION"
        case .water: return "WATER CONNECTION POINT"
        case .office: return "SITE OFFICE"
        case .zeroExport: return "ZERO EXPORT"
        case .meterSub: return "METER"
        case .weather: return "WEATHER STATION"
        case .roofLabel: return "ROOF"
        case .stairs: return "STAIRS"
        case .emergency: return "FTS SWITCH (EMERGENCY)"
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
        case .zeroExport: return "ZE"
        case .meterSub: return "M"
        case .weather: return "WS"
        case .roofLabel: return "Aa"
        case .stairs: return "ST"
        case .emergency: return "E"
        }
    }
    /// Line and text colour, from the design's icon set (docs/ui/survey-a2/icons).
    public var color: RGBA {
        switch self {
        case .meter: return RGBA(hex: 0x74268F)
        case .trafo, .mdb, .stairs: return RGBA(hex: 0x4A4A4A)
        case .inv: return RGBA(hex: 0x1A1A1A)
        case .water: return RGBA(hex: 0x0891B2)
        case .office, .zeroExport, .weather, .roofLabel: return RGBA(hex: 0xE03A2F)
        case .meterSub: return RGBA(hex: 0x1BA7C9)
        case .emergency: return RGBA(hex: 0xD9453B)
        }
    }
    /// Image in TCRoofUI's `A2Icons` asset catalog (docs/ui/survey-a2/icons); nil = no icon in the design, use `symbol`.
    public var assetName: String? { self == .water || self == .emergency ? nil : "mark-" + rawValue }
    /// SF Symbol for the editor toolbar; the fallback where `assetName` is nil or missing.
    public var symbol: String {
        switch self {
        case .meter: return "gauge.with.dots.needle.33percent"
        case .trafo: return "bolt.fill"
        case .mdb: return "rectangle.split.3x3"
        case .inv: return "bolt.batteryblock.fill"
        case .water: return "drop.fill"
        case .office: return "house.fill"
        case .zeroExport: return "arrow.uturn.backward.circle"
        case .meterSub: return "m.circle"
        case .weather: return "cloud.sun"
        case .roofLabel: return "textformat"
        case .stairs: return "stairs"
        case .emergency: return "exclamationmark.octagon.fill"
        }
    }
}

/// One symbol on the picture; x and y are fractions (0…1) of the picture's width and height.
public struct MapMark: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: MarkKind
    public var x: Double
    public var y: Double
    /// Rating shown under the symbol: kVA for a transformer, AT for an MDB; "MV" / "LV" for a กันย้อน symbol (empty = MV).
    public var value: String = ""
    /// Name written on the picture ("TX 1", "หลังคาถังน้ำใส 1"); empty uses the kind's default.
    public var label: String = ""
    /// The section this point belongs to: a B3 water module's water point (`WaterPoint`). nil for A2's own symbols.
    public var module: UUID? = nil
    /// The A3 entry this transformer / MDB fills (`SiteSync`): "tr:<Transformer.id>" or "bd:<Board.id>". nil until the first sync.
    public var link: String? = nil
    public init(id: UUID = UUID(), kind: MarkKind, x: Double, y: Double, value: String = "", label: String = "", module: UUID? = nil, link: String? = nil) {
        self.id = id; self.kind = kind; self.x = min(max(x, 0), 1); self.y = min(max(y, 0), 1); self.value = value; self.label = label
        self.module = module; self.link = link
    }
    enum CodingKeys: String, CodingKey { case id, kind, x, y, value, label, module, link }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(MarkKind.self, forKey: .kind)
        x = try c.decode(Double.self, forKey: .x); y = try c.decode(Double.self, forKey: .y)
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        module = try c.decodeIfPresent(UUID.self, forKey: .module)
        link = try c.decodeIfPresent(String.self, forKey: .link)
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

    /// Drawing symbols centred on each marked point, with the job's own text: the name inside a transformer / MDB
    /// ("TX 1", "MDP-1"), a rating tag to its right, other names above. Sizes scale with the picture's width.
    public static func ops(_ marks: [MapMark], in box: Box) -> [DrawOp] {
        let R = max(6, box.w * 0.019)
        return marks.flatMap { m -> [DrawOp] in
            let c = Pt(box.x + m.x * box.w, box.y + m.y * box.h)
            let name = m.label.trimmingCharacters(in: .whitespaces)
            // roof names and the site office are their own labels: red text in a red frame
            if m.kind == .roofLabel { return nameTag(name.isEmpty ? "หลังคา" : name, at: c, size: R * 1.05, color: m.kind.color) }
            if m.kind == .office { return nameTag(name.isEmpty ? "Site Office" : name, at: c, size: R * 1.05, color: m.kind.color) }
            let inside = m.kind == .trafo || m.kind == .mdb
            let text = inside ? (name.isEmpty ? defaultLabel(m, in: marks) : name) : m.kind == .zeroExport ? zeroExportLine(m) : nil
            var o = symbol(m.kind, at: c, radius: R, text: text)
            if !inside && !name.isEmpty {   // the engineer's own name above the symbol
                o += nameTag(name, at: Pt(c.x, c.y - R * 1.9), size: R * 0.7, color: m.kind.color)
            }
            let r = m.rating
            if !r.isEmpty {   // rating tag right of the symbol
                let fs = R * 0.72, w = ApproxText.width(r, size: fs, bold: false) + fs * 1.2, h = fs * 1.7
                let tag = Box(c.x + R * 1.15, c.y - h / 2, w, h)
                o.append(.rect(tag, stroke: m.kind.color, fill: .white, width: max(0.5, R * 0.08)))
                o.append(.text(r, at: Pt(tag.x + w / 2, c.y), size: fs, color: ink, align: .center))
            }
            return o
        }
    }

    /// Text in a white box framed in the symbol's colour, centred on `c`.
    static func nameTag(_ s: String, at c: Pt, size fs: Double, color: RGBA) -> [DrawOp] {
        let w = ApproxText.width(s, size: fs, bold: false) + fs * 1.2, h = fs * 1.7
        let b = Box(c.x - w / 2, c.y - h / 2, w, h)
        return [.rect(b, stroke: color, fill: .white, width: max(0.6, fs * 0.1)),
                .text(s, at: c, size: fs, color: color, align: .center)]
    }

    /// The third line of a กันย้อน symbol: "MV" or "LV".
    public static func zeroExportLine(_ m: MapMark) -> String {
        m.value.trimmingCharacters(in: .whitespaces).uppercased() == "LV" ? "LV" : "MV"
    }

    /// Name shown on the picture when the engineer hasn't typed one: "TX 1", "MDB-2", "INV"…
    public static func defaultLabel(_ m: MapMark, in marks: [MapMark]) -> String {
        let same = marks.filter { $0.kind == m.kind }
        let n = (same.firstIndex { $0.id == m.id } ?? 0) + 1
        switch m.kind {
        case .trafo: return "TX \(n)"
        case .mdb: return same.count > 1 ? "MDB-\(n)" : "MDB"
        case .inv: return same.count > 1 ? "INV \(n)" : "INV"
        case .roofLabel: return "หลังคา \(n)"
        default: return m.kind.paletteTitle
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

    public static let ink = RGBA(hex: 0x1A1A1A)

    /// One symbol of outer radius `R`, drawn as vectors from the design's icons (docs/ui/survey-a2/icons/svg/symbols:
    /// 34-unit box, circle r 15). `text` replaces the name inside a transformer / MDB ("TX 1", "MDP-1"), or a กันย้อน's "MV" / "LV".
    public static func symbol(_ k: MarkKind, at c: Pt, radius R: Double, text: String? = nil) -> [DrawOp] {
        let u = R / 15, col = k.color
        // SVG coordinates, centre (17, 17)
        func P(_ x: Double, _ y: Double) -> Pt { Pt(c.x + (x - 17) * u, c.y + (y - 17) * u) }
        func circle(_ r: Double, fill: RGBA, stroke: RGBA, width: Double) -> DrawOp { .circle(c, r: r * u, stroke: stroke, fill: fill, width: width * u) }
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, stroke: RGBA, width: Double) -> DrawOp {
            .rect(Box(c.x + (x - 17) * u, c.y + (y - 17) * u, w * u, h * u), stroke: stroke, fill: .white, width: width * u)
        }
        func line(_ a: (Double, Double), _ b: (Double, Double), _ color: RGBA, _ width: Double) -> DrawOp {
            .line(P(a.0, a.1), P(b.0, b.1), width: width * u, color: color)
        }
        /// Text on an SVG baseline `y`; DrawOp anchors at the line's vertical centre.
        func label(_ s: String, _ y: Double, _ size: Double, _ color: RGBA, bold: Bool = false) -> DrawOp {
            .text(s, at: P(17, y - size * 0.35), size: size * u, bold: bold, color: color, align: .center)
        }
        /// Shrinks a job's name to fit the circle's inner width.
        func fitted(_ s: String, _ size: Double) -> Double {
            min(size, size * 25 / max(1, ApproxText.width(s, size: size)))
        }
        switch k {
        case .meter:
            return [circle(15, fill: col, stroke: .white, width: 1.3), label("PEA", 15.7, 7, .white, bold: true), label("METER", 23.3, 7, .white, bold: true)]
        case .zeroExport:
            return [circle(15, fill: .white, stroke: col, width: 1.6), label("ZERO", 12.8, 5.6, col), label("EXPORT", 19, 5.6, col), label(text ?? "MV", 25.2, 5.6, col)]
        case .trafo, .mdb:
            let s = text ?? (k == .trafo ? "TX" : "MDB"), size = fitted(s, k == .trafo ? 9 : 8.5)
            return [circle(15, fill: .white, stroke: col, width: 1.3), .text(s, at: c, size: size * u, color: ink, align: .center)]
        case .inv:
            return [rect(11, 3, 12, 28, stroke: ink, width: 1.3), .text("INV", at: c, size: 8 * u, color: ink, align: .center, angle: -90)]
        case .meterSub:
            return [circle(15, fill: .white, stroke: col, width: 1.3), label("M", 22.4, 15, col)]
        case .weather:
            return [circle(11, fill: .white, stroke: col, width: 1.6),
                    line((17, 10), (17, 24), col, 1.5), line((10, 19), (24, 19), col, 1.5), line((12, 13), (22, 13), col, 1.5)]
        case .office, .roofLabel:
            return [rect(1, 9, 32, 16, stroke: col, width: 1.5), label("Aa", 20, 10, col)]
        case .stairs:
            return [rect(1, 1, 32, 32, stroke: col, width: 1.3), line((12, 6), (12, 28), ink, 1.5), line((22, 6), (22, 28), ink, 1.5)]
                + [10.0, 15, 20, 25].map { y in line((12, y), (22, y), ink, 1.5) }
        case .water:   // not in the design's set: valve in a circle, on the old 20-unit grid
            let v = R / 10, w = 1.7 * v
            func Q(_ x: Double, _ y: Double) -> Pt { Pt(c.x + x * v, c.y + y * v) }
            return [.circle(c, r: R, stroke: col, fill: .white, width: w),
                    .polygon([Q(-6, -4), Q(-6, 4), Q(0, 0)], stroke: nil, fill: col, width: w),
                    .polygon([Q(6, -4), Q(6, 4), Q(0, 0)], stroke: nil, fill: col, width: w),
                    .line(Q(0, 0), Q(0, -6), width: w, color: col), .line(Q(-2.5, -6), Q(2.5, -6), width: w, color: col)]
        case .emergency:   // docs/ui/survey-b5/icons/b5-fts-pin.svg on its 44-unit grid, r 21 = R
            let v = R / 21
            return [.circle(c, r: 21 * v, stroke: emergencyHalo, fill: RGBA(0.941, 0.549, 0, 0.18), width: 3 * v),
                    .circle(c, r: 13 * v, stroke: col, fill: .white, width: 4 * v),
                    .circle(c, r: 5.5 * v, stroke: nil, fill: col)]
        }
    }

    /// The orange halo round the FTS switch pin.
    public static let emergencyHalo = RGBA(hex: 0xF08C00)

    /// Kinds in use, in legend order.
    /// Roof names label themselves, so they stay out of the legend.
    public static func usedKinds(_ marks: [MapMark]) -> [MarkKind] {
        MarkKind.allCases.filter { k in k != .roofLabel && marks.contains { $0.kind == k } }
    }

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
