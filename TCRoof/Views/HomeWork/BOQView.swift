import SwiftUI
import UIKit
import TCRoofUI
import TCRoofCore
import ExcelExport

/// The BOQ printed in the company's layout: letterhead, project lines, the nine-section table with material and
/// labour, and the totals box. A4 portrait; long tables continue on the next page under the column header.
enum BOQRenderer {
    static let page = CGRect(x: 0, y: 0, width: 595.32, height: 841.92)
    static let left: CGFloat = 30, right: CGFloat = 565, bottom: CGFloat = 800
    static let rowH: CGFloat = 14.5
    /// Column edges: No, description, unit, qty, material unit/total, labour unit/total, amount.
    static let cols: [CGFloat] = [30, 60, 240, 276, 306, 360, 414, 464, 512, 565]

    static func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
        UIFont(name: bold ? "Sarabun-Bold" : "Sarabun-Regular", size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
    static var ink: UIColor { PermitRenderer.paper(Theme.paperInk) }
    static var line: UIColor { PermitRenderer.paper(Theme.borderControl) }
    static var band: UIColor { PermitRenderer.paper(Theme.primarySoft) }

    static func money(_ v: Double) -> String {
        guard v != 0 else { return "-" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    static func qty(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }

    static func text(_ s: String, _ r: CGRect, _ f: UIFont, align: NSTextAlignment = .left, color: UIColor? = nil) {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color ?? ink, .paragraphStyle: p])
            .draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    static func stroke(_ ctx: CGContext, _ r: CGRect, width: CGFloat = 0.6) {
        ctx.setStrokeColor(line.cgColor)
        ctx.setLineWidth(width)
        ctx.stroke(r)
    }

    /// Both sheets: `customer` prints each line as one lot at its total.
    static func pdf(_ boq: HomeBOQ, company: HomeCompany, customer: Bool) -> Data {
        UIGraphicsPDFRenderer(bounds: page).pdfData { r in
            r.beginPage()
            let ctx = r.cgContext
            var y = letterhead(boq, company: company, ctx)
            y = tableHeader(at: y, ctx)
            let lines = customer ? boq.customerLines : boq.lines
            var no = 0
            for section in HomeBOQ.Section.allCases {
                let rows = lines.filter { $0.section == section }
                guard !rows.isEmpty else { continue }
                no += 1
                let single = rows.count == 1 && rows[0].description == section.title
                if y + rowH * CGFloat(single ? 1 : rows.count + 1) > bottom && y > 300 {
                    r.beginPage(); y = tableHeader(at: 40, ctx)
                }
                if single {
                    y = row(at: y, no: "\(no)", rows[0], title: true, ctx)
                } else {
                    y = titleRow(at: y, no: "\(no)", section.title, ctx)
                    for l in rows {
                        if y + rowH > bottom { r.beginPage(); y = tableHeader(at: 40, ctx) }
                        y = row(at: y, no: "", l, title: false, ctx)
                    }
                }
                y += 2
            }
            // table frame down to here
            ctx.setStrokeColor(line.cgColor); ctx.setLineWidth(0.6)
            ctx.move(to: CGPoint(x: left, y: y)); ctx.addLine(to: CGPoint(x: right, y: y)); ctx.strokePath()
            if y + 6 * 15 > page.height - 12 { r.beginPage(); y = 40 }
            totals(boq, at: y, ctx)
        }
    }

    static func letterhead(_ boq: HomeBOQ, company: HomeCompany, _ ctx: CGContext) -> CGFloat {
        text("Bill of quantities", CGRect(x: 0, y: 26, width: page.width, height: 14), font(9), align: .center)
        let date = boq.issued.map(PermitDate.short) ?? ""
        text(date + "\nRev.\(boq.revision)", CGRect(x: 420, y: 22, width: 145, height: 28), font(8.5), align: .right)
        var y: CGFloat = 60
        if !company.nameTH.isEmpty { text(company.nameTH, CGRect(x: left, y: y, width: 535, height: 22), font(15, bold: true)); y += 21 }
        if !company.nameEN.isEmpty { text(company.nameEN, CGRect(x: left, y: y, width: 535, height: 20), font(12.5, bold: true)); y += 19 }
        if !company.isEmpty {
            ctx.setStrokeColor(ink.cgColor); ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: left, y: y + 2)); ctx.addLine(to: CGPoint(x: right, y: y + 2)); ctx.strokePath()
            y += 6
        }
        for l in [company.address, [company.phone.isEmpty ? "" : "โทรศัพท์ " + company.phone,
                                    company.taxID.isEmpty ? "" : "เลขประจำตัวผู้เสียภาษี " + company.taxID].filter { !$0.isEmpty }
                                    .joined(separator: " · ")] where !l.isEmpty {
            text(l, CGRect(x: left, y: y, width: 535, height: 13), font(8.5)); y += 12
        }
        y += 6
        text("เลขที่ / No : " + boq.number, CGRect(x: left, y: y, width: 170, height: 14), font(9))
        text("วันที่เสนอ / Issue date: " + (boq.issued.map(PermitDate.short) ?? ""), CGRect(x: 205, y: y, width: 190, height: 14), font(9))
        text("วันที่สิ้นสุด / Valid until: " + (boq.validUntil.map(PermitDate.short) ?? ""), CGRect(x: 395, y: y, width: 170, height: 14), font(9))
        y += 18
        text("ชื่อโครงการ / Project : " + boq.projectTitle, CGRect(x: left, y: y, width: 535, height: 14), font(9)); y += 18
        text("ชื่อลูกค้า / Customer Name : " + boq.customer, CGRect(x: left, y: y, width: 535, height: 14), font(9)); y += 18
        text("Bill of quantities", CGRect(x: left, y: y, width: 535, height: 14), font(9.5, bold: true), align: .center)
        return y + 16
    }

    static func tableHeader(at y: CGFloat, _ ctx: CGContext) -> CGFloat {
        let h: CGFloat = 40
        ctx.setFillColor(band.cgColor)
        ctx.fill(CGRect(x: left, y: y, width: right - left, height: h))
        let f = font(8), b = font(8.5, bold: true)
        func cell(_ i: Int, _ j: Int, _ top: String, _ bottomText: String) {
            let r = CGRect(x: cols[i], y: y, width: cols[j] - cols[i], height: h)
            stroke(ctx, r)
            text(top, CGRect(x: r.minX, y: y + 4, width: r.width, height: 12), b, align: .center)
            text(bottomText, CGRect(x: r.minX, y: y + 26, width: r.width, height: 12), f, align: .center)
        }
        cell(0, 1, "ลำดับ", "No.")
        cell(1, 2, "รายละเอียด", "Description")
        cell(2, 3, "หน่วย", "unit")
        cell(3, 4, "จำนวน", "Qty.")
        // material and labour: a group label over unit price / total
        for (a, label) in [(4, "ค่าอุปกรณ์ Procurement"), (6, "ค่าแรง Labor")] {
            stroke(ctx, CGRect(x: cols[a], y: y, width: cols[a + 2] - cols[a], height: 14))
            text(label, CGRect(x: cols[a], y: y + 2, width: cols[a + 2] - cols[a], height: 12), b, align: .center)
            for k in 0..<2 {
                let r = CGRect(x: cols[a + k], y: y + 14, width: cols[a + k + 1] - cols[a + k], height: h - 14)
                stroke(ctx, r)
                text(k == 0 ? "ราคาต่อหน่วย" : "รวม", CGRect(x: r.minX, y: r.minY + 1, width: r.width, height: 11), f, align: .center)
                text(k == 0 ? "Unit price" : "Total", CGRect(x: r.minX, y: r.minY + 13, width: r.width, height: 11), f, align: .center)
            }
        }
        cell(8, 9, "ราคารวม", "Amount")
        return y + h
    }

    static func verticals(_ y0: CGFloat, _ y1: CGFloat, _ ctx: CGContext) {
        ctx.setStrokeColor(line.cgColor); ctx.setLineWidth(0.6)
        for x in cols { ctx.move(to: CGPoint(x: x, y: y0)); ctx.addLine(to: CGPoint(x: x, y: y1)) }
        ctx.strokePath()
    }

    static func titleRow(at y: CGFloat, no: String, _ title: String, _ ctx: CGContext) -> CGFloat {
        verticals(y, y + rowH, ctx)
        text(no, CGRect(x: cols[0], y: y + 1.5, width: cols[1] - cols[0], height: 13), font(8.5), align: .center)
        text(title, CGRect(x: cols[1] + 3, y: y + 1.5, width: cols[2] - cols[1] - 6, height: 13), font(8.5, bold: true))
        return y + rowH
    }

    static func row(at y: CGFloat, no: String, _ l: HomeBOQ.Line, title: Bool, _ ctx: CGContext) -> CGFloat {
        verticals(y, y + rowH, ctx)
        let f = font(8.5)
        text(no, CGRect(x: cols[0], y: y + 1.5, width: cols[1] - cols[0], height: 13), f, align: .center)
        text(title ? l.description : "- " + l.description, CGRect(x: cols[1] + 3, y: y + 1.5, width: cols[2] - cols[1] - 6, height: 13),
             title ? font(8.5, bold: true) : f)
        guard !l.isNote else { return y + rowH }
        text(l.unit, CGRect(x: cols[2], y: y + 1.5, width: cols[3] - cols[2], height: 13), f, align: .center)
        text(qty(l.qty), CGRect(x: cols[3], y: y + 1.5, width: cols[4] - cols[3], height: 13), f, align: .center)
        let values = [l.material, l.materialTotal, l.labor, l.laborTotal]
        for (k, v) in values.enumerated() {
            text(money(v), CGRect(x: cols[4 + k] + 2, y: y + 1.5, width: cols[5 + k] - cols[4 + k] - 5, height: 13), f, align: .right)
        }
        text(money(l.amount), CGRect(x: cols[8] + 2, y: y + 1.5, width: cols[9] - cols[8] - 5, height: 13), f, align: .right)
        return y + rowH
    }

    static func totals(_ boq: HomeBOQ, at y0: CGFloat, _ ctx: CGContext) {
        let rows: [(String, Double)] = [("Subtotal", boq.subtotal), ("Overhead and Profit", boq.overhead), ("Discount", boq.discount),
                                        ("Total", boq.total), ("VAT 7%", boq.vat), ("Total", boq.grandTotal)]
        var y = y0
        for (i, (label, v)) in rows.enumerated() {
            let bold = i == rows.count - 1
            stroke(ctx, CGRect(x: cols[6], y: y, width: cols[8] - cols[6], height: 15))
            stroke(ctx, CGRect(x: cols[8], y: y, width: cols[9] - cols[8], height: 15))
            text(label, CGRect(x: cols[6] + 4, y: y + 1.5, width: cols[8] - cols[6] - 8, height: 13), font(8.5, bold: bold))
            text(money(v), CGRect(x: cols[8] + 2, y: y + 1.5, width: cols[9] - cols[8] - 5, height: 13), font(8.5, bold: bold), align: .right)
            y += 15
        }
    }
}

/// Field for a baht or count value that keeps what the engineer types (a trailing dot, commas) until it parses.
struct BOQNumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String?
    @State private var text = ""

    var body: some View {
        PermitField(title, text: $text, keyboard: .decimalPad, unit: unit)
            .onAppear { text = value == 0 ? "" : BOQRenderer.qty(value) }
            .onChange(of: text) { _, t in value = HomeJob.number(t) ?? 0 }
    }
}

/// The engineer's BOQ for one home job: drafted from the design, priced from the company's price book, checked
/// against the job, printed as the cost sheet and the customer sheet.
struct BOQView: View {
    let job: Job
    let home: HomeJob

    @State private var boq = HomeBOQ()
    @State private var library = HomeLibrary()
    @State private var loaded = false
    @State private var share: URL?
    @State private var confirmDraft = false
    static let file = "boq"

    private var store: PermitStore { PermitStore(job: job) }

    var body: some View {
        VStack(spacing: 0) {
            TCNavBar(title: "BOQ", trail: ["งานบ้าน", job.code], current: "BOQ") { exportMenu }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    headerCard
                    issuesCard
                    ForEach(HomeBOQ.Section.allCases, id: \.self) { sectionCard($0) }
                    totalsCard
                }
                .padding(isPhone ? Space.l : Space.xl)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { load() }
        .onChange(of: boq) { _, new in if loaded { store.save(new, Self.file) } }
        .onDisappear { rememberPrices() }
        .confirmationDialog("ร่างใหม่จากแบบ? รายการที่แก้ไว้จะถูกแทนที่ ราคาที่จำไว้ยังใช้ได้", isPresented: $confirmDraft, titleVisibility: .visible) {
            Button("ร่างใหม่", role: .destructive) { redraft() }
        }
        .sheet(item: Binding(get: { share.map(ShareURL.init) }, set: { share = $0?.url })) { ActivitySheet(items: [$0.url]) }
        .alert("ส่งออกไม่ได้", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("ตกลง", role: .cancel) {}
        } message: { Text(exportError ?? "") }
    }

    private struct ShareURL: Identifiable { let url: URL; var id: URL { url } }

    /// One menu on every width: Excel (both sheets, the company file) and the two PDFs.
    private var exportMenu: some View {
        Menu {
            Button { exportExcel() } label: { Label("Excel · Cost + Sent", systemImage: "tablecells") }
            Button { export(customer: true) } label: { Label("PDF ฉบับส่งลูกค้า", systemImage: "paperplane") }
            Button { export(customer: false) } label: { Label("PDF ฉบับต้นทุน", systemImage: "doc.text") }
        } label: {
            Label("ส่งออก", systemImage: "square.and.arrow.up").font(.sarabun(14, .semibold, relativeTo: .body))
                .padding(.horizontal, Space.m).frame(minHeight: touchMin)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.45)))
        }
        .accessibilityLabel("ส่งออก BOQ")
    }

    @State private var exportError: String?

    private func fileStem() -> String {
        "BOQ \(job.code) \(HomeBOQ.kw(boq.panelKWp ?? 0)) kWp Rev.\(boq.revision)".replacingOccurrences(of: "/", with: "-")
    }

    private func exportExcel() {
        rememberPrices()
        do {
            let data = try BOQExcel.export(boq)
            HomeArchive.keep(data, name: fileStem() + ".xlsx", job: job)
            share = store.exportURL(data, fileName: fileStem() + ".xlsx")
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func load() {
        guard !loaded else { return }
        library = PermitStore.library.load(HomeLibrary.self, PermitStore.libraryFile) ?? HomeLibrary()
        if let saved = store.load(HomeBOQ.self, Self.file) {
            boq = saved
        } else {
            boq = HomeBOQ.draft(job: home, prices: library.prices)
            boq.customer = job.customerName
            boq.issued = .now
            boq.validUntil = Calendar(identifier: .gregorian).date(byAdding: .day, value: 30, to: .now)
        }
        loaded = true
    }

    private func redraft() {
        rememberPrices()
        var fresh = HomeBOQ.draft(job: home, prices: library.prices, dcRunM: boq.dcRunM, acRunM: boq.acRunM)
        fresh.number = boq.number; fresh.revision = boq.revision + 1
        fresh.issued = boq.issued; fresh.validUntil = boq.validUntil; fresh.customer = boq.customer
        fresh.overhead = boq.overhead; fresh.discount = boq.discount
        boq = fresh
    }

    /// Unit prices typed here are offered on the next job's draft.
    private func rememberPrices() {
        guard loaded else { return }
        let book = boq.priceBook
        guard !book.isEmpty else { return }
        var lib = PermitStore.library.load(HomeLibrary.self, PermitStore.libraryFile) ?? HomeLibrary()
        lib.prices.merge(book) { _, new in new }
        PermitStore.library.save(lib, PermitStore.libraryFile)
        library = lib
    }

    private func export(customer: Bool) {
        rememberPrices()
        let data = BOQRenderer.pdf(boq, company: library.company, customer: customer)
        let name = "BOQ \(customer ? "" : "ต้นทุน ")\(job.code) \(HomeBOQ.kw(boq.panelKWp ?? 0)) kWp Rev.\(boq.revision).pdf"
        HomeArchive.keep(data, name: name, job: job)
        share = store.exportURL(data, fileName: name.replacingOccurrences(of: "/", with: "-"))
    }

    // MARK: Cards

    private var headerCard: some View {
        PermitSection(title: "หัว BOQ", subtitle: boq.projectTitle) {
            PermitRow {
                PermitField("เลขที่", text: $boq.number)
                PermitField("ลูกค้า", text: $boq.customer)
            }
            HomeDateRow(title: "วันที่เสนอ", date: $boq.issued, caption: "Rev.\(boq.revision)")
            HomeDateRow(title: "วันที่สิ้นสุด", date: $boq.validUntil, caption: "ราคานี้ใช้ได้ถึงวันนี้")
            PermitRow {
                BOQNumberField(title: "ระยะสาย DC (แผง → อินเวอร์เตอร์)", value: $boq.dcRunM, unit: "ม.")
                BOQNumberField(title: "ระยะสาย AC (อินเวอร์เตอร์ → ตู้)", value: $boq.acRunM, unit: "ม.")
            }
            HStack(spacing: Space.s) {
                TCButton("ร่างใหม่จากแบบ", systemImage: "arrow.triangle.2.circlepath", kind: .secondary, size: .card) { confirmDraft = true }
                if library.company.isEmpty {
                    Text("ยังไม่มีหัวกระดาษบริษัท ใส่ได้ที่คลังเอกสาร").font(.sarabun(TypeScale.caption, relativeTo: .caption))
                        .foregroundStyle(Theme.pending)
                }
            }
        }
    }

    @ViewBuilder private var issuesCard: some View {
        let issues = boq.issues(for: home)
        if !issues.isEmpty {
            PermitIssuesCard(issues: issues)
        }
    }

    private func sectionCard(_ s: HomeBOQ.Section) -> some View {
        let rows = boq.lines.filter { $0.section == s }
        let sum = rows.reduce(0) { $0 + $1.amount }
        return PermitSection(title: "\(s.rawValue). \(s.title)", subtitle: sum > 0 ? "รวม " + BOQRenderer.money(sum) + " บาท" : nil) {
            ForEach(rows) { lineEditor($0.id) }
            HStack(spacing: Space.s) {
                TCButton("เพิ่มรายการ", systemImage: "plus", kind: .secondary, size: .card) {
                    insert(HomeBOQ.Line(section: s, description: ""), after: rows.last?.id)
                }
                TCButton("เพิ่มบรรทัดรายละเอียด", systemImage: "text.append", kind: .secondary, size: .card) {
                    insert(HomeBOQ.Line(section: s, description: "", qty: 0), after: rows.last?.id)
                }
            }
        }
    }

    private func insert(_ line: HomeBOQ.Line, after id: String?) {
        if let id, let i = boq.lines.firstIndex(where: { $0.id == id }) { boq.lines.insert(line, at: i + 1) } else { boq.lines.append(line) }
    }

    private func binding(_ id: String) -> Binding<HomeBOQ.Line> {
        Binding(get: { boq.lines.first { $0.id == id } ?? HomeBOQ.Line(id: id, section: .module, description: "") },
                set: { new in if let i = boq.lines.firstIndex(where: { $0.id == id }) { boq.lines[i] = new } })
    }

    private func lineEditor(_ id: String) -> some View {
        let line = binding(id)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.m) {
                PermitRow {
                    PermitField(line.wrappedValue.isNote ? "รายละเอียด (ไม่มีราคา)" : "รายการ", text: line.description)
                    if !line.wrappedValue.isNote { PermitField("ยี่ห้อ", text: line.brand).frame(maxWidth: isPhone ? .infinity : 200) }
                }
                Button(role: .destructive) { boq.lines.removeAll { $0.id == id } } label: {
                    Image(systemName: "trash").frame(width: touchMin, height: touchMin)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.dangerText).padding(.top, 22)
                .accessibilityLabel("ลบรายการ")
            }
            if !line.wrappedValue.isNote {
                TCSwitchRow("รวมในราคารายการอื่น (แสดงรายการ ไม่มีราคา)", isOn: line.included)
                if line.wrappedValue.included { includedRow(line) } else { priceRow(line) }
            }
        }
        .padding(Space.m)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    /// Listed with a count only; its price sits in another line of the section.
    private func includedRow(_ line: Binding<HomeBOQ.Line>) -> some View {
        PermitRow {
            PermitField("หน่วย", text: line.unit).frame(maxWidth: isPhone ? .infinity : 110)
            BOQNumberField(title: "จำนวน", value: line.qty)
        }
    }

    private func priceRow(_ line: Binding<HomeBOQ.Line>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PermitRow {
                PermitField("หน่วย", text: line.unit).frame(maxWidth: isPhone ? .infinity : 110)
                BOQNumberField(title: "จำนวน", value: line.qty)
                BOQNumberField(title: "ค่าอุปกรณ์/หน่วย", value: line.material, unit: "บาท")
                BOQNumberField(title: "ค่าแรง/หน่วย", value: line.labor, unit: "บาท")
            }
            Text("รวม " + BOQRenderer.money(line.wrappedValue.amount) + " บาท")
                .font(.sarabun(TypeScale.caption, .semibold, relativeTo: .caption)).foregroundStyle(Theme.navy)
        }
    }

    private var totalsCard: some View {
        PermitSection(title: "สรุปราคา", subtitle: boq.perWp.map { String(format: "%.2f บาท/Wp ก่อน VAT", $0) }) {
            totalLine("Subtotal", boq.subtotal)
            PermitRow {
                BOQNumberField(title: "Overhead and Profit", value: $boq.overhead, unit: "บาท")
                BOQNumberField(title: "Discount", value: $boq.discount, unit: "บาท")
            }
            totalLine("Total", boq.total)
            totalLine("VAT 7%", boq.vat)
            totalLine("รวมทั้งสิ้น", boq.grandTotal, bold: true)
        }
    }

    private func totalLine(_ label: String, _ v: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.sarabun(15, bold ? .bold : .regular, relativeTo: .body)).foregroundStyle(Theme.navy)
            Spacer()
            Text(BOQRenderer.money(v) + " บาท").font(.sarabun(15, bold ? .bold : .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                .monospacedDigit()
        }
    }
}
