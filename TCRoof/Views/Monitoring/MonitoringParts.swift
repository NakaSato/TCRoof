import SwiftUI
import TCRoofUI
import TCRoofCore

/// Numbers on the monitoring page: grouped, a set number of decimals, and `—` for what isn't known (never 0).
enum MonFormat {
    static let dash = "—"

    static func number(_ v: Double?, _ digits: Int = 0) -> String {
        guard let v, v.isFinite else { return dash }
        return v.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "en_US")))
    }

    /// `74%`, `-23%` with `signed`.
    static func percent(_ v: Double?, signed: Bool = false, digits: Int = 0) -> String {
        guard let v, v.isFinite else { return dash }
        let p = v * 100
        let s = number(p, digits)
        return signed && p > 0 ? "+" + s + "%" : s + "%"
    }

    /// Energy with its unit scaled: `1.31 GWh`, `830 MWh`, `2,572 kWh`.
    static func energy(_ kWh: Double?) -> (value: String, unit: String) {
        guard let e = kWh else { return (dash, "kWh") }
        if e >= 1_000_000 { return (number(e / 1_000_000, 2), "GWh") }
        if e >= 10_000 { return (number(e / 1000, 1), "MWh") }
        return (number(e), "kWh")
    }

    /// Baht scaled: `5.51 ล้านบาท`.
    static func baht(_ v: Double?) -> (value: String, unit: String) {
        guard let v else { return (dash, "บาท") }
        if v >= 1_000_000 { return (number(v / 1_000_000, 2), "ล้านบาท") }
        return (number(v), "บาท")
    }

    static func time(_ d: Date?) -> String {
        guard let d else { return dash }
        return d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "en_GB")))
    }
}

/// A station's health as the table's chip: `ปกติ`, `แจ้งเตือน`, `ออฟไลน์`.
extension Monitoring.Health {
    var title: String {
        switch self {
        case .normal: "ปกติ"
        case .alarm: "แจ้งเตือน"
        case .offline: "ออฟไลน์"
        }
    }
    var ink: Color {
        switch self {
        case .normal: Theme.successInk
        case .alarm: Theme.dangerText
        case .offline: Theme.inkMuted
        }
    }
    var fill: Color {
        switch self {
        case .normal: Theme.successSoft
        case .alarm: Theme.dangerSoft
        case .offline: Theme.track
        }
    }
    /// The row's left bar.
    var bar: Color {
        switch self {
        case .normal: Theme.success
        case .alarm: Theme.danger
        case .offline: Theme.inkMuted.opacity(0.5)
        }
    }
}

/// The colour of a figure's chip.
enum MonTone {
    case info, ok, warn, bad, muted

    var ink: Color {
        switch self {
        case .info: Theme.primary
        case .ok: Theme.successInk
        case .warn: Theme.warningInk
        case .bad: Theme.dangerText
        case .muted: Theme.inkMuted
        }
    }
    var fill: Color {
        switch self {
        case .info: Theme.primarySoft
        case .ok: Theme.successSoft
        case .warn: Theme.warningSoft
        case .bad: Theme.dangerSoft
        case .muted: Theme.track
        }
    }
}

struct MonChip: View {
    let text: String
    let tone: MonTone

    init(_ text: String, _ tone: MonTone) { self.text = text; self.tone = tone }

    var body: some View {
        Text(text).font(.sarabunFixed(13, .bold)).foregroundStyle(tone.ink)
            .padding(.horizontal, 8).frame(height: 22)
            .background(tone.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .lineLimit(1).fixedSize()
    }
}

/// The page's white card: radius 16, a hairline border.
struct MonCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }
}

/// A two-to-four way switch as the board draws them: a grey track, the picked one white.
struct MonSwitch<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var disabled = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                let on = value == selection
                Button { selection = value } label: {
                    Text(verbatim: title).font(.sarabunFixed(14, on ? .bold : .regular))
                        .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background { if on { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface).shadow(color: Theme.navy.opacity(0.18), radius: 1.5, y: 1) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }
}
