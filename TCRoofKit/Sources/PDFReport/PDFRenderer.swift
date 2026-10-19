#if canImport(UIKit)
import UIKit
import CoreText
import TCRoofCore

/// Draws the NO.215 report into a PDF with the bundled Sarabun font.
public enum PDFRenderer {
    private static let registered: Bool = {
        for name in ["Sarabun-Regular", "Sarabun-Bold", "THSarabun"] {
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

    /// The font of a run: Sarabun, Helvetica, or TH Sarabun PSK (bundled, regular only).
    static func font(_ size: Double, bold: Bool, face: FontFace) -> UIFont {
        _ = registered
        switch face {
        case .sarabun: return font(size, bold: bold)
        case .helvetica:
            return UIFont(name: bold ? "Helvetica-Bold" : "Helvetica", size: CGFloat(size)) ?? font(size, bold: bold)
        case .thSarabun:
            return UIFont(name: "THSarabunPSK", size: CGFloat(size)) ?? font(size, bold: bold)
        }
    }

    static func attributed(_ runs: [TextRun], color: RGBA) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for r in runs {
            var a: [NSAttributedString.Key: Any] = [.font: font(r.size, bold: r.bold, face: r.face), .foregroundColor: uiColor(color)]
            if r.underline { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: r.text, attributes: a))
        }
        return out
    }

    /// A bundled picture a page names by its file (`FormImage`), when the caller's photos don't have it.
    static func bundled(_ p: Photo) -> UIImage? {
        guard let name = FormImage.resource(p) else { return nil }
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let url = Bundle.module.url(forResource: parts[0], withExtension: parts[1])
            ?? Bundle.module.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Resources")
        return url.flatMap { UIImage(contentsOfFile: $0.path) }
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
        public func width(_ runs: [TextRun]) -> Double { Double(PDFRenderer.attributed(runs, color: .black).size().width) }
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
            case let .photoFill(p, r):
                guard let img = photo(p) ?? bundled(p), img.size.width > 0, img.size.height > 0 else { break }
                let k = max(r.w / Double(img.size.width), r.h / Double(img.size.height))
                let w = Double(img.size.width) * k, h = Double(img.size.height) * k
                c.clip(to: cg(r))
                UIGraphicsPushContext(c)
                img.draw(in: CGRect(x: r.x + (r.w - w) / 2, y: r.y + (r.h - h) / 2, width: w, height: h))
                UIGraphicsPopContext()
            case let .runs(rs, at, col, al):
                let str = attributed(rs, color: col)
                let sz = str.size()
                let x: CGFloat = al == .left ? 0 : al == .center ? -sz.width / 2 : -sz.width
                UIGraphicsPushContext(c)
                str.draw(at: CGPoint(x: CGFloat(at.x) + x, y: CGFloat(at.y) - sz.height / 2))
                UIGraphicsPopContext()
            case let .photo(p, r):
                guard let img = photo(p) ?? bundled(p) else { break }
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
        let first = pages.first.map { CGRect(x: 0, y: 0, width: $0.width, height: $0.height) }
            ?? CGRect(x: 0, y: 0, width: ReportLayout.pageW, height: ReportLayout.pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: first, format: format)
        return renderer.pdfData { ctx in
            for page in pages {
                // the bounds alone don't reach the file: each page names its own media box (Letter forms beside A4 reports)
                var box = CGRect(x: 0, y: 0, width: page.width, height: page.height)
                let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)]
                ctx.beginPage(withBounds: box, pageInfo: info)
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
