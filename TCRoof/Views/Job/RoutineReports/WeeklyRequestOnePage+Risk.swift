import SwiftUI
import TCRoofUI
import TCRoofCore

// The risk sheet (docs/ui/weekly-request-ipad-map §4.5, state 06): a hazard's 5 × 5 grid of severity by likelihood,
// the level it gives, the band key and the controls. The week keeps one assessment per hazard.

extension WeeklyRequestOnePage {
    /// The hazard being scored, for which line, and the cell picked so far.
    struct RiskEdit: Equatable {
        let hazard: RoutineReport.Hazard
        let line: UUID
        var likelihood: Int
        var severity: Int
    }

    func riskSheet(_ e: RiskEdit) -> some View {
        ZStack {
            Theme.navySolid.opacity(0.35).ignoresSafeArea()
                .onTapGesture { riskEdit = nil }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                riskHeader(e)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                HStack(alignment: .top, spacing: 24) {
                    AnyView(riskGrid(e))
                    AnyView(riskPanel(e))
                }
                .padding(.horizontal, 24).padding(.vertical, 18)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                riskFooter(e)
            }
            .frame(width: 770)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Theme.navySolid.opacity(0.18), radius: 24, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("requestRiskSheet")
        }
        .transition(.opacity)
    }

    private func riskHeader(_ e: RiskEdit) -> some View {
        let line = request.work.first { $0.id == e.line }
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.hazard.name).font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                Text("ประเมินความเสี่ยง " + (line?.description ?? "")).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { riskEdit = nil } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.navy)
                    .frame(width: 44, height: 44).background(Theme.segmentTrack, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปิด")
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    private func riskGrid(_ e: RiskEdit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ความรุนแรง แตะช่องที่ตรงกับงานนี้").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
            ForEach((1...5).reversed(), id: \.self) { s in
                HStack(spacing: 6) {
                    Text("\(s) \(RoutineReport.severityTitles[s - 1])").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
                        .frame(width: 92, alignment: .trailing)
                    ForEach(1...5, id: \.self) { l in riskCell(e, likelihood: l, severity: s) }
                }
            }
            HStack(alignment: .top, spacing: 6) {
                Color.clear.frame(width: 92, height: 1)
                ForEach(1...5, id: \.self) { l in
                    Text("\(l) \(RoutineReport.likelihoodTitles[l - 1])").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center).frame(width: 54)
                }
            }
            Text("โอกาสเกิด →").font(.sarabunFixed(12.5, .bold)).foregroundStyle(Theme.navy).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .fixedSize()
    }

    private func riskCell(_ e: RiskEdit, likelihood l: Int, severity s: Int) -> some View {
        let score = l * s, band = RoutineReport.RiskBand(score: score), on = e.likelihood == l && e.severity == s
        return Button { riskEdit?.likelihood = l; riskEdit?.severity = s } label: {
            Text("\(score)").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                .frame(width: 54, height: 48)
                .background(Theme.riskBandsSoft[band.rawValue], in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay { if on { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.navy, lineWidth: 3) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("โอกาส \(l) ความรุนแรง \(s) คะแนน \(score)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("riskCell\(l)-\(s)")
    }

    private func riskPanel(_ e: RiskEdit) -> some View {
        let score = e.likelihood * e.severity, band = RoutineReport.RiskBand(score: score)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ระดับความเสี่ยง").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
                HStack(spacing: 14) {
                    Text("โอกาส \(e.likelihood) × ความรุนแรง \(e.severity) = \(score)").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                    Text(band.title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.riskBands[band.rawValue])
                        .accessibilityIdentifier("riskBand")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("riskLevel")
                ForEach(RoutineReport.RiskBand.allCases, id: \.self) { b in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.riskBands[b.rawValue]).frame(width: 10, height: 10)
                        Text("\(b.range) \(b.title)").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text("มาตรการควบคุม (Hierarchy of Controls)").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                ForEach(e.hazard.controls, id: \.self) { c in
                    Text(c).font(.sarabunFixed(14)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.borderOutdoor).frame(width: 2) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func riskFooter(_ e: RiskEdit) -> some View {
        HStack(spacing: 12) {
            if request.risk(for: e.hazard) != nil {
                Button {
                    request.removeAssessment(e.hazard)
                    riskEdit = nil
                } label: {
                    Text("ไม่ใช้กับงานนี้").font(.sarabunFixed(16, .bold)).padding(.horizontal, 6)
                }
                .buttonStyle(TCButtonStyle(.destructive, size: .card))
                .accessibilityIdentifier("riskRemove")
            }
            Spacer(minLength: 8)
            Button { riskEdit = nil } label: { Text("ยกเลิก").font(.sarabunFixed(16, .bold)).frame(width: 96) }
                .buttonStyle(TCButtonStyle(.secondary, size: .card))
            Button {
                request.assess(e.hazard, likelihood: e.likelihood, severity: e.severity)
                riskEdit = nil
            } label: { Text("บันทึกระดับ").font(.sarabunFixed(16, .bold)).frame(width: 128) }
                .buttonStyle(TCButtonStyle(.primary, size: .card))
                .accessibilityIdentifier("riskSave")
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }
}
