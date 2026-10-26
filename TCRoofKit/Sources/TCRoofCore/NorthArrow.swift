import Foundation

/// The team's north arrow (`docs/specs/cad-export-dxf/reference/North_Arrow.dxf`), taken by
/// `tools/cad-details/north_arrow.py` into `Resources/north-arrow.json`: its circle's centre at the origin, radius 1,
/// N up. The plan DXFs (roof, tank, site) place it as one block, `TC_NORTH_ARROW`, turned to the plan's north.
public struct NorthArrow: Decodable, Sendable {
    public struct Polyline: Decodable, Sendable { public var points: [[Double]]; public var closed: Bool }
    public struct Hatch: Decodable, Sendable {
        public struct Line: Decodable, Sendable { public var angle: Double; public var base: [Double]; public var offset: [Double]; public var dashes: [Double] }
        public var pattern: String; public var loops: [[[Double]]]; public var lines: [Line]
    }
    public struct Letter: Decodable, Sendable { public var text: String; public var at: [Double]; public var height: Double }
    public var source: String
    public var circles: [[Double]]
    public var polylines: [Polyline]
    public var hatches: [Hatch]
    public var texts: [Letter]

    public static let blockName = "TC_NORTH_ARROW"
    /// The circle's radius on the printed A3 sheet (mm).
    public static let paperRadius = 10.0

    public static let shared: NorthArrow? = {
        guard let url = Bundle.module.url(forResource: "north-arrow", withExtension: "json"), let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NorthArrow.self, from: d)
    }()

    /// The block, at radius 1 (its parts ByBlock, so the INSERT's layer carries them).
    public func define(_ dxf: inout SketchDXF) -> String {
        dxf.block(Self.blockName) { d in
            let l = CADLayers.north
            func pt(_ p: [Double]) -> (Double, Double) { (p[0], p[1]) }
            for c in circles where c.count == 3 { d.circle(l, (c[0], c[1]), r: c[2]) }
            for p in polylines { d.polyline(l, p.points.map(pt), closed: p.closed) }
            for h in hatches {
                d.patternHatch(l, loops: h.loops.map { $0.map(pt) }, name: h.pattern,
                               lines: h.lines.map { .init(angle: $0.angle, base: pt($0.base), offset: pt($0.offset), dashes: $0.dashes) })
            }
            for t in texts { d.text(l, pt(t.at), height: t.height, t.text, align: .center, middle: true) }
        }
    }

    /// Places the arrow centred at `c`, N turned `north` degrees counter-clockwise from the drawing's +y, at `radius`
    /// drawing metres (nil: `paperRadius` at the drawing's plot scale so far). False when the resource is missing.
    @discardableResult
    public static func place(_ dxf: inout SketchDXF, at c: (Double, Double), north: Double, radius: Double? = nil) -> Bool {
        guard let a = shared else { return false }
        let r = radius ?? paperRadius / 1000 * dxf.plotScale
        dxf.insert(CADLayers.north, a.define(&dxf), at: c, rotation: north, scale: r)
        return true
    }

    /// The site picture's `north` answer (ทิศเหนือของภาพอยู่) as the arrow's turn.
    public static func turn(siteNorth: String?) -> Double {
        ["ด้านบน": 0, "ด้านขวา": -90, "ด้านล่าง": 180, "ด้านซ้าย": 90][siteNorth ?? ""] ?? 0
    }
}
