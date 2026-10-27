import Foundation

/// The team's inverter station components (docs/specs/cad-export-dxf/reference/inverter-station/components: the
/// library extracted from their station drawings, with the cable trays and ladders drawn from the Niedax / EZ-FIT
/// sizes), as `tools/cad-details/station_components.py` writes them into `Resources/station-components.json`: true size
/// in metres, each block's base point at its lower-left corner as in the library. The B2 DXF (`InverterStationDXF`)
/// defines each one it uses as a block of the library's own name (`TCR_SOLAR_AC_DB_FRONT`, …) and inserts it, stretched
/// to the catalog's size where the two differ.
public struct StationComponents: Decodable, Sendable {
    public struct Poly: Decodable, Sendable { public var points: [[Double]]; public var closed: Bool }
    public struct Text: Decodable, Sendable {
        public var at: [Double]; public var height: Double; public var text: String; public var angle: Double
        public var align: String; public var middle: Bool
    }
    public struct Block: Decodable, Sendable {
        public var lines: [[Double]]?
        public var polylines: [Poly]?
        public var circles: [[Double]]?
        public var texts: [Text]?
        /// x0, y0, x1, y1 (m) around the base point.
        public var box: [Double]
        public var width: Double { box[2] - box[0] }
        public var height: Double { box[3] - box[1] }
    }
    public var blocks: [String: Block]

    /// The components the app ships.
    public static let shared: StationComponents? = {
        guard let url = Bundle.module.url(forResource: "station-components", withExtension: "json"), let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StationComponents.self, from: d)
    }()

    /// Defines the component `name` as a block (once) and gives its block name and box; nil when the library has no
    /// such component. `wipeout` puts a WIPEOUT over its box first, so it hides what is drawn behind it.
    public func define(_ dxf: inout SketchDXF, _ name: String, layer l: SketchDXF.Layer, wipeout: Bool = false) -> (name: String, block: Block)? {
        guard let b = blocks[name] else { return nil }
        let n = dxf.block(name) { d in
            d.fine = true
            if wipeout { d.wipeout(l, [(b.box[0], b.box[1]), (b.box[2], b.box[1]), (b.box[2], b.box[3]), (b.box[0], b.box[3])]) }
            for s in b.lines ?? [] { d.line(l, (s[0], s[1]), (s[2], s[3])) }
            for p in b.polylines ?? [] { d.polyline(l, p.points.map { ($0[0], $0[1]) }, closed: p.closed) }
            for c in b.circles ?? [] { d.circle(l, (c[0], c[1]), r: c[2]) }
            for t in b.texts ?? [] {
                d.text(l, (t.at[0], t.at[1]), height: t.height, t.text, align: t.align == "center" ? .center : t.align == "right" ? .right : .left,
                       middle: t.middle, angle: t.angle)
            }
        }
        return (n, b)
    }
}
