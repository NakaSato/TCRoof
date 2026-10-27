#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// A `Sketch` drawn at a scale and offset (the plan and section of C1), with the report's renderer.
struct SketchCanvas: View {
    let ops: [DrawOp]
    let fit: SketchFit
    var body: some View {
        SketchDrawing(ops: ops, fit: fit).equatable()
            .background(Theme.paper)
    }
}

/// The drawing itself, drawn again only when its ops or fit change: the pages around it are rebuilt on every edit and
/// every drag frame, and drawing a plan's text and modules costs far more than comparing them.
private struct SketchDrawing: View, Equatable {
    let ops: [DrawOp]
    let fit: SketchFit
    var body: some View {
        Canvas { ctx, _ in
            ctx.withCGContext { cg in
                cg.translateBy(x: fit.ox, y: fit.oy)
                cg.scaleBy(x: fit.s, y: fit.s)
                PDFRenderer.draw(ops, in: cg, photo: { _ in nil })
            }
        }
    }
}

/// A sketch of `w` × `h` fitted and centred in `size`.
struct SketchFit: Equatable {
    let s, ox, oy: CGFloat
    init(_ w: Double, _ h: Double, in size: CGSize) {
        s = min(size.width / w, size.height / h)
        ox = (size.width - w * s) / 2; oy = (size.height - h * s) / 2
    }
    func point(_ p: Pt) -> CGPoint { CGPoint(x: ox + p.x * s, y: oy + p.y * s) }
    func sketch(_ p: CGPoint) -> Pt { Pt((p.x - ox) / s, (p.y - oy) / s) }
    func rect(_ b: Box) -> CGRect { CGRect(x: ox + b.x * s, y: oy + b.y * s, width: b.w * s, height: b.h * s) }
}

extension RoofPageWide {
    // MARK: plan card

    var planCard: some View {
        card {
            if narrow {
                // iPhone: the caption and the mode switch sit above the plan, so the switch stays put between the tabs
                planCaption.lineLimit(2)
                RoofSegments(options: ["โครงสร้าง", "จัดแผง"], selected: mode == .pv ? 1 : 0, minSegment: 100, height: 44) { i in setMode(i == 1 ? .pv : .structure) }
                planStage.frame(maxWidth: .infinity, maxHeight: .infinity)
                legendRow
            } else {
                HStack(alignment: .top, spacing: 6) {
                    planStage.frame(maxWidth: .infinity, maxHeight: .infinity)
                    legend.frame(width: 150)
                }
                .frame(maxHeight: .infinity)
            }
            Divider()
            planFooter
        }
        .photoSources(picker: $sketchPicker, camera: $sketchCamera) { img in
            if let p = model.addPhoto(img, to: job.id) { set("planPhoto", .photo(p)) }
        }
        .sheet(item: $viewingSketch) { p in if let img = model.image(p, in: job.id) { PhotoViewer(image: img, title: "แบบร่างหลังคา") } }
    }

    var planHint: String {
        if tool == .keepOut { return "ลากเพื่อวาดเขตห้ามติด" }
        if tool == .skylight { return "ลากเพื่อวาดแผ่นใส | แตะ × เพื่อลบ" }
        if case .obstacle(let k)? = tool { return "ลากเพื่อวาด" + k.title }
        if mode == .pv && editModules { return "แตะแผงเพื่อเอาออกหรือใส่กลับ" }
        if mode == .pv { return "แตะแผงหรือสิ่งกีดขวางเพื่อดูรายละเอียด" }
        if editPosts { return "แตะจุดตัดกริด เพิ่ม/ลบเสา" }
        if values.photo("planPhoto") != nil { return "รายงานใช้แบบร่างที่ถ่ายไว้" }
        if values.text(Roof.Key.spansX).isEmpty || values.text(Roof.Key.spansY).isEmpty { return "ระยะตัวอย่าง | แตะเลขสีฟ้าเพื่อแก้" }
        return "แตะเลขสีฟ้า/แผ่นใสเพื่อแก้"
    }

    @ViewBuilder var planFooter: some View {
        if narrow {
            // iPhone: the buttons (the caption and the switch are above the plan)
            if mode == .pv {
                mountPhoneFooter
            } else {
                HStack(spacing: 8) {
                    structureButtons
                    Spacer(minLength: 0)
                    cadButton
                }
            }
        } else {
            HStack(spacing: 8) {
                planCaption.lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RoofSegments(options: ["โครงสร้าง", "จัดแผง"], selected: mode == .pv ? 1 : 0) { i in setMode(i == 1 ? .pv : .structure) }
                    .frame(minWidth: 120, maxWidth: 150)
                if mode == .structure { structureButtons } else { mountButtons }
                cadButton
            }
        }
    }

    var planCaption: some View {
        (Text("แปลนโครงหลังคา").bold().underline() + Text(" | " + planHint).foregroundColor(mode == .pv && tool == nil ? Theme.navy : Theme.inkMuted)
            .fontWeight(mode == .pv && tool == nil ? .bold : .regular))
            .font(.sarabunFixed(14)).minimumScaleFactor(0.6)
    }

    var cadButton: some View { cadButton(fill: false) }

    func cadButton(fill: Bool) -> some View {
        footerButton("CAD", icon: "doc.badge.arrow.up", on: showCAD, fill: fill) { showCAD.toggle(); span = nil }
            .accessibilityLabel("ส่งออก CAD")
            .popover(isPresented: $showCAD, arrowEdge: .bottom) { cadSheet.presentationCompactAdaptation(.popover) }
    }

    /// iPhone: north and the symbols in two columns under the plan.
    var legendRow: some View {
        let north = job.values.choice("north"), turn = Double(SitePageWide.norths.firstIndex(of: north ?? "") ?? 0) * 90
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                NorthArrow(degrees: turn).frame(width: 32, height: 32)
                Text("ทิศเหนือ").font(.sarabunFixed(13, .bold))
                Text(north == nil ? "ยังไม่ระบุใน A2" : "ตามภาพ A2 | หมุน \(Int(turn))°").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 4) {
                ForEach(Array(legendItems.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        LegendGlyph(kind: item.0).frame(width: 24, height: 14)
                        Text(item.1).font(.sarabunFixed(12)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
            }
        }
    }

    // MARK: legend

    /// North from A2 (the picture's north, a quarter turn per step), then the symbols of the current mode.
    var legend: some View {
        let north = job.values.choice("north"), turn = Double(SitePageWide.norths.firstIndex(of: north ?? "") ?? 0) * 90
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                NorthArrow(degrees: turn).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text("ทิศเหนือ").font(.sarabunFixed(13, .bold))
                    Text(north == nil ? "ยังไม่ระบุใน A2" : "ตามภาพ A2 | หมุน \(Int(turn))°").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Self.line.frame(height: 1)
            Text("สัญลักษณ์").font(.sarabunFixed(13, .bold))
            ForEach(Array(legendItems.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    LegendGlyph(kind: item.0).frame(width: 24, height: 14)
                    Text(item.1).font(.sarabunFixed(12)).lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    var legendItems: [(LegendGlyph.Kind, String)] {
        if mode == .pv {
            // iPad: the shade card's moment on the plan (RoofPageWide+Shade)
            let shade: [(LegendGlyph.Kind, String)] = narrow ? [] : [(.shadedModule, "แผงที่โดนเงา 21 ธ.ค. 09:00"), (.obstacleShadow, "เงาสิ่งกีดขวาง")]
            // the 09:00–15:00 shade outline only shows while the layout avoids it; on iPad its row then reads apart from the
            // moment's
            let avoided: [(LegendGlyph.Kind, String)] = narrow ? [(.gap, "เงาสิ่งกีดขวาง")]
                : mountChoice.avoidShade ? [(.gap, "เว้นเงา 09:00–15:00")] : []
            return [(.pv, "แผงโซลาร์")] + shade + [(.blocked, "ด้านที่ไม่วาง / ตัดแผง"), (.keepOut, "เขตห้ามติด"), (.skyOK, "แผ่นใส")]
                + avoided + [(.purlin, "แป | ราง | L-foot"), (.ridge, "สันหลังคา")]
        }
        let f = Roof.frame(values), pp = "แป @" + String(format: "%.2f", Roof.purlinSpacing(values))
        let two: [(LegendGlyph.Kind, String)] = f.isRafter ? [(.heavy, "อเส"), (.thin, "จันทัน @1.00")]
            : f == .rafterTruss ? [(.heavy, "จันทันถัก T1"), (.dashedHeavy, "T2 รับจันทัน")] : [(.double, "โครงถัก T1"), (.purlin, pp)]
        return [(.post, "เสา")] + two + [(.skyOK, "แผ่นใส | วางทับได้"), (.skyNo, "แผ่นใส | ห้ามวางทับ"), (.ridge, "สันหลังคา"), (.section, "แนวรูปตัด A–A")]
    }

    func footerButton(_ title: String, icon: String? = nil, on: Bool = false, tint: Color = Theme.navy, fill: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .bold)) }
                Text(title).font(.sarabunFixed(14, .bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? Theme.onMedia : tint)
            .frame(maxWidth: fill ? .infinity : nil)
            .padding(.horizontal, 10).frame(minHeight: 44)
            .background(on ? tint : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Color.clear : tint.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder var structureButtons: some View {
        let n = Roof.posts(values).count
        footerButton(editPosts ? "เสร็จ | เสา \(n) ต้น" : "แก้เสา (\(n))", icon: editPosts ? nil : "square.fill", on: editPosts, tint: editPosts ? Theme.primary : Theme.navy) {
            editPosts.toggle(); tool = nil; span = nil
        }
        if let p = values.photo("planPhoto") {
            Menu {
                Button("ดูแบบร่าง") { viewingSketch = p }
                Button("ถ่ายใหม่") { sketchCamera = true }
                Button("อัปโหลดใหม่") { sketchPicker = true }
                Button("ลบแบบร่าง", role: .destructive) { set("planPhoto", nil) }
            } label: {
                Label("แบบร่าง ✓", systemImage: "doc.richtext").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.success)
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.success.opacity(0.6)))
            }
        } else {
            Menu {
                Button { sketchCamera = true } label: { Label("ถ่ายภาพ", systemImage: "camera") }
                Button { sketchPicker = true } label: { Label("อัปโหลด", systemImage: "photo") }
            } label: {
                Label("ถ่ายแบบร่าง", systemImage: "camera").font(.sarabunFixed(14, .bold))
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.5)))
            }
            .accessibilityHint("ภาพแบบร่างที่วาดเองจะใช้แทนแปลนอัตโนมัติในรายงาน")
        }
    }

    // MARK: plan stage

    var planStage: some View {
        GeometryReader { geo in
            let plan = RoofPlan(values, mode: mode, chips: true, dragging: drag, highlight: member,
                                mount: mode == .pv ? shownMount : nil, selected: selectedSlots, pairNumbers: true, shade: planShade)
            let fit = SketchFit(RoofPlan.width, RoofPlan.height, in: geo.size)
            ZStack(alignment: .topLeading) {
                SketchCanvas(ops: plan.sketch.ops, fit: fit)
                    .accessibilityLabel(String(format: "แปลนโครงหลังคา %.2f คูณ %.2f เมตร", plan.layout.lx, plan.layout.ly))
                if mode == .pv && tool == nil { mountTap(plan.layout, fit) }
                if narrow && mode == .pv { planTag.padding(8) }
                if tool != nil { drawSurface(plan.layout, fit) }
                areaButtons(plan.layout, fit)
                spanChips(plan.layout, fit)
                if editPosts && mode == .structure { postButtons(plan.layout, fit) }
                if mode == .structure && !editPosts { skylightTool.position(x: geo.size.width - 62, y: geo.size.height - 26) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .popover(isPresented: Binding(get: { span != nil }, set: { if !$0 { span = nil } }),
                     attachmentAnchor: .rect(.rect(chipRect(plan.layout, fit))), arrowEdge: span?.axis == .y ? .leading : .top) {
                spanEditor.presentationCompactAdaptation(.popover)
            }
        }
    }

    func chipRect(_ L: RoofPlan.Layout, _ fit: SketchFit) -> CGRect {
        guard let span, let c = L.chips.first(where: { $0.axis == span.axis && $0.index == span.index }) else { return .zero }
        let p = fit.point(c.at)
        return CGRect(x: p.x - 18, y: p.y - 12, width: 36, height: 24)
    }

    func spanChips(_ L: RoofPlan.Layout, _ fit: SketchFit) -> some View {
        let live = mode == .structure && !editPosts && tool == nil
        return ZStack(alignment: .topLeading) {
            ForEach(Array(L.chips.enumerated()), id: \.offset) { _, c in
                spanChip(c, fit: fit, live: live).position(fit.point(c.at))
            }
            if live {
                addButton(.x).position(fit.point(L.addX))
                addButton(.y).position(fit.point(L.addY))
            }
        }
    }

    func spanChip(_ c: RoofPlan.Chip, fit: SketchFit, live: Bool) -> some View {
        let ref = SpanRef(axis: c.axis, index: c.index), on = span == ref
        let size: CGFloat = max(11, 13 * fit.s)
        let label = Text(fmt(c.value)).font(.sarabunFixed(size, on ? .bold : .regular)).underline(!on)
            .foregroundStyle(Theme.primary).padding(.horizontal, 4).frame(minWidth: 34 * fit.s, minHeight: 20 * fit.s)
        let chip = label
            .background(on ? Self.soft : Color.white.opacity(0.01), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Theme.primary : Color.clear, lineWidth: 1.5))
            .rotationEffect(.degrees(c.axis == .y ? -90 : 0))
        return Button { span = on ? nil : ref } label: { chip.frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).disabled(!live)
            .accessibilityLabel("แก้ระยะช่วง " + Roof.spanName(c.axis, c.index) + " " + fmt(c.value) + " เมตร")
    }

    func addButton(_ a: Roof.Axis) -> some View {
        Button {
            var s = Roof.spans(values, a)
            s.append(s.last ?? 4)
            update { Roof.setSpans(&$0, a, s) }
            span = SpanRef(axis: a, index: s.count - 1)
        } label: {
            Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.onPrimary)
                .frame(width: 26, height: 26).background(Theme.primary, in: RoundedRectangle(cornerRadius: 4))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a == .x ? "เพิ่มช่วงแนวนอน" : "เพิ่มช่วงแนวตั้ง")
    }

    func postButtons(_ L: RoofPlan.Layout, _ fit: SketchFit) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(L.nodes.enumerated()), id: \.offset) { _, n in
                let d = 22 * fit.s
                Button { update { Roof.togglePost(&$0, i: n.i, j: n.j) } } label: {
                    Circle().fill(n.post ? Self.red.opacity(0.18) : Theme.primary.opacity(0.1))
                        .overlay(Circle().stroke(n.post ? Self.red : Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: n.post ? [] : [3, 2])))
                        .frame(width: d, height: d)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel((n.post ? "ลบเสา " : "เพิ่มเสา ") + Roof.gridName(.x, n.i) + Roof.gridName(.y, n.j))
                .position(fit.point(n.at))
            }
        }
    }

    /// Skylights toggle วางทับได้ / ห้ามวางทับ on tap; in a drawing tool or the PV mode, skylights / keep-out zones get a ×.
    func areaButtons(_ L: RoofPlan.Layout, _ fit: SketchFit) -> some View {
        ZStack(alignment: .topLeading) {
            let movable = mode == .structure && !editPosts && tool == nil && RoofDesign.current(values) != nil
            ForEach(Array(L.areas.enumerated()), id: \.offset) { _, item in
                let r = fit.rect(item.box), a = item.area
                if movable {
                    areaMover(a, r, L, fit)
                } else if a.kind == Roof.skylightKind && mode == .structure && !editPosts && tool == nil {
                    Button { update { Roof.toggleCover(&$0, index: a.index) } } label: {
                        Color.clear.frame(width: max(44, r.width), height: max(44, r.height)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(a.canCover ? "แผ่นใส วางทับได้ | แตะเพื่อสลับ" : "แผ่นใส ห้ามวางทับ | แตะเพื่อสลับ")
                    .position(x: r.midX, y: r.midY)
                }
                let drawn = a.kind == Roof.keepOutKind || RoofObstacleKind(rawValue: a.kind) != nil
                if (drawn && mode == .pv) || (a.kind == Roof.skylightKind && tool == .skylight) {
                    Button { update { Roof.removeArea(&$0, index: a.index) } } label: {
                        Text("×").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.onPrimary)
                            .frame(width: 20, height: 20).background(Self.red, in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(a.kind == Roof.keepOutKind ? "ลบเขตห้ามติด" : a.kind == Roof.skylightKind ? "ลบแผ่นใส" : "ลบ" + a.label)
                    .position(x: r.maxX, y: r.minY)
                }
            }
        }
    }

    /// On a roof filled from a design (standard-designs.md §3.2): drag an area to where it is on site, snapped to 5 cm,
    /// which makes its item ต่างจากแบบ; a skylight still switches วางทับได้ / ห้ามวางทับ on tap.
    func areaMover(_ a: Roof.Area, _ r: CGRect, _ L: RoofPlan.Layout, _ fit: SketchFit) -> some View {
        let offset = moving?.index == a.index ? moving?.offset ?? .zero : .zero
        let k = fit.s * L.k
        let name = a.kind == Roof.skylightKind ? "แผ่นใส" : a.kind == Roof.keepOutKind ? "เขตห้ามติด" : a.label
        return Color.clear
            .frame(width: max(44, r.width), height: max(44, r.height))
            .overlay {
                if offset != .zero {
                    RoundedRectangle(cornerRadius: 2).fill(Self.amber.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Self.amber, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
                        .frame(width: r.width, height: r.height)
                        .offset(offset)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if a.kind == Roof.skylightKind { update { Roof.toggleCover(&$0, index: a.index) } } }
            .gesture(DragGesture(minimumDistance: 6).onChanged { g in moving = (a.index, g.translation) }.onEnded { g in
                moving = nil
                guard k > 0 else { return }
                update { Roof.moveArea(&$0, index: a.index, x: a.x + g.translation.width / k, y: a.y + g.translation.height / k,
                                       lx: L.lx, ly: L.ly) }
            })
            .accessibilityLabel(name + (a.kind == Roof.skylightKind ? (a.canCover ? " วางทับได้" : " ห้ามวางทับ") : ""))
            .accessibilityHint("ลากเพื่อย้ายไปตำแหน่งที่พบหน้างาน")
            .position(x: r.midX, y: r.midY)
    }

    func drawSurface(_ L: RoofPlan.Layout, _ fit: SketchFit) -> some View {
        Color.clear.contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tool == .skylight ? Theme.primary : Self.red, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .gesture(DragGesture(minimumDistance: 2).onChanged { g in
                let a = L.metres(fit.sketch(g.startLocation)), b = L.metres(fit.sketch(g.location))
                drag = (a.x, a.y, b.x, b.y)
            }.onEnded { _ in
                let kind: String = switch tool {
                case .keepOut?: Roof.keepOutKind
                case .obstacle(let k)?: k.rawValue
                default: Roof.skylightKind
                }
                if let d = drag { update { Roof.addArea(&$0, kind: kind, x1: d.0, y1: d.1, x2: d.2, y2: d.3) } }
                drag = nil
            })
            .accessibilityLabel(planHint)
    }

    var skylightTool: some View {
        let n = Roof.areas(values).filter { $0.kind == Roof.skylightKind }.count
        return Button { tool = tool == .skylight ? nil : .skylight; span = nil } label: {
            Text(tool == .skylight ? "เสร็จ | แผ่นใส \(n)" : "แผ่นใส" + (n > 0 ? " (\(n))" : " +")).font(.sarabunFixed(13, .bold))
                .foregroundStyle(tool == .skylight ? Theme.onPrimary : Theme.primary)
                .padding(.horizontal, 10).frame(minHeight: 36)
                .background(tool == .skylight ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.primary.opacity(0.6)))
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("วาดแผ่นใสบนแปลน แตะแผ่นใสเพื่อสลับ วางทับได้ หรือ ห้ามวางทับ")
    }

    // MARK: span popover

    @ViewBuilder var spanEditor: some View {
        if let ref = span {
            SpanEditor(spans: Roof.spans(values, ref.axis), ref: ref,
                       set: { s, i in update { Roof.setSpans(&$0, ref.axis, s) }; span = SpanRef(axis: ref.axis, index: i) },
                       select: { span = $0 })
        }
    }
}
#endif
