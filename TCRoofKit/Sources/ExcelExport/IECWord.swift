import Foundation
import TCRoofCore

/// The IEC 62446 test's photo appendix as Word (docs/specs/iec62446-word-appendix-swift.md, approach B: built from
/// the layout of docs/forms/iec62446-pwa/README.md §2, since the customer's .docx isn't in the repo). A4 portrait,
/// the same header on every page (project, station line, title, the PWA and PEA logos of the Excel form), then:
/// the before cover, each string's voltage and current photos (3 strings a page), the after cover and the same
/// after, the IR screens (6 a page), the irradiance meter, and the thermal images. A missing photo leaves its frame
/// with `ไม่มีรูป`, so the gap shows.
public enum IECWord {
    public enum Failure: Error, Equatable { case noStrings }

    /// `IEC62446 ภาพถ่าย <station> 2026-10-15.docx`.
    public static func fileName(station: String, date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "Asia/Bangkok")!, from: date)
        let name = station.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        return String(format: "IEC62446 ภาพถ่าย %@ %04d-%02d-%02d.docx", name, c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static let project = "โครงการจัดการพลังงานไฟฟ้าจากระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์ที่ติดตั้งบนหลังคา (Solar Rooftop) การประปาส่วนภูมิภาค"
    static let title = "ภาพถ่ายการตรวจสอบระบบก่อนและหลังการเชื่อมต่อระบบ ตามมาตรฐาน IEC 62446"
    static let font = "TH Sarabun New"

    /// `photos`: the report's photo ids → JPEG bytes (already downscaled by the app). `logos`: PNG / JPEG for the
    /// header; the Excel form's own when nil.
    public static func export(_ r: IECReport, photos: [String: Data], logos: [Data]? = nil) throws -> Data {
        guard r.stringCount > 0 else { throw Failure.noStrings }
        var doc = Builder()
        let header = try doc.header(r, logos: logos ?? formLogos())
        var body = ""
        body += doc.cover("(ก่อนการเชื่อมต่อระบบ)", first: true)
        body += doc.voltagePages(r, photos, after: false)
        body += doc.cover("(หลังการเชื่อมต่อระบบ)")
        body += doc.voltagePages(r, photos, after: true)
        body += doc.insulationPages(r, photos)
        body += doc.irradiancePage(r, photos)
        body += doc.thermalPages(r, photos)
        return try doc.package(body: body, header: header)
    }

    /// The PWA and PEA logos of `iec62446_template.xlsx` (`xl/media/image1.jpeg`, `image2.png`).
    public static func formLogos() throws -> [Data] {
        let zip = try ZipArchive(IECExcel.template())
        return ["xl/media/image1.jpeg", "xl/media/image2.png"].compactMap { zip.data($0) }
    }

    /// Pixel size of a JPEG (its SOF marker) or PNG (IHDR); nil for anything else.
    static func pixelSize(_ data: Data) -> (w: Int, h: Int)? {
        let b = [UInt8](data)
        if b.count > 24, b[0] == 0x89, b[1] == 0x50 {
            func u32(_ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) }
            return (u32(16), u32(20))
        }
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let m = b[i + 1]
            if m == 0xD8 || m == 0x01 || (0xD0...0xD7).contains(m) { i += 2; continue }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if (0xC0...0xCF).contains(m), m != 0xC4, m != 0xC8, m != 0xCC {
                return (Int(b[i + 7]) << 8 | Int(b[i + 8]), Int(b[i + 5]) << 8 | Int(b[i + 6]))
            }
            i += 2 + len
        }
        return nil
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - builder

    struct Builder {
        /// word/media/… with the part that refers to each (document or header).
        var media: [(path: String, data: Data)] = []
        var documentRels: [String] = []
        var headerRels: [String] = []
        var drawingID = 0

        static let emuPerInch = 914_400.0
        /// A4 at 2 cm sides: 11906 − 2 × 1134 twips = 6.69 in.
        static let contentInches = 6.69

        // MARK: text

        func run(_ text: String, size: Int = 16, bold: Bool = false, color: String? = nil) -> String {
            let props = "<w:rFonts w:ascii=\"\(IECWord.font)\" w:hAnsi=\"\(IECWord.font)\" w:cs=\"\(IECWord.font)\"/>"
                + (bold ? "<w:b/><w:bCs/>" : "") + (color.map { "<w:color w:val=\"\($0)\"/>" } ?? "")
                + "<w:sz w:val=\"\(size * 2)\"/><w:szCs w:val=\"\(size * 2)\"/>"
            return "<w:r><w:rPr>\(props)</w:rPr><w:t xml:space=\"preserve\">\(IECWord.escape(text))</w:t></w:r>"
        }

        func paragraph(_ runs: String, align: String = "left", pageBreakBefore: Bool = false, spacingAfter: Int = 60) -> String {
            "<w:p><w:pPr>" + (pageBreakBefore ? "<w:pageBreakBefore/>" : "")
                + "<w:spacing w:before=\"0\" w:after=\"\(spacingAfter)\"/><w:jc w:val=\"\(align)\"/></w:pPr>\(runs)</w:p>"
        }

        // MARK: pictures

        /// An inline picture fitted inside `w` × `h` inches keeping its aspect, or nil for bytes it can't size.
        mutating func picture(_ data: Data, maxW: Double, maxH: Double, inHeader: Bool = false) -> String? {
            guard let px = IECWord.pixelSize(data), px.w > 0, px.h > 0 else { return nil }
            let scale = min(maxW / Double(px.w), maxH / Double(px.h))
            let cx = Int(Double(px.w) * scale * Self.emuPerInch), cy = Int(Double(px.h) * scale * Self.emuPerInch)
            let ext = data.first == 0x89 ? "png" : "jpeg"
            let n = media.count + 1
            media.append(("word/media/image\(n).\(ext)", data))
            let rId = "rIdImg\(n)"
            let rel = "<Relationship Id=\"\(rId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/image\(n).\(ext)\"/>"
            if inHeader { headerRels.append(rel) } else { documentRels.append(rel) }
            drawingID += 1
            let id = drawingID
            return "<w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/>"
                + "<wp:docPr id=\"\(id)\" name=\"Picture \(id)\"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=\"1\"/></wp:cNvGraphicFramePr>"
                + "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic>"
                + "<pic:nvPicPr><pic:cNvPr id=\"\(id)\" name=\"image\(n).\(ext)\"/><pic:cNvPicPr/></pic:nvPicPr>"
                + "<pic:blipFill><a:blip r:embed=\"\(rId)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
                + "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr>"
                + "</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>"
        }

        /// A photo, or the `ไม่มีรูป` frame of the same height.
        mutating func photoOrGap(_ id: String?, _ photos: [String: Data], maxW: Double, maxH: Double) -> String {
            if let id, let data = photos[id], let pic = picture(data, maxW: maxW, maxH: maxH) { return paragraph(pic, align: "center", spacingAfter: 0) }
            let half = Int(maxH * 1440 / 2) - 200
            return "<w:p><w:pPr><w:spacing w:before=\"\(max(half, 0))\" w:after=\"\(max(half, 0))\"/><w:jc w:val=\"center\"/></w:pPr>\(run("ไม่มีรูป", size: 16, color: "9AA6B6"))</w:p>"
        }

        // MARK: tables

        /// One page's table: `columns` equal columns, each cell its label and content; rows never split across pages.
        func table(columns: Int, cells: [String], pageBreakBefore: Bool) -> String {
            let width = Int(Self.contentInches * 1440), colW = width / columns
            let grid = String(repeating: "<w:gridCol w:w=\"\(colW)\"/>", count: columns)
            var rows = ""
            for start in stride(from: 0, to: cells.count, by: columns) {
                var tcs = ""
                for k in 0..<columns {
                    let content = start + k < cells.count ? cells[start + k] : paragraph("")
                    tcs += "<w:tc><w:tcPr><w:tcW w:w=\"\(colW)\" w:type=\"dxa\"/><w:vAlign w:val=\"center\"/></w:tcPr>\(content)</w:tc>"
                }
                rows += "<w:tr><w:trPr><w:cantSplit/></w:trPr>\(tcs)</w:tr>"
            }
            let border = { (side: String) in "<w:\(side) w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"8C959F\"/>" }
            let borders = ["top", "left", "bottom", "right", "insideH", "insideV"].map(border).joined()
            let lead = pageBreakBefore ? paragraph("", pageBreakBefore: true, spacingAfter: 0) : ""
            return lead + "<w:tbl><w:tblPr><w:tblW w:w=\"\(width)\" w:type=\"dxa\"/><w:tblBorders>\(borders)</w:tblBorders>"
                + "<w:tblLayout w:type=\"fixed\"/><w:tblCellMar><w:top w:w=\"60\" w:type=\"dxa\"/><w:bottom w:w=\"60\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr>"
                + "<w:tblGrid>\(grid)</w:tblGrid>\(rows)</w:tbl>"
        }

        // MARK: parts

        func cover(_ text: String, first: Bool = false) -> String {
            // a third of the way down, in red, as the original's covers
            paragraph("", pageBreakBefore: !first, spacingAfter: 4200)
                + paragraph(run(text, size: 28, bold: true, color: "C00000"), align: "center")
        }

        /// Every string in inverter order with its label (`INV1ST3`), as the Word counts the used strings.
        func strings(_ r: IECReport) -> [(label: String, slot: IECReport.Slot, inverter: Int, seq: Int)] {
            r.inverters.enumerated().flatMap { i, inv in inv.strings.map { (IECReport.label(inverter: i + 1, seq: $0.seq), $0.value, i + 1, $0.seq) } }
        }

        /// Parts 2 and 4: one row per string with the voltage meter and the clamp side by side, 3 strings a page.
        mutating func voltagePages(_ r: IECReport, _ photos: [String: Data], after: Bool) -> String {
            let phase = after ? "หลังการเชื่อมต่อระบบ" : "ก่อนการเชื่อมต่อระบบ"
            let (v, a): (IECReport.PhotoKind, IECReport.PhotoKind) = after ? (.voltageAfter, .currentAfter) : (.voltageBefore, .currentBefore)
            var out = ""
            let all = strings(r)
            for start in stride(from: 0, to: all.count, by: 3) {
                var cells: [String] = []
                for s in all[start..<min(start + 3, all.count)] {
                    let label = paragraph(run("Voltage testing และ Current testing \(s.label) (\(phase))", size: 16, bold: true), spacingAfter: 40)
                    let pair = table2(photoOrGap(s.slot.photo(v), photos, maxW: 3.15, maxH: 2.45), photoOrGap(s.slot.photo(a), photos, maxW: 3.15, maxH: 2.45))
                    cells.append(label + pair + paragraph("", spacingAfter: 0))
                }
                out += table(columns: 1, cells: cells, pageBreakBefore: true)
            }
            return out
        }

        /// Two photos side by side inside a cell, without borders.
        func table2(_ left: String, _ right: String) -> String {
            let w = Int((Self.contentInches - 0.2) * 1440 / 2)
            let cell = { (c: String) in "<w:tc><w:tcPr><w:tcW w:w=\"\(w)\" w:type=\"dxa\"/></w:tcPr>\(c)</w:tc>" }
            return "<w:tbl><w:tblPr><w:tblW w:w=\"\(w * 2)\" w:type=\"dxa\"/><w:jc w:val=\"center\"/><w:tblLayout w:type=\"fixed\"/></w:tblPr>"
                + "<w:tblGrid><w:gridCol w:w=\"\(w)\"/><w:gridCol w:w=\"\(w)\"/></w:tblGrid><w:tr>\(cell(left))\(cell(right))</w:tr></w:tbl>"
        }

        /// Part 5: the IR tester's screen, 2 columns, 6 strings a page.
        mutating func insulationPages(_ r: IECReport, _ photos: [String: Data]) -> String {
            var out = ""
            let all = strings(r)
            for start in stride(from: 0, to: all.count, by: 6) {
                let cells = all[start..<min(start + 6, all.count)].map { s -> String in
                    paragraph(run("Insulation Resistance testing INV\(s.inverter) ST\(s.seq)", size: 16, bold: true), align: "center", spacingAfter: 40)
                        + photoOrGap(s.slot.photo(.insulation), photos, maxW: 3.1, maxH: 2.55)
                }
                out += table(columns: 2, cells: Array(cells), pageBreakBefore: true)
            }
            return out
        }

        /// Part 6: the irradiance meter's screen.
        mutating func irradiancePage(_ r: IECReport, _ photos: [String: Data]) -> String {
            let cell = paragraph(run("ความเข้มแสงอาทิตย์ (W/m²)", size: 18, bold: true), align: "center")
                + photoOrGap(r.irradiancePhoto, photos, maxW: 5.5, maxH: 4.5)
            return table(columns: 1, cells: [cell], pageBreakBefore: true)
        }

        /// Part 7 (the Excel's row 27 `เอกสารแนบ`): the thermal images with their places, 6 a page; none, no part.
        mutating func thermalPages(_ r: IECReport, _ photos: [String: Data]) -> String {
            var out = ""
            for start in stride(from: 0, to: r.thermalPhotos.count, by: 6) {
                let cells = r.thermalPhotos[start..<min(start + 6, r.thermalPhotos.count)].enumerated().map { k, id -> String in
                    let place = r.thermalPlaces[id].map { " · " + $0 } ?? ""
                    return paragraph(run("ภาพถ่ายความร้อน \(start + k + 1)\(place)", size: 16, bold: true), align: "center", spacingAfter: 40)
                        + photoOrGap(id, photos, maxW: 3.1, maxH: 2.55)
                }
                out += table(columns: 2, cells: Array(cells), pageBreakBefore: true)
            }
            return out
        }

        /// The header: project, station line and title on the left, the logos on the right.
        mutating func header(_ r: IECReport, logos: [Data]) throws -> String {
            let text = paragraph(run(IECWord.project, size: 14, bold: true), spacingAfter: 0)
                + paragraph(run(r.stationLine, size: 14), spacingAfter: 0)
                + paragraph(run(IECWord.title, size: 14, bold: true), spacingAfter: 0)
            let pics = logos.compactMap { picture($0, maxW: 0.62, maxH: 0.62, inHeader: true) }.joined(separator: run(" ", size: 8))
            let left = Int(5.4 * 1440), right = Int(Self.contentInches * 1440) - left
            return "<w:tbl><w:tblPr><w:tblW w:w=\"\(left + right)\" w:type=\"dxa\"/><w:tblLayout w:type=\"fixed\"/>"
                + "<w:tblBorders><w:bottom w:val=\"single\" w:sz=\"8\" w:space=\"0\" w:color=\"16325C\"/></w:tblBorders></w:tblPr>"
                + "<w:tblGrid><w:gridCol w:w=\"\(left)\"/><w:gridCol w:w=\"\(right)\"/></w:tblGrid><w:tr>"
                + "<w:tc><w:tcPr><w:tcW w:w=\"\(left)\" w:type=\"dxa\"/><w:vAlign w:val=\"center\"/></w:tcPr>\(text)</w:tc>"
                + "<w:tc><w:tcPr><w:tcW w:w=\"\(right)\" w:type=\"dxa\"/><w:vAlign w:val=\"center\"/></w:tcPr>\(paragraph(pics, align: "right", spacingAfter: 0))</w:tc>"
                + "</w:tr></w:tbl>" + paragraph("", spacingAfter: 0)
        }

        // MARK: package

        static let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
            + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
            + "xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" "
            + "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
            + "xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\""

        func package(body: String, header: String) throws -> Data {
            let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
            let sect = "<w:sectPr><w:headerReference w:type=\"default\" r:id=\"rIdHeader\"/><w:pgSz w:w=\"11906\" w:h=\"16838\"/>"
                + "<w:pgMar w:top=\"2268\" w:right=\"1134\" w:bottom=\"1134\" w:left=\"1134\" w:header=\"567\" w:footer=\"567\" w:gutter=\"0\"/></w:sectPr>"
            let document = xml + "<w:document \(Self.ns)><w:body>\(body)\(sect)</w:body></w:document>"
            let headerXML = xml + "<w:hdr \(Self.ns)>\(header)</w:hdr>"
            let rels = { (items: [String]) in
                xml + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + items.joined() + "</Relationships>"
            }
            let docRels = ["<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>",
                           "<Relationship Id=\"rIdSettings\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/>",
                           "<Relationship Id=\"rIdHeader\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"header1.xml\"/>"] + documentRels
            let styles = xml + "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:docDefaults><w:rPrDefault><w:rPr>"
                + "<w:rFonts w:ascii=\"\(IECWord.font)\" w:hAnsi=\"\(IECWord.font)\" w:cs=\"\(IECWord.font)\" w:eastAsia=\"\(IECWord.font)\"/>"
                + "<w:sz w:val=\"32\"/><w:szCs w:val=\"32\"/><w:lang w:val=\"th-TH\" w:bidi=\"th-TH\"/></w:rPr></w:rPrDefault>"
                + "<w:pPrDefault><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault></w:docDefaults>"
                + "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style></w:styles>"
            let settings = xml + "<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:defaultTabStop w:val=\"720\"/>"
                + "<w:compat><w:compatSetting w:name=\"compatibilityMode\" w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"15\"/></w:compat></w:settings>"
            let types = xml + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
                + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
                + "<Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/>"
                + "<Default Extension=\"png\" ContentType=\"image/png\"/>"
                + "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>"
                + "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>"
                + "<Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/>"
                + "<Override PartName=\"/word/header1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/>"
                + "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/></Types>"
            let core = xml + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" "
                + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>\(IECWord.escape(IECWord.title))</dc:title><dc:creator>TCRoof</dc:creator></cp:coreProperties>"
            var zip = ZipArchive()
            zip.set("[Content_Types].xml", types)
            zip.set("_rels/.rels", rels(["<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>",
                                         "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>"]))
            zip.set("word/document.xml", document)
            zip.set("word/_rels/document.xml.rels", rels(docRels))
            zip.set("word/header1.xml", headerXML)
            zip.set("word/_rels/header1.xml.rels", rels(headerRels))
            zip.set("word/styles.xml", styles)
            zip.set("word/settings.xml", settings)
            zip.set("docProps/core.xml", core)
            for m in media { zip.set(m.path, m.data) }
            return try zip.write()
        }
    }
}
