import SwiftUI
import TCRoofUI

/// On iPad, an installing PWA station's weekly request, Weekly Report and papers live in the install tracking page's tabs.
/// Links from elsewhere (the job screen's cards, notifications, the feed) open that tab, so the iPad has one screen for
/// each; the iPhone, and a station that isn't installing, keep the pushed screens.
extension Job {
    /// The install tracking page opens this station (`[Job].pwaInstalling`'s rule).
    var opensInstallPage: Bool {
        kind == .pwa && (status == .installing || (scheduleInput != nil && status != .completed))
    }
}

extension EnvironmentValues {
    /// Set on the screens the install tracking page pushes: goes back to the page and selects a tab.
    @Entry var installTab: ((InstallTrackingPage.Tab) -> Void)?
}

/// `tab` of the station's install tracking page on iPad, else `fallback`.
struct InstallTabScreen<Fallback: View>: View {
    let job: Job
    let tab: InstallTrackingPage.Tab
    @ViewBuilder let fallback: () -> Fallback
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass != .compact, job.opensInstallPage {
            InstallTrackingPage(job: job, start: tab)
        } else {
            fallback()
        }
    }
}

/// A card's link to `tab`: inside the install tracking page it goes back and selects the tab, elsewhere it pushes
/// `InstallTabScreen`.
struct InstallTabLink<Fallback: View, Label: View>: View {
    let job: Job
    let tab: InstallTrackingPage.Tab
    @ViewBuilder let fallback: () -> Fallback
    @ViewBuilder let label: () -> Label
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.installTab) private var installTab

    var body: some View {
        if sizeClass != .compact, job.opensInstallPage, let installTab {
            Button { installTab(tab) } label: { label() }
        } else {
            NavigationLink { InstallTabScreen(job: job, tab: tab, fallback: fallback) } label: { label() }
        }
    }
}
