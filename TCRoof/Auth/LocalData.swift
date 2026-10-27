import Foundation
import SwiftData
import TCRoofCore
import TCRoofUI

/// The team's records kept on this device. When an external account signs in after a different account, the previous
/// account's copy is removed before sync starts, so nobody sees jobs their role doesn't give them; sync then brings
/// back theirs. The next team member may read every job, so on a shared iPad the records stay for them.
@MainActor
enum LocalData {
    private static let ownerKey = "session.owner"
    private static let wipeKey = "session.wipePending"

    /// The account the records on this device belong to.
    static var owner: String? { UserDefaults.standard.string(forKey: ownerKey) }

    /// Records `email` as the owner. After a different owner, an external account leaves the records to be removed
    /// at the next start; a team account takes them over with what sync knows of them.
    static func signedIn(_ email: String, role: UserRole) {
        let d = UserDefaults.standard
        if let owner, owner != email {
            let external = role == .external
            d.set(external, forKey: wipeKey)
            d.set(!external, forKey: CloudSync.carryKnownKey)
        }
        d.set(email, forKey: ownerKey)
    }

    /// Accounts signed in before the owner was kept own what is here.
    static func adopt(_ email: String) {
        if owner == nil { UserDefaults.standard.set(email, forKey: ownerKey) }
    }

    /// Removes the previous account's records, if a different account signed in. Runs before `CloudSync.start`.
    static func wipeIfNeeded(_ context: ModelContext, survey: SurveyModel) {
        let d = UserDefaults.standard
        guard d.bool(forKey: wipeKey) else { return }
        // Sync deletes in Firestore what it once knew and no longer finds here; forgetting what it knew first keeps
        // this removal on the device.
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("cloudSync.known.") { d.removeObject(forKey: key) }
        try? context.delete(model: InstallLog.self)
        try? context.delete(model: Inspection.self)
        try? context.delete(model: ICLSheet.self)
        try? context.delete(model: ScannedDevice.self)
        try? context.delete(model: SurveyForm.self)
        try? context.delete(model: PhotoAsset.self)
        try? context.delete(model: DocumentAsset.self)
        try? context.delete(model: Job.self)
        try? context.delete(model: Trip.self)
        try? context.delete(model: Expense.self)
        try? context.delete(model: ClaimMonth.self)
        try? context.delete(model: ToolEvent.self)
        try? context.delete(model: CompanyVehicle.self)
        try? context.save()
        for job in survey.jobs { survey.delete(job.id) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for folder in ["Permits", "StationDocs"] {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(folder, isDirectory: true))
        }
        // the assistant's conversations name stations and their numbers
        Assistant.History.device.removeAll()
        d.removeObject(forKey: wipeKey)
    }
}
