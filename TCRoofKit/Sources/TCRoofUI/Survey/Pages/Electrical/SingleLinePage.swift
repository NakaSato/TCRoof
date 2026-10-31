#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// Single line diagram page (docs/ui/survey-sld), opened from A3's "สร้าง Single Line Diagram →".
/// The diagram is generated from the survey by `SingleLine` / `SingleLineLayout` — the same ops the A3 PDF draws — and is not edited here;
/// a tap on an item closes the page and opens the A3 (or B) page on that item.
struct SingleLinePage: View {
    @Binding var job: Job
    /// Tap on a diagram item or a "A3 →" link.
    let open: (SLTarget) -> Void
    let close: () -> Void
    @Environment(SurveyModel.self) var model
    @Environment(\.horizontalSizeClass) var sizeClass

    static let levels: [CGFloat] = [0.35, 0.5, 0.6, 0.75, 0.9, 1.0]
    @State var scale: CGFloat = 0.5
    @State var pinchBase: CGFloat?
    @State var viewport: CGSize = .zero
    @State var fitted = false
    /// HV / LV preview while the job has no B4 section.
    @State var hvPreview = false
    @State var focusPoint: CGPoint?
    @State var showPanel = false
    @State var listSheet: ListKind?
    @State var shared: ShareItem?
    @State var error: String?
    @State var stamp = Date()
    /// The diagram, rebuilt off the main thread after edits (`SingleLineRender`).
    @State var render = SingleLineRender()

    enum ListKind: String, Identifiable { case others, conditions, assumptions; var id: String { rawValue } }
    struct ShareItem: Identifiable { let id = UUID(); let url: URL }

    /// iPhone: a two-line header, the toggle's two choices side by side under their title, the zoom on the diagram and a smaller legend.
    var phone: Bool { sizeClass == .compact }
    var hasB4: Bool { job.modules.contains { $0.type == .backfeed } }
    /// Wide enough for the side panel next to the diagram.
    var twoPane: Bool { viewport.width >= 900 }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let made = render.result {
                GeometryReader { geo in
                    content(made.line, made.drawing).onAppear { viewport = geo.size } .onChange(of: geo.size) { _, s in viewport = s }
                }
                bottomBar(made.line)
            } else {
                ProgressView("กำลังสร้างแผนภาพ").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Paper.page)
        .foregroundStyle(Theme.navy)
        .sheet(isPresented: $showPanel) {
            if let sl = render.result?.line {
                NavigationStack { ScrollView { panel(sl).padding(16) }.tcPageBackground().navigationTitle("ข้อมูลฝั่ง PV")
                    .navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { showPanel = false } } } }
            }
        }
        .sheet(item: $listSheet) { k in if let sl = render.result?.line { listView(k, sl) } }
        .sheet(item: $shared) { s in ShareSheet(items: [s.url]).presentationDetents([.medium, .large]) }
        .errorAlert($error)
        .onAppear { stamp = Date(); render.update(job, hv: hasB4 ? nil : hvPreview, now: true) }
        .onDisappear { render.cancel() }
        .onChange(of: job) { _, j in render.update(j, hv: hasB4 ? nil : hvPreview) }
        .onChange(of: hvPreview) { _, v in render.update(job, hv: hasB4 ? nil : v, now: true) }
        #if DEBUG
        // `-surveySLDPanel YES` opens the iPhone's ข้อมูลฝั่ง PV sheet for simulator checks
        .task { if UserDefaults.standard.bool(forKey: "surveySLDPanel") { try? await Task.sleep(nanoseconds: 600_000_000); showPanel = true } }
        #endif
    }

    // MARK: header

    var subtitle: String {
        let code = job.jobSyncID.flatMap { model.linkedJobLabel?($0) }?.components(separatedBy: " | ").first
        let ref = [job.projectName.isEmpty ? nil : job.projectName, code ?? (job.docNo.isEmpty ? nil : job.docNo)].compactMap { $0 }.joined(separator: " ")
        return "สร้างอัตโนมัติจากข้อมูลสำรวจ A1 | A3 | B1 | B2 | B4 | B5" + (ref.isEmpty ? "" : " | " + ref)
    }

    var header: some View {
        HStack(spacing: phone ? 6 : 12) {
            Button(action: close) {
                Image("ui-back", bundle: .module).renderingMode(.template).resizable().scaledToFit().frame(width: 24, height: 24)
                    .foregroundStyle(Theme.primary).frame(width: 44, height: 44).background(Theme.onPrimary, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("ย้อนกลับ")
            VStack(alignment: .leading, spacing: 0) {
                Text(phone ? "แผนภาพเส้นเดียว" : "แผนภาพเส้นเดียว (Single Line Diagram)").font(.sarabunFixed(phone ? 17 : 20, .bold)).lineLimit(1)
                Text(phone ? "สร้างอัตโนมัติจากข้อมูลสำรวจ" : subtitle).font(.sarabunFixed(phone ? 13 : 15)).opacity(0.92).lineLimit(1)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if !twoPane {
                Button { showPanel = true } label: {
                    Group {
                        if phone { Image(systemName: "list.bullet.rectangle") } else { Label("ข้อมูล PV", systemImage: "list.bullet.rectangle") }
                    }
                    .font(.sarabunFixed(16, .semibold))
                    .padding(.horizontal, phone ? 0 : 14).frame(minWidth: 44, minHeight: 44).background(Theme.onPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).accessibilityLabel("ข้อมูลฝั่ง PV")
                .disabled(render.result == nil)
            }
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, phone ? 8 : 24).padding(.vertical, phone ? 6 : 10)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Theme.primary, Theme.primaryLight], startPoint: .leading, endPoint: .trailing).ignoresSafeArea(edges: .top))
    }

    // MARK: diagram area

    func content(_ sl: SingleLine, _ d: SingleLineDrawing) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 10) {
                toolbar(sl)
                card(sl, d)
                footer
            }
            if twoPane { ScrollView { panel(sl) }.frame(width: 310) }
        }
        .padding(.horizontal, phone ? 16 : 24).padding(.vertical, 12)
    }

    @ViewBuilder func toolbar(_ sl: SingleLine) -> some View {
        if phone {
            VStack(alignment: .leading, spacing: 8) { toggle(sl); connectionMenu(sl).frame(maxWidth: .infinity, alignment: .leading) }
        } else { padToolbar(sl) }
    }

    func padToolbar(_ sl: SingleLine) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { toggle(sl); connectionMenu(sl); Spacer(minLength: 8); zoomControl }
            VStack(alignment: .leading, spacing: 8) { HStack { toggle(sl); Spacer(); zoomControl }; connectionMenu(sl) }
        }
    }

    @ViewBuilder func toggle(_ sl: SingleLine) -> some View {
        if phone {
            VStack(alignment: .leading, spacing: 6) {
                Text("ตำแหน่งกันย้อน (B4)").font(.sarabunFixed(16, .bold)).lineLimit(1)
                HStack(spacing: 2) {
                    seg("แรงต่ำ | ที่ \(sl.connectionBoard?.name ?? "MDP-1")", on: !sl.zeroExportHV) { setHV(false) }
                    seg("แรงสูง | หลังมิเตอร์", on: sl.zeroExportHV) { setHV(true) }
                }
                .padding(3).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
                if !hasB4 { Text("ยังไม่มีหัวข้อ B4 | ดูตัวอย่างเท่านั้น").font(.sarabunFixed(12)).foregroundStyle(Theme.pending).lineLimit(1) }
            }
        } else { padToggle(sl) }
    }

    func padToggle(_ sl: SingleLine) -> some View {
        HStack(spacing: 10) {
            Text("ตำแหน่งกันย้อน (B4)").font(.sarabunFixed(17, .bold)).lineLimit(1)
            HStack(spacing: 2) {
                seg("แรงต่ำ | ที่ \(sl.connectionBoard?.name ?? "MDP-1")", on: !sl.zeroExportHV) { setHV(false) }
                seg("แรงสูง | หลังมิเตอร์", on: sl.zeroExportHV) { setHV(true) }
            }
            .padding(3).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
            if !hasB4 { Text("ยังไม่มีหัวข้อ B4 | ดูตัวอย่างเท่านั้น").font(.sarabunFixed(13)).foregroundStyle(Theme.pending).lineLimit(1) }
        }
    }

    func seg(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.sarabunFixed(15, .bold)).lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, phone ? 6 : 14)
                .frame(maxWidth: phone ? .infinity : nil, minHeight: 44)
                .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                .background(on ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    /// B4 `level`; without a B4 section the choice is only a preview.
    func setHV(_ hv: Bool) {
        guard let i = job.modules.firstIndex(where: { $0.type == .backfeed }) else { hvPreview = hv; return }
        job.modules[i].values["level"] = .choice(hv ? "กันย้อนที่แรงสูง" : "กันย้อนที่แรงต่ำ", other: "")
    }

    /// "เชื่อมต่อ PV ที่ตู้นี้": which transformer / board the PV branch hangs on (answers `sldTransformer`, `sldBoard`).
    func connectionMenu(_ sl: SingleLine) -> some View {
        Menu {
            ForEach(sl.transformers) { tx in
                ForEach(tx.boards) { bd in
                    Button {
                        job.values["sldTransformer"] = tx.index == 0 ? nil : .text(String(tx.index))
                        job.values["sldBoard"] = bd.index == 0 ? nil : .text(bd.id.uuidString)
                    } label: {
                        Label("TX\(tx.index + 1) | \(bd.name)", systemImage: tx.index == sl.connection.trafo && bd.index == sl.connection.board ? "checkmark" : "bolt")
                    }
                }
            }
        } label: {
            Label("เชื่อมต่อ PV ที่ \(sl.connectionBoard?.name ?? "—")", systemImage: "bolt.fill").font(.sarabunFixed(15, .bold)).lineLimit(1)
                .padding(.horizontal, 14).frame(minHeight: 44).foregroundStyle(Theme.primary)
                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(sl.transformers.isEmpty)
    }

    var zoomControl: some View {
        HStack(spacing: 6) {
            zoomButton("minus", "ย่อ") { step(-1) }
            Text("\(Int((scale * 100).rounded()))%").font(.sarabunFixed(16, .bold)).frame(minWidth: phone ? 46 : 52).monospacedDigit()
            zoomButton("plus", "ขยาย") { step(1) }
            Button { withAnimation { fit() } } label: {
                Group {
                    if phone { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 16, weight: .bold)) }
                    else { Text("พอดีจอ").font(.sarabunFixed(15, .bold)) }
                }
                .foregroundStyle(Theme.primary).padding(.horizontal, phone ? 0 : 12).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain).accessibilityLabel("พอดีจอ")
        }
        .padding(4).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle))
    }

    func zoomButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.primary).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    func step(_ d: Int) {
        let l = Self.levels
        let next = d > 0 ? l.first { $0 > scale + 0.005 } ?? l.last! : l.last { $0 < scale - 0.005 } ?? l.first!
        withAnimation { scale = next }
    }

    /// The diagram's width in the card, at most 100 %.
    func fit() { scale = cardWidth > 0 ? min(1, cardWidth / CGFloat(SingleLineLayout.width)) : 0.5 }
    var cardWidth: CGFloat { max(0, viewport.width - (phone ? 32 : 48) - 32 - (twoPane ? 326 : 0)) }

    func card(_ sl: SingleLine, _ d: SingleLineDrawing) -> some View {
        let w = CGFloat(d.width) * scale, h = CGFloat(d.height) * scale
        return ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Canvas { ctx, _ in
                    ctx.withCGContext { cg in
                        cg.scaleBy(x: scale, y: scale)
                        PDFRenderer.draw(d.sketch.ops, in: cg, photo: { _ in nil })
                    }
                }
                .frame(width: w, height: h)
                .background(Theme.paper)
                .contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .local) { p in tap(p, d) }
                .overlay(alignment: .topLeading) {
                    Color.clear.frame(width: 1, height: 1).offset(x: (focusPoint?.x ?? 0) * scale, y: (focusPoint?.y ?? 0) * scale).id("focus")
                }
                .accessibilityElement().accessibilityLabel("แผนภาพเส้นเดียว หม้อแปลง \(sl.transformers.count) ลูก ยังขาด \(sl.missing.count) จุด")
            }
            .onChange(of: focusPoint) { _, _ in Task { @MainActor in withAnimation { proxy.scrollTo("focus", anchor: .center) } } }
        }
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
        .simultaneousGesture(MagnifyGesture()
            .onChanged { v in let b = pinchBase ?? scale; pinchBase = b; scale = min(max(b * v.magnification, 0.3), 1.2) }
            .onEnded { _ in pinchBase = nil })
        .overlay(alignment: .bottomTrailing) { if phone { zoomControl.shadow(color: Theme.navy.opacity(0.15), radius: 4, y: 1).padding(8) } }
        .frame(maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { s in
            if !fitted, s.width > 0 { fitted = true; Task { @MainActor in fit() } }
        }
    }

    /// Smallest item under the finger; every tap area is at least 44 pt at the current zoom. Below 75 % the first tap zooms in.
    func tap(_ p: CGPoint, _ d: SingleLineDrawing) {
        let x = Double(p.x / scale), y = Double(p.y / scale)
        let minSide = 44.0 / Double(scale)
        let hits = d.hits.filter { h in
            let b = h.box, w = max(b.w, minSide), hh = max(b.h, minSide)
            let cx = b.x + b.w / 2, cy = b.y + b.h / 2
            return abs(x - cx) <= w / 2 && abs(y - cy) <= hh / 2
        }
        guard let best = hits.min(by: { $0.box.w * $0.box.h < $1.box.w * $1.box.h }) else { return }
        if scale < 0.75 {
            withAnimation { scale = 0.9 }
            focusPoint = CGPoint(x: best.box.x + best.box.w / 2, y: best.box.y + best.box.h / 2)
            return
        }
        open(best.target)
    }

    @ViewBuilder var footer: some View {
        if phone {
            VStack(alignment: .leading, spacing: 4) {
                Text("แตะอุปกรณ์เพื่อไปแก้ข้อมูลในหน้า A3 | ตัวแดง = ยังขาด").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 10) {
                    legend("legend-existing", "อุปกรณ์เดิม"); legend("legend-new-pv", "อุปกรณ์ใหม่ (PV)"); legend("legend-control", "สายสัญญาณควบคุม")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else { padFooter }
    }

    var padFooter: some View {
        HStack(spacing: 16) {
            Text("แตะอุปกรณ์เพื่อไปแก้ข้อมูลในหน้า A3 | ตัวแดง = ยังขาด").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            Spacer(minLength: 8)
            legend("legend-existing", "อุปกรณ์เดิม")
            legend("legend-new-pv", "อุปกรณ์ใหม่ (PV)")
            legend("legend-control", "สายสัญญาณควบคุม")
        }
    }

    func legend(_ icon: String, _ t: String) -> some View {
        HStack(spacing: 6) {
            Image(icon, bundle: .module).resizable().scaledToFit().frame(width: phone ? 18 : 24, height: 8)
            Text(t).font(.sarabunFixed(phone ? 12 : 14)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: bottom bar

    @ViewBuilder func bottomBar(_ sl: SingleLine) -> some View {
        if sizeClass == .compact { phoneBar(sl) } else { padBar(sl) }
    }

    /// iPhone: the notes and "แนบในรายงาน" above two equal buttons (docs/ui/components/iphone-bottom-bar, state 08).
    func phoneBar(_ sl: SingleLine) -> some View {
        VStack(spacing: 0) {
            // the note keeps the full width; the two buttons share the row under it
            VStack(alignment: .leading, spacing: 8) {
                notes(sl)
                HStack(spacing: 10) {
                    barButton("ส่งออก DXF", filled: false, action: exportDXF)
                    attachButton(job.values.text("sldAttach") == "1")
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Theme.surface)
                .overlay(alignment: .top) { Divider() }
            BottomBar(variant: .pair(secondary: .init(title: "แก้ข้อมูลใน A3") { open(SLTarget(.electrical)) },
                                     primary: .init(title: "ส่งออก PDF (A3)", action: exportPDF)))
        }
    }

    func padBar(_ sl: SingleLine) -> some View {
        let attach = job.values.text("sldAttach") == "1"
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { notes(sl); Spacer(minLength: 8); buttons(attach) }
            VStack(alignment: .leading, spacing: 8) { notes(sl); HStack { Spacer(); buttons(attach) } }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider() }
    }

    func notes(_ sl: SingleLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("สร้างจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง | อัปเดตเองเมื่อแก้ข้อมูลใน A3").font(.sarabunFixed(15, .semibold)).foregroundStyle(Theme.danger)
            Text("ข้อมูลล่าสุด \(stamp.formatted(.dateTime.hour().minute())) | ยังขาด \(sl.missing.count) จุด").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
        }
    }

    func buttons(_ attach: Bool) -> some View {
        HStack(spacing: 10) {
            barButton("‹ แก้ข้อมูลใน A3", filled: false, action: { open(SLTarget(.electrical)) })
            barButton("ส่งออก DXF", filled: false, action: exportDXF)
            barButton("ส่งออก PDF (A3)", filled: true, action: exportPDF)
            attachButton(attach)
        }
    }

    func attachButton(_ attach: Bool) -> some View {
        Button { job.values["sldAttach"] = attach ? nil : .text("1") } label: {
            HStack(spacing: 6) {
                if attach { Image(systemName: "checkmark") }
                Text("แนบในรายงาน")
            }
            .font(.sarabunFixed(16, .bold)).padding(.horizontal, 18).frame(minHeight: 48)
            .foregroundStyle(attach ? .white : Theme.navy)
            .background(attach ? Theme.success : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(attach ? Theme.success : Theme.borderControl))
        }
        .buttonStyle(.plain).accessibilityAddTraits(attach ? .isSelected : [])
    }

    func barButton(_ t: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.sarabunFixed(16, .bold)).padding(.horizontal, 18).frame(minHeight: 48)
                .foregroundStyle(filled ? Theme.onPrimary : Theme.navy)
                .background(filled ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(filled ? Theme.primary : Theme.borderControl))
        }
        .buttonStyle(.plain)
    }

    func exportPDF() {
        Task { @MainActor in
            do {
                let hv: Bool? = hasB4 ? nil : hvPreview
                let f = try await model.exportSingleLinePDF(job, hv: hv)
                shared = ShareItem(url: f.url)
            } catch { self.error = error.localizedDescription }
        }
    }

    /// The same diagram as `exportPDF`, as a DXF for CAD programs.
    func exportDXF() {
        Task { @MainActor in
            do {
                let hv: Bool? = hasB4 ? nil : hvPreview
                let f = try await model.exportSingleLineDXF(job, hv: hv)
                shared = ShareItem(url: f.url)
            } catch { self.error = error.localizedDescription }
        }
    }
}
#endif
