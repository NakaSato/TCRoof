#if canImport(UIKit)
import SwiftUI

/// A small bar chart of a day's values (a station's power hour by hour): one rounded bar per value, scaled to the
/// largest, empty values as a 2 pt stub on the track colour. Decorative: the caller's label carries the numbers.
public struct TCSparkline: View {
    var values: [Double]
    var tint: Color
    var spacing: CGFloat

    public init(_ values: [Double], tint: Color = Theme.primary, spacing: CGFloat = 2) {
        self.values = values; self.tint = tint; self.spacing = spacing
    }

    public var body: some View {
        let top = max(values.max() ?? 0, 0.0001)
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    let h = v > 0 ? max(geo.size.height * CGFloat(v / top), 3) : 2
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(v > 0 ? tint : Theme.borderSubtle)
                        .frame(height: h)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

/// A day's power as a smooth filled curve over light grid lines, with the expected curve as a dashed line: one point per
/// value, spread evenly across the width. Hours not reached yet (trailing zeros) are left off the actual curve, so it
/// stops at the last reading. Decorative: the caller's label carries the numbers.
public struct TCDayCurve: View {
    var actual: [Double]
    var expected: [Double]
    var tint: Color

    public init(actual: [Double], expected: [Double] = [], tint: Color = Theme.primary) {
        self.actual = actual; self.expected = expected; self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let count = max(actual.count, expected.count)
            let top = max((actual + expected).max() ?? 0, 0.0001) * 1.08
            let reached = actual.lastIndex(where: { $0 > 0 }).map { Array(actual[...$0]) } ?? []
            ZStack {
                ForEach(1..<4, id: \.self) { i in
                    Path { p in
                        let y = h * CGFloat(i) / 4
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Theme.hairline, lineWidth: 1)
                }
                if expected.contains(where: { $0 > 0 }) {
                    Self.line(Self.points(expected, count: count, top: top, w: w, h: h), floor: h)
                        .stroke(Theme.inkFaint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4]))
                }
                if reached.count > 1 {
                    let pts = Self.points(reached, count: count, top: top, w: w, h: h)
                    Self.area(pts, floor: h)
                        .fill(LinearGradient(colors: [tint.opacity(0.3), tint.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                    Self.line(pts, floor: h)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    static func points(_ values: [Double], count: Int, top: Double, w: CGFloat, h: CGFloat) -> [CGPoint] {
        let step = count > 1 ? w / CGFloat(count - 1) : 0
        return values.enumerated().map { i, v in CGPoint(x: step * CGFloat(i), y: h - h * CGFloat(max(v, 0) / top)) }
    }

    /// A Catmull-Rom curve through the points, its handles kept above `floor` so it never dips under zero.
    static func line(_ p: [CGPoint], floor: CGFloat) -> Path {
        Path { path in
            guard let first = p.first else { return }
            path.move(to: first)
            for i in 0..<(p.count - 1) {
                let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: min(p1.y + (p2.y - p0.y) / 6, floor))
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: min(p2.y - (p3.y - p1.y) / 6, floor))
                path.addCurve(to: p2, control1: c1, control2: c2)
            }
        }
    }

    static func area(_ p: [CGPoint], floor: CGFloat) -> Path {
        var path = line(p, floor: floor)
        guard let first = p.first, let last = p.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: floor))
        path.addLine(to: CGPoint(x: first.x, y: floor))
        path.closeSubpath()
        return path
    }
}
#endif
