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

    /// Saves an edit at once. A sent or closed test refuses edits; `evenWhenLocked` is for closing, reopening and
    /// recording an export, which don't change the values.
    func updateIEC(_ context: ModelContext, evenWhenLocked: Bool = false, _ change: (inout IECReport) -> Void) {
        var r = iecReport ?? newIECReport
        guard !r.isLocked || evenWhenLocked else { return }
        change(&r)
        iecReport = r
        try? context.save()
    }

    /// Who confirms a step or closes the test: the name in settings, else the test's tester.
    var iecActor: String {
        let name = UserDefaults.standard.string(forKey: GoogleSession.userNameKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? (iecReport?.tester ?? "") : name
    }

    #if DEBUG
    /// `-iecDemo YES`: the แพรกหนามแดง sample of docs/forms/iec62446-pwa, when the job has no test yet (for good);
    /// `-iecDemo reset` replaces the job's test with it.
    /// `-iecDemo full` (with `context`): the sample with every reading, check, record and a drawn photo in every slot,
    /// so each step is done but none confirmed.
    func seedIECDemo(replacing: Bool = false, full context: ModelContext? = nil) {
        guard iecReport == nil || replacing, let url = Bundle.main.url(forResource: "iec-demo-praek-nam-daeng", withExtension: "json"),
              let data = try? Data(contentsOf: url), var r = try? IECReport(form: data) else { return }
        // labelled as the sample in the sheet (C3) and the file name, so it can't pass for this job's test
        r.sampleName = "แพรกหนามแดง"
        r.stationLine += " (ตัวอย่าง)"
        if let context {
            for p in iecPhotos where p.tag != Job.keyPlanTag { context.delete(p) }
            let photo = IECCamera.stubPhoto("OK")
            func store() -> String { let id = UUID().uuidString; let a = PhotoAsset(data: photo, tag: id); context.insert(a); a.iecJob = self; return id }
            r.testDate = .now; r.tester = "ทีมทดสอบ"
            r.instruments.multimeterClamp = "CLAMP-01"; r.instruments.insulationTester = "IR-01"; r.instruments.irradianceMeter = "SUN-01"
            r.module.areaM2 = 2.58; r.after = r.before; r.gridOnAt = .now
            r.yrKWhM2Day = r.yrKWhM2Day ?? 4.24; r.arrayTempC = r.arrayTempC ?? 59.4
            r.irradiancePhoto = store(); r.thermalPhotos = [store()]
            for i in r.inverters.indices {
                r.inverters[i].continuity = .normal; r.inverters[i].functionalBefore = .normal; r.inverters[i].functionalAfter = .normal
                for n in r.inverters[i].slots.indices where r.inverters[i].slots[n] != nil {
                    r.inverters[i].slots[n]?.irPosMOhm = 250; r.inverters[i].slots[n]?.irNegMOhm = 300
                    let voc = r.inverters[i].slots[n]?.vocV
                    r.inverters[i].slots[n]?.vmpV = voc.map { ($0 * 0.82).rounded() }
                    r.inverters[i].slots[n]?.impA = 9.5
                    for k in IECReport.PhotoKind.allCases { r.inverters[i].slots[n]?.photos[k.rawValue] = store() }
                }
            }
        }
        iecReport = r
        // step 1 needs its SLD to be done
        if let context { seedDemoSLD(context: context) }
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
