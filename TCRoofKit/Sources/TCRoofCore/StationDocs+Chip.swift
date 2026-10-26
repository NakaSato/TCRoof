import Foundation

/// How a submission's papers read on a status chip (docs/ui/install-tracking-ipad-overview §2–§4): one rule for
/// every package tile, and the colour of one paper.
public extension StationDocs {
    /// A chip's colour, kept apart from any UI.
    enum ChipLevel: Equatable, Sendable {
        /// Approved, or ready on the team's side.
        case done
        /// Handed in, waiting on someone outside the team.
        case waiting
        /// The team is working on it.
        case working
        /// Missing, due within 7 days.
        case dueSoon
        /// Missing, past its due date.
        case late
        /// Missing, nothing pressing yet.
        case open
        /// Not needed at this station.
        case none
    }

    /// One paper: approved or signed is done, submitted or requested waits on the outside, a draft is the team's.
    static func level(_ s: Status) -> ChipLevel {
        switch s {
        case .approved, .signed: .done
        case .submitted, .requested: .waiting
        case .draft: .working
        case .missing: .open
        case .notNeeded: .none
        }
    }

    struct PackageChip: Equatable, Sendable {
        public let text: String
        public let level: ChipLevel
        /// Every paper is in and some still wait for approval (`ยื่นครบแล้ว …`).
        public let awaitingApproval: Bool
    }

    /// `ครบ r/t` when every paper is ready (waiting while any submitted one is not approved yet), else `r/t ฉบับ`,
    /// late or due soon by `due`. Papers not needed count as neither.
    static func packageChip(_ statuses: [Status], due: Date?, today: Date, calendar: Calendar = .current) -> PackageChip {
        let counted = statuses.filter { $0 != .notNeeded }
        let ready = counted.filter(\.isReady).count, total = counted.count
        if total > 0, ready == total {
            let handedIn = counted.allSatisfy { $0 == .submitted || $0 == .approved }
            let waiting = handedIn && counted.contains(.submitted)
            return PackageChip(text: "ครบ \(ready)/\(total)", level: waiting ? .waiting : .done, awaitingApproval: waiting)
        }
        let left = due.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: $0)).day ?? 0 }
        let level: ChipLevel = switch left {
        case let l? where l < 0: .late
        case let l? where l <= 7: .dueSoon
        default: .open
        }
        return PackageChip(text: "\(ready)/\(total) ฉบับ", level: level, awaitingApproval: false)
    }
}
