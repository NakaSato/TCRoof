#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// D1 on iPhone (docs/ui/survey-d1-size-iphone, 390 × 844): the step line with the photo chip, the four sub-steps as
/// numbered circles, then sub-step 1 as two cards (the plan drawn from the size, the tank's data) in one scroll.
/// The bottom bar's ‹ › step through the sub-steps (`JobEditor.tankSubSteps`).
extension TankPageWide {
    static let phoneTitles = ["ขนาดถัง", "สิ่งกีดขวาง", "จัดแผง", "ภาพถ่าย"]

    var phoneBody: some View {
        VStack(spacing: 8) {
            PageStepBar(job: job, here: .module(moduleID), compact: true, chip: photoChip)
            if tab == 1 {
                ScrollView { phoneSizeCards.padding(.top, 2).padding(.bottom, 8) }
                    .scrollIndicators(.hidden)
            } else if tab == 2 {
                ScrollView { phoneObstacleCards.padding(.top, 2).padding(.bottom, 8) }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(debugBottom ? .bottom : .top)
            } else if tab == 3 {
                ScrollView { phoneLayoutCards.padding(.top, 2).padding(.bottom, 8) }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(debugBottom ? .bottom : .top)
            } else {
                phoneTabs
                formStep
            }
        }
        .fullScreenCover(isPresented: $planFull) { planFullScreen }
    }

    /// `-surveyD1 obstbottom` / `layoutbottom`: sub-step 2 / 3 scrolled to its end (no scrolling in the simulator here).
    var debugBottom: Bool {
        #if DEBUG
        ["obstbottom", "layoutbottom"].contains(UserDefaults.standard.string(forKey: "surveyD1") ?? "")
        #else
        false
        #endif
    }

    var phoneSizeCards: some View {
        VStack(spacing: 12) {
            phoneTabs
            phonePlanCard
            phoneInfoCard
        }
    }

    /// "ยังขาด 2 ภาพ" while required photos are missing.
    var photoChip: (text: String, ok: Bool)? {
        let c = Tank.photoCompletion(values), k = c.total - c.filled
        return k > 0 ? ("ยังขาด \(k) ภาพ", false) : nil
    }

    // MARK: sub-step tabs

    var phoneTabs: some View {
        let s = steps
        // sub-step 2 is done when every standard point is checked (the shading stays in the section's count), sub-step 3
        // with a layout whose checks all pass
        let done = Self.phoneTitles.indices.map { i in
            i == 1 ? TankPoints.done(values) : i == 2 ? TankLayout.done(values) : s[safe: i]?.done ?? false
        }
        return HStack(spacing: 0) {
            ForEach(Array(Self.phoneTitles.enumerated()), id: \.offset) { i, title in
                // a connector is green from a finished sub-step to one that is finished or open
                let reached = { (k: Int) in done[k] || tab == k + 1 }
                phoneTab(i + 1, title: title, done: done[i],
                         greenBefore: i > 0 && done[i - 1] && reached(i),
                         greenAfter: i + 1 < done.count && done[i] && reached(i + 1))
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ขั้นย่อยของถังน้ำใส")
    }

    /// `greenBefore` / `greenAfter`: the connector halves to the neighbours run green.
    func phoneTab(_ n: Int, title: String, done: Bool, greenBefore: Bool, greenAfter: Bool) -> some View {
        let on = tab == n, last = Self.phoneTitles.count
        return Button { withAnimation(.easeOut(duration: 0.15)) { tab = n; span = nil } } label: {
            VStack(spacing: 3) {
                phoneCircle(n, done: done, current: on)
                    .frame(maxWidth: .infinity).frame(height: 29)
                    .background(alignment: .center) {
                        // the 3-pt connector, from this circle's centre to the neighbours'
                        HStack(spacing: 0) {
                            Rectangle().fill(n > 1 ? (greenBefore ? Theme.stepDone : Theme.borderSubtle) : Color.clear)
                            Rectangle().fill(n < last ? (greenAfter ? Theme.stepDone : Theme.borderSubtle) : Color.clear)
                        }
                        .frame(height: 3)
                    }
                Text(title).font(.system(size: 12, weight: on ? .heavy : .semibold))
                    .foregroundStyle(on ? Theme.primary : done ? Theme.navy : Theme.borderControl).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + (on ? " กำลังทำ" : done ? " เสร็จ" : " ยังไม่เสร็จ"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder func phoneCircle(_ n: Int, done: Bool, current: Bool) -> some View {
        if current {
            Text("\(n)").font(.system(size: 11.5, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.primary))
                .background(Circle().fill(Theme.primary.opacity(0.18)).frame(width: 34, height: 34))
        } else if done {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.stepDone))
        } else {
            Text("\(n)").font(.system(size: 11.5, weight: .heavy)).foregroundStyle(Theme.borderControl)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().strokeBorder(Theme.navy.opacity(0.25), lineWidth: 1.5))
        }
    }

    // MARK: cards

    /// White card, 16-pt corners: a number tile, the title and a chip, then the content.
    func phoneCard<Content: View>(_ n: Int, _ title: String, chip: (text: String, fg: Color, bg: Color),
                                  @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("\(n)").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.primary)
                    .frame(width: 24, height: 24).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 7))
                Text(title).font(.system(size: 16, weight: .bold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(chip.text).font(.system(size: 11, weight: .bold)).foregroundStyle(chip.fg).lineLimit(1).fixedSize()
                    .padding(.horizontal, 8).padding(.vertical, 1)
                    .background(chip.bg, in: Capsule())
            }
            .accessibilityElement(children: .combine)
            content()
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.borderSubtle))
        .shadow(color: Theme.navy.opacity(0.05), radius: 3, y: 2)
    }

    var phonePlanCard: some View {
        phoneCard(1, "แปลนหลังคาถัง", chip: ("วาดจากขนาดถัง", Theme.inkMuted, Theme.primarySoft)) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    if let sketch = TankPlan.compact(values) {
                        GeometryReader { g in
                            SketchCanvas(ops: sketch.ops, fit: SketchFit(sketch.width, sketch.height, in: g.size))
                        }
                        .aspectRatio(sketch.width / sketch.height, contentMode: .fit)
                        .accessibilityElement()
                        .accessibilityLabel("แปลนหลังคาถังน้ำใส " + (Tank.sizeLabel(values)?.name ?? ""))
                    } else {
                        emptyPlan.frame(height: 260)
                    }
                    Button { planFull = true } label: {
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
                    .disabled(!Tank.hasSize(values))
                }
                if let caption = planCaption {
                    Text(caption).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, 10).padding(.bottom, 8)
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
        }
    }

    /// "แปลนหลังคาถังน้ำใส 40 × 40 ม. · หน่วย ม."
    var planCaption: String? {
        let s = Tank.spans(values)
        guard !s.x.isEmpty, !s.y.isEmpty else { return nil }
        return "แปลนหลังคาถังน้ำใส \(fmt(s.x.reduce(0, +))) × \(fmt(s.y.reduce(0, +))) ม. · หน่วย ม."
    }

    /// The full plan with the span numbers to edit, full screen.
    var planFullScreen: some View {
        NavigationStack {
            planCard
                .padding(16)
                .background(Theme.background)
                .navigationTitle("แปลนหลังคาถัง")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { span = nil; planFull = false } }
                }
        }
        .foregroundStyle(Theme.navy)
    }

    /// Required fields of sub-step 1 still empty.
    var sizeMissing: Int {
        [Tank.hasSize(values), Tank.typeName(values) != nil, Tank.height(values) != nil, Tank.position(values) != nil,
         !values.text(Tank.Key.surface).trimmingCharacters(in: .whitespaces).isEmpty].filter { !$0 }.count
    }

    var phoneInfoCard: some View {
        let k = sizeMissing
        let chip = k == 0 ? ("✓ ครบ", Theme.okTick, Theme.okSoft) : ("ขาด \(k) ช่อง", Theme.pending, Theme.pendingSoft)
        return infoSheets(phoneCard(2, "ข้อมูลถัง", chip: chip) {
            sizeField
            typeField
            phoneLevels
            field("ตำแหน่งถัง", required: true) { positionControl }
            phoneSurfaceRow
            azimuthField
        })
    }

    var phoneLevels: some View {
        HStack(alignment: .top, spacing: 8) {
            field("ความสูงถัง", required: true) {
                TankStepper(value: Tank.height(values), step: 0.1, range: Tank.minHeight...200, label: "ความสูงถัง", unit: "ม.", glyph: 17) { h in
                    update { Tank.setHeight(&$0, h) }
                }
            }
            field("ส่วนพ้นดิน") {
                TankStepper(value: Tank.exposed(values), step: 0.1, range: 0...(Tank.height(values) ?? 200), label: "ส่วนพ้นดิน",
                            enabled: Tank.exposedEditable(values), unit: "ม.", glyph: 17) { e in update { Tank.setExposed(&$0, e) } }
            }
        }
    }

    var phoneSurfaceRow: some View {
        HStack(alignment: .top, spacing: 8) {
            field("ผิวหลังคา", required: true) { surfaceField }
            field("ดินกลบลึก") {
                TankStepper(value: values.number(Tank.Key.soil), step: 0.05, range: 0...50, label: "ดินกลบลึก", placeholder: "0.00",
                            unit: "ม.", glyph: 17) { d in update { Tank.setSoil(&$0, d) } }
            }
        }
    }

    /// `บนดิน / ฝังดิน / กึ่งฝัง` as a segmented control: grey track, the chosen one white and bold.
    var phonePositionControl: some View {
        let cur = Tank.position(values)
        return HStack(spacing: 3) {
            ForEach(Tank.positions, id: \.self) { p in
                let on = cur == p
                Button { update { Tank.setPosition(&$0, p) } } label: {
                    Text(p).font(.system(size: 14, weight: on ? .bold : .regular)).foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 8).fill(Theme.surface).shadow(color: Theme.navy.opacity(0.2), radius: 1.5, y: 1) }
                        }
                        // 44 pt with the track's padding
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
}
#endif
