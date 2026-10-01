import Foundation
import CoreGraphics

/// Part of the A1 satellite map used as the report picture (docs/ui/survey-a1 SPEC §3), in % of the map.
/// Kept in the job as `mapCrop` = "x,y,w,h". A job without it uses the whole picture.
public struct MapCrop: Equatable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double

    public static let key = "mapCrop"
    /// Frame of a new job and of "รีเซ็ตกรอบ".
    public static let standard = MapCrop(x: 22, y: 16, w: 54, h: 64)
    public static let full = MapCrop(x: 0, y: 0, w: 100, h: 100)
    /// Smallest side, in % of the map.
    public static let minSize = 12.0

    public enum Corner: CaseIterable, Sendable { case nw, ne, sw, se }

    public init(x: Double, y: Double, w: Double, h: Double) {
        let w = min(max(w, Self.minSize), 100), h = min(max(h, Self.minSize), 100)
        self.w = w; self.h = h
        self.x = min(max(x, 0), 100 - w)
        self.y = min(max(y, 0), 100 - h)
    }

    /// "22,16,54,64"; nil when it isn't four numbers.
    public init?(_ text: String) {
        let n = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard n.count == 4, let x = n[0], let y = n[1], let w = n[2], let h = n[3] else { return nil }
        self.init(x: x, y: y, w: w, h: h)
    }

    public var text: String { [x, y, w, h].map { String(format: "%g", ($0 * 10).rounded() / 10) }.joined(separator: ",") }

    /// Dragged from inside: same size, kept on the map.
    public func moved(dx: Double, dy: Double) -> MapCrop { MapCrop(x: x + dx, y: y + dy, w: w, h: h) }

    /// Dragged by a corner: that corner's two edges move, the opposite corner stays.
    public func resized(_ c: Corner, dx: Double, dy: Double) -> MapCrop {
        var l = x, t = y, r = x + w, b = y + h
        switch c {
        case .nw, .sw: l = min(max(l + dx, 0), r - Self.minSize)
        case .ne, .se: r = max(min(r + dx, 100), l + Self.minSize)
        }
        switch c {
        case .nw, .ne: t = min(max(t + dy, 0), b - Self.minSize)
        case .sw, .se: b = max(min(b + dy, 100), t + Self.minSize)
        }
        return MapCrop(x: l, y: t, w: r - l, h: b - t)
    }

    /// Ground size in whole metres: `across` is the map's width in metres, `aspect` its height / width.
    public func meters(across: Double, aspect: Double) -> (w: Int, h: Int) {
        (Int((across * w / 100).rounded()), Int((across * aspect * h / 100).rounded()))
    }

    /// "ภาพในรายงาน · 108 × 69 ม."
    public func label(across: Double, aspect: Double) -> String {
        let m = meters(across: across, aspect: aspect)
        return "ภาพในรายงาน · \(m.w) × \(m.h) ม."
    }

    /// The frame on a map (or picture) of this size.
    public func rect(in size: CGSize) -> CGRect {
        CGRect(x: size.width * x / 100, y: size.height * y / 100, width: size.width * w / 100, height: size.height * h / 100)
    }

    /// The frame in whole pixels of a picture, for cutting it out.
    public func pixelRect(width: Int, height: Int) -> CGRect {
        rect(in: CGSize(width: width, height: height)).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }
}
