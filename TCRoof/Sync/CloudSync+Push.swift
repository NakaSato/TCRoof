import Foundation
import SwiftData
import FirebaseFirestore
import os
import TCRoofCore
import TCRoofUI

extension CloudSync {
    // MARK: push

    func schedulePush(collections: Set<String>? = nil) {
        guard !applyingRemoteSnapshots else { return }
        uploadScans.mark(collections)
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.push(fullScan: false)
        }
    }

    func saveUncommittedChanges() {
        guard let context, context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("CloudSync: local save: \(error.localizedDescription)")
        }
    }

    struct Change {
        let key: String
        let write: (WriteBatch) throws -> Void
        let fingerprint: String?
    }

    /// Scheduled saves inspect affected collections. Startup, manual refresh and config changes recover with a full scan.
    func push(fullScan: Bool = true) {
        // an outdated build sends nothing (`config/app.minSyncVersion`); its edits wait here for the update
        guard let context, let survey, uid != nil, !AppGate.shared.outdated else { return }
        // A partial initial download must never be mistaken for local deletions during an upload scan.
        guard !loadingCollections.contains(Job.collection) else { return }
        guard survey.hasLoaded, !survey.isLoading, snapshotApplyTask == nil, pendingSnapshotWork.isEmpty else { schedulePush(); return }
        let interval = performance.beginInterval("Push")
        defer { performance.endInterval("Push", interval) }
        guard let plan = uploadScans.takePlan(fullScan: fullScan) else { return }
        var scanned = Set<String>()
        var changes: [Change] = []
        var present = Set<String>()
        // an external member changes only a job's IEC test (`iec.fill_submit`) and weekly requests (`weekly.request`), and only reads the ICL (`icl.checklist`)
        collect(Job.self, context, &changes, &present, external == nil ? .full : .iecOnly, plan: plan, scanned: &scanned)
        collect(SurveyForm.self, context, &changes, &present, plan: plan, scanned: &scanned)
        collect(ScannedDevice.self, context, &changes, &present, plan: plan, scanned: &scanned)
        collect(InstallLog.self, context, &changes, &present, plan: plan, scanned: &scanned)
        collect(Inspection.self, context, &changes, &present, external == nil ? .full : .readOnly, plan: plan, scanned: &scanned)
        // the site ICL: a contractor fills and sends their sheets (`icl.site_fill`); the rules refuse a sent or signed one.
        // Committed on its own, so a refusal (rules not deployed yet, a sheet signed meanwhile) never holds back the rest.
        var iclSheets: [Change] = []
        collect(ICLSheet.self, context, &iclSheets, &present, plan: plan, scanned: &scanned)
        var photos: [Change] = []
        collect(PhotoAsset.self, context, &photos, &present, plan: plan, scanned: &scanned)
        // the travel log goes in its own batches: a refusal (rules not deployed yet) mustn't hold back the jobs
        var travel: [Change] = []
        if external == nil {
            collect(Trip.self, context, &travel, &present, plan: plan, scanned: &scanned)
            collect(Expense.self, context, &travel, &present, plan: plan, scanned: &scanned)
            collect(ClaimMonth.self, context, &travel, &present, plan: plan, scanned: &scanned)
        }
        // the tool and vehicle log in its own batches too
        var tools: [Change] = []
        if external == nil {
            collect(ToolEvent.self, context, &tools, &present, plan: plan, scanned: &scanned)
            collect(CompanyVehicle.self, context, &tools, &present, plan: plan, scanned: &scanned)
        }
        var contacts = external == nil ? contactChanges(context, &present, plan: plan, scanned: &scanned) : []
        if plan.includes(Self.surveyCollection) {
            scanned.insert(Self.surveyCollection)
            for job in survey.jobs {
                let key = "\(Self.surveyCollection)/\(job.id.uuidString)"
                present.insert(key)
                guard let (record, fingerprint) = surveyRecord(job), known[key] != fingerprint else { continue }
                if let external, record.externals?.contains(external) != true { continue }
                let ref = db.document(key)
                changes.append(Change(key: key, write: { try $0.setData(from: record, forDocument: ref) }, fingerprint: fingerprint))
            }
            surveyRecords = surveyRecords.filter { present.contains("\(Self.surveyCollection)/\($0.key.uuidString)") }
        }
        var revisions: [Change] = []
        if external == nil, plan.includes(Self.revisionCollection) {
            revisions = revisionChanges(survey, &present)
            scanned.insert(Self.revisionCollection)
        }
        let deleted = plan.deletions(known: Set(known.keys), present: present, scanned: scanned)
        for key in deleted {
            // An incomplete local survey inventory must not delete cloud surveys or revisions.
            if (!survey.hasLoaded || survey.isLoading || !survey.loadFailures.isEmpty),
               key.hasPrefix("\(Self.surveyCollection)/") || key.hasPrefix("\(Self.revisionCollection)/") { continue }
            let ref = db.document(key)
            let change = Change(key: key, write: { $0.deleteDocument(ref) }, fingerprint: nil)
            if key.hasPrefix("\(PhotoAsset.collection)/") { photos.append(change) }
            else if key.hasPrefix("\(ICLSheet.collection)/") { iclSheets.append(change) }
            else if key.hasPrefix("\(Self.contactCollection)/") { contacts.append(change) }
            else if Self.travelCollections.contains(where: { key.hasPrefix("\($0)/") }) { travel.append(change) }
            else if Self.toolCollections.contains(where: { key.hasPrefix("\($0)/") }) { tools.append(change) }
            else { changes.append(change) }
        }
        if context.hasChanges { try? context.save() }   // syncIDs given to older records
#if DEBUG
        print("CloudSync: upload scan \(scanned.sorted().joined(separator: ", ")); \(deleted.count) deletions")
#endif
        defer { refreshSurveyPending() }
        commitSeparately(revisions, "REV upload")
        commitSeparately(contacts, "contact upload")
        commitSeparately(iclSheets, "site ICL upload", size: external == nil ? 400 : 1)
        commitSeparately(travel, "travel upload")
        commitSeparately(tools, "tool log upload")
        // Photos go after the records they belong to, so a new daily report reaches Firestore before its photos
        // (the rules check that an external member's photo points at their own report). An external member's go one
        // by one, so a refused photo doesn't hold back the rest.
        let photoBatch = external == nil ? 400 : 1
        guard !changes.isEmpty else { commitSeparately(photos, "photo upload", size: photoBatch); return }

        // Firestore takes at most 500 writes per batch. An external member's writes go one by one: the rules refuse
        // some (a record of a job just taken off them), and one refusal mustn't hold back the rest or stop the sync.
        let size = external == nil ? 400 : 1
        for start in stride(from: 0, to: changes.count, by: size) {
            let slice = changes[start..<min(start + size, changes.count)]
            let sent = Array(slice)
            let batch = db.batch()
            var previous: [String: String?] = [:]
            for change in slice {
                do { try change.write(batch) } catch {
                    uploadScans.retry(keys: [change.key])
                    failed(error)
                    continue
                }
                previous[change.key] = known[change.key]
                known[change.key] = change.fingerprint
                unconfirmed[change.key, default: 0] += 1
            }
            let session = snapshotSession
            batch.commit { [weak self] error in
                guard MainActor.assumeIsolated({ self?.snapshotSession == session }) else { return }
                MainActor.assumeIsolated {
                    guard let self, self.snapshotSession == session else { return }
                    // Firestore calls back once the server has the batch, or has refused it
                    for key in previous.keys {
                        let left = (self.unconfirmed[key] ?? 1) - 1
                        self.unconfirmed[key] = left > 0 ? left : nil
                    }
                    defer { self.refreshSurveyPending() }
                    if let error {
                        self.uploadScans.retry(keys: Set(previous.keys))
                        // Put back what the server still has so the next push tries again.
                        for (key, old) in previous { self.known[key] = old }
                        self.saveKnown()
                        let refused = (error as NSError).code == FirestoreErrorCode.permissionDenied.rawValue
                        if self.external != nil, refused {
                            print("CloudSync: refused \(previous.keys.joined(separator: ", ")): \(error.localizedDescription)")
                        } else if refused, sent.count > 1 {
                            // One write the rules refuse fails the whole batch, and every later push with it: a delete
                            // made here would never leave this device. Send the batch's writes one by one instead, so
                            // only the refused one waits (and is named in the log).
                            self.commitSeparately(sent, "refused write", size: 1)
                        } else {
                            self.failed(error)
                        }
                    } else {
                        self.synced()
                    }
                }
            }
        }
        commitSeparately(photos, "photo upload", size: photoBatch)
        saveKnown()
    }

    /// Issued REVs this device holds and Firestore doesn't yet. Every REV a job lists counts as present, so a REV
    /// still on its way here is never deleted; it goes only with its job.
    private func revisionChanges(_ survey: SurveyModel, _ present: inout Set<String>) -> [Change] {
        var out: [Change] = []
        for job in survey.jobs {
            for r in job.revisions ?? [] { present.insert(Self.revisionKey(job.id, r.rev)) }
            for doc in survey.revisionDocs(job) {
                let key = Self.revisionKey(job.id, doc.rev)
                let record = RevisionRecord(doc)
                guard known[key] != record.fingerprint else { continue }
                let ref = db.document(key)
                out.append(Change(key: key, write: { try $0.setData(from: record, forDocument: ref) }, fingerprint: record.fingerprint))
            }
        }
        return out
    }

    static func revisionKey(_ job: UUID, _ rev: String) -> String {
        "\(revisionCollection)/\(job.uuidString)_\(rev.replacingOccurrences(of: "/", with: "-"))"
    }

    /// Their own batches (REVs, photos): a refusal here (rules not deployed yet) must not hold back the jobs. Tried
    /// again on the next push.
    func commitSeparately(_ changes: [Change], _ label: String, size: Int = 400) {
        let session = snapshotSession
        for start in stride(from: 0, to: changes.count, by: size) {
            let batch = db.batch()
            var previous: [String: String?] = [:]
            for change in changes[start..<min(start + size, changes.count)] {
                guard (try? change.write(batch)) != nil else {
                    uploadScans.retry(keys: [change.key])
                    continue
                }
                previous[change.key] = known[change.key]
                known[change.key] = change.fingerprint
            }
            batch.commit { [weak self] error in
                guard MainActor.assumeIsolated({ self?.snapshotSession == session }) else { return }
                MainActor.assumeIsolated {
                    guard let self, self.snapshotSession == session, let error else { return }
                    self.uploadScans.retry(keys: Set(previous.keys))
                    for (key, old) in previous { self.known[key] = old }
                    self.saveKnown()
                    print("CloudSync: \(label) refused \(previous.keys.sorted().joined(separator: ", ")): \(error.localizedDescription)")
                }
            }
        }
    }

    /// What a push may send of a collection: everything, nothing (still kept, never deleted), or a job's IEC test.
    enum Upload { case full, readOnly, iecOnly }
    // iecOnly: a job's IEC test, and the weekly requests and WBS ticks its contractor changed

    private func collect<M: CloudSynced>(_ type: M.Type, _ context: ModelContext, _ changes: inout [Change], _ present: inout Set<String>,
                                         _ upload: Upload = .full, plan: UploadScanState.Plan, scanned: inout Set<String>) {
        guard plan.includes(M.collection) else { return }
        guard let models = try? context.fetch(FetchDescriptor<M>()) else {
            uploadScans.mark([M.collection])
            return
        }
        scanned.insert(M.collection)
        let interval = performance.beginInterval("Collect", id: performance.makeSignpostID(), "\(M.collection, privacy: .public)")
        defer { performance.endInterval("Collect", interval) }
        let cache = recordFingerprintCache(M.self)
        let me = MemberRole.shared.permissions.email
        for model in models {
            if model.syncID == nil { model.syncID = UUID().uuidString }
            guard let syncID = model.syncID, model.syncs else { continue }
            let key = "\(M.collection)/\(syncID)"
            present.insert(key)
            guard upload != .readOnly else { continue }
            // someone else's travel log left on a shared iPad: theirs to send, and the rules would refuse it
            if let owned = model as? OwnedRecord, Permissions.normalized(owned.ownerEmail) != me { continue }
            // an external member's record outside their jobs stays on the device: the rules would refuse it
            if let external, model.ownerJob?.externals.contains(external) != true { continue }
            let record = model.record
            let print = cache.fingerprint(id: key, record: record) { fingerprint($0) }
            guard known[key] != print else { continue }
            let ref = db.document(key)
            if upload == .iecOnly {
                guard let job = model as? Job else { continue }
                var fields: [String: Any] = ["iecReport": job.iecReportJSON ?? NSNull(),
                                             "iecState": job.iecReport?.lockState.rawValue ?? NSNull()]
                // the weekly requests the contractor changed (`weekly.request`), signed with their email for the rules
                if job.weeklyRequestsUnsent, let external {
                    fields["weeklyRequests"] = job.weeklyRequestsJSON ?? NSNull()
                    fields["weeklyRequestsBy"] = external
                }
                // the WBS rows the contractor ticked or took back, signed the same way
                if job.wbsTicksUnsent, let external {
                    fields["wbsTicks"] = job.wbsTicksJSON ?? "{}"
                    fields["wbsTicksBy"] = external
                }
                changes.append(Change(key: key, write: { [fields] in $0.setData(fields, forDocument: ref, merge: true) },
                                      fingerprint: print))
            } else {
                changes.append(Change(key: key, write: { try $0.setData(from: record, forDocument: ref) }, fingerprint: print))
            }
        }
        cache.retainIDs(Set(models.compactMap { $0.syncID.map { "\(M.collection)/\($0)" } }))
    }

    /// Each job's phone and address in `jobContacts`, written by the team whether or not the job's own document still
    /// carries them, so they are all there when `contactsSplit` is switched on.
    private func contactChanges(_ context: ModelContext, _ present: inout Set<String>,
                                plan: UploadScanState.Plan, scanned: inout Set<String>) -> [Change] {
        guard plan.includes(Self.contactCollection) else { return [] }
        guard let jobs = try? context.fetch(FetchDescriptor<Job>()) else {
            uploadScans.mark([Self.contactCollection])
            return []
        }
        scanned.insert(Self.contactCollection)
        var out: [Change] = []
        for job in jobs {
            guard let id = job.syncID else { continue }
            let key = "\(Self.contactCollection)/\(id)"
            present.insert(key)
            let record = JobContactRecord(job)
            let print = fingerprint(record)
            guard known[key] != print else { continue }
            let ref = db.document(key)
            out.append(Change(key: key, write: { try $0.setData(from: record, forDocument: ref) }, fingerprint: print))
        }
        return out
    }
}
