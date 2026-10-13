import SwiftUI
import TCRoofUI
import SwiftData

/// Root tabs of the iPad (regular width) behind the floating dock (docs/ui/tcroof-home-ipad-v2).
enum PadTab: String, CaseIterable {
    /// `settings` is only the dock's button for the settings sheet, never a selected tab.
    case home, survey, plan, install, scan, pwa, tools, settings

    static let stacks = allCases.filter { $0 != .settings }
    /// Space the root screens keep above the dock: with the dock's 72 pt and its 18 pt below, content ends 100 pt up.
    static let barGap: CGFloat = 10

    var module: AppModule? { AppModule(rawValue: rawValue) }

    /// The page colour its content fades into behind the dock.
    var fade: Color { self == .home || self == .tools ? Theme.phonePage : Theme.background }
}

/// The dock's state, for the screens under it: the home sends `ดูทั้งหมด` to the `สำรวจ` tab and closes its
/// notifications when the dock is used.
@Observable final class PadDock {
    var tab: PadTab
    private(set) var opened: Set<PadTab>
    var showSettings = false

    init(_ tab: PadTab) {
        self.tab = tab
        opened = [tab]
    }

    func select(_ t: PadTab) {
        opened.insert(t)
        tab = t
    }
}

/// iPad root, as `PhoneTabs` on the iPhone: one `NavigationStack` per tab, the selected one shown. Each tab's root
/// screen carries `TCTabBar` as its bottom safe-area inset, so a pushed screen slides in over the dock and covers it.
/// A tab's stack is built the first time it is opened and then kept. `ตั้งค่า` opens the settings sheet.
struct PadTabs<HomeRoot: View>: View {
    @ViewBuilder let home: () -> HomeRoot

    @State private var dock = PadDock(Self.initialTab)
    @State private var notificationService = NotificationService.shared
    @Query(sort: \Job.installStart) private var jobs: [Job]

    var body: some View {
        ZStack {
            ForEach(PadTab.stacks, id: \.self) { t in
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
        .debugBoard()
        .sheet(isPresented: $dock.showSettings) {
            SettingsView().presentationDetents([.large]).formSheetSizing()
        }
        // a notification tap opens its screen on the home stack
        .onChange(of: notificationService.link) { _, link in
            guard link != nil else { return }
            dock.showSettings = false
            dock.select(.home)
        }
    }

    private func stack(_ t: PadTab) -> some View {
        NavigationStack {
            Group {
                if let module = t.module { module.destination } else { home() }
            }
            .safeAreaInset(edge: .bottom, spacing: PadTab.barGap) {
                TCTabBar(items: items, selection: Binding(get: { dock.tab }, set: dock.select), dividerBefore: .settings, size: .pad)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity)
                    .background(alignment: .bottom) { TCDockFade(t.fade, height: 90) }
            }
            // the dock measures from the screen's bottom edge, not the home indicator's safe area
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private var items: [TCTabItem<PadTab>] {
        let today = jobs.filter { $0.surveyDate.isToday }.count
        return [
            TCTabItem(.home, title: "หน้าหลัก", symbol: "house"),
            TCTabItem(.survey, title: "สำรวจ", asset: "tab-survey", badge: today, accessibilityLabel: today > 0 ? "สำรวจ · นัดวันนี้ \(today)" : nil),
            TCTabItem(.plan, title: "แผนงาน", symbol: "calendar"),
            TCTabItem(.install, title: "ติดตั้ง", asset: "tab-install"),
            TCTabItem(.scan, title: "สแกน", asset: "tab-scan"),
            TCTabItem(.pwa, title: "กปภ.", asset: "tab-pwa"),
            TCTabItem(.tools, title: "เครื่องมือ", asset: "tab-tools", accessibilityLabel: "เครื่องมือวัด"),
            // not a tab: settings stays a sheet, as on the iPhone
            TCTabItem(.settings, title: "ตั้งค่า", symbol: "gearshape", accessibilityLabel: "ตั้งค่าและบัญชี") { dock.showSettings = true },
        ]
    }

    private static var initialTab: PadTab {
        #if DEBUG
        // `-homeTab survey|plan|install|scan|pwa|tools` opens with that tab selected, for simulator checks
        if let raw = UserDefaults.standard.string(forKey: "homeTab"), let t = PadTab(rawValue: raw), PadTab.stacks.contains(t) { return t }
        #endif
        return .home
    }
}
