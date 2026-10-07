import Foundation
import TCRoofCore

/// รายงานประจำวัน R2 as an Excel workbook (docs/specs/routine-reports-swift.md §4.6): one sheet with the sections of
/// the PDF, written from scratch so none of the old template's hidden sheets come along. Percent columns hold
/// fractions formatted 0%, as the company file did.
public enum DailyReportExcel {
    public struct Header: Sendable {
        public var project: String
        public var station: String
        public var employer: String
        public var contractor: String
        public var engineer: String
        public var inspector: String
        public var engineerSignedAt: Date?
        public var inspectorAckAt: Date?
        public init(project: String, station: String, employer: String, contractor: String, engineer: String, inspector: String,
                    engineerSignedAt: Date?, inspectorAckAt: Date?) {
            self.project = project; self.station = station; self.employer = employer; self.contractor = contractor
            self.engineer = engineer; self.inspector = inspector
            self.engineerSignedAt = engineerSignedAt; self.inspectorAckAt = inspectorAckAt
        }
    }

    /// `all` holds every report of the station, for the "วันนี้" column.
    public static func export(_ r: RoutineReport.Daily, all: [RoutineReport.Daily], header h: Header) throws -> Data {
        var s = Sheet()
        s.row([.text("รายงานประจำวัน (Daily Report)", .title)], merge: 16)
        s.row([.text("โครงการ", .bold), .text(h.project)], merge: 16, from: 2)
        s.row([.text("สถานี", .bold), .text(h.station)], merge: 16, from: 2)
        s.row([.text("ผู้ว่าจ้าง", .bold), .text(h.employer)], merge: 16, from: 2)
        s.row([.text("ผู้รับจ้าง", .bold), .text(h.contractor)], merge: 16, from: 2)
        s.row([.text("วันที่", .bold), .text(RoutineReport.thaiDate(r.date)), .empty, .text("เวลาทำงาน", .bold),
               .text("\(r.workStart) – \(r.workEnd) น.")])
        s.blank()

        s.row([.text("1. สภาพอากาศ", .section)])
        s.row([.text("เวลา", .head)] + RoutineReport.weatherHours.map { .text(String(format: "%02d", $0), .head) })
        s.row([.text("สภาพ", .cell)] + r.weather.map { .text($0?.rawValue ?? "", .center) })
        s.row([.text("F = ท้องฟ้าโปร่ง   C = เมฆครึ้ม   R = ฝนตก")])
        s.blank()

        s.row([.text("2. กำลังคน", .section)])
        s.row([.text("ตำแหน่ง", .head), .text("จำนวน (คน)", .head)])
        for c in r.crew where c.count > 0 { s.row([.text(c.name, .cell), .number(Double(c.count), .cell)]) }
        s.row([.text("รวม", .headLeft), .number(Double(r.crewTotal), .head)])
        if !r.crewConfirmed, r.crewTotal > 0 { s.row([.text("* กำลังคนยังไม่ได้ยืนยัน (ใช้ค่าจากรายงานก่อนหน้า)")]) }
        s.blank()

        s.row([.text("3. เครื่องมือ / เครื่องจักร", .section)])
        s.row([.text("รายการ", .head), .text("จำนวน", .head)])
        let tools = r.tools.filter { $0.count > 0 }
        if tools.isEmpty { s.row([.text("ไม่มี", .cell), .empty]) }
        for c in tools { s.row([.text(c.name, .cell), .number(Double(c.count), .cell)]) }
        s.blank()

        s.row([.text("4. วัสดุเข้าหน้างาน", .section)])
        s.row(["รายการ", "ตำแหน่ง", "จำนวน", "หน่วย", "หมายเหตุ"].map { .text($0, .head) })
        if r.materials.isEmpty { s.row([.text("ไม่มี", .cell)]) }
        for m in r.materials {
            s.row([.text(m.name, .cell), .text(m.location, .cell), .number(m.qty, .cell), .text(m.unit, .cell), .text(m.remark, .cell)])
        }
        s.blank()

        s.row([.text("5. ความก้าวหน้างาน", .section)])
        s.row(["งาน MP", "รายละเอียด", "ตำแหน่ง", "วันนี้", "สะสม"].map { .text($0, .head) })
        if r.progress.isEmpty { s.row([.text(r.stopReason.isEmpty ? "ไม่มี" : "หยุดงาน: " + r.stopReason, .cell)]) }
        for l in r.progress {
            s.row([.text(l.task?.code ?? "อื่น", .center), .text(l.description.isEmpty ? (l.task?.title ?? "") : l.description, .cell),
                   .text(l.location, .cell), .number(RoutineReport.todayDelta(l, on: r.date, in: all) / 100, .percent),
                   .number(l.percent / 100, .percent)])
        }
        s.blank()

        s.row([.text("6. ปัญหา / อุปสรรค", .section)])
        s.row(["ปัญหา", "แนวทางแก้ไข", "สถานะ", "ตั้งแต่"].map { .text($0, .head) })
        let problems = r.problems.filter { !$0.description.isEmpty }
        if problems.isEmpty { s.row([.text("ไม่มี", .cell)]) }
        for p in problems {
            s.row([.text(p.description, .cell), .text(p.solution, .cell), .text(p.closed ? "ปิดแล้ว" : "ยังเปิด", .center),
                   .text(RoutineReport.thaiDate(p.since), .center)])
        }
        s.blank()

        s.row([.text("Site Engineer", .bold), .text(h.engineer), .empty, .text("Inspector", .bold), .text(h.inspector)])
        s.row([.text("ลงนาม", .bold), .text(h.engineerSignedAt.map(RoutineReport.thaiDate) ?? ""), .empty,
               .text("รับทราบ", .bold), .text(h.inspectorAckAt.map(RoutineReport.thaiDate) ?? "")])
        return try s.workbook(name: "Daily Report", widths: [22, 34, 18, 12, 18] + Array(repeating: 6, count: 11))
    }

    // MARK: - A minimal one-sheet workbook

    enum Style: Int { case normal = 0, bold, title, section, head, headLeft, cell, center, percent }

    enum Cell {
        case text(String, Style = .normal), number(Double, Style = .normal), empty
    }

    struct Sheet {
        var rows: [[Cell]] = []
        var merges: [String] = []

        /// Appends a row; `merge` joins the cells from column `from` to column `merge` (1-based).
        mutating func row(_ cells: [Cell], merge: Int? = nil, from: Int = 1) {
            rows.append(cells)
            if let merge { merges.append("\(CellRef.name(from))\(rows.count):\(CellRef.name(merge))\(rows.count)") }
        }
        mutating func blank() { rows.append([]) }

        func workbook(name: String, widths: [Double]) throws -> Data {
            var zip = ZipArchive()
            zip.set("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
            """)
            zip.set("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """)
            zip.set("xl/_rels/workbook.xml.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
            """)
            zip.set("xl/workbook.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="\(XML.escape(name))" sheetId="1" r:id="rId1"/></sheets></workbook>
            """)
            zip.set("xl/styles.xml", Self.styles)
            zip.set("xl/worksheets/sheet1.xml", sheetXML(widths: widths))
            return try zip.write()
        }

        func sheetXML(widths: [Double]) -> String {
            var x = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols>"#
            for (i, w) in widths.enumerated() { x += #"<col min="\#(i + 1)" max="\#(i + 1)" width="\#(w)" customWidth="1"/>"# }
            x += "</cols><sheetData>"
            for (ri, cells) in rows.enumerated() where !cells.isEmpty {
                let r = ri + 1
                x += #"<row r="\#(r)">"#
                for (ci, c) in cells.enumerated() {
                    let ref = "\(CellRef.name(ci + 1))\(r)"
                    switch c {
                    case let .text(t, st):
                        x += #"<c r="\#(ref)" s="\#(st.rawValue)" t="inlineStr"><is><t xml:space="preserve">\#(XML.escape(t))</t></is></c>"#
                    case let .number(v, st):
                        x += #"<c r="\#(ref)" s="\#(st.rawValue)"><v>\#(v)</v></c>"#
                    case .empty: break
                    }
                }
                x += "</row>"
            }
            x += "</sheetData>"
            if !merges.isEmpty {
                x += #"<mergeCells count="\#(merges.count)">"# + merges.map { #"<mergeCell ref="\#($0)"/>"# }.joined() + "</mergeCells>"
            }
            x += #"<pageSetup paperSize="9" orientation="portrait" fitToWidth="1" fitToHeight="0"/></worksheet>"#
            return x
        }

        /// Fonts: normal, bold, title. Fills: none, gray125, header blue. Borders: none, thin.
        /// cellXfs follow `Style`'s raw values.
        static let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="4"><font><sz val="11"/><name val="TH Sarabun New"/></font><font><b/><sz val="11"/><name val="TH Sarabun New"/></font><font><b/><sz val="16"/><color rgb="FF16325C"/><name val="TH Sarabun New"/></font><font><b/><sz val="12"/><color rgb="FF16325C"/><name val="TH Sarabun New"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE3EEF8"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFC9D3DF"/></left><right style="thin"><color rgb="FFC9D3DF"/></right><top style="thin"><color rgb="FFC9D3DF"/></top><bottom style="thin"><color rgb="FFC9D3DF"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="9"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"><alignment vertical="top"/></xf><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="top"/></xf><xf numFmtId="9" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/></cellXfs></styleSheet>
        """
    }
}
