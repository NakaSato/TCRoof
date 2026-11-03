#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

// MARK: - Mount Walkway, Faces, Alignment & Bearing Options

extension RoofPageWide {
    // MARK: - Shed Roof Orientation

    /// A shed roof's low side, also turned by a tap on the plan's arrow.
    @ViewBuilder var mountShedSide: some View {
        if RoofMount.shape(values) == .shed {
            let alongX = Roof.ridge(values) == .h, start = RoofMount.shedLowAtStart(values)
            VStack(alignment: .leading, spacing: 6) {
                A3Label(text: "ด้านต่ำของหลังคาเพิง (ชายคา)")
                RoofSegments(options: alongX ? ["ขอบล่างแปลน", "ขอบบนแปลน"] : ["ขอบขวาแปลน", "ขอบซ้ายแปลน"], selected: start ? 1 : 0,
                             minSegment: 90) { i in
                    if (i == 1) != start { turnShed() }
                }
                Text("แตะลูกศร ด้านต่ำ บนแปลนเพื่อสลับได้").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    // MARK: - Walkways

    /// The walkway along the ridge with the roof access (on by default), and one module wide down the middle of each
    /// face (the default once on) or after every n columns, for cleaning (off by default).
    var mountWalkway: some View {
        VStack(alignment: .leading, spacing: 2) {
            mountRidgeWalkway
            mountCleaningWalkway
        }
        .id("walkway")
    }

    /// Along the ridge: on by default; the walkways down the middle need it, so switching it off clears them.
    @ViewBuilder var mountRidgeWalkway: some View {
        let centre = mountChoice.walkwayCentre
        let hasRidge = RoofMount.shape(values) != .shed, ridge = hasRidge && (mountChoice.walkwayRidge || centre)
        if hasRidge {
            Toggle(isOn: Binding(get: { ridge }, set: { on in changeChoice { $0.walkwayRidge = on; if !on { $0.walkwayCentre = false } } })) {
                Text("ทางเดินตามสันหลังคา").font(.sarabunFixed(14))
            }
            .tint(Theme.primary).frame(minHeight: 44)
            if ridge { ridgeWidthStepper; mountAccessSide }
        }
    }

    var mountCleaningWalkway: some View {
        let n = mountChoice.walkwayEvery, centre = mountChoice.walkwayCentre
        let hasRidge = RoofMount.shape(values) != .shed
        return VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { n > 0 || centre }, set: { on in changeChoice { c in
                c.walkwayCentre = on; c.walkwayEvery = 0
                if on && hasRidge { c.walkwayRidge = true }
            } })) {
                Text("เว้นทางเดินล้างแผง").font(.sarabunFixed(14))
            }
            .tint(Theme.primary).frame(minHeight: 44)
            if n > 0 || centre {
                Picker("ตำแหน่งทางเดิน", selection: Binding(get: { centre ? 0 : 1 }, set: { pick in
                    changeChoice { c in
                        c.walkwayCentre = pick == 0; c.walkwayEvery = pick == 0 ? 0 : max(2, n == 0 ? 8 : n)
                        if pick == 0 { c.walkwayRidge = true }
                    }
                })) {
                    Text("กลางหลังคา").tag(0)
                    Text("ทุก n แผง").tag(1)
                }
                .pickerStyle(.segmented).frame(minHeight: 44)
            }
            if n > 0 {
                HStack(spacing: 6) {
                    Text("ทางเดินกว้าง 1 แผง ทุก").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 4)
                    stepButton("minus", enabled: n > 2) { changeChoice { $0.walkwayEvery = max(2, n - 1) } }
                    Text("\(n) แผง").font(.sarabunFixed(14, .bold)).monospacedDigit().frame(minWidth: 56)
                    stepButton("plus", enabled: n < 40) { changeChoice { $0.walkwayEvery = min(40, n + 1) } }
                }
            }
        }
    }

    /// Down the middle the roof is reached up the gable wall at one end of the ridge walkway (the CAD file's cat ladder
    /// and landing): which end, as the plan shows it.
    @ViewBuilder var mountAccessSide: some View {
        if narrow {
            VStack(alignment: .leading, spacing: 6) {
                A3Label(text: "ทางขึ้นหลังคา (Roof access)")
                RoofSegments(options: ["ด้านซ้าย", "ด้านขวา"], selected: mountChoice.accessRight ? 1 : 0, minSegment: 100, height: 44) { i in
                    changeChoice { $0.accessRight = i == 1 }
                }
                Text("ทางขึ้นอยู่ปลายสันหลังคาด้านซ้ายหรือขวาเท่านั้น และต่อกับทางเดินตามสัน")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } else {
            mountAccessSideWide
        }
    }

    var mountAccessSideWide: some View {
        HStack(spacing: 8) {
            Text("ทางขึ้นหลังคา (บันไดลิง)").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            Spacer(minLength: 4)
            Picker("ทางขึ้นหลังคา", selection: Binding(get: { mountChoice.accessRight ? 1 : 0 }, set: { pick in
                changeChoice { $0.accessRight = pick == 1 }
            })) {
                Text("ซ้าย").tag(0)
                Text("ขวา").tag(1)
            }
            .pickerStyle(.segmented).frame(width: 140, height: 44)
        }
    }

    // MARK: - Roof Faces & Alignment

    var mountFaces: some View {
        let faces = shownMount?.faces ?? [], c = mountChoice
        let best = faces.map(\.yield).max() ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            A3Label(text: "ด้านหลังคาที่วางแผง")
            ForEach(faces, id: \.face.id) { f in
                let auto = c.faceUse[f.face.id] == nil
                Button {
                    changeChoice { $0.faceUse[f.face.id] = !f.used }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: f.used ? "checkmark.square.fill" : "square").font(.system(size: 20))
                            .foregroundStyle(f.used ? Theme.primary : Theme.inkMuted)
                        Text("\(RoofFace.direction(f.face.azimuth)) \(Int(f.face.azimuth.rounded()))° | ลาด \(String(format: "%.0f", f.face.tilt * 180 / .pi))°")
                            .font(.sarabunFixed(14)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Int(f.yield.rounded()).formatted()) kWh/kWp | \(f.modules) แผง")
                            .font(.sarabunFixed(12.5).monospacedDigit()).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(f.used ? .isSelected : [])
                .accessibilityHint(auto ? "ตั้งอัตโนมัติ" : "ตั้งเอง")
            }
            if faces.contains(where: { $0.yield < best * mountChoice.standardOrDefault.faceMinShare }) {
                Text("ด้านที่ได้พลังงานต่ำกว่า \(Int(mountChoice.standardOrDefault.faceMinShare * 100))% ของด้านที่ดีที่สุดไม่วางแผง (ค่าสมมติ) | แตะเพื่อเปิดเอง")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    var mountAlign: some View {
        let faces = shownMount?.faces ?? [], c = mountChoice
        let face = faces.first { $0.face.id == mountFace } ?? faces.first
        let maxOffset = (c.landscape ? c.standardOrDefault.moduleLength : c.standardOrDefault.moduleWidth) + c.standardOrDefault.moduleGap
        return VStack(alignment: .leading, spacing: 6) {
            A3Label(text: "จัดแนวผัง")
            if faces.count > 1 {
                RoofSegments(options: faces.map { RoofFace.direction($0.face.azimuth) }, selected: faces.firstIndex { $0.face.id == face?.face.id },
                             minSegment: 60) { i in mountFace = faces[i].face.id }
            }
            if let face {
                let off = face.placement.columnOffset
                HStack(spacing: 8) {
                    Text("เลื่อนแนวแผงตามชายคา").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 4)
                    Text(String(format: "%.2f ม.", off)).font(.sarabunFixed(14, .bold)).monospacedDigit()
                }
                Slider(value: Binding(get: { off }, set: { new in
                    let snapped = (new / 0.05).rounded() * 0.05
                    guard abs(snapped - off) > 1e-9 else { return }
                    changeChoice { ch in
                        var p = ch.placements[face.face.id] ?? face.placement
                        p.columnOffset = snapped
                        ch.placements[face.face.id] = p
                    }
                }), in: 0...maxOffset)
                .tint(Theme.primary)
                .accessibilityLabel("เลื่อนแนวแผงตามชายคา")
                .accessibilityValue(String(format: "%.2f เมตร", off))
            }
            Button {
                Task { await searchMostModules() }
            } label: {
                Label("หาผังที่ได้แผงมากที่สุด", systemImage: "wand.and.stars").font(.sarabunFixed(15, .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card))
            .disabled(mountBusy)
            .id("most")
            if let t = mountTried {
                Text("ลอง \(t.tried.formatted()) แบบ | ดีที่สุด \(t.best) แผง").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            if mountArrangements.count > 1 {
                let c = mountChoice, top = mountArrangements.map(\.modules).max() ?? 0
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(mountArrangements, id: \.label) { a in
                        let picked = a.landscape == c.landscape && a.railsAcross == (c.railsAcross && !c.ribClamp && !RoofMount.tileRoof(values))
                        HStack(spacing: 6) {
                            Image(systemName: picked ? "checkmark.circle.fill" : "circle").foregroundStyle(picked ? Theme.primary : Theme.inkMuted)
                            Text(a.label).font(.sarabunFixed(12.5, picked ? .bold : .regular))
                            Spacer(minLength: 4)
                            Text("\(a.modules) แผง").font(.sarabunFixed(12.5, a.modules == top ? .bold : .regular)).monospacedDigit()
                        }
                        .foregroundStyle(picked ? Theme.navy : Theme.inkMuted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    var mountBearing: some View {
        let b = RoofMount.bearing(values)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ทิศของขอบบนแปลน").font(.sarabunFixed(14))
                Text(b.map { "หันทิศ" + RoofFace.direction($0) } ?? "ยังไม่ระบุ | คิดเป็นทิศเหนือ (ค่าสมมติ)")
                    .font(.sarabunFixed(12)).foregroundStyle(b == nil ? Self.amber : Theme.inkMuted)
            }
            Spacer(minLength: 6)
            stepButton("minus", enabled: true) { update { RoofMount.setBearing(&$0, (b ?? 0) - 5) } }
            Text(b.map { "\(Int($0))°" } ?? "—").font(.sarabunFixed(18, .bold)).monospacedDigit().frame(minWidth: 52)
            stepButton("plus", enabled: true) { update { RoofMount.setBearing(&$0, (b ?? 0) + 5) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ทิศของขอบบนแปลน " + (b.map { "\(Int($0)) องศา" } ?? "ยังไม่ระบุ"))
    }
}
#endif
