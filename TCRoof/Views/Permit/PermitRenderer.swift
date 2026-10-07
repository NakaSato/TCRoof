import UIKit
import SwiftUI
import TCRoofCore
import TCRoofUI

/// Draws a PEA permit form: the original PEA PDF page, untouched (its own fonts and layout), with the answers
/// written on top at the positions of `PermitFormMap`. The preview and the exported PDF use the same drawing.
enum PermitRenderer {
    struct Content {
        var values: [String: String]
        var marks: [String: PermitMark]
        /// Photo pages by area key (`att1` … `att10`).
        var attachments: [String: AttachmentPage] = [:]
    }

    /// The photos of one attachment page, already turned, in page order.
    struct AttachmentPage {
        struct Item {
            var image: UIImage
            var fit: AttachmentPhotoInfo.Fit
            var highlights: [[Double]]
            var caption: String
        }
        var layout: PhotoLayout = .auto
        var captions = true
        var items: [Item] = []
    }

    /// Answers sit this far above the dotted line so Thai descenders stay clear of it.
    static let lift: CGFloat = 2.5
    /// Answers are written in the paper's value colour, always its light value (the page is white).
    static var ink: UIColor { UIColor(Theme.paperValue).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)) }

    static func pageSize(_ map: PermitFormMap) -> CGSize { CGSize(width: map.pageSize[0], height: map.pageSize[1]) }

    static func document(_ map: PermitFormMap) -> CGPDFDocument? {
        PermitFormMap.templateURL(map.template).flatMap { CGPDFDocument($0 as CFURL) }
    }

    // MARK: Output

    /// All pages as one PDF, vector: the template page is copied as is and the answers are real text.
    static func pdf(_ map: PermitFormMap, _ content: Content) -> Data? {
        guard let doc = document(map) else { return nil }
        let bounds = CGRect(origin: .zero, size: pageSize(map))
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { r in
            for i in 0..<map.pages {
                r.beginPage()
                draw(page: i, map: map, document: doc, content: content, in: r.cgContext)
            }
        }
    }

    /// One page as an image for the on-screen preview.
    static func image(page: Int, _ map: PermitFormMap, _ content: Content, document: CGPDFDocument?, scale: CGFloat = 2) -> UIImage? {
        guard let document else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: pageSize(map), format: format).image { r in
            draw(page: page, map: map, document: document, content: content, in: r.cgContext)
        }
    }

    // MARK: Drawing

    static func draw(page index: Int, map: PermitFormMap, document: CGPDFDocument, content: Content, in ctx: CGContext) {
        let bounds = CGRect(origin: .zero, size: pageSize(map))
        UIColor.white.setFill()
        ctx.fill(bounds)
        if let page = document.page(at: index + 1) {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.concatenate(page.getDrawingTransform(.mediaBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
            ctx.drawPDFPage(page)
            ctx.restoreGState()
        }
        for area in map.areas where area.page == index {
            if let page = content.attachments[area.key] { drawPhotos(page, in: area.rect, ctx) }
        }
        for field in map.fields where field.page == index {
            if let text = content.values[field.key]?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
                drawText(text, field, size: map.fontSize)
            }
        }
        for check in map.checks where check.page == index {
            if let mark = content.marks[check.key] { drawMark(mark, in: rect(check.rect), ctx) }
        }
    }

    static func rect(_ r: [Double]) -> CGRect { CGRect(x: r[0], y: r[1], width: r[2], height: r[3]) }

    static func font(_ size: CGFloat) -> UIFont { UIFont(name: "Sarabun-Regular", size: size) ?? .systemFont(ofSize: size) }

    /// The value on its blank, shrunk (down to 8 pt) to stay between the blank's ends.
    static func drawText(_ text: String, _ field: PermitFormMap.Field, size: Double) {
        let room = CGFloat(field.x1 - field.x0) - 4
        var s = CGFloat(size)
        var f = font(s)
        var str = NSAttributedString(string: text, attributes: [.font: f, .foregroundColor: ink])
        while str.size().width > room && s > 8 {
            s -= 0.5
            f = font(s)
            str = NSAttributedString(string: text, attributes: [.font: f, .foregroundColor: ink])
        }
        let w = min(str.size().width, room)
        let x = field.align == .left ? CGFloat(field.x0) + 2 : CGFloat(field.x0) + (CGFloat(field.x1 - field.x0) - w) / 2
        let top = CGFloat(field.baseline) - lift - f.ascender
        str.draw(with: CGRect(x: x, y: top, width: room + 2, height: f.lineHeight + 4),
                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    /// ✓ or – inside the printed box.
    static func drawMark(_ mark: PermitMark, in r: CGRect, _ ctx: CGContext) {
        let path = UIBezierPath()
        switch mark {
        case .yes:
            path.move(to: CGPoint(x: r.minX + 2.2, y: r.minY + r.height * 0.55))
            path.addLine(to: CGPoint(x: r.minX + r.width * 0.42, y: r.maxY - 2.3))
            path.addLine(to: CGPoint(x: r.maxX - 1.8, y: r.minY + 2))
        case .no:
            path.move(to: CGPoint(x: r.minX + 2.5, y: r.midY))
            path.addLine(to: CGPoint(x: r.maxX - 2.5, y: r.midY))
        }
        ink.setStroke()
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// Light colours of the paper tokens: the page is printed on white whatever the device theme.
    static func paper(_ color: Color) -> UIColor { UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)) }

    /// Photos in the cells of the page's layout: every picture box gets the same thin frame; `fill` photos are
    /// cropped to it, `fit` photos (documents) sit whole on a light grey mat; red marks; a numbered caption under each.
    static func drawPhotos(_ page: AttachmentPage, in area: [Double], _ ctx: CGContext) {
        let cells = page.layout.cells(in: area, count: page.items.count)
        for (item, cell) in zip(page.items, cells) {
            let box = rect(PhotoFrame.pictureBox(cell: cell, caption: page.captions))
            let drawn = PhotoFrame.placement(size: [Double(item.image.size.width), Double(item.image.size.height)],
                                             in: PhotoFrame.pictureBox(cell: cell, caption: page.captions), fit: item.fit)
            ctx.saveGState()
            ctx.clip(to: box)
            if item.fit == .fit {
                paper(Theme.paperPage).setFill()
                ctx.fill(box)
            }
            item.image.draw(in: rect(drawn))
            paper(Theme.danger).setStroke()
            for h in item.highlights where h.count == 4 {
                let r = UIBezierPath(rect: rect(PhotoFrame.highlight(h, drawn: drawn)).intersection(box.insetBy(dx: 0.75, dy: 0.75)))
                r.lineWidth = 1.5
                r.stroke()
            }
            ctx.restoreGState()

            let frame = UIBezierPath(rect: box)
            frame.lineWidth = 0.5
            paper(Theme.borderControl).setStroke()
            frame.stroke()

            if page.captions { drawCaption(item.caption, in: rect(PhotoFrame.captionBox(cell: cell))) }
        }
    }

    static func drawCaption(_ text: String, in box: CGRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let f = font(PhotoFrame.captionFontSize)
        let str = NSAttributedString(string: text, attributes: [.font: f, .foregroundColor: paper(Theme.paperInk), .paragraphStyle: style])
        str.draw(with: CGRect(x: box.minX, y: box.minY + 2, width: box.width, height: box.height + 2),
                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
}
