#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// A2's picture card: the site picture with symbols and drawings, the drawing toolbar, north arrow, layers and scale.
extension SitePageWide {
    static let stageSpace = "a2stage"
    static let norths = ["ด้านบน", "ด้านขวา", "ด้านล่าง", "ด้านซ้าย"]

    var pictureCard: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in stage(geo.size) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tool == nil ? Home.navy.opacity(0.15) : Home.primary, lineWidth: tool == nil ? 1 : 2))
            captionRow
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.2)))
    }

    // MARK: stage

    /// The picture fitted in `size`; symbols and drawings sit in the same rect.
    func imageRect(_ img: UIImage, in size: CGSize) -> CGRect {
        guard img.size.width > 0, img.size.height > 0, size.width > 0, size.height > 0 else { return .zero }
        let k = min(size.width / img.size.width, size.height / img.size.height)
        let w = img.size.width * k, h = img.size.height * k
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    @ViewBuilder func stage(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.91, green: 0.933, blue: 0.961)
            if let p = photo, let img = model.image(p, in: job.id) {
                let r = imageRect(img, in: size)
                Image(uiImage: img).resizable().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                drawing(r).allowsHitTesting(false)
                if layers.contains(.symbols) { markHandles(r) }
                Color.clear.frame(width: 1, height: 1).position(anchor)
                    .popover(item: $editing) { e in editor(e, rect: r).environment(model) }
                    .allowsHitTesting(false)
            } else if photo != nil {
                Label("ภาพนี้อยู่ในอีกเครื่อง ยังไม่ได้ดาวน์โหลด", systemImage: "icloud.and.arrow.down")
                    .font(.callout).foregroundStyle(Home.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .overlay(alignment: .topLeading) { if photo != nil { toolbar.padding(10) } }
        .overlay(alignment: .bottomLeading) { if photo != nil { layerBar.padding(10) } }
        .overlay(alignment: .bottomTrailing) { if photo != nil { scaleBar(size).padding(10) } }
        .overlay(alignment: .bottom) { if tool != nil { hintBar.padding(.bottom, 64) } }
    }

    var emptyPicture: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.badge.plus").font(.system(size: 34)).foregroundStyle(Home.muted)
            Text("เลือกภาพมุมสูงของสถานที่ติดตั้ง").font(.headline)
            HStack(spacing: 10) {
                Button { fetchGoogle() } label: { Label("Google Maps", systemImage: "map").frame(minHeight: 36) }.buttonStyle(.borderedProminent)
                Button { pickDrone = true } label: { Label("อัปโหลดภาพจากโดรน", systemImage: "photo").frame(minHeight: 36) }.buttonStyle(.bordered)
            }
        }
    }

    /// Shapes, the shape being drawn, symbols and the grid, drawn like the report does.
    func drawing(_ r: CGRect) -> some View {
        let box = Box(Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
        let visible = shapes.filter { s in
            switch s.kind {
            case .panelArea: return layers.contains(.panels)
            case .cableRoute: return layers.contains(.cables)
            case .measure: return layers.contains(.measure)
            case .craneEntry, .shade: return layers.contains(.symbols)
            case .boundary: return false
            }
        }
        return Canvas { ctx, _ in
            if layers.contains(.grid) {
                var p = Path()
                for i in 1..<10 {
                    let x = r.minX + r.width * CGFloat(i) / 10, y = r.minY + r.height * CGFloat(i) / 10
                    p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
                    p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
                }
                ctx.stroke(p, with: .color(.white.opacity(0.45)), lineWidth: 0.7)
            }
            var ops = SiteShapes.ops(visible, in: box, metersAcross: metersAcross)
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
                .overlay { if editing == .mark(m.id) { Circle().stroke(Color.yellow, lineWidth: 3).padding(4) } }
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
        anchor = p
        realLength = ""
        editing = e
    }

    func move(_ id: UUID, to p: CGPoint, in r: CGRect) {
        guard let f = fraction(p, in: r) else { return }
        if draggingMark != id {   // one undo step per drag
            draggingMark = id
            history.append(Snapshot(marks: marks, shapes: shapes))
        }
        var a = marks
        guard let i = a.firstIndex(where: { $0.id == id }) else { return }
        a[i].x = f.x; a[i].y = f.y
        setMarks(a)
    }

    // MARK: taps and drags on the picture

    func dragging(_ g: DragGesture.Value, in size: CGSize) {
        guard case .shape(let k)? = tool, k.fixedPoints == 2, let r = currentRect(size) else { return }
        // measure / crane entrance: press, drag, release
        if hypot(g.translation.width, g.translation.height) > 8, draft.isEmpty, let a = fraction(g.startLocation, in: r) {
            draft = [a]
        }
        if draft.count == 1, hypot(g.translation.width, g.translation.height) > 8 { dragEnd = fraction(g.location, in: r) }
    }

    func ended(_ g: DragGesture.Value, in size: CGSize) {
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
            if let s = shapeHit(p, in: r) { open(.shape(s.id), at: p) } else { editing = nil }
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

    // MARK: overlays

    var toolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                toolButton("วาดพื้นที่แผง", icon: "tool-panelArea", symbol: "pencil", .shape(.panelArea))
                toolButton("วาดแนวสายไฟ", icon: "tool-cableRoute", symbol: "point.topleft.down.to.point.bottomright.curvepath", .shape(.cableRoute))
                toolButton("วัดระยะ", icon: "tool-measure", symbol: "ruler", .shape(.measure))
                Button { undo() } label: { toolLabel("ย้อน", icon: nil, symbol: "arrow.uturn.backward", on: false) }
                    .buttonStyle(.plain).disabled(history.isEmpty && draft.isEmpty).opacity(history.isEmpty && draft.isEmpty ? 0.5 : 1)
            }
            northButton
        }
    }

    func toolButton(_ title: String, icon: String, symbol: String, _ t: Tool) -> some View {
        Button { arm(t) } label: { toolLabel(title, icon: icon, symbol: symbol, on: tool == t) }
            .buttonStyle(.plain).accessibilityAddTraits(tool == t ? .isSelected : [])
    }

    func toolLabel(_ title: String, icon: String?, symbol: String, on: Bool) -> some View {
        Label { Text(title) } icon: { A2Icon(name: icon, fallback: symbol, size: 20) }
            .font(.system(size: 14, weight: .bold)).labelStyle(TightLabel())
            .foregroundStyle(on ? Color.white : Home.navy)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(on ? Home.navy : Color.white, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }

    /// Where north is on the picture; each tap turns it a quarter and saves to `north`.
    var northButton: some View {
        let n = job.values.choice("north")
        let i = n.flatMap { Self.norths.firstIndex(of: $0) }
        return Button {
            let next = Self.norths[((i ?? -1) + 1) % 4]
            job.values["north"] = .choice(next, other: "")
        } label: {
            VStack(spacing: -2) {
                Image(systemName: "location.north.fill").font(.system(size: 18)).foregroundStyle(i == nil ? Home.muted : Home.danger)
                Text("N").font(.system(size: 11, weight: .heavy))
            }
            .rotationEffect(.degrees(Double(i ?? 0) * 90))
            .frame(width: 50, height: 50)
            .background(Color.white, in: Circle())
            .overlay(Circle().stroke(i == nil ? Home.pending : .clear, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ทิศเหนือของภาพ")
        .accessibilityValue(n ?? "ยังไม่ระบุ")
        .accessibilityHint("แตะเพื่อหมุนทีละ 90 องศา")
    }

    var layerBar: some View {
        HStack(spacing: 2) {
            Text("ชั้น").font(.system(size: 12)).foregroundStyle(Home.muted).padding(.horizontal, 6)
            ForEach(Layer.allCases, id: \.self) { l in
                let on = layers.contains(l)
                Button { if on { layers.remove(l) } else { layers.insert(l) } } label: {
                    Text(l.title).font(.system(size: 12, weight: .bold)).foregroundStyle(on ? Home.navy : Home.muted)
                        .strikethrough(!on)
                        .padding(.horizontal, 8).frame(minHeight: 44)
                        .background(on ? Home.primarySoft : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ชั้น " + l.title).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 3)
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }

    @ViewBuilder func scaleBar(_ size: CGSize) -> some View {
        if let m = metersAcross, let r = currentRect(size), r.width > 0 {
            let length = [1.0, 2, 5, 10, 20, 50, 100, 200, 500, 1000].last { $0 <= m * 0.22 } ?? 1
            let w = CGFloat(length / m) * r.width
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Rectangle().fill(Home.navy).frame(width: w / 2, height: 5)
                    Rectangle().fill(Color.white).frame(width: w / 2, height: 5).overlay(Rectangle().stroke(Home.navy, lineWidth: 1))
                }
                HStack(spacing: 0) {
                    Text("0").frame(width: w / 2, alignment: .leading)
                    Text(fmt(length / 2)).frame(width: w / 2, alignment: .leading)
                    Text(fmt(length) + " ม.")
                }
                .font(.system(size: 11, weight: .semibold)).monospacedDigit().fixedSize()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        } else if photo != nil {
            Button { arm(.shape(.measure)) } label: {
                Label("ตั้งมาตราส่วน", systemImage: "ruler").font(.system(size: 13, weight: .bold)).foregroundStyle(Home.pending)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityHint("วัดระยะที่รู้ความยาวจริงบนภาพ แล้วใส่ระยะจริง")
        }
    }

    func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    var hintBar: some View {
        let text: String = {
            switch tool {
            case .mark(let k)?: return "แตะบนภาพเพื่อวาง \(k.paletteTitle)"
            case .shape(.panelArea)?: return "แตะทีละมุม · แตะจุดแรกเพื่อปิดพื้นที่ (\(draft.count) จุด)"
            case .shape(.shade)?: return "แตะรอบสิ่งที่บังแดด · แตะจุดแรกเพื่อปิด (\(draft.count) จุด)"
            case .shape(.cableRoute)?: return "แตะตามแนวสาย แล้วกดเสร็จ (\(draft.count) จุด)"
            case .shape(.measure)?: return metersAcross == nil ? "ลากตามระยะที่รู้ความยาวจริง เพื่อตั้งมาตราส่วน" : "ลากหรือแตะ 2 จุดเพื่อวัดระยะ"
            case .shape(.craneEntry)?: return "ลากจากถนนเข้าหาจุดติดตั้ง"
            case .shape(.boundary)?, nil: return ""
            }
        }()
        return HStack(spacing: 10) {
            Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if case .shape(let k)? = tool, k.fixedPoints == nil {
                Button("เสร็จ") { finishDraft() }.font(.system(size: 14, weight: .bold))
                    .disabled(draft.count < k.minPoints)
                    .padding(.horizontal, 12).frame(minHeight: 36)
                    .background(Color.white.opacity(draft.count < k.minPoints ? 0.4 : 1), in: Capsule())
                    .foregroundStyle(Home.navy)
            }
            Button("ยกเลิก") { arm(nil) }.font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 12).frame(minHeight: 36)
                .overlay(Capsule().stroke(.white.opacity(0.7)))
                .foregroundStyle(.white)
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 4)
        .background(Home.navy.opacity(0.92), in: Capsule())
        .frame(minHeight: 44)
    }

    // MARK: caption

    var captionRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ภาพสถานที่ติดตั้ง").font(.system(size: 14, weight: .bold)).underline()
                Text(photoLine).font(.system(size: 12)).foregroundStyle(Home.muted)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            panelChip
            Menu {
                Button { fetchGoogle() } label: { Label("Google Maps ตามพิกัด A1", systemImage: "map") }
                Button { pickDrone = true } label: { Label("อัปโหลดภาพจากโดรน", systemImage: "photo") }
                if photo != nil {
                    Button(role: .destructive) { job.values["siteMap"] = nil; job.values[SiteShapes.sourceKey] = nil; job.values[SiteShapes.scaleKey] = nil } label: {
                        Label("ลบภาพ", systemImage: "trash")
                    }
                }
            } label: {
                Text(photo == nil ? "เลือกภาพ" : "เปลี่ยนภาพ").font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.5)))
            }
        }
    }

    /// "ภาพโดรน 29/9/2569 10:12"
    var photoLine: String {
        guard let p = photo else { return "ยังไม่มีภาพ" }
        let kind = source == "google" ? "ภาพดาวเทียม" : source == "drone" ? "ภาพโดรน" : "ภาพ"
        return kind + " " + ISODate.thai(ISODate.string(p.takenAt)) + " " + p.takenAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// Panels from the C sections (before − cut), for checking the drawn area; W/panel and kWp come later.
    var panelChip: some View {
        let n = job.modules.filter { $0.type == .roof || $0.type == .tank }.reduce(0.0) { sum, m in
            sum + max(0, (m.values.number("panelsBefore") ?? 0) - (m.values.number("panelsCut") ?? 0))
        }
        return HStack(spacing: 4) {
            Text("C1").foregroundStyle(Home.muted)
            Text(n > 0 ? "\(Int(n)) แผง" : "— แผง").bold()
            Text("× [W/แผง] = [kWp]").foregroundStyle(Home.muted)
        }
        .font(.system(size: 13)).lineLimit(1).fixedSize()
        .padding(.horizontal, 10).frame(minHeight: 36)
        .background(Home.primarySoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("หน้า C จำนวนแผง \(Int(n))")
    }

    // MARK: editors

    @ViewBuilder func editor(_ e: Editing, rect r: CGRect) -> some View {
        switch e {
        case .mark(let id): if let m = marks.first(where: { $0.id == id }) { markEditor(m) }
        case .shape(let id): if let s = shapes.first(where: { $0.id == id }) { shapeEditor(s, rect: r) }
        }
    }

    func markBinding(_ id: UUID, _ key: WritableKeyPath<MapMark, String>) -> Binding<String> {
        Binding(get: { marks.first { $0.id == id }?[keyPath: key] ?? "" },
                set: { v in var a = marks; if let i = a.firstIndex(where: { $0.id == id }) { a[i][keyPath: key] = v; setMarks(a) } })
    }

    func markEditor(_ m: MapMark) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(m.kind.paletteTitle).font(.headline)
                Spacer()
                if m.kind == .trafo || m.kind == .mdb {
                    Button("ดึงจาก A3") {
                        // the n-th transformer / MDB on the picture takes the n-th one's size from A3
                        let same = marks.filter { $0.kind == m.kind }
                        let before = Array(same.prefix(same.firstIndex { $0.id == m.id } ?? 0))
                        markBinding(m.id, \.value).wrappedValue = SiteMarks.suggestedValue(m.kind, existing: before, trafos: job.values.transformers("trafos"))
                    }
                    .font(.system(size: 13)).frame(minHeight: 44)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                editorField("ชื่อบนภาพ", text: markBinding(m.id, \.label), placeholder: SiteMarks.defaultLabel(m, in: marks))
                if let unit = m.kind.unit {
                    editorField("ขนาด", text: markBinding(m.id, \.value), placeholder: "0", unit: unit, numeric: true).frame(width: 130)
                }
            }
            editorButtons { change { a, _ in a.removeAll { $0.id == m.id } }; editing = nil }
        }
        .padding(16).frame(width: 340)
        .foregroundStyle(Home.navy)
    }

    func shapeEditor(_ s: SiteShape, rect r: CGRect) -> some View {
        let names: [ShapeKind: String] = [.panelArea: "พื้นที่ติดตั้งแผง", .cableRoute: "แนวสายไฟ", .measure: "วัดระยะ", .craneEntry: "ทางเข้าเครน", .shade: "ร่มเงา"]
        let aspect = r.height > 0 ? Double(r.width / r.height) : 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(names[s.kind] ?? "").font(.headline)
                Spacer()
                if s.kind == .measure, let m = metersAcross, let l = SiteShapes.length(s, aspect: aspect, metersAcross: m) {
                    Text(SiteShapes.meters(l)).font(.headline).monospacedDigit().foregroundStyle(Home.primary)
                }
            }
            if s.kind == .shade || s.kind == .craneEntry {
                editorField("ข้อความบนภาพ", text: Binding(
                    get: { shapes.first { $0.id == s.id }?.label ?? "" },
                    set: { v in var a = shapes; if let i = a.firstIndex(where: { $0.id == s.id }) { a[i].label = v; setShapes(a) } }),
                            placeholder: s.kind == .shade ? "เช่น ร่มเงาต้นไม้" : "ทางเข้าเครน")
            }
            if s.kind == .measure {
                editorField(metersAcross == nil ? "ระยะจริง (ตั้งมาตราส่วนของภาพ)" : "ระยะจริง (แก้มาตราส่วน)", text: $realLength, placeholder: "0", unit: "ม.", numeric: true)
            }
            editorButtons {
                change { _, a in a.removeAll { $0.id == s.id } }; editing = nil
            } done: {
                if s.kind == .measure, let real = NumberInput.value(realLength), real > 0,
                   let across = SiteShapes.length(s, aspect: aspect, metersAcross: 1), across > 0 {
                    job.values[SiteShapes.scaleKey] = .text(String(format: "%.2f", real / across))
                }
            }
        }
        .padding(16).frame(width: 340)
        .foregroundStyle(Home.navy)
    }

    func editorField(_ title: String, text: Binding<String>, placeholder: String, unit: String? = nil, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(Home.muted)
            HStack(spacing: 6) {
                TextField(placeholder, text: text).font(.system(size: 17, weight: .semibold))
                    .keyboardType(numeric ? .decimalPad : .default)
                if let unit { Text(unit).font(.system(size: 14)).foregroundStyle(Home.muted) }
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Home.borderControl.opacity(0.7)))
        }
    }

    func editorButtons(delete: @escaping () -> Void, done: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 10) {
            Button(role: .destructive, action: delete) {
                Text("ลบ").font(.system(size: 16, weight: .semibold)).foregroundStyle(Home.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.danger))
            }
            Button { done(); editing = nil } label: {
                Text("เสร็จ").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Home.primary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
