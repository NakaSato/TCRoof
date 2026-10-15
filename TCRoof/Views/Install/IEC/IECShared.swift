import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// The IEC 62446 test screens (docs/ui/iec62446-test) read and write the job's `IECReport` through this: every edit
/// is saved at once, as the board's `บันทึกอัตโนมัติ` says.
extension Job {
    /// A new test for this station: its name as the sheet's station line and one inverter of the job's size.
    var newIECReport: IECReport {
        let kWp = capacityKW.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
        return IECReport(stationLine: stationName + (capacityKW > 0 ? " ขนาดกำลังผลิต \(kWp) kWp" : ""),
                         inverters: [IECReport.Inverter(ratedKW: inverterKW ?? 0)])
    }

    func updateIEC(_ context: ModelContext, _ change: (inout IECReport) -> Void) {
        var r = iecReport ?? newIECReport
        change(&r)
        iecReport = r
        try? context.save()
    }

    #if DEBUG
    /// `-iecDemo YES`: the แพรกหนามแดง sample of docs/forms/iec62446-pwa, when the job has no test yet (for good).
    func seedIECDemo() {
        guard iecReport == nil, let url = Bundle.main.url(forResource: "iec-demo-praek-nam-daeng", withExtension: "json"),
              let data = try? Data(contentsOf: url), let r = try? IECReport(form: data) else { return }
        iecReport = r
    }
    #endif
}

enum IECFormat {
    static let en = Locale(identifier: "en_US")
    /// `209.76`, `125`, `1000`; `1,504.6` with grouping.
    static func number(_ v: Double, digits: Int = 2, grouping: Bool = false) -> String {
        v.formatted(.number.precision(.fractionLength(0...digits)).grouping(grouping ? .automatic : .never).locale(en))
    }
    /// `125 kW`.
    static func kW(_ v: Double) -> String { number(v, digits: 2) + " kW" }
}

/// The blue header of the IEC screens: back, title and sub line, and trailing controls.
struct IECHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.onPrimary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.onPrimary.opacity(0.6)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("กลับ")
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabunFixed(22, .bold)).lineLimit(1).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.sarabunFixed(15)).opacity(0.92).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 14)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15, style: .continuous)
                .fill(Theme.headerGradient).ignoresSafeArea(edges: .top)
        }
    }
}

/// An outlined button on the blue header.
struct IECHeaderButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.sarabunFixed(15, .semibold))
                .padding(.horizontal, 16).frame(height: 44)
                .background(Theme.onPrimary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.onPrimary.opacity(0.6)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// `ก่อนเชื่อมต่อ | หลังเชื่อมต่อ` on the blue header.
struct IECPhaseSwitch: View {
    @Binding var phase: IECReport.Phase

    var body: some View {
        HStack(spacing: 4) {
            ForEach(IECReport.Phase.allCases, id: \.self) { p in
                let on = p == phase
                Button { phase = p } label: {
                    Text(p == .before ? "ก่อนเชื่อมต่อ" : "หลังเชื่อมต่อ").font(.sarabunFixed(15, .bold))
                        .foregroundStyle(on ? Theme.navy : Theme.onPrimary)
                        .padding(.horizontal, 16).frame(height: 40)
                        .background { if on { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.onPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

/// A thin progress ring.
struct IECRing: View {
    let fraction: Double
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 4)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(fraction >= 1 ? Theme.success : Theme.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A labelled bar: green when complete, orange while short.
struct IECBar: View {
    let title: String
    let tally: IECReport.Tally
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.sarabunFixed(15)).foregroundStyle(Theme.navy).frame(width: 130, alignment: .leading)
            Capsule().fill(tally.isComplete ? Theme.success : Theme.pending).frame(height: 6)
                .frame(maxWidth: .infinity)
            Text(value ?? "\(tally.done)/\(tally.total)").font(.sarabunFixed(13, .bold))
                .foregroundStyle(tally.isComplete ? Theme.successInk : Theme.warningInk).monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
