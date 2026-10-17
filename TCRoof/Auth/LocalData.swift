import Foundation
import SwiftData
import TCRoofUI

/// The team's records kept on this device. When a different account signs in, the previous account's copy is
/// removed before sync starts, so nobody sees jobs their role doesn't give them; sync then brings back theirs.
@MainActor
enum LocalData {
    private static let ownerKey = "session.owner"
    private static let wipeKey = "session.wipePending"

    /// The account the records on this device belong to.
    static var owner: String? { UserDefaults.standard.string(forKey: ownerKey) }

    /// Records `email` as the owner; a different previous owner leaves the records to be removed at the next start.
    static func signedIn(_ email: String) {
        let d = UserDefaults.standard
        if let owner, owner != email { d.set(true, forKey: wipeKey) }
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
        try? context.delete(model: ScannedDevice.self)
        try? context.delete(model: SurveyForm.self)
        try? context.delete(model: PhotoAsset.self)
        try? context.delete(model: DocumentAsset.self)
        try? context.delete(model: Job.self)
        try? context.save()
        for job in survey.jobs { survey.delete(job.id) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for folder in ["Permits", "StationDocs"] {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(folder, isDirectory: true))
        }
        d.removeObject(forKey: wipeKey)
    }
}
