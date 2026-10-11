#if canImport(UIKit)
import SwiftUI
import UIKit

/// Survey step header (`g-head` + `g-prog` + `g-caps`): the gradient title block, then `5/13`, the step name and 13 capsules.
/// iPad: title 20 / sub 15, capsules 8 high (mint done · gradient current · grey todo), step name on the right.
/// iPhone: title 19 / sub 13, capsules 6 high (green done · blue current), the step name after the number and
/// `status` (usually a `ขาด n ช่อง` chip) at the end of the step line.
public struct TCSurveyHeader<Status: View>: View {
    let title: String
    let subtitle: String
    /// 1-based.
    let step: Int
    let count: Int
    let stepName: String
    @ViewBuilder var status: Status
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(title: String, subtitle: String, step: Int, count: Int, stepName: String, @ViewBuilder status: () -> Status) {
        self.title = title; self.subtitle = subtitle; self.step = step; self.count = count
        self.stepName = stepName; self.status = status()
    }

    var compact: Bool { sizeClass == .compact }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabun(compact ? 19 : 20, .bold, relativeTo: .title3))
                Text(subtitle).font(.sarabun(compact ? 13 : 15, relativeTo: .subheadline)).opacity(0.92)
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, compact ? 16 : 24).padding(.top, compact ? 10 : 18).padding(.bottom, compact ? 14 : 18)
            .background(Theme.headerGradient, in: UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: compact ? 7 : 10) {
                HStack(spacing: 8) {
                    Text("\(step)/\(count)").font(.sarabun(compact ? 14 : 15, .bold)).foregroundStyle(Theme.navy)
                    if compact {
                        Text(stepName).font(.sarabun(14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        Spacer(minLength: 4)
                        status
                    } else {
                        Spacer(minLength: 8)
                        Text(stepName).font(.sarabun(15)).foregroundStyle(Theme.navy).lineLimit(1)
                    }
                }
                TCStepCapsules(step: step, count: count)
            }
            .padding(.horizontal, compact ? 16 : 24).padding(.vertical, compact ? 10 : 14)
        }
        .background(Theme.background)
    }
}

public extension TCSurveyHeader where Status == EmptyView {
    init(title: String, subtitle: String, step: Int, count: Int, stepName: String) {
        self.init(title: title, subtitle: subtitle, step: step, count: count, stepName: stepName) { EmptyView() }
    }
}

/// The 13 capsules under a survey header. Done steps are those before `step`.
public struct TCStepCapsules: View {
    let step: Int
    let count: Int
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(step: Int, count: Int) { self.step = step; self.count = count }

    public var body: some View {
        let compact = sizeClass == .compact
        HStack(spacing: compact ? 2 : 6) {
            ForEach(1...max(count, 1), id: \.self) { i in
                Capsule().fill(fill(i, compact: compact)).frame(height: compact ? 6 : 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("ขั้น \(step) จาก \(count)")
    }

    func fill(_ i: Int, compact: Bool) -> AnyShapeStyle {
        if i < step { return AnyShapeStyle(compact ? Theme.stepDone : Theme.mint) }
        if i == step { return compact ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.headerGradient) }
        return AnyShapeStyle(compact ? Theme.borderSubtle : Theme.capsuleTodo)
    }
}

/// PWA module header: back tile, title 28–30 over a subtitle, and a search field in the header; bottom corners 15.
/// On iPhone the search field moves under the title.
public struct TCPWAHeader: View {
    let title: String
    let subtitle: String
    @Binding var search: String
    var prompt: String
    var onBack: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(title: String, subtitle: String, search: Binding<String>, prompt: String = "ค้นหาเลขที่ ชื่อโครงการ…", onBack: (() -> Void)? = nil) {
        self.title = title; self.subtitle = subtitle; self._search = search; self.prompt = prompt; self.onBack = onBack
    }

    public var body: some View {
        let compact = sizeClass == .compact
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
        layout {
            HStack(spacing: 16) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                            .frame(width: touchMin, height: touchMin)
                            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.lg))
                            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(.white.opacity(0.35)))
                    }
                    .buttonStyle(TCPressStyle())
                    .accessibilityLabel("กลับ")
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.sarabun(compact ? 24 : TypeScale.header, .bold, relativeTo: .largeTitle)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(subtitle).font(.sarabun(15)).opacity(0.92).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            searchField.frame(maxWidth: compact ? .infinity : 400)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 16 : 28).padding(.top, 20).padding(.bottom, compact ? 16 : 24)
        .background(Theme.headerGradient, in: UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15))
    }

    var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.navy)
            TextField("", text: $search, prompt: Text(prompt).foregroundStyle(Theme.inkMuted))
                .font(.sarabun(17)).foregroundStyle(Theme.navy)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.muted)
                        .frame(width: touchMin, height: touchMin)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ล้างคำค้นหา")
            }
        }
        .padding(.leading, 16).padding(.trailing, search.isEmpty ? 16 : 0)
        .frame(minHeight: 52)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
    }
}

/// White nav bar (`pc-nav`): back, page title over the breadcrumb, and `trailing` (usually a secondary button).
/// Pages using it hide the system navigation bar.
public struct TCNavBar<Trailing: View>: View {
    let title: String
    /// Pages before this one, e.g. `["หน้าหลัก", "สำรวจหน้างาน"]`.
    let trail: [String]
    let current: String
    var backLabel: String
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(title: String, trail: [String], current: String, backLabel: String = "กลับหน้าหลัก",
                onBack: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.trail = trail; self.current = current; self.backLabel = backLabel
        self.onBack = onBack; self.trailing = trailing()
    }

    public var body: some View {
        let compact = sizeClass == .compact
        // a tab's root screen (iPhone floating tab bar) has nothing to go back to
        let back = onBack != nil || isPresented
        HStack(spacing: 12) {
            if back {
                TCIconButton("chevron.left", accessibilityLabel: backLabel, bordered: !compact) { (onBack ?? { dismiss() })() }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabun(compact ? 20 : TypeScale.pageTitle, .bold, relativeTo: .title2)).foregroundStyle(Theme.navy)
                    .lineLimit(1).accessibilityAddTraits(.isHeader)
                if !compact {
                    (Text(trail.map { "\($0) › " }.joined()) + Text(current).bold().foregroundColor(Theme.navy))
                        .font(.sarabun(14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.leading, back ? (compact ? 8 : 24) : (compact ? 16 : 28)).padding(.trailing, compact ? 8 : 24)
        .padding(.vertical, compact ? 4 : 12)
        .frame(minHeight: compact ? 52 : 72)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }
}

public extension TCNavBar where Trailing == EmptyView {
    init(title: String, trail: [String], current: String, backLabel: String = "กลับหน้าหลัก", onBack: (() -> Void)? = nil) {
        self.init(title: title, trail: trail, current: current, backLabel: backLabel, onBack: onBack) { EmptyView() }
    }
}

/// iPad: the system navigation bar gives way to a `TCNavBar`. iPhone: nothing changes, so the screen's own
/// `navigationTitle` and `toolbar` still drive its bar (they don't show while the iPad bar is hidden).
private struct TCPadNavBar<Trailing: View>: ViewModifier {
    let title: String
    let trail: [String]
    let current: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .compact {
            content
        } else {
            content
                .safeAreaInset(edge: .top, spacing: 0) { TCNavBar(title: title, trail: trail, current: current) { trailing } }
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

public extension View {
    /// The white nav bar on iPad (`pc-nav`); iPhone keeps the system bar. `current` defaults to `title`.
    func tcPadNavBar<Trailing: View>(_ title: String, trail: [String], current: String? = nil,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(TCPadNavBar(title: title, trail: trail, current: current ?? title, trailing: trailing))
    }

    func tcPadNavBar(_ title: String, trail: [String], current: String? = nil) -> some View {
        tcPadNavBar(title, trail: trail, current: current) { EmptyView() }
    }
}

/// A search field for the right of a `TCNavBar` (screens whose iPhone bar uses `.searchable`, which the iPad bar hides).
public struct TCBarSearchField: View {
    @Binding var text: String
    let prompt: String

    public init(text: Binding<String>, prompt: String) { self._text = text; self.prompt = prompt }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.muted))
                .font(.sarabun(16)).foregroundStyle(Theme.navy)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(Theme.muted)
                        .frame(width: touchMin, height: touchMin)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ล้างคำค้นหา")
            }
        }
        .padding(.leading, 14).padding(.trailing, text.isEmpty ? 14 : 0)
        .frame(width: 360, height: 48)
        .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.headerLine))
    }
}

/// Columns whose widths follow `fractions` (2 : 1 for form + info card, 1 : 2 : 1.4 for filter · list · detail).
public struct TCFractionColumns: Layout {
    public var fractions: [CGFloat]
    public var spacing: CGFloat

    public init(_ fractions: [CGFloat], spacing: CGFloat = Space.l) { self.fractions = fractions; self.spacing = spacing }

    func widths(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        let f = (0..<n).map { $0 < fractions.count ? fractions[$0] : 1 }
        let free = max(0, total - spacing * CGFloat(max(n - 1, 0)))
        let sum = f.reduce(0, +)
        return f.map { free * $0 / max(sum, 0.001) }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // measured without a width (or an infinite one): lay out at the board's column width
        let total = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 800
        let w = widths(total, subviews.count)
        let h = zip(subviews, w).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: total, height: h)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (s, w) in zip(subviews, widths(bounds.width, subviews.count)) {
            // the height they were measured with: inside a ScrollView that is nil, and proposing the
            // tallest column's height instead kept the view graph invalidating (blank screen, full CPU)
            s.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: proposal.height))
            x += w + spacing
        }
    }
}

/// Page scaffold: iPad columns by `fractions`, top aligned; iPhone one column, margin 16, gap 12, scrolling.
/// Presets: `.twoColumn` (form / picture · info cards), `.threePane` (filter · list · detail).
public struct TCPageColumns<Content: View>: View {
    public static var twoColumn: [CGFloat] { [2, 1] }
    public static var threePane: [CGFloat] { [1, 2, 1.4] }

    let fractions: [CGFloat]
    @ViewBuilder var content: Content
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(_ fractions: [CGFloat], @ViewBuilder content: () -> Content) {
        self.fractions = fractions; self.content = content()
    }

    public var body: some View {
        if sizeClass == .compact {
            ScrollView { VStack(spacing: Space.m) { content }.padding(Space.l) }
        } else {
            TCFractionColumns(fractions) { content }.padding(Space.xl)
        }
    }
}

/// Card grid: 3 columns on iPad, 1 on iPhone (gap 16 / 12).
public struct TCCardGrid<Content: View>: View {
    var columns: Int
    @ViewBuilder var content: Content
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(columns: Int = 3, @ViewBuilder content: () -> Content) { self.columns = columns; self.content = content() }

    public var body: some View {
        let compact = sizeClass == .compact
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: compact ? Space.m : Space.l, alignment: .top), count: compact ? 1 : columns),
                  spacing: compact ? Space.m : Space.l) { content }
    }
}

/// iPhone screen header (docs/ui/tcroof-survey-list-iphone): `headerGradient` under the status bar, bottom radius 15,
/// a 19 pt title over a 13 pt subtitle, and trailing 44 pt buttons (`TCHeaderIcon`). The back chevron shows only when
/// the screen is pushed; a tab root has `หน้าหลัก` in the tab bar instead. A sheet passes `onClose` for a leading ✕
/// (`ยกเลิก`) in place of the chevron.
public struct TCGradientHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    var backLabel: String
    var onClose: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    public init(title: String, subtitle: String, backLabel: String = "กลับหน้าหลัก", onClose: (() -> Void)? = nil,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.backLabel = backLabel; self.onClose = onClose; self.trailing = trailing()
    }

    private var hasLeading: Bool { onClose != nil || isPresented }

    public var body: some View {
        HStack(spacing: 2) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 22, weight: .semibold))
                        .frame(width: touchMin, height: touchMin).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ยกเลิก")
            } else if isPresented {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 21, weight: .semibold))
                        .frame(width: touchMin, height: touchMin).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(backLabel)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabun(19, .bold, relativeTo: .title3)).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.sarabun(13, relativeTo: .caption)).opacity(0.92).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) { trailing }
        }
        .foregroundStyle(.white)
        .padding(.leading, hasLeading ? 6 : 16).padding(.trailing, 8)
        .padding(.top, 6).padding(.bottom, 14)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15, style: .continuous)
                .fill(Theme.headerGradient)
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// A `TCGradientHeader` button's label: a white glyph in a 44 pt square, radius 12, white 16 %.
public struct TCHeaderIcon: View {
    let symbol: String
    public init(_ symbol: String) { self.symbol = symbol }

    public var body: some View {
        Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            .frame(width: touchMin, height: touchMin)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// One tab of `TCTabBar`. With `action` the tab runs it instead of becoming selected
/// (the iPhone's `ตั้งค่า` opens the settings sheet).
public struct TCTabItem<ID: Hashable>: Identifiable {
    public let id: ID
    public var title: String
    /// SF Symbol name, or with `asset` the name of a template image in the main bundle (a board glyph with no matching symbol).
    public var symbol: String
    public var asset = false
    /// Red count badge; hidden at 0.
    public var badge: Int
    /// VoiceOver label when it should say more than the title (`สำรวจ · นัดวันนี้ 2`).
    public var accessibilityLabel: String?
    public var action: (() -> Void)?

    public init(_ id: ID, title: String, symbol: String, badge: Int = 0, accessibilityLabel: String? = nil, action: (() -> Void)? = nil) {
        self.id = id; self.title = title; self.symbol = symbol; self.badge = badge
        self.accessibilityLabel = accessibilityLabel; self.action = action
    }

    public init(_ id: ID, title: String, asset: String, badge: Int = 0, accessibilityLabel: String? = nil, action: (() -> Void)? = nil) {
        self.init(id, title: title, symbol: asset, badge: badge, accessibilityLabel: accessibilityLabel, action: action)
        self.asset = true
    }
}

/// iPhone docked bottom tab bar (docs/ui/tcroof-home-iphone-v2): white, a 1 pt top line, padding 4 / 6,
/// equal tabs at least 48 high with a 22 pt glyph in a 52 × 28 slot over a 10.5 pt label.
/// The selected tab's glyph sits on a soft blue capsule. Attach it with `.safeAreaInset(edge: .bottom)`
/// on the tab root screens only; the white runs on under the home indicator.
public struct TCTabBar<ID: Hashable>: View {
    let items: [TCTabItem<ID>]
    @Binding var selection: ID

    public init(items: [TCTabItem<ID>], selection: Binding<ID>) {
        self.items = items; self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in tab(item) }
        }
        .padding(.top, 4).padding(.horizontal, 6)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderOutdoor).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("เมนูหลัก")
    }

    func tab(_ item: TCTabItem<ID>) -> some View {
        let selected = item.action == nil && item.id == selection
        return Button {
            if let action = item.action { action() } else { selection = item.id }
        } label: {
            VStack(spacing: 2) {
                glyph(item, selected: selected)
                    .frame(width: 52, height: 28)
                    .background { if selected { Capsule().fill(Theme.primarySoft) } }
                    .overlay(alignment: .topTrailing) {
                        if item.badge > 0 { badge(item.badge).padding(.trailing, 4).offset(y: -4) }
                    }
                Text(item.title).font(.sarabun(10.5, selected ? .heavy : .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(height: 13)
            }
            .foregroundStyle(selected ? Theme.primary : Theme.inkTab)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel ?? item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder func glyph(_ item: TCTabItem<ID>, selected: Bool) -> some View {
        if item.asset {
            Image(item.symbol).renderingMode(.template).resizable().frame(width: 22, height: 22)
        } else {
            Image(systemName: item.symbol).font(.system(size: 18, weight: selected ? .medium : .regular))
        }
    }

    func badge(_ n: Int) -> some View {
        Text("\(n)").font(.system(size: 10, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
            .background(Theme.danger, in: Capsule())
            .background(Capsule().fill(Theme.surface).padding(-2))
            .fixedSize()
            .accessibilityHidden(true)
    }
}
#endif
