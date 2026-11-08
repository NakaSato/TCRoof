import Foundation
import Observation
import SwiftData
import TCRoofCore

/// The SwiftData store, one for the process: the scene's, and `DriveBackgroundWork`'s when iOS launches the app for it.
/// A store that won't open (a model change SwiftData can't migrate on its own, a damaged file) is reported here instead
/// of stopping the app at every launch: `StoreRecoveryView` offers to try again, or to set it aside and start empty.
@MainActor
@Observable
final class AppStore {
    static let shared = AppStore()

    static let schema = Schema([
        Job.self, SurveyForm.self, ScannedDevice.self, InstallLog.self,
        Inspection.self, ICLSheet.self, PhotoAsset.self, DocumentAsset.self,
        Trip.self, Expense.self, ClaimMonth.self,
        ToolEvent.self, CompanyVehicle.self,
    ])

    private(set) var container: ModelContainer?
    /// Why the store didn't open, for the recovery screen's details.
    private(set) var failure: String?

    private init() { open() }

    func open() {
        do {
            #if DEBUG
            // `-storeFailure YES` shows `StoreRecoveryView` without damaging the store; `ลองเปิดอีกครั้ง` then opens it
            if container == nil, failure == nil, UserDefaults.standard.bool(forKey: "storeFailure") {
                throw CocoaError(.fileReadCorruptFile)
            }
            #endif
            container = try ModelContainer(for: Self.schema)
            failure = nil
        } catch {
            container = nil
            failure = String(describing: error)
            CrashReporting.storeFailed(error)
        }
    }

    /// Where `startFresh` keeps the stores it set aside.
    static var backups: URL {
        URL.applicationSupportDirectory.appendingPathComponent("StoreBackups", isDirectory: true)
    }

    /// Moves the store's files into `backups` (`StoreBackup`) and opens an empty one. Sync then downloads the records
    /// again; what hadn't synced is only in the copy set aside.
    func startFresh() throws {
        let store = ModelConfiguration(schema: Self.schema).url
        // Sync deletes in Firestore what it once knew and no longer finds here: forgetting what it knew first keeps
        // the empty store from removing every record on the server (as `LocalData`'s removal does).
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("cloudSync.known.") {
            defaults.removeObject(forKey: key)
        }
        Task { await InstallSummaryCache.clearPersistentCache() }
        try StoreBackup.moveAside(store, into: Self.backups)
        open()
    }
}
