#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

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
        if let l = TankLayout.current(values) {
            layoutSummaryCard(l)
            layoutChecksCard(l)
        }
        dxfButton
    }

    /// iPad: the plan card on the left, the materials and checks on the right; one column in portrait.
    @ViewBuilder var padLayoutStep: some View {
        let next = nextButton("ถัดไป · ภาพถ่าย ›") { withAnimation { tab = 4 } }
        if stacked {
            layoutSheets(ScrollView {
                VStack(spacing: 14) {
                    layoutPlanCard.frame(maxWidth: 640)
                    layoutSideCards.frame(maxWidth: 640)
                    next.frame(maxWidth: 640)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden))
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
            Button(layoutAsk == .max ? "หาผังแผงมากสุด" : "จัดแผงใหม่", role: .destructive) {
                if let a = layoutAsk { runLayout(a) }
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("แผงที่ปิดหรือโต๊ะที่เอาออกจะกลับมาตามผังอัตโนมัติ")
        }
        .sheet(isPresented: $drawingOpen) { drawingSheet }
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

    /// `จัดแผงใหม่` / `หาผังแผงมากสุด`: asks first when panels were edited by hand.
    func askLayout(_ a: LayoutRun) {
        if TankLayout.off(values).isEmpty { runLayout(a) } else { layoutAsk = a }
    }

    func runLayout(_ a: LayoutRun) {
        layoutAsk = nil
        switch a {
        case .auto: update { TankLayout.save(&$0, TankLayout.auto($0), off: []) }
        case .max:
            let v = values
            layoutSearching = true
            Task { @MainActor in
                let p = await Task.detached(priority: .userInitiated) { TankLayout.best(v) }.value
                if let p { update { TankLayout.save(&$0, p, off: []) } }
                layoutSearching = false
            }
        }
    }

    // MARK: card 1 · plan

    var layoutAside: String {
        "ตามแบบ \(Self.drawingRef) · เอียง " + String(format: "%.1f°", TankLayout.defaults().tilt)
    }

    var layoutPlanCard: some View {
        phoneCard(1, "การวางผังแผง", chip: (layoutAside, Theme.inkMuted, Color.clear)) {
            layoutSegment
            layoutPlanFrame
            HStack(spacing: 8) {
                Button { askLayout(.auto) } label: {
                    Text("จัดแผงใหม่").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary))
                }
                .buttonStyle(.plain)
                Button { askLayout(.max) } label: {
                    Group {
                        if layoutSearching { ProgressView().tint(Theme.navy) } else { Text("หาผังแผงมากสุด") }
                    }
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.mint, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .disabled(layoutSearching)
            }
            .disabled(!Tank.hasSize(values))
        }
    }

    /// `เลื่อนผัง` / `แก้แผง`
    var layoutSegment: some View {
        HStack(spacing: 3) {
            ForEach([(false, "เลื่อนผัง"), (true, "แก้แผง")], id: \.0) { item in
                let on = layoutEditing == item.0
                Button { withAnimation(.easeOut(duration: 0.15)) { layoutEditing = item.0 } } label: {
                    Text(item.1).font(.system(size: 14, weight: on ? .bold : .regular)).foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 8).fill(Color.white).shadow(color: Theme.navy.opacity(0.2), radius: 1.5, y: 1) }
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
                        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Theme.navy.opacity(0.2), radius: 2, y: 1)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("ขยายแปลนเต็มจอ")
                .disabled(TankLayout.current(values) == nil)
            }
            Text(Tank.hasSize(values) ? "แผงโมโน \(fmt(TankLayout.defaults().moduleKW * 1000)) W · แตะแผงเพื่อแก้" : "เลือกขนาดถังในขั้นที่ 1 ก่อน")
                .font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 10).padding(.bottom, 8)
        }
        .background(Color.white)
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
                            layoutPlan(l).frame(width: w, height: w * 300 / 330).background(Color.white)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .simultaneousGesture(MagnifyGesture().onChanged { m in layoutZoom = min(4, max(1, layoutZoom * sqrt(m.magnification))) })
                }
                if let l = TankLayout.current(values) {
                    Text("\(l.count) แผง · " + String(format: "%.1f kWp", l.kWp)).font(.system(size: 15, weight: .bold))
                }
            }
            .padding(16)
            .background(Theme.background)
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

    // MARK: card 2 · summary and materials

    func layoutSummaryCard(_ l: TankLayout) -> some View {
        let b = l.bom, w = fmt(l.params.moduleKW * 1000)
        let rows: [(String, String)] = [
            ("แผง \(w) W", "\(l.count)"),
            ("กำลังรวม", String(format: "%.1f kWp", l.kWp)),
            ("แถว · โต๊ะแผง", "\(l.rows) · \(l.builtTables.count)"),
            ("เสา + โครงหน้า", "\(b.posts)"),
            ("ฐานราก", "\(b.footings) จุด"),
            ("ราง (4 เส้น)", "\(Int(b.railLength.rounded())) ม."),
            ("Mid / End clamp", "\(b.midClamps) / \(b.endClamps)"),
            ("Rail clamp", "\(b.railClamps)"),
            ("ค้ำยันไขว้", "\(b.braces) ชุด"),
        ]
        let chip = ("\(l.count) แผง · " + String(format: "%.1f kWp", l.kWp), Theme.okTick, Theme.okSoft)
        return phoneCard(2, "สรุป · วัสดุโครงสร้าง", chip: chip) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.0).font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
                        Spacer(minLength: 8)
                        Text(r.1).font(.system(size: 15, weight: .bold)).monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.borderSubtle).frame(height: 1) } }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: card 3 · checks

    func layoutChecksCard(_ l: TankLayout) -> some View {
        let c = l.checks
        let chip = c.allOK ? ("✓ 3/3", Theme.okTick, Theme.okSoft) : ("\(c.passed)/3", Theme.pending, Theme.pendingSoft)
        return phoneCard(3, "ตรวจสอบก่อนไปต่อ", chip: chip) {
            VStack(spacing: 0) {
                // the panel underside above the vent, less the vent's height
                checkRow("ใต้คานเหนือปล่อง (แผงทับได้)", c.ventHeadroom.map { String(format: "%.2f ม.", $0) } ?? "ไม่มีปล่องใต้แผง", ok: c.ventsOK, first: true)
                checkRow("ขอบถังถึงขอบแผง ≥ " + String(format: "%.2f ม.", l.params.clearance), c.edge.map { String(format: "%.2f ม.", $0) } ?? "-", ok: c.edgeOK)
                checkRow("ขาโครงสร้างไม่ชนสิ่งกีดขวาง", "เสา \(c.posts) ต้น · ตัดแผง \(c.cutColumns) คอลัมน์", ok: c.legsOK)
            }
            Button { drawingOpen = true } label: {
                Text("ดูแบบ \(Self.drawingRef) · ภาพตัดโต๊ะแผง · ฐานเสา").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary))
            }
            .buttonStyle(.plain)
        }
    }

    func checkRow(_ title: String, _ value: String, ok: Bool, first: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark" : "exclamationmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(ok ? Theme.success : Theme.warning))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Text(value).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.borderSubtle).frame(height: 1) } }
        .accessibilityElement(children: .combine)
        .accessibilityValue(ok ? "ผ่าน" : "ไม่ผ่าน")
    }

    /// The standard drawing B1-C3: not in the app yet.
    var drawingSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundStyle(Theme.disabledText)
                Text("แบบ \(Self.drawingRef) · ภาพตัดโต๊ะแผง · ฐานเสา").font(.system(size: 16, weight: .bold))
                Text("ยังไม่มีไฟล์แบบในแอป").font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .navigationTitle("แบบ \(Self.drawingRef)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { drawingOpen = false } } }
        }
        .foregroundStyle(Theme.navy)
        .presentationDetents([.medium])
    }
}
#endif
