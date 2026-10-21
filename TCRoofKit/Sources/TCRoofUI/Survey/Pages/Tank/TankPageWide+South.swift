#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// D1 sub-step 3: the true-south comparison (docs/specs/tank-mounting-layout.md §3a, comparison only). After
/// `หาผังที่ได้พลังงานมากที่สุด` it is worked out off the main thread when the walls are a degree or more off south; card 1
/// shows one line, and `ดูผังเทียบ` opens the turned plan beside the chosen layout's numbers. Nothing is stored.
extension TankPageWide {
    func compareSouth(_ v: Values, latitude: Double, wall: TankLayout.EnergySearch) {
        guard TankLayout.comparesSouth(v) else { return }
        southBusy = true
        Task { @MainActor in
            let c = await Task.detached(priority: .utility) { TankLayout.compareSouth(v, latitude: latitude, wall: wall) }.value
            // a newer search or layout may have replaced the one compared
            if energySearch?.chosen == wall.chosen { southCompare = c }
            southBusy = false
        }
    }

    @ViewBuilder var southRow: some View {
        if southBusy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.navy)
                Text("กำลังเทียบกับแถวหันทิศใต้จริง…").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
            }
        } else if let c = southCompare {
            HStack(alignment: .center, spacing: 8) {
                Text(c.line).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { southOpen = true } label: {
                    Text("ดูผังเทียบ").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 10).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: the sheet

    var southSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let c = southCompare {
                        Text(String(format: "แถวหันทิศใต้จริง หมุนจากผนังถัง %.0f° | เทียบเท่านั้น ผังที่ใช้ยังขนานผนังถังตามมาตรฐานทีม",
                                    abs(c.south.wallOffset)))
                            .font(.sarabunFixed(14)).fixedSize(horizontal: false, vertical: true)
                        southPlan(c.south)
                        southTable(c)
                        Text(southVerdict(c)).font(.sarabunFixed(14, .bold)).fixedSize(horizontal: false, vertical: true)
                        Text("พลังงานเป็นค่าประมาณจากแบบจำลองแดดฟ้าใส หักเงาแถวหน้าและสิ่งบังรอบถัง ใช้เทียบกันเท่านั้น")
                            .font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .navigationTitle("เทียบหันทิศใต้จริง")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { southOpen = false } } }
        }
        .foregroundStyle(Theme.navy)
        .presentationDetents([.large])
    }

    func southVerdict(_ c: TankLayout.SouthComparison) -> String {
        c.change < 0
            ? String(format: "ขนานผนังถังได้พลังงานมากกว่า %.1f%% | ใช้ผังขนานผนังถังต่อ", -c.change * 100)
            : String(format: "หันทิศใต้จริงได้พลังงานมากกว่า %.1f%% | แต่โต๊ะเอียงจากผนัง ติดตั้งและเดินรางยากกว่า", c.change * 100)
    }

    /// The tank plan with the turned modules, their posts and the obstacles.
    @ViewBuilder func southPlan(_ s: TankLayout.TrueSouth) -> some View {
        if let sketch = TankPlan.compact(values), let f = TankPlan.compactFrame(values) {
            GeometryReader { g in
                let fit = SketchFit(sketch.width, sketch.height, in: g.size)
                ZStack {
                    SketchCanvas(ops: sketch.ops, fit: fit)
                    Canvas { ctx, _ in
                        ctx.translateBy(x: fit.ox, y: fit.oy)
                        ctx.scaleBy(x: fit.s, y: fit.s)
                        func pt(_ p: Pt) -> CGPoint { CGPoint(x: f.ox + p.x * f.k, y: f.oy + p.y * f.k) }
                        for o in TankPoints.points(values) where !o.isAbsent && !TankPoints.onWall(o.kind) {
                            guard let r = TankPoints.rect(o) else { continue }
                            let b = CGRect(x: f.ox + r.x * f.k, y: f.oy + r.y * f.k, width: r.w * f.k, height: r.h * f.k).insetBy(dx: -1, dy: -1)
                            ctx.stroke(Path(b), with: .color(Theme.borderControl.opacity(0.6)),
                                       style: StrokeStyle(lineWidth: 0.8, dash: o.kind == TankPoints.vent ? [] : [2, 1.5]))
                        }
                        for m in s.modules {
                            var p = Path(); p.addLines(m.corners.map(pt)); p.closeSubpath()
                            ctx.fill(p, with: .color(Theme.panelBlue.opacity(0.85)))
                            ctx.stroke(p, with: .color(Theme.paper), lineWidth: 0.5)
                        }
                        for q in s.posts {
                            let c = pt(q)
                            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 0.9, y: c.y - 0.9, width: 1.8, height: 1.8)), with: .color(Theme.navy))
                        }
                    }
                }
            }
            .aspectRatio(sketch.width / sketch.height, contentMode: .fit)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement()
            .accessibilityLabel("ผังแถวหันทิศใต้จริง \(s.count) แผง \(s.tables) โต๊ะ")
        }
    }

    /// Both layouts side by side: gap, modules, kWp, kWh/kWp, row shade, MWh a year.
    func southTable(_ c: TankLayout.SouthComparison) -> some View {
        let w = c.wall, s = c.south
        let rows: [(String, String, String)] = [
            ("ระยะห่างแถว", String(format: "%.2f ม.", w.gap), String(format: "%.2f ม.", s.gap)),
            ("แผง", "\(w.modules)", "\(s.count)"),
            ("kWp", String(format: "%.1f", w.kWp), String(format: "%.1f", s.kWp)),
            ("เงาแถวหน้า", String(format: "%.1f%%", w.rowLoss * 100), String(format: "%.1f%%", s.rowLoss * 100)),
            ("MWh/ปี", String(format: "%.1f", w.mwh), String(format: "%.1f", s.mwh)),
        ]
        return VStack(spacing: 0) {
            southTableRow("", "ขนานผนังถัง (ใช้)", "หันทิศใต้จริง", bold: true)
            ForEach(rows, id: \.0) { r in
                Divider()
                southTableRow(r.0, r.1, r.2, bold: r.0 == "MWh/ปี")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle))
    }

    func southTableRow(_ a: String, _ b: String, _ c: String, bold: Bool) -> some View {
        HStack {
            Text(a).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Theme.inkMuted)
            Text(b).frame(maxWidth: .infinity, alignment: .trailing)
            Text(c).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.sarabunFixed(14, bold ? .bold : .regular))
        .frame(minHeight: 36)
    }
}
#endif
