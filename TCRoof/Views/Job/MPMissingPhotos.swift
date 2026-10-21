import SwiftUI
import TCRoofUI
import TCRoofCore

/// A construction task about to be booked at 100 % and the install photos (`9 ภาพถ่ายติดตั้งระบบ`) it still lacks
/// (`IECReport.missingPhotoLabels`). Site work is never blocked: the warning only asks before saving.
struct MPMissingPhotos: Identifiable, Equatable {
    let task: MasterSchedule.Task
    let labels: [String]
    var id: String { task.rawValue }

    /// The tasks of `tasks` that need photos the job doesn't have yet.
    static func list(_ tasks: [MasterSchedule.Task], job: Job) -> [MPMissingPhotos] {
        let report = job.iecReport
        return tasks.compactMap { t in
            let labels = IECReport.missingPhotoLabels(report, for: t)
            return labels.isEmpty ? nil : MPMissingPhotos(task: t, labels: labels)
        }
    }

    /// The alert's text: each task and its missing photos, a few per task.
    static func message(_ list: [MPMissingPhotos]) -> String {
        let lines = list.map { m -> String in
            let shown = m.labels.prefix(4).map { "• " + $0 }
            let more = m.labels.count > 4 ? ["• และอีก \(m.labels.count - 4) รูป"] : []
            return ([m.task.code + " " + m.task.title] + shown + more).joined(separator: "\n")
        }
        return (lines + ["ถ่ายได้ที่ ทดสอบ IEC 62446 › ภาพถ่ายติดตั้งระบบ"]).joined(separator: "\n\n")
    }
}

extension View {
    /// Asks before a booking that brings these tasks to 100 % without their install photos: `บันทึกทั้งที่ยังไม่มีรูป`
    /// runs `onSave`, `กลับไปแก้` leaves everything as it was.
    func mpMissingPhotos(_ list: Binding<[MPMissingPhotos]>, onSave: @escaping () -> Void) -> some View {
        alert("ยังไม่มีรูปติดตั้งของงานนี้",
              isPresented: Binding(get: { !list.wrappedValue.isEmpty }, set: { if !$0 { list.wrappedValue = [] } })) {
            Button("บันทึกทั้งที่ยังไม่มีรูป") { list.wrappedValue = []; onSave() }
            Button("กลับไปแก้", role: .cancel) { list.wrappedValue = [] }
        } message: {
            Text(MPMissingPhotos.message(list.wrappedValue))
        }
    }
}

/// `100% จากเอกสารอนุมัติ | 4/2/69`: a permit task the station's papers booked (`MasterSchedule.Actual.fromDocuments`).
struct MPDocumentsMark: View {
    let day: Date

    var body: some View {
        Label("100% จากเอกสารอนุมัติ | " + ThaiFormat.numericDate.string(from: day), systemImage: "checkmark.seal")
            .font(.sarabun(12, relativeTo: .caption))
            .foregroundStyle(Theme.inkMuted)
            .accessibilityIdentifier("mpDocumentsMark")
    }
}
