#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// D1 sub-step 2 on iPad (docs/ui/survey-d1-obstacles-ipad, Part A): the plan with its legend and `เลิกทำ` on the
/// left; on the right the `บนหลังคา | เงาบัง` segment and the selected point: a three-way status, distances moved
/// alone or with the point's row / column, an inline `ทำซ้ำเป็นแถว`, and the four action tiles. The iPhone keeps
/// `phoneObstacleCards`.
extension TankPageWide {
    // MARK: left | plan

    var padObstaclePlanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if obsShade {
                AnyView(shadeFields)
            } else {
                if TankDesign.current(values) != nil { AnyView(compareSegment) }
                if stacked {
                    AnyView(padPlan)
                    AnyView(padLegend)
                } else {
                    HStack(alignment: .bottom, spacing: 16) {
                        AnyView(padPlan)
                        AnyView(padLegend).frame(width: 210)
                    }
                }
                if obsCompare && TankDesign.current(values) != nil { AnyView(differenceList) }
                AnyView(designRow)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tcCard()
    }

    /// The points' row / column being moved together (empty for a single point).
    var padGroup: [UUID] {
        guard let p = selectedPoint, groupMode != .single else { return [] }
        return TankPoints.group(values, of: p.id, mode: groupMode).map(\.id)
    }

    /// The layout's opening → panel clearance (the team's tank standard): the keep-out drawn around the selected point.
    var keepOut: Double { TankLayout.params(values)?.openClear ?? TankLayout.defaults(values).openClear }

    @ViewBuilder var padPlan: some View {
        ZStack(alignment: .bottomTrailing) {
            if Tank.hasSize(values) {
                TankPointsPlan(values: values, selected: $pointSel, move: { id, x, y in dropPoint(id, x, y) },
                               compare: obsCompare && TankDesign.current(values) != nil, group: padGroup, keepOut: keepOut)
            } else {
                emptyPlan.frame(height: 360)
            }
            Button { obsZoom = 1; obsFull = true } label: {
                Image(systemName: "arrow.down.left.and.arrow.up.right").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Theme.navy.opacity(0.2), radius: 2, y: 1)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ขยายแปลนเต็มจอ")
            .disabled(!Tank.hasSize(values))
        }
        .frame(maxWidth: .infinity)
    }

    /// A drop on the plan: the point alone, or its whole row / column by the same step.
    func dropPoint(_ id: UUID, _ x: Double, _ y: Double) {
        let group = padGroup
        guard group.count > 1, group.contains(id), let r = TankPoints.points(values).first(where: { $0.id == id }).flatMap(TankPoints.rect) else {
            update { TankPoints.move(&$0, id, x: x, y: y) }
            return
        }
        moveGroup(group, dx: x - r.x, dy: y - r.y)
    }

    func moveGroup(_ group: [UUID], dx: Double, dy: Double) {
        var cut = false
        update { cut = TankPoints.move(&$0, group: group, dx: dx, dy: dy).clamped }
        obsNotice = cut ? "เลื่อนได้ถึงผนังถัง | จุดในแนวเดียวกันไม่ออกนอกถัง" : nil
    }

    var padLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("สัญลักษณ์").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
            legendRow(symbol: "plus.square", "V | ช่องระบาย")
            legendRow(symbol: "square", "H | ช่องลงถัง")
            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
            swatchRow(Theme.primary, dash: true, "จากแบบ ยังไม่ยืนยัน")
            swatchRow(Theme.navySolid, dash: false, "ยืนยันแล้ว")
            swatchRow(Theme.danger, dash: true, "ไม่มีจริง")
            swatchRow(Theme.warning, dash: false, "จุดที่เลือก", fill: Theme.warning.opacity(0.18))
            HStack(spacing: 8) {
                Rectangle().fill(Theme.teal).frame(width: 18, height: 1.5)
                Text("แนวเดียวกัน").font(.sarabunFixed(13)).foregroundStyle(Theme.navy)
            }
            swatchRow(Theme.danger.opacity(0.6), dash: true, "เว้นระยะ " + String(format: "%.2f", keepOut) + " ม. (จุดที่เลือก)")
            Text("กดค้างแล้วลากเพื่อย้าย | ใกล้แนวจะดูดเข้าแนวเอง").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button { undoStep() } label: {
                Label("เลิกทำ", systemImage: "arrow.uturn.backward").font(.sarabunFixed(15, .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
            .disabled(undo.back.isEmpty)
            .accessibilityIdentifier("obstacleUndo")
        }
    }

    func legendRow(symbol: String, _ t: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.navy).frame(width: 18)
            Text(t).font(.sarabunFixed(13)).foregroundStyle(Theme.navy)
        }
        .accessibilityElement(children: .combine)
    }

    func swatchRow(_ c: Color, dash: Bool, _ t: String, fill: Color = .clear) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(c, style: StrokeStyle(lineWidth: 1.5, dash: dash ? [3, 2] : [])))
                .frame(width: 18, height: 18)
            Text(t).font(.sarabunFixed(13)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: right | the point

    /// `บนหลังคา | เงาบัง`, then the point card on `บนหลังคา`.
    var padPointColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnyView(obstacleSegment)
            if !obsShade { AnyView(padPointCard) }
        }
        .padding(16)
        .tcCard()
    }

    @ViewBuilder var padPointCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnyView(padPointHeader)
            if let p = selectedPoint {
                AnyView(pointPicker(p))
                AnyView(pointTitle(p))
                if repeatOpen {
                    AnyView(repeatPanel(p))
                } else {
                    AnyView(statusTiles(p))
                    if padMoving(p) { AnyView(padDistances(p)) }
                    if let n = obsNotice {
                        Text(n).font(.sarabunFixed(12.5, .bold)).foregroundStyle(Theme.pending).fixedSize(horizontal: false, vertical: true)
                    }
                    AnyView(pointPhoto(p))
                    if p.kind == TankPoints.vent { AnyView(ventHeightField) }
                }
            } else if Tank.hasSize(values) {
                Text("ยังไม่มีจุดบนแปลน").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            }
            if !repeatOpen && Tank.hasSize(values) { AnyView(actionTiles(selectedPoint)) }
        }
        .onChange(of: pointSel) { _, _ in repeatOpen = false; obsNotice = nil }
    }

    /// `จุด V9 | ช่องระบายอากาศ | 1.45 × 1.45 ม.`: what the selected point is, as the board's picker shows it.
    func pointTitle(_ p: Obstacle) -> some View {
        let r = TankPoints.rect(p), size = r.map { " | " + fmt($0.w) + " × " + fmt($0.h) + " ม." } ?? ""
        return Text("จุด \(p.label) | " + (p.note.isEmpty ? TankPoints.kindName(p.kind) : p.note) + size)
            .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
    }

    /// `ข้อมูลสิ่งกีดขวาง` with `ตรวจแล้ว n/m`, over a bar of the checked (green) and missing (red) points.
    var padPointHeader: some View {
        let list = TankPoints.points(values), total = max(list.count, 1)
        let absent = list.filter(\.isAbsent).count, ok = list.filter { !$0.status.isEmpty && !$0.isAbsent }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ข้อมูลสิ่งกีดขวาง").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                Spacer(minLength: 6)
                Text("ตรวจแล้ว ").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    + Text("\(ok + absent)/\(list.count)").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
            }
            GeometryReader { g in
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.success).frame(width: g.size.width * CGFloat(ok) / CGFloat(total))
                    Rectangle().fill(Theme.danger).frame(width: g.size.width * CGFloat(absent) / CGFloat(total))
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 4)
            .background(Self.track)
            .clipShape(Capsule())
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: status

    /// `ย้ายตำแหน่ง` is on for a point that is there and away from its design position, or once tapped until it is.
    func padMoving(_ p: Obstacle) -> Bool {
        guard p.status == TankPoints.ok else { return false }
        return TankPoints.moved(p) || movingID == p.id
    }

    func statusTiles(_ p: Obstacle) -> some View {
        let moving = padMoving(p)
        return HStack(spacing: 8) {
            statusTile("checkmark", "ตรงแบบ", on: p.status == TankPoints.ok && !moving, fill: Theme.mint, ink: Theme.navy, border: Theme.navy.opacity(0.2)) {
                movingID = nil
                update { v in
                    TankPoints.restore(&v, p.id)
                    TankPoints.setStatus(&v, p.id, p.status == TankPoints.ok && !moving ? "" : TankPoints.ok)
                }
            }
            statusTile("arrow.up.and.down.and.arrow.left.and.right", "ย้ายตำแหน่ง", on: moving, fill: Theme.primarySoft, ink: Theme.primary,
                       border: Theme.primary) {
                movingID = moving ? nil : p.id
                if moving { update { TankPoints.restore(&$0, p.id) } } else { update { TankPoints.setStatus(&$0, p.id, TankPoints.ok) } }
            }
            statusTile("xmark", "ไม่มีจริง", on: p.isAbsent, fill: Theme.danger.opacity(0.14), ink: Theme.dangerText, border: Theme.danger) {
                movingID = nil
                update { TankPoints.setStatus(&$0, p.id, p.isAbsent ? "" : TankPoints.absent) }
            }
        }
        .background { pointKeys(p) }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in fieldEditing = true }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in fieldEditing = false }
    }

    func statusTile(_ icon: String, _ title: String, on: Bool, fill: Color, ink: Color, border: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 17, weight: .bold))
                Text(title).font(.sarabunFixed(14, .bold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? ink : Theme.navy)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(on ? fill : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? border : Theme.navy.opacity(0.3), lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("สถานะ " + title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: distances and moving together

    func padDistances(_ p: Obstacle) -> some View {
        let r = TankPoints.rect(p), t = TankPoints.tankSize(values)
        let round = Tank.isRound(values), left = round ? "ห่างขอบซ้ายสุด" : "ห่างผนังซ้าย", top = round ? "ห่างขอบบนสุด" : "ห่างผนังบน"
        let group = padGroup
        return VStack(alignment: .leading, spacing: 10) {
            distanceRow(left, value: r?.x, upper: (t?.w ?? 100) - (r?.w ?? 0)) { x in nudge(p, group, x: x, y: nil) }
            distanceRow(top, value: r?.y, upper: (t?.h ?? 100) - (r?.h ?? 0)) { y in nudge(p, group, x: nil, y: y) }
            AnyView(pointInfo(p))
            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
            Text("ย้ายพร้อมกัน").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
            AnyView(groupSegment)
            if groupMode != .single, group.count > 1 { AnyView(spacingRow(p)) }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
        .id(p.id)
    }

    func distanceRow(_ title: String, value: Double?, upper: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            (Text(title).font(.sarabunFixed(14, .bold)) + Text("  (ม.)").font(.sarabunFixed(12)).foregroundColor(Theme.inkMuted))
                .foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            TankStepper(value: value, step: TankPoints.nudge, range: 0...max(upper, 0), label: title) { v in if let v { set(v) } }
                .frame(width: 180)
        }
    }

    /// A stepper or a typed distance: the point alone, or its group by the same step.
    func nudge(_ p: Obstacle, _ group: [UUID], x: Double?, y: Double?) {
        guard group.count > 1, let r = TankPoints.rect(p) else {
            update { TankPoints.move(&$0, p.id, x: x, y: y) }
            return
        }
        moveGroup(group, dx: x.map { $0 - r.x } ?? 0, dy: y.map { $0 - r.y } ?? 0)
    }

    var groupSegment: some View {
        let items: [(TankPoints.GroupMode, String, String)] = [(.single, "circle.fill", "จุดเดียว"), (.row, "arrow.left.and.right", "แถว"),
                                                               (.column, "arrow.up.and.down", "คอลัมน์")]
        return HStack(spacing: 3) {
            ForEach(items, id: \.0) { mode, icon, title in
                let on = groupMode == mode
                Button { withAnimation(.easeOut(duration: 0.15)) { groupMode = mode; obsNotice = nil } } label: {
                    Label(title, systemImage: icon).font(.sarabunFixed(14, on ? .bold : .regular))
                        .labelStyle(.titleAndIcon).imageScale(.small)
                        .foregroundStyle(on ? Theme.pending : Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background { if on { RoundedRectangle(cornerRadius: 8).fill(Theme.surface).shadow(color: Theme.navy.opacity(0.2), radius: 1.5, y: 1) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ย้ายพร้อมกัน " + title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Self.track, in: RoundedRectangle(cornerRadius: 10))
    }

    /// `ระยะห่างจุด`: even spacing along the group, from the selected point.
    func spacingRow(_ p: Obstacle) -> some View {
        let members = TankPoints.group(values, of: p.id, mode: groupMode)
        let now = TankPoints.spacing(values, group: members, mode: groupMode)
        let t = TankPoints.tankSize(values)
        return distanceRow("ระยะห่างจุด", value: now, upper: max(t?.w ?? 100, t?.h ?? 100)) { d in
            guard d > 0 else { return }
            var cut = 0
            update { cut = TankPoints.respace(&$0, group: members, from: p.id, spacing: d, mode: groupMode) }
            obsNotice = cut > 0 ? "\(cut) จุดชนผนังถัง | ดึงกลับให้อยู่ในถัง" : nil
        }
    }

    // MARK: repeat

    /// `ทำซ้ำเป็นแถว` in place of the status and distances: direction, count and spacing.
    func repeatPanel(_ p: Obstacle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ทำซ้ำเป็นแถว").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
            HStack(spacing: 3) {
                ForEach([false, true], id: \.self) { down in
                    let on = repeatDown == down
                    Button { repeatDown = down } label: {
                        Label(down ? "แนวตั้ง" : "แนวนอน", systemImage: down ? "arrow.down" : "arrow.right")
                            .font(.sarabunFixed(14, on ? .bold : .regular)).foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background { if on { RoundedRectangle(cornerRadius: 8).fill(Theme.surface).shadow(color: Theme.navy.opacity(0.2), radius: 1.5, y: 1) } }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Self.track, in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 8) {
                Text("จำนวนเพิ่ม (จุด)").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                Spacer(minLength: 4)
                countStepper
            }
            distanceRow("ระยะห่าง", value: rowSpacing, upper: 100) { rowSpacing = max($0, 0.5) }
            HStack(spacing: 8) {
                Button("ยกเลิก") { repeatOpen = false }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                Button("สร้าง \(rowCount) จุด") {
                    var ids: [UUID] = []
                    update { ids = TankPoints.repeatPoint(&$0, p.id, count: rowCount, spacing: rowSpacing, down: repeatDown) }
                    let skipped = rowCount - ids.count
                    repeatOpen = false
                    if let last = ids.last { pointSel = last }
                    obsNotice = skipped > 0 ? "ไม่ได้สร้าง \(skipped) จุดที่เกินขอบถัง" : nil
                }
                .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
                .accessibilityIdentifier("repeatCreate")
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
    }

    var countStepper: some View {
        HStack(spacing: 4) {
            ForEach([-1, 1], id: \.self) { d in
                if d == 1 {
                    Text("\(rowCount)").font(.sarabunFixed(16, .bold)).monospacedDigit().foregroundStyle(Theme.navy)
                        .frame(width: 72, height: 44)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.3)))
                        .accessibilityLabel("จำนวนเพิ่ม \(rowCount) จุด")
                }
                let next = rowCount + d, ok = (1...20).contains(next)
                Button { if ok { rowCount = next } } label: {
                    Image(systemName: d < 0 ? "minus" : "plus").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ok ? Theme.primary : Theme.disabledText).frame(width: 44, height: 44)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .disabled(!ok)
                .accessibilityLabel(d < 0 ? "ลดจำนวน" : "เพิ่มจำนวน")
            }
        }
    }

    // MARK: actions

    /// `+ ช่องระบาย` `+ ช่องลงถัง` `ทำซ้ำแถว` `ลบจุดนี้`, 56 pt tiles under `เพิ่ม / แก้ไข | กรณีไม่มีในแบบ`.
    func actionTiles(_ p: Obstacle?) -> some View {
        let canDelete = p.map(TankPoints.canDelete) ?? false
        return VStack(alignment: .leading, spacing: 8) {
            Text("เพิ่ม / แก้ไข | กรณีไม่มีในแบบ").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
            HStack(spacing: 8) {
                actionTile("plus", "ช่องระบาย", ink: Theme.primary, border: Theme.primary.opacity(0.5)) { addPoint(TankPoints.vent) }
                actionTile("plus", "ช่องลงถัง", ink: Theme.primary, border: Theme.primary.opacity(0.5)) { addPoint(TankPoints.hatch) }
                actionTile("square.on.square", "ทำซ้ำแถว", ink: Theme.navy, border: Theme.navy.opacity(0.35)) {
                    rowCount = 3; rowSpacing = TankPoints.rowSpacing(values); repeatDown = false; repeatOpen = true
                }
                .disabled(p == nil).opacity(p == nil ? 0.45 : 1)
                actionTile("trash", "ลบจุดนี้", ink: Theme.dangerText, border: Theme.danger.opacity(0.45)) { deleteAsk = true }
                    .disabled(!canDelete).opacity(canDelete ? 1 : 0.45)
                    .accessibilityHint(canDelete ? "" : "จุดตามแบบใช้ ไม่มีจริง แทนการลบ")
            }
        }
    }

    func actionTile(_ icon: String, _ title: String, ink: Color, border: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 15, weight: .bold))
                Text(title).font(.sarabunFixed(12.5, .bold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "plus" ? "เพิ่ม" + title : title)
    }
}
#endif
