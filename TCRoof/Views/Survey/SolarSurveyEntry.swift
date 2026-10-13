import SwiftUI
import TCRoofUI

/// Bridges the TCRoof home screen to the SurveyKit module.
struct SolarSurveyEntryView: View {
    /// The project home (`PWARoot`) or the project settings page (`PWASettingsPage`).
    var page = SolarSurveyReportView.Page.project

    var body: some View {
        // the home's header is `โครงการ PWA` (docs/ui/pwa-solar-survey-iphone-v3 §2); the settings page still names
        // the project and its client
        SolarSurveyReportView(title: page == .settings ? "PWA Solar Project" : "โครงการ PWA", subtitle: "การประปาส่วนภูมิภาค", page: page)
    }
}
