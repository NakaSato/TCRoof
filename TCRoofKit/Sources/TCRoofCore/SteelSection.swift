import Foundation

/// A steel section read from a member size as entered on C1 ("C-100x50x20x3.2", "□-100x100x3.2", "ท่อกลม Ø1\" หนา 1.6"),
/// with its mass per metre for the member schedule's estimate (docs/specs/auto-drawing.md §4.4).
///
/// Mass = area × 7,850 kg/m³. Areas follow the method of the published tables (JIS G 3350 / มอก. 1228 lipped channel,
/// JIS G 3466 / มอก. 107 square and rectangular tube, JIS G 3444 / มอก. 107 round pipe, JIS G 3192 H and I):
/// - **Cold formed (C, 2C, □):** centre-line length × t, less each 90° bend's rounding with the inside radius taken as t
///   (outside 2t): a bend's sharp corner holds 3t², its rounded one π/4 · 3t², so each bend takes off (1 − π/4) · 3t².
///   This reproduces the tables' areas (C-100x50x20x3.2 7.007 cm², □-100x100x3.2 12.13 cm²) to 0.1 %.
/// - **Round pipe:** π · t · (D − t). The inch sizes take the outside diameters of the JIS / มอก. 107 series (1" = 34.0 mm).
/// - **H and I:** two flanges and the web, b·tf·2 + (h − 2tf)·tw, plus four root fillets of (1 − π/4) r², with r from the
///   JIS table for its sizes and r = tf otherwise. I-beams' tapered flanges are taken as parallel, r = tf (I-200x100x7x10
///   26.3 kg/m against the table's 26.0).
/// - **Equal or unequal angle:** t · (a + b − t), without the root and toe radii (they nearly cancel: within 1 %).
/// Wood, reinforced concrete, the T2 truss and anything that doesn't read as one of these have no section: `parse` returns
/// nil and the schedule shows "-", never a guess.
public struct SteelSection: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        /// Lipped channel h × b × lip × t; `double` for 2C (two channels).
        case lippedC(h: Double, b: Double, lip: Double, t: Double, double: Bool)
        /// Square or rectangular tube h × b × t.
        case tube(h: Double, b: Double, t: Double)
        /// Round pipe, outside diameter × t.
        case pipe(d: Double, t: Double)
        /// H or I: depth × flange width × web × flange.
        case h(h: Double, b: Double, tw: Double, tf: Double, i: Bool)
        /// Angle a × b × t.
        case angle(a: Double, b: Double, t: Double)
    }
    public let shape: Shape

    /// kg/m³.
    public static let density = 7850.0

    /// Cross-section area in mm².
    public var area: Double {
        switch shape {
        case let .lippedC(h, b, lip, t, double):
            // centre line: web h − t, flanges 2(b − t), lips 2(lip − t/2); four bends
            let one = t * (h + 2 * b + 2 * lip - 4 * t) - 4 * Self.bend(t)
            return double ? 2 * one : one
        case let .tube(h, b, t):
            return 2 * t * (h + b - 2 * t) - 4 * Self.bend(t)
        case let .pipe(d, t):
            return Double.pi * t * (d - t)
        case let .h(h, b, tw, tf, i):
            let r = i ? tf : Self.rootRadius["\(Self.n(h))x\(Self.n(b))x\(Self.n(tw))x\(Self.n(tf))"] ?? tf
            return 2 * b * tf + (h - 2 * tf) * tw + 4 * (1 - Double.pi / 4) * r * r
        case let .angle(a, b, t):
            return t * (a + b - t)
        }
    }
    /// kg/m.
    public var kgPerMetre: Double { area * 1e-6 * Self.density }

    /// What one 90° bend of inside radius t takes off the centre-line area (mm²).
    static func bend(_ t: Double) -> Double { (1 - Double.pi / 4) * 3 * t * t }
    /// JIS G 3192 root radii (mm) of the H sizes in the pick list.
    static let rootRadius: [String: Double] = [
        "100x100x6x8": 10, "125x125x6.5x9": 10, "150x150x7x10": 11, "200x100x5.5x8": 8, "200x200x8x12": 13,
    ]
    static func n(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(x) }

    /// Outside diameter (mm) of the JIS / มอก. 107 pipe sizes by nominal inch.
    public static let pipeOD: [Double: Double] = [
        0.5: 21.7, 0.75: 27.2, 1: 34.0, 1.25: 42.7, 1.5: 48.6, 2: 60.5, 2.5: 76.3, 3: 89.1, 3.5: 101.6, 4: 114.3, 5: 139.8, 6: 165.2,
    ]

    /// The section a size names, or nil for anything that isn't one of the steel shapes above.
    public static func parse(_ size: String) -> SteelSection? {
        let s = size.trimmingCharacters(in: .whitespaces)
        func body(after prefix: String) -> String? {
            guard s.hasPrefix(prefix) else { return nil }
            var r = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if r.hasPrefix("-") { r.removeFirst() }
            return r
        }
        func dims(_ r: String) -> [Double]? {
            let parts = r.lowercased().replacingOccurrences(of: "×", with: "x").split(separator: "x", omittingEmptySubsequences: false)
            let nums = parts.map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard !nums.isEmpty, nums.allSatisfy({ ($0 ?? 0) > 0 }) else { return nil }
            return nums.compactMap { $0 }
        }
        func make(_ shape: Shape) -> SteelSection? {
            let x = SteelSection(shape: shape)
            return x.area.isFinite && x.area > 0 ? x : nil
        }
        if let r = body(after: "2C"), let d = dims(r), d.count == 4, d[3] * 2 < min(d[0], d[1]) {
            return make(.lippedC(h: d[0], b: d[1], lip: d[2], t: d[3], double: true))
        }
        if let r = body(after: "C"), let d = dims(r), d.count == 4, d[3] * 2 < min(d[0], d[1]) {
            return make(.lippedC(h: d[0], b: d[1], lip: d[2], t: d[3], double: false))
        }
        if let r = body(after: "□"), let d = dims(r), d.count == 3, d[2] * 2 < min(d[0], d[1]) {
            return make(.tube(h: d[0], b: d[1], t: d[2]))
        }
        for (p, i) in [("H", false), ("I", true)] {
            if let r = body(after: p), let d = dims(r), d.count == 4, d[3] * 2 < d[0], d[2] < d[1] {
                return make(.h(h: d[0], b: d[1], tw: d[2], tf: d[3], i: i))
            }
        }
        if let r = body(after: "L"), let d = dims(r) {
            if d.count == 3, d[2] < min(d[0], d[1]) { return make(.angle(a: d[0], b: d[1], t: d[2])) }
        }
        if let r = body(after: "Ø"), let d = dims(r), d.count == 2, d[1] * 2 < d[0] {
            return make(.pipe(d: d[0], t: d[1]))
        }
        if let r = body(after: "ท่อกลม") { return inchPipe(r) }
        return nil
    }

    /// `Ø1¼" หนา 2.0`: a nominal inch size from `pipeOD` and the wall thickness in mm.
    static func inchPipe(_ r: String) -> SteelSection? {
        guard r.hasPrefix("Ø"), let q = r.firstIndex(where: { $0 == "\"" || $0 == "”" }),
              let th = r.range(of: "หนา") else { return nil }
        var nominal = String(r[r.index(after: r.startIndex)..<q]).trimmingCharacters(in: .whitespaces)
        var inch = 0.0
        for (f, v) in [("½", 0.5), ("¼", 0.25), ("¾", 0.75)] where nominal.hasSuffix(f) {
            inch += v; nominal = String(nominal.dropLast())
        }
        // "1", "1 1/4" or "3/4"
        for part in nominal.split(separator: " ") {
            let f = part.split(separator: "/").compactMap { Double($0) }
            if f.count == 1, !part.contains("/") { inch += f[0] }
            else if f.count == 2, f[1] > 0 { inch += f[0] / f[1] }
            else { return nil }
        }
        let tText = r[th.upperBound...].trimmingCharacters(in: .whitespaces)
            .prefix { $0.isNumber || $0 == "." }
        guard let d = pipeOD[inch], let t = Double(tText), t > 0, t * 2 < d else { return nil }
        return SteelSection(shape: .pipe(d: d, t: t))
    }
}
