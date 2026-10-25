#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// The iPhone `จัดแผง` tab (docs/ui/survey-c1-iphone-pv): the plan's count tag and buttons, `02 แผงและการวาง`,
/// `03 สรุปการจัดแผง`, and everything else under one closed section.
extension RoofPageWide {
    // MARK: plan

    /// `<n> แผง · <kWp> kWp` at the plan's top left; the same numbers as the summary.
    var planTag: some View {
        let q = shownMount?.quantities
        return VStack {
            HStack {
                Text("\(q?.modules ?? 0) แผง · " + String(format: "%.1f", q?.kWp ?? 0) + " kWp")
                    .font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.primary, in: Capsule())
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    /// `แก้แผง · จัดแผงใหม่ · CAD`, the edit hint, then `ย้อน` and `วาด`.
    var mountPhoneFooter: some View {
        let out = mountChoice.removed.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                footerButton(editModules ? "เสร็จ" : "แก้แผง", icon: editModules ? nil : "pencil", on: editModules,
                             tint: editModules ? Theme.primary : Theme.navy, fill: true) {
                    editModules.toggle(); tool = nil; span = nil; mountSelection = nil
                }
                .accessibilityIdentifier("editModules")
                footerButton("จัดแผงใหม่", icon: "arrow.triangle.2.circlepath", fill: true) {
                    changeChoice { $0.removed = [] }; editModules = false
                }
                .disabled(out == 0).opacity(out == 0 ? 0.45 : 1)
                .accessibilityIdentifier("resetModules")
                cadButton(fill: true)
            }
            if editModules {
                Text("แตะแผงบนแปลนเพื่อเอาออกหรือใส่กลับ · เอาออกแล้ว \(out) แผ่น")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.primary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("editHint")
            }
            HStack(spacing: 8) {
                undoButton
                Spacer(minLength: 0)
                drawMenu
            }
        }
    }

    // MARK: numbered cards

    func numberedHeader(_ number: String, _ title: String, pill: (text: String, ok: Bool)? = nil) -> some View {
        HStack(spacing: 10) {
            Text(number).font(.sarabunFixed(24, .bold)).foregroundStyle(Theme.primary)
            Rectangle().fill(Theme.borderSubtle).frame(width: 1, height: 22)
            Text(title).font(.sarabunFixed(16, .bold)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if let pill {
                Text(pill.text).font(.sarabunFixed(12, .bold)).foregroundStyle(pill.ok ? Theme.okText : Theme.inkMuted)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(pill.ok ? Theme.okSoft : Self.track, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// `02 แผงและการวาง`: module, orientation, edge distance, ridge walkway and roof access.
    var mountSettingsPhone: some View {
        let c = mountChoice, has = (shownMount?.quantities.modules ?? 0) > 0
        return VStack(alignment: .leading, spacing: 10) {
            numberedHeader("02", "แผงและการวาง", pill: has ? ("✓ ครบ", true) : ("ยังไม่มีแผง", false))
            moduleRow
            VStack(alignment: .leading, spacing: 6) {
                A3Label(text: "การวางแผง")
                RoofSegments(options: ["แนวตั้ง", "แนวนอน"], selected: c.landscape ? 1 : 0, minSegment: 100, height: 44) { i in
                    changeChoice { $0.landscape = i == 1 }
                }
            }
            landscapeArrangement.id("pairs")
            edgeStepper
            mountRidgeWalkway.id("walkway")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.track, in: RoundedRectangle(cornerRadius: 12))
    }

    /// One distance from the roof's edge: sets the eave and the verge together (the ridge is the walkway's).
    var edgeStepper: some View {
        let s = mountChoice.standardOrDefault, v = max(s.setEave, s.setVerge)
        let lo = 0.30, hi = 1.50
        func set(_ x: Double) { setStandard { $0.setEave = x; $0.setVerge = x } }
        return HStack(spacing: 6) {
            Text("ระยะห่างจากขอบหลังคา").font(.sarabunFixed(13)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            stepButton("minus", enabled: v - 0.1 >= lo - 1e-9) { set(max(lo, ((v - 0.1) * 100).rounded() / 100)) }
            Text(String(format: "%.2f ม.", v)).font(.sarabunFixed(14, .bold)).monospacedDigit().frame(minWidth: 62)
            stepButton("plus", enabled: v + 0.1 <= hi + 1e-9) { set(min(hi, ((v + 0.1) * 100).rounded() / 100)) }
        }
        .frame(minHeight: 52)
    }

    /// `03 สรุปการจัดแผง`: four tiles, then the count the report takes and the energy.
    var mountSummaryPhone: some View {
        let q = shownMount?.quantities, s = mountChoice.standardOrDefault
        let n = q?.modules ?? 0
        let perRow = (shownMount?.faces ?? []).filter(\.used).flatMap(\.rows).map { $0.slots.filter(\.isModule).count }.max() ?? 0
        let area = Double(n) * s.moduleLength * s.moduleWidth
        return VStack(alignment: .leading, spacing: 10) {
            numberedHeader("03", "สรุปการจัดแผง")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                summaryTile("\(n)", "แผง", note: mountBusy ? "กำลังจัดผัง…" : (mountChoice.landscape ? "แนวนอน" : "แนวตั้ง") + " · \(perRow) แผงต่อแถว")
                    .accessibilityIdentifier("tileCount")
                summaryTile(String(format: "%.1f", q?.kWp ?? 0), "kWp", note: "\(n) × \(Int(s.moduleWp)) W")
                stringTile
                summaryTile(String(format: "%.1f", area), "ตร.ม.", note: String(format: "%d × %.2f × %.2f ม.", n, s.moduleLength, s.moduleWidth))
            }
            panelsField(n)
            mountEnergy
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.track, in: RoundedRectangle(cornerRadius: 12))
    }

    /// `สตริง`: full strings × modules per string, from the module on B2's inverter (`RoofMountYield.stringPlan`).
    @ViewBuilder var stringTile: some View {
        if let p = mountYieldInputs.flatMap(RoofMountYield.stringPlan) {
            let note = "\(p.strings) × \(p.perString) แผง" + (p.leftover > 0 ? " | เหลือ \(p.leftover) แผง" : "")
                + (p.fits ? "" : " | เกินช่อง \(p.inputs) สตริง")
            summaryTile("\(p.strings)", "สตริง", note: note)
                .accessibilityIdentifier("tileStrings")
        } else {
            summaryTile("—", "สตริง", note: "ยังไม่มีแบบจำลองแผงหรืออินเวอร์เตอร์")
                .accessibilityIdentifier("tileStrings")
        }
    }

    /// Everything else the tab had, behind one closed row.
    var mountMorePhone: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { moreOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("ตั้งค่าและรายละเอียดเพิ่มเติม").font(.sarabunFixed(15, .bold))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkMuted)
                        .rotationEffect(.degrees(moreOpen ? 180 : 0))
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pvMore")
            .accessibilityValue(moreOpen ? "เปิดอยู่" : "ปิดอยู่")
            if moreOpen {
                mountFixing
                mountShedSide
                mountCleaningWalkway
                mountFaces
                mountAlign
                mountBearing
                mountQuantities
                mountRules.id("rules")
                mountFooter
            }
        }
        .onChange(of: scrollTarget) { _, t in if let t, ["rules", "most"].contains(t) { moreOpen = true } }
    }
}
#endif
