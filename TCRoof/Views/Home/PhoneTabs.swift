import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore

/// Root tabs of the iPhone (compact width) behind the floating tab dock (docs/ui/tcroof-home-iphone-v3).
enum PhoneTab: String {
    /// `settings` is only the dock's button for the settings sheet, never a selected tab.
    case home, homeWork = "homework", pwa, docs, monitor, settings

    static let stacks: [PhoneTab] = [.home, .homeWork, .pwa, .docs, .monitor]
    /// Space the root screens keep above the dock: with the dock's 66 pt and its 22 pt below, content ends 104 pt up.
    static let barGap: CGFloat = 16

    var module: AppModule? {
        switch self {
        case .home, .settings: nil
        case .homeWork: .survey
        case .pwa: .pwa
        case .docs, .monitor: nil
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
    func swipe(dx: CGFloat, dy: CGFloat, tabs: [PhoneTab]) {
        guard atRoot.contains(tab), abs(dx) > 70, abs(dx) > 2.5 * abs(dy),
              let i = tabs.firstIndex(of: tab) else { return }
        let next = i + (dx < 0 ? 1 : -1)
        guard tabs.indices.contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { select(tabs[next]) }
    }
}

/// iPhone root: one `NavigationStack` per tab, the selected one shown. Each tab's root screen carries
/// `TCTabBar` as its bottom safe-area inset, so the page scrolls behind the dock and a pushed screen slides in
/// over it and covers it, like a system tab bar that hides on push. A tab's stack is built the first time it is opened and then kept,
/// so each tab keeps its place. Not a `TabView`: its system bar would come back on every pushed screen that
/// doesn't hide it. `ตั้งค่า` opens the settings sheet, as the avatar does.
struct PhoneTabs<HomeRoot: View>: View {
    @ViewBuilder let home: () -> HomeRoot

    @Environment(\.permissions) private var permissions

    @State private var dock = PhoneDock(Self.initialTab)
    @State private var notificationService = NotificationService.shared

    private var availableTabs: [PhoneTab] {
        // the papers and Monitoring are the team's (a contractor has neither), as on iPad
        PhoneTab.stacks.filter { ($0 != .docs && $0 != .monitor) || permissions.role != .external }
    }

    var body: some View {
        ZStack {
            ForEach(availableTabs, id: \.self) { t in
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
        .onChange(of: availableTabs, initial: true) { _, tabs in
            if !tabs.contains(dock.tab) { dock.select(.home) }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { dock.swipe(dx: $0.translation.width, dy: $0.translation.height, tabs: availableTabs) })
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
                case .docs: AnyView(PWADocsHomeView(isActive: dock.tab == .docs))
                // the PWA project home, with its plan, stations and bell (docs/ui/pwa-solar-survey-iphone-v3 §1)
                case .pwa: AnyView(PWARoot())
                // every handed-over station's output from Growatt, in one column (CHA-34, docs/ui/iphone-monitor-entry)
                case .monitor: AnyView(PhoneMonitoringPage())
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
        // `-homeTab homework|pwa|docs|monitor` opens with that tab selected, for simulator checks
        if let raw = UserDefaults.standard.string(forKey: "homeTab"), let t = PhoneTab(rawValue: raw), PhoneTab.stacks.contains(t) { return t }
        #endif
        return .home
    }
}

/// The iPhone dock (`TCTabBar`): `PhoneTabs` puts it under each tab's root, and a pushed page that keeps the dock puts
/// it under itself (`phoneDock`). Outside `PhoneTabs` it is not shown.
struct PhoneDockBar: View {
    @Environment(\.permissions) private var permissions
    @Environment(PhoneDock.self) private var dock: PhoneDock?
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Calendar.current.startOfDay(for: .now)

    var body: some View {
        if let dock {
            PhoneDockBarContent(dock: dock, permissions: permissions, today: today)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        let currentStart = Calendar.current.startOfDay(for: .now)
                        if currentStart != today { today = currentStart }
                    }
                }
        }
    }
}

private struct PhoneDockBarContent: View {
    let dock: PhoneDock
    let permissions: Permissions
    let today: Date
    @Query private var jobsToday: [Job]
    /// The badge of `Monitor`: the stations needing someone (`MonitoringStore.attentionCount`, as on iPad).
    @State private var monitoring = MonitoringStore.shared

    init(dock: PhoneDock, permissions: Permissions, today: Date) {
        self.dock = dock
        self.permissions = permissions
        self.today = today
        let end = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        _jobsToday = Query(filter: #Predicate<Job> {
            $0.surveyDate >= today && $0.surveyDate < end
        })
    }

    var body: some View {
        TCTabBar(items: items(dock), selection: Binding(get: { dock.tab }, set: dock.select), dividerBefore: .settings)
            // the demo's fleet counts from launch; real stations once the page has read them
            .task { if MonitoringStore.demo, monitoring.refreshedAt == nil { monitoring.refresh(jobs: []) } }
            // the team's phones read Growatt while the app is open (only with a token saved on this phone), for the
            // badge; they post no alerts, which stay the iPad's (CHA-34); contractors have no Monitor
            .background { if permissions.role != .external { MonitoringPoller() } }
    }

    private func items(_ dock: PhoneDock) -> [TCTabItem<PhoneTab>] {
        let home = jobsToday.filter { $0.kind == .home }.count
        let pwa = jobsToday.filter { $0.kind == .pwa }.count
        let attention = monitoring.attentionCount
        return [
            TCTabItem<PhoneTab>(.home, title: "หน้าหลัก", symbol: "house"),
            TCTabItem(.homeWork, title: "งานบ้าน", asset: "tab-homework", badge: home, accessibilityLabel: home > 0 ? "งานบ้าน | นัดวันนี้ \(home)" : nil),
            TCTabItem(.pwa, title: "กปภ.", asset: "tab-pwa", badge: pwa, accessibilityLabel: pwa > 0 ? "กปภ. | นัดวันนี้ \(pwa)" : nil),
            TCTabItem(.docs, title: "เอกสาร", asset: "tab-docs"),
            TCTabItem(.monitor, title: "Monitor", asset: "tab-monitor", badge: attention,
                      accessibilityLabel: attention > 0 ? "Monitor | ต้องดูแล \(attention)" : "Monitor"),
            // not a tab: settings stays a sheet, like the avatar
            TCTabItem(.settings, title: "ตั้งค่า", symbol: "gearshape") { dock.showSettings = true },
        ].filter { ($0.id != .docs && $0.id != .monitor) || permissions.role != .external }
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
