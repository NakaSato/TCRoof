#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// D1 sub-step 1 "ขนาดถัง": the plan card and the `ข้อมูลถัง` card.
extension TankPageWide {
    // MARK: plan card

    var planCard: some View {
        card {
            GeometryReader { geo in
                if let plan = TankPlan(values, width: 690, chips: true, hints: true) {
                    let fit = SketchFit(plan.sketch.width, plan.sketch.height, in: geo.size)
                    ZStack(alignment: .topLeading) {
                        SketchCanvas(ops: plan.sketch.ops, fit: fit)
                            .accessibilityLabel("แปลนหลังคาถังน้ำใส " + (Tank.sizeLabel(values)?.name ?? ""))
                        ForEach(Array(plan.chips.enumerated()), id: \.offset) { _, c in
                            spanChip(c, fit: fit).position(fit.point(c.at))
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .popover(isPresented: Binding(get: { span != nil }, set: { if !$0 { span = nil } }),
                             attachmentAnchor: .rect(.rect(chipRect(plan, fit))), arrowEdge: span?.axis == .y ? .leading : .top) {
                        spanEditor.presentationCompactAdaptation(.popover)
                    }
                } else {
                    emptyPlan
                }
            }
        }
    }

    /// A tank with no spans yet: an empty frame and the hint.
    var emptyPlan: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(Home.navy.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3").font(.system(size: 34)).foregroundStyle(Home.disabledText)
                    Text("เลือกขนาดถัง").font(.system(size: 17, weight: .bold)).foregroundStyle(Home.muted)
                }
            }
            .padding(24)
    }

    func chipRect(_ plan: TankPlan, _ fit: SketchFit) -> CGRect {
        guard let span, let c = plan.chips.first(where: { $0.axis == span.axis && $0.index == span.index }) else { return .zero }
        let p = fit.point(c.at)
        return CGRect(x: p.x - 18, y: p.y - 12, width: 36, height: 24)
    }

    /// The span's number: tap to edit it with C1's span editor.
    func spanChip(_ c: TankPlan.Chip, fit: SketchFit) -> some View {
        let ref = RoofPageWide.SpanRef(axis: c.axis, index: c.index), on = span == ref
        let chip = Text(String(format: "%.2f", c.value)).font(.system(size: max(10, 8.5 * fit.s), weight: on ? .bold : .regular)).underline(!on)
            .foregroundStyle(Home.primary).lineLimit(1).fixedSize().padding(.horizontal, 3)
            .background(on ? RoofPageWide.soft : Color.white.opacity(0.01), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Home.primary : Color.clear, lineWidth: 1.5))
            .rotationEffect(.degrees(c.axis == .y ? -90 : 0))
        return Button { span = on ? nil : ref } label: { chip.frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel("แก้ระยะช่วง " + Roof.spanName(c.axis, c.index) + " " + fmt(c.value) + " เมตร")
    }

    @ViewBuilder var spanEditor: some View {
        if let ref = span {
            SpanEditor(spans: Roof.spans(values, ref.axis), ref: ref,
                       set: { s, i in update { Roof.setSpans(&$0, ref.axis, s) }; span = RoofPageWide.SpanRef(axis: ref.axis, index: i) },
                       select: { span = $0 })
        }
    }

    // MARK: info card

    func infoCard(fill: Bool) -> some View {
        card {
            Text("ข้อมูลถัง").font(.system(size: 17, weight: .bold))
            sizeField
            typeField
            HStack(alignment: .top, spacing: 10) {
                field("ความสูงถัง", unit: "(ม.)", required: true) {
                    TankStepper(value: Tank.height(values), step: 0.1, range: Tank.minHeight...200, label: "ความสูงถัง") { h in update { Tank.setHeight(&$0, h) } }
                }
                field("ส่วนพ้นดิน", unit: "(ม.)") {
                    TankStepper(value: Tank.exposed(values), step: 0.1, range: 0...(Tank.height(values) ?? 200), label: "ส่วนพ้นดิน",
                                enabled: Tank.exposedEditable(values)) { e in update { Tank.setExposed(&$0, e) } }
                }
            }
            field("ตำแหน่งถัง", required: true) { positionControl }
            HStack(alignment: .top, spacing: 10) {
                field("ผิวหลังคา", required: true) { surfaceField }
                field("ดินกลบลึก", unit: "(ม.)") {
                    TankStepper(value: values.number(Tank.Key.soil), step: 0.05, range: 0...50, label: "ดินกลบลึก", placeholder: "0.00") { d in update { Tank.setSoil(&$0, d) } }
                }
            }
            azimuthField
            if fill { Spacer(minLength: 8) }
            nextButton("ถัดไป · สิ่งกีดขวาง ›") { withAnimation { tab = 2 } }.padding(.top, fill ? 0 : 6)
        }
        .confirmationDialog("เปลี่ยนขนาดถัง?", isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } }),
                            titleVisibility: .visible, presenting: pendingPreset) { p in
            Button("เปลี่ยนเป็น " + p.name, role: .destructive) { update { Tank.apply(&$0, p) }; pendingPreset = nil }
            Button("ยกเลิก", role: .cancel) { pendingPreset = nil }
        } message: { _ in Text("ตำแหน่งสิ่งกีดขวางเดิมอาจอยู่นอกแปลน") }
        .alert("ระบุชนิดถัง", isPresented: $typeOther) {
            TextField("พิมพ์ชนิดถัง", text: $otherText)
            Button("ตกลง") {
                let t = otherText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { set(Tank.Key.type, .choice("อื่นๆ", other: t)) }
            }
            Button("ยกเลิก", role: .cancel) {}
        }
        .alert("ทิศของถัง (องศา 0–359)", isPresented: $azEntry) {
            TextField("เช่น 90", text: $azText).keyboardType(.numberPad)
            Button("ตกลง") {
                if let a = NumberInput.value(azText), a >= 0, a < 360 { update { Tank.setAzimuth(&$0, Int(a.rounded()) % 360, source: .manual) } }
            }
            if Tank.azimuth(values) != nil { Button("ล้างค่า", role: .destructive) { update { Tank.setAzimuth(&$0, nil, source: .manual) } } }
            Button("ยกเลิก", role: .cancel) {}
        } message: { Text("ผนังบน (แนว A) หันไปทิศ") }
        .fullScreenCover(isPresented: $compass) {
            TankCompassView(lastColumn: Tank.spans(values).x.count + 1, close: { compass = false }) { az, accuracy in
                update { Tank.setAzimuth(&$0, az, source: accuracy == nil ? .manual : .compass, accuracy: accuracy) }
                compass = false
            }
        }
    }

    /// A 15 pt label, a red * for required fields, the unit / aside in muted grey, then the control.
    func field<Content: View>(_ label: String, unit: String? = nil, aside: String? = nil, required: Bool = false,
                              @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label).font(.system(size: 15, weight: .bold)).lineLimit(1)
                if let unit { Text(unit).font(.system(size: 12)).foregroundStyle(Home.muted) }
                if required { Text("*").font(.system(size: 15, weight: .bold)).foregroundStyle(Home.danger) }
                Spacer(minLength: 4)
                if let aside { Text(aside).font(.system(size: 12)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.8) }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: size

    var sizeField: some View {
        let shown = Tank.sizeLabel(values)
        return field("ขนาดถัง", aside: "เลือกจากรายการ", required: true) {
            Button { sizeOpen.toggle() } label: {
                HStack(spacing: 6) {
                    if let shown {
                        (Text(shown.name).font(.system(size: 17, weight: .bold)) + Text(" · " + shown.sub).font(.system(size: 13)).foregroundColor(Home.muted))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        Text("เลือกจากรายการ").font(.system(size: 16)).foregroundStyle(Home.muted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(Home.primary)
                }
                .inputBox(focused: sizeOpen, minHeight: 44, trailing: 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ขนาดถัง " + (shown?.name ?? "ยังไม่เลือก"))
            .popover(isPresented: $sizeOpen, arrowEdge: .top) { sizeList.presentationCompactAdaptation(.popover) }
        }
    }

    var sizeList: some View {
        let cur = Tank.preset(values)
        return VStack(spacing: 0) {
            ForEach(Tank.presets, id: \.name) { p in
                let on = cur == p
                Button { choose(p) } label: {
                    HStack(spacing: 10) {
                        Text(p.name).font(.system(size: 16, weight: .bold))
                        Spacer(minLength: 8)
                        Text(p.sub).font(.system(size: 12)).foregroundStyle(Home.muted)
                        if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Home.primary) }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .background(on ? RoofPageWide.soft : Color.white)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                Divider()
            }
            Button {
                sizeOpen = false
                if !Tank.hasSize(values) { update { Tank.apply(&$0, Tank.presets[0]) } }
                // the popover has to close before the span editor opens on the plan
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { span = RoofPageWide.SpanRef(axis: .x, index: 0) }
            } label: {
                HStack {
                    Text("+ กำหนดขนาดเอง (กว้าง × ยาว)").font(.system(size: 15, weight: .bold)).foregroundStyle(Home.primary)
                    Spacer()
                    if cur == nil && Tank.hasSize(values) { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Home.primary) }
                }
                .padding(.horizontal, 14).frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Home.navy)
        .frame(width: 310)
        .padding(.vertical, 4)
    }

    /// A preset replaces the spans; with obstacles placed, ask first.
    func choose(_ p: Tank.Preset) {
        sizeOpen = false
        guard Tank.preset(values) != p else { return }
        if values.obstacles(Roof.Key.obstacles).isEmpty { update { Tank.apply(&$0, p) } }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pendingPreset = p } }
    }

    // MARK: type (not in the design: still required for completion, the PDF and Excel)

    var typeField: some View {
        let name = Tank.typeName(values), choice = values.choice(Tank.Key.type)
        return field("ชนิดถัง", required: true) {
            Menu {
                ForEach(Schema.tankTypes, id: \.self) { t in
                    Button {
                        if t == "อื่นๆ" { otherText = values.other(Tank.Key.type); typeOther = true }
                        else { set(Tank.Key.type, .choice(t, other: "")) }
                    } label: {
                        if choice == t { Label(t == "อื่นๆ" ? "อื่นๆ…" : t, systemImage: "checkmark") } else { Text(t == "อื่นๆ" ? "อื่นๆ…" : t) }
                    }
                }
            } label: {
                HStack {
                    Text(name ?? "เลือก").font(.system(size: 16, weight: name == nil ? .regular : .bold))
                        .foregroundStyle(name == nil ? Home.muted : Home.navy).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(Home.primary)
                }
                .inputBox(minHeight: 44, trailing: 12)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("ชนิดถัง " + (name ?? "ยังไม่เลือก"))
        }
    }

    // MARK: position

    var positionControl: some View {
        let cur = Tank.position(values)
        return HStack(spacing: 6) {
            ForEach(Tank.positions, id: \.self) { p in
                let on = cur == p
                Button { update { Tank.setPosition(&$0, p) } } label: {
                    Text(p).font(.system(size: 15, weight: on ? .bold : .semibold)).foregroundStyle(Home.navy)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Self.teal : Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Home.teal : Home.navy.opacity(0.3), lineWidth: on ? 1.5 : 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    // MARK: surface: suggestions, or any text

    @ViewBuilder var surfaceField: some View {
        let s = values.text(Tank.Key.surface)
        if surfaceTyping {
            HStack(spacing: 4) {
                TextField("พิมพ์ผิวหลังคา", text: Binding(get: { values.text(Tank.Key.surface) },
                                                         set: { set(Tank.Key.surface, $0.isEmpty ? nil : .text($0)) }))
                    .focused($surfaceFocus)
                    .onSubmit { surfaceTyping = false }
                    .onChange(of: surfaceFocus) { _, f in if !f { surfaceTyping = false } }
                    .font(.system(size: 15, weight: .bold))
                surfaceMenu { Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Home.primary).frame(width: 30, height: 44) }
            }
            .inputBox(focused: true, minHeight: 44, trailing: 4)
            .onAppear { surfaceFocus = true }
        } else {
            surfaceMenu {
                HStack {
                    Text(s.isEmpty ? "เลือก" : s).font(.system(size: 15, weight: s.isEmpty ? .regular : .bold))
                        .foregroundStyle(s.isEmpty ? Home.muted : Home.navy).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(Home.primary)
                }
                .inputBox(minHeight: 44, trailing: 10)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("ผิวหลังคา " + (s.isEmpty ? "ยังไม่เลือก" : s))
        }
    }

    func surfaceMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        let s = values.text(Tank.Key.surface)
        return Menu {
            ForEach(Tank.surfaces, id: \.self) { o in
                Button { set(Tank.Key.surface, .text(o)); surfaceTyping = false } label: {
                    if s == o { Label(o, systemImage: "checkmark") } else { Text(o) }
                }
            }
            Divider()
            Button("อื่นๆ…") { surfaceTyping = true }
        } label: { label() }
    }

    // MARK: azimuth

    var azimuthField: some View {
        let az = Tank.azimuth(values)
        return field("ทิศของถัง", aside: "ผนังบน (แนว A) หันไปทิศ") {
            HStack(spacing: 8) {
                Button { azText = az.map(String.init) ?? ""; azEntry = true } label: {
                    HStack(spacing: 6) {
                        if let az {
                            Text("\(az)°").font(.system(size: 17, weight: .bold)).monospacedDigit()
                            Text(Tank.directionName(az)).font(.system(size: 13)).foregroundStyle(Home.muted).lineLimit(1).minimumScaleFactor(0.7)
                        } else {
                            Text("แตะเพื่อป้อน").font(.system(size: 15)).foregroundStyle(Home.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .inputBox(minHeight: 44, trailing: 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ทิศของถัง " + (az.map(Tank.azimuthText) ?? "ยังไม่ระบุ") + " แตะเพื่อป้อนเอง")
                Button { compass = true } label: {
                    HStack(spacing: 6) {
                        A2Icon(name: "d1-compass", fallback: "location.north.circle", size: 18)
                        Text("วัดด้วย iPad").font(.system(size: 15, weight: .bold)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(Home.primary)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.primary.opacity(0.7), lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let line = Tank.sourceLine(values) {
                Text(line).font(.system(size: 12)).foregroundStyle(Home.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// − value + for a length in metres: 44 pt buttons, the value in 16 pt bold; tap the value to type it.
struct TankStepper: View {
    let value: Double?
    let step: Double
    let range: ClosedRange<Double>
    let label: String
    var enabled = true
    var placeholder = "—"
    let set: (Double?) -> Void
    @State var typed = ""
    @FocusState var typing: Bool

    func r2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
    func clamp(_ x: Double) -> Double { min(range.upperBound, max(range.lowerBound, r2(x))) }

    var body: some View {
        HStack(spacing: 4) {
            button("minus", on: enabled && (value ?? range.lowerBound) > range.lowerBound) { set(clamp((value ?? range.lowerBound) - step)) }
            TextField(placeholder, text: $typed)
                .keyboardType(.decimalPad).focused($typing)
                .font(.system(size: 16, weight: .bold)).monospacedDigit().multilineTextAlignment(.center)
                .foregroundStyle(enabled ? Home.navy : Home.disabledText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(enabled ? Color.white : Home.disabledFill, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(typing ? Home.primary : Home.navy.opacity(enabled ? 0.3 : 0.12), lineWidth: typing ? 2 : 1))
                .disabled(!enabled)
                .onSubmit(commit)
                .onChange(of: typing) { _, on in if !on { commit() } }
                .accessibilityLabel(label)
            button("plus", on: enabled && (value ?? range.lowerBound) < range.upperBound) { set(clamp(value.map { $0 + step } ?? range.lowerBound)) }
        }
        .onAppear { typed = text(value) }
        .onChange(of: value) { _, v in if !typing { typed = text(v) } }
    }

    func text(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "" }

    func commit() {
        let t = typed.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { set(nil); return }
        if let v = NumberInput.value(t) { set(clamp(v)) }
        typed = text(value)
    }

    func button(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(on ? Home.primary : Home.disabledText)
                .frame(width: 44, height: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Home.navy.opacity(0.3) : Home.disabledFill))
        }
        .buttonStyle(.plain).disabled(!on)
        .accessibilityLabel((symbol == "plus" ? "เพิ่ม" : "ลด") + label)
    }
}
#endif
