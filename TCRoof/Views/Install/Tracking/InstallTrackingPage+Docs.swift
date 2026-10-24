import SwiftUI
import QuickLook
import TCRoofUI
import TCRoofCore
import ExcelExport

/// The iPad page's `เอกสาร` tab (docs/ui/install-tracking-ipad-docs): the summary card, the permit path
/// `เส้นทางขออนุญาต`, the selected package's papers and a detail panel. The papers open `StationDocsScreen`'s own sheet.
extension InstallTrackingPage {
    /// What the tab reads: the station's papers, the shared library and the station's facts (or the board's example).
    struct DocsSource {
        var station: StationDocs.Station
        var library: StationDocs.Library
        var ctx: StationDocs.Context
    }

    var docsSource: DocsSource {
        #if DEBUG
        if Debug.demo { return Self.demoDocs }
        #endif
        return DocsSource(station: job.stationDocs, library: docsLibrary, ctx: job.stationContext)
    }

    /// A contractor views what `stationdocs.drafts` lets them; nothing changes, so no upload or export.
    var docsReadOnly: Bool { !permissions.can(.stationDocsDrafts, on: job.access) }

    @ViewBuilder func docsTab() -> some View {
        if permissions.canView(.stationDocsDrafts, on: job.access) {
            let src = docsSource
            let steps = StationDocs.path(station: src.station, library: src.library, src.ctx)
            let selected = docsStage ?? StationDocs.defaultStep(steps)
            let step = steps.first { $0.package == selected } ?? steps[0]
            let kinds = step.applies ? StationDocs.papers(in: step.package, src.ctx) : []
            let paper = kinds.first { $0.id == docsPaper } ?? kinds.first
            VStack(alignment: .leading, spacing: 14) {
                docsSummary(StationDocs.pathSummary(station: src.station, library: src.library, src.ctx), step: step, src: src)
                docsPath(steps, selected: step.package)
                HStack(alignment: .top, spacing: 14) {
                    docsPapers(step, kinds, selected: paper, src: src)
                    docsDetail(paper, code: paper.flatMap { p in step.package.section.flatMap { sec in kinds.firstIndex(of: p).map { StationDocs.code(section: sec, index: $0) } } },
                               src: src).frame(width: 400)
                }
            }
            .onAppear { docsLibrary = StationDocsStore.loadLibrary() }
            .sheet(item: $docsSheet, onDismiss: { docsLibrary = StationDocsStore.loadLibrary() }) { kind in
                StationDocSheet(job: job, kind: kind, library: $docsLibrary)
            }
        } else {
            TCEmptyState("เอกสารสำหรับทีมภายใน", systemImage: "lock.doc", description: Text("เอกสารสถานี กปภ. ร่างและยื่นโดยทีมภายใน"))
                .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private func docsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: frame)
            .overlay(frame.strokeBorder(Theme.borderSubtle))
            .cardShadow()
    }

    static func legendInk(_ l: StationDocs.Legend) -> Color {
        switch l {
        case .todo: Theme.warning
        case .waiting: Theme.aiPurple
        case .done: Theme.success
        case .notYet: Theme.inkFaint
        }
    }

    static func legendTone(_ l: StationDocs.Legend) -> InstallPageData.Tone {
        switch l {
        case .todo: .warn
        case .waiting: .waiting
        case .done: .ok
        case .notYet: .idle
        }
    }

    // MARK: 4.1 summary

    private func docsSummary(_ s: StationDocs.PathSummary, step: StationDocs.PathStep, src: DocsSource) -> some View {
        let all = max(s.total + s.count(.notYet), 1)
        return docsCard {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("เอกสารโครงการ").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                        Button("ทุกสถานี ›") { openAllStations() }
                            .font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary).buttonStyle(.plain)
                            .frame(minHeight: 44).accessibilityIdentifier("docsAllStations")
                    }
                    Text("เอกสารขออนุญาตของสถานีนี้ | \(StationDocs.permitPath.count) หมวด | \(s.total) ฉบับ")
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                .frame(width: 300, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(s.done)").font(.sarabunFixed(24, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                        Text("/ \(s.total) ฉบับเรียบร้อย").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                        Spacer(minLength: 12)
                        legendRow(s)
                    }
                    GeometryReader { g in
                        HStack(spacing: 2) {
                            ForEach([StationDocs.Legend.done, .waiting, .todo, .notYet], id: \.self) { l in
                                if s.count(l) > 0 {
                                    Capsule().fill(Self.legendInk(l)).frame(width: max(4, g.size.width * CGFloat(s.count(l)) / CGFloat(all) - 2))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Capsule().fill(Theme.track))
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !docsReadOnly {
                    HStack(spacing: 10) {
                        TCButton("อัปโหลด", systemImage: "arrow.up.doc", kind: .secondary) { upload(step, src: src) }
                            .disabled(!step.applies)
                        TCButton("ส่งออกชุดเอกสาร", systemImage: "square.and.arrow.up", kind: .primary) { exportPackages(src) }
                            .accessibilityIdentifier("docsExport")
                    }
                    .fixedSize()
                }
            }
        }
    }

    private func legendRow(_ s: StationDocs.PathSummary) -> some View {
        HStack(spacing: 14) {
            ForEach(StationDocs.Legend.allCases, id: \.self) { l in
                HStack(spacing: 5) {
                    Circle().fill(Self.legendInk(l)).frame(width: 8, height: 8)
                    Text(l.title)
                    Text("\(s.count(l))").bold().foregroundStyle(Theme.navy).monospacedDigit()
                }
            }
        }
        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
    }

    // MARK: 4.2 path

    private func docsPath(_ steps: [StationDocs.PathStep], selected: StationDocs.Package) -> some View {
        docsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("เส้นทางขออนุญาต").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Text("ยื่นตามลำดับ | แตะเพื่อดูเอกสารในชุด").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                HStack(spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                        if i > 0 {
                            Image(systemName: "arrow.right").font(.system(size: 18, weight: .bold))
                                .foregroundStyle(steps[i - 1].cleared ? Theme.success : Theme.inkFaint)
                                .accessibilityHidden(true)
                        }
                        stepCard(step, on: step.package == selected)
                    }
                }
            }
        }
    }

    private func stepCard(_ s: StationDocs.PathStep, on: Bool) -> some View {
        let share = s.progress.total > 0 ? Double(s.progress.ready) / Double(s.progress.total) : 0
        let tone: InstallPageData.Tone = !s.applies ? .idle : s.progress.isComplete ? .ok : .info
        let frame = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button { docsStage = s.package; docsPaper = nil } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Theme.track, lineWidth: 5)
                    Circle().trim(from: 0, to: share)
                        .stroke(s.progress.isComplete ? Theme.success : Theme.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(s.applies ? "\(s.progress.ready)/\(s.progress.total)" : "–").font(.sarabunFixed(12, .bold))
                        .foregroundStyle(Theme.navy).monospacedDigit().minimumScaleFactor(0.7)
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ขั้น \(s.number) | \(s.agency)").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    Text(s.title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 8) {
                        chip(s.chip, tone).fixedSize()
                        Text(s.note).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(Theme.surface, in: frame)
            .overlay(frame.strokeBorder(on ? Theme.primary : Theme.borderSubtle, lineWidth: on ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ขั้น \(s.number) | \(s.title) | " + (s.applies ? "\(s.progress.ready) จาก \(s.progress.total)" : s.chip))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("docsStep.\(s.package.rawValue)")
    }

    // MARK: 4.3 papers

    private func docsPapers(_ step: StationDocs.PathStep, _ kinds: [StationDocs.Kind], selected: StationDocs.Kind?, src: DocsSource) -> some View {
        docsCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text([step.package.section, step.title].compactMap { $0 }.joined(separator: " "))
                            .font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                        Text(step.package.padNote).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("ร่าง → ยื่น → อนุมัติ").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    if !docsReadOnly && step.applies {
                        Button { upload(step, src: src) } label: {
                            Label("อัปโหลด", systemImage: "plus").font(.sarabunFixed(14, .bold))
                        }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card))
                    }
                }
                .padding(.bottom, 10)
                if kinds.isEmpty {
                    VStack(spacing: 4) {
                        Text("ชุดนี้ไม่ต้องยื่น").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                        Text(step.applies ? "ไม่มีเอกสารในชุดนี้" : "สถานีต่ำกว่า 200 kVA ไม่ต้องขอ พค.2")
                            .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("docsEmpty")
                } else {
                    ForEach(Array(kinds.enumerated()), id: \.element.id) { i, k in
                        paperRow(k, code: step.package.section.map { StationDocs.code(section: $0, index: i) },
                                 status: StationDocs.state(k, station: src.station, library: src.library).status, on: k.id == selected?.id)
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) } }
                    }
                }
            }
        }
    }

    private func paperRow(_ k: StationDocs.Kind, code: String?, status s: StationDocs.Status, on: Bool) -> some View {
        let legend = StationDocs.legend(s), level = StationDocs.flowLevel(s)
        return Button { docsPaper = k.id } label: {
            HStack(spacing: 12) {
                Text("PDF").font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 38, height: 46, alignment: .bottom).padding(.bottom, 4)
                    .background(Self.legendInk(legend), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    if let code { Text(code).font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.primary).monospacedDigit() }
                    Text(k.name).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text(StationDocs.source(k)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 6)
                flowDots(level)
                chip(s.title, Self.legendTone(legend)).fixedSize()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background {
                if on { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.primary, lineWidth: 2).padding(2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([code, k.name].compactMap { $0 }.joined(separator: " ") + " | " + s.title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("docsPaper.\(k.id)")
    }

    /// `ร่าง → ยื่น → อนุมัติ` as three joined checks, green up to the paper's level.
    private func flowDots(_ level: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                if i > 0 { Rectangle().fill(i < level ? Theme.success : Theme.track).frame(width: 12, height: 2) }
                ZStack {
                    Circle().fill(i < level ? Theme.success : Theme.track).frame(width: 20, height: 20)
                    if i < level { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.onPrimary) }
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: 4.4 detail

    @ViewBuilder private func docsDetail(_ k: StationDocs.Kind?, code: String?, src: DocsSource) -> some View {
        docsCard {
            if let k {
                let state = StationDocs.state(k, station: src.station, library: src.library)
                let level = StationDocs.flowLevel(state.status)
                VStack(alignment: .leading, spacing: 12) {
                    docsPreview(k, state: state)
                    VStack(alignment: .leading, spacing: 2) {
                        Text([code, state.status.title].compactMap { $0 }.joined(separator: " | ")).font(.sarabunFixed(13, .bold)).foregroundStyle(Self.ink(Self.legendTone(StationDocs.legend(state.status))))
                        Text(k.name).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("docsDetailTitle")
                        Text(StationDocs.source(k)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(Self.paperFlow.enumerated()), id: \.offset) { i, f in
                            flowStep(f.0, f.1, done: i < level, last: i == Self.paperFlow.count - 1)
                        }
                    }
                    HStack(spacing: 10) {
                        Button { docsSheet = k } label: {
                            Label("เปิดเอกสาร", systemImage: "doc.text.magnifyingglass").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
                        .accessibilityIdentifier("docsOpen")
                        if !docsReadOnly {
                            Button { docsSheet = k } label: {
                                Image(systemName: state.fileName == nil ? "arrow.up.doc" : "square.and.arrow.up")
                                    .font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                            }
                            .buttonStyle(TCButtonStyle(.secondary, size: .card))
                            .accessibilityLabel(state.fileName == nil ? "แนบไฟล์" : "แชร์ไฟล์")
                        }
                    }
                }
                .task(id: k.id + (state.fileName ?? "")) { await loadThumbnail(k, state: state) }
            } else {
                Text("เลือกเอกสารเพื่อดูรายละเอียด").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }

    /// The paper's way through: who drafts it, who hands it in, who approves.
    static let paperFlow: [(String, String)] = [("ร่าง / แนบไฟล์", "ทีมเรา"), ("ยื่น กปภ.", "ผู้ควบคุมงาน กปภ."), ("อนุมัติ", "กปภ.")]

    private func flowStep(_ title: String, _ who: String, done: Bool, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(done ? Theme.success : Theme.track).frame(width: 18, height: 18)
                    if done { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.onPrimary) }
                }
                if !last { Rectangle().fill(done ? Theme.success : Theme.track).frame(width: 2, height: 22) }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabunFixed(14, .bold)).foregroundStyle(done ? Theme.navy : Theme.inkMuted)
                Text(who).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "เสร็จแล้ว" : "ยังไม่ถึง")
    }

    /// The file's first page, or a drawn page while there is none.
    private func docsPreview(_ k: StationDocs.Kind, state: StationDocs.DocState) -> some View {
        let frame = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack {
            frame.fill(Theme.paper)
            if let img = docsThumbnail, state.fileName != nil {
                Image(uiImage: img).resizable().scaledToFit().padding(8)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.track).frame(width: 110, height: 9)
                    ForEach(0..<6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(Theme.hairline).frame(width: i % 3 == 2 ? 120 : 190, height: 6)
                    }
                    Text(state.fileName == nil ? "ยังไม่มีไฟล์" : "ไฟล์แนบ").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).padding(.top, 4)
                }
            }
        }
        .frame(height: 210)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
        .accessibilityHidden(true)
    }

    private func loadThumbnail(_ k: StationDocs.Kind, state: StationDocs.DocState) async {
        docsThumbnail = nil
        guard let url = fileURL(k, state: state) else { return }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 360, height: 400), scale: 2, representationTypes: .thumbnail)
        docsThumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
    }

    /// A paper's file: the library's for a shared paper, the job's documents (written to a temporary file) for its own.
    func fileURL(_ k: StationDocs.Kind, state: StationDocs.DocState) -> URL? {
        guard let name = state.fileName else { return nil }
        if k.scope.isShared { return StationDocsStore.fileURL(name) }
        guard let doc = job.documents.first(where: { $0.name == name }) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(doc.name)
        try? doc.data.write(to: url)
        return url
    }

    // MARK: actions

    /// The selected paper's sheet, where its file is attached (the first paper of the step when none is picked).
    private func upload(_ step: StationDocs.PathStep, src: DocsSource) {
        let kinds = StationDocs.papers(in: step.package, src.ctx)
        docsSheet = kinds.first { $0.id == docsPaper } ?? kinds.first
    }

    /// Every station's papers: the dock's `เอกสาร`, or the station's own papers outside the dock.
    private func openAllStations() {
        if let dock { dock.select(.docs) } else { route = .docs }
    }

    /// A ZIP of the path's packages, one folder per package (`4.2 ขนานไฟ (กฟภ.)/4.2-07 แผนผัง….pdf`), with the papers
    /// that have a file.
    private func exportPackages(_ src: DocsSource) {
        var zip = ZipArchive()
        for step in StationDocs.path(station: src.station, library: src.library, src.ctx) where step.applies {
            let folder = Self.safeName([step.package.section, step.title].compactMap { $0 }.joined(separator: " "))
            for (i, k) in StationDocs.papers(in: step.package, src.ctx).enumerated() {
                let state = StationDocs.state(k, station: src.station, library: src.library)
                guard let url = fileURL(k, state: state), let data = try? Data(contentsOf: url) else { continue }
                let code = step.package.section.map { StationDocs.code(section: $0, index: i) + " " } ?? ""
                zip.set(folder + "/" + Self.safeName(code + k.name) + "." + url.pathExtension, data)
            }
        }
        if zip.paths.isEmpty { docsNote = "ยังไม่มีไฟล์แนบในชุดเอกสาร"; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.safeName("เอกสารขออนุญาต \(job.code)") + ".zip")
        guard let data = try? zip.write(), (try? data.write(to: url)) != nil else { docsNote = "ส่งออกไม่สำเร็จ"; return }
        shared = Shared(url: url)
    }

    static func safeName(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
    }

    // MARK: demo

    #if DEBUG
    /// The board's example (`assets/sample-data.json`): a station under 200 kVA with every paper on the path approved;
    /// nothing is saved.
    static var demoDocs: DocsSource {
        var station = StationDocs.Station(over200kVA: false)
        var library = StationDocs.Library()
        let ctx = StationDocs.Context(station, inverterKW: 90)
        for p in StationDocs.permitPath.map(\.package) {
            for k in StationDocs.papers(in: p, ctx) {
                if k.scope.isShared { library.docs[k.id] = .init(status: .approved) } else { station.docs[k.id] = .init(status: .approved) }
            }
        }
        return DocsSource(station: station, library: library, ctx: ctx)
    }
    #endif
}
