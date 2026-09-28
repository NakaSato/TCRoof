#if canImport(UIKit)
import SwiftUI
import SurveyCore

/// One report's editor, for a host app to push from its own screens (e.g. a job's detail page).
public struct SurveyReportEditor: View {
    let jobID: UUID
    @State private var model = SurveyModel.shared
    public init(jobID: UUID) { self.jobID = jobID }
    public var body: some View {
        if let j = model.job(jobID) {
            JobEditorView(job: j).environment(model)
        } else {
            ContentUnavailableView("ไม่พบแบบสำรวจ", systemImage: "doc.questionmark", description: Text("อาจถูกลบจากเครื่องอื่นแล้ว"))
        }
    }
}

/// The "which kind of site" picker shown before a new report is created.
public struct SurveyTemplatePicker: View {
    let create: (JobTemplate) -> Void
    public init(create: @escaping (JobTemplate) -> Void) { self.create = create }
    public var body: some View { NewJobSheet(create: create) }
}
#endif
