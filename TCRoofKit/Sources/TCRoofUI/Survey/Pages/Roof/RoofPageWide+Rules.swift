#if canImport(UIKit)
import SwiftUI
import TCRoofCore
import ModuleRules

/// แผงบนหลังคา's installation checks from ZNSHINE's manual (docs/specs/module-install-rules.md §7.2): the catalog model,
/// the mounting method with its torque, washer and load rating, the clamp zone on a module outline, the string builder,
/// cable and grounding, and the rules they raise. The layout gives tilt, orientation, clamp side and offsets, gap and
/// rails; the rest is `ArrayLayoutCheck`, kept as JSON in `pvRules`.
extension RoofPageWide {
    static let rulesKey = "pvRules"
    static let methods: [(MountingMethod, String)] = [(.clamp, "ตัวจับ (clamp)"), (.bolt, "ยึดน็อตผ่านรู"), (.tracker1P, "แทรคเกอร์ 1 แกน"), (.tracker2V, "แทรคเกอร์ 2V")]

    var layoutCheck: ArrayLayoutCheck { ArrayLayoutCheck.decode(values.text(Self.rulesKey)) }

    func setLayoutCheck(_ f: (inout ArrayLayoutCheck) -> Void) {
        var c = layoutCheck
        f(&c)
        update { $0[Self.rulesKey] = c == ArrayLayoutCheck() ? nil : .text(c.json) }
    }

    /// The catalog model in use: the one picked, else the one matching the layout's module.
    var rulesModule: ModuleModel? {
        if let m = layoutCheck.module { return m }
        let s = mountChoice.standardOrDefault
        return ArrayLayoutCheck.match(wp: s.moduleWp, lengthMm: s.moduleLength * 1000, widthMm: s.moduleWidth * 1000)
    }

    /// The record with the effective module, for the engine.
    var effectiveLayoutCheck: ArrayLayoutCheck {
        var c = layoutCheck
        if c.moduleID == nil { c.moduleID = rulesModule?.id }
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

    func ruleNumber(_ kp: WritableKeyPath<ArrayLayoutCheck, Double?>) -> Binding<Double?> {
        Binding(get: { layoutCheck[keyPath: kp] }, set: { v in setLayoutCheck { $0[keyPath: kp] = v } })
    }
    func ruleCount(_ kp: WritableKeyPath<ArrayLayoutCheck, Int?>) -> Binding<Double?> {
        Binding(get: { layoutCheck[keyPath: kp].map(Double.init) }, set: { v in setLayoutCheck { $0[keyPath: kp] = v.map { Int($0.rounded()) } } })
    }
    func ruleReason(_ id: String) -> Binding<String> {
        Binding(get: { layoutCheck.reasons[id] ?? "" }, set: { v in setLayoutCheck { $0.reasons[id] = v.isEmpty ? nil : v } })
    }

    /// A labelled number field: TCNumberField's title is only spoken.
    func ruleField<F: View>(_ title: String, @ViewBuilder _ field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
            field()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                ModuleRulesList(c.validation(g), empty: "ผ่านทุกข้อที่ตรวจได้", reason: ruleReason)
            } else {
                Text("ยังไม่มีผังแผง").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            rulesModulePicker
            rulesMethod
            rulesClamp
            rulesStrings
            rulesCable
        }
        .padding(12)
        .background(Self.track.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Picking a catalog model sets the layout's module too.
    var rulesModulePicker: some View {
        let m = rulesModule
        return VStack(alignment: .leading, spacing: 4) {
            A3Label(text: "รุ่นแผงตามแคตตาล็อก")
            Menu {
                ForEach(ModuleCatalog.models) { model in
                    Button(model.id + String(format: " | %.0f W", model.pmaxW)) {
                        setLayoutCheck { $0.moduleID = model.id }
                        setStandard { s in
                            s.moduleLength = model.lengthMm / 1000; s.moduleWidth = model.widthMm / 1000
                            s.moduleWp = model.pmaxW; if model.weightKg > 0 { s.moduleKg = model.weightKg }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(m.map { $0.id + String(format: " | %.0f W | %d เซลล์ (%@)", $0.pmaxW, $0.cellCount, $0.sizeClass == .big ? "ใหญ่" : "เล็ก") }
                         ?? "ไม่ตรงกับแคตตาล็อก | เลือกรุ่น")
                        .font(.sarabunFixed(14, .bold)).foregroundStyle(m == nil ? Self.amber : Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 10).frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.navy.opacity(0.3)))
            }
            if let m, m.doubleGlass {
                Text("แผงกระจกสองชั้น: คู่มือฉบับนี้เขียนสำหรับแผงกระจกชั้นเดียว").font(.sarabunFixed(11.5)).foregroundStyle(Self.amber)
            }
        }
    }

    var rulesMethod: some View {
        let method = layoutCheck.method ?? .clamp
        let p = ModuleCatalog.profile(method)
        return VStack(alignment: .leading, spacing: 4) {
            A3Label(text: "วิธียึดตามคู่มือ")
            RoofSegments(options: Self.methods.map(\.1), selected: Self.methods.firstIndex { $0.0 == method }, minSegment: 70) { i in
                setLayoutCheck { $0.method = Self.methods[i].0 }
            }
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
            HStack(spacing: 8) {
                ruleField("ตัวจับยาว") { TCNumberField("ตัวจับยาว", value: ruleNumber(\.clampLengthMm), range: 0...500, unit: "มม.") }
                ruleField("ตัวจับหนา") { TCNumberField("ตัวจับหนา", value: ruleNumber(\.clampThicknessMm), range: 0...50, step: 0.5, unit: "มม.") }
                ruleField("ตัวจับต่อแผง") { TCNumberField("ตัวจับต่อแผง", value: ruleCount(\.clampsPerModule), range: 0...12, unit: "ตัว") }
            }
            ruleField("ระยะใต้แผงถึงหลังคา") { TCNumberField("ระยะใต้แผงถึงหลังคา", value: ruleNumber(\.rearClearanceMm), range: 0...2000, unit: "มม.") }
        }
    }

    // MARK: strings and cable

    @ViewBuilder var rulesStrings: some View {
        let c = effectiveLayoutCheck
        VStack(alignment: .leading, spacing: 4) {
            A3Label(text: "สตริง")
            HStack(spacing: 8) {
                ruleField("แผงต่อสตริง") { TCNumberField("แผงต่อสตริง", value: ruleCount(\.modulesPerString), range: 0...60, unit: "แผง") }
                ruleField("อินเวอร์เตอร์ DC สูงสุด") { TCNumberField("อินเวอร์เตอร์ DC สูงสุด", value: ruleNumber(\.inverterMaxDcV), range: 0...2000, unit: "V") }
                ruleField("T_min") { TCNumberField("T_min", value: ruleNumber(\.tMinC), range: -50...40, unit: "°C") }
            }
            if layoutCheck.inverterMaxDcV == nil {
                Button("ใช้ 1100 V (Growatt MAX)") { setLayoutCheck { $0.inverterMaxDcV = 1100 } }
                    .font(.sarabunFixed(13, .bold)).frame(minHeight: 44)
            }
            if let s = c.stringLimit {
                let n = layoutCheck.modulesPerString ?? 0
                Text(String(format: "ได้สูงสุด %d แผง | Voc ที่ T_min %.1f V ต่อแผง", s.nmax, s.coldVoc)
                     + (n > 0 ? String(format: " | %d แผง = %.0f V จาก %.0f V", n, Double(n) * s.coldVoc, s.limitV) : ""))
                    .font(.sarabunFixed(12.5, .bold)).foregroundStyle(n > s.nmax ? Theme.dangerText : Theme.navy)
            } else if rulesModule != nil && rulesModule?.betaVocPctPerC == nil {
                Text("แผงรุ่นนี้ยังไม่มีค่าสัมประสิทธิ์อุณหภูมิ Voc").font(.sarabunFixed(12)).foregroundStyle(Theme.dangerText)
            } else {
                Text("ใส่ T_min เพื่อคำนวณจำนวนแผงสูงสุดต่อสตริง").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            if (layoutGeometry?.tiltsByFace.count ?? 0) > 1 {
                Toggle(isOn: Binding(get: { layoutCheck.stringAcrossFaces ?? false }, set: { v in setLayoutCheck { $0.stringAcrossFaces = v } })) {
                    Text("มีสตริงข้ามด้านหลังคา").font(.sarabunFixed(14))
                }
                .tint(Theme.primary).frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder var rulesCable: some View {
        VStack(alignment: .leading, spacing: 4) {
            A3Label(text: "สาย DC และสายดิน")
            HStack(spacing: 8) {
                ruleField("ขนาดสาย") { TCNumberField("ขนาดสาย", value: ruleNumber(\.cableMm2), range: 0...300, step: 0.5, unit: "ตร.มม.") }
                ruleField("พิกัดกระแสสาย") { TCNumberField("พิกัดกระแสสาย", value: ruleNumber(\.cableAmpacityA), range: 0...1000, step: 0.5, unit: "A") }
                ruleField("ต่อขนาน") { TCNumberField("ต่อขนาน", value: ruleCount(\.parallelCount), range: 0...20, unit: "ชุด") }
            }
            if let m = rulesModule {
                Text(String(format: "ต้องรับกระแสได้ ≥ 1.25 × %.2f × %d = %.2f A", m.iscA, max(1, layoutCheck.parallelCount ?? 1),
                            ModuleRules.minCableAmpacity(module: m, parallelCount: max(1, layoutCheck.parallelCount ?? 1))))
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            HStack(spacing: 8) {
                ruleField("สายดินต่อขนาน") { TCNumberField("สายดินต่อขนาน", value: ruleCount(\.groundingParallel), range: 0...20, unit: "แผง") }
                ruleField("สายดินต่ออนุกรม") { TCNumberField("สายดินต่ออนุกรม", value: ruleCount(\.groundingSeries), range: 0...40, unit: "แผง") }
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
