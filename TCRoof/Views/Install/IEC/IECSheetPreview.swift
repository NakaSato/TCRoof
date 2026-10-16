import SwiftUI
import TCRoofUI
import TCRoofCore
import ExcelExport

/// `ชีต INV 01-ก่อน · ตามฟอร์ม 1FORMI1` (docs/ui/iec62446-sheet-before): the exported Excel sheet drawn as the form,
/// read only. With `แสดงที่มา` each cell the app fills is tinted by the wizard step that fills it (a value still
/// missing gets a dashed red border), and a tap on it opens that step. iPad only. The sheet is read from an export
/// of the test, so it shows what the file holds. The after sheets `INV nn-หลัง` (board 5b) add steps 4 and 5.
struct IECSheetPreview: View {
    @Bindable var job: Job
    @State var inverter: Int
    /// `INV nn-ก่อน` or `INV nn-หลัง`.
    @State var phase: IECReport.Phase = .before
    /// A tinted cell or a legend swatch: the step, at an inverter and (for a string column) a slot.
    let open: (IECReport.Stage, Int, Int?) -> Void

    @State private var sources = true
    /// By sheet name.
    @State private var layouts: [String: IECSheetLayout] = [:]
    @State private var failed: String?
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var debugApplied = false
    @State private var printed: IECTestScreen.ExportedFile?
    /// A tap on a closed test: the step it asked for, opened once `แก้ไข` has reopened the test.
    @State private var pendingOpen: PendingOpen?
    struct PendingOpen { let stage: IECReport.Stage; let inverter: Int; let slot: Int? }
    @Environment(\.modelContext) private var context
    @State private var printFailed: String?

    private var report: IECReport { job.iecReport ?? job.newIECReport }
    private func sheetName(_ i: Int, _ p: IECReport.Phase) -> String { String(format: "INV %02d-", i + 1) + (p == .before ? "ก่อน" : "หลัง") }
    private var sheet: String { sheetName(inverter, phase) }

    var body: some View {
        let r = report
        VStack(spacing: 0) {
            IECHeader(title: "ชีต \(sheet) · ตามฟอร์ม 1FORMI1", subtitle: r.stationLine.isEmpty ? job.stationName : r.stationLine) {
                sheetPicker(r)
                IECHeaderButton(title: "PDF ชีตนี้", symbol: "doc.richtext") { printSheet(r) }
                    .disabled(layouts[sheet] == nil)
                    .accessibilityIdentifier("iec.sheet.pdf")
                Toggle("แสดงที่มา", isOn: $sources).toggleStyle(.button).font(.sarabunFixed(15, .bold))
                    .tint(Theme.onPrimary).foregroundStyle(Theme.onPrimary)
                    .accessibilityHint("สีบอกขั้นตอนที่กรอกแต่ละช่อง")
                    .accessibilityIdentifier("iec.sheet.sources")
            }
            GeometryReader { g in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let l = layouts[sheet] {
                            let scale = (g.size.width - 48) / l.width * zoom
                            IECSheetCanvas(layout: l, report: r, inverter: inverter, phase: phase, sources: sources, scale: scale,
                                           doubleTap: { withAnimation { zoom = zoom > 1.01 ? 1 : 2; lastZoom = zoom } }) { stage, slot in
                                request(stage, inverter, slot)
                            }
                            .frame(width: l.width * scale, height: l.height * scale)
                            .simultaneousGesture(MagnifyGesture().onChanged { zoom = min(3, max(1, lastZoom * $0.magnification)) }.onEnded { _ in lastZoom = zoom })
                            if sources { legend.frame(width: max(g.size.width - 48, 0)) }
                        } else if let failed {
                            Text(failed).font(.sarabunFixed(16)).foregroundStyle(Theme.dangerText).padding(40)
                        } else {
                            ProgressView("กำลังวาดชีต…").padding(60).frame(width: g.size.width - 48)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $printed) { ActivitySheet(items: [$0.url]) }
        .confirmationDialog("เปิดผลทดสอบให้แก้ไข", isPresented: Binding(get: { pendingOpen != nil }, set: { if !$0 { pendingOpen = nil } }),
                            titleVisibility: .visible, presenting: pendingOpen) { p in
            Button("แก้ไข") {
                job.updateIEC(context, evenWhenLocked: true) { $0.reopen() }
                open(p.stage, p.inverter, p.slot)
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: { _ in Text(job.iecReport?.result != nil ? "การทดสอบนี้ปิดแล้ว ผลที่สรุปไว้จะถูกยกเลิก ต้องส่งผลให้ทีมและให้ทีมภายในปิดอีกครั้งหลังแก้"
                                                          : "ผลนี้ส่งให้ทีมแล้ว แก้แล้วต้องกด ส่งผลให้ทีม อีกครั้ง") }
        .alert("ทำ PDF ไม่ได้", isPresented: Binding(get: { printFailed != nil }, set: { if !$0 { printFailed = nil } })) {
            Button("ตกลง", role: .cancel) {}
        } message: { Text(printFailed ?? "") }
        .task(id: r.inverters.count) { await load(r) }
        #if DEBUG
        .task {
            guard !debugApplied else { return }
            debugApplied = true
            if UserDefaults.standard.string(forKey: "iecSheetSource") == "off" { sources = false }
        }
        #endif
    }

    /// Every inverter's before and after sheets from one export of the test, off the main thread.
    private func load(_ r: IECReport) async {
        let names = IECReport.Phase.allCases.flatMap { p in r.inverters.indices.map { sheetName($0, p) } }
        do {
            let result = try await Task.detached(priority: .userInitiated) { () -> [String: IECSheetLayout] in
                let data = try IECExcel.export(r)
                var out: [String: IECSheetLayout] = [:]
                for n in names { out[n] = try IECSheetLayout.make(workbook: data, sheet: n) }
                return out
            }.value
            layouts = result
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "iecSheetPDF"),
               let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                _ = writePDF(r, to: docs.appendingPathComponent("iec-sheet.pdf"))
            }
            #endif
        } catch {
            failed = "วาดชีตไม่ได้: \(error.localizedDescription)"
        }
    }

    /// A tinted cell or a swatch: its step, or on a closed test the `แก้ไข` question first.
    private func request(_ stage: IECReport.Stage, _ inverter: Int, _ slot: Int?) {
        if job.iecReport?.isLocked == true { pendingOpen = PendingOpen(stage: stage, inverter: inverter, slot: slot) } else { open(stage, inverter, slot) }
    }

    /// `PDF ชีตนี้`: the sheet as exported (no source tints), vector, fitted on one A4 landscape page, for sending
    /// before the Excel is final. Only shared, not kept with the job's documents.
    private func printSheet(_ r: IECReport) {
        let station = r.sampleName.map { "ตัวอย่าง " + $0 } ?? job.stationName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IEC 62446 \(sheet) \(station).pdf")
        if writePDF(r, to: url) { printed = IECTestScreen.ExportedFile(url: url) } else { printFailed = "เขียนไฟล์ไม่ได้" }
    }

    private func writePDF(_ r: IECReport, to url: URL) -> Bool {
        guard let l = layouts[sheet] else { return false }
        let page = CGRect(x: 0, y: 0, width: 842, height: 595), margin: CGFloat = 24
        let scale = min((page.width - 2 * margin) / l.width, (page.height - 2 * margin) / l.height)
        let renderer = ImageRenderer(content: IECSheetCanvas(layout: l, report: r, inverter: inverter, phase: phase, sources: false, scale: scale,
                                                             doubleTap: {}) { _, _ in }
            .frame(width: l.width * scale, height: l.height * scale))
        var box = page
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return false }
        renderer.render { size, draw in
            pdf.beginPDFPage(nil)
            pdf.translateBy(x: (page.width - size.width) / 2, y: (page.height - size.height) / 2)
            draw(pdf)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return true
    }

    private func sheetPicker(_ r: IECReport) -> some View {
        Menu {
            ForEach(IECReport.Phase.allCases, id: \.self) { p in
                Section {
                    ForEach(r.inverters.indices, id: \.self) { i in
                        Button(sheetName(i, p)) { inverter = i; phase = p; zoom = 1; lastZoom = 1 }
                    }
                }
            }
        } label: {
            Label(sheet, systemImage: "chevron.down").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.onPrimary.opacity(0.6)))
        }
        .accessibilityLabel("เลือกชีต")
    }

    /// `ค่าที่มาจากแอป iPad · IEC 62446` and the five steps; a swatch opens its step.
    private var legend: some View {
        HStack(spacing: 14) {
            Text("ค่าที่มาจากแอป iPad · IEC 62446").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
            ForEach(IECSheetCanvas.legendStages, id: \.self) { s in
                Button { request(s, inverter, nil) } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(IECSheetCanvas.fill(s)).frame(width: 18, height: 14)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(IECSheetCanvas.line(s)))
                        Text("\(s.rawValue)").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.navy)
                            .frame(width: 20, height: 20).overlay(Circle().strokeBorder(Theme.navy))
                        Text(s.title).font(.sarabunFixed(14)).foregroundStyle(Theme.navy)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ขั้น \(s.rawValue) \(s.title)")
            }
            Spacer(minLength: 8)
            Text("ไม่พิมพ์ลงไฟล์ Excel").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
    }
}

/// The sheet: fills, the source tints and borders in a `Canvas`, cell text and the logos over it, all from the layout.
struct IECSheetCanvas: View {
    let layout: IECSheetLayout
    let report: IECReport
    let inverter: Int
    let phase: IECReport.Phase
    let sources: Bool
    let scale: CGFloat
    /// Fit ↔ 2×: on the same view as the cell tap, which it comes before.
    let doubleTap: () -> Void
    let open: (IECReport.Stage, Int?) -> Void

    static let legendStages: [IECReport.Stage] = [.setup, .beforeVoltage, .beforeInsulation, .afterVoltage, .energy]

    static func fill(_ s: IECReport.Stage) -> Color {
        switch s {
        case .setup: Theme.sheetSource1Fill
        case .beforeVoltage: Theme.sheetSource2Fill
        case .beforeInsulation: Theme.sheetSource3Fill
        case .afterVoltage: Theme.sheetSource4Fill
        default: Theme.sheetSource5Fill
        }
    }

    static func line(_ s: IECReport.Stage) -> Color {
        switch s {
        case .setup: Theme.sheetSource1Line
        case .beforeVoltage: Theme.sheetSource2Line
        case .beforeInsulation: Theme.sheetSource3Line
        case .afterVoltage: Theme.sheetSource4Line
        default: Theme.sheetSource5Line
        }
    }

    /// TH Sarabun New (the form's font, not on iOS) draws about this much smaller than Sarabun at the same size.
    static let fontFactor: CGFloat = 0.74

    private var inv: IECReport.Inverter { report.inverters.indices.contains(inverter) ? report.inverters[inverter] : IECReport.Inverter() }

    /// A drawn cell: its rect (the merge's when merged) and what's in it.
    struct Box { let ref: String; let rect: CGRect; let cell: IECSheetLayout.Cell?; let source: IECReport.Stage? }

    private var boxes: [Box] {
        var out: [Box] = []
        for r in 1...layout.rows.count {
            for c in 1...layout.columns.count {
                let ref = Self.ref(c, r)
                var rect = CGRect(x: layout.x(c), y: layout.y(r), width: layout.columns[c - 1], height: layout.rows[r - 1])
                if let m = layout.merge(at: c, r) {
                    guard m.c0 == c, m.r0 == r else { continue }
                    rect = CGRect(x: layout.x(m.c0), y: layout.y(m.r0), width: layout.x(m.c1 + 1) - layout.x(m.c0), height: layout.y(m.r1 + 1) - layout.y(m.r0))
                }
                guard rect.width > 0, rect.height > 0 else { continue }
                out.append(Box(ref: ref, rect: rect, cell: layout.cells[ref], source: IECReport.sheetSource(ref, inverter: inv, phase: phase)))
            }
        }
        return out
    }

    static func ref(_ c: Int, _ r: Int) -> String {
        var n = c - 1, s = ""
        repeat { s = String(UnicodeScalar(UInt8(65 + n % 26))) + s; n = n / 26 - 1 } while n >= 0
        return s + String(r)
    }

    var body: some View {
        let boxes = boxes
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in draw(ctx, boxes) }
            ForEach(boxes.filter { !($0.cell?.text.isEmpty ?? true) }, id: \.ref) { b in text(b) }
            ForEach(Array(layout.images.enumerated()), id: \.offset) { _, img in
                if let ui = UIImage(data: img.data) {
                    Image(uiImage: ui).resizable().scaledToFit()
                        .frame(width: img.width * scale, height: img.height * scale)
                        .offset(x: img.x * scale, y: img.y * scale)
                        .accessibilityHidden(true)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: doubleTap)
        .onTapGesture(coordinateSpace: .local) { p in tap(p, boxes) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ชีต Excel")
    }

    private func color(_ c: IECSheetLayout.RGB) -> Color { Color(red: c.r, green: c.g, blue: c.b) }

    private func scaled(_ r: CGRect) -> CGRect { CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale) }

    private func draw(_ ctx: GraphicsContext, _ boxes: [Box]) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: layout.width * scale, height: layout.height * scale)), with: .color(Theme.paper))
        for b in boxes {
            let rect = scaled(b.rect)
            if let s = b.cell.map({ layout.styles[$0.style] }), let f = s.fill { ctx.fill(Path(rect), with: .color(color(f))) }
            if sources, let src = b.source {
                ctx.fill(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(Self.fill(src)))
                let inner = Path(rect.insetBy(dx: 1.5, dy: 1.5))
                // a value still missing: dashed red, so the gap shows
                if b.cell?.text.isEmpty ?? true {
                    ctx.stroke(inner, with: .color(Theme.danger), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                } else {
                    ctx.stroke(inner, with: .color(Self.line(src)), lineWidth: 1)
                }
            }
        }
        // borders after the fills, each cell's own, skipping the inside of a merge
        for r in 1...layout.rows.count {
            for c in 1...layout.columns.count {
                guard let cell = layout.cells[Self.ref(c, r)] else { continue }
                let s = layout.styles[cell.style], m = layout.merge(at: c, r)
                let x0 = layout.x(c) * scale, x1 = layout.x(c + 1) * scale, y0 = layout.y(r) * scale, y1 = layout.y(r + 1) * scale
                func edge(_ line: IECSheetLayout.Line?, _ a: CGPoint, _ b: CGPoint, inside: Bool) {
                    guard let line, !inside else { return }
                    var p = Path(); p.move(to: a); p.addLine(to: b)
                    ctx.stroke(p, with: .color(color(line.color)),
                               style: StrokeStyle(lineWidth: max(0.5, line.width * scale * 0.75), dash: line.dashed ? [2, 2] : []))
                }
                edge(s.top, CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), inside: m.map { r > $0.r0 } ?? false)
                edge(s.bottom, CGPoint(x: x0, y: y1), CGPoint(x: x1, y: y1), inside: m.map { r < $0.r1 } ?? false)
                edge(s.left, CGPoint(x: x0, y: y0), CGPoint(x: x0, y: y1), inside: m.map { c > $0.c0 } ?? false)
                edge(s.right, CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), inside: m.map { c < $0.c1 } ?? false)
            }
        }
    }

    private func text(_ b: Box) -> some View {
        let cell = b.cell!, s = layout.styles[cell.style]
        let h: TextAlignment = s.horizontal == "center" || s.horizontal == "centerContinuous" ? .center
            : s.horizontal == "right" || (s.horizontal == "general" && cell.isNumber) ? .trailing : .leading
        let frameAlign: Alignment = switch (h, s.vertical) {
        case (.center, "top"): .top
        case (.center, "center"): .center
        case (.center, _): .bottom
        case (.trailing, "top"): .topTrailing
        case (.trailing, "center"): .trailing
        case (.trailing, _): .bottomTrailing
        case (_, "top"): .topLeading
        case (_, "center"): .leading
        default: .bottomLeading
        }
        let size = max(4, s.fontSize * Self.fontFactor * scale * (s.symbols ? 0.8 : 1))
        return Text(cell.text)
            .font(.sarabunFixed(size, s.bold ? .bold : .regular))
            .foregroundStyle(color(s.color))
            .multilineTextAlignment(h)
            .lineLimit(s.wrap ? 4 : 1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 2 * scale)
            .frame(width: b.rect.width * scale, height: b.rect.height * scale, alignment: frameAlign)
            .offset(x: b.rect.minX * scale, y: b.rect.minY * scale)
            .allowsHitTesting(false)
    }

    private func tap(_ p: CGPoint, _ boxes: [Box]) {
        guard sources, let hit = layout.cell(at: p.x / scale, p.y / scale) else { return }
        let ref = Self.ref(hit.col, hit.row)
        guard let stage = IECReport.sheetSource(ref, inverter: inv, phase: phase) else { return }
        open(stage, IECReport.sheetSlot(ref))
    }
}
