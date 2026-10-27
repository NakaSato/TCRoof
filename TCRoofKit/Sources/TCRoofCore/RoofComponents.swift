import Foundation

/// The team's roof section components and measurements, taken from their section drawing
/// (`docs/specs/cad-export-dxf/reference/Roof section eave ceiling.dxf`) by `tools/cad-details/roof_components.py` into
/// `Resources/roof-components.json`. The roof DXF draws each purlin and the ridge cap as one INSERT of the team's own
/// block, and `RoofComponentsTests` checks that the app's section keeps the drawing's measures (`checks`).
public struct RoofComponents: Decodable, Sendable {
    public struct Component: Decodable, Sendable {
        public var note: String
        /// x1, y1, x2, y2 in the component's frame (metres).
        public var lines: [[Double]]
        /// The purlin's height and width as drawn (m).
        public var size: [Double]?
        /// The pitch the ridge cap is drawn at (degrees).
        public var pitch: Double?
    }
    public var source: String
    public var components: [String: Component]
    /// The drawing's measures (m): rafterDepth, rafterLip, sheetOverRafter, sheetThickness, purlinSpacing, tieDepth,
    /// strutTopUnderHead, postWidth, beamDepth, soffitUnderHead, …
    public var checks: [String: Double]

    public static let shared: RoofComponents? = {
        guard let url = Bundle.module.url(forResource: "roof-components", withExtension: "json"), let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RoofComponents.self, from: d)
    }()

    /// The purlin block (`RF_PURLIN_C`): its origin at the C's bottom centre, +x where the flanges open, +y off the
    /// rafter; and the ridge cap block (`RF_RIDGE_CAP`), its origin on the sheet's top at the ridge.
    public func define(_ dxf: inout SketchDXF) -> (purlin: String?, cap: String?) {
        func block(_ id: String, _ name: String, _ l: SketchDXF.Layer) -> String? {
            guard let c = components[id] else { return nil }
            return dxf.block(name) { d in
                for s in c.lines where s.count >= 4 { d.line(l, (s[0], s[1]), (s[2], s[3])) }
            }
        }
        return (purlinBlock(&dxf), block("ridge_cap", "RF_RIDGE_CAP", CADLayers.roofSection))
    }

    /// The purlin as steel: a C-100x50x20x2.3 at the drawing's size, its wall one closed polyline filled with a SOLID
    /// hatch (the reference drawing's C has a 10 mm wall and reads as a bracket, not a cold-formed section).
    func purlinBlock(_ dxf: inout SketchDXF) -> String? {
        guard let size = components["purlin_c"]?.size, size.count == 2 else { return nil }
        let c = StructureSection.Cut(.init(.channel(lip: Self.purlinLip), h: size[0], b: size[1], t: Self.purlinWall), at: Pt(0, 0))
        let loop = c.wall.map { ($0.x, $0.y) }
        return dxf.block("RF_PURLIN_C") { d in
            d.solid(CADLayers.roofPurlin, loop)
            d.polyline(CADLayers.roofPurlin, loop, closed: true)
        }
    }
    /// The purlin's lip and wall (m), C-100x50x20x2.3.
    public static let purlinLip = 0.02, purlinWall = 0.0023
}
