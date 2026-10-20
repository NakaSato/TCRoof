#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// A3 (docs/ui/survey-a3): the power-flow diagram meter → transformers → boards, filled in place, on iPad and iPhone. Field ids are unchanged; the new answers are optional
/// (`Transformer.boards`, `meterKV` …), so A3's completion counts as before.
struct ElectricalPageWide: View {
    @Binding var job: Job
    /// Transformer a bottom-bar "ยังขาดภาพ" chip asked for; handled and cleared here.
    @Binding var request: Int?
    /// A breaker (or board) the single line diagram asked for: its transformer opens and the breaker sheet shows.
    @Binding var focus: SLTarget?
    /// Opens the single line diagram page.
    var openDiagram: () -> Void = {}
    /// iPhone: a two-line header, a smaller zoom panel and the diagram opened at 80 % to scroll around.
    var narrow = false
    @Environment(SurveyModel.self) var model

    /// One breaker being edited in the sheet.
    struct BreakerEdit: Identifiable { let id: UUID; let trafo: Int; let board: Int }

    @State var open = 0
    @State var scale: CGFloat = 0.66
    @State var pinchBase: CGFloat?
    @State var viewport: CGSize = .zero
    /// Transformer to scroll to; the canvas reads and clears it.
    @State var scrollTarget: Int?
    @State var moreMeter = false
    @State var confirmRemove: Int?
    @State var editBreaker: BreakerEdit?
    /// A board whose SLD busbar / ground is being edited (level 2, optional).
    @State var editBoardSLD: BoardSLDEdit?
    /// The `ดึงจากภาพ A2` panel.
    @State var showA2 = false
    @State var a2Cache = A2SyncCache()

    // MARK: layout (points at 100 %)

    static let top: CGFloat = 16, gap: CGFloat = 12
    static let meterX: CGFloat = 16, meterW: CGFloat = 220
    static let trunkX: CGFloat = 262
    static let trafoX: CGFloat = 290, trafoW: CGFloat = 460
    static let boardsX: CGFloat = 782
    static let expandedH: CGFloat = 640, collapsedH: CGFloat = 96
    static let mainW: CGFloat = 640, subW: CGFloat = 220, miniW: CGFloat = 176, addW: CGFloat = 96, boardGap: CGFloat = 28
    static let levels: [CGFloat] = [0.5, 0.6, 0.66, 0.8, 0.9, 1, 1.25, 1.5]

    var trafos: [Transformer] { job.values.transformers("trafos") }
    var openIndex: Int { min(open, max(trafos.count - 1, 0)) }
    func rowH(_ i: Int) -> CGFloat { i == openIndex ? Self.expandedH : Self.collapsedH }
    func rowY(_ i: Int) -> CGFloat { (0..<i).reduce(Self.top) { $0 + rowH($1) + Self.gap } }
    /// y of the line that leaves the transformer and its boards.
    func headerY(_ i: Int) -> CGFloat { rowY(i) + (i == openIndex ? 30 : Self.collapsedH / 2) }
    var addY: CGFloat { rowY(trafos.count) }
    var contentH: CGFloat { addY + 64 + Self.top }
    func boardsEnd(_ i: Int) -> CGFloat {
        let n = boards(i).count
        if i == openIndex { return Self.boardsX + Self.mainW + CGFloat(max(n - 1, 0)) * (Self.subW + Self.boardGap) + Self.boardGap + Self.addW }
        return Self.boardsX + CGFloat(max(n, 1)) * (Self.miniW + Self.boardGap) + Self.addW
    }
    var contentW: CGFloat { max(1720, (0..<trafos.count).map(boardsEnd).max() ?? 0) + Self.top }
    var meterH: CGFloat { moreMeter ? 560 : 400 }

    var body: some View {
        Group {
            if narrow {
                phoneBody
            } else {
                VStack(spacing: 16) {
                    PageStepBar(job: job, here: .electrical)
                    card.frame(maxHeight: .infinity)
                }
            }
        }
        .foregroundStyle(Theme.navy)
        // marks placed on A2 (or before links existed) fill this page's empty fields
        .onAppear { SiteSync.push(&job) }
        #if DEBUG
        // `-surveyA2Panel YES` opens the ดึงจากภาพ A2 panel for simulator checks
        .task { if UserDefaults.standard.bool(forKey: "surveyA2Panel") { try? await Task.sleep(nanoseconds: 600_000_000); showA2 = true } }
        #endif
        .onChange(of: request) { _, i in
            guard let i else { return }
            request = nil
            reveal(i)
        }
        .onChange(of: focus) { _, t in
            guard let t, let i = t.trafo else { return }
            focus = nil
            reveal(i)
            if let id = t.breaker, let k = t.board, boards(i)[safe: k]?.breakers.contains(where: { $0.id == id }) == true {
                editBreaker = BreakerEdit(id: id, trafo: i, board: k)
            }
        }
        .sheet(item: $editBreaker) { e in
            BreakerSheet(breaker: breakerBinding(e), isMain: e.board == 0,
                         onDelete: { removeBreaker(e); editBreaker = nil })
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $editBoardSLD) { e in
            BoardSLDSheet(board: boardSLDBinding(e)).presentationDetents([.medium])
        }
        .confirmationDialog("ลบหม้อแปลง TX \(( confirmRemove ?? 0) + 1)?", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                            titleVisibility: .visible) {
            Button("ลบ", role: .destructive) { if let i = confirmRemove { removeTrafo(i) }; confirmRemove = nil }
        } message: { Text("ข้อมูล ตู้ MDB และรูปภาพของหม้อแปลงนี้จะถูกลบ ลูกถัดไปเลื่อนขึ้นแทน") }
    }

    // MARK: card

    var card: some View {
        VStack(spacing: 0) {
            cardHeader
            GeometryReader { _ in
                canvas
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { s in
                        let first = viewport == .zero
                        viewport = s
                        // portrait is narrow: open readable (scrolling sideways) rather than at the whole-diagram fit
                        if first { fit(); if s.height > s.width { scale = max(scale, narrow ? 0.8 : 0.5) } }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(narrow ? 10 : 16)
        .tcCard()
    }

    @ViewBuilder var cardHeader: some View {
        if narrow {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("ผังการจ่ายไฟ").font(.sarabunFixed(19, .bold)).lineLimit(1)
                    Spacer(minLength: 4)
                    diagramButton
                }
                a2Button
            }
            .padding(.bottom, 8)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("ผังการจ่ายไฟ").font(.sarabunFixed(22, .bold))
                Text("กรอกทุกอย่างในผังนี้ · มิเตอร์ → หม้อแปลง → ตู้ MDB").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Spacer(minLength: 8)
                a2Button
                diagramButton
            }
            .padding(.bottom, 10)
        }
    }

    var diagramButton: some View {
        Button(action: openDiagram) {
            Text(narrow ? "Single Line →" : "สร้าง Single Line Diagram →").font(.sarabunFixed(narrow ? 15 : 16, .bold)).lineLimit(1)
                .foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, narrow ? 12 : 18).frame(minHeight: 44)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("สร้าง Single Line Diagram").accessibilityHint("เปิดแผนภาพเส้นเดียวที่สร้างจากข้อมูลสำรวจ")
    }

    // MARK: zoomable canvas

    var canvas: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                diagram
                    .frame(width: contentW, height: contentH, alignment: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: contentW * scale, height: contentH * scale, alignment: .topLeading)
                    // scaling doesn't change layout, so the scroll targets sit in the scaled frame
                    .overlay(alignment: .topLeading) {
                        ForEach(Array(trafos.indices), id: \.self) { i in
                            Color.clear.frame(width: 1, height: 1).offset(y: max(0, rowY(i) * scale - 8)).id(i)
                        }
                    }
            }
            .onChange(of: scrollTarget) { _, i in
                guard let i else { return }
                scrollTarget = nil
                withAnimation { proxy.scrollTo(i, anchor: .topLeading) }
            }
        }
        .background(Theme.phonePage)
        .simultaneousGesture(MagnifyGesture()
            .onChanged { v in
                let base = pinchBase ?? scale
                pinchBase = base
                scale = min(max(base * v.magnification, 0.4), 1.6)
            }
            .onEnded { _ in pinchBase = nil })
        .overlay(alignment: .bottomTrailing) { zoomPanel.padding(narrow ? 8 : 14) }
    }

    var zoomPanel: some View {
        HStack(spacing: 10) {
            if !narrow { Text("หนีบ 2 นิ้วเพื่อซูม · ลากเพื่อเลื่อน").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted) }
            HStack(spacing: 6) {
                zoomButton("minus", "ย่อ") { step(-1) }
                Text("\(Int((scale * 100).rounded()))%").font(.sarabunFixed(16, .bold)).frame(minWidth: 52)
                zoomButton("plus", "ขยาย") { step(1) }
                Button { withAnimation { fit() } } label: {
                    Text("พอดีจอ").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
    }

    func zoomButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    func step(_ d: Int) {
        let l = Self.levels
        let next = d > 0 ? l.first { $0 > scale + 0.005 } ?? l.last! : l.last { $0 < scale - 0.005 } ?? l.first!
        withAnimation { scale = next }
    }

    /// Whole diagram in the viewport, never above 100 %.
    func fit() {
        guard viewport.width > 0, viewport.height > 0 else { return }
        scale = min(1, viewport.width / contentW, viewport.height / contentH)
    }

    /// Opens transformer `i` and scrolls the diagram to it.
    func reveal(_ i: Int) {
        guard trafos.indices.contains(i) else { return }
        withAnimation { open = i }
        // after the rows above have their new heights
        DispatchQueue.main.async { scrollTarget = i }
    }

    // MARK: diagram

    var diagram: some View {
        ZStack(alignment: .topLeading) {
            connectors
            meterCard
                .frame(width: Self.meterW, height: meterH, alignment: .top)
                .offset(x: Self.meterX, y: meterY)
            ForEach(Array(trafos.indices), id: \.self) { i in
                transformerView(i)
                    .frame(width: Self.trafoW, height: rowH(i), alignment: .top)
                    .offset(x: Self.trafoX, y: rowY(i))
                boardsRow(i)
                    .offset(x: Self.boardsX, y: rowY(i))
            }
            addTransformerButton
                .frame(width: Self.trafoW, height: 64)
                .offset(x: Self.trafoX, y: addY)
        }
    }

    /// The meter sits at the middle of the transformers.
    var meterY: CGFloat {
        guard !trafos.isEmpty else { return Self.top }
        let mid = (headerY(0) + headerY(trafos.count - 1)) / 2
        return max(Self.top, mid - meterH / 2)
    }

    var connectors: some View {
        Canvas { ctx, _ in
            var p = Path()
            let my = meterY + 34, mx = Self.meterX + Self.meterW
            let ys = trafos.indices.map(headerY)
            p.move(to: CGPoint(x: mx, y: my)); p.addLine(to: CGPoint(x: Self.trunkX, y: my))
            if let a = ys.first, let b = ys.last {
                p.move(to: CGPoint(x: Self.trunkX, y: min(a, my))); p.addLine(to: CGPoint(x: Self.trunkX, y: max(b, my)))
            }
            for (i, y) in ys.enumerated() {
                p.move(to: CGPoint(x: Self.trunkX, y: y)); p.addLine(to: CGPoint(x: Self.trafoX, y: y))
                p.move(to: CGPoint(x: Self.trafoX + Self.trafoW, y: y)); p.addLine(to: CGPoint(x: boardsEnd(i) - Self.addW - Self.boardGap, y: y))
            }
            ctx.stroke(p, with: .color(Theme.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: contentW, height: contentH)
        .allowsHitTesting(false)
    }

    var addTransformerButton: some View {
        Group {
            if trafos.count < Transformer.maxTransformers {
                Button { add() } label: {
                    Label("เพิ่มหม้อแปลง", systemImage: "plus").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("ครบ 5 ลูกแล้ว (สูงสุด) · แตะหม้อแปลงเพื่อขยายมาแก้").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderControl.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
            }
        }
    }

    // MARK: data

    /// Writes the transformers, and the symbols linked to them on A2 take the new kVA / AT.
    func setTrafos(_ a: [Transformer]) {
        let before = job
        job.values["trafos"] = a.isEmpty ? nil : .transformers(a)
        SiteSync.pull(&job, since: before)
    }

    func edit(_ i: Int, _ body: (inout Transformer) -> Void) {
        var a = trafos
        guard a.indices.contains(i) else { return }
        body(&a[i])
        setTrafos(a)
    }

    /// Boards of transformer `i`; an older job's boards come from `mdb[]`, and there is always a main board to fill in.
    func boards(_ i: Int) -> [Board] {
        guard let t = trafos[safe: i] else { return [] }
        let b = t.resolvedBoards
        return b.isEmpty ? [Board(isMain: true)] : b
    }

    func editBoards(_ i: Int, _ body: (inout [Board]) -> Void) {
        edit(i) { t in
            var b = t.resolvedBoards
            if b.isEmpty { b = [Board(isMain: true)] }
            body(&b)
            t.setBoards(b)
        }
    }

    func add() {
        var a = trafos
        guard a.count < Transformer.maxTransformers else { return }
        a.append(Transformer())
        setTrafos(a)
        withAnimation { open = a.count - 1 }
        reveal(a.count - 1)
    }

    func removeTrafo(_ i: Int) {
        var a = trafos
        guard a.indices.contains(i) else { return }
        a.remove(at: i)
        job.values.shiftTransformerAnswers(removed: i)
        setTrafos(a)
        withAnimation { open = max(0, min(open > i ? open - 1 : open, a.count - 1)) }
    }

    func removeBreaker(_ e: BreakerEdit) {
        editBoards(e.trafo) { b in if b.indices.contains(e.board) { b[e.board].breakers.removeAll { $0.id == e.id } } }
    }

    func breakerBinding(_ e: BreakerEdit) -> Binding<Breaker> {
        Binding(get: { boards(e.trafo)[safe: e.board]?.breakers.first { $0.id == e.id } ?? Breaker() },
                set: { new in
                    editBoards(e.trafo) { b in
                        guard b.indices.contains(e.board), let k = b[e.board].breakers.firstIndex(where: { $0.id == e.id }) else { return }
                        b[e.board].breakers[k] = new
                    }
                })
    }

    func tText(_ i: Int, _ kp: WritableKeyPath<Transformer, String>, number: Bool = false) -> Binding<String> {
        Binding(get: { trafos[safe: i]?[keyPath: kp] ?? "" },
                set: { v in edit(i) { $0[keyPath: kp] = number ? NumberInput.clean(v) : v } })
    }
    func bText(_ i: Int, _ k: Int, _ kp: WritableKeyPath<Board, String>, number: Bool = false) -> Binding<String> {
        Binding(get: { boards(i)[safe: k]?[keyPath: kp] ?? "" },
                set: { v in editBoards(i) { b in if b.indices.contains(k) { b[k][keyPath: kp] = number ? NumberInput.clean(v) : v } } })
    }
    func vText(_ id: String) -> Binding<String> {
        Binding(get: { job.values.text(id) }, set: { job.values[id] = $0.isEmpty ? nil : .text($0) })
    }
    func vChoice(_ id: String) -> String { job.values.choice(id) ?? "" }
    func setChoice(_ id: String, _ v: String) { job.values[id] = v.isEmpty ? nil : .choice(v, other: "") }
    func photoBinding(_ key: String) -> Binding<Photo?> {
        Binding(get: { job.values.photo(key) }, set: { job.values[key] = $0.map { .photo($0) } })
    }

    // MARK: gaps for the bottom bar

    static let mainPhotoSlots: [(key: String, label: String)] = [("feedPhoto", "หน้าตู้ (ปิด)"), ("mdbOpen", "เปิดตู้ ภายใน"),
                                                                  ("mdbBreaker", "เมนเบรกเกอร์"), ("mdbSpace", "ที่ว่างติดตั้ง CB โซลาร์")]

    /// "TX 1 (1)" for a transformer short of photos and "MDP-1 (1)" for its main board; each opens that transformer.
    static func gaps(_ job: Job) -> [(index: Int, title: String)] {
        var out: [(Int, String)] = []
        for i in job.values.transformers("trafos").indices where Schema.transformerPresent(job.values, i) {
            let tx = Schema.transformerAngles.filter { job.values.photo("tr\(i)_\($0.key)") == nil }.count
            if tx > 0 { out.append((i, "TX \(i + 1) (\(tx))")) }
            let mb = mainPhotoSlots.filter { job.values.photo("tr\(i)_\($0.key)") == nil }.count
            if mb > 0 {
                let n = job.values.text("tr\(i)_feed").trimmingCharacters(in: .whitespaces)
                out.append((i, (n.isEmpty ? "ตู้หลัก TX \(i + 1)" : n) + " (\(mb))"))
            }
        }
        return out
    }
}
#endif
