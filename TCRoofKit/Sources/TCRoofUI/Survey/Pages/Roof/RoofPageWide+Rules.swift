#if canImport(UIKit)
import SwiftUI
import TCRoofCore
import ModuleRules

/// แผงบนหลังคา's installation checks from ZNSHINE's manual (docs/specs/module-install-rules.md §7.2), information only,
/// nothing to type: the catalog model matched to the layout's module, the clamp method with its torque, washer and load
/// rating, the clamp zone on a module outline, and the rules the layout itself raises (tilt, orientation, clamp offsets,
/// gap, rails). The layout gives all of it; `ArrayLayoutCheck` is built from it and nothing is stored.
extension RoofPageWide {
    /// The catalog model matching the layout's module.
    var rulesModule: ModuleModel? {
        let s = mountChoice.standardOrDefault
        return ArrayLayoutCheck.match(wp: s.moduleWp, lengthMm: s.moduleLength * 1000, widthMm: s.moduleWidth * 1000)
    }

    /// What the engine checks: the matched module and the clamp method, no typed answers.
    var effectiveLayoutCheck: ArrayLayoutCheck {
        var c = ArrayLayoutCheck()
        c.moduleID = rulesModule?.id
        c.method = .clamp
        return c
    }

    var layoutGeometry: ArrayLayoutCheck.LayoutGeometry? {
        guard let m = shownMount else { return nil }
        let faces = m.usedFaceAngles
        return ArrayLayoutCheck.LayoutGeometry(tiltDeg: m.roof.tilt * 180 / .pi, latitude: latitude, landscape: m.options.landscape,
                                               clampSide: m.clampsLongSide ? .long : .short, clampOffsetsMm: m.clampOffsetsMm,
                                               gapMm: m.standard.moduleGap * 1000, railsPerModule: 2,
                                               tiltsByFace: faces.map(\.tilt), azimuthsByFace: faces.map(\.azimuth))
    }

    // MARK: the card

    @ViewBuilder var mountRules: some View {
        let c = effectiveLayoutCheck
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("ตรวจตามคู่มือติดตั้งแผง").font(.sarabunFixed(15, .bold))
                Spacer(minLength: 6)
                Text("ZNSHINE | " + ModuleCatalog.ruleSetVersion).font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted)
            }
            if let g = layoutGeometry {
                ModuleRulesList(c.validation(g), empty: "ผ่านทุกข้อที่ตรวจได้")
            } else {
                Text("ยังไม่มีผังแผง").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            rulesModuleInfo
            rulesMethod
            rulesClamp
        }
        .padding(12)
        .background(Self.track.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    var rulesModuleInfo: some View {
        let m = rulesModule
        return VStack(alignment: .leading, spacing: 4) {
            A3Label(text: "รุ่นแผงตามแคตตาล็อก")
            Text(m.map { $0.id + String(format: " | %.0f W | %d เซลล์ (%@)", $0.pmaxW, $0.cellCount, $0.sizeClass == .big ? "ใหญ่" : "เล็ก") }
                 ?? "ไม่ตรงกับแคตตาล็อก")
                .font(.sarabunFixed(14, .bold)).foregroundStyle(m == nil ? Self.amber : Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
            if let line = m?.datasheetLine {
                Text(line).font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            if let m, m.doubleGlass {
                Text("แผงกระจกสองชั้น: คู่มือฉบับนี้เขียนสำหรับแผงกระจกชั้นเดียว").font(.sarabunFixed(11.5)).foregroundStyle(Self.amber)
            }
        }
    }

    var rulesMethod: some View {
        let method = MountingMethod.clamp
        let p = ModuleCatalog.profile(method)
        return VStack(alignment: .leading, spacing: 4) {
            A3Label(text: "วิธียึดตามคู่มือ | ตัวจับ (clamp)")
            if let p {
                let load = rulesModule.flatMap { p.load(cellCount: $0.cellCount, side: layoutGeometry?.clampSide) }
                Text("\(p.holeSpec) | \(p.bolt) | ขัน \(Int(p.torqueNm.lowerBound))–\(Int(p.torqueNm.upperBound)) N·m"
                     + (p.washerMinThicknessMm > 0 ? String(format: " | แหวน ≥ %.1f มม. OD %.0f–%.0f มม.", p.washerMinThicknessMm, p.washerOdMm.lowerBound, p.washerOdMm.upperBound) : ""))
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                Text(load.map { String(format: "รับแรง +%.0f / −%.0f Pa (ค่าทดสอบ ปลอดภัย 1.5 เท่า)", $0.pushPa, $0.pullPa) } ?? "วิธีนี้ไม่รับรองแผงรุ่นนี้ในแนวที่วาง")
                    .font(.sarabunFixed(12, .bold)).foregroundStyle(load == nil ? Theme.dangerText : Theme.navy)
            }
        }
    }

    // MARK: clamp zone

    @ViewBuilder var rulesClamp: some View {
        if let g = layoutGeometry, let m = rulesModule {
            let zone = ModuleRules.clampZone(module: m, side: g.clampSide)
            let offsets = g.clampOffsetsMm
            let outside = zone.map { z in offsets.contains { !z.contains($0) } } ?? true
            VStack(alignment: .leading, spacing: 4) {
                A3Label(text: "ตำแหน่งตัวจับ | ด้าน" + (g.clampSide == .long ? "ยาว" : "สั้น"))
                ClampZoneOutline(side: g.clampSide == .long ? m.lengthMm : m.widthMm, zone: zone, offsets: offsets)
                    .frame(height: 64)
                Text((offsets.isEmpty ? "ยังไม่มีราง" : String(format: "ผังใช้ A = %.0f–%.0f มม.", offsets.first!, offsets.last!))
                     + (zone.map { String(format: " | ช่วงที่รับรอง %.0f–%.0f มม.", $0.lowerBound, $0.upperBound) } ?? " | ไม่รับรองการจับด้านนี้"))
                    .font(.sarabunFixed(12)).foregroundStyle(outside ? Theme.dangerText : Theme.inkMuted)
                if outside, let zone, g.clampSide == .long {
                    Button("ใช้ช่วงจับตาม ZNSHINE ในงานนี้") {
                        setStandard { s in s.clampMin = (zone.lowerBound / 10).rounded() / 100; s.clampMax = (zone.upperBound / 10).rounded() / 100 }
                    }
                    .font(.sarabunFixed(13, .bold)).frame(minHeight: 44)
                }
            }
        }
    }
}

/// A module's clamped side as a bar: the rated zones at both ends (green) and the rails the layout uses (navy ticks),
/// red when outside a zone.
struct ClampZoneOutline: View {
    let side: Double
    let zone: ClosedRange<Double>?
    let offsets: [Double]

    var body: some View {
        Canvas { ctx, size in
            let k = (size.width - 4) / max(side, 1), y0 = size.height * 0.3, h = size.height * 0.4
            func x(_ mm: Double) -> CGFloat { 2 + mm * k }
            ctx.fill(Path(CGRect(x: 2, y: y0, width: side * k, height: h)), with: .color(Theme.primary.opacity(0.12)))
            ctx.stroke(Path(CGRect(x: 2, y: y0, width: side * k, height: h)), with: .color(Theme.navy), lineWidth: 1.2)
            if let z = zone {
                for (a, b) in [(z.lowerBound, z.upperBound), (side - z.upperBound, side - z.lowerBound)] {
                    ctx.fill(Path(CGRect(x: x(a), y: y0, width: (b - a) * k, height: h)), with: .color(Theme.success.opacity(0.35)))
                }
            }
            for o in offsets {
                for at in [o, side - o] {
                    let ok = zone?.contains(o) ?? false
                    var p = Path(); p.move(to: CGPoint(x: x(at), y: y0 - 8)); p.addLine(to: CGPoint(x: x(at), y: y0 + h + 8))
                    ctx.stroke(p, with: .color(ok ? Theme.navy : Theme.danger), lineWidth: 2)
                }
            }
        }
        .accessibilityLabel(zone.map { String(format: "ช่วงจับที่รับรอง %.0f ถึง %.0f มิลลิเมตรจากปลายแผง", $0.lowerBound, $0.upperBound) } ?? "ด้านนี้ไม่รับรองการจับ")
    }
}
#endif
