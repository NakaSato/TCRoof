import SwiftUI
import TCRoofUI

/// Bridges the TCRoof home screen to the SurveyKit module.
struct SolarSurveyEntryView: View {
    /// iPhone only: the project home or the `ตั้งค่า` tab's page (`PWAPhoneTabs`).
    var page = SolarSurveyReportView.Page.project
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            // the iPhone header names the project and its client (docs/ui/pwa-solar-survey-iphone-v2)
            SolarSurveyReportView(title: "PWA Solar Project", subtitle: "การประปาส่วนภูมิภาค", page: page)
        } else {
            SolarSurveyReportView(
                title: "PWA Solar Survey",
                subtitle: "แบบสำรวจเพื่อออกแบบ (เบื้องต้น)"
            )
        }
    }
}
