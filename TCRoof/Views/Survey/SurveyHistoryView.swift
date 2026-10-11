import SwiftUI
import TCRoofUI
import SwiftData
import CoreLocation
import TCRoofCore

// MARK: - History & detail

struct SurveyHistoryView: View {
    @Query(filter: #Predicate<SurveyForm> { !$0.isDraft }, sort: \SurveyForm.createdAt, order: .reverse)
    private var surveys: [SurveyForm]

    var body: some View {
        PadForm {
            if surveys.isEmpty {
                TCEmptyState("ยังไม่มีประวัติการสำรวจ", systemImage: "list.clipboard")
            }
            PadSection {
                ForEach(surveys) { survey in
                    PadLink { SurveyDetailView(survey: survey) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(survey.job?.code ?? "-") · \(survey.job?.projectName ?? "")").bold()
                            Text("\(survey.createdAt.thaiLongTime) · โดย \(survey.surveyor)")
                                .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                            Text("\(survey.roofType) · \(survey.roofAreaSqm.plain) ตร.ม. · เสนอ \(survey.recommendedKW.kw)")
                                .font(.sarabun(15, relativeTo: .subheadline))
                        }
                        .foregroundStyle(Theme.navy)
                    }
                }
            }
        }
        .navigationTitle("ประวัติการสำรวจ")
        .tcPadNavBar("ประวัติการสำรวจ", trail: ["หน้าหลัก", "สำรวจหน้างาน"])
    }
}

struct SurveyDetailView: View {
    let survey: SurveyForm

    private func orDash(_ s: String) -> String { s.isEmpty ? "-" : s }

    var body: some View {
        PadForm {
            PadSection {
                InfoRow(title: "โครงการ", value: survey.job?.projectName ?? "-")
                InfoRow(title: "วันที่สำรวจ", value: survey.createdAt.thaiLongTime)
                InfoRow(title: "ผู้สำรวจ", value: survey.surveyor)
                if let lat = survey.latitude, let lon = survey.longitude {
                    InfoRow(title: "พิกัด", value: String(format: "%.6f, %.6f", lat, lon))
                }
            }
            PadSection("หลังคา") {
                InfoRow(title: "ประเภท", value: orDash(survey.roofType))
                InfoRow(title: "พื้นที่", value: "\(survey.roofAreaSqm.plain) ตร.ม.")
                InfoRow(title: "ทิศทาง / ลาดชัน", value: "\(orDash(survey.orientation)) / \(survey.tiltDegree)°")
                InfoRow(title: "เงาบัง", value: orDash(survey.shading))
                InfoRow(title: "โครงสร้าง", value: survey.structureOK ? "รับน้ำหนักได้" : "ต้องเสริมโครงสร้าง")
            }
            PadSection("ระบบไฟฟ้า") {
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
                    PadSection("รูป\(tag.title)") {
                        PhotoGrid(images: photos.map(\.data)).padding(.vertical, 8)
                    }
                }
            }
            if !survey.notes.isEmpty {
                PadSection("หมายเหตุ") { Text(survey.notes) }
            }
        }
        .navigationTitle("แบบสำรวจ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { SurveyFormView(survey: survey) } label: { Text("แก้ไข") }
            }
        }
        .tcPadNavBar("แบบสำรวจ", trail: ["หน้าหลัก", "ประวัติการสำรวจ"], current: survey.job?.code ?? "แบบสำรวจ") {
            TopBarLink(title: "แก้ไข", systemImage: "pencil") { SurveyFormView(survey: survey) }
        }
    }
}
