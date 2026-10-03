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
struct SketchFit {
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
            HStack(alignment: .top, spacing: 6) {
                planStage.frame(maxWidth: .infinity, maxHeight: .infinity)
                legend.frame(width: 150)
            }
            .frame(maxHeight: .infinity)
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
        if tool == .skylight { return "ลากเพื่อวาดแผ่นใส · แตะ × เพื่อลบ" }
        if mode == .pv { return "จัดอัตโนมัติ · หลบแผ่นใสและเขตห้ามติด" }
        if editPosts { return "แตะจุดตัดกริด เพิ่ม/ลบเสา" }
        if values.photo("planPhoto") != nil { return "รายงานใช้แบบร่างที่ถ่ายไว้" }
        if values.text(Roof.Key.spansX).isEmpty || values.text(Roof.Key.spansY).isEmpty { return "ระยะตัวอย่าง · แตะเลขสีฟ้าเพื่อแก้" }
        return "แตะเลขสีฟ้า/แผ่นใสเพื่อแก้"
    }

    var planFooter: some View {
        HStack(spacing: 8) {
            (Text("แปลนโครงหลังคา").bold().underline() + Text(" · " + planHint).foregroundColor(mode == .pv && tool == nil ? Home.navy : Home.muted)
                .fontWeight(mode == .pv && tool == nil ? .bold : .regular))
                .font(.system(size: 14)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            RoofSegments(options: ["โครงสร้าง", "จัดแผง"], selected: mode == .pv ? 1 : 0) { i in setMode(i == 1 ? .pv : .structure) }
                .frame(minWidth: 120, maxWidth: 150)
            if mode == .structure { structureButtons } else { pvButtons }
            footerButton("CAD", icon: "doc.badge.arrow.up", on: showCAD) { showCAD.toggle(); span = nil }
                .accessibilityLabel("ส่งออก CAD")
                .popover(isPresented: $showCAD, arrowEdge: .bottom) { cadSheet.presentationCompactAdaptation(.popover) }
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
                    Text("ทิศเหนือ").font(.system(size: 13, weight: .bold))
                    Text(north == nil ? "ยังไม่ระบุใน A2" : "ตามภาพ A2 · หมุน \(Int(turn))°").font(.system(size: 11)).foregroundStyle(Home.muted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Self.line.frame(height: 1)
            Text("สัญลักษณ์").font(.system(size: 13, weight: .bold))
            ForEach(Array(legendItems.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    LegendGlyph(kind: item.0).frame(width: 24, height: 14)
                    Text(item.1).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    var legendItems: [(LegendGlyph.Kind, String)] {
        if mode == .pv {
            let tables = Roof.pvRows(values) > 0 || Roof.pvPerTable(values) > 0
            return [(.pv, "แผงโซลาร์")] + (tables ? [(.table, "ชุดแผง (โต๊ะ)"), (.gap, "ระยะห่างระหว่างชุด")] : [])
                + [(.blocked, "ช่องที่วางไม่ได้"), (.keepOut, "เขตห้ามติด"), (.skyOK, "แผ่นใส"), (.ridge, "สันหลังคา")]
        }
        let f = Roof.frame(values), pp = "แป @" + String(format: "%.2f", Roof.purlinSpacing(values))
        let two: [(LegendGlyph.Kind, String)] = f.isRafter ? [(.heavy, "อเส"), (.thin, "จันทัน @1.00")]
            : f == .rafterTruss ? [(.heavy, "จันทันถัก T1"), (.dashedHeavy, "T2 รับจันทัน")] : [(.double, "โครงถัก T1"), (.purlin, pp)]
        return [(.post, "เสา")] + two + [(.skyOK, "แผ่นใส · วางทับได้"), (.skyNo, "แผ่นใส · ห้ามวางทับ"), (.ridge, "สันหลังคา"), (.section, "แนวรูปตัด A–A")]
    }

    func footerButton(_ title: String, icon: String? = nil, on: Bool = false, tint: Color = Home.navy, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .bold)) }
                Text(title).font(.system(size: 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? Color.white : tint)
            .padding(.horizontal, 10).frame(minHeight: 44)
            .background(on ? tint : Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Color.clear : tint.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder var structureButtons: some View {
        let n = Roof.posts(values).count
        footerButton(editPosts ? "เสร็จ · เสา \(n) ต้น" : "แก้เสา (\(n))", icon: editPosts ? nil : "square.fill", on: editPosts, tint: editPosts ? Home.primary : Home.navy) {
            editPosts.toggle(); tool = nil; span = nil
        }
        if let p = values.photo("planPhoto") {
            Menu {
                Button("ดูแบบร่าง") { viewingSketch = p }
                Button("ถ่ายใหม่") { sketchCamera = true }
                Button("อัปโหลดใหม่") { sketchPicker = true }
                Button("ลบแบบร่าง", role: .destructive) { set("planPhoto", nil) }
            } label: {
                Label("แบบร่าง ✓", systemImage: "doc.richtext").font(.system(size: 14, weight: .bold)).foregroundStyle(Home.ok)
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.ok.opacity(0.6)))
            }
        } else {
            Menu {
                Button { sketchCamera = true } label: { Label("ถ่ายภาพ", systemImage: "camera") }
                Button { sketchPicker = true } label: { Label("อัปโหลด", systemImage: "photo") }
            } label: {
                Label("ถ่ายแบบร่าง", systemImage: "camera").font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.5)))
            }
            .accessibilityHint("ภาพแบบร่างที่วาดเองจะใช้แทนแปลนอัตโนมัติในรายงาน")
        }
    }

    @ViewBuilder var pvButtons: some View {
        let zones = Roof.areas(values).filter { $0.kind == Roof.keepOutKind }.count
        footerButton(tool == .keepOut ? "เสร็จ · เขตห้าม \(zones)" : "วาดเขตห้ามติด" + (zones > 0 ? " (\(zones))" : ""),
                     on: tool == .keepOut, tint: Self.red) {
            tool = tool == .keepOut ? nil : .keepOut
        }
    }

    // MARK: plan stage

    var planStage: some View {
        GeometryReader { geo in
            let plan = RoofPlan(values, mode: mode, chips: true, dragging: drag, highlight: member)
            let fit = SketchFit(RoofPlan.width, RoofPlan.height, in: geo.size)
            ZStack(alignment: .topLeading) {
                SketchCanvas(ops: plan.sketch.ops, fit: fit)
                    .accessibilityLabel(String(format: "แปลนโครงหลังคา %.2f คูณ %.2f เมตร", plan.layout.lx, plan.layout.ly))
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
        let label = Text(fmt(c.value)).font(.system(size: size, weight: on ? .bold : .regular)).underline(!on)
            .foregroundStyle(Home.primary).padding(.horizontal, 4).frame(minWidth: 34 * fit.s, minHeight: 20 * fit.s)
        let chip = label
            .background(on ? Self.soft : Color.white.opacity(0.01), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Home.primary : Color.clear, lineWidth: 1.5))
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
            Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Home.primary, in: RoundedRectangle(cornerRadius: 4))
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
                    Circle().fill(n.post ? Self.red.opacity(0.18) : Home.primary.opacity(0.1))
                        .overlay(Circle().stroke(n.post ? Self.red : Home.primary, style: StrokeStyle(lineWidth: 1.5, dash: n.post ? [] : [3, 2])))
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
            ForEach(Array(L.areas.enumerated()), id: \.offset) { _, item in
                let r = fit.rect(item.box), a = item.area
                if a.kind == Roof.skylightKind && mode == .structure && !editPosts && tool == nil {
                    Button { update { Roof.toggleCover(&$0, index: a.index) } } label: {
                        Color.clear.frame(width: max(44, r.width), height: max(44, r.height)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(a.canCover ? "แผ่นใส วางทับได้ · แตะเพื่อสลับ" : "แผ่นใส ห้ามวางทับ · แตะเพื่อสลับ")
                    .position(x: r.midX, y: r.midY)
                }
                if (a.kind == Roof.keepOutKind && mode == .pv) || (a.kind == Roof.skylightKind && tool == .skylight) {
                    Button { update { Roof.removeArea(&$0, index: a.index) } } label: {
                        Text("×").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(Self.red, in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(a.kind == Roof.keepOutKind ? "ลบเขตห้ามติด" : "ลบแผ่นใส")
                    .position(x: r.maxX, y: r.minY)
                }
            }
        }
    }

    func drawSurface(_ L: RoofPlan.Layout, _ fit: SketchFit) -> some View {
        Color.clear.contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tool == .keepOut ? Self.red : Home.primary, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .gesture(DragGesture(minimumDistance: 2).onChanged { g in
                let a = L.metres(fit.sketch(g.startLocation)), b = L.metres(fit.sketch(g.location))
                drag = (a.x, a.y, b.x, b.y)
            }.onEnded { _ in
                if let d = drag { update { Roof.addArea(&$0, kind: tool == .keepOut ? Roof.keepOutKind : Roof.skylightKind, x1: d.0, y1: d.1, x2: d.2, y2: d.3) } }
                drag = nil
            })
            .accessibilityLabel(tool == .keepOut ? "ลากเพื่อวาดเขตห้ามติดตั้ง" : "ลากเพื่อวาดแผ่นใส")
    }

    var skylightTool: some View {
        let n = Roof.areas(values).filter { $0.kind == Roof.skylightKind }.count
        return Button { tool = tool == .skylight ? nil : .skylight; span = nil } label: {
            Text(tool == .skylight ? "เสร็จ · แผ่นใส \(n)" : "แผ่นใส" + (n > 0 ? " (\(n))" : " +")).font(.system(size: 13, weight: .bold))
                .foregroundStyle(tool == .skylight ? Color.white : Home.primary)
                .padding(.horizontal, 10).frame(minHeight: 36)
                .background(tool == .skylight ? Home.primary : Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Home.primary.opacity(0.6)))
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

    // MARK: section card

    var sectionCard: some View {
        let f = Roof.frame(values)
        return card {
            sectionStage(big: false).frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 8) {
                (Text("รูปตัด A-A · " + f.title).bold().underline() + Text(" · หน่วย ม.").foregroundColor(Home.muted))
                    .font(.system(size: 14)).lineLimit(1).minimumScaleFactor(0.6).truncationMode(.tail)
                Spacer(minLength: 8)
                footerButton("ขยาย", icon: "arrow.up.left.and.arrow.down.right", tint: Home.primary) { sectionBig = true }
                    .accessibilityLabel("ขยายรูปตัดเต็มจอ")
                if !f.isRafter { baysStepper }
            }
        }
    }

    /// Section A-A with its overhang / clear-height buttons and the numbered callouts (a tap picks that member row).
    func sectionStage(big: Bool) -> some View {
        let f = Roof.frame(values)
        return GeometryReader { geo in
            let sec = RoofSection(values, highlight: member)
            let fit = SketchFit(RoofSection.width, RoofSection.height, in: geo.size)
            ZStack(alignment: .topLeading) {
                SketchCanvas(ops: sec.sketch.ops, fit: fit)
                    .accessibilityLabel(String(format: "รูปตัด A-A %@ ช่วง %.2f ม. มุม %@ องศา R %.2f ม.", f.title, sec.span, fmt(f.slope), sec.rise))
                if !big {
                    lengthButton(Roof.Key.overhang, "ชายคา").position(fit.point(sec.overhangLabel))
                    lengthButton(Roof.Key.clearHeight, f.isRafter ? "สูงถึงหัวเสา" : "สูงใต้ขื่อ").position(fit.point(sec.clearLabel))
                }
                ForEach(sec.callouts.keys.sorted(), id: \.self) { n in
                    Button { member = member == n ? nil : n } label: { Color.clear.frame(width: 44, height: 44).contentShape(Circle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("ตำแหน่งชิ้นส่วน \(n) " + f.members[n - 1].name)
                        .accessibilityAddTraits(member == n ? .isSelected : [])
                        .position(fit.point(sec.callouts[n]!))
                }
            }
        }
    }

    var baysStepper: some View {
        let n = Roof.bays(values), auto = Roof.baysAreAuto(values), w = Roof.span(values) / 2 / Double(n)
        return HStack(spacing: 8) {
            Text("ช่อง/ข้าง").font(.system(size: 13)).foregroundStyle(Home.muted).lineLimit(1).fixedSize()
            stepButton("minus", enabled: n > Roof.baysRange.lowerBound) { update { Roof.setBays(&$0, n - 1) } }
            Text("\(n) × " + String(format: "%.2f ม.", w)).font(.system(size: 16, weight: .bold)).monospacedDigit()
                .lineLimit(1).fixedSize()
            stepButton("plus", enabled: n < Roof.baysRange.upperBound) { update { Roof.setBays(&$0, n + 1) } }
            Button { update { Roof.setBays(&$0, nil) } } label: {
                Text("อัตโนมัติ").font(.system(size: 13, weight: .bold)).lineLimit(1).fixedSize().foregroundStyle(auto ? Home.disabledText : Home.primary)
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(auto ? Home.disabledFill : Home.primary.opacity(0.5)))
            }
            .buttonStyle(.plain).disabled(auto)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ช่องโครงถักต่อข้าง \(n) ช่อง")
    }

    func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(enabled ? Home.primary : Home.disabledText)
                .frame(width: 44, height: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(enabled ? Home.navy.opacity(0.3) : Home.disabledFill))
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "เพิ่ม" : "ลด")
    }

    /// The section's overhang and clear height: tap to step them by 0.05 m.
    func lengthButton(_ key: String, _ name: String) -> some View {
        Button { lengthKey = key } label: { Color.clear.frame(width: 88, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel(name + " แตะเพื่อแก้")
            .popover(isPresented: Binding(get: { lengthKey == key }, set: { if !$0 { lengthKey = nil } })) {
                lengthEditor(key, name).presentationCompactAdaptation(.popover)
            }
    }

    func lengthEditor(_ key: String, _ name: String) -> some View {
        let overhang = key == Roof.Key.overhang
        let m = overhang ? Roof.overhang(values) : Roof.clearHeight(values), range = overhang ? 0.0...3.0 : 1.0...30.0
        return VStack(alignment: .leading, spacing: 10) {
            Text(name + " (ม.)").font(.system(size: 15, weight: .bold))
            HStack(spacing: 10) {
                stepButton("minus", enabled: m > range.lowerBound) { update { Roof.setLength(&$0, key, max(range.lowerBound, m - 0.05)) } }
                Text(String(format: "%.2f", m)).font(.system(size: 20, weight: .bold)).monospacedDigit().frame(minWidth: 70)
                stepButton("plus", enabled: m < range.upperBound) { update { Roof.setLength(&$0, key, min(range.upperBound, m + 0.05)) } }
            }
            Button { update { Roof.setLength(&$0, key, nil) } } label: {
                Text("ใช้ค่าตามแบบ (" + (overhang ? "0.70" : "4.00") + ")").font(.system(size: 13, weight: .semibold)).foregroundStyle(Home.primary).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Home.navy)
        .padding(14)
    }
}

/// The span popover: ± 0.5 m, quick values, split, delete, next, equalise and "all 4.00".
struct SpanEditor: View {
    let spans: [Double]
    let ref: RoofPageWide.SpanRef
    let set: ([Double], Int) -> Void
    let select: (RoofPageWide.SpanRef?) -> Void
    @State var typed = ""
    @FocusState var typing: Bool

    var cur: Double { spans[safe: ref.index] ?? 0 }
    func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    func with(_ v: Double) { var a = spans; if a.indices.contains(ref.index) { a[ref.index] = v; set(a, ref.index) } }
    var total: Double { spans.reduce(0, +) }
    var equal: Bool { spans.allSatisfy { abs($0 - total / Double(spans.count)) <= 0.005 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("ระยะช่วงกริด " + Roof.spanName(ref.axis, ref.index)).font(.system(size: 17, weight: .bold))
                Spacer(minLength: 8)
                Text("ช่วงที่ \(ref.index + 1) จาก \(spans.count)").font(.system(size: 12)).foregroundStyle(Home.muted)
                Button { select(nil) } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Home.muted).frame(width: 44, height: 32)
                }
                .buttonStyle(.plain).accessibilityLabel("ปิด")
            }
            valueRow
            HStack(spacing: 8) {
                ForEach([1.5, 3, 4, 4.5, 6], id: \.self) { v in
                    let on = abs(v - cur) < 0.001
                    Button { with(v) } label: {
                        Text(fmt(v)).font(.system(size: 15, weight: on ? .bold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? Home.mint : Color.white, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.clear : Home.navy.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 14) {
                Button("แบ่งครึ่ง") {
                    var a = spans; let h = r2(cur / 2)
                    a.replaceSubrange(ref.index...ref.index, with: [h, r2(cur - h)]); set(a, ref.index)
                }
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Home.primary).frame(minHeight: 44)
                Button("ลบช่วง") {
                    var a = spans; a.remove(at: ref.index); set(a, min(ref.index, a.count - 1))
                }
                .font(.system(size: 15, weight: .bold)).foregroundStyle(spans.count > 1 ? RoofPageWide.red : Home.disabledText).frame(minHeight: 44)
                .disabled(spans.count <= 1)
                Spacer()
                Button {
                    if ref.index < spans.count - 1 { select(.init(axis: ref.axis, index: ref.index + 1)) }
                    else { select(.init(axis: ref.axis == .x ? .y : .x, index: 0)) }
                } label: {
                    Text("ถัดไป ›").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(minHeight: 44).background(Home.primary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                outline("EQ เท่ากันทั้งแนว", enabled: !equal) {
                    let m = spans.count; set(Array(repeating: (total / Double(m) * 1000).rounded() / 1000, count: m), ref.index)
                }
                outline("ทุกช่วง 4.00 ม.", enabled: spans.contains { abs($0 - 4) > 0.001 }) { set(Array(repeating: 4, count: spans.count), ref.index) }
            }
            Divider()
            (Text("ทั้งแนว: ") + Text(spans.map { fmt($0) }.joined(separator: ", ")).bold() + Text(" · รวม " + String(format: "%.2f", total) + " ม."))
                .font(.system(size: 13)).foregroundStyle(Home.muted).lineLimit(2)
        }
        .foregroundStyle(Home.navy)
        .padding(16)
        .frame(width: 340)
        .onAppear { typed = String(format: "%.2f", cur) }
        .onChange(of: ref) { _, _ in typed = String(format: "%.2f", cur) }
        .onChange(of: cur) { _, v in if !typing { typed = String(format: "%.2f", v) } }
    }

    var valueRow: some View {
        HStack(spacing: 10) {
            square("minus") { with(max(0.5, r2(cur - 0.5))) }
            HStack {
                TextField("", text: $typed).keyboardType(.decimalPad).focused($typing)
                    .font(.system(size: 24, weight: .bold)).monospacedDigit()
                    .onSubmit(commit)
                    .onChange(of: typing) { _, on in if !on { commit() } }
                Text("ม.").font(.system(size: 15)).foregroundStyle(Home.muted)
            }
            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 52)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.primary, lineWidth: 2))
            square("plus") { with(r2(cur + 0.5)) }
        }
    }

    func commit() {
        if let v = NumberInput.value(typed), v > 0 { with(r2(v)) } else { typed = String(format: "%.2f", cur) }
    }

    func square(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(Home.primary)
                .frame(width: 48, height: 52)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "เพิ่ม 0.5 เมตร" : "ลด 0.5 เมตร")
    }

    func outline(_ t: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 14, weight: .bold)).foregroundStyle(enabled ? Home.primary : Home.disabledText).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(enabled ? Home.primary.opacity(0.6) : Home.disabledFill))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}
/// The plan legend's north arrow (icons/north-arrow.svg): navy half pointing north, white half south.
struct NorthArrow: View {
    let degrees: Double
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 48, c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: s, y: s)
            ctx.fill(Path(ellipseIn: CGRect(x: -21, y: -21, width: 42, height: 42)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: -21, y: -21, width: 42, height: 42)), with: .color(Home.navy), lineWidth: 1.2)
            ctx.rotate(by: .degrees(degrees))
            var n = Path(); n.move(to: CGPoint(x: 0, y: -18)); n.addLine(to: CGPoint(x: 6, y: 4)); n.addLine(to: .zero); n.addLine(to: CGPoint(x: -6, y: 4)); n.closeSubpath()
            ctx.fill(n, with: .color(Home.navy))
            var so = Path(); so.move(to: CGPoint(x: 0, y: 18)); so.addLine(to: CGPoint(x: 6, y: 4)); so.addLine(to: .zero); so.addLine(to: CGPoint(x: -6, y: 4)); so.closeSubpath()
            ctx.fill(so, with: .color(.white)); ctx.stroke(so, with: .color(Home.navy), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// A 24 × 14 legend symbol (icons/legend).
struct LegendGlyph: View {
    enum Kind { case post, double, heavy, thin, dashedHeavy, purlin, skyOK, skyNo, ridge, section, pv, table, gap, blocked, keepOut }
    let kind: Kind
    static let ink = Color(red: 0.067, green: 0.067, blue: 0.067)
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 14
            func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy) }
            func h(_ y: Double, _ x0: Double = 1, _ x1: Double = 23) -> Path { var p = Path(); p.move(to: CGPoint(x: x0 * sx, y: y * sy)); p.addLine(to: CGPoint(x: x1 * sx, y: y * sy)); return p }
            let chain = StrokeStyle(lineWidth: 1.4, dash: [6, 2, 1.5, 2])
            switch kind {
            case .post: ctx.fill(Path(r(7, 2, 10, 10)), with: .color(Color(red: 0.067, green: 0.094, blue: 0.153)))
            case .double: ctx.stroke(h(5), with: .color(Self.ink), lineWidth: 1.3); ctx.stroke(h(9), with: .color(Self.ink), lineWidth: 1.3)
            case .heavy: ctx.stroke(h(7), with: .color(Self.ink), lineWidth: 2.2)
            case .thin: ctx.stroke(h(7), with: .color(Self.ink), lineWidth: 0.9)
            case .dashedHeavy: ctx.stroke(h(7), with: .color(Self.ink), style: StrokeStyle(lineWidth: 1.8, dash: [6, 2]))
            case .purlin: ctx.stroke(h(7), with: .color(Color(red: 0.42, green: 0.447, blue: 0.502)), lineWidth: 0.8)
            case .skyOK, .skyNo:
                ctx.fill(Path(r(3, 2, 18, 10)), with: .color(Color(red: 0.812, green: 0.91, blue: 0.969)))
                if kind == .skyOK { ctx.stroke(Path(r(3, 2, 18, 10)), with: .color(Color(red: 0.18, green: 0.561, blue: 0.859)), lineWidth: 1) }
                else { ctx.stroke(Path(r(3, 2, 18, 10)), with: .color(RoofPageWide.red), style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
            case .ridge: ctx.stroke(h(7), with: .color(Self.ink), style: chain)
            case .section: ctx.stroke(h(7), with: .color(Color(red: 0.067, green: 0.094, blue: 0.153)), style: StrokeStyle(lineWidth: 1.8, dash: [6, 2, 1.5, 2]))
            case .pv:
                ctx.fill(Path(r(3, 2, 18, 10)), with: .color(Color(red: 0.122, green: 0.31, blue: 0.561).opacity(0.85)))
                ctx.stroke(Path(r(3, 2, 18, 10)), with: .color(Color(red: 0.863, green: 0.902, blue: 0.949)), lineWidth: 1)
            case .table: ctx.stroke(Path(r(2, 2, 20, 10)), with: .color(Home.navy), lineWidth: 1.6)
            case .gap:
                ctx.stroke(h(7, 2, 22), with: .color(RoofPageWide.amber), lineWidth: 1.2)
                var t = Path(); t.move(to: CGPoint(x: 2 * sx, y: 4 * sy)); t.addLine(to: CGPoint(x: 2 * sx, y: 10 * sy))
                t.move(to: CGPoint(x: 22 * sx, y: 4 * sy)); t.addLine(to: CGPoint(x: 22 * sx, y: 10 * sy))
                ctx.stroke(t, with: .color(RoofPageWide.amber), lineWidth: 1.2)
            case .blocked: ctx.stroke(Path(r(3, 2, 18, 10)), with: .color(Color(red: 0.122, green: 0.31, blue: 0.561)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            case .keepOut:
                ctx.fill(Path(r(3, 2, 18, 10)), with: .color(RoofPageWide.red.opacity(0.12)))
                ctx.stroke(Path(r(3, 2, 18, 10)), with: .color(RoofPageWide.red), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
