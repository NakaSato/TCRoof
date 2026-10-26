import Foundation

/// A2 "ส่งออก DXF" (docs/specs/cad-export-dxf phase 3): the site plan drawn over the site picture — building models,
/// drawn shapes and symbols — as DXF R2000 in metres (`millimetres` for 1 unit = 1 mm), from the picture's bottom-left corner with Y up. The picture
/// itself is not written (no image is embedded); its frame is. With a scale (`siteScale`, metres across the picture) the
/// drawing is at real scale; without one it is 400 mm wide and the title says so, and building models (which need the
/// scale) are left out, as on the report.
public enum SiteDXF {
    /// Sketch points across the picture: symbol, tag and text sizes follow it as they do on the report's picture.
    static let sketchWidth = 1000.0
    /// Drawing width in mm when the picture has no scale.
    public static let paperWidth = 400.0

    static let frame = CADLayers.siteFrame, pvArea = CADLayers.sitePVArea, building = CADLayers.siteBuilding,
               symbol = CADLayers.siteSymbol, north = CADLayers.north, text = CADLayers.text
    static func layer(_ k: ShapeKind) -> SketchDXF.Layer {
        switch k {
        case .panelArea: return CADLayers.sitePanelArea
        case .cableRoute: return CADLayers.siteCable
        case .measure: return CADLayers.siteMeasure
        case .craneEntry: return CADLayers.siteCrane
        case .shade: return CADLayers.siteShade
        case .boundary, .pvPoint: return CADLayers.siteShape
        }
    }

    /// A translucent fill with no stroke only tints what is under it (a model's or boundary's area); its outline is
    /// drawn by another op, so it would be written twice.
    static func isTint(_ op: DrawOp) -> Bool {
        switch op {
        case let .polygon(_, nil, f?, _), let .rect(_, nil, f?, _): return f.a < 1
        default: return false
        }
    }

    /// nil without a site picture (every position is a fraction of it).
    public static func build(_ job: Job, millimetres: Bool = false) -> RoofDXF.Output? {
        let v = job.values
        guard let p = v.photo("siteMap"), p.width > 0, p.height > 0 else { return nil }
        let meters = v.number(SiteShapes.scaleKey).flatMap { $0 > 0 ? $0 : nil }
        let W = sketchWidth, H = W * Double(p.height) / Double(p.width), box = Box(0, 0, W, H)
        let k = (meters ?? paperWidth / 1000) / W   // metres per sketch point
        var o = SketchDXF.Options(); o.millimetres = millimetres
        // every object ByLayer: the layers carry the colours
        o.dashes = true; o.textBoxes = true; o.hatches = true; o.outlineBoxes = true
        o.skipFillOnly = true; o.centreText = false
        var dxf = SketchDXF(options: o)
        func add(_ ops: [DrawOp], _ l: SketchDXF.Layer) {
            dxf.add(ops.filter { !isTint($0) }, layer: { _, _ in l }, transform: { q in (q.x * k, (H - q.y) * k) }, pointsPerMetre: 1 / k)
        }

        add([.rect(box, stroke: .black, fill: nil, width: 1)], frame)
        if let meters {
            for m in SiteModels.placed(job) {
                add(SiteModels.ops(m.model, m.source, in: box, metersAcross: meters, detailed: false, unit: max(0.5, W / 860)),
                    m.source.isPV ? pvArea : building)
            }
        }
        // areas first, as `SiteShapes.ops` draws them
        for s in v.shapes(SiteShapes.key).sorted(by: { $0.kind.isClosed && !$1.kind.isClosed }) {
            add(SiteShapes.ops([s], in: box, metersAcross: meters), layer(s.kind))
        }
        add(SiteMarks.ops(v.marks(ModuleMarks.key), in: box), symbol)
        let cs = W * 0.08
        // the team's north arrow where `Drawings.compass` sits (its circle centred at 43, 45 of 86, radius 24)
        let cc = Pt(W - cs * 1.1 + 43 * cs / 86, cs * 0.1 + 45 * cs / 86)
        if !NorthArrow.place(&dxf, at: (cc.x * k, (H - cc.y) * k), north: NorthArrow.turn(siteNorth: v.choice("north")), radius: 24 * cs / 86 * k) {
            add(Drawings.compass(v.choice("north"), size: cs).translated(W - cs * 1.1, cs * 0.1), north)
        }

        // title under the frame, sized to the drawing
        let th = W * k * 0.012, docNo = job.docNo.isEmpty ? "-" : job.docNo, site = job.projectName.isEmpty ? "-" : job.projectName
        var title = "SITE PLAN | \(docNo) | \(site)"
        if !v.text("date").isEmpty { title += " | " + ISODate.thai(v.text("date")) }
        dxf.text(text, (0, -th * 2), height: th, title)
        dxf.text(text, (W * k, -th * 2), height: th,
                 meters == nil ? "ไม่มีมาตราส่วน: วัดระยะบนภาพใน A2 ก่อน" : "มาตราส่วนจริง หน่วย มม.", align: .right)
        return dxf.output
    }
}
