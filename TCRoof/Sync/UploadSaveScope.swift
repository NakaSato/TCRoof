import Foundation
import SwiftData

/// Saved identifiers identify the affected collections even after a local deletion removes the model itself.
@MainActor
enum UploadSaveScope {
    private static let collectionsByEntity: [String: Set<String>] = [
        // Children and NO.224 reports carry their project's external-reader list.
        Schema.entityName(for: Job.self): [Job.collection, SurveyForm.collection, ScannedDevice.collection,
            InstallLog.collection, Inspection.collection, ICLSheet.collection, PhotoAsset.collection,
            "jobContacts", "pwaSurveys"],
        Schema.entityName(for: SurveyForm.self): [SurveyForm.collection],
        Schema.entityName(for: ScannedDevice.self): [ScannedDevice.collection],
        Schema.entityName(for: InstallLog.self): [InstallLog.collection, PhotoAsset.collection],
        Schema.entityName(for: Inspection.self): [Inspection.collection, PhotoAsset.collection],
        Schema.entityName(for: ICLSheet.self): [ICLSheet.collection, PhotoAsset.collection],
        Schema.entityName(for: PhotoAsset.self): [PhotoAsset.collection],
        Schema.entityName(for: Trip.self): [Trip.collection],
        Schema.entityName(for: Expense.self): [Expense.collection],
        Schema.entityName(for: ClaimMonth.self): [ClaimMonth.collection],
        Schema.entityName(for: ToolEvent.self): [ToolEvent.collection],
        Schema.entityName(for: CompanyVehicle.self): [CompanyVehicle.collection],
        // Documents themselves travel through Drive; their job's changed Drive links produce a separate save.
        Schema.entityName(for: DocumentAsset.self): []
    ]

    static func collections(in notification: Notification) -> Set<String>? {
        guard let info = notification.userInfo else { return nil }
        func value(_ key: ModelContext.NotificationKey) -> Any? { info[key] ?? info[key.rawValue] }
        func identifiers(_ raw: Any) -> [PersistentIdentifier]? {
            if let ids = raw as? [PersistentIdentifier] { return ids }
            if let ids = raw as? Set<PersistentIdentifier> { return Array(ids) }
            return nil
        }
        if let invalidated = value(.invalidatedAllIdentifiers) {
            if let flag = invalidated as? Bool {
                if flag { return nil }
            } else if identifiers(invalidated)?.isEmpty != true { return nil }
        }
        var foundMetadata = false
        var collections = Set<String>()
        for key in [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers] {
            guard let raw = value(key) else { continue }
            guard let ids = identifiers(raw) else { return nil }
            foundMetadata = true
            for id in ids {
                guard let affected = collectionsByEntity[id.entityName] else { return nil }
                collections.formUnion(affected)
            }
        }
        return foundMetadata ? collections : nil
    }
}
