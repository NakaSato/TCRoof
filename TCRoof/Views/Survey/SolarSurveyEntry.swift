import SwiftUI
import TCRoofUI

/// Bridges the TCRoof home screen to the SurveyKit module.
struct SolarSurveyEntryView: View {
    /// iPhone only: the project home (`PWAPhoneRoot`) or the project settings page (`PWASettingsPage`).
    var page = SolarSurveyReportView.Page.project
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            // the home's header is `โครงการ PWA` (docs/ui/pwa-solar-survey-iphone-v3 §2); the settings page still names
            // the project and its client
            SolarSurveyReportView(title: page == .settings ? "PWA Solar Project" : "โครงการ PWA", subtitle: "การประปาส่วนภูมิภาค", page: page)
        } else {
            SolarSurveyReportView(
                title: "PWA Solar Survey",
                subtitle: "แบบสำรวจเพื่อออกแบบ (เบื้องต้น)"
            )
        }
    }
}
