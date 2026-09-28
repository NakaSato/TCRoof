import SwiftUI
import SurveyUI

/// กลุ่ม "การประปาส่วนภูมิภาค" — ระบบ PWA Solar Survey: แบบสำรวจเพื่อออกแบบ (เบื้องต้น) ฟอร์ม NO.224,
/// Export Excel ตรงแบบฟอร์ม, รายงาน PDF แบบ NO.215 และบันทึกลง Google Drive (จาก SolarSurveyKit)
struct SolarSurveyEntryView: View {
    var body: some View {
        SolarSurveyReportView(
            title: "PWA Solar Survey",
            subtitle: "การประปาส่วนภูมิภาค · แบบสำรวจเพื่อออกแบบ (เบื้องต้น)"
        )
    }
}
