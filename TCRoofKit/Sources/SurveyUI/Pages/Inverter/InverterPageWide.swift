#if canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import TCRoofCore
import PDFReport
import TCRoofUI

/// B2 (docs/ui/survey-b2): the area photo with its drawn boundary, the measured size and column spans on the left;
/// the live station plan and the Growatt inverters on the right. Everything else (cabinets, breakers, cables, tray, ladder, room)
/// comes from `InverterStation` and the equipment catalog. Field ids are unchanged and the new answers are optional.
/// iPad portrait and iPhone stack the two columns.
struct InverterPageWide: View {
    @Binding var job: Job
    let moduleID: UUID
    /// Width of the page's content.
    let width: CGFloat
    /// Portrait: the photo and size column on top, the plan and inverters below it, the page scrolling.
    var stacked = false
    @Environment(SurveyModel.self) var model

    enum PhotoTab { case area, boundary }
    @State var tab: PhotoTab = .area
    @State var drawing = false
    @State var draft: [ShapePoint] = []
    @State var history: [[SiteShape]] = []
    @State var editingEdge: Int?
    @State var edgeText = ""
    @State var spanSel = 0
    @State var showPlan = false
    @State var viewing: Photo?

    var leftWidth: CGFloat { min(460, max(400, width * 0.33)) }
    /// iPhone: asides under labels, a shorter photo, rows that sit side by side on iPad one above the other.
    var narrow: Bool { width < 600 }
    var photoHeight: CGFloat { narrow ? 260 : stacked ? 420 : 300 }

    var index: Int? { job.modules.firstIndex { $0.id == moduleID } }
    var values: Values { index.map { job.modules[$0].values } ?? Values() }
    var station: InverterStation { InverterStation(values) }

    /// Changes the station and writes it back (with `sizeLWH` and `inverterCount`).
    func update(_ change: (inout InverterStation) -> Void) {
        guard let i = index else { return }
        var s = station
        change(&s)
        s.write(to: &job.modules[i].values)
    }
    func set(_ id: String, _ v: FieldValue?) { if let i = index { job.modules[i].values[id] = v } }
    func text(_ id: String) -> Binding<String> {
        Binding(get: { values.text(id) }, set: { set(id, .text($0)) })
    }

    var body: some View {
        VStack(spacing: 16) {
            PageStepBar(job: job, here: .module(moduleID))
            if stacked {
                ScrollView {
                    VStack(spacing: 24) {
                        leftColumn
                        rightColumn
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    ScrollView { leftColumn.padding(.bottom, 4) }.scrollIndicators(.hidden).frame(width: leftWidth)
                    ScrollView { rightColumn.padding(.bottom, 4) }.scrollIndicators(.hidden).frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .foregroundStyle(Theme.navy)
        .sheet(item: $viewing) { p in if let img = model.image(p, in: job.id) { PhotoViewer(image: img, title: "พื้นที่ติดตั้งอินเวอร์เตอร์") } }
        .fullScreenCover(isPresented: $showPlan) { PlanViewer(sketch: InverterStationDrawing.sketch(station), title: planTitle) }
        .alert("ระยะด้านนี้ (ม.)", isPresented: Binding(get: { editingEdge != nil }, set: { if !$0 { editingEdge = nil } })) {
            TextField("เช่น 9.5", text: $edgeText).keyboardType(.decimalPad)
            Button("ตกลง") { saveEdge() }
            Button("ยกเลิก", role: .cancel) { editingEdge = nil }
        } message: { Text("พิมพ์ความยาวที่วัดได้ของเส้นขอบนี้") }
    }

    // MARK: left column

    var leftColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            photoCard
            sizeCard
            if station.site == .outdoor { spansCard }
            VStack(alignment: .leading, spacing: 6) {
                label("รายละเอียดเพิ่มเติม", aside: "เช่น พื้นเดิม หลังคา ตู้ที่ต้องย้าย")
                TextEditor(text: text("detail"))
                    .font(.sarabunFixed(17)).scrollContentBackground(.hidden).padding(8)
                    .frame(minHeight: 110)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderControl))
            }
        }
    }

    func label(_ t: String, required: Bool = false, aside: String? = nil) -> some View {
        let row = narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return row {
            (Text(t) + (required ? Text(" *").foregroundColor(Theme.danger) : Text(""))).font(.sarabunFixed(17, .bold))
            if !narrow { Spacer(minLength: 8) }
            if let aside { Text(aside).font(.footnote).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8) }
        }
    }

    // MARK: photos and boundary

    var photoField: String { tab == .area ? "photoArea" : "photoDetail" }
    var boundary: SiteShape? { values.shapes(InverterStation.Key.boundary).first }

    func addPhoto(_ img: UIImage) {
        guard let p = model.addPhoto(img, to: job.id) else { return }
        set(photoField, .photo(p))
    }

    var photoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("ภาพพื้นที่", required: true)
            HStack(spacing: 0) {
                segment(values.photo("photoArea") != nil ? "ภาพพื้นที่ ✓" : "ภาพพื้นที่", on: tab == .area) { tab = .area; drawing = false; draft = [] }
                segment(boundary != nil ? "ภาพระบุขอบเขต ✓" : "ภาพระบุขอบเขต", on: tab == .boundary) { tab = .boundary }
            }
            .padding(3).background(Theme.navy.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
            if values.photo(photoField) == nil {
                PhotoSlot(photo: nil, jobID: job.id, hint: tab == .area ? "ถ่ายภาพพื้นที่ติดตั้ง Inverter Station" : "ภาพสำหรับวาดขอบเขตพื้นที่",
                          required: tab == .area, extra: useAreaPhoto, onPick: addPhoto, onClear: {})
                    .frame(height: photoHeight)
            } else {
                GeometryReader { geo in stage(geo.size) }
                    .frame(height: photoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(drawing ? Theme.teal : Theme.navy.opacity(0.15), lineWidth: drawing ? 2 : 1))
            }
        }
    }

    func segment(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.sarabunFixed(15, on ? .bold : .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .shadow(color: on ? Theme.navy.opacity(0.12) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    func imageRect(_ img: UIImage, in size: CGSize) -> CGRect {
        guard img.size.width > 0, img.size.height > 0, size.width > 0, size.height > 0 else { return .zero }
        let k = min(size.width / img.size.width, size.height / img.size.height)
        let w = img.size.width * k, h = img.size.height * k
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
    func point(_ p: ShapePoint, in r: CGRect) -> CGPoint { CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height) }

    @ViewBuilder func stage(_ size: CGSize) -> some View {
        let photo = values.photo(photoField)
        ZStack(alignment: .topLeading) {
            PhotoSlot.stageColor
            if let p = photo, let img = model.image(p, in: job.id) {
                let r = imageRect(img, in: size)
                Image(uiImage: img).resizable().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                if tab == .boundary {
                    boundaryDrawing(r).allowsHitTesting(false)
                    if !drawing { edgeChips(r) }
                    // taps while drawing add points
                    if drawing {
                        Color.white.opacity(0.001).frame(width: size.width, height: size.height)
                            .onTapGesture(coordinateSpace: .local) { tap($0, in: r) }
                    }
                } else {
                    Color.white.opacity(0.001).frame(width: size.width, height: size.height).onTapGesture { viewing = p }
                }
            } else {
                PhotoSlot.notDownloaded
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) {
            if photo != nil { if tab == .boundary { boundaryTools.padding(10) } else { PhotoDoneBadge() } }
        }
        .overlay(alignment: .topTrailing) {
            if photo != nil {
                PhotoClearButton(label: tab == .boundary && (boundary != nil || !draft.isEmpty) ? "ล้างขอบเขต" : "ลบภาพ") { clearPhotoOrBoundary() }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if photo != nil && tab == .boundary {
                Text(drawing ? "แตะทีละมุม · แตะจุดแรกเพื่อปิดขอบเขต (\(draft.count) จุด)" : "วาดขอบเขตแล้วใส่ระยะบนเส้น")
                    .font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.navy)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.surface.opacity(0.95), in: Capsule()).padding(10).allowsHitTesting(false)
            }
        }
    }

    /// On the boundary tab, reuses the area photo instead of taking another.
    var useAreaPhoto: AnyView? {
        guard tab == .boundary, let p = values.photo("photoArea"), let img = model.image(p, in: job.id) else { return nil }
        return AnyView(Button { addPhoto(img) } label: {
            Label("ใช้ภาพพื้นที่", systemImage: "photo").font(.sarabunFixed(15, .bold)).frame(minHeight: 44)
        }.buttonStyle(TCButtonStyle(.primary, size: .card)))
    }

    var boundaryTools: some View {
        HStack(spacing: 6) {
            Button { drawing.toggle(); draft = [] } label: {
                HStack(spacing: 6) {
                    A2Icon(name: "ui-draw-boundary", fallback: "pencil", size: 16).foregroundStyle(Theme.teal)
                    Text(drawing ? "เลิกวาด" : "วาดขอบเขต")
                }
                .toolChip(on: drawing)
            }
            .buttonStyle(.plain)
            Button { undo() } label: { Text("↶ ย้อน").toolChip(on: false) }
                .buttonStyle(.plain).disabled(draft.isEmpty && history.isEmpty).opacity(draft.isEmpty && history.isEmpty ? 0.5 : 1)
        }
    }

    func boundaryDrawing(_ r: CGRect) -> some View {
        let box = Box(Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
        return Canvas { ctx, _ in
            var shapes: [SiteShape] = []
            // edge chips are SwiftUI buttons on the page, so draw the outline without them
            if var b = boundary, !drawing { b.edges = []; shapes.append(b) }
            if drawing && draft.count >= 2 {
                // an open outline while drawing
                let pts = draft.map { point($0, in: r) }
                for (a, b) in zip(pts, pts.dropFirst()) {
                    var p = Path(); p.move(to: a); p.addLine(to: b)
                    ctx.stroke(p, with: .color(Theme.teal), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                }
            }
            let ops = SiteShapes.ops(shapes, in: box, metersAcross: nil)
            ctx.withCGContext { cg in PDFRenderer.draw(ops, in: cg, photo: { _ in nil }) }
            if drawing {
                for (i, p) in draft.enumerated() {
                    let c = point(p, in: r), rad: CGFloat = i == 0 ? 9 : 5
                    let e = Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad))
                    ctx.fill(e, with: .color(.white)); ctx.stroke(e, with: .color(Theme.teal), lineWidth: 2)
                }
            }
        }
    }

    /// A chip on each edge: its typed length, or "ใส่ระยะ"; tap to type.
    func edgeChips(_ r: CGRect) -> some View {
        ForEach(Array((boundary?.points.indices ?? 0..<0)), id: \.self) { i in
            if let b = boundary, let m = b.edgeMid(i) {
                let e = b.edges[safe: i] ?? ""
                Button { edgeText = e; editingEdge = i } label: {
                    Text(e.isEmpty ? "ใส่ระยะ" : e + " ม.").font(.sarabunFixed(13, .bold))
                        .foregroundStyle(e.isEmpty ? Theme.teal : .white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(e.isEmpty ? Theme.surface : Theme.teal, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.teal))
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(point(m, in: r))
                .accessibilityLabel("ระยะด้านที่ \(i + 1)" + (e.isEmpty ? "" : " \(e) เมตร"))
            }
        }
    }

    func tap(_ p: CGPoint, in r: CGRect) {
        guard r.width > 0, r.height > 0, r.insetBy(dx: -4, dy: -4).contains(p) else { return }
        if draft.count >= 3, let first = draft.first, hypot(point(first, in: r).x - p.x, point(first, in: r).y - p.y) < 22 {
            setBoundary(SiteShape(kind: .boundary, points: draft, edges: Array(repeating: "", count: draft.count)))
            draft = []; drawing = false
            return
        }
        draft.append(ShapePoint(Double((p.x - r.minX) / r.width), Double((p.y - r.minY) / r.height)))
    }

    func setBoundary(_ s: SiteShape?) {
        history.append(values.shapes(InverterStation.Key.boundary))
        set(InverterStation.Key.boundary, s.map { .shapes([$0]) })
    }
    func undo() {
        if !draft.isEmpty { draft.removeLast(); return }
        guard let last = history.popLast() else { return }
        set(InverterStation.Key.boundary, last.isEmpty ? nil : .shapes(last))
    }
    func saveEdge() {
        guard let i = editingEdge, var b = boundary else { editingEdge = nil; return }
        if b.edges.count < b.points.count { b.edges += Array(repeating: "", count: b.points.count - b.edges.count) }
        b.edges[i] = NumberInput.value(edgeText).map { fmt($0) } ?? ""
        setBoundary(b)
        editingEdge = nil
    }
    /// × on the photo: clears the boundary first (while drawing, the draft), then the photo.
    func clearPhotoOrBoundary() {
        if tab == .boundary && (drawing || !draft.isEmpty) { draft = []; drawing = false; return }
        if tab == .boundary && boundary != nil { setBoundary(nil); return }
        set(photoField, nil)
    }

    // MARK: size

    var sizeCard: some View {
        let s = station
        return VStack(alignment: .leading, spacing: 8) {
            label("ขนาดพื้นที่ที่มีจริง (วัด)", required: true, aside: "ก × ย × ส (ม.) · แปลนวาดตามค่านี้")
            if narrow {
                RatioRow(weights: [1, 1], spacing: 10) { roomWidthStepper(s); roomLengthStepper(s) }
                heightField(s)
            } else {
                RatioRow(weights: [1.15, 1.15, 0.8], spacing: 10) { roomWidthStepper(s); roomLengthStepper(s); heightField(s) }
            }
        }
    }

    func roomWidthStepper(_ s: InverterStation) -> some View {
        stepper("ก กว้าง", value: s.width, digits: 1, error: s.width.map { !InverterStation.widthRange.contains($0) } ?? false,
                down: { step(\.width, -InverterStation.widthStep, InverterStation.widthRange, start: InverterStation.roomWidth) },
                up: { step(\.width, InverterStation.widthStep, InverterStation.widthRange, start: InverterStation.roomWidth) })
    }

    func roomLengthStepper(_ s: InverterStation) -> some View {
        stepper("ย ยาว", value: s.length, digits: 1, error: s.length.map { !InverterStation.lengthRange.contains($0) } ?? false,
                down: { step(\.length, -InverterStation.lengthStep, InverterStation.lengthRange, start: s.minLength) },
                up: { step(\.length, InverterStation.lengthStep, InverterStation.lengthRange, start: s.minLength) })
    }

    func heightField(_ s: InverterStation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ส สูง").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            TextField("3.0", text: Binding(get: { s.height.map { fmt($0) } ?? "" },
                                          set: { t in update { $0.height = NumberInput.value(t) } }))
                .keyboardType(.decimalPad).font(.sarabunFixed(20, .bold)).inputBox(minHeight: 48)
        }
    }

    /// Steps W / L; the first press on an empty value starts from `start`. Values are clamped only when stepped.
    func step(_ key: WritableKeyPath<InverterStation, Double?>, _ d: Double, _ range: ClosedRange<Double>, start: Double) {
        update { s in
            let v = s[keyPath: key].map { (($0 + d) * 10).rounded() / 10 } ?? start
            s[keyPath: key] = min(range.upperBound, max(range.lowerBound, v))
        }
    }

    func stepper(_ title: String, value: Double?, digits: Int, error: Bool, down: @escaping () -> Void, up: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            HStack(spacing: 0) {
                stepButton("minus", action: down)
                Text(value.map { String(format: "%.\(digits)f", $0) } ?? "–").font(.sarabunFixed(20, .bold)).monospacedDigit()
                    .foregroundStyle(error ? Theme.danger : Theme.navy).frame(maxWidth: .infinity)
                stepButton("plus", action: up)
            }
            .frame(minHeight: 48)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(error ? Theme.danger : Theme.navy.opacity(0.45)))
        }
    }

    func stepButton(_ symbol: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(enabled ? Theme.primary : Theme.disabledText)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    // MARK: column spans

    var spansCard: some View {
        let s = station, editable = s.editableSpans, sel = min(spanSel, max(editable.count - 1, 0))
        let custom = s.userSpans != nil
        let eqEnabled = s.spans.count > 1 && s.spans.contains { abs($0 - s.planLength / Double(s.spans.count)) > 0.005 }
        return VStack(alignment: .leading, spacing: 8) {
            label("ระยะช่วงเสา (ม.)", required: true)
            if narrow {
                // iPhone: the stepper on its own line, the spans five to a row under it
                HStack(spacing: 6) {
                    stepButton("minus", enabled: !editable.isEmpty) { setSpan(sel, by: -InverterStation.spanStep) }
                    Text(editable.isEmpty ? "–" : "ช่วงที่ \(sel + 1)").font(.sarabunFixed(14, .semibold)).frame(maxWidth: .infinity)
                    stepButton("plus", enabled: !editable.isEmpty) { setSpan(sel, by: InverterStation.spanStep) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(Array(s.spans.enumerated()), id: \.offset) { i, v in spanButton(i, v, s, sel: sel) }
                }
            } else {
                HStack(spacing: 6) {
                    stepButton("minus", enabled: !editable.isEmpty) { setSpan(sel, by: -InverterStation.spanStep) }
                    ForEach(Array(s.spans.enumerated()), id: \.offset) { i, v in spanButton(i, v, s, sel: sel) }
                    stepButton("plus", enabled: !editable.isEmpty) { setSpan(sel, by: InverterStation.spanStep) }
                }
            }
            Text(s.spansOK ? "\(s.spans.count) ช่วง · รวม \(String(format: "%.2f", s.planLength)) ม. " + (custom ? "✓" : "· อัตโนมัติ ✓")
                           : "ช่วงสุดท้ายเหลือ \(String(format: "%.2f", s.lastSpan)) ม. ✗")
                .font(.sarabunFixed(13, s.spansOK ? .regular : .bold)).foregroundStyle(s.spansOK ? Theme.success : Theme.danger)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: narrow ? 2 : 4), spacing: 6) {
                smallButton(s.spans.count < InverterStation.maxSpans ? "+ เพิ่มช่วง" : "ครบ 10 ช่วง", enabled: s.spans.count < InverterStation.maxSpans) {
                    update { $0.userSpans = $0.editableSpans + [2.5] }; spanSel = editable.count
                }
                smallButton("ลบช่วงที่เลือก", enabled: editable.count > 1) {
                    update { var a = $0.editableSpans; a.remove(at: sel); $0.userSpans = a }; spanSel = max(0, sel - 1)
                }
                smallButton("EQ เท่ากัน", enabled: eqEnabled) { update { $0.userSpans = $0.equalSpans } }
                smallButton("คืนค่าอัตโนมัติ", enabled: custom) { update { $0.userSpans = nil }; spanSel = 0 }
            }
        }
    }

    /// One span; the last is what's left of the room and can't be picked.
    func spanButton(_ i: Int, _ v: Double, _ s: InverterStation, sel: Int) -> some View {
        let last = i == s.spans.count - 1
        return Button { if !last { spanSel = i } } label: {
            Text(String(format: "%.2f", v)).font(.sarabunFixed(14, .bold)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(last ? (s.spansOK ? Theme.inkMuted : Theme.dangerText) : Theme.navy)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(last ? (s.spansOK ? Theme.progressBoxIdle : Theme.danger.opacity(0.08)) : i == sel ? Theme.primarySoft : Theme.surface,
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(last ? (s.spansOK ? Theme.borderControl : Theme.danger) : i == sel ? Theme.primary : Theme.borderControl,
                                                                  style: StrokeStyle(lineWidth: !last && i == sel ? 2 : 1, dash: last ? [4, 3] : [])))
        }
        .buttonStyle(.plain).disabled(last)
        .accessibilityLabel("ช่วงที่ \(i + 1) \(String(format: "%.2f", v)) เมตร" + (last ? " คำนวณจากความยาวห้อง" : ""))
    }

    func setSpan(_ i: Int, by d: Double) {
        update { s in
            var a = s.editableSpans
            guard a.indices.contains(i) else { return }
            a[i] = min(InverterStation.spanRange.upperBound, max(InverterStation.spanRange.lowerBound, ((a[i] + d) * 100).rounded() / 100))
            s.userSpans = a
        }
    }

    func smallButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.sarabunFixed(13, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(enabled ? Theme.primary : Theme.disabledText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(enabled ? Theme.primary.opacity(0.5) : Theme.disabledFill))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

extension View {
    /// White chip on the photo (draw / undo), teal when active.
    func toolChip(on: Bool) -> some View {
        font(.system(size: 14, weight: .semibold)).foregroundStyle(on ? .white : Theme.navy)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(on ? Theme.teal : Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The plan full screen: pinch and pan.
struct PlanViewer: View {
    let sketch: Sketch
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let k = min(8, max(1, zoom * pinch))
                ScrollView([.horizontal, .vertical]) {
                    SketchView(sketch: sketch)
                        .frame(width: geo.size.width * k, height: geo.size.width * k * CGFloat(sketch.height / sketch.width))
                        .background(Theme.paper)
                }
                .gesture(MagnifyGesture().updating($pinch) { v, s, _ in s = v.magnification }.onEnded { v in zoom = min(8, max(1, zoom * v.magnification)) })
            }
            .background(Theme.paper)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("ปิด") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { Button { zoom = 1 } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }.disabled(zoom == 1) }
            }
        }
    }
}
#endif
