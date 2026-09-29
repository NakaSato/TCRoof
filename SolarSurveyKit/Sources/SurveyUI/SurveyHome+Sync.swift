#if canImport(UIKit)
import SwiftUI
import SurveyCore
import DriveSync

extension SurveyHomeView {
    /// Sends pending jobs to the host's cloud. Without one, saves every job waiting for Drive with the files the
    /// export sheet was last set to, asking first when a PDF would go out unsigned or without photos still on another iPad.
    func syncAll() {
        // the host's cloud keeps the answers — just send them now
        if let push = model.cloudPush { return push() }
        let todo = model.jobsToSync
        guard !todo.isEmpty else { return }
        let choice = ExportSheet.driveChoice
        func name(_ j: Job) -> String { j.docNo.isEmpty ? j.projectName : "NO.\(j.docNo) \(j.projectName)" }
        var notes: [String] = []
        if choice.kinds.contains(.pdf) {
            let unsigned = todo.filter { !$0.missingSignatures.isEmpty }
            if !unsigned.isEmpty { notes.append("PDF ยังไม่มีลายเซ็น: " + unsigned.map(name).joined(separator: ", ")) }
        }
        if !choice.kinds.isEmpty {
            let gaps = todo.filter { !model.missingPhotos($0).isEmpty }
            if !gaps.isEmpty { notes.append("รูปจากเครื่องอื่นยังไม่อยู่ในเครื่องนี้ รายงานจะไม่มีรูปเหล่านี้: " + gaps.map(name).joined(separator: ", ")) }
        }
        if notes.isEmpty { runSync() } else { pendingSync = PendingSync(notes: notes) }
    }

    func runSync() {
        let choice = ExportSheet.driveChoice
        busy = "กำลังซิงก์…"
        Task {
            defer { busy = nil }
            do { if !model.google.isSignedIn { try await model.google.signIn() } }
            catch { self.error = error.localizedDescription; return }
            let total = model.jobsToSync.count
            let failed = await model.saveAllToDrive(kinds: choice.kinds, photos: choice.photos) { done, total, j in
                busy = "กำลังซิงก์ \(done + 1)/\(total)\n\(j.projectName)"
            }
            if failed.isEmpty { message = "ซิงก์ \(total) งานขึ้น Google Drive แล้ว" }
            else {
                error = "ซิงก์ไม่สำเร็จ \(failed.count) จาก \(total) งาน\n"
                    + failed.map { "• \($0.job.projectName): \($0.error.localizedDescription)" }.joined(separator: "\n")
            }
        }
    }
}
#endif
