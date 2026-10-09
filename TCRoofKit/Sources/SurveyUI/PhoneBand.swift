#if canImport(UIKit)
import SwiftUI
import TCRoofCore
import TCRoofUI

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
        done >= total ? ("✓ \(done)/\(total)", Home.badgeOkText, Home.badgeOkBg) : ("\(done)/\(total)", Home.pending, Home.badgeWarnBg)
    }
    /// A neutral note chip (no completion to count).
    static func noteChip(_ text: String) -> Chip { (text, Home.muted, Home.primarySoft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(number).font(.system(size: 24, weight: .heavy)).tracking(-0.5).monospacedDigit().foregroundStyle(Home.primary)
                Rectangle().fill(Home.hairline).frame(width: 1, height: 18)
                Text(title).font(.system(size: 16, weight: .bold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(chip.text).font(.system(size: 11, weight: .bold)).foregroundStyle(chip.fg).lineLimit(1).fixedSize()
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
        .background(Color.white)
        .overlay(alignment: .top) { Rectangle().fill(Home.hairline).frame(height: 1) }
        .overlay(alignment: .bottom) { if last { Rectangle().fill(Home.hairline).frame(height: 1) } }
    }
}
#endif
