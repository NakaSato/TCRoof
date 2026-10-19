#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// The iPhone `ตั้งค่า` tab of the PWA module (docs/ui/pwa-solar-survey-iphone-v2 §7): grouped cards under the blue
/// header. It also carries what the header's ••• menu had. A row with no screen yet shows its chevron and does nothing.
extension SurveyHomeView {
    private func setting<T>(_ key: WritableKeyPath<SurveySettings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: key] }, set: { model.settings[keyPath: key] = $0 })
    }

    private func toggle(_ key: WritableKeyPath<SurveySettings, Bool>, _ label: String) -> some View {
        Toggle(label, isOn: setting(key)).labelsHidden().tint(Theme.success)
    }

    private func action(_ title: String, detail: String = "", disabled: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { TCSettingsRow(title, detail: detail) }.buttonStyle(.plain).disabled(disabled)
    }

    private func percent(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }

    @ViewBuilder var settingsGroups: some View {
        projectGroups
        reportGroups
        dataGroups
        Text("TCRoof \(appVersion) · ใช้กับงานของ กปภ. เท่านั้น งานอื่นไม่เปลี่ยน")
            .font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 2)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    @ViewBuilder private var projectGroups: some View {
        let stations = installStations
        let teams = InstallOverview.contractors(stations, threshold: model.settings.behindThreshold)
        TCSettingsGroup("โครงการ") {
            TCSettingsRow(title, detail: "\(stations.count + maintenanceStations.count) สถานี · ผู้ว่าจ้าง \(subtitle)")
            TCSettingsRow("สัญญาและระยะเวลา", detail: "เลขที่สัญญา · วันเริ่ม–วันสิ้นสุด")
        }
        TCSettingsGroup("ทีมงาน") {
            TCSettingsRow("ผู้รับเหมา", detail: teams.isEmpty ? "ยังไม่มีผู้รับเหมาในงานติดตั้ง" : "\(teams.count) ทีม · " + teams.map(\.name).joined(separator: ", "))
            TCSettingsRow("ทีมควบคุมงาน TC", detail: "ผู้ควบคุมงาน และวิศวกร")
        }
        TCSettingsGroup("แผน MP") {
            TCSettingsRow("น้ำหนักงานมาตรฐาน", detail: "น้ำหนักของแต่ละงานในแผน MP")
            thresholdRow
        }
    }

    /// `เกณฑ์ "ช้ากว่าแผน"`: the install overview counts a station behind from this many percent under its plan.
    private var thresholdRow: some View {
        Menu {
            Picker("เกณฑ์ \"ช้ากว่าแผน\"", selection: setting(\.behindThreshold)) {
                ForEach([1.0, 2, 3, 5, 10], id: \.self) { Text("ต่ำกว่าแผน ≥ \(percent($0))%").tag($0) }
            }
        } label: {
            TCSettingsRow("เกณฑ์ \"ช้ากว่าแผน\"", detail: "ต่ำกว่าแผน ≥ \(percent(model.settings.behindThreshold))%")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var reportGroups: some View {
        TCSettingsGroup("รายงานประจำวัน") {
            TCSettingsRow("แจ้งเตือนก่อนหมดเวลาส่ง", detail: "ก่อนครบกำหนดส่งรายงานของวัน") { toggle(\.remindDailyDeadline, "แจ้งเตือนก่อนหมดเวลาส่ง") }
            TCSettingsRow("เตือนเมื่อผู้ตรวจยังไม่รับทราบ", detail: "รายงานที่ลงนามแล้วแต่ยังไม่มีผู้รับทราบ") {
                toggle(\.remindInspectorPending, "เตือนเมื่อผู้ตรวจยังไม่รับทราบ")
            }
            TCSettingsRow("ผู้ตรวจงานเริ่มต้น", detail: "ผู้แทนของแต่ละสถานี")
        }
        TCSettingsGroup("เอกสารและซิงก์") {
            TCSettingsRow("แม่แบบรายงาน", detail: "รายงานประจำวัน · คำขอรายสัปดาห์ · ผลทดสอบ")
            TCSettingsRow("ซิงก์รูปขึ้น Google Drive อัตโนมัติ", detail: "ส่งรูปใหม่ขึ้น Drive เบื้องหลัง") {
                toggle(\.autoUploadPhotos, "ซิงก์รูปขึ้น Google Drive อัตโนมัติ")
            }
            syncRow
        }
    }

    private var syncRow: some View {
        let n = model.jobsToSync.count
        return Button { syncAll() } label: {
            TCSettingsRow("ซิงก์ทั้งหมดตอนนี้", detail: n > 0 ? "\(n) งานรอขึ้นคลาวด์" : "ทุกงานขึ้นคลาวด์แล้ว") {
                TCToneChip(n > 0 ? "ซิงก์ \(n)" : "ครบแล้ว", tone: n > 0 ? .blue : .green)
            }
        }
        .buttonStyle(.plain)
        .disabled(n == 0 || busy != nil)
        .accessibilityLabel("ซิงก์ทั้งหมด (\(n))")
    }

    private var dataGroups: some View {
        TCSettingsGroup("ข้อมูล") {
            action("เปิดจาก Google Drive") { showDriveOpen = true }
            action("นำเข้าไฟล์ข้อมูล (.json)") { importing = true }
            action("สำรองข้อมูลทุกงาน", disabled: model.jobs.isEmpty) {
                do { share = try model.exportBackup() } catch { self.error = error.localizedDescription }
            }
            action("คลังแบบมาตรฐาน", detail: "แบบถังน้ำใส กปภ. · แบบที่ทีมบันทึก") { showLibrary = true }
            action("ตั้งค่าแอป", detail: "วิศวกร · แผนที่ · Google Drive · เครื่องนี้") { showSettings = true }
        }
    }
}
#endif
