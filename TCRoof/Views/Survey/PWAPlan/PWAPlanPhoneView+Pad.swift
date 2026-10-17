import SwiftUI
import TCRoofUI
import TCRoofCore

/// The plan page on iPad (docs/ui/pwa-plan-ipad): under the PWA home's header and nav, the framed `ตารางงาน` card
/// 440 pt wide on the left, and on the right `แผน MP` with the S-curve at full width over `รายสถานี | กำหนดส่ง`. The
/// right column scrolls behind the dock; the card ends above it.
extension PWAPlanPhoneView {
    func padPage(_ board: PWAPlanBoard) -> some View {
        let due = PWAPlan.groups(board.deadlines, today: Self.today)
        return GeometryReader { g in
            HStack(alignment: .top, spacing: 20) {
                // 116 pt above the screen's edge: 18 over the dock's 98, which is the bottom safe-area inset
                padSchedule(board).frame(width: 440).padding(.bottom, 18)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        mineChip(labelled: true)
                        padPlan(board)
                        // side by side in landscape; the portrait column is too narrow for two
                        if g.size.width >= 1200 {
                            HStack(alignment: .top, spacing: 14) {
                                padGantt(board)
                                padDueCard(due)
                            }
                        } else {
                            padGantt(board)
                            padDueCard(due)
                        }
                    }
                    // 130 pt under the last card, with the dock's 98
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(Debug.scrollEnd ? .bottom : .top)
                .scrollDismissesKeyboard(.immediately)
            }
            .padding(.horizontal, 63).padding(.top, 16)
        }
        // the board has no fade behind the dock on this page
        .onAppear { dock?.noFade = true }
        .onDisappear { dock?.noFade = false }
    }

    /// A card's title with its note: `ตารางงาน ทุกงานของโครงการ`.
    func padCardHeader(_ title: String, _ note: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            Text(note).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
        }
        .lineLimit(1)
        .padding(.bottom, 2)
    }
}

extension View {
    /// A row of the plan page: a white card on iPhone, and on iPad a soft row inside its framed card.
    func padRow(_ pad: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: pad ? 12 : 16, style: .continuous)
        return background(pad ? Theme.stripFill : Theme.surface, in: shape)
            .overlay(shape.strokeBorder(pad ? Theme.track : Theme.borderSubtle))
    }
}
