import SwiftUI
import TCRoofUI
import SwiftData

/// Root tabs of the iPhone (compact width) under the docked tab bar (docs/ui/tcroof-home-iphone-v2).
enum PhoneTab: String {
    /// `settings` is only the bar's button for the settings sheet, never a selected tab.
    case home, survey, plan, tools, settings

    static let stacks: [PhoneTab] = [.home, .survey, .plan, .tools]
    /// Space the root screens keep above the tab bar.
    static let barGap: CGFloat = 4

    var module: AppModule? {
        switch self {
        case .home, .settings: nil
        case .survey: .survey
        case .plan: .plan
        case .tools: .tools
        }
    }
}

/// iPhone root: one `NavigationStack` per tab, the selected one shown. Each tab's root screen carries
/// `TCTabBar` as its bottom safe-area inset, so a pushed screen slides in over the bar and covers it,
/// like a system tab bar that hides on push. A tab's stack is built the first time it is opened and then kept,
/// so each tab keeps its place. Not a `TabView`: its system bar would come back on every pushed screen that
/// doesn't hide it. `ตั้งค่า` opens the settings sheet, as the avatar does.
struct PhoneTabs<HomeRoot: View>: View {
    @ViewBuilder let home: () -> HomeRoot

    @State private var tab: PhoneTab = Self.initialTab
    @State private var opened: Set<PhoneTab> = [Self.initialTab]
    @State private var showSettings = false
    @State private var notificationService = NotificationService.shared
    @State private var instruments = InstrumentStore.shared
    @Query(sort: \Job.installStart) private var jobs: [Job]

    var body: some View {
        ZStack {
            ForEach(PhoneTab.stacks, id: \.self) { t in
                if opened.contains(t) {
                    let shown = t == tab
                    stack(t)
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(shown)
                        .accessibilityHidden(!shown)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().presentationDetents([.large]).environment(\.homeInk, .outdoor)
        }
        // a notification tap opens its screen on the home stack
        .onChange(of: notificationService.link) { _, link in
            guard link != nil else { return }
            showSettings = false
            select(.home)
        }
    }

    private func select(_ t: PhoneTab) {
        opened.insert(t)
        tab = t
    }

    private func stack(_ t: PhoneTab) -> some View {
        NavigationStack {
            Group {
                switch t {
                // scan, install records and PWA have no tab: they are rows above the tools register
                case .tools: ToolsView(modules: [.scan, .install, .pwa])
                default: if let module = t.module { module.destination } else { home() }
                }
            }
            // 4 pt over the bar: a root's FAB (12 pt padding) sits the board's 16 pt above it
            .safeAreaInset(edge: .bottom, spacing: PhoneTab.barGap) {
                TCTabBar(items: items, selection: Binding(get: { tab }, set: select))
            }
            // the bar stays docked behind the keyboard instead of riding up on it (survey list search)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    private var surveyToday: Int { jobs.filter { $0.surveyDate.isToday }.count }

    private var items: [TCTabItem<PhoneTab>] {
        let n = surveyToday
        // tools due for calibration within 30 days or past it
        let due = instruments.dueCount()
        return [
            TCTabItem(.home, title: "หน้าหลัก", symbol: "house"),
            TCTabItem(.survey, title: "สำรวจ", symbol: "list.clipboard", badge: n, accessibilityLabel: n > 0 ? "สำรวจ · นัดวันนี้ \(n)" : nil),
            TCTabItem(.plan, title: "แผนงาน", symbol: "calendar"),
            TCTabItem(.tools, title: "เครื่องมือ", asset: "tab-tools", badge: due,
                      accessibilityLabel: due > 0 ? "เครื่องมือวัด · ต้องสอบเทียบ \(due)" : "เครื่องมือวัด"),
            // not a tab: settings stays a sheet, like the avatar
            TCTabItem(.settings, title: "ตั้งค่า", symbol: "gearshape") { showSettings = true },
        ]
    }

    private static var initialTab: PhoneTab {
        #if DEBUG
        // `-homeTab survey|plan|tools` opens with that tab selected, for simulator checks
        if let raw = UserDefaults.standard.string(forKey: "homeTab"), let t = PhoneTab(rawValue: raw), PhoneTab.stacks.contains(t) { return t }
        #endif
        return .home
    }
}
