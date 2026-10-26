import Foundation

/// A team detail drawing turned into primitives by `tools/cad-details/convert.py` (lines, polylines, filled polygons,
/// texts, each with its AutoCAD colour), in the source's own units (paper millimetres), bottom-left at (0, 0). The DXF
/// exports place it beside a plan as one block (`SketchDXF.detailBlock`).
public struct CADDetail: Decodable, Sendable {
    public struct Poly: Decodable, Sendable { public var points: [[Double]]; public var closed: Bool?; public var aci: Int }
    public struct Text: Decodable, Sendable { public var at: [Double]; public var height, rotation: Double; public var text: String; public var align, aci: Int }
    public var source: String
    public var size: [Double]
    /// x1, y1, x2, y2, aci.
    public var lines: [[Double]]
    public var polylines: [Poly]
    public var fills: [Poly]
    public var texts: [Text]

    /// The walkway detail (`docs/specs/cad-export-dxf/reference/Walkway.dxf`): top view, elevations 1–3 and detail 1.
    public static let walkway: CADDetail? = load("walkway-detail")

    static func load(_ name: String) -> CADDetail? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"), let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CADDetail.self, from: d)
    }
}

extension SketchDXF {
    /// Defines `d` as one block in its own units (paper millimetres), on `CADLayers.detail` with each entity's colour,
    /// and returns its name: insert it at scale `plot scale × unit / 1000` so it prints at its size.
    @discardableResult
    public mutating func detailBlock(_ d: CADDetail, name: String) -> String {
        let m = options.millimetres ? 1.0 / 1000 : 1, l = CADLayers.detail
        return block(name, keepLayers: true) { b in
            for s in d.lines where s.count >= 5 { b.line(l, (s[0] * m, s[1] * m), (s[2] * m, s[3] * m), aci: Int(s[4])) }
            for p in d.polylines { b.polyline(l, p.points.map { ($0[0] * m, $0[1] * m) }, closed: p.closed ?? false, aci: p.aci) }
            for f in d.fills where f.points.count >= 3 { b.solid(l, f.points.map { ($0[0] * m, $0[1] * m) }, aci: f.aci) }
            for t in d.texts {
                b.text(l, (t.at[0] * m, t.at[1] * m), height: t.height * m, t.text, align: t.align == 1 ? TextAlign.center : t.align == 2 ? TextAlign.right : TextAlign.left,
                       angle: t.rotation, aci: t.aci)
            }
        }
    }
}
