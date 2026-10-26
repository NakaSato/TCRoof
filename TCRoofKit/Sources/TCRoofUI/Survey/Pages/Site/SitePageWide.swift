#if canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import TCRoofCore
import PDFReport

/// A2 on iPad in landscape (docs/ui/survey-a2, layout v3 in docs/ui/survey-a2-ipad-v3): the symbol rail, the site picture
/// with drawing tools, then the side column of picture source, LIST and site note. Portrait stacks the picture over the
/// sections (the palette as a grid card); the iPhone has its own bands (`phoneBody`).
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
    /// iPhone: `phoneBody` (bands; the picture is edited full screen) in place of the picture card.
    @Environment(\.horizontalSizeClass) var sizeClass
    var isPhone: Bool { sizeClass == .compact }

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
    /// The A2 DXF being shared.
    @State var dxfFile: SurveyModel.ExportFile?
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
    /// Full screen: the building list is open (under the picture on iPhone; floating on the right on iPad, closed
    /// each time full screen opens there).
    @State var panelOpen = true
    /// iPad landscape: `LIST ในภาพ` is open in the side column.
    @State var listOpen = false
    @FocusState var noteFocused: Bool
    /// Full-screen zoom and pan; the card always shows the whole picture.
    @State var zoom: CGFloat = 1
    @State var zoomStart: CGFloat?
    @State var pan: CGSize = .zero
    @State var panStart: CGSize?
    /// The full-screen picture's frame in `fullSpace`, for dropping cards.
    @State var fullFrame: CGRect = .zero

    /// Picture card 860 of 1318 (v2 §1). v3: the rail (104), the picture and the side column with gaps of 12, so the
    /// picture keeps its width and the side column takes the rest (330 at 1366).
    var pictureWidth: CGFloat { (width - 24) * 860 / 1294 }
    /// iPad landscape: the symbol rail and the side column (v3); portrait keeps the right column under the picture.
    var railLayout: Bool { !isPhone && !stacked }

    var body: some View {
        Group {
            if isPhone { phoneBody } else { padBody }
        }
        .foregroundStyle(Theme.navy)
        .onAppear { tickFromCover() }
        #if DEBUG
        // `-surveyA2 layers|fullscreen` opens the layers menu or full screen (with the first placed model selected and the
        // building panel open) for simulator checks; `rail|armed|listopen|fullpanel` are docs/ui/survey-a2-ipad-v3's
        // states 01, 02 (Site Office armed), 04 (LIST open) and 06 (full screen with the panel open)
        .task {
            switch UserDefaults.standard.string(forKey: "surveyA2") {
            case "layers"?: showLayers = true
            case "fullscreen"?: selectedModel = models.first?.id; await openFull(panel: true)
            case "fullpanel"?: await openFull(panel: true)
            case "rail"?: tool = nil; listOpen = false
            case "armed"?: try? await Task.sleep(nanoseconds: 600_000_000); arm(.mark(.office))
            case "listopen"?: listOpen = true
            // `trafo|zero` opens that symbol's editor (docs/ui/a2-a3-autofill states 01 / 02)
            case let k? where k == "trafo" || k == "zero":
                try? await Task.sleep(nanoseconds: 800_000_000)
                if let m = marks.first(where: { $0.kind == (k == "zero" ? .zeroExport : .trafo) }) { open(.mark(m.id), at: CGPoint(x: 420, y: 300)) }
            default: break
            }
        }
        #endif
        .onChange(of: request) { _, item in if let item { handle(item); request = nil } }
        // iPad: full screen opens with the building panel closed (the iPhone keeps its own default)
        .onChange(of: fullScreen) { _, on in if on, !isPhone { panelOpen = false } }
        .photosPicker(isPresented: $pickDrone, selection: $droneItem, matching: .images)
        .onChange(of: droneItem) { _, item in load(item) { img in setPicture(img, source: "drone") }; droneItem = nil }
        .photosPicker(isPresented: $pickSign, selection: $signItem, matching: .images)
        .onChange(of: signItem) { _, item in load(item) { img in setSignPhoto(img) }; signItem = nil }
        .fullScreenCover(isPresented: $cameraSign) {
            CheckedCamera { img in if let img { setSignPhoto(img) } }
        }
        .confirmationDialog("ประเภทที่ดิน", isPresented: $chooseLand, titleVisibility: .visible) {
            ForEach(Options.landType, id: \.self) { o in Button(o) { setLand(o) } }
        }
        .errorAlert($failure)
        .sheet(item: $dxfFile) { f in ShareSheet(items: [f.url]).presentationDetents([.medium, .large]) }
        .fullScreenCover(isPresented: $fullScreen, onDismiss: { zoom = 1; pan = .zero; cardDrag = nil }) {
            fullScreenView.environment(model)
        }
    }

    var padBody: some View {
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
                HStack(alignment: .top, spacing: 12) {
                    symbolRail
                    pictureCard.frame(width: pictureWidth).frame(maxHeight: .infinity)
                    sideColumn.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    #if DEBUG
    /// Opens full screen, then the building panel once the iPad's closed default has been applied.
    func openFull(panel: Bool) async {
        fullScreen = true
        guard panel else { return }
        try? await Task.sleep(nanoseconds: 400_000_000)
        panelOpen = true
    }
    #endif

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

    /// Writes the symbols, then fills A3 / B4 from them (`SiteSync`; a deleted symbol leaves A3's data as it is).
    func setMarks(_ a: [MapMark]) {
        let before = marks
        job.values["siteMarks"] = a.isEmpty ? nil : .marks(a)
        SiteSync.push(&job, previous: before)
    }
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
        // iPhone: the picture is only drawn on full screen, so arming a symbol or shape opens it
        if isPhone, tool != nil, !fullScreen { fullScreen = true }
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

    /// Portrait: every section under the picture, the palette as a grid.
    var rightColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourceSection
            paletteSection
            listSection
            noteSection
        }
    }

    /// iPad landscape (v3): the side column's cards, in a column that fits the page (only an open LIST scrolls). Notes
    /// take the height left while LIST is closed.
    var sideColumn: some View {
        VStack(spacing: 12) {
            sideCard { sourceSection }
            listCard
            noteCard
        }
    }

    /// A white side-column card; `fill` stretches it to the height left.
    func sideCard<C: View>(fill: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
    }

    /// iPad: the section's title, then its hint on a line of its own (v3). iPhone: the band already has the title, so only the hint.
    @ViewBuilder func heading(_ title: String, required: Bool = false, trailing: String) -> some View {
        if isPhone {
            Text(trailing).font(.sarabunFixed(12)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title).font(.sarabunFixed(17, .bold)).lineLimit(1).minimumScaleFactor(0.85)
                    if required { Text("*").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.danger) }
                }
                Text(trailing).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("ภาพมุมสูง", required: true, trailing: "เลือก 1 แหล่ง")
            // one above the other on an iPhone and in the iPad's side column
            let narrow = width < 600 || railLayout
            let stack = narrow ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
            stack {
                sourceButton("แผนที่ดาวเทียม", "ภาพดาวเทียมตามพิกัด A1", icon: "source-google", symbol: "map", on: source == "google") { fetchGoogle() }
                sourceButton("อัปโหลดภาพจากโดรน", "JPG ภาพมุมตรง (Nadir)", icon: "source-drone", symbol: "camera.aperture", on: source == "drone") { pickDrone = true }
            }
        }
    }

    func sourceButton(_ title: String, _ detail: String, icon: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                A2Icon(name: icon, fallback: symbol).foregroundStyle(Theme.primary).frame(width: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.sarabunFixed(16, .bold)).lineLimit(1).minimumScaleFactor(0.85)
                    Text(detail).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 48)
            .background(on ? Theme.mint : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.teal : Theme.borderControl.opacity(0.6)))
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

    /// iPad landscape (v3): the palette as a slim rail left of the picture, one tile per row.
    var symbolRail: some View {
        VStack(spacing: 6) {
            VStack(spacing: 1) {
                Text("สัญลักษณ์").font(.sarabunFixed(14, .bold)).lineLimit(1)
                Text("แตะ แล้วแตะบนภาพ").font(.sarabunFixed(10.5)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 2)
            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
            ScrollView {
                VStack(spacing: 5) { ForEach(paletteTools, id: \.self) { t in paletteButton(t, rail: true) } }
                    .padding(2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .frame(width: 104)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
    }

    func paletteText(_ t: Tool) -> (title: String, detail: String) {
        switch t {
        case .mark(let k): return (k.paletteTitle, k.paletteDetail)
        case .shape(.craneEntry): return ("ทางเข้าเครน", "ลูกศรทางเข้า")
        case .shape: return ("ร่มเงา", "สิ่งบดบังแสง")
        }
    }

    /// A palette tile: a row with its detail line in the grid, or the rail's icon-over-title tile (`rail`). Both arm `t`.
    func paletteButton(_ t: Tool, rail: Bool = false) -> some View {
        let on = tool == t
        let text = paletteText(t)
        return Button { arm(t) } label: {
            if rail { railTile(t, title: text.title, on: on) } else { gridTile(t, title: text.title, detail: text.detail, on: on) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text.title + " " + text.detail)
        .accessibilityValue(placed(t) ? "วางแล้ว" : "ยังไม่วาง")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func gridTile(_ t: Tool, title: String, detail: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            ToolIcon(tool: t).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabunFixed(13, .bold)).lineLimit(1).minimumScaleFactor(0.75)
                Text(detail).font(.sarabunFixed(10.5)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            placedDot(t)
        }
        .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 44)
        .background(on ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.primary : Theme.borderControl.opacity(0.5), lineWidth: on ? 2 : 1))
    }

    /// The rail's tile (v3): the icon over the title, no detail line (VoiceOver keeps it), the placed dot in the corner.
    func railTile(_ t: Tool, title: String, on: Bool) -> some View {
        VStack(spacing: 4) {
            ToolIcon(tool: t).frame(width: 30, height: 30)
            Text(title).font(.sarabunFixed(11.5, .bold)).lineLimit(1).minimumScaleFactor(0.8).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 58)
        .overlay(alignment: .topTrailing) { placedDot(t).padding(6) }
        .background(on ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.primary : Theme.borderControl.opacity(0.5), lineWidth: on ? 2 : 1))
        .contentShape(Rectangle())
    }

    func placedDot(_ t: Tool) -> some View {
        Circle().fill(placed(t) ? Theme.success : Theme.progressZero).frame(width: 7, height: 7)
    }

    var listSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(isPhone ? "LIST — รายการที่ระบุในภาพ" : "LIST ในภาพ", trailing: "ติ๊กอัตโนมัติเมื่อวาง")
            listGrid
                .padding(2)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
        }
    }

    /// The LIST rows: one column on iPhone and in the iPad's side column, two in portrait.
    var listGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: isPhone || railLayout ? 1 : 2), alignment: .leading, spacing: 0) {
            ForEach(Options.list, id: \.self) { item in listRow(item) }
        }
    }

    /// iPad landscape (v3): `LIST ในภาพ` with its count chip, folded by default; open, its rows scroll in the height left.
    var listCard: some View {
        sideCard(fill: listOpen) {
            listHeader
            if listOpen {
                Text("ติ๊กอัตโนมัติเมื่อวาง").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).padding(.top, -6)
                ScrollView { listGrid }.scrollIndicators(.hidden)
            }
        }
    }

    var listHeader: some View {
        let chip = PhoneBand<EmptyView>.countChip(list.count, Options.list.count)
        return Button { withAnimation(.easeOut(duration: 0.15)) { listOpen.toggle() } } label: {
            HStack(spacing: 8) {
                Text("LIST ในภาพ").font(.sarabunFixed(17, .bold)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Text(chip.text).font(.sarabunFixed(12, .bold)).foregroundStyle(chip.fg).lineLimit(1).fixedSize()
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(chip.bg, in: Capsule())
                Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
                    .rotationEffect(.degrees(listOpen ? 180 : 0))
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("LIST ในภาพ \(chip.text)")
        .accessibilityValue(listOpen ? "แสดงอยู่" : "ซ่อนอยู่")
        .accessibilityHint("แตะเพื่อซ่อนหรือแสดงรายการ")
    }

    func listRow(_ item: String) -> some View {
        let on = list.contains(item)
        return HStack(spacing: 8) {
            Button {
                setList(on ? list.filter { $0 != item } : list + [item])
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 19))
                        .foregroundStyle(on ? Theme.primary : Theme.pending).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    Text(item).font(.sarabunFixed(12)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
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
        .background(on ? Color.clear : Theme.pending.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
        A2Icon(name: icon, fallback: symbol, size: 18).foregroundStyle(Theme.pending)
            .frame(width: 32, height: 30)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.pending.opacity(0.6)))
            // laid out 34 wide so the LIST text keeps its line; the touch target still reaches 44 × 44
            .frame(width: 34, height: 44).contentShape(Rectangle().inset(by: -5))
    }

    func shortcutLabel(_ title: String, icon: String?, symbol: String) -> some View {
        Label { Text(title) } icon: { A2Icon(name: icon, fallback: symbol, size: 16) }
            .font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.pending)
            .labelStyle(TightLabel()).fixedSize()
            .padding(.horizontal, 8).frame(minHeight: 30)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.pending.opacity(0.6)))
            .frame(minHeight: 44).contentShape(Rectangle())
    }

    var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("หมายเหตุหน้างาน", trailing: "ไม่บังคับ | ใต้ภาพในรายงาน")
            noteField(fill: false)
        }
    }

    /// iPad landscape (v3): the note fills the height left while LIST is closed, and is one or two lines while it is open.
    var noteCard: some View {
        sideCard(fill: !listOpen) {
            heading("หมายเหตุหน้างาน", trailing: "ไม่บังคับ | ใต้ภาพในรายงาน")
            noteField(fill: !listOpen)
        }
    }

    /// The site note; `fill` grows the box to the height left, where a tap anywhere starts typing.
    @ViewBuilder func noteField(fill: Bool) -> some View {
        let field = TextField("เช่น รถเครนเข้าทางถนนด้านตะวันออก | ต้นไม้บังแดดเช้า", text: Binding(
            get: { job.values.text("siteNote") },
            set: { job.values["siteNote"] = $0.isEmpty ? nil : .text($0) }), axis: .vertical)
            .font(.sarabunFixed(15))
            .padding(.horizontal, 14).padding(.vertical, 10)
        if fill {
            field.lineLimit(1...40)
                .focused($noteFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderControl.opacity(0.6)))
                .contentShape(Rectangle())
                .onTapGesture { noteFocused = true }
        } else {
            field.lineLimit(1...2).frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderControl.opacity(0.6)))
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
                .foregroundStyle(Color(k.color))
        }
    }
}
#endif
