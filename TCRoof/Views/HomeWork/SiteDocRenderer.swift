import SwiftUI
import UIKit
import TCRoofUI
import TCRoofCore

/// The papers that go to the installer — work order, delivery note, change request, acceptance — as one-page A4
/// PDFs in the BOQ's letterhead: a title, key facts, a table, notes, and the signatures taken in the app.
enum SiteDocRenderer {
    struct Doc {
        var title: String
        var number: String
        var facts: [(String, String)]
        var columns: [(String, CGFloat, NSTextAlignment)] = []
        var rows: [[String]] = []
        var notes: [String] = []
        /// Role under the line, the signature (nil = blank line to sign on paper).
        var signatures: [(String, HomeSignature?)] = []
    }

    static let page = BOQRenderer.page
    static let left = BOQRenderer.left, right = BOQRenderer.right

    static func pdf(_ doc: Doc, company: HomeCompany, store: PermitStore) -> Data {
        UIGraphicsPDFRenderer(bounds: page).pdfData { r in
            r.beginPage()
            let ctx = r.cgContext
            var y = letterhead(company, ctx)
            BOQRenderer.text(doc.title, CGRect(x: left, y: y, width: right - left, height: 20), BOQRenderer.font(14, bold: true), align: .center)
            y += 22
            if !doc.number.isEmpty {
                BOQRenderer.text("เลขที่ " + doc.number, CGRect(x: left, y: y, width: right - left, height: 14), BOQRenderer.font(9), align: .center)
                y += 18
            }
            for (k, v) in doc.facts {
                BOQRenderer.text(k, CGRect(x: left, y: y, width: 150, height: 14), BOQRenderer.font(9.5, bold: true))
                let h = height(v, width: right - left - 155)
                BOQRenderer.text(v, CGRect(x: left + 155, y: y, width: right - left - 155, height: h), BOQRenderer.font(9.5))
                y += max(15, h + 2)
            }
            y += 6
            if !doc.columns.isEmpty { y = table(doc, at: y, ctx, r) }
            for n in doc.notes {
                let h = height(n, width: right - left)
                if y + h > page.height - 150 { r.beginPage(); y = 40 }
                BOQRenderer.text(n, CGRect(x: left, y: y, width: right - left, height: h), BOQRenderer.font(9.5))
                y += h + 4
            }
            if y > page.height - 140 { r.beginPage(); y = 40 }
            signatures(doc.signatures, at: max(y + 20, page.height - 140), store: store, ctx)
        }
    }

    static func height(_ s: String, width: CGFloat) -> CGFloat {
        let r = (s as NSString).boundingRect(with: CGSize(width: width, height: 1000), options: [.usesLineFragmentOrigin],
                                             attributes: [.font: BOQRenderer.font(9.5)], context: nil)
        return ceil(r.height) + 2
    }

    static func letterhead(_ c: HomeCompany, _ ctx: CGContext) -> CGFloat {
        var y: CGFloat = 32
        if !c.nameTH.isEmpty { BOQRenderer.text(c.nameTH, CGRect(x: left, y: y, width: 535, height: 20), BOQRenderer.font(13, bold: true)); y += 18 }
        if !c.nameEN.isEmpty { BOQRenderer.text(c.nameEN, CGRect(x: left, y: y, width: 535, height: 16), BOQRenderer.font(10.5, bold: true)); y += 15 }
        if !c.address.isEmpty { BOQRenderer.text(c.address, CGRect(x: left, y: y, width: 535, height: 13), BOQRenderer.font(8.5)); y += 12 }
        if !c.isEmpty {
            ctx.setStrokeColor(BOQRenderer.ink.cgColor); ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: left, y: y + 3)); ctx.addLine(to: CGPoint(x: right, y: y + 3)); ctx.strokePath()
        }
        return y + 16
    }

    static func table(_ doc: Doc, at y0: CGFloat, _ ctx: CGContext, _ r: UIGraphicsPDFRendererContext) -> CGFloat {
        let total = doc.columns.reduce(0) { $0 + $1.1 }
        let scale = (right - left) / max(total, 1)
        var xs: [CGFloat] = [left]
        for c in doc.columns { xs.append(xs.last! + c.1 * scale) }
        func header(_ y: CGFloat) -> CGFloat {
            ctx.setFillColor(BOQRenderer.band.cgColor)
            ctx.fill(CGRect(x: left, y: y, width: right - left, height: 18))
            for (i, c) in doc.columns.enumerated() {
                BOQRenderer.stroke(ctx, CGRect(x: xs[i], y: y, width: xs[i + 1] - xs[i], height: 18))
                BOQRenderer.text(c.0, CGRect(x: xs[i] + 2, y: y + 3, width: xs[i + 1] - xs[i] - 4, height: 13), BOQRenderer.font(8.5, bold: true), align: .center)
            }
            return y + 18
        }
        var y = header(y0)
        for row in doc.rows {
            let h = max(16, row.enumerated().map { i, s in i < doc.columns.count ? height(s, width: xs[i + 1] - xs[i] - 6) : 0 }.max() ?? 16)
            if y + h > page.height - 160 { r.beginPage(); y = header(40) }
            for (i, s) in row.enumerated() where i < doc.columns.count {
                BOQRenderer.stroke(ctx, CGRect(x: xs[i], y: y, width: xs[i + 1] - xs[i], height: h))
                BOQRenderer.text(s, CGRect(x: xs[i] + 3, y: y + 1.5, width: xs[i + 1] - xs[i] - 6, height: h), BOQRenderer.font(9), align: doc.columns[i].2)
            }
            y += h
        }
        return y + 10
    }

    static func signatures(_ sigs: [(String, HomeSignature?)], at y: CGFloat, store: PermitStore, _ ctx: CGContext) {
        guard !sigs.isEmpty else { return }
        let w = (right - left) / CGFloat(sigs.count)
        for (i, (role, sig)) in sigs.enumerated() {
            let x = left + CGFloat(i) * w
            let box = CGRect(x: x + 20, y: y, width: w - 40, height: 60)
            if let sig, let data = store.photo(sig.file), let img = UIImage(data: data) {
                let s = min(box.width / img.size.width, box.height / img.size.height)
                let size = CGSize(width: img.size.width * s, height: img.size.height * s)
                img.draw(in: CGRect(x: box.midX - size.width / 2, y: box.maxY - size.height, width: size.width, height: size.height))
            }
            ctx.setStrokeColor(BOQRenderer.ink.cgColor); ctx.setLineWidth(0.6)
            ctx.move(to: CGPoint(x: box.minX, y: box.maxY + 2)); ctx.addLine(to: CGPoint(x: box.maxX, y: box.maxY + 2)); ctx.strokePath()
            let name = sig.map { "(\($0.name))" } ?? "(.................................................)"
            BOQRenderer.text(name, CGRect(x: x, y: box.maxY + 6, width: w, height: 13), BOQRenderer.font(9), align: .center)
            BOQRenderer.text(role, CGRect(x: x, y: box.maxY + 20, width: w, height: 13), BOQRenderer.font(9, bold: true), align: .center)
            let date = sig.map { "วันที่ " + PermitDate.long($0.at) } ?? "วันที่ ......../......../........"
            BOQRenderer.text(date, CGRect(x: x, y: box.maxY + 34, width: w, height: 13), BOQRenderer.font(8.5), align: .center)
        }
    }
}

/// Name and finger/Pencil signature, saved as a PNG in the job's folder.
struct SiteSignatureSheet: View {
    let title: String
    var defaultName = ""
    let store: PermitStore
    let done: (HomeSignature?) -> Void

    @State private var name = ""
    @State private var png: Data?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.l) {
                PermitField("ชื่อผู้ลงนาม", text: $name, required: true)
                TCFieldLabel("ลายเซ็น")
                AccountSignatureCanvas(signature: $png)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .accessibilityLabel("ช่องลายเซ็น")
                MySignatureActions(signature: $png)
                TCButton("ล้างลายเซ็น", systemImage: "eraser", kind: .secondary, size: .card) { png = nil }
                Spacer()
            }
            .padding(Space.l)
            .tcPageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { done(nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") {
                        guard let png else { return }
                        done(HomeSignature(name: name.trimmingCharacters(in: .whitespaces), file: store.addFile(png, ext: "png")))
                    }
                    .disabled(png == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if name.isEmpty { name = defaultName } }
        }
    }
}
