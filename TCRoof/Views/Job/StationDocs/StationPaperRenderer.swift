import UIKit
import TCRoofCore

/// Draws a station paper the app drafts (`StationDocs.Letter`) as an A4 PDF: the company's letterhead, the number
/// and date, เรื่อง / เรียน, the paragraphs and the signature block. It is signed on paper.
enum StationPaperRenderer {
    static let page = BOQRenderer.page
    static let left: CGFloat = 64, right: CGFloat = 531
    static var width: CGFloat { right - left }

    static func pdf(_ letter: StationDocs.Letter, company: HomeCompany) -> Data {
        UIGraphicsPDFRenderer(bounds: page).pdfData { r in
            r.beginPage()
            var y = letterhead(company, r.cgContext)
            let body = BOQRenderer.font(12)
            BOQRenderer.text("ที่ " + letter.number, CGRect(x: left, y: y, width: width / 2, height: 18), body)
            y += 22
            BOQRenderer.text(letter.date, CGRect(x: left + width / 2, y: y, width: width / 2, height: 18), body)
            y += 28
            y = labelled("เรื่อง", letter.subject, at: y) + 6
            y = labelled("เรียน", letter.to, at: y) + 14
            for p in letter.paragraphs {
                let text = paragraph(p, indent: 48)
                let h = height(text, width)
                if y + h > page.height - 60 { r.beginPage(); y = 60 }
                text.draw(with: CGRect(x: left, y: y, width: width, height: h), options: .usesLineFragmentOrigin, context: nil)
                y += h + 8
            }
            if y > page.height - 190 { r.beginPage(); y = 60 }
            signature(letter, company: company, at: y + 22)
        }
    }

    private static func letterhead(_ c: HomeCompany, _ ctx: CGContext) -> CGFloat {
        var y: CGFloat = 44
        if !c.nameTH.isEmpty { BOQRenderer.text(c.nameTH, CGRect(x: left, y: y, width: width, height: 22), BOQRenderer.font(15, bold: true)); y += 21 }
        if !c.nameEN.isEmpty { BOQRenderer.text(c.nameEN, CGRect(x: left, y: y, width: width, height: 16), BOQRenderer.font(11, bold: true)); y += 16 }
        let contact = [c.address, c.phone.isEmpty ? "" : "โทร. " + c.phone].filter { !$0.isEmpty }.joined(separator: " | ")
        if !contact.isEmpty { BOQRenderer.text(contact, CGRect(x: left, y: y, width: width, height: 14), BOQRenderer.font(9)); y += 14 }
        if !c.isEmpty {
            ctx.setStrokeColor(BOQRenderer.ink.cgColor); ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: left, y: y + 4)); ctx.addLine(to: CGPoint(x: right, y: y + 4)); ctx.strokePath()
        }
        return y + 26
    }

    /// `เรื่อง  …` with the value wrapping under itself; returns the y below it.
    private static func labelled(_ label: String, _ value: String, at y: CGFloat) -> CGFloat {
        BOQRenderer.text(label, CGRect(x: left, y: y, width: 44, height: 18), BOQRenderer.font(12, bold: true))
        let text = paragraph(value, indent: 0)
        let h = max(18, height(text, width - 48))
        text.draw(with: CGRect(x: left + 48, y: y, width: width - 48, height: h), options: .usesLineFragmentOrigin, context: nil)
        return y + h
    }

    private static func signature(_ letter: StationDocs.Letter, company: HomeCompany, at y: CGFloat) {
        let x = left + width / 2, w = width / 2
        let f = BOQRenderer.font(12)
        BOQRenderer.text(letter.closing, CGRect(x: x, y: y, width: w, height: 18), f, align: .center)
        let name = letter.signer.isEmpty ? "(.................................................)" : "(\(letter.signer))"
        BOQRenderer.text(name, CGRect(x: x, y: y + 78, width: w, height: 18), f, align: .center)
        var line = y + 96
        for s in [letter.position, company.nameTH] where !s.isEmpty {
            BOQRenderer.text(s, CGRect(x: x, y: line, width: w, height: 18), f, align: .center)
            line += 18
        }
    }

    private static func paragraph(_ s: String, indent: CGFloat) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = indent
        p.lineSpacing = 4
        return NSAttributedString(string: s, attributes: [.font: BOQRenderer.font(12), .foregroundColor: BOQRenderer.ink, .paragraphStyle: p])
    }

    private static func height(_ s: NSAttributedString, _ width: CGFloat) -> CGFloat {
        ceil(s.boundingRect(with: CGSize(width: width, height: 2000), options: .usesLineFragmentOrigin, context: nil).height) + 2
    }
}
