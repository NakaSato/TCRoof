import Foundation

/// SLD symbols as vector `DrawOp`s. The geometry, stroke widths and colours are copied from
/// docs/ui/survey-sld/icons/svg/sld-*.svg (cut from diagram-lv.svg), so the drawing stays sharp at any zoom and in the A3 PDF.
/// Each symbol is placed by the same anchor the design uses: x is the centre line, y the first point named in the doc comment.
public enum SLSymbols {
    public static let ink = RGBA(hex: 0x2B2B2B), blue = RGBA(hex: 0x1F4E8C), poleFill = RGBA(hex: 0x9CA3AF), poleStroke = RGBA(hex: 0x6B7280)

    static func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ c: RGBA = ink, _ w: Double = 2, dash: [Double] = []) -> DrawOp {
        .line(Pt(x1, y1), Pt(x2, y2), width: w, color: c, dash: dash)
    }
    /// Polyline through the points, one segment per pair — the SVG `M … L …` paths.
    static func path(_ pts: [(Double, Double)], _ c: RGBA = ink, _ w: Double = 2) -> [DrawOp] {
        zip(pts, pts.dropFirst()).map { line($0.0, $0.1, $1.0, $1.1, c, w) }
    }
    /// Quadratic curve from `a` through control `c` to `b`, as a polyline (the `))` mark).
    static func quad(_ a: (Double, Double), _ c: (Double, Double), _ b: (Double, Double), _ col: RGBA, _ w: Double) -> [DrawOp] {
        let pts = (0...8).map { i -> (Double, Double) in
            let t = Double(i) / 8, u = 1 - t
            return (u * u * a.0 + 2 * u * t * c.0 + t * t * b.0, u * u * a.1 + 2 * u * t * c.1 + t * t * b.1)
        }
        return path(pts, col, w)
    }
    static func text(_ s: String, _ x: Double, _ y: Double, size: Double, bold: Bool = false, _ c: RGBA, align: TextAlign = .left) -> DrawOp {
        .text(s, at: Pt(x, y), size: size, bold: bold, color: c, align: align)
    }

    /// sld-line-break: `))` on the PEA line; (x, 60) is the line.
    public static func lineBreak(x: Double, y: Double = 60) -> [DrawOp] {
        quad((x - 4, y + 10), (x + 2, y), (x - 4, y - 10), ink, 1.5) + quad((x + 4, y + 10), (x + 10, y), (x + 4, y - 10), ink, 1.5)
    }

    /// Pole marker on a line: 10 × 10 grey square centred on (x, y).
    public static func pole(x: Double, y: Double) -> DrawOp {
        .rect(Box(x - 5, y - 5, 10, 10), stroke: poleStroke, fill: poleFill, width: 1)
    }

    /// Open switch with two contact circles (sld-dropout-switch, sld-hv-switch): (x, y) → (x, y + 40).
    public static func openSwitch(x: Double, y: Double) -> [DrawOp] {
        [line(x, y, x, y + 8),
         .circle(Pt(x, y + 10), r: 3, stroke: ink, fill: .white, width: 1.5),
         line(x, y + 12, x + 10, y + 28),
         .circle(Pt(x + 10, y + 30), r: 3, stroke: ink, fill: .white, width: 1.5),
         line(x, y + 30, x, y + 40)]
    }

    /// sld-hv-switch: junction dot on the HV bus and the switch below it; (x, y) is the bus.
    public static func hvSwitch(x: Double, y: Double) -> [DrawOp] {
        [.circle(Pt(x, y), r: 3.5, stroke: nil, fill: ink)] + openSwitch(x: x, y: y)
    }

    /// sld-pea-meter: kWh circle centred at (x, y), leads 28 above and below.
    public static func meter(x: Double, y: Double) -> [DrawOp] {
        [line(x, y - 28, x, y - 14),
         .circle(Pt(x, y), r: 14, stroke: ink, fill: .white, width: 2),
         text("kWh", x, y + 4, size: 9, bold: true, ink, align: .center)]
    }

    /// sld-ct-vt-hv / sld-ct-lv: zero-export CT on a vertical line, centred at (x, y); blue, new equipment.
    public static func ct(x: Double, y: Double) -> [DrawOp] {
        [.circle(Pt(x, y), r: 14, stroke: blue, fill: .white, width: 2),
         line(x - 9, y + 9, x + 9, y - 9, blue, 1.5),
         text("3", x + 7, y - 8, size: 9, bold: true, blue)]
    }

    /// sld-lightning-arrester: branch from (x, y) down; box 16 × 26, arrow, ground. x is the branch line.
    public static func arrester(x: Double, y: Double = 300) -> [DrawOp] {
        [line(x, y, x, y + 10),
         .rect(Box(x - 8, y + 10, 16, 26), stroke: ink, fill: .white, width: 1.5),
         .polygon([Pt(x - 4, y + 18), Pt(x + 4, y + 18), Pt(x, y + 26)], stroke: nil, fill: ink),
         line(x, y + 36, x, y + 44), line(x - 10, y + 44, x + 10, y + 44), line(x - 6, y + 48, x + 6, y + 48), line(x - 3, y + 52, x + 3, y + 52)]
    }

    /// sld-cable-terminations: three filled triangles, top at (x, y).
    public static func cableTerminations(x: Double, y: Double = 318) -> [DrawOp] {
        (0..<3).map { k in
            let t = y + Double(k) * 11
            return .polygon([Pt(x - 8, t), Pt(x + 8, t), Pt(x, t + 10)], stroke: nil, fill: ink)
        }
    }

    /// Ground symbol: 3 bars of decreasing width, top bar at y.
    public static func ground(x: Double, y: Double, widths: [Double], step: Double, _ w: Double) -> [DrawOp] {
        widths.enumerated().map { k, hw in line(x - hw, y + Double(k) * step, x + hw, y + Double(k) * step, ink, w) }
    }

    /// sld-transformer: Δ over Y with grounded neutral; (x, y) is the centre of the upper (Δ) circle.
    public static func transformer(x: Double, y: Double = 370) -> [DrawOp] {
        var o: [DrawOp] = [
            .circle(Pt(x, y), r: 20, stroke: ink, fill: nil, width: 2),
            .circle(Pt(x, y + 26), r: 20, stroke: ink, fill: nil, width: 2),
            .polygon([Pt(x - 7, y - 1), Pt(x, y - 13), Pt(x + 7, y - 1)], stroke: ink, fill: nil, width: 1.5)]
        o += path([(x, y + 31), (x, y + 39)], ink, 1.5)
        o += path([(x, y + 31), (x - 7, y + 25)], ink, 1.5)
        o += path([(x, y + 31), (x + 7, y + 25)], ink, 1.5)
        o += path([(x, y + 31), (x - 30, y + 31), (x - 30, y + 41)], ink, 1.5)
        o += ground(x: x - 30, y: y + 41, widths: [10, 6, 2], step: 4, 1.5)
        return o
    }

    /// sld-breaker-mccb / sld-breaker-acb-drawout: (x, y) is the top of the contact, 36 tall.
    /// The white block hides the feeder line behind the symbol; the draw-out type has open chevrons above and below.
    public static func breaker(x: Double, y: Double, color: RGBA = ink, drawout: Bool = false) -> [DrawOp] {
        var o: [DrawOp] = []
        if drawout {
            o += path([(x - 6, y - 12), (x, y - 6), (x + 6, y - 12)], color, 1.5)
            o += path([(x - 6, y - 6), (x, y), (x + 6, y - 6)], color, 1.5)
        }
        o.append(.rect(Box(x - 12, y, 14, 36), stroke: nil, fill: .white))
        o += path([(x, y), (x, y + 8)], color, 2)
        o += path([(x - 4, y + 4), (x + 4, y + 12)], color, 2)
        o += path([(x + 4, y + 4), (x - 4, y + 12)], color, 2)
        o += path([(x, y + 28), (x - 10, y + 10)], color, 2)
        o += path([(x, y + 28), (x, y + 36)], color, 2)
        if drawout {
            o += path([(x - 6, y + 38), (x, y + 44), (x + 6, y + 38)], color, 1.5)
            o += path([(x - 6, y + 44), (x, y + 50), (x + 6, y + 44)], color, 1.5)
        }
        return o
    }

    /// sld-load: black block 36 × 18 at the end of an outgoing breaker; (x, y) is its top centre.
    public static func load(x: Double, y: Double) -> DrawOp { .rect(Box(x - 18, y, 36, 18), stroke: nil, fill: ink) }

    /// sld-inverter: box 40 × 36 with the =/~ diagonal; (x, y) is its top centre.
    public static func inverter(x: Double, y: Double) -> [DrawOp] {
        [.rect(Box(x - 20, y, 40, 36), stroke: blue, fill: .white, width: 2),
         line(x - 20, y + 36, x + 20, y, blue, 1.5),
         text("=", x - 12, y + 13, size: 11, blue), text("~", x + 6, y + 31, size: 12, blue)]
    }

    /// sld-dc-disconnect: (x, y) is the top lead; 54 tall.
    public static func dcDisconnect(x: Double, y: Double) -> [DrawOp] {
        [line(x, y, x, y + 16, blue, 2),
         .circle(Pt(x, y + 16), r: 2.5, stroke: nil, fill: blue),
         line(x, y + 16, x + 10, y + 32, blue, 1.8),
         line(x, y + 34, x, y + 42, blue, 1.8),
         line(x, y + 42, x, y + 54, blue, 2)]
    }

    /// sld-pv-array: box 36 × 28 with cell lines; (x, y) is its top centre.
    public static func pvArray(x: Double, y: Double) -> [DrawOp] {
        [.rect(Box(x - 18, y, 36, 28), stroke: blue, fill: .white, width: 2),
         line(x - 6, y, x - 6, y + 28, blue, 1), line(x + 6, y, x + 6, y + 28, blue, 1), line(x - 18, y + 14, x + 18, y + 14, blue, 1)]
    }

    /// sld-emergency-button.
    public static func emergency(x: Double, y: Double) -> [DrawOp] {
        [.circle(Pt(x, y), r: 12, stroke: blue, fill: .white, width: 2), .circle(Pt(x, y), r: 6, stroke: nil, fill: blue)]
    }
}
