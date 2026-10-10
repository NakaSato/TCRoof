#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport
import TCRoofUI

/// A2's picture card: the site picture with symbols, drawings and building models, the v2 toolbar, north arrow, layers and scale.
extension SitePageWide {
    static let stageSpace = "a2stage"
    static let norths = ["ด้านบน", "ด้านขวา", "ด้านล่าง", "ด้านซ้าย"]

    var pictureCard: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in picture(geo.size, full: false) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tool == nil ? Theme.navy.opacity(0.15) : Theme.primary, lineWidth: tool == nil ? 1 : 2))
            captionRow
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy.opacity(0.2)))
    }

    // MARK: picture

    /// The picture with its toolbar, north button, hint and scale; full screen adds pinch-to-zoom and pan.
    func picture(_ size: CGSize, full: Bool) -> some View {
        let z = full ? zoom : 1
        return stage(size, full: full)
            .scaleEffect(z)
            .offset(full ? pan : .zero)
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(magnify, including: full ? .all : .subviews)
            .simultaneousGesture(panning, including: full ? .all : .subviews)
            // iPhone and narrow cards: icon-only tools so the bar fits one line
            .overlay(alignment: .top) { if photo != nil { toolbar(full: full, narrow: size.width < 600).padding(8) } }
            .overlay(alignment: .topTrailing) { if photo != nil && showLayers { layersMenu.padding(.top, 54).padding(.trailing, 8) } }
            .overlay(alignment: .topLeading) { if photo != nil { northButton.padding(.leading, 10).padding(.top, 58) } }
            // narrow pictures: the hint sits above the scale button instead of under it
            .overlay(alignment: .bottomLeading) { if photo != nil { hintStack.padding(10).padding(.bottom, size.width < 600 ? 54 : 0) } }
            .overlay(alignment: .bottomTrailing) { if photo != nil { scaleBar(size, zoom: z).padding(10) } }
    }

    var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if zoomStart == nil { zoomStart = zoom }
                zoom = min(6, max(1, (zoomStart ?? 1) * v.magnification))
            }
            .onEnded { _ in
                zoomStart = nil
                if zoom < 1.02 { zoom = 1; pan = .zero }
            }
    }

    /// Full screen, zoomed in, Select tool: dragging the picture (not a symbol or model) moves it.
    var panning: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { g in
                guard zoom > 1, tool == nil, zoomStart == nil else { return }
                if panStart == nil { panStart = pan }
                guard modelGrab == nil, draggingMark == nil else { pan = panStart ?? pan; return }
                pan = CGSize(width: (panStart?.width ?? 0) + g.translation.width, height: (panStart?.height ?? 0) + g.translation.height)
            }
            .onEnded { _ in panStart = nil }
    }

    // MARK: stage

    /// The picture fitted in `size`; symbols and drawings sit in the same rect.
    func imageRect(_ img: UIImage, in size: CGSize) -> CGRect {
        guard img.size.width > 0, img.size.height > 0, size.width > 0, size.height > 0 else { return .zero }
        let k = min(size.width / img.size.width, size.height / img.size.height)
        let w = img.size.width * k, h = img.size.height * k
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    /// The picture, drawings and handles in unzoomed coordinates (`stageSpace`).
    @ViewBuilder func stage(_ size: CGSize, full: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.91, green: 0.933, blue: 0.961)
            if let p = photo, let img = model.image(p, in: job.id) {
                let r = imageRect(img, in: size)
                Image(uiImage: img).resizable().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                drawing(r).allowsHitTesting(false)
                if layers.contains(.symbols) { markHandles(r) }
                // only the copy on screen (card or full screen) carries the editor
                if full == fullScreen {
                    Color.clear.frame(width: 1, height: 1).position(anchor)
                        .popover(item: $editing) { e in editor(e, rect: r).environment(model) }
                        .allowsHitTesting(false)
                }
            } else if photo != nil {
                Label("ภาพนี้อยู่ในอีกเครื่อง ยังไม่ได้ดาวน์โหลด", systemImage: "icloud.and.arrow.down")
                    .font(.callout).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyPicture.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if fetchingMap { Color.black.opacity(0.3); ProgressView("กำลังดึงภาพดาวเทียม…").tint(.white).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .coordinateSpace(name: Self.stageSpace)
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.stageSpace))
            .onChanged { g in dragging(g, in: size) }
            .onEnded { g in ended(g, in: size) })
    }

    var emptyPicture: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.badge.plus").font(.system(size: 34)).foregroundStyle(Theme.inkMuted)
            Text("เลือกภาพมุมสูงของสถานที่ติดตั้ง").font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { emptyButtons }
                VStack(spacing: 10) { emptyButtons }
            }
        }
    }

    @ViewBuilder var emptyButtons: some View {
        Button { fetchGoogle() } label: { Label("แผนที่ดาวเทียม", systemImage: "map").frame(minHeight: 36) }.buttonStyle(.borderedProminent)
        Button { pickDrone = true } label: { Label("อัปโหลดภาพจากโดรน", systemImage: "photo").frame(minHeight: 36) }.buttonStyle(.bordered)
    }

    /// Grid, building models, shapes, the shape being drawn and symbols, drawn like the report does.
    func drawing(_ r: CGRect) -> some View {
        let box = Box(Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
        let visible = shapes.filter { s in
            switch s.kind {
            case .panelArea: return layers.contains(.panels)
            case .cableRoute: return layers.contains(.cables)
            case .measure: return layers.contains(.measure)
            case .craneEntry, .shade: return layers.contains(.symbols)
            case .boundary, .pvPoint: return false
            }
        }
        let placed = layers.contains(.symbols) ? placedModels : []
        return Canvas { ctx, _ in
            if layers.contains(.grid) { ctx.stroke(grid(r), with: .color(.white.opacity(0.45)), lineWidth: 0.7) }
            var ops: [DrawOp] = []
            if let m = metersAcross {
                for p in placed {
                    ops += SiteModels.ops(p.model, p.source, in: box, metersAcross: m, detailed: true,
                                          selected: p.model.id == selectedModel, locked: isLocked(p.model))
                }
            }
            ops += SiteShapes.ops(visible, in: box, metersAcross: metersAcross)
            if case .shape(let k)? = tool {
                let pts = draft + (dragEnd.map { [$0] } ?? [])
                if pts.count >= 2 { ops += SiteShapes.ops([SiteShape(kind: k, points: pts, label: k == .craneEntry ? "ทางเข้าเครน" : "")], in: box, metersAcross: metersAcross) }
            }
            if layers.contains(.symbols) { ops += SiteMarks.ops(marks, in: box) }
            ctx.withCGContext { cg in PDFRenderer.draw(ops, in: cg, photo: { _ in nil }) }
            // points tapped so far; the first is bigger when tapping it closes the area
            if case .shape(let k)? = tool {
                for (i, p) in draft.enumerated() {
                    let c = point(p, in: r), rad: CGFloat = i == 0 && k.isClosed ? 9 : 5
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad)), with: .color(.white))
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad)),
                               with: .color(Color(red: k.color.r, green: k.color.g, blue: k.color.b)), lineWidth: 2)
                }
            }
        }
    }

    /// "กริด 5 ม.": lines every 5 m once the scale is known (wider steps on a big picture), else tenths of the picture.
    func grid(_ r: CGRect) -> Path {
        var step = r.width / 10
        if let m = metersAcross {
            var meters = 5.0
            while m / meters > 60 { meters *= 2 }
            step = CGFloat(meters / m) * r.width
        }
        var p = Path()
        guard step > 2 else { return p }
        for x in stride(from: r.minX + step, to: r.maxX, by: step) { p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)) }
        for y in stride(from: r.minY + step, to: r.maxY, by: step) { p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)) }
        return p
    }

    func point(_ p: ShapePoint, in r: CGRect) -> CGPoint { CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height) }
    func fraction(_ p: CGPoint, in r: CGRect) -> ShapePoint? {
        guard r.width > 0, r.height > 0, r.insetBy(dx: -4, dy: -4).contains(p) else { return nil }
        return ShapePoint(Double((p.x - r.minX) / r.width), Double((p.y - r.minY) / r.height))
    }
    func currentRect(_ size: CGSize) -> CGRect? {
        guard let p = photo, let img = model.image(p, in: job.id) else { return nil }
        return imageRect(img, in: size)
    }

    /// 44-pt touch targets on every symbol: tap to edit, drag to move.
    func markHandles(_ r: CGRect) -> some View {
        ForEach(marks) { m in
            Circle().fill(Color.white.opacity(0.001))
                .overlay { if editing == .mark(m.id) { Circle().stroke(m.kind == .zeroExport ? Theme.warning : Color.yellow, lineWidth: 3).padding(4) } }
                .frame(width: 44, height: 44)
                .position(point(ShapePoint(m.x, m.y), in: r))
                .onTapGesture { open(.mark(m.id), at: point(ShapePoint(m.x, m.y), in: r)) }
                .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.stageSpace))
                    .onChanged { g in move(m.id, to: g.location, in: r) }
                    .onEnded { _ in draggingMark = nil })
                .accessibilityLabel(m.label.isEmpty ? m.kind.paletteTitle : m.label)
                .accessibilityHint("แตะเพื่อแก้ไข ลากเพื่อย้าย")
        }
    }

    func open(_ e: Editing, at p: CGPoint) {
        tool = nil; draft = []
        selectedModel = nil
        anchor = p
        realLength = ""
        editing = e
    }

    func move(_ id: UUID, to p: CGPoint, in r: CGRect) {
        guard let f = fraction(p, in: r) else { return }
        if draggingMark != id {   // one undo step per drag
            draggingMark = id
            history.record(snapshot)
        }
        var a = marks
        guard let i = a.firstIndex(where: { $0.id == id }) else { return }
        a[i].x = f.x; a[i].y = f.y
        setMarks(a)
    }

    // MARK: building models on the picture

    var placedModels: [(model: SiteModel, source: SiteModels.Source)] { SiteModels.placed(job) }

    /// The topmost model under `p` (symbols layer on, scale known).
    func modelHit(_ p: CGPoint, in r: CGRect) -> SiteModel? {
        guard layers.contains(.symbols), let m = metersAcross else { return nil }
        let box = Box(Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
        for q in placedModels.reversed() {
            guard let w = q.source.width, let l = q.source.length else { continue }
            let pts = SiteModels.corners(q.model, width: w, length: l, in: box, metersAcross: m).map { CGPoint(x: $0.x, y: $0.y) }
            if contains(pts, p) { return q.model }
        }
        return nil
    }

    /// Select tool: drags a model (unless locked) with one undo step.
    func dragModel(_ g: DragGesture.Value, in r: CGRect) {
        if modelGrab == nil {
            guard hypot(g.translation.width, g.translation.height) > 4, let m = modelHit(g.startLocation, in: r) else { return }
            selectedModel = m.id
            guard !isLocked(m) else { return }
            let start = ShapePoint(Double((g.startLocation.x - r.minX) / r.width), Double((g.startLocation.y - r.minY) / r.height))
            history.record(snapshot)
            modelGrab = (m.id, m.x - start.x, m.y - start.y)
        }
        guard let grab = modelGrab, r.width > 0, r.height > 0 else { return }
        var a = models
        guard let i = a.firstIndex(where: { $0.id == grab.id }) else { return }
        a[i].x = min(max(Double((g.location.x - r.minX) / r.width) + grab.dx, 0), 1)
        a[i].y = min(max(Double((g.location.y - r.minY) / r.height) + grab.dy, 0), 1)
        setModels(a)
    }

    // MARK: taps and drags on the picture

    func dragging(_ g: DragGesture.Value, in size: CGSize) {
        guard let r = currentRect(size) else { return }
        if tool == nil { return dragModel(g, in: r) }
        guard case .shape(let k)? = tool, k.fixedPoints == 2 else { return }
        // measure / crane entrance: press, drag, release
        if hypot(g.translation.width, g.translation.height) > 8, draft.isEmpty, let a = fraction(g.startLocation, in: r) {
            draft = [a]
        }
        if draft.count == 1, hypot(g.translation.width, g.translation.height) > 8 { dragEnd = fraction(g.location, in: r) }
    }

    func ended(_ g: DragGesture.Value, in size: CGSize) {
        showLayers = false
        if modelGrab != nil { modelGrab = nil; return }
        guard let r = currentRect(size) else { return }
        let isTap = hypot(g.translation.width, g.translation.height) <= 8
        if !isTap, let end = dragEnd, draft.count == 1, case .shape(let k)? = tool {
            dragEnd = nil
            anchor = g.location
            commit(SiteShape(kind: k, points: [draft[0], end]))
            return
        }
        dragEnd = nil
        guard isTap else { return }
        tap(g.location, in: r)
    }

    func tap(_ p: CGPoint, in r: CGRect) {
        switch tool {
        case .mark(let k)?:
            guard let f = fraction(p, in: r) else { return }
            var m = MapMark(kind: k, x: f.x, y: f.y, value: SiteMarks.suggestedValue(k, existing: marks, trafos: job.values.transformers("trafos")))
            if [.trafo, .mdb, .roofLabel].contains(k) { m.label = SiteMarks.defaultLabel(m, in: marks + [m]) }
            change { a, _ in a.append(m) }
            tick(k.listItem)
            tool = nil
            // name and rating are worth checking straight away
            if [.trafo, .mdb, .roofLabel].contains(k) { open(.mark(m.id), at: point(ShapePoint(m.x, m.y), in: r)) }
        case .shape(let k)?:
            guard let f = fraction(p, in: r) else { return }
            anchor = p   // the editor for a finished shape opens by the last tap
            if k.isClosed, draft.count >= k.minPoints, let first = draft.first,
               hypot(point(first, in: r).x - p.x, point(first, in: r).y - p.y) < 22 {
                return finishDraft()
            }
            draft.append(f)
            if let n = k.fixedPoints, draft.count >= n { finishDraft() }
        case nil:
            if let m = modelHit(p, in: r) { editing = nil; selectedModel = m.id }
            else if let s = shapeHit(p, in: r) { open(.shape(s.id), at: p) }
            else { editing = nil; selectedModel = nil }
        }
    }

    /// Ends the shape being drawn if it has enough points.
    func finishDraft() {
        guard case .shape(let k)? = tool, draft.count >= k.minPoints else { return }
        commit(SiteShape(kind: k, points: draft))
    }

    func commit(_ s: SiteShape) {
        var s = s
        if s.kind == .craneEntry { s.label = "ทางเข้าเครน" }
        change { _, a in a.append(s) }
        tick(s.kind.listItem)
        draft = []; tool = nil
        // a drone photo measured for the first time: ask for the real length to set the scale
        if s.kind == .measure && metersAcross == nil || s.kind == .shade { open(.shape(s.id), at: anchor) }
    }

    /// The shape under a tap: within 22 pt of one of its lines, or inside a closed area.
    func shapeHit(_ p: CGPoint, in r: CGRect) -> SiteShape? {
        for s in shapes.reversed() {
            let pts = s.points.map { point($0, in: r) }
            let segs = zip(pts, pts.dropFirst() + (s.kind.isClosed ? [pts[0]] : []))
            if segs.contains(where: { distance(p, $0, $1) < 22 }) { return s }
            if s.kind.isClosed && contains(pts, p) { return s }
        }
        return nil
    }

    func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy
        guard l2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    func contains(_ poly: [CGPoint], _ p: CGPoint) -> Bool {
        var inside = false
        for (a, b) in zip(poly, poly.dropFirst() + [poly[0]]) where (a.y > p.y) != (b.y > p.y) {
            if p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }
}
#endif
