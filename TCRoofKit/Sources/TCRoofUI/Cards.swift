#if canImport(UIKit)
import SwiftUI
import UIKit

/// Section 5 · Cards & lists (docs/ui/components/sections/05-cards.png). Cards take plain values, never app models.

/// White card: radius 16, `border-subtle` hairline, `shadow-card`.
struct TCCardBackground: ViewModifier {
    var border: Color = Theme.borderSubtle
    var fill: Color = Theme.surface
    var lineWidth: CGFloat = 1
    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(border, lineWidth: lineWidth))
            .cardShadow()
    }
}

public extension View {
    /// The board's card: white, radius 16, hairline border, `shadow-card`.
    func tcCard() -> some View { modifier(TCCardBackground()) }
}

/// Two rotated rounded squares with a white symbol (home menu card illustration).
public struct TCModuleIllustration: View {
    let symbol: String
    var size: CGFloat

    public init(symbol: String, size: CGFloat = 104) { self.symbol = symbol; self.size = size }

    public var body: some View {
        let k = size / 104
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16 * k, style: .continuous).fill(Theme.primarySoft)
                .frame(width: 90 * k, height: 92 * k).rotationEffect(.degrees(-10))
                .offset(x: 0, y: 6 * k)
            RoundedRectangle(cornerRadius: 16 * k, style: .continuous).fill(Theme.primary)
                .frame(width: 92 * k, height: 92 * k)
                .overlay(Image(systemName: symbol).font(.system(size: 36 * k, weight: .semibold)).foregroundStyle(Theme.onPrimary))
                .rotationEffect(.degrees(6))
                .offset(x: 12 * k, y: 4 * k)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// Home menu card: two-line title, subtitle, illustration on the right. The whole card is the button.
public struct TCMenuCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(title: String, subtitle: String, symbol: String = "briefcase.fill", action: @escaping () -> Void) {
        self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.action = action
    }

    public var body: some View {
        let compact = sizeClass == .compact
        Button(action: action) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.sarabun(compact ? 22 : 26, .bold, relativeTo: .title)).foregroundStyle(Theme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.sarabun(compact ? 14 : 16)).foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TCModuleIllustration(symbol: symbol, size: compact ? 76 : 104)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, compact ? 20 : 28).padding(.vertical, 16)
            .frame(minHeight: compact ? 130 : 170)
            .tcCard()
            .contentShape(RoundedRectangle(cornerRadius: Radius.xl))
        }
        .buttonStyle(TCPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Sync mark at the foot of a job card.
public enum TCSyncState: Sendable {
    case pending, synced

    var title: String { self == .pending ? "รอซิงก์" : "ซิงก์แล้ว" }
    var color: Color { self == .pending ? Theme.warning : Theme.okText }
}

/// PWA job card: number, gap chip, name, place · kWp, ring %, 13-step bar, resume strip, section counts, date and sync.
public struct TCPWAJobCard: View {
    public struct Resume: Sendable {
        public let index: Int
        public let count: Int
        public let step: String
        public init(index: Int, count: Int, step: String) { self.index = index; self.count = count; self.step = step }
    }

    let number: String
    let missing: Int
    let name: String
    let place: String
    let progress: Double
    let steps: [TCSegmentedProgress.Segment]
    let resume: Resume?
    let sections: [String]
    let date: String
    let sync: TCSyncState
    let onOpen: () -> Void
    let onResume: () -> Void

    /// `sections`: one chip per extra section group, e.g. `B ระบบไฟฟ้า ×5`. `date`: already formatted.
    public init(number: String, missing: Int, name: String, place: String, progress: Double,
                steps: [TCSegmentedProgress.Segment], resume: Resume?, sections: [String] = [],
                date: String, sync: TCSyncState, onOpen: @escaping () -> Void, onResume: @escaping () -> Void) {
        self.number = number; self.missing = missing; self.name = name; self.place = place; self.progress = progress
        self.steps = steps; self.resume = resume; self.sections = sections; self.date = date; self.sync = sync
        self.onOpen = onOpen; self.onResume = onResume
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) { head }.buttonStyle(.plain)
            TCSegmentedProgress(steps)
            if let resume { TCResumeStrip(index: resume.index, count: resume.count, step: resume.step, action: onResume) }
            if !sections.isEmpty {
                HStack(spacing: 6) {
                    ForEach(sections, id: \.self) { TCStatusChip($0, fill: Theme.primarySoft, text: Theme.navy) }
                }
            }
            footer
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
        .tcCard()
    }

    var head: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(number).font(.sarabun(13, .bold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    if missing > 0 { TCStatusChip("ขาด \(missing) ช่อง", kind: .pending) } else { TCStatusChip("ครบ", kind: .done) }
                }
                Text(name).font(.sarabun(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy).lineLimit(2)
                Text(place).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TCProgressRing(.percent(progress), size: 58)
        }
        .contentShape(Rectangle())
    }

    var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar").font(.system(size: 14))
            Text(date)
            Spacer(minLength: 8)
            Text("● " + sync.title).font(.sarabun(TypeScale.caption, .bold, relativeTo: .caption)).foregroundStyle(sync.color)
        }
        .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
        .padding(.top, 9)
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }
}

/// Survey job card: customer and team, project code and interest tag, kW; appointment time large;
/// draft progress (`ทำต่อ 3/5 ระบบไฟฟ้า`, %, 5-step bar); the teal call to action.
public struct TCSurveyJobCard: View {
    let customer: String
    let team: String?
    let code: String
    let tag: String?
    let capacity: String?
    let when: String
    let date: String
    let progress: (index: Int, count: Int, step: String, percent: Double)?
    let cta: String
    let onOpen: () -> Void
    let onAction: () -> Void

    /// `when` is the bold relative time (`วันนี้ 09:30 น.`), `date` the plain date after it.
    /// `progress` nil hides the box (survey not started).
    public init(customer: String, team: String?, code: String, tag: String? = nil, capacity: String? = nil,
                when: String, date: String, progress: (index: Int, count: Int, step: String, percent: Double)?,
                cta: String = "ทำแบบสำรวจต่อ (ร่าง)", onOpen: @escaping () -> Void, onAction: @escaping () -> Void) {
        self.customer = customer; self.team = team; self.code = code; self.tag = tag; self.capacity = capacity
        self.when = when; self.date = date; self.progress = progress; self.cta = cta
        self.onOpen = onOpen; self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpen) { details }.buttonStyle(.plain)
            if let progress { progressBox(progress) }
            Button(action: onAction) {
                Label(cta, systemImage: "list.clipboard").labelStyle(TCIconTitleLabel())
            }
            .buttonStyle(TCButtonStyle(.tealGradient, fullWidth: true))
            .padding(.top, 6)
        }
        .padding(16)
        .tcCard()
    }

    var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s) {
                Text(customer).font(.sarabun(18, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let team { TCTeamChip(team) }
            }
            HStack(spacing: 6) {
                Text(code).font(.sarabun(TypeScale.caption, .bold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                if let tag { TCStatusChip(tag, fill: Theme.primaryLight.opacity(0.12), text: Theme.primaryLight) }
            }
            if let capacity {
                Label(capacity, systemImage: "bolt.fill").labelStyle(TCIconTitleLabel())
                    .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    .imageScale(.small)
            }
            Rectangle().fill(Theme.borderSubtle).frame(height: 1).padding(.vertical, 4)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "calendar")
                Text(when).font(.sarabun(15, .bold, relativeTo: .subheadline))
                Text(date).font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    func progressBox(_ p: (index: Int, count: Int, step: String, percent: Double)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s) {
                Text("ทำต่อ \(p.index)/\(p.count)").foregroundStyle(Theme.inkMuted)
                Text(p.step).bold().foregroundStyle(Theme.navy)
                Spacer(minLength: 4)
                Text("\(Int((p.percent * 100).rounded()))%").bold().foregroundStyle(Theme.primary)
            }
            .font(.sarabun(TypeScale.caption, relativeTo: .caption))
            TCSegmentedProgress(done: p.index - 1, count: p.count)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.keyFill, in: RoundedRectangle(cornerRadius: Radius.md))
        .padding(.top, 6)
    }
}

/// Horizontal list row (a tool): icon tile, title + code, subtitle; status chip and queue line on the right.
/// `overdue` tints the row red.
public struct TCListRow: View {
    let symbol: String
    let title: String
    let code: String?
    let subtitle: String
    let status: (title: String, kind: TCStatusChip.Kind)?
    let trailing: String?
    let overdue: Bool
    let action: () -> Void

    public init(symbol: String, title: String, code: String? = nil, subtitle: String,
                status: (title: String, kind: TCStatusChip.Kind)? = nil, trailing: String? = nil,
                overdue: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol; self.title = title; self.code = code; self.subtitle = subtitle
        self.status = status; self.trailing = trailing; self.overdue = overdue; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.okTick)
                    .frame(width: 44, height: 44)
                    .background(Theme.okSoft, in: RoundedRectangle(cornerRadius: Radius.lg))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title).font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                        if let code { Text(code).font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.muted) }
                    }
                    .lineLimit(1)
                    Text(subtitle).font(.sarabun(TypeScale.caption, overdue ? .semibold : .regular, relativeTo: .caption))
                        .foregroundStyle(overdue ? Theme.dangerText : Theme.inkMuted).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    if let status { TCStatusChip(status.title, kind: status.kind) }
                    if let trailing { Text(trailing).font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.primary).lineLimit(1) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 64)
            .modifier(TCCardBackground(border: overdue ? Theme.danger.opacity(0.4) : Theme.borderSubtle,
                                       fill: overdue ? Theme.dangerSoft.opacity(0.45) : Theme.surface))
            .contentShape(RoundedRectangle(cornerRadius: Radius.xl))
        }
        .buttonStyle(TCPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Number tile used as a filter: big number, title, caption. Selected: 2 pt primary border.
public struct TCNumberTile: View {
    let value: Int
    let title: String
    let caption: String?
    let tint: Color
    let selected: Bool
    let action: () -> Void

    /// `tint` colours the number (`Theme.dangerText` for overdue).
    public init(value: Int, title: String, caption: String? = nil, tint: Color = Theme.navy, selected: Bool,
                action: @escaping () -> Void) {
        self.value = value; self.title = title; self.caption = caption; self.tint = tint; self.selected = selected; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)").font(.sarabun(26, .bold, relativeTo: .title)).foregroundStyle(tint).monospacedDigit()
                Text(title).font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                if let caption { Text(caption).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted) }
            }
            .lineLimit(1)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(TCCardBackground(border: selected ? Theme.primary : Theme.borderSubtle, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.xl))
        }
        .buttonStyle(TCPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Side filter list: a small title, then rows of dot · name · count; the selected row is primarySoft with a primary rim.
public struct TCSideFilterList<ID: Hashable>: View {
    public struct Row: Identifiable {
        public let id: ID
        public let title: String
        public let count: Int
        public let color: Color
        /// Count in red (`เกินกำหนดคืน`).
        public let alert: Bool
        public init(id: ID, title: String, count: Int, color: Color, alert: Bool = false) {
            self.id = id; self.title = title; self.count = count; self.color = color; self.alert = alert
        }
    }

    let title: String
    let rows: [Row]
    @Binding var selection: ID

    public init(title: String, rows: [Row], selection: Binding<ID>) {
        self.title = title; self.rows = rows; self._selection = selection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 12).padding(.vertical, 4)
            ForEach(rows) { row in
                let on = row.id == selection
                Button { selection = row.id } label: {
                    HStack(spacing: 10) {
                        Circle().fill(row.color).frame(width: 9, height: 9)
                        Text(row.title).font(.sarabun(15, on ? .bold : .regular)).foregroundStyle(Theme.navy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(row.count)").font(.sarabun(TypeScale.caption, .bold, relativeTo: .caption))
                            .foregroundStyle(row.alert ? Theme.dangerText : Theme.inkMuted).monospacedDigit()
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .background(on ? Theme.primarySoft : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay { if on { RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.primary) } }
                    .contentShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.title) \(row.count)")
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Theme.borderSubtle))
    }
}
#endif
