#if canImport(UIKit)
import SwiftUI
import UIKit

/// Section 7 | Overlays (docs/ui/components/sections/07-overlays.png).

/// `shadow` of floating cards: y 12, blur 32, navy 25 %.
private extension View {
    func overlayShadow() -> some View { shadow(color: Theme.navy.opacity(0.25), radius: 16, y: 12) }
}

/// Centre dialog: title, subtitle, a content slot, then `ยกเลิก` and the confirm button.
/// `confirmDisabledReason` greys the confirm button and says why.
public struct TCDialog<Content: View>: View {
    let title: String
    var subtitle: String?
    let confirmTitle: String
    var confirmDisabledReason: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let content: Content

    public init(title: String, subtitle: String? = nil, confirmTitle: String, confirmDisabledReason: String? = nil,
                onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.confirmTitle = confirmTitle
        self.confirmDisabledReason = confirmDisabledReason; self.onCancel = onCancel; self.onConfirm = onConfirm
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title).font(.sarabun(19, .bold)).foregroundStyle(Theme.navy)
            if let subtitle { Text(subtitle).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted) }
            content
            HStack(spacing: Space.m) {
                TCButton("ยกเลิก", kind: .secondary, size: .card, fullWidth: true, action: onCancel)
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
                    .disabled(confirmDisabledReason != nil)
            }
            .padding(.top, Space.xs)
            if let confirmDisabledReason {
                Text(confirmDisabledReason).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: 420)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Theme.borderSubtle))
        .overlayShadow()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Alert: a red-tinted circle with a warning sign, title, body and 2–3 stacked actions
/// (primary gradient, secondary outline, text `ยกเลิก`).
public struct TCAlertCard: View {
    public struct Action {
        public let title: String
        public let kind: TCButtonKind
        public let action: () -> Void
        public init(_ title: String, kind: TCButtonKind, action: @escaping () -> Void) {
            self.title = title; self.kind = kind; self.action = action
        }
    }

    let title: String
    let message: String
    var systemImage: String
    let actions: [Action]

    public init(title: String, message: String, systemImage: String = "exclamationmark.triangle", actions: [Action]) {
        self.title = title; self.message = message; self.systemImage = systemImage; self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.dangerText)
                .frame(width: 52, height: 52).background(Theme.dangerSoft, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(.sarabun(18, .bold)).foregroundStyle(Theme.navy)
            Text(message).font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
            VStack(spacing: 10) {
                ForEach(actions.indices, id: \.self) { i in
                    let a = actions[i]
                    TCButton(a.title, kind: a.kind, size: .card, fullWidth: true, action: a.action)
                }
            }
            .padding(.top, Space.xs)
        }
        .multilineTextAlignment(.center)
        .padding(22)
        .frame(maxWidth: 360)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.borderSubtle))
        .overlayShadow()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Right-hand detail panel (iPad): title, ✕, content, and a primary action at the bottom.
public struct TCDetailPanel<Content: View>: View {
    let title: String
    var actionTitle: String?
    var actionSymbol: String?
    let onClose: () -> Void
    var onAction: () -> Void
    let content: Content

    public init(title: String, actionTitle: String? = nil, actionSymbol: String? = nil, onClose: @escaping () -> Void,
                onAction: @escaping () -> Void = {}, @ViewBuilder content: () -> Content) {
        self.title = title; self.actionTitle = actionTitle; self.actionSymbol = actionSymbol
        self.onClose = onClose; self.onAction = onAction; self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Space.s) {
                Text(title).font(.sarabun(19, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: Space.s)
                TCIconButton("xmark", accessibilityLabel: "ปิด", action: onClose)
            }
            ScrollView { VStack(alignment: .leading, spacing: 10) { content }.frame(maxWidth: .infinity, alignment: .leading) }
            if let actionTitle {
                TCButton(actionTitle, systemImage: actionSymbol, size: .card, fullWidth: true, action: onAction)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: Theme.navy.opacity(0.3), radius: 16, y: 12)
        .accessibilityElement(children: .contain)
    }
}

/// Sample of an iOS notification banner with its quick actions, on a wallpaper.
/// Visual sample only: the real banner is drawn by iOS, and its quick actions come from `UNNotificationCategory` actions.
public struct TCNotificationBannerSample: View {
    public struct QuickAction: Sendable {
        public let title: String
        public let systemImage: String
        public init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    }

    let title: String
    let message: String
    var time: String
    let actions: [QuickAction]

    public init(title: String, message: String, time: String = "ตอนนี้", actions: [QuickAction]) {
        self.title = title; self.message = message; self.time = time; self.actions = actions
    }

    static let ink = Color.black.opacity(0.9)
    static let bubble = Color.white.opacity(0.9)

    public var body: some View {
        VStack(spacing: Space.s) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "house.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "sun.max.fill").font(.system(size: 10)).foregroundStyle(Theme.sun).padding(3)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Self.ink)
                        Spacer(minLength: Space.s)
                        Text(time).font(.system(size: 13)).foregroundStyle(Color.black.opacity(0.45))
                    }
                    Text(message).font(.system(size: 15)).foregroundStyle(Self.ink)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Self.bubble, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            VStack(spacing: 0) {
                ForEach(actions.indices, id: \.self) { i in
                    HStack {
                        Text(actions[i].title).font(.system(size: 15))
                        Spacer()
                        Image(systemName: actions[i].systemImage).font(.system(size: 16))
                    }
                    .foregroundStyle(Self.ink)
                    .padding(.horizontal, 16).frame(minHeight: touchMin)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.black.opacity(0.12)).frame(height: 0.5) } }
                }
            }
            .background(Self.bubble, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(18)
        .background(Theme.wallpaperGradient, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// In-app notification panel: header `การแจ้งเตือน` with the unread count and `อ่านทั้งหมด`,
/// rows with an icon tile, title, detail, and an unread dot on a tinted row.
public struct TCNotificationPanel: View {
    public struct Item: Identifiable, Sendable {
        public let id: String
        public let systemImage: String
        public let title: String
        public let detail: String
        public let unread: Bool
        public init(id: String, systemImage: String, title: String, detail: String, unread: Bool) {
            self.id = id; self.systemImage = systemImage; self.title = title; self.detail = detail; self.unread = unread
        }
    }

    let items: [Item]
    let onReadAll: () -> Void
    let onOpen: (Item) -> Void

    public init(items: [Item], onReadAll: @escaping () -> Void, onOpen: @escaping (Item) -> Void) {
        self.items = items; self.onReadAll = onReadAll; self.onOpen = onOpen
    }

    public var body: some View {
        let unread = items.filter(\.unread).count
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                Text("การแจ้งเตือน").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                if unread > 0 {
                    Text("\(unread)").font(.sarabun(12.5, .bold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 10).frame(height: 24).background(Theme.primarySoft, in: Capsule())
                        .accessibilityLabel("ยังไม่อ่าน \(unread)")
                }
                Spacer(minLength: Space.s)
                Button("อ่านทั้งหมด", action: onReadAll)
                    .font(.sarabun(13, .bold)).foregroundStyle(Theme.primary)
                    .frame(minHeight: touchMin).buttonStyle(.plain)
                    .disabled(unread == 0)
            }
            .padding(.horizontal, 14).frame(minHeight: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderControl).frame(height: 1) }
            ForEach(items) { item in
                Button { onOpen(item) } label: { row(item) }.buttonStyle(.plain)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Theme.borderControl))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    func row(_ item: Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary)
                .frame(width: 38, height: 38).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: Radius.sm))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                Text(item.detail).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.unread { Circle().fill(Theme.primary).frame(width: 10, height: 10).accessibilityLabel("ยังไม่อ่าน") }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(minHeight: touchMin)
        .background(item.unread ? Theme.unreadRow : Theme.surface)
        .contentShape(Rectangle())
    }
}

// MARK: - Presenting

/// Dims the page and centres `card` over it; tapping the dim calls `onDismiss` when given.
struct TCModalOverlay<Card: View>: ViewModifier {
    let isPresented: Bool
    var dim: Double = 0.35
    var onDismiss: (() -> Void)?
    var alignment: Alignment = .center
    @ViewBuilder var card: () -> Card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack(alignment: alignment) {
                        Theme.navy.opacity(dim).ignoresSafeArea()
                            .onTapGesture { onDismiss?() }
                            .accessibilityHidden(true)
                        card()
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isPresented)
    }
}

public extension View {
    /// A `TCDialog` centred over a dimmed page. Tapping outside cancels.
    func tcDialog<Content: View>(isPresented: Binding<Bool>, title: String, subtitle: String? = nil, confirmTitle: String,
                                 confirmDisabledReason: String? = nil, onConfirm: @escaping () -> Void,
                                 @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(TCModalOverlay(isPresented: isPresented.wrappedValue, onDismiss: { isPresented.wrappedValue = false }) {
            TCDialog(title: title, subtitle: subtitle, confirmTitle: confirmTitle, confirmDisabledReason: confirmDisabledReason,
                     onCancel: { isPresented.wrappedValue = false },
                     onConfirm: { onConfirm(); isPresented.wrappedValue = false }, content: content)
                .padding(Space.l)
        })
    }

    /// A `TCAlertCard` centred over a dimmed page. Each action closes it after running.
    func tcAlert(isPresented: Binding<Bool>, title: String, message: String, systemImage: String = "exclamationmark.triangle",
                 actions: [TCAlertCard.Action]) -> some View {
        modifier(TCModalOverlay(isPresented: isPresented.wrappedValue) {
            TCAlertCard(title: title, message: message, systemImage: systemImage,
                        actions: actions.map { a in TCAlertCard.Action(a.title, kind: a.kind) { a.action(); isPresented.wrappedValue = false } })
                .padding(Space.l)
        })
    }

    /// A `TCDetailPanel` on the right of a dimmed page (iPad), 10 pt from the edges. Tapping the dim closes it.
    func tcDetailPanel<Content: View>(isPresented: Binding<Bool>, title: String, width: CGFloat = 380,
                                      actionTitle: String? = nil, actionSymbol: String? = nil, onAction: @escaping () -> Void = {},
                                      @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(TCModalOverlay(isPresented: isPresented.wrappedValue, onDismiss: { isPresented.wrappedValue = false }, alignment: .trailing) {
            TCDetailPanel(title: title, actionTitle: actionTitle, actionSymbol: actionSymbol,
                          onClose: { isPresented.wrappedValue = false }, onAction: onAction, content: content)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .padding(10)
                .transition(.move(edge: .trailing))
        })
    }
}
#endif
