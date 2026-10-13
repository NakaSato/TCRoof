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
    var fade: Color { self == .homeWork || self == .docs ? Theme.background : Theme.phonePage }

    /// The fade's height: the board's 128 pt, or lower under the survey list so it stays clear of that list's own dock.
    var fadeHeight: CGFloat { self == .homeWork ? 108 : 128 }
}

/// iPhone root: one `NavigationStack` per tab, the selected one shown. Each tab's root screen carries
/// `TCTabBar` as its bottom safe-area inset, so the page scrolls behind the dock and a pushed screen slides in
/// over it and covers it, like a system tab bar that hides on push. A tab's stack is built the first time it is opened and then kept,
/// so each tab keeps its place. Not a `TabView`: its system bar would come back on every pushed screen that
/// doesn't hide it. `ตั้งค่า` opens the settings sheet, as the avatar does.
struct PhoneTabs<HomeRoot: View>: View {
    @ViewBuilder let home: () -> HomeRoot

    @State private var tab: PhoneTab = Self.initialTab
    @State private var opened: Set<PhoneTab> = [Self.initialTab]
    @State private var showSettings = false
    @State private var notificationService = NotificationService.shared
    @Query(sort: \Job.installStart) private var jobs: [Job]

    var body: some View {
        ZStack {
            ForEach(PhoneTab.stacks, id: \.self) { t in
                if opened.contains(t) {
                    let shown = t == tab
                    Group {
                        // the PWA module brings its own dock and stacks, in place of this one
                        if t == .pwa { PWAPhoneTabs { select(.home) } } else { stack(t) }
                    }
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
                // the residential document library; the tools register is under the settings sheet for now
                case .docs: HomeLibraryView()
                default: if let module = t.module { module.destination } else { home() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: PhoneTab.barGap) {
                TCTabBar(items: items, selection: Binding(get: { tab }, set: select), dividerBefore: .settings)
                    .padding(.horizontal, 12).padding(.bottom, 22)
                    .background(alignment: .bottom) { TCDockFade(t.fade, height: t.fadeHeight) }
            }
            // the dock measures from the screen's bottom edge, not the home indicator's safe area, and stays
            // there behind the keyboard instead of riding up on it (survey list search)
            .ignoresSafeArea(.all, edges: .bottom)
        }
    }

    /// Today's appointments of one kind of job, for the badge of the tab that owns them.
    private func surveyToday(_ kind: JobKind) -> Int { jobs.filter { $0.surveyDate.isToday && $0.kind == kind }.count }

    private var items: [TCTabItem<PhoneTab>] {
        let home = surveyToday(.home), pwa = surveyToday(.pwa)
        return [
            TCTabItem(.home, title: "หน้าหลัก", symbol: "house"),
            TCTabItem(.homeWork, title: "งานบ้าน", asset: "tab-homework", badge: home, accessibilityLabel: home > 0 ? "งานบ้าน · นัดวันนี้ \(home)" : nil),
            TCTabItem(.pwa, title: "กปภ.", asset: "tab-pwa", badge: pwa, accessibilityLabel: pwa > 0 ? "กปภ. · นัดวันนี้ \(pwa)" : nil),
            TCTabItem(.docs, title: "เอกสาร", asset: "tab-docs"),
            // not a tab: settings stays a sheet, like the avatar
            TCTabItem(.settings, title: "ตั้งค่า", symbol: "gearshape") { showSettings = true },
        ]
    }

    private static var initialTab: PhoneTab {
        #if DEBUG
        // `-homeTab homework|pwa|docs` opens with that tab selected, for simulator checks
        if let raw = UserDefaults.standard.string(forKey: "homeTab"), let t = PhoneTab(rawValue: raw), PhoneTab.stacks.contains(t) { return t }
        #endif
        return .home
    }
}
