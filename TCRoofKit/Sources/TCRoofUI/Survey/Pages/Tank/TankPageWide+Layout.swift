#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// D1 sub-step 3 "จัดแผง" on iPhone (docs/ui/survey-d1-layout-iphone, 390 × 844): the automatic panel layout on the
/// tank roof (`TankLayout`), its structure materials and three checks before going on. The layout's offset,
/// orientation and the panels switched off are stored in the tank's values; `panelsBefore` follows the count. iPad shows
/// the same cards in two columns (`padLayoutStep`).
extension TankPageWide {
    static let drawingRef = "B1-C3"

    var phoneLayoutCards: some View {
        layoutSheets(VStack(spacing: 12) {
            phoneTabs
            layoutPlanCard
            layoutSideCards
        })
    }

    @ViewBuilder var layoutSideCards: some View {
        if let s = TankDesign.summary(values), s.open > 0 {
            DesignCheckBanner(open: s.open, unit: "จุด") { withAnimation { tab = 2 } }
        }
        if let l = TankLayout.current(values) {
            layoutSummaryCard(l)
            layoutChecksCard(l)
            shadeCard(l)
        }
        dxfButton
    }

    /// iPad: the plan card on the left, the materials and checks on the right; one column in portrait.
    @ViewBuilder var padLayoutStep: some View {
        let next = nextButton("ถัดไป | ภาพถ่าย ›") { withAnimation { tab = 4 } }
        if stacked {
            layoutSheets(ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        layoutPlanCard.frame(maxWidth: 640)
                        layoutSideCards.frame(maxWidth: 640)
                        next.frame(maxWidth: 640)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .onChange(of: shadeScroll) { _, on in if on { withAnimation { proxy.scrollTo("shadeCard", anchor: .top) }; shadeScroll = false } }
            })
        } else {
            layoutSheets(HStack(alignment: .top, spacing: gap) {
                ScrollView { layoutPlanCard.frame(maxWidth: 680).frame(maxWidth: .infinity) }.scrollIndicators(.hidden)
                ScrollView {
                    VStack(spacing: 12) {
                        layoutSideCards
                        next
                    }
                }
                .scrollIndicators(.hidden)
                .frame(width: 360)
            }
            .frame(maxHeight: .infinity))
        }
    }

    /// First open, the question before a new layout and the B1-C3 sheet, for both layouts.
    func layoutSheets<V: View>(_ content: V) -> some View {
        content
        .onAppear(perform: openLayout)
        .confirmationDialog("ล้างการแก้แผงที่ทำไว้?", isPresented: Binding(get: { layoutAsk != nil }, set: { if !$0 { layoutAsk = nil } }),
                            titleVisibility: .visible) {
            Button(layoutAsk == .max ? "หาผังที่ได้พลังงานมากที่สุด" : "จัดแผงใหม่", role: .destructive) {
                if let a = layoutAsk { runLayout(a) }
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("แผงที่ปิดหรือโต๊ะที่เอาออกจะกลับมาตามผังอัตโนมัติ")
        }
        .sheet(isPresented: $drawingOpen) { drawingSheet }
        .sheet(isPresented: $southOpen) { southSheet }
    }

    /// First open: the automatic layout; later opens write `panelsBefore` again, as sub-step 2 may have changed.
    func openLayout() {
        guard Tank.hasSize(values) else { return }
        update { v in
            if let p = TankLayout.params(v) { TankLayout.save(&v, p, off: TankLayout.off(v)) }
            else { TankLayout.save(&v, TankLayout.auto(v), off: []) }
        }
    }

    enum LayoutRun { case auto, max }

    /// `จัดแผงใหม่` / `หาผังที่ได้พลังงานมากที่สุด`: asks first when panels were edited by hand.
    func askLayout(_ a: LayoutRun) {
        if TankLayout.off(values).isEmpty { runLayout(a) } else { layoutAsk = a }
    }

    func runLayout(_ a: LayoutRun) {
        layoutAsk = nil
        switch a {
        case .auto:
            energySearch = nil; southCompare = nil
            update { TankLayout.save(&$0, TankLayout.auto($0), off: []) }
        case .max:
            // the row gaps from the standard's up, scored by the year's energy after shade (tank-mounting-layout.md §3a)
            let v = values, site = RoofMount.site(job), lat = site.latitude ?? RoofMount.defaultLatitude, lon = site.longitude
            layoutSearching = true
            Task { @MainActor in
                let s = await Task.detached(priority: .userInitiated) { TankLayout.bestEnergy(v, latitude: lat, longitude: lon) }.value
                if let s { update { TankLayout.save(&$0, s.params, off: []) } }
                energySearch = s
                southCompare = nil
                layoutSearching = false
                if let s { compareSouth(v, latitude: lat, longitude: lon, wall: s) }
            }
        }
    }

    // MARK: card 1 | plan

    var layoutAside: String {
        "ตามแบบ \(Self.drawingRef) | เอียง " + String(format: "%.1f°", (TankLayout.params(values) ?? TankLayout.defaults()).tilt)
    }

    var layoutPlanCard: some View {
        phoneCard(1, "การวางผังแผง", chip: (layoutAside, Theme.inkMuted, Color.clear)) {
            if TankLayout.standardChanged(values) { standardNote }
            layoutSegment
            layoutPlanFrame
            HStack(spacing: 8) {
                Button { askLayout(.auto) } label: {
                    Text("จัดแผงใหม่").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary))
                }
                .buttonStyle(.plain)
                Button { askLayout(.max) } label: {
                    Group {
                        if layoutSearching { ProgressView().tint(Theme.navy) } else {
                            Text("หาผังที่ได้พลังงานมากที่สุด").multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                        }
                    }
                    .font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.mint, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle))
                }
                .buttonStyle(.plain)
                .disabled(layoutSearching)
            }
            .disabled(!Tank.hasSize(values))
            if let s = energySearch, let p = TankLayout.params(values), abs(p.rowGap - s.chosen.gap) < 1e-6 {
                Text(s.line).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                southRow
            }
        }
    }

    /// The team's standard changed since this layout was made: it keeps its own until laid out again.
    var standardNote: some View {
        let team = TankStandard.Store.shared.current
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.primary)
            Text("มาตรฐานโครงสร้างของทีมเปลี่ยนแล้ว (rev \(team.revision): \(team.summary)) | ผังนี้ยังใช้ค่าเดิม กด จัดแผงใหม่ เพื่อใช้ค่าใหม่")
                .font(.sarabunFixed(13)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 10))
    }

    /// `เลื่อนผัง` / `แก้แผง`
    var layoutSegment: some View {
        HStack(spacing: 3) {
            ForEach([(false, "เลื่อนผัง"), (true, "แก้แผง")], id: \.0) { item in
                let on = layoutEditing == item.0
                Button { withAnimation(.easeOut(duration: 0.15)) { layoutEditing = item.0 } } label: {
                    Text(item.1).font(.sarabunFixed(14, on ? .bold : .regular)).foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 8).fill(Theme.surface).shadow(color: Theme.navy.opacity(0.2), radius: 1.5, y: 1) }
                        }
                        .contentShape(Rectangle().inset(by: -3))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(minHeight: 44)
        .background(Theme.disabledFill, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder func layoutPlan(_ l: TankLayout) -> some View {
        TankLayoutPlan(values: values, layout: l, editing: layoutEditing,
                       move: { x, y in update { v in
                           guard var p = TankLayout.params(v) else { return }
                           p.offX = x; p.offY = y
                           TankLayout.save(&v, p, off: TankLayout.off(v))
                       } },
                       toggle: { key in update { TankLayout.toggle(&$0, key) } },
                       removeTable: { r, t in update { TankLayout.removeTable(&$0, row: r, index: t) } })
    }

    var layoutPlanFrame: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                if let l = TankLayout.current(values) { layoutPlan(l) } else { emptyPlan.frame(height: 260) }
                Button { layoutZoom = 1; layoutFull = true } label: {
                    Image(systemName: "arrow.down.left.and.arrow.up.right").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 36, height: 36)
                        .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Theme.navy.opacity(0.2), radius: 2, y: 1)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("ขยายแปลนเต็มจอ")
                .disabled(TankLayout.current(values) == nil)
            }
            Text(Tank.hasSize(values) ? "แผงโมโน \(fmt((TankLayout.params(values) ?? TankLayout.defaults()).moduleKW * 1000)) W | แตะแผงเพื่อแก้" : "เลือกขนาดถังในขั้นที่ 1 ก่อน")
                .font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 10).padding(.bottom, 8)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
    }

    /// The plan full screen with the two modes, zoomed by pinch or − / +.
    var layoutFullScreen: some View {
        NavigationStack {
            VStack(spacing: 12) {
                layoutSegment
                GeometryReader { g in
                    let w = g.size.width * layoutZoom
                    ScrollView([.horizontal, .vertical]) {
                        if let l = TankLayout.current(values) {
                            layoutPlan(l).frame(width: w, height: w * 300 / 330).background(Theme.paper)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .simultaneousGesture(MagnifyGesture().onChanged { m in layoutZoom = min(4, max(1, layoutZoom * sqrt(m.magnification))) })
                }
                if let l = TankLayout.current(values) {
                    Text("\(l.count) แผง | " + String(format: "%.1f kWp", l.kWp)).font(.sarabunFixed(15, .bold))
                }
            }
            .padding(16)
            .tcPageBackground()
            .navigationTitle("การวางผังแผง")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { layoutZoom = max(1, layoutZoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("ย่อ").disabled(layoutZoom <= 1)
                    Button { layoutZoom = min(4, layoutZoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("ขยาย").disabled(layoutZoom >= 4)
                }
                ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { layoutFull = false } }
            }
        }
        .foregroundStyle(Theme.navy)
    }

    // MARK: card 2 | summary and materials

    func layoutSummaryCard(_ l: TankLayout) -> some View {
        let b = l.bom, w = fmt(l.params.moduleKW * 1000)
        let rows: [(String, String)] = [
            ("แผง \(w) W", "\(l.count)"),
            ("กำลังรวม", String(format: "%.1f kWp", l.kWp)),
            ("แถว | โต๊ะแผง", "\(l.rows) | \(l.builtTables.count)"),
            ("ระยะห่างแถว", String(format: "%.2f ม.", l.params.rowGap) + (l.params.rowGap > l.params.standardGap + 1e-6 ? "" : " (มาตรฐาน)")),
            ("เสา + โครงหน้า", "\(b.posts)"),
            ("ฐานราก", "\(b.footings) จุด"),
            ("ราง (4 เส้น)", "\(Int(b.railLength.rounded())) ม."),
            ("Mid / End clamp", "\(b.midClamps) / \(b.endClamps)"),
            ("Rail clamp", "\(b.railClamps)"),
            ("ค้ำยันไขว้", "\(b.braces) ชุด"),
            ("ฐานเสา | พุก M12", "\(b.bases) | \(b.anchors)"),
            ("ค้ำโครงข้าง | ค้ำยื่น", "\(b.sideBraces) | \(b.struts)"),
        ]
        let chip = ("\(l.count) แผง | " + String(format: "%.1f kWp", l.kWp), Theme.okTick, Theme.okSoft)
        return phoneCard(2, "สรุป | วัสดุโครงสร้าง", chip: chip) {
            AnyView(energyTiles(l))
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.0).font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
                        Spacer(minLength: 8)
                        Text(r.1).font(.sarabunFixed(15, .bold)).monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.borderSubtle).frame(height: 1) } }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// MWh a year, kWh per kWp and the row shade, after the shade simulation (card 4's, worked out off the main thread).
    @ViewBuilder func energyTiles(_ l: TankLayout) -> some View {
        let s = shadeResult
        let tiles: [(String, String)] = [
            ("MWh/ปี", s.map { String(format: "%.1f", $0.netMWh) } ?? "…"),
            ("kWh/kWp/ปี", s.map { l.kWp > 0 ? String(format: "%.0f", $0.netMWh * 1000 / l.kWp) : "-" } ?? "…"),
            ("เงาแถวหน้า", s.map { String(format: "%.1f%%", $0.rowLoss * 100) } ?? "…"),
        ]
        HStack(spacing: 6) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.1).font(.sarabunFixed(16, .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    Text(t.0).font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Self.track, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
            }
        }
        Text("พลังงานโดยประมาณจากแบบจำลองท้องฟ้าแจ่มใส หักเงาแถวหน้าและสิ่งบังแล้ว").font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: card 3 | checks

    func layoutChecksCard(_ l: TankLayout) -> some View {
        let c = l.checks
        let chip = c.allOK ? ("✓ 3/3", Theme.okTick, Theme.okSoft) : ("\(c.passed)/3", Theme.pending, Theme.pendingSoft)
        return phoneCard(3, "ตรวจสอบก่อนไปต่อ", chip: chip) {
            VStack(spacing: 0) {
                // the panel underside above the vent, less the vent's height
                checkRow("ใต้คานเหนือปล่อง (แผงทับได้)", c.ventHeadroom.map { String(format: "%.2f ม.", $0) } ?? "ไม่มีปล่องใต้แผง", ok: c.ventsOK, first: true)
                checkRow("ขอบถังถึงขอบแผง ≥ " + String(format: "%.2f ม.", l.params.clearance), c.edge.map { String(format: "%.2f ม.", $0) } ?? "-", ok: c.edgeOK)
                checkRow("ขาโครงสร้างไม่ชนสิ่งกีดขวาง", "เสา \(c.posts) ต้น | ตัดแผง \(c.cutColumns) คอลัมน์", ok: c.legsOK)
            }
            Button { drawingOpen = true } label: {
                Text("ดูแบบ \(Self.drawingRef) | ภาพตัดโต๊ะแผง | ฐานเสา").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary))
            }
            .buttonStyle(.plain)
        }
    }

    func checkRow(_ title: String, _ value: String, ok: Bool, first: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark" : "exclamationmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.onMedia)
                .frame(width: 24, height: 24)
                .background(Circle().fill(ok ? Theme.success : Theme.warning))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarabunFixed(14.5, .bold)).fixedSize(horizontal: false, vertical: true)
                Text(value).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.borderSubtle).frame(height: 1) } }
        .accessibilityElement(children: .combine)
        .accessibilityValue(ok ? "ผ่าน" : "ไม่ผ่าน")
    }

    // MARK: card 4 | shade

    /// What the simulation depends on, so it runs again when any of it changes.
    var shadeKey: String {
        let l = TankLayout.current(values)
        return [String(l?.count ?? 0), values.text(TankLayout.Key.offX), values.text(TankLayout.Key.offY), values.text(TankLayout.Key.off),
                values.choice("shade") ?? "", values.multi("shadeDir").joined(), values.text(TankShade.Key.height),
                values.text(TankShade.Key.distance), values.text(Tank.Key.azimuth), String(Tank.exposed(values) ?? 0), job.values.text("gps"),
                values.text(TankShade.ItemKey.items)]
            .joined(separator: "|")
    }

    func refreshShade() async {
        let v = values, site = RoofMount.site(job), lat = site.latitude ?? RoofMount.defaultLatitude, lon = site.longitude
        shadeBusy = true
        let r = await Task.detached(priority: .userInitiated) { TankShade(v, latitude: lat, longitude: lon) }.value
        guard !Task.isCancelled else { return }
        shadeResult = r
        shadeBusy = false
    }

    /// `เงาบัง`: the year's losses, the recommendation, a moment's shaded panels and the month × hour map.
    func shadeCard(_ l: TankLayout) -> some View {
        let s = shadeResult
        let chip = shadeBusy ? ("กำลังคำนวณ…", Theme.inkMuted, Theme.hairline)
            : s.map { (String(format: "เสีย %.1f%%", $0.totalLoss * 100), $0.objectLoss >= 0.01 ? Theme.pending : Theme.okTick,
                       $0.objectLoss >= 0.01 ? Theme.pendingSoft : Theme.okSoft) } ?? ("-", Theme.inkMuted, Theme.hairline)
        return phoneCard(4, "เงาบัง | จำลองทั้งปี", chip: chip) {
            if let s {
                let tiles: [(String, String)] = [("เงาแถวหน้า", String(format: "%.1f%%", s.rowLoss * 100)),
                                                 ("เงาสิ่งบัง", String(format: "%.1f%%", s.objectLoss * 100)),
                                                 ("สูญเสียรวม", String(format: "%.1f%%", s.totalLoss * 100)),
                                                 ("เสียจากสิ่งบัง", String(format: "%.1f MWh/ปี", s.objectMWh))]
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.1).font(.sarabunFixed(16, .bold)).monospacedDigit()
                            Text(t.0).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Self.track, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityElement(children: .combine)
                    }
                }
                Text(s.recommendation(values)).font(.sarabunFixed(13.5)).foregroundStyle(s.objectLoss >= 0.01 ? Theme.dangerText : Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                shadeMoments(s, l)
                let map = TankDrawings.heatMap(s)
                GeometryReader { g in SketchCanvas(ops: map.ops, fit: SketchFit(map.width, map.height, in: g.size)) }
                    .aspectRatio(map.width / map.height, contentMode: .fit)
                    .accessibilityLabel("แผนที่สัดส่วนแผงที่โดนเงา รายเดือนและรายชั่วโมง")
            } else if !shadeBusy {
                Text("ยังไม่มีผังแผง").font(.sarabunFixed(13.5)).foregroundStyle(Theme.inkMuted)
            }
        }
        .task(id: shadeKey) { await refreshShade() }
        .id("shadeCard")
    }

    /// A moment of the year on the plan: the panels without direct sun in orange.
    @ViewBuilder func shadeMoments(_ s: TankShade, _ l: TankLayout) -> some View {
        if s.snapshots.indices.contains(shadeMoment), let plan = TankDrawings.layoutPlan(values, l, shaded: s.snapshots[shadeMoment].shaded) {
            Menu {
                ForEach(Array(s.snapshots.enumerated()), id: \.offset) { i, m in
                    Button(m.title + " | \(m.shaded.count) แผง") { shadeMoment = i }
                }
            } label: {
                Label(s.snapshots[shadeMoment].title + " | เงาบนแผง \(s.snapshots[shadeMoment].shaded.count) แผง", systemImage: "sun.max")
                    .font(.sarabunFixed(14, .bold)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            GeometryReader { g in SketchCanvas(ops: plan.ops, fit: SketchFit(plan.width, plan.height, in: g.size)) }
                .aspectRatio(plan.width / plan.height, contentMode: .fit)
                .background(Theme.paper)
                .accessibilityLabel("ผังแผง แผงที่โดนเงาเป็นสีส้ม")
        }
    }

    /// The standard drawings: the row section and the tank sections (`TankDrawings`).
    var drawingSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    let l = TankLayout.current(values)
                    let sketches = [l.map { TankDrawings.tableSection($0.params) } ?? TankDrawings.tableSection(TankLayout.defaults(values))]
                        + [l.flatMap { TankDrawings.tableFront($0) }].compactMap { $0 }
                        + [false, true].compactMap { TankDrawings.section(values, across: $0) }
                    ForEach(Array(sketches.enumerated()), id: \.offset) { _, sk in
                        GeometryReader { g in SketchCanvas(ops: sk.ops, fit: SketchFit(sk.width, sk.height, in: g.size)) }
                            .aspectRatio(sk.width / sk.height, contentMode: .fit)
                            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
            }
            .navigationTitle("แบบ \(Self.drawingRef) | รูปตัด")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { drawingOpen = false } } }
        }
        .foregroundStyle(Theme.navy)
        .presentationDetents([.large])
    }
}
#endif
