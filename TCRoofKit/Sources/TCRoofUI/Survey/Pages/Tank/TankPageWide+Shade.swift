#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// D1 sub-step 2's `เงาบัง` on iPad (docs/ui/survey-d1-obstacles-ipad Part B): the shade simulation of the objects
/// around the tank (`TankShade.Item`). The left card shows a moment (month, time, play) in plan or 3D with the add
/// toolbar; the right column the sun path, one chip per object with its yearly loss, the selected object's editor and
/// the form's shade answers under `ข้อมูลในแบบฟอร์ม`. The year runs off the main thread (`refreshShade`); a moment is
/// worked out as it is drawn.
extension TankPageWide {
    var shadeItems: [TankShade.Item] { TankShade.items(values) }
    var shadeLatitude: Double { RoofMount.site(job).latitude ?? RoofMount.defaultLatitude }
    var shadeScene: TankShadeScene {
        TankShadeScene(values, items: shadeItems, moment: TankShade.moment(values, latitude: shadeLatitude, month: shadeMonth, time: shadeTime))
    }
    /// The 30-minute steps of the chosen month's daylight.
    var shadeTimes: [Double] { TankShade.sunPath(latitude: shadeLatitude, month: shadeMonth).map(\.time) }

    func setShadeItems(_ list: [TankShade.Item]) { update { TankShade.setItems(&$0, list) } }

    func editItem(_ id: String, _ f: (inout TankShade.Item) -> Void) {
        var list = shadeItems
        guard let k = list.firstIndex(where: { $0.id == id }) else { return }
        f(&list[k])
        setShadeItems(list)
    }

    // MARK: left | the simulation

    var padShadeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnyView(shadeHeader)
            AnyView(shadeStage(full: false)).frame(height: stacked ? 460 : 620)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tcCard()
        .task(id: shadeKey) { await refreshShade() }
        .task(id: shadePlaying) { await playDay() }
        .fullScreenCover(isPresented: $shadeFullScreen) { shadeFull }
        .alert(shadeAdding.map { "เพิ่ม" + TankShade.Item.name($0) } ?? "", isPresented: $shadeAddAsk) {
            TextField("สูงจากพื้นดิน (ม.)", text: $shadeAddHeight).keyboardType(.decimalPad)
            TextField(shadeAdding == .tree ? "ทรงพุ่มกว้าง (ม.)" : shadeAdding == .tower ? "ถังกว้าง (ม.)" : "กว้าง (ม.)", text: $shadeAddWidth)
                .keyboardType(.decimalPad)
            Button("เพิ่ม") { if let k = shadeAdding { addShadeItem(k) } }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("ใส่ความสูงและความกว้างที่วัดหรือประมาณหน้างาน แล้วลากไปวางบนแปลน")
        }
    }

    var shadeHeader: some View {
        HStack(spacing: 8) {
            Text("จำลองเงาบัง").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
            AnyView(shadeViewSegment)
            Spacer(minLength: 4)
            shadeStepper(RoutineReport.thaiMonthsShort[shadeMonth], width: 64, label: "เดือน", id: "shadeMonth") { d in
                shadeMonth = (shadeMonth + d + 12) % 12
                if let t = shadeTimes.min(by: { abs($0 - shadeTime) < abs($1 - shadeTime) }) { shadeTime = t }
            }
            shadeStepper(Self.clock(shadeTime), width: 72, label: "เวลา", id: "shadeTime") { d in
                let times = shadeTimes
                guard let i = times.firstIndex(where: { abs($0 - shadeTime) < 0.01 }) ?? times.indices.min(by: { abs(times[$0] - shadeTime) < abs(times[$1] - shadeTime) }) else { return }
                shadeTime = times[min(max(i + d, 0), times.count - 1)]
            }
            Button { shadePlaying.toggle() } label: {
                Image(systemName: shadePlaying ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.onPrimary).frame(width: 48, height: 48).background(Theme.primary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shadePlaying ? "หยุดเล่น" : "เล่นทั้งวัน")
        }
    }

    var shadeViewSegment: some View {
        HStack(spacing: 3) {
            ForEach([false, true], id: \.self) { three in
                let on = shade3D == three
                Button { shadePlaying = false; withAnimation(.easeOut(duration: 0.15)) { shade3D = three } } label: {
                    Text(three ? "3 มิติ" : "แปลน").font(.sarabunFixed(14, on ? .bold : .regular)).foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                        .frame(minWidth: 60, minHeight: 40)
                        .background { if on { RoundedRectangle(cornerRadius: 8).fill(Theme.surface).shadow(color: Theme.navy.opacity(0.2), radius: 1.5, y: 1) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Self.track, in: RoundedRectangle(cornerRadius: 10))
    }

    /// `‹ value ›`, 44 pt arrows.
    func shadeStepper(_ value: String, width: CGFloat, label: String, id: String, step: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach([-1, 1], id: \.self) { d in
                if d == 1 {
                    Text(value).font(.sarabunFixed(16, .bold)).monospacedDigit().foregroundStyle(Theme.navy).frame(width: width)
                        .accessibilityLabel(label).accessibilityValue(value).accessibilityIdentifier(id)
                }
                Button { shadePlaying = false; step(d) } label: {
                    Image(systemName: d < 0 ? "chevron.left" : "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel((d < 0 ? "ก่อนหน้า " : "ถัดไป ") + label)
                .accessibilityIdentifier(id + (d < 0 ? "-" : "+"))
            }
        }
    }

    static func clock(_ t: Double) -> String { String(format: "%02d:%02d", Int(t), Int(((t - floor(t)) * 60).rounded())) }

    /// Plays the day from the time shown, a 30-minute step about four times a second, stopping at sunset.
    func playDay() async {
        guard shadePlaying else { return }
        while shadePlaying, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let times = shadeTimes
            guard let next = times.first(where: { $0 > shadeTime + 0.01 }) else { shadePlaying = false; break }
            shadeTime = next
        }
    }

    /// The picture with its caption, compass, add toolbar and buttons.
    func shadeStage(full: Bool) -> some View {
        let scene = shadeScene
        return ZStack {
            if shade3D {
                TankShade3D(scene: scene, turn: shadeTurn, selected: shadeSel)
            } else {
                TankShadePlan(scene: scene, picture: sitePicture, selected: $shadeSel,
                              moved: { id, x, y in editItem(id) { $0.x = x; $0.y = y } },
                              gap: { TankShade.gap($0, in: values) })
            }
        }
        .overlay(alignment: .topLeading) { shadeCaption(scene).padding(10) }
        .overlay(alignment: .topTrailing) { shadeCompass(scene).padding(10) }
        .overlay(alignment: .leading) { shadeAddBar.padding(10) }
        .overlay(alignment: .bottomLeading) { shadeLegend.padding(10) }
        .overlay(alignment: .bottomTrailing) { shadeCorner(full: full).padding(10) }
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
    }

    /// The A2 site picture, under the plan.
    var sitePicture: UIImage? { job.values.photo("siteMap").flatMap { model.image($0, in: job.id) } }

    /// `21 ธ.ค. 15:30 น. | ดวงอาทิตย์สูง 27° | มุม 234°`
    func shadeCaption(_ scene: TankShadeScene) -> some View {
        let day = "21 " + RoutineReport.thaiMonthsShort[shadeMonth] + " " + Self.clock(shadeTime) + " น."
        let sun = scene.moment.map { String(format: " | ดวงอาทิตย์สูง %.0f° | มุม %.0f°", $0.altitude, ($0.azimuth + 180).truncatingRemainder(dividingBy: 360)) }
            ?? " | ดวงอาทิตย์ตกแล้ว"
        return Text(day + sun).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("shadeCaption")
    }

    func shadeCompass(_ scene: TankShadeScene) -> some View {
        let v = scene.northOnPlan, angle = atan2(v.dx, -v.dy) * 180 / .pi
        return ZStack {
            Circle().fill(Theme.surface).shadow(color: Theme.navy.opacity(0.2), radius: 2, y: 1)
            VStack(spacing: 0) {
                Text("N").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.danger)
                Image(systemName: "location.north.fill").font(.system(size: 18)).foregroundStyle(Theme.navySolid)
            }
            .rotationEffect(.degrees(shade3D ? angle - Double(shadeTurn) * 45 : angle))
        }
        .frame(width: 52, height: 52)
        .accessibilityLabel("ทิศเหนือ")
    }

    var shadeAddBar: some View {
        VStack(spacing: 2) {
            Text("+ เพิ่ม").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted).padding(.top, 6)
            ForEach(TankShade.Item.Kind.allCases, id: \.self) { k in
                Button {
                    shadePlaying = false; shadeAddHeight = ""; shadeAddWidth = ""; shadeAdding = k; shadeAddAsk = true
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: k == .tree ? "tree" : k == .building ? "building.2" : "drop.circle").font(.system(size: 18))
                        Text(TankShade.Item.name(k)).font(.sarabunFixed(11.5, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Theme.primary).frame(width: 64, height: 56).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("เพิ่ม" + TankShade.Item.name(k))
                .accessibilityIdentifier("shadeAdd-" + k.rawValue)
            }
        }
        .padding(.horizontal, 4).padding(.bottom, 6)
        .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Theme.navy.opacity(0.15), radius: 3, y: 1)
    }

    var shadeLegend: some View {
        HStack(spacing: 10) {
            ForEach([(Theme.primary.opacity(0.75), "รับแดด"), (Theme.navySolid.opacity(0.16), "เงาต้นไม้"), (Theme.navySolid.opacity(0.3), "เงาทึบ")], id: \.1) { c, t in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 10)
                    Text(t).font(.sarabunFixed(12)).foregroundStyle(Theme.navy)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    /// 3D: `มองจาก <side>` turns the view 45°; both: full screen.
    func shadeCorner(full: Bool) -> some View {
        HStack(spacing: 0) {
            if shade3D {
                Button { shadePlaying = false; shadeTurn = (shadeTurn + 1) % 8 } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 15, weight: .semibold))
                        VStack(spacing: 0) {
                            Text("มองจาก").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                            Text(TankShade3D.sideName(turn: shadeTurn, planAzimuth: Double(Tank.azimuth(values) ?? 0))).font(.sarabunFixed(13, .bold))
                        }
                    }
                    .foregroundStyle(Theme.navy).padding(.horizontal, 10).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("หมุนมุมมอง")
            }
            Button { if full { shadeFullScreen = false } else { shadePlaying = false; shadeFullScreen = true } } label: {
                Image(systemName: full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.primary).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(full ? "ออกจากเต็มจอ" : "เต็มจอ")
        }
        .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Theme.navy.opacity(0.15), radius: 3, y: 1)
    }

    var shadeFull: some View {
        VStack(spacing: 12) {
            AnyView(shadeHeader)
            AnyView(shadeStage(full: true))
        }
        .padding(16)
        .tcPageBackground()
    }

    /// A new object of `kind` beside the tank on the side with fewest objects, 3 m from the wall, selected.
    func addShadeItem(_ kind: TankShade.Item.Kind) {
        guard let h = NumberInput.value(shadeAddHeight), h > 0, let w = NumberInput.value(shadeAddWidth), w > 0,
              let t = TankPoints.tankSize(values) else { return }
        let list = shadeItems
        let sides: [(Double, Double)] = [(t.w / 2, t.h + 3 + w / 2), (t.w + 3 + w / 2, t.h / 2), (-3 - w / 2, t.h / 2), (t.w / 2, -3 - w / 2)]
        func count(_ i: Int) -> Int {
            list.filter { o in
                switch i {
                case 0: return o.y > t.h
                case 1: return o.x > t.w
                case 2: return o.x < 0
                default: return o.y < 0
                }
            }.count
        }
        let side = (0..<4).min { count($0) < count($1) } ?? 0
        let item = TankShade.Item(id: TankShade.nextID(kind, in: list), kind: kind, x: sides[side].0, y: sides[side].1, height: h, width: w)
        setShadeItems(list + [item])
        shadeSel = item.id
    }

    // MARK: right | sun path, chips, editor

    var padShadeColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("เส้นทางดวงอาทิตย์").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
            TankSunPath(latitude: shadeLatitude, month: shadeMonth, time: shadeTime, scene: shadeScene)
            AnyView(shadeChips)
            if let id = shadeSel, let item = shadeItems.first(where: { $0.id == id }) { AnyView(shadeEditor(item)) }
            DisclosureGroup(isExpanded: $shadeFormOpen) {
                AnyView(shadeFields).padding(.top, 6)
            } label: {
                Text("ข้อมูลในแบบฟอร์ม").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).frame(minHeight: 44)
            }
            .tint(Theme.primary)
        }
    }

    var shadeChips: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(shadeItems) { i in
                let loss = shadeResult?.itemLoss[i.id], on = i.id == shadeSel
                Button { shadePlaying = false; shadeSel = on ? nil : i.id } label: {
                    HStack(spacing: 6) {
                        Group {
                            if i.kind == .building { RoundedRectangle(cornerRadius: 2).fill(TankShadeScene.color(i.kind)) } else { Circle().fill(TankShadeScene.color(i.kind)) }
                        }
                        .frame(width: 12, height: 12)
                        Text(i.id).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                        Text(loss.map { String(format: "−%.1f%%", $0 * 100) } ?? (shadeBusy ? "…" : "—"))
                            .font(.sarabunFixed(14, .bold)).monospacedDigit()
                            .foregroundStyle((loss ?? 0) > 0.0005 ? Theme.dangerText : Theme.inkMuted)
                    }
                    .padding(.horizontal, 12).frame(minWidth: 96, minHeight: 48)
                    .background(on ? Theme.warning.opacity(0.1) : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.warning : Theme.navy.opacity(0.25), lineWidth: on ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i.id) \(TankShade.Item.name(i.kind))" + (loss.map { String(format: " เสีย %.1f เปอร์เซ็นต์", $0 * 100) } ?? ""))
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("shadeChip-" + i.id)
            }
        }
    }

    /// The selected object: height, width and gap to the wall, and remove.
    func shadeEditor(_ i: TankShade.Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(i.id) | \(TankShade.Item.name(i.kind))").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
            distanceRow("สูง", value: i.height, upper: 100) { v in editItem(i.id) { $0.height = max(v, 0.5) } }
            distanceRow("กว้าง", value: i.width, upper: 60) { v in editItem(i.id) { $0.width = max(v, 0.5) } }
            distanceRow("ห่างผนัง", value: TankShade.gap(i, in: values), upper: 200) { v in
                let vals = values
                editItem(i.id) { TankShade.setGap(&$0, v, in: vals) }
            }
            Button(role: .destructive) {
                setShadeItems(shadeItems.filter { $0.id != i.id }); shadeSel = nil
            } label: {
                Label("ลบสิ่งบังนี้", systemImage: "trash").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.dangerText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(TCButtonStyle(.destructive, size: .card, fullWidth: true))
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
        .id(i.id)
    }

    /// `เงาบัง | 1.2%` once the simulation has a figure for the objects.
    var shadeSegmentText: String? {
        guard !phone, !shadeItems.isEmpty, let s = shadeResult else { return nil }
        return String(format: "เงาบัง | %.1f%%", s.totalLoss * 100)
    }

    // MARK: DEBUG

    #if DEBUG
    /// `-surveyD1 shade3d|shadeplan|shadejune|shadeselect`: the example tank checked and laid out, with the board's five
    /// objects (example values, not saved anywhere else), T1 selected (B1 for `shadeselect`), December 15:30 (June
    /// 12:00 for `shadejune`).
    func seedShadeDemo(_ state: String) {
        update { v in
            TankPoints.seed(&v)
            for o in TankPoints.points(v) where o.status.isEmpty { TankPoints.setStatus(&v, o.id, TankPoints.ok) }
            if TankLayout.current(v) == nil { TankLayout.save(&v, TankLayout.auto(v), off: []) }
            let t = TankPoints.tankSize(v) ?? (40, 40)
            TankShade.setItems(&v, [
                .init(id: "T1", kind: .tree, x: -3 - 4, y: t.h - 6, height: 14, width: 8),
                .init(id: "T2", kind: .tree, x: -3 - 3, y: 8, height: 9, width: 6),
                .init(id: "B1", kind: .building, x: t.w * 0.7, y: -4 - 5, height: 8, width: 10),
                .init(id: "B2", kind: .building, x: t.w + 4 + 5, y: t.h - 4, height: 10, width: 10),
                .init(id: "W1", kind: .tower, x: t.w + 14, y: t.h * 0.2, height: 30, width: 6),
            ])
        }
        obsShade = true
        shade3D = state == "shade3d"
        shadeSel = state == "shadeselect" ? "B1" : "T1"
        if state == "shadejune" { shadeMonth = 5; shadeTime = 12 } else { shadeMonth = 11; shadeTime = 15.5 }
    }
    #endif
}
#endif
