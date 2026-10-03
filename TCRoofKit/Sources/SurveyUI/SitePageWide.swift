#if canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import TCRoofCore
import PDFReport

/// A2 on iPad in landscape (docs/ui/survey-a2): the site picture with drawing tools on the left; picture source,
/// symbol palette, LIST and site note on the right. Portrait and iPhone keep the schema form (`groupPage`).
/// Field ids are unchanged; drawings go under `SiteShapes.key` and the new fields are optional, so completion is too.
struct SitePageWide: View {
    @Binding var job: Job
    /// Width of the page's content.
    let width: CGFloat
    /// A LIST item the bottom bar's "ยังขาด" chip asked for; handled and cleared here.
    @Binding var request: String?
    /// Portrait: the picture on top and the right column below it, the page scrolling (landscape puts them side by side).
    var stacked = false
    @Environment(SurveyModel.self) var model

    /// What a tap on the picture does.
    enum Tool: Hashable { case mark(MarkKind), shape(ShapeKind) }
    enum Layer: CaseIterable, Hashable {
        case panels, cables, symbols, measure, grid
        var title: String { [.panels: "แผง", .cables: "แนวสายไฟ", .symbols: "สัญลักษณ์", .measure: "ระยะ", .grid: "กริด 5 ม."][self]! }
    }
    /// A symbol or shape whose editor is open.
    enum Editing: Identifiable, Hashable {
        case mark(UUID), shape(UUID)
        var id: Self { self }
    }
    struct Snapshot: Equatable, Sendable { let marks: [MapMark]; let shapes: [SiteShape]; let models: [SiteModel] }
    /// A building-model card being dragged onto the picture (full screen), at `at` in `fullSpace`.
    struct CardDrag: Equatable { let id: String; var at: CGPoint }

    @State var tool: Tool?
    @State var draft: [ShapePoint] = []
    /// Live end of a measure / crane line being dragged.
    @State var dragEnd: ShapePoint?
    @State var editing: Editing?
    @State var anchor: CGPoint = .zero
    @State var history = UndoStack<Snapshot>()
    @State var layers: Set<Layer> = Set(Layer.allCases)
    @State var showLayers = false
    @State var fetchingMap = false
    @State var failure: String?
    @State var pickDrone = false
    @State var droneItem: PhotosPickerItem?
    @State var pickSign = false
    @State var signItem: PhotosPickerItem?
    @State var cameraSign = false
    @State var chooseLand = false
    @State var realLength = ""
    @State var draggingMark: UUID?
    /// Building model picked on the picture or in the panel (v2 §5).
    @State var selectedModel: String?
    /// A model being dragged on the picture, with the grab offset from its centre (fractions); one undo step per drag.
    @State var modelGrab: (id: String, dx: Double, dy: Double)?
    @State var cardDrag: CardDrag?
    @State var fullScreen = false
    /// Full-screen zoom and pan; the card always shows the whole picture.
    @State var zoom: CGFloat = 1
    @State var zoomStart: CGFloat?
    @State var pan: CGSize = .zero
    @State var panStart: CGSize?
    /// The full-screen picture's frame in `fullSpace`, for dropping cards.
    @State var fullFrame: CGRect = .zero

    /// Picture card 860 of 1318 (v2 §1); the right column fills the rest.
    var pictureWidth: CGFloat { (width - 24) * 860 / 1294 }

    var body: some View {
        VStack(spacing: 16) {
            PageStepBar(job: job, here: .site)
            if stacked {
                ScrollView {
                    VStack(spacing: 20) {
                        pictureCard.frame(height: max(320, width * 0.78))
                        rightColumn
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    pictureCard.frame(width: pictureWidth).frame(maxHeight: .infinity)
                    ScrollView { rightColumn.padding(.bottom, 4) }
                        .scrollIndicators(.hidden)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .foregroundStyle(Home.navy)
        .onAppear { tickFromCover() }
        #if DEBUG
        // `-surveyA2 layers|fullscreen` opens the layers menu or full screen (with the first placed model selected) for simulator checks
        .task {
            switch UserDefaults.standard.string(forKey: "surveyA2") {
            case "layers"?: showLayers = true
            case "fullscreen"?: selectedModel = models.first?.id; fullScreen = true
            default: break
            }
        }
        #endif
        .onChange(of: request) { _, item in if let item { handle(item); request = nil } }
        .photosPicker(isPresented: $pickDrone, selection: $droneItem, matching: .images)
        .onChange(of: droneItem) { _, item in load(item) { img in setPicture(img, source: "drone") }; droneItem = nil }
        .photosPicker(isPresented: $pickSign, selection: $signItem, matching: .images)
        .onChange(of: signItem) { _, item in load(item) { img in setSignPhoto(img) }; signItem = nil }
        .fullScreenCover(isPresented: $cameraSign) {
            CameraPicker { img in if let img { setSignPhoto(img) } }.ignoresSafeArea()
        }
        .confirmationDialog("ประเภทที่ดิน", isPresented: $chooseLand, titleVisibility: .visible) {
            ForEach(Options.landType, id: \.self) { o in Button(o) { setLand(o) } }
        }
        .errorAlert($failure)
        .fullScreenCover(isPresented: $fullScreen, onDismiss: { zoom = 1; pan = .zero; cardDrag = nil }) {
            fullScreenView.environment(model)
        }
    }

    // MARK: values

    var marks: [MapMark] { job.values.marks("siteMarks") }
    var shapes: [SiteShape] { job.values.shapes(SiteShapes.key) }
    var models: [SiteModel] { SiteModels.models(job.values) }
    /// The toolbar's "ล็อก": every building model stays where it is.
    var allLocked: Bool { SiteModels.allLocked(job.values) }
    func isLocked(_ m: SiteModel) -> Bool { allLocked || m.locked }
    var list: [String] { job.values.multi("siteList") }
    var photo: Photo? { job.values.photo("siteMap") }
    var source: String { job.values.text(SiteShapes.sourceKey) }
    /// Metres across the picture's width; nil until known (map zoom, or a drone photo measured once).
    var metersAcross: Double? { job.values.number(SiteShapes.scaleKey).flatMap { $0 > 0 ? $0 : nil } }

    func setMarks(_ a: [MapMark]) { job.values["siteMarks"] = a.isEmpty ? nil : .marks(a) }
    func setShapes(_ a: [SiteShape]) { job.values[SiteShapes.key] = a.isEmpty ? nil : .shapes(a) }
    func setModels(_ a: [SiteModel]) { SiteModels.setModels(a, in: &job.values) }
    func setList(_ a: [String]) { job.values["siteList"] = a.isEmpty ? nil : .multi(Options.list.filter(a.contains)) }

    var snapshot: Snapshot { Snapshot(marks: marks, shapes: shapes, models: models) }
    func restore(_ s: Snapshot) {
        setMarks(s.marks); setShapes(s.shapes); setModels(s.models)
    }

    /// Changes symbols / shapes with an undo step (and drops what could be redone).
    func change(_ body: (inout [MapMark], inout [SiteShape]) -> Void) {
        var m = marks, s = shapes
        history.record(snapshot)
        body(&m, &s)
        if m != marks { setMarks(m) }
        if s != shapes { setShapes(s) }
    }

    /// Changes the building models with an undo step.
    func changeModels(_ body: (inout [SiteModel]) -> Void) {
        var a = models
        history.record(snapshot)
        body(&a)
        if a != models { setModels(a) }
    }

    var canUndo: Bool { history.canUndo || !draft.isEmpty }
    func undo() {
        if !draft.isEmpty { draft.removeLast(); return }
        guard let last = history.undo(snapshot) else { return }
        editing = nil
        restore(last)
    }
    func redo() {
        guard draft.isEmpty, let next = history.redo(snapshot) else { return }
        editing = nil
        restore(next)
    }

    /// Ticks a LIST item because something on the page now shows it; the engineer can still untick it.
    func tick(_ item: String?) {
        guard let item, !list.contains(item) else { return }
        setList(list + [item])
    }

    /// GPS and address come from A1: tick them the first time A2 opens with them filled.
    func tickFromCover() {
        let seenKey = "siteListAuto"
        var seen = Set(job.values.text(seenKey).split(separator: "|").map(String.init))
        for (field, item) in [("gps", Options.list[10]), ("address", Options.list[11])] where !seen.contains(item) {
            guard !job.values.text(field).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            tick(item); seen.insert(item)
        }
        let s = seen.sorted().joined(separator: "|")
        if s != job.values.text(seenKey) { job.values[seenKey] = s.isEmpty ? nil : .text(s) }
    }

    // MARK: picture source

    func load(_ item: PhotosPickerItem?, _ done: @escaping (UIImage) -> Void) {
        guard let item else { return }
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { done(img) }
        }
    }

    func setPicture(_ img: UIImage, source: String) {
        guard let p = model.addPhoto(img, to: job.id, maxSide: 2400) else { failure = "บันทึกภาพไม่ได้"; return }
        job.values["siteMap"] = .photo(p)
        job.values[SiteShapes.sourceKey] = .text(source)
        // a new drone photo has an unknown scale until it is measured
        if source == "drone" { job.values[SiteShapes.scaleKey] = nil }
    }

    func fetchGoogle() {
        let gps = job.values.text("gps")
        guard let c = MapImage.coordinate(from: gps) else { failure = "ใส่พิกัด GPS ในหน้า A1 ก่อน แล้วจึงดึงภาพดาวเทียม"; return }
        let zoom = Int(job.values.text("mapZoom")) ?? model.settings.mapZoom
        fetchingMap = true
        Task { @MainActor in
            defer { fetchingMap = false }
            do {
                let p = try await model.mapPhoto(gps: gps, for: job.id)
                job.values["siteMap"] = .photo(p)
                job.values[SiteShapes.sourceKey] = .text("google")
                // the picture is cut to the A1 report frame, so it spans that share of the map's width
                let share = (MapCrop(job.values.text(MapCrop.key))?.w ?? 100) / 100
                job.values[SiteShapes.scaleKey] = .text(String(format: "%.2f", MapImage.metersAcross(lat: c.latitude, zoom: zoom) * share))
            } catch { failure = error.localizedDescription }
        }
    }

    func setSignPhoto(_ img: UIImage) {
        guard let p = model.addPhoto(img, to: job.id) else { return }
        job.values["projectSignPhoto"] = .photo(p)
        tick(Options.list[9])
    }

    func setLand(_ o: String) {
        job.values["landType"] = .choice(o, other: "")
        tick(Options.list[12])
    }

    // MARK: LIST shortcuts

    /// What a LIST item's shortcut does: arm the symbol / shape that shows it, take the sign photo, or pick the land type.
    func handle(_ item: String) {
        if let k = MarkKind.palette.first(where: { $0.listItem == item }) { arm(.mark(k)) }
        else if let k = ShapeKind.allCases.first(where: { $0.listItem == item }) { arm(.shape(k)) }
        else if item == Options.list[9] { takeSignPhoto() }
        else if item == Options.list[12] { chooseLand = true }
    }

    func takeSignPhoto() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) { cameraSign = true } else { pickSign = true }
    }

    func arm(_ t: Tool?) {
        editing = nil
        draft = []; dragEnd = nil
        showLayers = false
        if t != nil { selectedModel = nil }
        tool = tool == t ? nil : t
    }

    /// LIST items not ticked yet, with the bottom bar's short names.
    static func gaps(_ job: Job) -> [(item: String, title: String)] {
        let short: [String: String] = [Options.list[0]: "พื้นที่แผง", Options.list[1]: "ห้องอินเวอร์เตอร์", Options.list[2]: "Site Office",
                                       Options.list[3]: "กันย้อน", Options.list[4]: "บันได", Options.list[5]: "แนวสายไฟ",
                                       Options.list[6]: "ตู้ SMDB", Options.list[7]: "มิเตอร์ PEA", Options.list[8]: "หม้อแปลง",
                                       Options.list[9]: "รูปป้ายโครงการ", Options.list[10]: "GPS", Options.list[11]: "ที่อยู่",
                                       Options.list[12]: "ประเภทที่ดิน"]
        let ticked = job.values.multi("siteList")
        return Options.list.filter { !ticked.contains($0) }.map { ($0, short[$0] ?? $0) }
    }

    // MARK: right column

    var rightColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourceSection
            paletteSection
            listSection
            noteSection
        }
    }

    func heading(_ title: String, required: Bool = false, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 17, weight: .bold)).lineLimit(1).layoutPriority(1)
            if required { Text("*").font(.system(size: 17, weight: .bold)).foregroundStyle(Home.danger) }
            Spacer(minLength: 8)
            Text(trailing).font(.system(size: 12)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("ภาพมุมสูง", required: true, trailing: "เลือก 1 แหล่ง")
            // one above the other on an iPhone
            let narrow = width < 600
            let stack = narrow ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
            stack {
                sourceButton("Google Maps", "ภาพดาวเทียมตามพิกัด A1", icon: "source-google", symbol: "map", on: source == "google") { fetchGoogle() }
                sourceButton("อัปโหลดภาพจากโดรน", "JPG ภาพมุมตรง (Nadir)", icon: "source-drone", symbol: "camera.aperture", on: source == "drone") { pickDrone = true }
            }
        }
    }

    func sourceButton(_ title: String, _ detail: String, icon: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                A2Icon(name: icon, fallback: symbol).foregroundStyle(Home.primary).frame(width: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.85)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Home.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 48)
            .background(on ? Home.mint : Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Home.teal : Home.borderControl.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The 10 symbols, then the crane entrance and shade, which are drawn rather than placed.
    var paletteTools: [Tool] { MarkKind.palette.map(Tool.mark) + [.shape(.craneEntry), .shape(.shade)] }

    var paletteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("สัญลักษณ์บนภาพ", trailing: "แตะ แล้วแตะบนภาพเพื่อวาง")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: width < 600 ? 2 : 3), spacing: 8) {
                ForEach(paletteTools, id: \.self) { t in paletteButton(t) }
            }
        }
    }

    func placed(_ t: Tool) -> Bool {
        switch t {
        case .mark(let k): return marks.contains { $0.kind == k }
        case .shape(let k): return shapes.contains { $0.kind == k }
        }
    }

    func paletteButton(_ t: Tool) -> some View {
        let on = tool == t
        let (title, detail): (String, String) = {
            switch t {
            case .mark(let k): return (k.paletteTitle, k.paletteDetail)
            case .shape(.craneEntry): return ("ทางเข้าเครน", "ลูกศรทางเข้า")
            case .shape: return ("ร่มเงา", "สิ่งบดบังแสง")
            }
        }()
        return Button { arm(t) } label: {
            HStack(spacing: 6) {
                ToolIcon(tool: t).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Circle().fill(placed(t) ? Home.ok : Color.gray.opacity(0.35)).frame(width: 7, height: 7)
            }
            .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 44)
            .background(on ? Home.primarySoft : Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Home.primary : Home.borderControl.opacity(0.5), lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + " " + detail)
        .accessibilityValue(placed(t) ? "วางแล้ว" : "ยังไม่วาง")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    var listSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("LIST — รายการที่ระบุในภาพ", trailing: "ติ๊กอัตโนมัติเมื่อวาง")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 0) {
                ForEach(Options.list, id: \.self) { item in listRow(item) }
            }
            .padding(2)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.15)))
        }
    }

    func listRow(_ item: String) -> some View {
        let on = list.contains(item)
        return HStack(spacing: 8) {
            Button {
                setList(on ? list.filter { $0 != item } : list + [item])
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 19))
                        .foregroundStyle(on ? Home.primary : Home.pending).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    Text(item).font(.system(size: 12)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
            if !on { shortcut(item) }
        }
        .padding(.leading, 6)
        .background(on ? Color.clear : Home.pending.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder func shortcut(_ item: String) -> some View {
        if item == Options.list[12] {
            Menu {
                ForEach(Options.landType, id: \.self) { o in Button(o) { setLand(o) } }
            } label: { shortcutLabel("เลือก", icon: "action-chevronDown", symbol: "chevron.down") }
        } else if item == Options.list[9] {
            Button { takeSignPhoto() } label: { shortcutIcon("action-camera", symbol: "camera") }
                .buttonStyle(.plain).accessibilityLabel("ถ่ายรูป")
        } else if MarkKind.palette.contains(where: { $0.listItem == item }) || ShapeKind.allCases.contains(where: { $0.listItem == item }) {
            Button { handle(item) } label: { shortcutIcon("action-place", symbol: "mappin.and.ellipse") }
                .buttonStyle(.plain).accessibilityLabel("วางบนภาพ")
        }
    }

    /// v2: the place / photo shortcuts are icon-only 44 × 44.
    func shortcutIcon(_ icon: String, symbol: String) -> some View {
        A2Icon(name: icon, fallback: symbol, size: 18).foregroundStyle(Home.pending)
            .frame(width: 32, height: 30)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Home.pending.opacity(0.6)))
            // laid out 34 wide so the LIST text keeps its line; the touch target still reaches 44 × 44
            .frame(width: 34, height: 44).contentShape(Rectangle().inset(by: -5))
    }

    func shortcutLabel(_ title: String, icon: String?, symbol: String) -> some View {
        Label { Text(title) } icon: { A2Icon(name: icon, fallback: symbol, size: 16) }
            .font(.system(size: 12, weight: .bold)).foregroundStyle(Home.pending)
            .labelStyle(TightLabel()).fixedSize()
            .padding(.horizontal, 8).frame(minHeight: 30)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Home.pending.opacity(0.6)))
            .frame(minHeight: 44).contentShape(Rectangle())
    }

    var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("หมายเหตุหน้างาน", trailing: "ไม่บังคับ · ใต้ภาพในรายงาน")
            TextField("เช่น รถเครนเข้าทางถนนด้านตะวันออก · ต้นไม้บังแดดเช้า", text: Binding(
                get: { job.values.text("siteNote") },
                set: { job.values["siteNote"] = $0.isEmpty ? nil : .text($0) }), axis: .vertical)
                .lineLimit(1...2).font(.system(size: 15))
                .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.borderControl.opacity(0.6)))
        }
    }
}

/// Palette icon from the design's icon set; the retired water point (no icon) keeps its drawn symbol.
struct ToolIcon: View {
    let tool: SitePageWide.Tool
    var body: some View {
        switch tool {
        case .mark(let k) where A2Icon.has(k.assetName):
            k.icon(size: nil)
        case .mark(let k):
            Canvas { ctx, sz in
                let ops = SiteMarks.symbol(k, at: Pt(Double(sz.width) / 2, Double(sz.height) / 2), radius: Double(min(sz.width, sz.height)) / 2 - 1.5)
                ctx.withCGContext { cg in PDFRenderer.draw(ops, in: cg, photo: { _ in nil }) }
            }
        case .shape(let k):
            A2Icon(name: "shape-" + k.rawValue, fallback: k == .craneEntry ? "arrow.left" : "square.dashed", size: nil)
                .foregroundStyle(Color(red: k.color.r, green: k.color.g, blue: k.color.b))
        }
    }
}
#endif
