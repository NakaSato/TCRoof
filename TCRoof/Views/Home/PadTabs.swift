import SwiftUI
import TCRoofUI
import SwiftData

/// Root tabs of the iPad (regular width) behind the floating dock (docs/ui/tcroof-home-ipad-v2).
enum PadTab: String, CaseIterable {
    /// `settings` is only the dock's button for the settings sheet, never a selected tab.
    case home, pwa, survey, docs, tools, scan, settings

    static let stacks = allCases.filter { $0 != .settings }
    /// Space the root screens keep above the dock: with the dock's 72 pt and its 18 pt below, content ends 100 pt up.
    static let barGap: CGFloat = 10

    var module: AppModule? { AppModule(rawValue: rawValue) }

    /// The page colour its content fades into behind the dock.
    var fade: Color { self == .home || self == .pwa || self == .tools || self == .docs ? Theme.phonePage : Theme.background }
}

/// The dock's state, for the screens under it: the home sends `ดูทั้งหมด` to the `งานบ้าน` tab, and it and the PWA home
/// close their notifications when the dock is used.
@Observable final class PadDock {
    var tab: PadTab
    private(set) var opened: Set<PadTab>
    var showSettings = false
    /// The page shown has no fade behind the dock (the PWA plan page, docs/ui/pwa-plan-ipad).
    var noFade = false

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
            // each root erased: written out, every tab's screen type sat in one switch and SwiftUI worked out all of their
            // layouts at launch, tabs never opened included (seconds of CPU on a device)
            Group {
                switch t {
                // the PWA project home, with its plan, stations and bell (docs/ui/pwa-solar-survey-ipad-v3 §2)
                case .pwa: AnyView(PWARoot())
                // every PWA station's papers (docs/ui/pwa-docs-ipad); the residential library is the settings sheet's
                // `เอกสารงานบ้าน` row, as on the iPhone
                case .docs: AnyView(PWADocsPadView())
                // the plan calendar and the install records left the dock: they are rows over the register for now
                // (docs/ui/pwa-solar-survey-ipad-v3, open question 1)
                case .tools: AnyView(ToolsView(modules: [.plan, .travel]))
                default: if let module = t.module { AnyView(module.destination) } else { AnyView(home()) }
                }
            }
            .padDock(fade: dock.noFade ? nil : t.fade)
        }
    }

    private static var initialTab: PadTab {
        #if DEBUG
        // `-screen pwa` is the PWA module: the `โครงการ` tab
        if DebugScreen.requested == "pwa" { return .pwa }
        // `-homeTab survey|pwa|docs|tools|scan` opens with that tab selected, for simulator checks
        if let raw = UserDefaults.standard.string(forKey: "homeTab"), let t = PadTab(rawValue: raw), PadTab.stacks.contains(t) { return t }
        #endif
        return .home
    }
}

/// The iPad dock (`TCTabBar`): `PadTabs` puts it under each tab's root, and a pushed page that keeps the dock
/// (the install tracking page, docs/ui/install-tracking-ipad) puts it under itself. Outside `PadTabs` it is not shown.
struct PadDockBar: View {
    @Environment(PadDock.self) private var dock: PadDock?
    @Query(sort: \Job.installStart) private var jobs: [Job]

    var body: some View {
        if let dock {
            TCTabBar(items: items(dock), selection: Binding(get: { dock.tab }, set: dock.select), dividerBefore: .settings, size: .pad)
        }
    }

    private func items(_ dock: PadDock) -> [TCTabItem<PadTab>] {
        let home = jobs.surveyToday(.home), pwa = jobs.surveyToday(.pwa)
        return [
            TCTabItem(.home, title: "หน้าแรก", symbol: "house"),
            TCTabItem(.pwa, title: "โครงการ", asset: "tab-project", badge: pwa, accessibilityLabel: pwa > 0 ? "โครงการ | นัดวันนี้ \(pwa)" : nil),
            TCTabItem(.survey, title: "งานบ้าน", asset: "tab-homework", badge: home, accessibilityLabel: home > 0 ? "งานบ้าน | นัดวันนี้ \(home)" : nil),
            TCTabItem(.docs, title: "เอกสาร", asset: "tab-docs"),
            TCTabItem(.tools, title: "เครื่องมือ", asset: "tab-tools", accessibilityLabel: "เครื่องมือวัด"),
            TCTabItem(.scan, title: "สแกน", asset: "tab-scan"),
            // not a tab: settings stays a sheet, as on the iPhone
            TCTabItem(.settings, title: "ตั้งค่า", symbol: "gearshape", accessibilityLabel: "ตั้งค่าและบัญชี") { dock.showSettings = true },
        ]
    }
}

extension View {
    /// The dock as the bottom safe-area inset, 18 pt above the screen's edge, over the page's fade when it has one.
    func padDock(fade: Color?) -> some View {
        safeAreaInset(edge: .bottom, spacing: PadTab.barGap) {
            PadDockBar()
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity)
                .background(alignment: .bottom) { if let fade { TCDockFade(fade, height: 90) } }
        }
        // the dock measures from the screen's bottom edge, not the home indicator's safe area
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

extension Array where Element == Job {
    /// Today's survey appointments of one kind of job, for the badge of the dock tab that owns them.
    func surveyToday(_ kind: JobKind) -> Int { filter { $0.surveyDate.isToday && $0.kind == kind }.count }
}
