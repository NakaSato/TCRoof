import SwiftUI
import TCRoofUI
import SwiftData

/// Root tabs of the iPhone (compact width) behind the floating tab dock (docs/ui/tcroof-home-iphone-v3).
enum PhoneTab: String {
    /// `settings` is only the dock's button for the settings sheet, never a selected tab.
    case home, homeWork = "homework", pwa, docs, settings

    static let stacks: [PhoneTab] = [.home, .homeWork, .pwa, .docs]
    /// Space the root screens keep above the dock: with the dock's 66 pt and its 22 pt below, content ends 104 pt up.
    static let barGap: CGFloat = 16

    var module: AppModule? {
        switch self {
        case .home, .settings: nil
        case .homeWork: .survey
        case .pwa: .pwa
        case .docs: nil
        }
    }

    /// The page colour its content fades into behind the dock.
    var fade: Color { self == .homeWork ? Theme.background : Theme.phonePage }

    /// The fade's height: the board's 128 pt, or lower under the survey list so it stays clear of that list's own dock.
    var fadeHeight: CGFloat { self == .homeWork ? 108 : 128 }
}

/// The iPhone dock's state, for the screens under it: a pushed page that keeps the dock (the install tracking page,
/// docs/ui/install-tracking-iphone) puts `PhoneDockBar` under itself, as `PadDock` does on iPad.
@Observable final class PhoneDock {
    var tab: PhoneTab
    private(set) var opened: Set<PhoneTab>
    var showSettings = false
    /// Tabs whose root screen is showing (nothing pushed over it): only there a sideways swipe changes tab.
    var atRoot: Set<PhoneTab> = []

    init(_ tab: PhoneTab) {
        self.tab = tab
        opened = [tab]
    }

    func select(_ t: PhoneTab) {
        opened.insert(t)
        tab = t
    }

    /// A swipe to the left goes to the next tab of the dock, to the right to the one before.
    func swipe(dx: CGFloat, dy: CGFloat) {
        guard atRoot.contains(tab), abs(dx) > 70, abs(dx) > 2.5 * abs(dy),
              let i = PhoneTab.stacks.firstIndex(of: tab) else { return }
        let next = i + (dx < 0 ? 1 : -1)
        guard PhoneTab.stacks.indices.contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { select(PhoneTab.stacks[next]) }
    }
}

/// iPhone root: one `NavigationStack` per tab, the selected one shown. Each tab's root screen carries
/// `TCTabBar` as its bottom safe-area inset, so the page scrolls behind the dock and a pushed screen slides in
/// over it and covers it, like a system tab bar that hides on push. A tab's stack is built the first time it is opened and then kept,
/// so each tab keeps its place. Not a `TabView`: its system bar would come back on every pushed screen that
/// doesn't hide it. `ตั้งค่า` opens the settings sheet, as the avatar does.
struct PhoneTabs<HomeRoot: View>: View {
    @ViewBuilder let home: () -> HomeRoot

    @State private var dock = PhoneDock(Self.initialTab)
    @State private var notificationService = NotificationService.shared

    var body: some View {
        ZStack {
            ForEach(PhoneTab.stacks, id: \.self) { t in
                if dock.opened.contains(t) {
                    let shown = t == dock.tab
                    stack(t)
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(shown)
                        .accessibilityHidden(!shown)
                }
            }
        }
        .environment(dock)
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { dock.swipe(dx: $0.translation.width, dy: $0.translation.height) })
        .sheet(isPresented: $dock.showSettings) {
            SettingsView(pwa: dock.tab == .pwa).presentationDetents([.large]).environment(\.homeInk, .outdoor)
        }
        // a notification tap opens its screen on the home stack
        .onChange(of: notificationService.link) { _, link in
            guard link != nil else { return }
            dock.showSettings = false
            dock.select(.home)
        }
    }

    private func stack(_ t: PhoneTab) -> some View {
        NavigationStack {
            Group {
                switch t {
                // every PWA station's papers (docs/ui/pwa-docs-iphone-v2); the residential library is a row of the
                // settings sheet, as the tools register is
                // each root erased, as on iPad (`PadTabs`): otherwise every tab's layouts are worked out at launch
                case .docs: AnyView(PWADocsHomeView())
                // the PWA project home, with its plan, stations and bell (docs/ui/pwa-solar-survey-iphone-v3 §1)
                case .pwa: AnyView(PWARoot())
                default: if let module = t.module { AnyView(module.destination) } else { AnyView(home()) }
                }
            }
            .onAppear { dock.atRoot.insert(t) }
            .onDisappear { dock.atRoot.remove(t) }
            // the PWA home keeps its own space over the dock, for its add button
            .phoneDock(fade: t.fade, fadeHeight: t.fadeHeight, spacing: t == .pwa ? 0 : PhoneTab.barGap)
        }
    }

    private static var initialTab: PhoneTab {
        #if DEBUG
        // `-screen pwa` is the PWA module: the `กปภ.` tab
        if DebugScreen.requested == "pwa" { return .pwa }
        // `-homeTab homework|pwa|docs` opens with that tab selected, for simulator checks
        if let raw = UserDefaults.standard.string(forKey: "homeTab"), let t = PhoneTab(rawValue: raw), PhoneTab.stacks.contains(t) { return t }
        #endif
        return .home
    }
}

/// The iPhone dock (`TCTabBar`): `PhoneTabs` puts it under each tab's root, and a pushed page that keeps the dock puts
/// it under itself (`phoneDock`). Outside `PhoneTabs` it is not shown.
struct PhoneDockBar: View {
    @Environment(PhoneDock.self) private var dock: PhoneDock?
    @Query(sort: \Job.installStart) private var jobs: [Job]

    var body: some View {
        if let dock {
            TCTabBar(items: items(dock), selection: Binding(get: { dock.tab }, set: dock.select), dividerBefore: .settings)
        }
    }

    private func items(_ dock: PhoneDock) -> [TCTabItem<PhoneTab>] {
        let home = jobs.surveyToday(.home), pwa = jobs.surveyToday(.pwa)
        return [
            TCTabItem(.home, title: "หน้าหลัก", symbol: "house"),
            TCTabItem(.homeWork, title: "งานบ้าน", asset: "tab-homework", badge: home, accessibilityLabel: home > 0 ? "งานบ้าน | นัดวันนี้ \(home)" : nil),
            TCTabItem(.pwa, title: "กปภ.", asset: "tab-pwa", badge: pwa, accessibilityLabel: pwa > 0 ? "กปภ. | นัดวันนี้ \(pwa)" : nil),
            TCTabItem(.docs, title: "เอกสาร", asset: "tab-docs"),
            // not a tab: settings stays a sheet, like the avatar
            TCTabItem(.settings, title: "ตั้งค่า", symbol: "gearshape") { dock.showSettings = true },
        ]
    }
}

extension View {
    /// The iPhone dock as the bottom safe-area inset, 22 pt above the screen's edge, over the page's fade.
    func phoneDock(fade: Color, fadeHeight: CGFloat = 128, spacing: CGFloat = PhoneTab.barGap) -> some View {
        safeAreaInset(edge: .bottom, spacing: spacing) {
            PhoneDockBar()
                .padding(.horizontal, 12).padding(.bottom, 22)
                .background(alignment: .bottom) { TCDockFade(fade, height: fadeHeight) }
        }
        // the dock measures from the screen's bottom edge, not the home indicator's safe area, and stays
        // there behind the keyboard instead of riding up on it (survey list search)
        .ignoresSafeArea(.all, edges: .bottom)
    }
}
