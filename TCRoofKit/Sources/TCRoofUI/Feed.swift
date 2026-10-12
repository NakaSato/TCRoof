#if canImport(UIKit)
import SwiftUI
import UIKit

/// Project feed of the iPhone home (docs/ui/tcroof-home-iphone-v3). The parts take plain values, never app models.

/// The four badge colours of a post: `รายงานวันนี้` blue, `อัตโนมัติ` green, `รอผู้ตรวจ` orange, `ปัญหา` red.
public enum TCFeedTone: CaseIterable, Sendable {
    case blue, green, orange, red

    /// Badge fill and text.
    var badge: (fill: Color, text: Color) {
        switch self {
        case .blue: (Theme.primarySoft, Theme.primary)
        case .green: (Theme.successSoft, Theme.successText)
        case .orange: (Theme.warningSoft, Theme.warningText)
        case .red: (Theme.dangerSoft, Theme.dangerText)
        }
    }

    /// Stat tile fill and text; a blue tile is quieter than the blue badge.
    var tile: (fill: Color, text: Color) {
        self == .blue ? (Theme.progressBox, Theme.navy) : badge
    }

    /// Fill of a chip over a photo.
    var solid: Color {
        switch self {
        case .green: Theme.success
        case .red: Theme.danger
        case .orange: Theme.warning
        case .blue: Theme.heroSolid.opacity(0.72)
        }
    }
}

/// Filter chip of the feed: a 40 pt capsule with a count, in a 44 pt hit area.
public struct TCFeedChip: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    public init(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.count = count; self.selected = selected; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(.sarabun(13, selected ? .bold : .semibold, relativeTo: .footnote))
                Text("\(count)").font(.sarabun(11, selected ? .bold : .semibold, relativeTo: .caption2))
                    .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                    .background(selected ? Theme.onPrimary.opacity(0.22) : Theme.hairline, in: Capsule())
            }
            .foregroundStyle(selected ? Theme.onPrimary : Theme.navy)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 12).frame(height: 40)
            .background(selected ? Theme.navySolid : Theme.surface, in: Capsule())
            .overlay { if !selected { Capsule().strokeBorder(Theme.borderSubtle) } }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The box under an issue post: who fixes it and by when, `ยังค้าง` on red until `แก้แล้ว`, then green with `เปิดอีกครั้ง`.
public struct TCIssueBox: View {
    let owner: String
    let due: String?
    let fixed: Bool
    let action: () -> Void

    public init(owner: String, due: String?, fixed: Bool, action: @escaping () -> Void) {
        self.owner = owner; self.due = due; self.fixed = fixed; self.action = action
    }

    public var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if !owner.isEmpty { line("ผู้รับผิดชอบ", owner) }
                statusLine
            }
            .font(.sarabun(12, relativeTo: .caption))
            .frame(maxWidth: .infinity, alignment: .leading)
            button
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(fixed ? Theme.successSoft : Theme.dangerSoft, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func line(_ label: String, _ value: String) -> some View {
        (Text(label + " ").foregroundStyle(Theme.inkMuted) + Text(value).bold().foregroundStyle(Theme.navy)).lineLimit(1)
    }

    private var statusLine: some View {
        let status = Text(fixed ? "แก้แล้ว ✓" : "ยังค้าง").bold().foregroundStyle(fixed ? Theme.successText : Theme.dangerText)
        guard let due else { return status.lineLimit(1) }
        return (Text("กำหนด ").foregroundStyle(Theme.inkMuted) + Text(due).bold().foregroundStyle(Theme.navy)
                + Text(" · ").foregroundStyle(Theme.inkMuted) + status).lineLimit(1)
    }

    private var button: some View {
        Button(action: action) {
            Text(fixed ? "เปิดอีกครั้ง" : "แก้แล้ว").font(.sarabun(13, .bold, relativeTo: .footnote))
                .foregroundStyle(fixed ? Theme.inkMuted : Theme.onPrimary)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(fixed ? Theme.surface : Theme.success, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay { if fixed { RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Theme.borderOutdoor) } }
        }
        .buttonStyle(.plain)
    }
}

/// One feed post: avatar, who, badge, `where · when`, text, then the record's photos or stat tiles, an issue box,
/// the acknowledgement line and the action row (`รับทราบ` · the link to the source record). No comments.
public struct TCFeedPost<Photo: View>: View {
    public struct Stat: Identifiable {
        public let id = UUID()
        let value: String, label: String, tone: TCFeedTone
        public init(_ value: String, _ label: String, _ tone: TCFeedTone) { self.value = value; self.label = label; self.tone = tone }
    }

    /// A chip over the photo, bottom-left.
    public struct PhotoChip: Identifiable {
        public let id = UUID()
        let text: String, tone: TCFeedTone
        public init(_ text: String, _ tone: TCFeedTone) { self.text = text; self.tone = tone }
    }

    public struct Issue {
        let owner: String, due: String?, fixed: Bool, toggle: () -> Void
        public init(owner: String, due: String?, fixed: Bool, toggle: @escaping () -> Void) {
            self.owner = owner; self.due = due; self.fixed = fixed; self.toggle = toggle
        }
    }

    /// A row of the `⋯` menu.
    public struct MenuItem: Identifiable {
        public let id = UUID()
        let title: String, symbol: String, action: () -> Void
        public init(_ title: String, symbol: String, action: @escaping () -> Void) { self.title = title; self.symbol = symbol; self.action = action }
    }

    let initials: String
    let avatar: Color
    let who: String
    let badge: String
    let tone: TCFeedTone
    let detail: String
    let text: String
    var stats: [Stat]
    var photoCount: Int
    var photoChips: [PhotoChip]
    var issue: Issue?
    let ackLine: String
    let acknowledged: Bool
    let link: String
    var menu: [MenuItem]
    let onAck: () -> Void
    let onOpen: () -> Void
    @ViewBuilder var photo: (Int) -> Photo

    @State private var page: Int? = 0

    /// `detail` is the `where · when` line. `photo` draws photo `n` of `photoCount`; it is cropped to 330 × 170.
    public init(initials: String, avatar: Color, who: String, badge: String, tone: TCFeedTone, detail: String, text: String,
                stats: [Stat] = [], photoCount: Int = 0, photoChips: [PhotoChip] = [], issue: Issue? = nil,
                ackLine: String, acknowledged: Bool, link: String, menu: [MenuItem] = [],
                onAck: @escaping () -> Void, onOpen: @escaping () -> Void, @ViewBuilder photo: @escaping (Int) -> Photo) {
        self.initials = initials; self.avatar = avatar; self.who = who; self.badge = badge; self.tone = tone
        self.detail = detail; self.text = text; self.stats = stats; self.photoCount = photoCount; self.photoChips = photoChips
        self.issue = issue; self.ackLine = ackLine; self.acknowledged = acknowledged; self.link = link; self.menu = menu
        self.onAck = onAck; self.onOpen = onOpen; self.photo = photo
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(text).font(.sarabun(13.5, relativeTo: .footnote)).foregroundStyle(Theme.navy).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.bottom, 8)
            if photoCount > 0 { photos.padding(.horizontal, 12) }
            if !stats.isEmpty { tiles.padding(.horizontal, 12) }
            if let issue {
                TCIssueBox(owner: issue.owner, due: issue.due, fixed: issue.fixed, action: issue.toggle)
                    .padding(.horizontal, 12).padding(.top, 8)
            }
            Text(ackLine).font(.sarabun(11.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.borderSubtle))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(initials).font(.sarabun(initials.count > 1 ? 13 : 16, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.onPrimary)
                .frame(width: 40, height: 40).background(avatar, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(who).font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text(badge).font(.sarabun(10.5, .bold, relativeTo: .caption2)).foregroundStyle(tone.badge.text)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 7).background(tone.badge.fill, in: Capsule())
                }
                Text(detail).font(.sarabun(11.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            menuButton
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.top, 10).padding(.bottom, 6)
    }

    private var menuButton: some View {
        Menu {
            ForEach(menu) { item in Button(action: item.action) { Label(item.title, systemImage: item.symbol) } }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("ตัวเลือกโพสต์")
    }

    /// The record's photos, swiped sideways, with the counter top-right and the chips bottom-left.
    private var photos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(0..<photoCount, id: \.self) { i in
                    photo(i).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                        .containerRelativeFrame(.horizontal)
                        .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollDisabled(photoCount < 2)
        .aspectRatio(330.0 / 170.0, contentMode: .fit)
        .background(Theme.primarySoft)
        .overlay(alignment: .topTrailing) {
            Text("\((page ?? 0) + 1)/\(photoCount)").font(.sarabun(11, .bold, relativeTo: .caption2)).foregroundStyle(Theme.onMedia)
                .padding(.horizontal, 8).padding(.vertical, 1)
                .background(Theme.heroSolid.opacity(0.6), in: Capsule())
                .padding(8)
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                ForEach(photoChips) { chip in
                    Text(chip.text).font(.sarabun(11, .bold, relativeTo: .caption2)).foregroundStyle(Theme.onMedia).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(chip.tone.solid, in: Capsule())
                }
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var tiles: some View {
        HStack(spacing: 6) {
            ForEach(stats.prefix(3)) { s in
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.value).font(.sarabun(16, .bold, relativeTo: .callout)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(s.label).font(.sarabun(10.5, relativeTo: .caption2)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(s.tone.tile.text)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(s.tone.tile.fill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 0) {
            Button(action: onAck) {
                HStack(spacing: 6) {
                    Image(systemName: acknowledged ? "hand.thumbsup.fill" : "hand.thumbsup").font(.system(size: 16, weight: .semibold))
                    Text("รับทราบ").font(.sarabun(13, acknowledged ? .heavy : .semibold, relativeTo: .footnote))
                }
                .foregroundStyle(acknowledged ? Theme.primary : Theme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityAddTraits(acknowledged ? .isSelected : [])
            Button(action: onOpen) {
                Text(link + " ›").font(.sarabun(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .padding(.top, 6)
    }
}

public extension TCFeedPost where Photo == EmptyView {
    /// A post with no photo.
    init(initials: String, avatar: Color, who: String, badge: String, tone: TCFeedTone, detail: String, text: String,
         stats: [Stat] = [], issue: Issue? = nil, ackLine: String, acknowledged: Bool, link: String, menu: [MenuItem] = [],
         onAck: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.init(initials: initials, avatar: avatar, who: who, badge: badge, tone: tone, detail: detail, text: text,
                  stats: stats, photoCount: 0, issue: issue, ackLine: ackLine, acknowledged: acknowledged, link: link, menu: menu,
                  onAck: onAck, onOpen: onOpen) { _ in EmptyView() }
    }
}

#if DEBUG
/// The board's example photos, drawn: a roof with panels and an inverter room. For the gallery and `-homeFeed demo`;
/// the app shows the record's real photos.
public struct TCFeedExamplePhoto: View {
    public enum Scene: Sendable { case roof, inverters }
    let scene: Scene
    public init(_ scene: Scene) { self.scene = scene }

    public var body: some View {
        Canvas { ctx, size in
            let k = size.width / 330
            ctx.scaleBy(x: k, y: k)
            switch scene {
            case .roof: roof(&ctx)
            case .inverters: inverters(&ctx)
            }
        }
        .aspectRatio(330.0 / 170.0, contentMode: .fill)
        .accessibilityLabel(scene == .roof ? "ภาพตัวอย่าง: แผงบนหลังคา" : "ภาพตัวอย่าง: ห้องอินเวอร์เตอร์")
    }

    private func roof(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: 330, height: 170)), with: .color(Theme.primarySoft))
        var slope = Path()
        slope.move(to: CGPoint(x: 0, y: 120)); slope.addLine(to: CGPoint(x: 330, y: 70))
        slope.addLine(to: CGPoint(x: 330, y: 170)); slope.addLine(to: CGPoint(x: 0, y: 170)); slope.closeSubpath()
        ctx.fill(slope, with: .color(Theme.borderOutdoor))
        let xs: [CGFloat] = [20, 58, 96, 134, 172, 210, 248]
        for top in [CGFloat(128), 150] {
            for (i, x) in xs.enumerated() {
                let y = top - CGFloat(i) * 5.8
                var p = Path()
                p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + 34, y: y - 5.2))
                p.addLine(to: CGPoint(x: x + 34, y: y + 10.8)); p.addLine(to: CGPoint(x: x, y: y + 16)); p.closeSubpath()
                ctx.fill(p, with: .color(Theme.navySolid))
                ctx.stroke(p, with: .color(Theme.chip), lineWidth: 1)
            }
        }
        var ridge = Path()
        ridge.move(to: CGPoint(x: 0, y: 120)); ridge.addLine(to: CGPoint(x: 330, y: 70))
        ctx.stroke(ridge, with: .color(Theme.muted), lineWidth: 3)
    }

    private func inverters(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: 330, height: 170)), with: .color(Theme.hairline))
        ctx.fill(Path(CGRect(x: 0, y: 132, width: 330, height: 38)), with: .color(Theme.borderOutdoor))
        var cable = Path()
        for x in [CGFloat(40), 130, 220] {
            let box = Path(roundedRect: CGRect(x: x, y: 38, width: 62, height: 86), cornerRadius: 5)
            ctx.fill(box, with: .color(Theme.surface))
            ctx.stroke(box, with: .color(Theme.chevron), lineWidth: 2)
            ctx.fill(Path(roundedRect: CGRect(x: x + 14, y: 52, width: 34, height: 16), cornerRadius: 2), with: .color(Theme.navySolid))
            ctx.fill(Path(ellipseIn: CGRect(x: x + 26, y: 91, width: 10, height: 10)), with: .color(Theme.success))
            cable.move(to: CGPoint(x: x + 31, y: 124)); cable.addLine(to: CGPoint(x: x + 31, y: 150))
        }
        cable.move(to: CGPoint(x: 50, y: 150)); cable.addLine(to: CGPoint(x: 272, y: 150))
        ctx.stroke(cable, with: .color(Theme.warning), lineWidth: 4)
    }
}
#endif
#endif
