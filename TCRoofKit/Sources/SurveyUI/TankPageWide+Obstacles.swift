#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// D1 sub-step 2 "สิ่งกีดขวาง" on iPhone (docs/ui/survey-d1-obstacles-iphone, 390 × 844): verify on site. The tank's
/// standard vents and hatches (`TankPoints`) are on the plan; the surveyor marks each one มีตรงแบบ / ไม่มีจริง, moves
/// it by drag or by typed distances, and adds the ones missing from the layout. Card 1 also switches to the shading
/// questions. The points live in `obst`, so the PDF, Excel and the iPad page keep reading them.
extension TankPageWide {
    var phoneObstacleCards: some View {
        VStack(spacing: 12) {
            phoneTabs
            obstaclePlanCard
            if !obsShade { pointCard }
        }
        .onAppear(perform: openPoints)
        .confirmationDialog("ลบจุดนี้?", isPresented: $deleteAsk, titleVisibility: .visible) {
            Button("ลบจุด " + (selectedPoint?.label ?? ""), role: .destructive, action: deletePoint)
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("ลบได้เฉพาะจุดที่เพิ่มหน้างาน")
        }
        .sheet(isPresented: $rowAsk) { rowSheet }
    }

    /// First open: the standard points from the tank's size, and the first point still to check selected.
    func openPoints() {
        update { TankPoints.seed(&$0) }
        if selectedPoint == nil { pointSel = TankPoints.pending(values).first?.id ?? TankPoints.points(values).first?.id }
    }

    var selectedPoint: Obstacle? { pointSel.flatMap { id in TankPoints.points(values).first { $0.id == id } } }

    // MARK: card 1 · plan

    var obstaclePlanCard: some View {
        let c = TankPoints.checked(values), all = c.total > 0 && c.n == c.total
        let chip = all ? ("✓ ตรวจครบ", Home.badgeOkText, Home.badgeOkBg) : ("ตรวจแล้ว \(c.n)/\(c.total)", Home.pending, Home.badgeWarnBg)
        return phoneCard(1, "แปลนสิ่งกีดขวาง", chip: chip) {
            obstacleSegment
            if obsShade { shadeFields } else {
                obstaclePlanFrame
                obstacleLegend
            }
        }
    }

    /// `บนหลังคา · 15 จุด` / `เงาบัง · <answer>`
    var obstacleSegment: some View {
        let n = TankPoints.points(values).count, shade = values.choice("shade")
        let items = [(false, "บนหลังคา · \(n) จุด"), (true, "เงาบัง" + (shade.map { " · " + $0 } ?? ""))]
        return HStack(spacing: 3) {
            ForEach(items, id: \.0) { item in
                let on = obsShade == item.0
                Button { withAnimation(.easeOut(duration: 0.15)) { obsShade = item.0 } } label: {
                    Text(item.1).font(.system(size: 14, weight: on ? .bold : .regular)).foregroundStyle(on ? Home.navy : Home.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 8).fill(Color.white).shadow(color: Home.navy.opacity(0.2), radius: 1.5, y: 1) }
                        }
                        .contentShape(Rectangle().inset(by: -3))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(minHeight: 44)
        .background(Home.disabledFill, in: RoundedRectangle(cornerRadius: 10))
    }

    var obstaclePlanFrame: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                if Tank.hasSize(values) {
                    TankPointsPlan(values: values, selected: $pointSel) { id, x, y in update { TankPoints.move(&$0, id, x: x, y: y) } }
                } else {
                    emptyPlan.frame(height: 260)
                }
                Button { obsZoom = 1; obsFull = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Home.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Home.navy.opacity(0.2), radius: 2, y: 1)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("ขยายแปลนเต็มจอ")
                .disabled(!Tank.hasSize(values))
            }
            Text(Tank.hasSize(values) ? "แตะจุดเพื่อเลือก · ลากเพื่อย้าย" : "เลือกขนาดถังในขั้นที่ 1 ก่อน")
                .font(.system(size: 11)).foregroundStyle(Home.muted)
                .padding(.horizontal, 10).padding(.bottom, 8)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.hairline))
    }

    /// The legend draws "ยังไม่ยืนยัน" dashed as on the board; the plan draws it solid.
    var obstacleLegend: some View {
        let items: [(String, Color, Bool, CGFloat)] = [("ยังไม่ยืนยัน", Home.primary, true, 0), ("ยืนยันแล้ว", Home.pillOn, false, 0),
                                                        ("ไม่มีจริง", Home.danger, true, 0), ("จุดที่เลือก", Home.pointSelected, false, 3)]
        return HStack(spacing: 12) {
            ForEach(items, id: \.0) { t, c, dashed, r in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: r).strokeBorder(c, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : []))
                        .frame(width: 10, height: 10)
                    Text(t).font(.system(size: 11)).foregroundStyle(Home.muted).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The section's shading questions, as on the form.
    @ViewBuilder var shadeFields: some View {
        if let i = index {
            let fields = Schema.spec(.tank).fields
            VStack(alignment: .leading, spacing: 4) {
                ForEach(["shade", "shadeFrom", "shadeDir", "shadeNote"].compactMap { id in fields.first { $0.id == id } }) { f in
                    if f.isVisible(job.modules[i].values) {
                        FieldView(spec: f, values: $job.modules[i].values, jobID: job.id, moduleType: .tank, gps: job.values.text("gps"))
                    }
                }
            }
        }
    }

    /// The plan full screen, zoomed by pinch or − / +, with the selected point's status under it.
    var obstacleFullScreen: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { g in
                    let w = g.size.width * obsZoom
                    ScrollView([.horizontal, .vertical]) {
                        TankPointsPlan(values: values, selected: $pointSel) { id, x, y in update { TankPoints.move(&$0, id, x: x, y: y) } }
                            .frame(width: w, height: w * 300 / 330)
                            .background(Color.white)
                    }
                    .scrollIndicators(.hidden)
                    .simultaneousGesture(MagnifyGesture().onChanged { m in obsZoom = min(4, max(1, obsZoom * sqrt(m.magnification))) })
                }
                if let p = selectedPoint {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("จุด \(p.label) · \(TankPoints.kindName(p.kind))").font(.system(size: 16, weight: .bold))
                        statusChoice(p)
                    }
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(16)
            .background(Home.lockedCard)
            .navigationTitle("แปลนสิ่งกีดขวาง")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { obsZoom = max(1, obsZoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("ย่อ").disabled(obsZoom <= 1)
                    Button { obsZoom = min(4, obsZoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("ขยาย").disabled(obsZoom >= 4)
                }
                ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { obsFull = false } }
            }
        }
        .foregroundStyle(Home.navy)
    }

    // MARK: card 2 · the selected point

    @ViewBuilder var pointCard: some View {
        if let p = selectedPoint {
            let moved = TankPoints.moved(p)
            let chip = !TankPoints.isStandard(p) ? ("เพิ่มหน้างาน", Home.muted, Home.primarySoft)
                : moved ? ("ย้ายแล้ว", Home.badgeOkText, Home.badgeOkBg) : ("ตามแบบ", Home.muted, Home.primarySoft)
            phoneCard(2, "จุด \(p.label) · \(TankPoints.kindName(p.kind))", chip: chip) {
                pointPicker(p)
                field("สถานะ", required: true) { statusChoice(p) }
                pointDistances(p)
                pointInfo(p)
                field("เพิ่ม / แก้ไข", aside: "กรณีไม่มีในแบบ") { pointActions(p) }
            }
        } else if Tank.hasSize(values) {
            phoneCard(2, "จุดสิ่งกีดขวาง", chip: ("ไม่มีจุด", Home.muted, Home.primarySoft)) {
                Text("ยังไม่มีจุดบนแปลน").font(.system(size: 14)).foregroundStyle(Home.muted)
                field("เพิ่ม / แก้ไข", aside: "กรณีไม่มีในแบบ") { pointActions(nil) }
            }
        }
    }

    /// `‹` the selected point and the next ones to check `›`; ‹ › step through the points still to check (all points
    /// once every one is checked).
    func pointPicker(_ p: Obstacle) -> some View {
        let pending = TankPoints.pending(values), ring = pending.isEmpty ? TankPoints.points(values) : pending
        let chips = [p] + Array(pending.filter { $0.id != p.id }.prefix(3))
        func step(_ d: Int) {
            guard !ring.isEmpty else { return }
            let all = TankPoints.points(values), at = all.firstIndex { $0.id == p.id } ?? 0
            // the next / previous one of the ring in list order from the selected point
            let order = ring.compactMap { o in all.firstIndex { $0.id == o.id }.map { (o.id, $0) } }
            let next = d > 0 ? (order.first { $0.1 > at } ?? order.first) : (order.last { $0.1 < at } ?? order.last)
            if let n = next { withAnimation(.easeOut(duration: 0.15)) { pointSel = n.0 } }
        }
        return HStack(spacing: 6) {
            arrowChip("‹", label: "จุดก่อนหน้าที่ยังไม่ตรวจ") { step(-1) }
            ForEach(chips) { o in
                let on = o.id == p.id
                Button { withAnimation(.easeOut(duration: 0.15)) { pointSel = o.id } } label: {
                    Text(o.label).font(.system(size: 14, weight: .heavy)).foregroundStyle(on ? Color.white : Home.primary).lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Home.pointSelected : Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            if !on { RoundedRectangle(cornerRadius: 10).strokeBorder(Home.primary, style: StrokeStyle(lineWidth: 1.5, dash: o.status.isEmpty ? [4, 3] : [])) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("จุด \(o.label)" + (o.status.isEmpty ? " ยังไม่ตรวจ" : ""))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            arrowChip("›", label: "จุดถัดไปที่ยังไม่ตรวจ") { step(1) }
        }
    }

    func arrowChip(_ t: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 18, weight: .bold)).foregroundStyle(Home.primary)
                .frame(width: 44, height: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// `มีตรงแบบ` (mint when on) / `ไม่มีจริง` (danger tint when on).
    func statusChoice(_ p: Obstacle) -> some View {
        HStack(spacing: 8) {
            statusButton(p, TankPoints.ok, "มีตรงแบบ", on: Home.mint, ink: Home.navy)
            statusButton(p, TankPoints.absent, "ไม่มีจริง", on: Home.danger.opacity(0.14), ink: Home.red)
        }
    }

    func statusButton(_ p: Obstacle, _ s: String, _ title: String, on bg: Color, ink: Color) -> some View {
        let on = p.status == s
        return Button {
            update { TankPoints.setStatus(&$0, p.id, on ? "" : s) }
        } label: {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(on ? ink : Home.navy).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? bg : Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(on && s == TankPoints.absent ? Home.danger : Home.navy.opacity(on ? 0.2 : 0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("สถานะ " + title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func pointDistances(_ p: Obstacle) -> some View {
        let r = TankPoints.rect(p)
        return HStack(alignment: .top, spacing: 8) {
            field("ห่างผนังซ้าย") {
                PointDistanceField(value: r?.x, label: "ห่างผนังซ้าย") { x in update { TankPoints.move(&$0, p.id, x: x, y: nil) } }
            }
            field("ห่างผนังบน") {
                PointDistanceField(value: r?.y, label: "ห่างผนังบน") { y in update { TankPoints.move(&$0, p.id, x: nil, y: y) } }
            }
        }
        .id(p.id)
    }

    /// "แนวเดียวกับ V10 · ไม่ทับจุดอื่น" in mint; an overlap or a point outside the tank in orange.
    @ViewBuilder func pointInfo(_ p: Obstacle) -> some View {
        if let c = TankPoints.check(values, p.id) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: c.warning ? "exclamationmark.triangle" : "info.circle").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.warning ? Home.pending : Home.okTick)
                Text(c.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(c.warning ? Home.badgeWarnBg : Home.badgeOkBg, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
    }

    /// `+ ช่องระบาย` `+ ช่องลงถัง` / `ทำซ้ำเป็นแถว` `ลบจุดนี้` (only points added on site).
    func pointActions(_ p: Obstacle?) -> some View {
        let canDelete = p.map(TankPoints.canDelete) ?? false
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            actionButton("+ ช่องระบาย", ink: Home.primary, border: Home.primary) { addPoint(TankPoints.vent) }
            actionButton("+ ช่องลงถัง", ink: Home.primary, border: Home.primary) { addPoint(TankPoints.hatch) }
            actionButton("ทำซ้ำเป็นแถว", ink: Home.navy, border: Home.navy.opacity(0.35)) {
                rowCount = 3; rowSpacing = TankPoints.rowSpacing(values); rowAsk = true
            }
            .disabled(p == nil).opacity(p == nil ? 0.45 : 1)
            actionButton("ลบจุดนี้", ink: Home.red, border: Home.danger.opacity(0.45)) { deleteAsk = true }
                .disabled(!canDelete).opacity(canDelete ? 1 : 0.45)
                .accessibilityHint(canDelete ? "" : "จุดตามแบบใช้ ไม่มีจริง แทนการลบ")
        }
        .disabled(!Tank.hasSize(values))
    }

    func actionButton(_ title: String, ink: Color, border: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(border))
        }
        .buttonStyle(.plain)
    }

    func addPoint(_ kind: String) {
        var id: UUID?
        update { id = TankPoints.add(&$0, kind: kind) }
        if let id { withAnimation(.easeOut(duration: 0.15)) { pointSel = id } }
    }

    func deletePoint() {
        guard let p = selectedPoint else { return }
        let all = TankPoints.points(values), at = all.firstIndex { $0.id == p.id } ?? 0
        update { TankPoints.delete(&$0, p.id) }
        let rest = TankPoints.points(values)
        pointSel = rest[safe: at]?.id ?? rest.last?.id
    }

    /// "ทำซ้ำเป็นแถว": how many copies and how far apart, to the right along the selected point's row.
    var rowSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("ทำซ้ำ \(selectedPoint?.label ?? "") ไปทางขวาตามแถวเดียวกัน").font(.system(size: 14)).foregroundStyle(Home.muted)
                field("จำนวนจุดที่เพิ่ม") {
                    Stepper(value: $rowCount, in: 1...20) {
                        Text("\(rowCount) จุด").font(.system(size: 16, weight: .semibold)).monospacedDigit()
                    }
                    .frame(minHeight: 44)
                }
                field("ระยะห่าง") {
                    TankStepper(value: rowSpacing, step: 0.05, range: 0.5...100, label: "ระยะห่าง", unit: "ม.", glyph: 17) { d in
                        rowSpacing = d ?? TankPoints.rowSpacing(values)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("ทำซ้ำเป็นแถว")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { rowAsk = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เพิ่ม \(rowCount) จุด") {
                        guard let p = selectedPoint else { rowAsk = false; return }
                        var ids: [UUID] = []
                        update { ids = TankPoints.repeatRow(&$0, p.id, count: rowCount, spacing: rowSpacing) }
                        if let last = ids.last { pointSel = last }
                        rowAsk = false
                    }
                }
            }
        }
        .foregroundStyle(Home.navy)
        .presentationDetents([.height(320)])
    }
}

/// A distance in metres with 2 decimals, typed on the number pad: the value, `ม.` and the number-pad icon.
struct PointDistanceField: View {
    let value: Double?
    let label: String
    let set: (Double) -> Void
    @State var typed = ""
    @FocusState var typing: Bool

    func text(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "" }

    var body: some View {
        HStack(spacing: 4) {
            TextField("0.00", text: $typed)
                .keyboardType(.decimalPad).focused($typing)
                .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                .onSubmit(commit)
                .onChange(of: typing) { _, on in if !on { commit() } }
                .accessibilityLabel(label + " (เมตร)")
            Text("ม.").font(.system(size: 13)).foregroundStyle(Home.borderControl).accessibilityHidden(true)
            Image(systemName: "keyboard").font(.system(size: 14)).foregroundStyle(Home.primary).accessibilityHidden(true)
        }
        .padding(.leading, 12).padding(.trailing, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(typing ? Home.primary : Home.navy.opacity(0.35), lineWidth: typing ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { typing = true }
        .onAppear { typed = text(value) }
        .onChange(of: value) { _, v in if !typing { typed = text(v) } }
        .toolbar {
            if typing {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("เสร็จ") { typing = false }
                }
            }
        }
    }

    func commit() {
        if let v = NumberInput.value(typed.trimmingCharacters(in: .whitespaces)) { set(v) }
        typed = text(value)
    }
}
#endif
