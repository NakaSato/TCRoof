import SwiftUI
import SwiftData
import CoreLocation
import TCRoofCore

// MARK: - History & detail

struct SurveyHistoryView: View {
    @Query(filter: #Predicate<SurveyForm> { !$0.isDraft }, sort: \SurveyForm.createdAt, order: .reverse)
    private var surveys: [SurveyForm]

    var body: some View {
        List {
            if surveys.isEmpty {
                ContentUnavailableView("ยังไม่มีประวัติการสำรวจ", systemImage: "list.clipboard")
            }
            ForEach(surveys) { survey in
                NavigationLink { SurveyDetailView(survey: survey) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(survey.job?.code ?? "-") · \(survey.job?.projectName ?? "")").bold()
                        Text("\(survey.createdAt.thaiLongTime) · โดย \(survey.surveyor)")
                            .font(.caption).foregroundStyle(Theme.muted)
                        Text("\(survey.roofType) · \(survey.roofAreaSqm.plain) ตร.ม. · เสนอ \(survey.recommendedKW.kw)")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Theme.navy)
                }
            }
        }
        .navigationTitle("ประวัติการสำรวจ")
    }
}

struct SurveyDetailView: View {
    let survey: SurveyForm

    private func orDash(_ s: String) -> String { s.isEmpty ? "-" : s }

    var body: some View {
        Form {
            Section {
                InfoRow(title: "โครงการ", value: survey.job?.projectName ?? "-")
                InfoRow(title: "วันที่สำรวจ", value: survey.createdAt.thaiLongTime)
                InfoRow(title: "ผู้สำรวจ", value: survey.surveyor)
                if let lat = survey.latitude, let lon = survey.longitude {
                    InfoRow(title: "พิกัด", value: String(format: "%.6f, %.6f", lat, lon))
                }
            }
            Section("หลังคา") {
                InfoRow(title: "ประเภท", value: orDash(survey.roofType))
                InfoRow(title: "พื้นที่", value: "\(survey.roofAreaSqm.plain) ตร.ม.")
                InfoRow(title: "ทิศทาง / ลาดชัน", value: "\(orDash(survey.orientation)) / \(survey.tiltDegree)°")
                InfoRow(title: "เงาบัง", value: orDash(survey.shading))
                InfoRow(title: "โครงสร้าง", value: survey.structureOK ? "รับน้ำหนักได้" : "ต้องเสริมโครงสร้าง")
            }
            Section("ระบบไฟฟ้า") {
                InfoRow(title: "การไฟฟ้า / CA", value: "\(orDash(survey.utility)) / \(orDash(survey.caNumber))")
                InfoRow(title: "มิเตอร์", value: [survey.meterPhase, survey.meterSize].filter { !$0.isEmpty }.joined(separator: " · "))
                InfoRow(title: "เมนเบรกเกอร์", value: survey.mainBreakerAmp > 0 ? "\(survey.mainBreakerAmp) A" : "-")
                InfoRow(title: "อัตราค่าไฟ", value: orDash(survey.tariff))
                if survey.monthlyKWh > 0 { InfoRow(title: "หน่วย/เดือน", value: "\(survey.monthlyKWh.plain) kWh") }
                InfoRow(title: "ค่าไฟ/เดือน", value: survey.monthlyBill > 0 ? "\(survey.monthlyBill.plain) บาท" : "-")
                InfoRow(title: "สายดินเดิม", value: orDash(survey.grounding))
                InfoRow(title: "ขนาดที่เสนอ", value: survey.recommendedKW.kw)
            }
            ForEach(SurveyOptions.photoTags) { tag in
                let photos = SurveyOptions.photos(survey, tag.id)
                if !photos.isEmpty {
                    Section("รูป\(tag.title)") {
                        PhotoGrid(images: photos.map(\.data)).padding(.vertical, 8)
                    }
                }
            }
            if !survey.notes.isEmpty {
                Section("หมายเหตุ") { Text(survey.notes) }
            }
        }
        .navigationTitle("แบบสำรวจ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { SurveyFormView(survey: survey) } label: { Text("แก้ไข") }
            }
        }
    }
}
