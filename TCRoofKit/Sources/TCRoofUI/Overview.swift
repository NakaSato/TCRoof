#if canImport(UIKit)
import SwiftUI

/// Parts of the PWA project home's overviews on iPhone (docs/ui/pwa-solar-survey-iphone-v2). No shadows.

/// The view switch of the PWA module's iPhone pages (docs/ui/pwa-plan-iphone §2): one 44 pt track holding 38 pt
/// segments, the selected one white with a soft shadow. A count stands after its label as plain bold text, red
/// when `alert` (`กำหนดส่ง` with something late). Segments share the width, or with `equalWidths` off take their own
/// (`สัปดาห์ | เดือน`). The white segment slides to the selection, unless Reduce Motion is on.
public struct TCCountSegments: View {
    public struct Segment: Sendable {
        let title: String
        let count: String?
        let alert: Bool
        /// What VoiceOver reads after the title and the count (`สถานี` in `บำรุงรักษา 6 สถานี`).
        let unit: String?

        public init(_ title: String, count: String? = nil, alert: Bool = false, unit: String? = nil) {
            self.title = title; self.count = count; self.alert = alert; self.unit = unit
        }

        public init(_ title: String, count: Int, alert: Bool = false, unit: String? = nil) {
            self.init(title, count: "\(count)", alert: alert, unit: unit)
        }
    }

    let segments: [Segment]
    @Binding var selection: Int
    let equalWidths: Bool
    let fontSize: CGFloat
    let countSize: CGFloat
    @Namespace private var slide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ segments: [Segment], selection: Binding<Int>, equalWidths: Bool = true, fontSize: CGFloat = 13,
                countSize: CGFloat = 12) {
        self.segments = segments; self._selection = selection; self.equalWidths = equalWidths; self.fontSize = fontSize
        self.countSize = countSize
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { i, s in segment(s, on: i == selection) { selection = i } }
        }
        .padding(3)
        .background(Theme.track, in: Capsule())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selection)
    }

    private func segment(_ s: Segment, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(s.title).font(.sarabunFixed(fontSize, on ? .bold : .semibold))
                if let count = s.count {
                    Text(count).font(.sarabunFixed(countSize, .bold)).monospacedDigit()
                        .foregroundStyle(s.alert ? Theme.dangerText : on ? Theme.primary : Theme.inkMuted)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
            .padding(.horizontal, equalWidths ? 6 : 12)
            .frame(maxWidth: equalWidths ? .infinity : nil, minHeight: 38)
            .background {
                if on {
                    Capsule().fill(Theme.surface).shadow(color: Theme.navySolid.opacity(0.16), radius: 1.5, y: 1)
                        .matchedGeometryEffect(id: "selected", in: slide)
                }
            }
            // the track's padding is part of the hit area
            .padding(.vertical, 3).contentShape(Rectangle()).padding(.vertical, -3)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([s.title, s.count, s.unit].compactMap { $0 }.joined(separator: " "))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// A row filter of the overviews with its count after the title: a capsule 40 pt high in a 44 pt hit area.
public struct TCCountPill: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    public init(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.count = count; self.selected = selected; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text("\(title) \(count)").font(.sarabunFixed(13, .bold)).monospacedDigit()
                .lineLimit(1).fixedSize()
                .foregroundStyle(selected ? Theme.onPrimary : Theme.navySolid)
                .padding(.horizontal, 12).frame(height: 40)
                .background(selected ? Theme.navySolid : Theme.surface, in: Capsule())
                .overlay { if !selected { Capsule().strokeBorder(Theme.borderSubtle) } }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(count)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The blue header of a PWA module page on iPhone: title 18 over a subtitle 12, and a 44 pt search button that
/// grows into the field while the title slides away. A page without a search shows only its title; a pushed page
/// gets a back button. Use it as the page's top safe-area inset. `large` is the PWA project home's header
/// (docs/ui/pwa-solar-survey-iphone-v3 §2): title 22 on one line and round buttons, with a bell after the search.
/// `wide` is that header on iPad (docs/ui/pwa-solar-survey-ipad-v3 §3): title 30, 63 pt margins, 88 pt high, and the
/// search grows to 420 pt beside the title, which stays.
public struct TCPhoneSearchHeader: View {
    /// The header's bell: its unread count and what a tap opens.
    public struct Bell {
        let unread: Int
        let action: () -> Void

        public init(unread: Int, action: @escaping () -> Void) { self.unread = unread; self.action = action }
    }

    let title: String
    let subtitle: String?
    let showsSearch: Bool
    let onBack: (() -> Void)?
    let large: Bool
    let wide: Bool
    let bell: Bell?
    let settings: (() -> Void)?
    @Binding var search: String
    @Binding var isOpen: Bool
    var prompt: String
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: String, subtitle: String?, search: Binding<String>, isOpen: Binding<Bool>, prompt: String = "ค้นหาเลขที่ ชื่อโครงการ",
                showsSearch: Bool = true, large: Bool = false, wide: Bool = false, bell: Bell? = nil, settings: (() -> Void)? = nil, onBack: (() -> Void)? = nil) {
        self.title = title; self.subtitle = subtitle; self._search = search; self._isOpen = isOpen; self.prompt = prompt
        self.showsSearch = showsSearch; self.large = large; self.wide = wide; self.bell = bell; self.settings = settings; self.onBack = onBack
    }

    private var corner: CGFloat { large ? 22 : 12 }

    public var body: some View {
        HStack(spacing: 10) {
            if let onBack, !isOpen || wide {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                        .background(Theme.onPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                }
                .accessibilityLabel("ย้อนกลับ")
            }
            if !isOpen || !showsSearch || wide { titles.transition(titleTransition) }
            Spacer(minLength: 0)
            if showsSearch { searchBox }
            if let bell { bellButton(bell) }
            if let settings, !isOpen || wide { settingsButton(settings).transition(titleTransition) }
        }
        .frame(height: 44)
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, wide ? 63 : 16).padding(.top, wide ? 22 : 2).padding(.bottom, wide ? 22 : 10)
        .background {
            Theme.headerGradient
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: wide ? 20 : 15, bottomTrailingRadius: wide ? 20 : 15, style: .continuous))
                .ignoresSafeArea(edges: .top)
        }
        // the keyboard put away over an empty field closes the search; with text it stays open
        .onChange(of: focused) { _, on in
            if !on && isOpen && search.isEmpty { close() }
        }
    }

    private func curve(_ duration: Double, delay: Double) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .timingCurve(0.2, 0.8, 0.2, 1, duration: duration).delay(delay)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.sarabunFixed(wide ? 30 : large ? 22 : 18, .bold)).frame(height: wide ? 36 : large ? 28 : 23)
            if let subtitle { Text(subtitle).font(.sarabunFixed(12)).opacity(0.9).frame(height: 16) }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var titleTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let move = AnyTransition.opacity.combined(with: .offset(x: -16))
        return .asymmetric(insertion: move.animation(curve(0.34, delay: 0.14)), removal: move.animation(curve(0.30, delay: 0.10)))
    }

    /// With Reduce Motion the button and the field are two views that cross-fade; otherwise one shape changes width.
    @ViewBuilder private var searchBox: some View {
        if reduceMotion {
            if isOpen { shape(open: true).transition(.opacity) } else { shape(open: false).transition(.opacity) }
        } else {
            shape(open: isOpen)
        }
    }

    private func bellButton(_ bell: Bell) -> some View {
        Button(action: bell.action) {
            Image(systemName: "bell").font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Theme.onPrimary.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(Theme.onPrimary.opacity(0.4)))
                .overlay(alignment: .topTrailing) {
                    if bell.unread > 0 {
                        Text("\(bell.unread)").font(.system(size: 10, weight: .heavy)).monospacedDigit()
                            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                            .background(Theme.danger, in: Capsule())
                            .background(Capsule().fill(Theme.headerBadgeRing).padding(-2))
                            .padding(5)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bell.unread > 0 ? "การแจ้งเตือน · ยังไม่อ่าน \(bell.unread)" : "การแจ้งเตือน")
    }

    private func settingsButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "gearshape").font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Theme.onPrimary.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(Theme.onPrimary.opacity(0.4)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ตั้งค่าโครงการ")
        .accessibilityIdentifier("pwaHome.settings")
    }

    private func shape(open: Bool) -> some View {
        let box = RoundedRectangle(cornerRadius: corner, style: .continuous)
        // the field and ✕ come in once the box has grown
        let late = AnyTransition.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.24).delay(reduceMotion ? 0 : 0.42)),
                                            removal: .opacity.animation(.easeOut(duration: 0.1)))
        return HStack(spacing: 0) {
            Button(action: self.open) {
                Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(open ? Theme.inkMuted : Theme.onPrimary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(open)
            .accessibilityLabel(prompt)
            .accessibilityHidden(open)
            if open {
                TextField(prompt + "…", text: $search)
                    .font(.sarabunFixed(15)).foregroundStyle(Theme.navy)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .focused($focused)
                    .accessibilityLabel(prompt)
                    .transition(late)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.inkMuted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ปิดการค้นหา")
                .transition(late)
            }
        }
        .frame(maxWidth: open ? (wide ? 420 : .infinity) : 44, alignment: .leading)
        .frame(height: 44)
        .background(open ? Theme.surface.opacity(0.97) : Theme.onPrimary.opacity(0.18), in: box)
        .overlay(box.strokeBorder(Theme.onPrimary.opacity(open ? 0 : 0.4)))
        .clipShape(box)
    }

    private func open() {
        withAnimation(curve(0.36, delay: 0.10)) { isOpen = true }
        // the field exists once the box has grown
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 480))
            if isOpen { focused = true }
        }
    }

    private func close() {
        focused = false
        search = ""
        withAnimation(curve(0.30, delay: 0.06)) { isOpen = false }
    }
}

/// The face of a round 44 pt filter button: white with a border, light blue with a blue border while its popover
/// is open, navy with an orange dot once a filter is set.
public struct TCFilterCircle: View {
    let open: Bool
    let filtered: Bool

    public init(open: Bool, filtered: Bool) { self.open = open; self.filtered = filtered }

    public var body: some View {
        let fill = open ? Theme.primarySoft : filtered ? Theme.navySolid : Theme.surface
        Image(systemName: "line.3.horizontal.decrease").font(.system(size: 17, weight: .bold))
            .foregroundStyle(filtered && !open ? Theme.onPrimary : Theme.navySolid)
            .frame(width: 44, height: 44)
            .background(fill, in: Circle())
            .overlay {
                if open { Circle().strokeBorder(Theme.primary) } else if !filtered { Circle().strokeBorder(Theme.borderSubtle) }
            }
            .overlay(alignment: .topTrailing) {
                if filtered {
                    Circle().fill(Theme.warning).frame(width: 8, height: 8)
                        .background(Circle().fill(fill).padding(-2))
                        .padding(.top, 6).padding(.trailing, 7)
                }
            }
            .contentShape(Circle())
    }
}

/// A 64 pt progress ring with its percent in the middle, and a navy tick where the plan stands.
public struct TCPlanRing: View {
    let actual: Double
    let plan: Double?
    let tint: Color
    let small: Bool

    /// - Parameters:
    ///   - actual: 0…1, the arc and the centre text.
    ///   - plan: 0…1, the tick; nil for no tick.
    ///   - small: the 44 pt ring of an iPad station row, else 64 pt.
    public init(actual: Double, plan: Double? = nil, tint: Color = Theme.primary, small: Bool = false) {
        self.actual = min(max(actual, 0), 1); self.plan = plan.map { min(max($0, 0), 1) }; self.tint = tint; self.small = small
    }

    public var body: some View {
        let line: CGFloat = small ? 5 : 7, size: CGFloat = small ? 44 : 64
        ZStack {
            Circle().stroke(Theme.borderSubtle, lineWidth: line)
            Circle().trim(from: 0, to: actual).stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round)).rotationEffect(.degrees(-90))
            if let plan {
                Capsule().fill(Theme.navySolid).frame(width: small ? 2 : 2.5, height: small ? 8 : 11).offset(y: -(size - line) / 2 - 0.5)
                    .rotationEffect(.degrees(plan * 360))
            }
            Text("\(Int((actual * 100).rounded()))%").font(.sarabunFixed(small ? 12 : 15, .bold)).monospacedDigit().foregroundStyle(Theme.navy)
        }
        .padding(line / 2)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// An 8 pt progress bar with a 2 × 14 navy tick where the plan stands.
public struct TCPlanBar: View {
    let actual: Double
    let plan: Double?
    let tint: Color

    public init(actual: Double, plan: Double? = nil, tint: Color = Theme.primary) {
        self.actual = min(max(actual, 0), 1); self.plan = plan.map { min(max($0, 0), 1) }; self.tint = tint
    }

    public var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: 8)
                Capsule().fill(tint).frame(width: max(g.size.width * actual, actual > 0 ? 8 : 0), height: 8)
                if let plan {
                    Rectangle().fill(Theme.navySolid).frame(width: 2, height: 14).offset(x: g.size.width * plan - 1)
                }
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

/// A count over its label on a tint; nil tone is grey (`ออฟไลน์`). `large` is the iPad summary's 60 pt tile.
public struct TCStatTile: View {
    let value: String
    let label: String
    let tone: TCFeedTone?
    let large: Bool

    public init(_ value: String, _ label: String, tone: TCFeedTone?, large: Bool = false) {
        self.value = value; self.label = label; self.tone = tone; self.large = large
    }

    public var body: some View {
        let c = tone?.tile ?? (Theme.hairline, Theme.inkMuted)
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.sarabunFixed(large ? 22 : 18, .bold)).monospacedDigit()
            Text(label).font(.sarabunFixed(large ? 12 : 11)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(c.1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, large ? 10 : 8).padding(.vertical, large ? 8 : 6)
        .frame(minHeight: large ? 60 : nil)
        .background(c.0, in: RoundedRectangle(cornerRadius: large ? 12 : 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// A small status capsule on a tint (`ช้ากว่า 12%`, `รายงานวันนี้ ✓`); nil tone is grey.
public struct TCToneChip: View {
    let text: String
    let tone: TCFeedTone?

    public init(_ text: String, tone: TCFeedTone?) { self.text = text; self.tone = tone }

    public var body: some View {
        let c = tone?.tile ?? (Theme.hairline, Theme.inkMuted)
        Text(text).font(.sarabunFixed(11, .bold)).lineLimit(1).fixedSize()
            .foregroundStyle(c.1)
            .padding(.horizontal, 8).frame(height: 18)
            .background(c.0, in: Capsule())
    }
}

/// A grouped card of a settings page: a 12 pt title over `TCSettingsRow`s, with hairlines between them.
public struct TCSettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            // each row draws a hairline on its top edge; the first one's is pushed out under the clip
            VStack(spacing: 0) { content }
                .padding(.top, -1)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        }
    }
}

/// One row of `TCSettingsGroup`: a title over a detail line, then a chevron, a pill or a switch.
public struct TCSettingsRow<Trailing: View>: View {
    let title: String
    let detail: String
    let trailing: Trailing

    public init(_ title: String, detail: String = "", @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.detail = detail; self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarabunFixed(15)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.85)
                if !detail.isEmpty {
                    Text(detail).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .padding(.top, 1)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

public extension TCSettingsRow where Trailing == TCSettingsChevron {
    /// A row that opens something: a chevron at the end.
    init(_ title: String, detail: String = "") { self.init(title, detail: detail) { TCSettingsChevron() } }
}

public struct TCSettingsChevron: View {
    public init() {}
    public var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chevron)
            .accessibilityHidden(true)
    }
}
#endif
