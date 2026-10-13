#if canImport(UIKit)
import SwiftUI
import TCRoofCore

extension Job {
    /// The step line's chip on iPhone: `ครบ n/m ช่อง` (green) or `ขาด n ช่อง` (orange), from the page's own completion.
    func stepChip(_ page: MissingGroup.Target) -> (text: String, ok: Bool)? {
        guard let c = steps.first(where: { $0.page == page })?.completion, c.total > 0 else { return nil }
        return c.isComplete ? ("ครบ \(c.filled)/\(c.total) ช่อง", true) : ("ขาด \(c.total - c.filled) ช่อง", false)
    }
}

/// iPhone full-width white band (docs/ui/survey-a1-iphone): 1-pt borders, a big blue number, a divider, the title and a chip.
/// Shared by the phone bodies of the card pages (A1, A2).
struct PhoneBand<Content: View>: View {
    typealias Chip = (text: String, fg: Color, bg: Color)

    let number: String
    let title: String
    let chip: Chip
    var last = false
    @ViewBuilder var content: Content

    /// `✓ n/m` in green when `done == total`, `n/m` in orange otherwise.
    static func countChip(_ done: Int, _ total: Int) -> Chip {
        done >= total ? ("✓ \(done)/\(total)", Theme.okTick, Theme.okSoft) : ("\(done)/\(total)", Theme.pending, Theme.pendingSoft)
    }
    /// A neutral note chip (no completion to count).
    static func noteChip(_ text: String) -> Chip { (text, Theme.inkMuted, Theme.primarySoft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(number).font(.sarabunFixed(24, .heavy)).tracking(-0.5).monospacedDigit().foregroundStyle(Theme.primary)
                Rectangle().fill(Theme.borderSubtle).frame(width: 1, height: 18)
                Text(title).font(.sarabunFixed(16, .bold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(chip.text).font(.sarabunFixed(11, .bold)).foregroundStyle(chip.fg).lineLimit(1).fixedSize()
                    .padding(.horizontal, 8).padding(.vertical, 1)
                    .background(chip.bg, in: Capsule())
            }
            // the board's 24-pt number sits in a row that makes the bands the board's height
            .frame(height: 26)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            content
        }
        .padding(.top, 12).padding(.horizontal, 16).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .overlay(alignment: .bottom) { if last { Rectangle().fill(Theme.borderSubtle).frame(height: 1) } }
    }
}
#endif
