import Foundation
import SwiftData
import FirebaseFirestore
import TCRoofCore

extension CloudSync {
    // MARK: pull

    /// The listeners take metadata changes too: when the cache already matches the server, the only event
    /// after the first (cached) snapshot is `isFromCache` turning false, and without it the state stays `.connecting`.
    /// `optional`: a refused listener (its rule not deployed yet) is logged and the rest still syncs.
    /// `owner`: only the documents of that person (`ownerEmail`), the one query the rules allow for the travel log.
    func listen<M: CloudSynced>(_ type: M.Type, optional: Bool = false, owner: String? = nil,
                                onServerSnapshot: ((Int?) -> Void)? = nil, onFirstSnapshot: (() -> Void)? = nil,
                                queryOverride: Query? = nil, barrier: StartupLoadBarrier? = nil) {
        guard queryOverride != nil || !listeningCollections.contains(M.collection) else { onServerSnapshot?(nil); onFirstSnapshot?(); return }
        listeningCollections.insert(M.collection)
        let session = snapshotSession
        let q = queryOverride ?? owner.map { db.collection(M.collection).whereField("ownerEmail", isEqualTo: $0) } ?? query(M.collection)
        let registration = q.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            guard MainActor.assumeIsolated({ self?.snapshotSession == session }) else { return }
            MainActor.assumeIsolated {
                guard let self, self.snapshotSession == session else { return }
                if let error {
                    self.enqueueStartupSnapshot(barrier, session: session, isFromCache: false) { [weak self] in
                        guard let self, self.snapshotIsCurrent(session) else { return }
                        onServerSnapshot?(nil)
                        onFirstSnapshot?()
                        if optional { print("CloudSync: \(M.collection) listener: \(error.localizedDescription)") }
                        else { self.failed(error) }
                    }
                    return
                }
                guard let snapshot else { onServerSnapshot?(nil); onFirstSnapshot?(); return }
                if M.self == Job.self, !snapshot.metadata.isFromCache, self.loadingCollections.contains(Job.collection) {
                    self.initialServerProjectIDs.formUnion(snapshot.documents.map(\.documentID))
                }
                let changes = snapshot.documentChanges
                // Metadata-only acknowledgements and errors must not overtake earlier data snapshots.
                self.enqueueStartupSnapshot(barrier, session: session, isFromCache: snapshot.metadata.isFromCache) { [weak self] in
                    guard let self else { return }
                    await self.receive(M.self, changes, session: session)
                    guard self.snapshotIsCurrent(session) else { return }
                    onFirstSnapshot?()
                    if !snapshot.metadata.isFromCache {
                        onServerSnapshot?(snapshot.documents.count)
                        if !optional { self.synced() }
                    }
                }
            }
        }
        listeners.append(registration)
    }

    /// Loads a collection when its feature is opened instead of during app startup.
    func listenOnDemand<M: CloudSynced>(_ type: M.Type, optional: Bool = false, owner: String? = nil) {
        guard context != nil, !listeningCollections.contains(M.collection) else { return }
        loadingCollections.insert(M.collection)
        listen(type, optional: optional, owner: owner, onFirstSnapshot: { [weak self] in
            self?.loadingCollections.remove(M.collection)
        })
    }

    func isLoading(_ collection: String) -> Bool { loadingCollections.contains(collection) }

    func loadScannedDevices() { listenOnDemand(ScannedDevice.self) }

    func loadSiteICLSheets() { listenOnDemand(ICLSheet.self, optional: true) }

    func loadTravelRecords() {
        guard external == nil else { return }
        let email = MemberRole.shared.permissions.email
        guard !email.isEmpty else { return }
        listenOnDemand(Trip.self, optional: true, owner: email)
        listenOnDemand(Expense.self, optional: true, owner: email)
        listenOnDemand(ClaimMonth.self, optional: true, owner: email)
    }

    func loadToolRecords() {
        guard external == nil else { return }
        listenOnDemand(ToolEvent.self, optional: true)
        listenOnDemand(CompanyVehicle.self, optional: true)
    }

    func receive<M: CloudSynced>(_ type: M.Type, _ documents: [DocumentChange], session: UUID) async {
        // Publish the first batch before decoding the rest of an initial collection snapshot.
        for start in stride(from: 0, to: documents.count, by: 16) {
            guard snapshotIsCurrent(session) else { return }
            await receiveBatch(type, Array(documents[start..<min(start + 16, documents.count)]), session: session)
            snapshotJobIndex = nil
            pendingModelIndexes.removeAll(keepingCapacity: true)
            guard await pauseSnapshotApplication(session) else { return }
        }
    }

    private func receiveBatch<M: CloudSynced>(_ type: M.Type, _ documents: [DocumentChange], session: UUID) async {
        guard snapshotIsCurrent(session), !documents.isEmpty else { return }
        let recordType = M.Record.self
        let prepared = try? await Self.snapshotWorker.prepare(documents) { change -> PreparedDocumentChange<M.Record>? in
            let id = change.document.documentID
            if change.type == .removed { return .removed(id: id) }
            guard let record = try? change.document.data(as: recordType) else { return nil }
            return .updated(id: id, record: record, fingerprint: Self.recordFingerprint(record))
        }
        guard snapshotIsCurrent(session), let changes = prepared, let context else { return }
        // A cache/server echo needs no SwiftData fetch or save, but recheck known at the actual apply below too.
        guard changes.contains(where: { change in
            switch change {
            case .removed: true
            case .updated(let id, _, let fingerprint): known["\(M.collection)/\(id)"] != fingerprint
            }
        }) else { return }
#if DEBUG
        let applyStartedAt = Date()
        var activeTime = 0.0
        var longestChunk = 0.0
        var chunks = 0
        defer {
            let elapsedMS = Int(Date().timeIntervalSince(applyStartedAt) * 1_000)
            print("CloudSync: applied \(changes.count) \(M.collection) changes in \(elapsedMS) ms; active \(Int(activeTime * 1000)) ms, max chunk \(Int(longestChunk * 1000)) ms, \(chunks) chunks")
        }
#endif
        var index = 0
        while index < changes.count {
            guard snapshotIsCurrent(session) else { return }
            let started = Date()
            // A local edit made while the worker ran or between chunks must keep its normal upload notification.
            saveUncommittedChanges()
            // UI edits can insert or delete models while we yield. Never retain an outdated model index across it.
            if index > 0 {
                snapshotJobIndex = nil
                pendingModelIndexes.removeAll(keepingCapacity: true)
            }
            let limit = min(index + 16, changes.count)
            let ids = changes[index..<limit].map(\.id)
            let local = Dictionary(((try? M.fetchForSync(in: context, ids: ids)) ?? []).compactMap { model in
                model.syncID.map { ($0, model) }
            }, uniquingKeysWith: { first, _ in first })
            // Projects have no parent project. Avoid a second full-table lookup for every project chunk.
            let jobs = M.self == Job.self ? [:] : jobIndexForSnapshotBatch()
#if DEBUG
            let lookupFinished = Date()
#endif
            applyingRemoteSnapshots = true
            repeat {
                let change = changes[index]
                let id = change.id
                let key = "\(M.collection)/\(id)"
                switch change {
                case .removed:
                    if let model = local[id] { context.delete(model) }
                    known[key] = nil
                    pending[key] = nil
                case .updated(_, let record, let fingerprint):
                    if known[key] != fingerprint,
                       !upsert(M.self, id: id, record: record, existing: local[id], jobs: jobs) {
                        pending[key] = { [weak self] in
                            guard let self else { return true }
                            let existing = self.model(M.self, syncID: id)
                            return self.upsert(M.self, id: id, record: record, existing: existing,
                                               jobs: self.jobIndexForSnapshotBatch())
                        }
                    }
                }
                index += 1
            } while index < limit && Date().timeIntervalSince(started) < 0.008
#if DEBUG
            let saveStarted = Date()
#endif
            saveSnapshotChanges()
#if DEBUG
            let duration = Date().timeIntervalSince(started)
            print("CloudSync: \(M.collection) lookup \(Int(lookupFinished.timeIntervalSince(started) * 1000)) ms, save \(Int(Date().timeIntervalSince(saveStarted) * 1000)) ms")
            activeTime += duration
            longestChunk = max(longestChunk, duration)
            chunks += 1
#endif
            if index < changes.count {
                guard await pauseSnapshotApplication(session) else { return }
            }
        }
        guard snapshotIsCurrent(session) else { return }
        if M.self == Job.self { snapshotJobIndex = nil }
        // records waiting for their job, and photos waiting for their log or inspection
        if !pending.isEmpty && (M.self == Job.self || M.self == InstallLog.self || M.self == Inspection.self || M.self == ICLSheet.self) {
            pendingModelIndexes.removeAll(keepingCapacity: true)
            schedulePendingRetries()
        }
    }

    /// Retry dependent records in bounded work items; a new parent arriving requests one more pass.
    private func schedulePendingRetries() {
        guard !pendingRetryScheduled else { pendingRetryAgain = true; return }
        let keys = Array(pending.keys)
        guard !keys.isEmpty else { return }
        pendingRetryScheduled = true
        pendingRetryAgain = false
        let session = snapshotSession
        for start in stride(from: 0, to: keys.count, by: 32) {
            let end = min(start + 32, keys.count)
            let chunk = Array(keys[start..<end])
            let last = end == keys.count
            enqueueSnapshotApplication { [weak self] in
                guard let self, self.snapshotSession == session else { return }
                self.applyingRemoteSnapshots = true
                defer { self.applyingRemoteSnapshots = false }
                for key in chunk where self.pending[key]?() == true { self.pending[key] = nil }
                self.saveSnapshotChanges()
                if last {
                    self.pendingRetryScheduled = false
                    if self.pendingRetryAgain { self.schedulePendingRetries() }
                }
            }
        }
    }

    private func model<M: CloudSynced>(_ type: M.Type, syncID: String) -> M? {
        let typeID = ObjectIdentifier(M.self)
        let models: [String: M]
        if let cached = pendingModelIndexes[typeID] as? [String: M] {
            models = cached
        } else {
            guard let context else { return nil }
            models = Dictionary(((try? context.fetch(FetchDescriptor<M>())) ?? []).compactMap { model in
                model.syncID.map { ($0, model) }
            }, uniquingKeysWith: { first, _ in first })
            pendingModelIndexes[typeID] = models
        }
        return models[syncID]
    }

    /// Applies a remote record; false when it belongs to a job this device hasn't received yet.
    private func upsert<M: CloudSynced>(_ type: M.Type, id: String, record: M.Record, existing: M?, jobs: [String: Job]) -> Bool {
        guard let context else { return true }
        let model: M
        if let existing {
            guard existing.apply(record, jobs: jobs) else { return false }
            model = existing
        } else {
            guard let made = M.make(record, jobs: jobs) else { return false }
            made.syncID = id
            context.insert(made)
            // a photo whose log or inspection hasn't arrived yet waits for it
            guard made.apply(record, jobs: jobs) else { context.delete(made); return false }
            model = made
        }
        let key = "\(M.collection)/\(id)"
        known[key] = recordFingerprintCache(M.self).fingerprint(id: key, record: model.record) { fingerprint($0) }
        return true
    }
}
