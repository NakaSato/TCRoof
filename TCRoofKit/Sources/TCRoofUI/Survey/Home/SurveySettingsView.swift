#if canImport(UIKit)
import SwiftUI
import TCRoofCore

struct SurveySettingsView: View {
    @Environment(SurveyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var s = SurveySettings()
    @State private var error: String?
    @State private var signedIn = false
    @AppStorage(CameraRoll.defaultsKey) private var saveToLibrary = true

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                PadSection("รายงาน") {
                    TextField("ชื่อบริษัท (หัวรายงาน PDF)", text: $s.company)
                    TextField("ชื่อวิศวกรผู้สำรวจ (ใส่ให้งานใหม่อัตโนมัติ)", text: $s.engineer)
                    Toggle("พิมพ์พิกัด ทิศ และเวลาใต้รูปในรายงาน", isOn: $s.printPhotoStamps)
                }
                PadSection("รูปถ่าย") {
                    Toggle("บันทึกรูปที่ถ่ายลงคลังภาพของเครื่องด้วย", isOn: $saveToLibrary)
                } footer: {
                    Text("รูปจากกล้องในแอปจะเก็บไว้ในแอป Photos ด้วย ขนาดเต็ม พร้อมพิกัดและทิศที่ถ่าย")
                }
                DeviceCapsSection()
                PadSection("แผงโซลาร์") {
                    PadPicker("แผงโซลาร์", selection: $s.pvModule) {
                        ForEach(PVModuleCatalog.all) { spec in
                            ForEach(spec.variants) { v in Text("\(spec.manufacturer) \(spec.series) | \(Int(v.pmaxW)) W").tag(v.id) }
                        }
                    }
                    if let hit = PVModuleCatalog.variant(s.pvModule) {
                        LabeledContent("ขนาด", value: "\(Int(hit.spec.mechanical.lengthMm)) × \(Int(hit.spec.mechanical.widthMm)) มม. | \(hit.spec.mechanical.weightKg.formatted()) กก.")
                        LabeledContent("Voc / Isc", value: "\(hit.variant.stc.vocV.formatted()) V / \(hit.variant.stc.iscA.formatted()) A")
                    }
                } footer: {
                    Text("ใช้คิด W/แผง → kWp ในภาพสถานที่ติดตั้ง (A2) ข้อมูลจาก datasheet ที่แนบไว้ในแอป")
                }
                PadSection("ภาพสถานที่ติดตั้งจากแผนที่") {
                    SecureField("Mapbox access token", text: $s.mapboxToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Google Maps API key (Maps Static API)", text: $s.googleMapsKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Stepper(value: $s.mapZoom, in: 15...21) {
                        LabeledContent("ระดับซูม", value: "\(s.mapZoom)  (กว้างประมาณ \(Int(MapImage.metersAcross(lat: 15, zoom: s.mapZoom).rounded())) ม.)")
                    }
                } footer: {
                    Text("ปุ่ม \"แผนที่ดาวเทียม\" ในกรอบภาพสถานที่ติดตั้ง / ภาพมุมสูง ดึงภาพดาวเทียมตรงพิกัด GPS ของงาน ใช้ภาพดาวเทียม Mapbox เป็นหลัก ถ้าไม่มี token หรือ Mapbox ไม่ตอบ จะใช้ Google Maps (ถ้าใส่ key ไว้) แล้วจึงใช้ภาพของ Apple Maps")
                }
                PadSection("น้ำท่วม (A4)") {
                    SecureField("GISTDA API key", text: $s.gistdaKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text("ใช้ปุ่ม \"ดึงข้อมูลจาก GISTDA\" ในหน้า A4 เมื่อไม่ทราบประวัติน้ำท่วม key เก็บในเครื่องนี้เท่านั้น ไม่ถูกบันทึกในงานหรือส่งขึ้น Drive")
                }
                PadSection("Google Drive") {
                    TextField("xxxxxxxx.apps.googleusercontent.com", text: $s.googleClientID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("โฟลเดอร์หลักใน Drive", text: $s.driveRoot)
                    Toggle("อัปรูปขึ้น Drive อัตโนมัติ", isOn: $s.autoUploadPhotos)
                    if signedIn {
                        LabeledContent("บัญชี", value: model.google.email ?? "ลงชื่อเข้าใช้แล้ว")
                        Button("ออกจากระบบ Google", role: .destructive) { if let out = model.signOutHandler { out() } else { model.google.signOut(); signedIn = false } }
                            .foregroundStyle(Theme.danger)
                    } else {
                        Button("ลงชื่อเข้าใช้ Google") {
                            apply()
                            Task { do { try await model.google.signIn(); signedIn = true } catch { self.error = error.localizedDescription } }
                        }
                        .foregroundStyle(Theme.primary)
                    }
                } footer: {
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
