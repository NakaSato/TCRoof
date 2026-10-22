import Foundation

/// SLD "ส่งออก DXF" (docs/specs/cad-export-dxf phase 2): the same diagram as the A3 PDF page, as DXF R2000 at paper scale,
/// 400 mm wide (A3 landscape less its margins), with a title line and the "not a construction drawing" note under it.
/// Layers follow `SingleLineLayout.color(_:)`: ink is a known value, blue new equipment, red a missing value, grey an
/// assumed one. Condition colours (green / amber / red) only colour text, which goes on `SLD_TEXT` with its colour kept.
public enum SingleLineDXF {
    /// Drawing width in mm.
    public static let paperWidth = 400.0

    /// (colour, layer).
    static let colourLayers: [(RGBA, SketchDXF.Layer)] = [
        (SingleLineLayout.ink, .init("SLD_LINE", aci: 7)), (SingleLineLayout.blue, .init("SLD_NEW", aci: 5)),
        (SingleLineLayout.green, .init("SLD_OK", aci: 3)), (SingleLineLayout.amber, .init("SLD_WARN", aci: 30)),
        (SingleLineLayout.red, .init("SLD_MISSING", aci: 1)), (SingleLineLayout.pole, .init("SLD_POLE", aci: 8)),
        (SingleLineLayout.grey, .init("SLD_ASSUMED", aci: 8)),
    ]
    static let textLayer = SketchDXF.Layer("SLD_TEXT", aci: 7), otherLayer = SketchDXF.Layer("SLD_OTHER", aci: 7)

    static func layer(_ op: DrawOp) -> SketchDXF.Layer {
        let colour: RGBA?
        switch op {
        case .text, .textBox, .runs: return textLayer
        case let .line(_, _, _, c, _), let .polyline(_, _, c, _), let .hatch(_, c, _): colour = c
        // the pole marker is the only shape filled `pole` (its stroke is grey)
        case let .rect(_, s, f, _), let .polygon(_, s, f, _), let .circle(_, _, s, f, _): colour = f == SLSymbols.poleFill ? f : s ?? f
        case .photo, .photoFill, .checkbox: colour = nil
        }
        return colourLayers.first { $0.0 == colour }?.1 ?? otherLayer
    }

    /// `hv` as `PDFRenderer.renderSingleLine`: nil follows the job (B4), true / false forces the HV / LV drawing.
    public static func build(_ job: Job, hv: Bool? = nil) -> RoofDXF.Output {
        let drawing = SingleLineLayout.draw(SingleLine.build(job, hvOverride: hv))
        let H = drawing.sketch.height, s = paperWidth / drawing.width   // mm per sketch point
        var o = SketchDXF.Options()
        o.dashes = true; o.opColours = true; o.textBoxes = true; o.hatches = true; o.outlineBoxes = true
        o.skipFillOnly = true; o.centreText = false
        var dxf = SketchDXF(options: o)
        dxf.add(drawing.sketch.ops, layer: { _, op in layer(op) }, transform: { p in (p.x * s / 1000, (H - p.y) * s / 1000) },
                pointsPerMetre: 1000 / s, symbols: drawing.symbols)

        let docNo = job.docNo.isEmpty ? "-" : job.docNo, site = job.projectName.isEmpty ? "-" : job.projectName
        var title = "SINGLE LINE DIAGRAM | \(docNo) | \(site)"
        if !job.values.text("date").isEmpty { title += " | " + ISODate.thai(job.values.text("date")) }
        dxf.text(textLayer, (0, -0.008), height: 0.0035, title)
        dxf.text(textLayer, (paperWidth / 1000, -0.008), height: 0.0035, "สร้างจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", align: .right)
        return dxf.output
    }
}
