import Foundation
import SwiftData
import TCRoofCore
import TCRoofUI

/// The team's records kept on this device. When an external account signs in after a different account, the previous
/// account's copy is removed before sync starts, so nobody sees jobs their role doesn't give them; sync then brings
/// back theirs. The next team member may read every job, so on a shared iPad the records stay for them.
@MainActor
enum LocalData {
    private static let transition = AccountDataTransition()

    /// Records `email` as the owner. After a different owner, an external account leaves the records to be removed
    /// at the next start; a team account takes them over with what sync knows of them.
    static func signedIn(_ email: String, role: UserRole) {
        let changed = transition.owner != email
        let carry = transition.signedIn(email, external: role == .external)
        if changed || transition.needsCleanup {
            UserDefaults.standard.set(carry, forKey: CloudSync.carryKnownKey)
        }
    }

    /// Removes the previous account's records, if a different account signed in. Runs before `CloudSync.start`.
    static func wipeIfNeeded(_ context: ModelContext, survey: SurveyModel) throws {
        let d = UserDefaults.standard
        try transition.cleanupIfNeeded {
            Task { await InstallSummaryCache.clearPersistentCache() }
            // Sync deletes in Firestore what it once knew and no longer finds here; forgetting what it knew first keeps
            // this removal on the device.
            for key in d.dictionaryRepresentation().keys where key.hasPrefix("cloudSync.known.") { d.removeObject(forKey: key) }
            // Delete through object graph to avoid SQLite batch delete constraint trigger violations
            deleteAll(Job.self, in: context)
            deleteAll(SurveyForm.self, in: context)
            deleteAll(ScannedDevice.self, in: context)
            deleteAll(InstallLog.self, in: context)
            deleteAll(Inspection.self, in: context)
            deleteAll(ICLSheet.self, in: context)
            deleteAll(PhotoAsset.self, in: context)
            deleteAll(DocumentAsset.self, in: context)
            deleteAll(Trip.self, in: context)
            deleteAll(Expense.self, in: context)
            deleteAll(ClaimMonth.self, in: context)
            deleteAll(ToolEvent.self, in: context)
            deleteAll(CompanyVehicle.self, in: context)
            try? context.save()
            try survey.removeLocalAccountData()
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            for folder in ["Permits", "StationDocs"] {
                let url = docs.appendingPathComponent(folder, isDirectory: true)
                do { try FileManager.default.removeItem(at: url) }
                catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError { }
            }
        }
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        do {
            let items = try context.fetch(FetchDescriptor<T>())
            for item in items { context.delete(item) }
        } catch {
            try? context.delete(model: type)
        }
    }
}
