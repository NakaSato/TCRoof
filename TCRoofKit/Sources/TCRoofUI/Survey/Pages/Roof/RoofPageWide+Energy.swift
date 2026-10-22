#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// The แผงบนหลังคา tab's yearly energy (docs/specs/energy-yield): the hourly engine on the layout's faces, modules,
/// catalog module and B2's inverters (`RoofMountYield`), with SolarModel when an input is missing, and which of the
/// two the numbers came from. Worked out off the main thread, 0.6 s after the layout settles.
extension RoofPageWide {
    /// What the estimate depends on; nil until the layout is on screen.
    var mountYieldInputs: RoofMountYield.Inputs? {
        guard mode == .pv, let mount else { return nil }
        return RoofMountYield.inputs(mount, job: job)
    }

    /// The estimate of the layout on screen (not one left from an earlier layout).
    var currentYield: RoofMountYield.Estimate? {
        guard let y = mountYield, let i = mountYieldInputs, mountYieldFor == i else { return nil }
        return y
    }

    /// The energy card's figure, which the report and the workbook print too (`RoofMount.printed`).
    var shownEnergy: Double? { currentYield?.mwh }

    func refreshYield() async {
        guard let inputs = mountYieldInputs else { mountYieldBusy = false; return }
        mountYieldBusy = true
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }
        let estimate = await Task.detached(priority: .utility) { RoofMountYield.estimate(inputs) }.value
        guard !Task.isCancelled else { return }
        mountYield = estimate
        mountYieldFor = inputs
        mountYieldBusy = false
    }

    // MARK: the card

    @ViewBuilder var mountEnergy: some View {
        if let y = currentYield {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    A3Label(text: "พลังงานต่อปี | ประมาณการเบื้องต้น")
                    Spacer(minLength: 4)
                    if mountYieldBusy { ProgressView().controlSize(.small) }
                }
                energyFigures(y)
                energySource(y)
                ForEach(y.faces) { f in energyFaceRow(f) }
                energyNotes(y)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.soft, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
        } else if mountYieldBusy && mount != nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("กำลังคำนวณพลังงานรายชั่วโมง…").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
            }
            .frame(minHeight: 44)
        }
    }

    func energyFigures(_ y: RoofMountYield.Estimate) -> some View {
        let big: CGFloat = narrow ? 20 : 22
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(y.isHourly ? "P50" : "≈").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
            Text(String(format: "%.1f", y.mwh)).font(.sarabunFixed(big, .bold)).monospacedDigit()
            Text("MWh/ปี").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            if let p90 = y.p90MWh {
                Text("P90").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted).padding(.leading, 6)
                Text(String(format: "%.1f", p90)).font(.sarabunFixed(big, .bold)).monospacedDigit()
            }
            Text("\(Int(y.kWhPerKWp.rounded()).formatted()) kWh/kWp").font(.sarabunFixed(13).monospacedDigit())
                .foregroundStyle(Theme.inkMuted).padding(.leading, 6)
            if let pr = y.performanceRatio {
                Text(String(format: "PR %.0f%%", pr * 100)).font(.sarabunFixed(13).monospacedDigit()).foregroundStyle(Theme.inkMuted)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }

    func energySource(_ y: RoofMountYield.Estimate) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: y.isHourly ? "clock.badge.checkmark" : "sun.max")
                .foregroundStyle(y.isHourly ? Theme.primary : Self.amber)
            Text("ที่มา: " + y.sourceLine).font(.sarabunFixed(12.5))
                .foregroundStyle(y.isHourly ? Theme.navy : Self.amber).fixedSize(horizontal: false, vertical: true)
        }
    }

    func energyFaceRow(_ f: RoofMountYield.FaceYield) -> some View {
        let face = mount?.faces.first { $0.face.id == f.id }
        let name = face.map { "\(RoofFace.direction($0.face.azimuth)) \(Int($0.face.azimuth.rounded()))°" } ?? f.id
        return HStack(spacing: 8) {
            Text(name).font(.sarabunFixed(13.5)).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(f.modules) แผง | " + String(format: "%.1f MWh/ปี", f.mwh) + " | \(Int(f.kWhPerKWp.rounded()).formatted()) kWh/kWp")
                .font(.sarabunFixed(12.5).monospacedDigit()).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder func energyNotes(_ y: RoofMountYield.Estimate) -> some View {
        let lines = ([y.inverterLine].compactMap { $0 } + y.assumptions.map { "ค่าสมมติ: " + $0 })
        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
            Text(l).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
        if case .hourly(_, _, _, let attribution) = y.source {
            Text("ข้อมูลอากาศ " + attribution).font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted)
        }
        Text("ไม่ใช่ค่ารับประกัน ผลจริงขึ้นกับอากาศ การล้างแผง และเงา | ยืนยันแบบสุดท้ายด้วย PVsyst")
            .font(.sarabunFixed(11.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
    }
}
#endif
