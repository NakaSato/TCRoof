import Foundation
import TCRoofCore

/// The engineer's BOQ as the company's Excel workbook (`boq_template.xlsx`, made from the company's own file):
/// sheet Cost with real quantities and unit prices, sheet Sent with each line as one lot for the customer.
/// Row styles come from the template's prototype rows; every amount is a live formula with its value cached, so
/// the file reads right in Excel, Numbers and Quick Look alike.
public enum BOQExcel {
    public enum Failure: Error, LocalizedError {
        case template
        public var errorDescription: String? { "แม่แบบ BOQ เสียหาย" }
    }

    /// Prototype rows of the template.
    enum Proto {
        static let section = 17, item = 18, spacer = 21, single = 48, last = 52
        static let totals = Array(53...58)
    }

    public static func export(_ boq: HomeBOQ, template: Data? = nil) throws -> Data {
        guard let data = template ?? ExcelExporter.resource("boq_template", "xlsx") else { throw Failure.template }
        var zip = try ZipArchive(data)
        var wb = zip.string("xl/workbook.xml") ?? ""
        for (path, name, customer) in [("xl/worksheets/sheet1.xml", "Cost", false), ("xl/worksheets/sheet2.xml", "Sent", true)] {
            guard let xml = zip.string(path) else { throw Failure.template }
            let (out, last) = try sheet(xml, boq: boq, customer: customer)
            zip.set(path, out)
            let area = NSRegularExpression.escapedTemplate(for: "\(name)!$A$1:$M$\(last + 1)")
            wb = wb.replacingOccurrences(of: #"\#(name)!\$A\$1:\$M\$\d+"#, with: area, options: .regularExpression)
        }
        zip.set("xl/workbook.xml", wb)
        return try zip.write()
    }

    // MARK: One sheet

    struct Row {
        var number: Int
        var xml: String
    }

    static func sheet(_ xml: String, boq: HomeBOQ, customer: Bool) throws -> (String, Int) {
        guard let a = xml.range(of: "<sheetData>"), let b = xml.range(of: "</sheetData>") else { throw Failure.template }
        let head = String(xml[..<a.upperBound]), body = String(xml[a.upperBound..<b.lowerBound])
        var tail = String(xml[b.lowerBound...])
        var protos: [Int: String] = [:]
        var header: [String] = []
        for r in rows(body) {
            guard let n = rowNumber(r) else { continue }
            if n <= 16 { header.append(r) } else { protos[n] = r }
        }
        guard let pSection = protos[Proto.section], let pItem = protos[Proto.item], let pSpacer = protos[Proto.spacer],
              let pSingle = protos[Proto.single], let pLast = protos[Proto.last] else { throw Failure.template }

        // header: number, dates, project, customer
        header = header.map { r in
            var r = r
            if rowNumber(r) == 8 {
                r = setText(r, "B8", boq.number)
                r = setText(r, "G8", boq.issued.map(PermitDate.long) ?? "")
                r = setText(r, "L8", boq.validUntil.map(PermitDate.long) ?? "")
            }
            if rowNumber(r) == 9 { r = setText(r, "C9", boq.projectTitle) }
            if rowNumber(r) == 11 { r = setText(r, "C11", boq.customer) }
            return r
        }

        // item rows
        let lines = customer ? boq.customerLines : boq.lines
        var out: [String] = []
        var merges: [String] = []
        var n = 17
        let groups = HomeBOQ.Section.allCases.map { s in (s, lines.filter { $0.section == s }) }.filter { !$0.1.isEmpty }
        var amountRows: [Int] = []
        for (gi, (section, rowsOf)) in groups.enumerated() {
            let isLastGroup = gi == groups.count - 1
            let no = "\(gi + 1)"
            let single = rowsOf.count == 1 && rowsOf[0].description == section.title
            if single {
                out.append(lineRow(isLastGroup ? pLast : pSingle, n, no: no, rowsOf[0], title: true))
                merges.append("B\(n):E\(n)"); amountRows.append(n); n += 1
            } else {
                out.append(titleRow(pSection, n, no: no, section.title))
                merges.append("B\(n):E\(n)"); n += 1
                for (li, l) in rowsOf.enumerated() {
                    let proto = isLastGroup && li == rowsOf.count - 1 ? pLast : pItem
                    out.append(lineRow(proto, n, no: "", l, title: false))
                    merges.append("B\(n):E\(n)")
                    if !l.isNote { amountRows.append(n) }
                    n += 1
                }
            }
            if !isLastGroup { out.append(clone(pSpacer, n)); n += 1 }
        }
        let lastItem = n - 1

        // totals
        let labels = ["Subtotal", "Overhead and Profit", "Discount", "Total", "VAT 7%", "Total"]
        let values = [boq.subtotal, boq.overhead, boq.discount, boq.total, boq.vat, boq.grandTotal]
        let first = n
        for (k, p) in Proto.totals.enumerated() {
            guard let proto = protos[p] else { continue }
            var r = clone(proto, n, keepColumns: ["L"])
            r = setText(r, "L\(n)", labels[k])
            switch k {
            case 0: r = setFormula(r, "M\(n)", "SUM(M17:M\(lastItem))", values[k])
            case 1, 2: r = setNumber(r, "M\(n)", values[k])
            case 3: r = setFormula(r, "M\(n)", "M\(first)+M\(first + 1)-M\(first + 2)", values[k])
            case 4: r = setFormula(r, "M\(n)", "ROUND(M\(first + 3)*0.07,2)", values[k])
            default: r = setFormula(r, "M\(n)", "M\(first + 4)+M\(first + 3)", values[k])
            }
            out.append(r); n += 1
        }
        let lastRow = n - 1

        // merges: the header's, then one per item row
        if let r = tail.range(of: #"<mergeCells count="\d+">(.*?)</mergeCells>"#, options: .regularExpression) {
            let keep = String(tail[r]).components(separatedBy: "<mergeCell ").dropFirst().map { "<mergeCell " + $0.replacingOccurrences(of: "</mergeCells>", with: "") }
            let all = keep + merges.map { "<mergeCell ref=\"\($0)\"/>" }
            tail.replaceSubrange(r, with: "<mergeCells count=\"\(all.count)\">" + all.joined() + "</mergeCells>")
        }
        tail = tail.replacingOccurrences(of: "{{DATE}}", with: XML.escape(boq.issued.map(PermitDate.long) ?? ""))
            .replacingOccurrences(of: "{{REV}}", with: "\(boq.revision)")
        let headOut = head.replacingOccurrences(of: #"<dimension ref="[^"]*"/>"#, with: "<dimension ref=\"A1:M\(lastRow)\"/>",
                                                options: .regularExpression)
        return (headOut + header.joined() + out.joined() + tail, lastRow)
    }

    // MARK: Rows

    static func titleRow(_ proto: String, _ n: Int, no: String, _ title: String) -> String {
        var r = clone(proto, n)
        r = setNumberOrText(r, "A\(n)", no)
        return setText(r, "B\(n)", title)
    }

    static func lineRow(_ proto: String, _ n: Int, no: String, _ l: HomeBOQ.Line, title: Bool) -> String {
        var r = clone(proto, n)
        if !no.isEmpty { r = setNumberOrText(r, "A\(n)", no) }
        r = setText(r, "B\(n)", title ? l.description : "- " + l.description)
        if !l.brand.isEmpty { r = setText(r, "F\(n)", l.brand) }
        guard !l.isNote else { return r }
        r = setText(r, "G\(n)", l.unit)
        r = setNumber(r, "H\(n)", l.qty)
        if !l.included {
            if l.material > 0 { r = setNumber(r, "I\(n)", l.material) }
            if l.labor > 0 { r = setNumber(r, "K\(n)", l.labor) }
        }
        r = setFormula(r, "J\(n)", "H\(n)*I\(n)", l.materialTotal)
        r = setFormula(r, "L\(n)", "H\(n)*K\(n)", l.laborTotal)
        return setFormula(r, "M\(n)", "L\(n)+J\(n)", l.amount)
    }

    // MARK: XML

    static func rows(_ body: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"<row [^>]*?(?:/>|>.*?</row>)"#, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = body as NSString
        return re.matches(in: body, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    static func rowNumber(_ row: String) -> Int? {
        guard let r = row.range(of: #"^<row r="(\d+)""#, options: .regularExpression) else { return nil }
        return Int(row[r].filter(\.isNumber))
    }

    /// The prototype row renumbered to `n`, cells emptied (styles kept) except `keepColumns`.
    static func clone(_ proto: String, _ n: Int, keepColumns: Set<String> = []) -> String {
        var r = proto.replacingOccurrences(of: #"^<row r="\d+""#, with: "<row r=\"\(n)\"", options: .regularExpression)
        guard let re = try? NSRegularExpression(pattern: #"<c r="([A-Z]+)\d+"([^>]*?)(/>|>.*?</c>)"#, options: [.dotMatchesLineSeparators]) else { return r }
        let ns = r as NSString
        var out = "", last = 0
        for m in re.matches(in: r, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let col = ns.substring(with: m.range(at: 1))
            var attrs = ns.substring(with: m.range(at: 2))
            if keepColumns.contains(col) {
                out += "<c r=\"\(col)\(n)\"" + attrs + ns.substring(with: m.range(at: 3))
            } else {
                attrs = attrs.replacingOccurrences(of: #"\s+t="[^"]*""#, with: "", options: .regularExpression)
                out += "<c r=\"\(col)\(n)\"" + attrs + "/>"
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        r = out
        return r
    }

    /// Replaces the cell `ref` (adding it in column order when the row lacks it).
    static func put(_ row: String, _ ref: String, _ make: (String) -> String) -> String {
        let pattern = #"<c r="\#(ref)"([^>]*?)(/>|>.*?</c>)"#
        if let r = row.range(of: pattern, options: .regularExpression) {
            let cell = String(row[r])
            var attrs = cell.range(of: #"^<c r="[^"]*"([^>]*?)(/>|>)"#, options: .regularExpression).map { String(cell[$0]) } ?? ""
            attrs = attrs.replacingOccurrences(of: #"^<c r="[^"]*""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"/?>$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+t="[^"]*""#, with: "", options: .regularExpression)
            var out = row
            out.replaceSubrange(r, with: make(attrs))
            return out
        }
        // no such cell: insert before </row>, or before the first cell of a later column
        let col = ref.prefix { $0.isLetter }
        var out = row
        if let re = try? NSRegularExpression(pattern: #"<c r="([A-Z]+)\d+""#) {
            let ns = row as NSString
            for m in re.matches(in: row, range: NSRange(location: 0, length: ns.length)) {
                let other = ns.substring(with: m.range(at: 1))
                if other.count > col.count || (other.count == col.count && other > col) {
                    out = ns.replacingCharacters(in: NSRange(location: m.range.location, length: 0), with: make(""))
                    return out
                }
            }
        }
        if let r = out.range(of: "</row>", options: .backwards) { out.replaceSubrange(r, with: make("") + "</row>") }
        else if out.hasSuffix("/>") { out = String(out.dropLast(2)) + ">" + make("") + "</row>" }
        return out
    }

    static func setText(_ row: String, _ ref: String, _ text: String) -> String {
        put(row, ref) { attrs in
            "<c r=\"\(ref)\"\(attrs) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(XML.escape(text))</t></is></c>"
        }
    }

    static func setNumber(_ row: String, _ ref: String, _ v: Double) -> String {
        put(row, ref) { attrs in "<c r=\"\(ref)\"\(attrs)><v>\(number(v))</v></c>" }
    }

    /// "6.1" and "1" are numbers in the template's first column; anything else is text.
    static func setNumberOrText(_ row: String, _ ref: String, _ s: String) -> String {
        if let v = Double(s) { return setNumber(row, ref, v) }
        return setText(row, ref, s)
    }

    static func setFormula(_ row: String, _ ref: String, _ f: String, _ cached: Double) -> String {
        put(row, ref) { attrs in "<c r=\"\(ref)\"\(attrs)><f>\(f)</f><v>\(number(cached))</v></c>" }
    }

    static func number(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}
