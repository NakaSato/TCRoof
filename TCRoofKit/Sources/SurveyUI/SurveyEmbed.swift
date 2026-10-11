#if canImport(UIKit)
import SwiftUI
import TCRoofCore
import TCRoofUI

/// One report's editor, for a host app to push from its own screens (e.g. a job's detail page).
public struct SurveyReportEditor: View {
    let jobID: UUID
    let start: MissingGroup.Target?
    @State private var model = SurveyModel.shared
    /// - Parameter start: page to open on (e.g. the job's `nextStep`); nil opens the editor's default page.
    public init(jobID: UUID, start: MissingGroup.Target? = nil) { self.jobID = jobID; self.start = start }
    public var body: some View {
        if let j = model.job(jobID) {
            JobEditorView(job: j, start: start).environment(model)
        } else {
            TCEmptyState("ไม่พบแบบสำรวจ", systemImage: "doc.questionmark", description: Text("อาจถูกลบจากเครื่องอื่นแล้ว"))
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
