#if canImport(UIKit)
import UIKit
import CoreText
import TCRoofCore

/// Draws the NO.215 report into a PDF with the bundled Sarabun font.
public enum PDFRenderer {
    private static let registered: Bool = {
        for name in ["Sarabun-Regular", "Sarabun-Bold"] {
            let url = Bundle.module.url(forResource: name, withExtension: "ttf")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Resources")
            if let url { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
        return true
    }()

    static func font(_ size: Double, bold: Bool) -> UIFont {
        _ = registered
        return UIFont(name: bold ? "Sarabun-Bold" : "Sarabun-Regular", size: CGFloat(size))
            ?? (bold ? UIFont.boldSystemFont(ofSize: CGFloat(size)) : UIFont.systemFont(ofSize: CGFloat(size)))
    }

    /// Real font metrics for the layout.
    public struct Measure: TextMeasuring {
        public init() {}
        public func width(_ s: String, size: Double, bold: Bool) -> Double {
            Double((s as NSString).size(withAttributes: [.font: PDFRenderer.font(size, bold: bold)]).width)
        }
        public func height(_ s: String, width: Double, size: Double, bold: Bool) -> Double {
            let r = (s as NSString).boundingRect(with: CGSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                 attributes: PDFRenderer.attributes(size, bold: bold, color: .black, align: .left), context: nil)
            return Double(ceil(r.height))
        }
    }

    static func attributes(_ size: Double, bold: Bool, color: RGBA, align: TextAlign, wrap: Bool = true) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.alignment = align == .left ? .left : align == .center ? .center : .right
        p.lineBreakMode = wrap ? .byWordWrapping : .byClipping
        return [.font: font(size, bold: bold), .foregroundColor: uiColor(color), .paragraphStyle: p]
    }
    static func uiColor(_ c: RGBA) -> UIColor { UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a)) }
    static func cg(_ b: Box) -> CGRect { CGRect(x: b.x, y: b.y, width: b.w, height: b.h) }

    /// Builds the whole report. `photo` returns a decoded image for a stored photo.
    /// The one-page summary on its own.
    public static func renderSummary(job: Job, header: ReportHeader, photo: @escaping (Photo) -> UIImage?) -> Data {
        render(pages: [ReportLayout(job: job, header: header, measure: Measure()).summaryPage()], job: job, photo: photo)
    }

    /// The single line diagram alone, on one A3 landscape page.
    public static func renderSingleLine(job: Job, header: ReportHeader, hv: Bool? = nil, photo: @escaping (Photo) -> UIImage?) -> Data {
        render(pages: [ReportLayout(job: job, header: header, measure: Measure()).singleLinePage(hv: hv)], job: job, photo: photo)
    }

    public static func render(job: Job, header: ReportHeader, photo: @escaping (Photo) -> UIImage?,
                              progress: ((Int, Int) -> Void)? = nil) -> Data {
        render(pages: ReportLayout(job: job, header: header, measure: Measure()).pages(), job: job, photo: photo, progress: progress)
    }

    static func render(pages: [ReportLayout.Page], job: Job, photo: @escaping (Photo) -> UIImage?, progress: ((Int, Int) -> Void)? = nil) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: ReportLayout.pageW, height: ReportLayout.pageH)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "แบบสำรวจ \(job.docNo)",
                               kCGPDFContextAuthor as String: job.values.text("engineer"),
                               kCGPDFContextSubject as String: job.projectName]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { ctx in
            for (i, page) in pages.enumerated() {
                progress?(i + 1, pages.count)
                ctx.beginPage(withBounds: CGRect(x: 0, y: 0, width: page.width, height: page.height), pageInfo: [:])
                draw(page.ops, in: ctx.cgContext, photo: photo)
            }
        }
    }

    /// Draws vector operations into any context (PDF page, image renderer for the Excel plan).
    public static func draw(_ ops: [DrawOp], in c: CGContext, photo: (Photo) -> UIImage?) {
        for op in ops {
            c.saveGState()
            switch op {
            case let .line(a, b, w, col, dash):
                c.setStrokeColor(uiColor(col).cgColor); c.setLineWidth(CGFloat(w))
                if !dash.isEmpty { c.setLineDash(phase: 0, lengths: dash.map { CGFloat($0) }) }
                c.move(to: CGPoint(x: a.x, y: a.y)); c.addLine(to: CGPoint(x: b.x, y: b.y)); c.strokePath()
            case let .rect(r, st, f, w):
                if let f { c.setFillColor(uiColor(f).cgColor); c.fill(cg(r)) }
                if let st { c.setStrokeColor(uiColor(st).cgColor); c.setLineWidth(CGFloat(w)); c.stroke(cg(r)) }
            case let .hatch(r, col, sp):
                c.clip(to: cg(r)); c.setStrokeColor(uiColor(col).cgColor); c.setLineWidth(1.4)
                var t = -r.h
                while t < r.w { c.move(to: CGPoint(x: r.x + t, y: r.maxY)); c.addLine(to: CGPoint(x: r.x + t + r.h, y: r.y)); t += sp }
                c.strokePath()
            case let .circle(p, rad, st, f, w):
                let rect = CGRect(x: p.x - rad, y: p.y - rad, width: 2 * rad, height: 2 * rad)
                if let f { c.setFillColor(uiColor(f).cgColor); c.fillEllipse(in: rect) }
                if let st { c.setStrokeColor(uiColor(st).cgColor); c.setLineWidth(CGFloat(w)); c.strokeEllipse(in: rect) }
            case let .polygon(ps, st, f, w):
                guard let first = ps.first else { break }
                let path = CGMutablePath()
                path.move(to: CGPoint(x: first.x, y: first.y))
                for p in ps.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
                path.closeSubpath()
                if let f { c.addPath(path); c.setFillColor(uiColor(f).cgColor); c.fillPath() }
                if let st { c.addPath(path); c.setStrokeColor(uiColor(st).cgColor); c.setLineWidth(CGFloat(w)); c.strokePath() }
            case let .polyline(ps, w, col, dash):
                guard let first = ps.first else { break }
                c.setStrokeColor(uiColor(col).cgColor); c.setLineWidth(CGFloat(w)); c.setLineJoin(.miter); c.setMiterLimit(6)
                if !dash.isEmpty { c.setLineDash(phase: 0, lengths: dash.map { CGFloat($0) }) }
                c.move(to: CGPoint(x: first.x, y: first.y))
                for p in ps.dropFirst() { c.addLine(to: CGPoint(x: p.x, y: p.y)) }
                c.strokePath()
            case let .text(s, at, size, bold, col, al, angle):
                let attrs = attributes(size, bold: bold, color: col, align: .left, wrap: false)
                let str = s as NSString
                let sz = str.size(withAttributes: attrs)
                c.translateBy(x: CGFloat(at.x), y: CGFloat(at.y))
                if angle != 0 { c.rotate(by: CGFloat(angle * .pi / 180)) }
                let x: CGFloat = al == .left ? 0 : al == .center ? -sz.width / 2 : -sz.width
                UIGraphicsPushContext(c)
                str.draw(at: CGPoint(x: x, y: -sz.height / 2), withAttributes: attrs)
                UIGraphicsPopContext()
            case let .textBox(s, r, size, bold, col, al):
                c.clip(to: cg(r).insetBy(dx: -1, dy: -1))
                UIGraphicsPushContext(c)
                (s as NSString).draw(with: cg(r), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                     attributes: attributes(size, bold: bold, color: col, align: al), context: nil)
                UIGraphicsPopContext()
            case let .photo(p, r):
                guard let img = photo(p) else { break }
                let f = r.fit(Double(img.size.width), Double(img.size.height))
                UIGraphicsPushContext(c)
                img.draw(in: cg(f))
                UIGraphicsPopContext()
            case let .checkbox(r, on):
                let rect = cg(r)
                c.setFillColor(on ? uiColor(.tick).cgColor : UIColor.white.cgColor); c.fill(rect)
                c.setStrokeColor(UIColor.black.cgColor); c.setLineWidth(0.7); c.stroke(rect)
                if on {
                    c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(1.3)
                    c.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.5))
                    c.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.75))
                    c.addLine(to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.25))
                    c.strokePath()
                }
            }
            c.restoreGState()
        }
    }

    /// A sketch as a PNG (used for the auto plan in the Excel frame).
    /// One sketch as a one-page PDF the sketch's size (the MP weekly-meeting page).
    public static func pdf(_ sketch: Sketch, title: String) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: sketch.width, height: sketch.height)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title]
        return UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { ctx in
            ctx.beginPage()
            draw(sketch.ops, in: ctx.cgContext, photo: { _ in nil })
        }
    }

    /// Pages not tied to a survey job (the routine reports), each at its own size.
    public static func pdf(pages: [ReportLayout.Page], title: String, photo: @escaping (Photo) -> UIImage?) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: ReportLayout.pageW, height: ReportLayout.pageH), format: format)
        return renderer.pdfData { ctx in
            for page in pages {
                ctx.beginPage(withBounds: CGRect(x: 0, y: 0, width: page.width, height: page.height), pageInfo: [:])
                draw(page.ops, in: ctx.cgContext, photo: photo)
            }
        }
    }

    public static func png(_ sketch: Sketch, scale: CGFloat = 2) -> (Data, Int, Int)? {
        let size = CGSize(width: sketch.width, height: sketch.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            draw(sketch.ops, in: ctx.cgContext, photo: { _ in nil })
        }
        guard let data = img.pngData() else { return nil }
        return (data, Int(size.width * scale), Int(size.height * scale))
    }
}
#endif
