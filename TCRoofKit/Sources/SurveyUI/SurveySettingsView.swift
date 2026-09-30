#if canImport(UIKit)
import SwiftUI
import TCRoofCore

struct SurveySettingsView: View {
    @Environment(SurveyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var s = SurveySettings()
    @State private var error: String?
    @State private var signedIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section("รายงาน") {
                    TextField("ชื่อบริษัท (หัวรายงาน PDF)", text: $s.company)
                    TextField("ชื่อวิศวกรผู้สำรวจ (ใส่ให้งานใหม่อัตโนมัติ)", text: $s.engineer)
                }
                Section {
                    SecureField("Google Maps API key (Maps Static API)", text: $s.googleMapsKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Stepper(value: $s.mapZoom, in: 15...21) {
                        LabeledContent("ระดับซูม", value: "\(s.mapZoom)  (กว้างประมาณ \(Int(MapImage.metersAcross(lat: 15, zoom: s.mapZoom).rounded())) ม.)")
                    }
                } header: { Text("ภาพสถานที่ติดตั้งจากแผนที่") } footer: {
                    Text("ปุ่ม \"Google Maps\" ในกรอบภาพสถานที่ติดตั้ง / ภาพมุมสูง ดึงภาพดาวเทียมตรงพิกัด GPS ของงาน ใส่ key ของ Maps Static API เพื่อใช้ภาพ Google ถ้าเว้นว่างจะใช้ภาพดาวเทียมของ Apple Maps แทน")
                }
                Section {
                    SecureField("GISTDA API key", text: $s.gistdaKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("น้ำท่วม (A4)") } footer: {
                    Text("ใช้ปุ่ม \"ดึงข้อมูลจาก GISTDA\" ในหน้า A4 เมื่อไม่ทราบประวัติน้ำท่วม key เก็บในเครื่องนี้เท่านั้น ไม่ถูกบันทึกในงานหรือส่งขึ้น Drive")
                }
                Section {
                    TextField("xxxxxxxx.apps.googleusercontent.com", text: $s.googleClientID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("โฟลเดอร์หลักใน Drive", text: $s.driveRoot)
                    Toggle("อัปรูปขึ้น Drive อัตโนมัติ", isOn: $s.autoUploadPhotos)
                    if signedIn {
                        LabeledContent("บัญชี", value: model.google.email ?? "ลงชื่อเข้าใช้แล้ว")
                        Button("ออกจากระบบ Google", role: .destructive) { if let out = model.signOutHandler { out() } else { model.google.signOut(); signedIn = false } }
                    } else {
                        Button("ลงชื่อเข้าใช้ Google") {
                            apply()
                            Task { do { try await model.google.signIn(); signedIn = true } catch { self.error = error.localizedDescription } }
                        }
                    }
                } header: { Text("Google Drive") } footer: {
                    Text("สร้าง OAuth client ชนิด iOS ใน Google Cloud Console (เปิด Google Drive API) ใส่ Bundle ID ของแอป แล้วคัดลอก Client ID มาวางที่นี่ แอปจะเห็นเฉพาะไฟล์ที่แอปสร้างเอง (สิทธิ์ drive.file)\n\nอัปรูปอัตโนมัติ: รูปใหม่จะถูกส่งเข้าโฟลเดอร์งานใน Drive ภายในไม่กี่วินาที เพื่อให้ iPad เครื่องอื่นที่เปิดงานเดียวกันดึงรูปไปได้")
                }
            }
            .navigationTitle("ตั้งค่าแบบสำรวจ").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { apply(); dismiss() } }
            }
            .onAppear { s = model.settings; signedIn = model.google.isSignedIn }
            .errorAlert($error)
        }
    }

    func apply() {
        s.googleClientID = s.googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        model.settings = s
        model.google.clientID = s.googleClientID
    }
}
#endif
