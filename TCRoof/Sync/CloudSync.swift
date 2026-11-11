import Foundation
import os
import Observation
import SwiftData
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import Network
import os
import TCRoofCore
import TCRoofUI

/// Keeps every device's jobs, surveys, device scans, install logs, ICLs and NO.224 survey reports in step
/// through Firestore. SwiftData and the survey module's files stay the working copy, so the app works offline.
///
/// `known` holds, per document, a fingerprint of the version both sides last agreed on. A local record whose
/// fingerprint differs is pushed; a known document missing locally was deleted here and is deleted remotely;
/// a remote change is applied unless it matches `known` (our own write coming back).
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    @ObservationIgnored let performance = OSSignposter(subsystem: "com.tcroof.internal", category: "CloudSync")

    enum State: Equatable {
        case off, connecting, synced
        case failed(String)
    }

    var state = State.off
    var lastSync: Date?
    /// The last pull to refresh found no network or couldn't reach the server; the feed says it shows what's here.
    var refreshFailed = false
    /// Pulls to refresh so far: the feed rebuilds after each, at the time it ends.
    var refreshes = 0
    var loadingCollections = Set<String>()

    @ObservationIgnored var context: ModelContext?
    @ObservationIgnored var survey: SurveyModel?
    @ObservationIgnored var uid: String?
    @ObservationIgnored var listeners: [ListenerRegistration] = []
    @ObservationIgnored var listeningCollections = Set<String>()
    @ObservationIgnored var connectTask: Task<Void, Never>?
    @ObservationIgnored var startupBarrier: StartupLoadBarrier?
    @ObservationIgnored var initialServerProjectIDs = Set<String>()
    @ObservationIgnored var observers: [NSObjectProtocol] = []
    @ObservationIgnored var timer: Timer?
    @ObservationIgnored var recordFingerprintCaches: [ObjectIdentifier: Any] = [:]
    @ObservationIgnored var surveyRecords: [UUID: (job: TCRoofCore.Job, externals: [String]?, record: SurveyRecord, fingerprint: String)] = [:]
    @ObservationIgnored var pushTask: Task<Void, Never>?
    @ObservationIgnored var uploadScans = UploadScanState()
    /// Preserve listener order while preparing remote values off-main, then commit bounded main-actor chunks.
    /// Relationship lookups are shared across each queued burst.
    @ObservationIgnored var pendingSnapshotWork: [@MainActor () async -> Void] = []
    @ObservationIgnored var snapshotApplyTask: Task<Void, Never>?
    /// Invalidates callbacks already queued by Firestore when a session stops or restarts.
    @ObservationIgnored var snapshotSession = UUID()
    static let snapshotWorker = SnapshotPreparationWorker()
    @ObservationIgnored var snapshotJobIndex: [String: Job]?
    @ObservationIgnored var applyingRemoteSnapshots = false
    @ObservationIgnored var remoteSavePushSuppressions = Set<ObjectIdentifier>()
    @ObservationIgnored var pendingModelIndexes: [ObjectIdentifier: Any] = [:]
    @ObservationIgnored var known: [String: String] = [:]
    /// The record behind each `known` fingerprint, while the app runs: what the server last had, so a local edit not
    /// pushed yet can be merged with another device's change instead of being overwritten (`mergeUnpushed`).
    @ObservationIgnored var syncedRecords: [String: any Sendable] = [:]
    /// Writes per document not yet confirmed by the server (offline, or still uploading).
    @ObservationIgnored var unconfirmed: [String: Int] = [:]
    /// Child records waiting for their job to arrive, keyed like `known`.
    @ObservationIgnored var pending: [String: () -> Bool] = [:]
    @ObservationIgnored var pendingRetryScheduled = false
    @ObservationIgnored var pendingRetryAgain = false
    /// The signed-in email when the member is external (roles): the listeners then ask only for the documents that
    /// list it in `externals`, which is all firestore.rules lets them read, and the push sends only what they may change.
    @ObservationIgnored var external: String?

    static let surveyCollection = "pwaSurveys"
    /// One document per issued REV of a survey report, written once.
    static let revisionCollection = "pwaSurveyRevisions"
    /// One document per feed post: the emails of the members who acknowledged it (`รับทราบ`).
    static let ackCollection = "feedAcks"
    /// One document per job: the customer's phone and address, for the team only (`JobContactRecord`).
    static let contactCollection = "jobContacts"
    /// Each person's travel log (`Trip`, `Expense`, `ClaimMonth`).
    static let travelCollections = [Trip.collection, Expense.collection, ClaimMonth.collection]
    static let toolCollections = [ToolEvent.collection, CompanyVehicle.collection]
    /// `config/app`: the team's settings set in the Firebase console (the center Drive, the claim share list), read by
    /// the team only (CHA-59).
    static let configDocument = "config/app"
    /// `config/public`: what every member's device needs, contractors' too: `minSyncVersion`, `installLink`,
    /// `contactsSplit` and `driveShareWith`. Read before `config/app`'s copy of the same fields.
    static let publicConfigDocument = "config/public"
    /// The two config documents as last read, combined by `applyConfig`.
    @ObservationIgnored var configApp: [String: Any]?
    @ObservationIgnored var configPublic: [String: Any]?
    static let contactsSplitKey = "cloudSync.contactsSplit"
    var db: Firestore { Firestore.firestore() }

    /// Pacing delay between sequential collection loads from Firebase to prevent network spikes and UI stutters.
    static let sequenceLoadDelay: Duration = .milliseconds(60)

    private func delaySequenceLoad() async throws {
        try await Task.sleep(for: Self.sequenceLoadDelay)
    }

    /// Disposable Firestore copies are bounded separately from the app's durable projects and files.
    /// Configure before the first Firestore call (including account membership checks).
    private static var cacheConfigured = false
    static func configureCache() {
        guard !cacheConfigured else { return }
        cacheConfigured = true
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: 100 * 1024 * 1024))
        Firestore.firestore().settings = settings
    }

    // MARK: lifecycle

    func start(context: ModelContext, survey: SurveyModel) {
        guard self.context == nil else { return }
        Self.configureCache()
        self.context = context
        self.survey = survey
        startupBarrier?.cancel(); startupBarrier = nil
        initialServerProjectIDs.removeAll()
        loadingCollections = []
        Job.contactsSplit = UserDefaults.standard.bool(forKey: Self.contactsSplitKey)
        // the survey home shows what Firestore still lacks, even before sign-in finishes
        if let u = Auth.auth().currentUser?.uid {
            Self.carryKnown(to: u)
            known = UserDefaults.standard.dictionary(forKey: "cloudSync.known.\(u)") as? [String: String] ?? [:]
            syncedRecords = [:]
        }
        survey.cloudPush = { [weak self] in
            guard let self else { return }
            if case .failed = self.state { self.retry() } else { self.push() }
        }
        refreshSurveyPending()
        connectTask = Task { await connect() }
    }

    func stop() {
        snapshotSession = UUID()
        survey?.invalidateStorageSession()
        recordFingerprintCaches.removeAll()
        connectTask?.cancel(); connectTask = nil
        startupBarrier?.cancel(); startupBarrier = nil
        listeners.forEach { $0.remove() }
        listeners = []
        listeningCollections = []
        initialServerProjectIDs.removeAll()
        loadingCollections = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        timer?.invalidate(); timer = nil
        pushTask?.cancel(); pushTask = nil
        uploadScans = UploadScanState()
        survey?.onChange = nil
        survey?.cloudPush = nil
        survey?.cloudPending = nil
        FeedAcks.shared.send = nil
        DesignLibrary.shared.onChange = nil
        DesignLibrary.shared.onRoofChange = nil
        TankStandard.Store.shared.onChange = nil
        CrewSupply.Store.shared.onChange = nil
        TeamDirectory.shared.clear()
        PhotoSync.shared.stop()
        pending = [:]
        pendingRetryScheduled = false
        pendingRetryAgain = false
        unconfirmed = [:]
        syncedRecords = [:]
        snapshotApplyTask?.cancel(); snapshotApplyTask = nil
        pendingSnapshotWork = []
        snapshotJobIndex = nil
        applyingRemoteSnapshots = false
        remoteSavePushSuppressions = []
        pendingModelIndexes = [:]
        external = nil
        context = nil; survey = nil; uid = nil
        try? Auth.auth().signOut()
        state = .off
    }

    func retry() {
        guard let context, let survey else { return }
        stop()
        start(context: context, survey: survey)
    }

    private func connect() async {
        if let survey {
            if !survey.isLoading { survey.reload() }
            await survey.waitForReload()
            guard survey.hasLoaded, !Task.isCancelled, context != nil else { return }
        }
        state = .connecting
        do {
            let user = try await firebaseUser()
            guard context != nil, !Task.isCancelled else { return }
            uid = user.uid
            // the role decides what the listeners may ask for; offline it is the one last read
            await MemberRole.shared.refresh()
            guard context != nil, !Task.isCancelled else { return }
            let me = MemberRole.shared.permissions
            external = me.role == .external && !me.email.isEmpty ? me.email : nil
            known = UserDefaults.standard.dictionary(forKey: knownKey) as? [String: String] ?? [:]
            syncedRecords = [:]
            let coldStart = SyncLog.signposts.beginInterval("sync start")
            defer { SyncLog.signposts.endInterval("sync start", coldStart) }
            // Start each collection sequentially with pacing delays to prevent request bursts.
            guard try await loadProjectsInBatches() else { return }
            try await delaySequenceLoad()
            guard await listenInitial(SurveyForm.self) else { return }
            try await delaySequenceLoad()
            guard await listenInitial(InstallLog.self) else { return }
            try await delaySequenceLoad()
            guard await listenInitial(Inspection.self) else { return }
            try await delaySequenceLoad()
            guard await listenInitial(PhotoAsset.self, optional: true) else { return }
            try await delaySequenceLoad()
            // Secondary collections also wait for their initial application with sequential delays.
            if external == nil, !me.email.isEmpty {
                guard await waitForStartup("claim reviews", register: { listenClaimReviews(owner: me.email, barrier: $0) }) else { return }
                try await delaySequenceLoad()
            }
            guard await listenSurveysInitial() else { return }
            try await delaySequenceLoad()
            if external == nil {
                guard await waitForStartup("survey revisions", register: { listenRevisions(barrier: $0) }) else { return }
                try await delaySequenceLoad()
            }
            guard await waitForStartup("feed acknowledgements", register: { listenFeedAcks(barrier: $0) }) else { return }
            try await delaySequenceLoad()
            guard await waitForStartup("designs", register: { listenDesigns(barrier: $0) }) else { return }
            try await delaySequenceLoad()
            guard await waitForStartup("design sheets", register: { listenDesignSheets(barrier: $0) }) else { return }
            try await delaySequenceLoad()
            guard await waitForStartup("tank standard", register: { listenTankStandard(barrier: $0) }) else { return }
            try await delaySequenceLoad()
            if external == nil {
                guard await waitForStartup("contacts", register: { listenContacts(barrier: $0) }) else { return }
                try await delaySequenceLoad()
                guard await waitForStartup("directory", register: { listenDirectory(barrier: $0) }) else { return }
                try await delaySequenceLoad()
                guard await waitForStartup("monitoring settings", register: { listenMonitoringSettings(barrier: $0) }) else { return }
                try await delaySequenceLoad()
                guard await waitForStartup("crew supply", register: { listenCrewSupply(barrier: $0) }) else { return }
                try await delaySequenceLoad()
                guard await waitForStartup("risk register", register: { listenRiskRegister(barrier: $0) }) else { return }
                try await delaySequenceLoad()
                guard await waitForStartup("stakeholders", register: { listenStakeholders(barrier: $0) }) else { return }
            }
            guard await waitForStartup("configuration", register: { listenConfig(barrier: $0) }) else { return }
            observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    if let self {
                        if let context = notification.object as? ModelContext {
                            if self.remoteSavePushSuppressions.remove(ObjectIdentifier(context)) == nil {
                                self.schedulePush(collections: UploadSaveScope.collections(in: notification))
                            }
                        } else if !self.applyingRemoteSnapshots {
                            self.schedulePush()
                        }
                    }
                    // photos taken here go up to Drive, photos received download
                    PhotoSync.shared.schedule()
                }
            })
            if let context, let survey { PhotoSync.shared.start(context: context, survey: survey) }
            survey?.onChange = { [weak self] in
                self?.schedulePush(collections: [Self.surveyCollection, Self.revisionCollection])
            }
            // Persist edits that haven't autosaved yet. The save notification schedules a push, avoiding a full
            // collection scan on every timer tick when the device is idle.
            timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveUncommittedChanges() }
            }
            push()
        } catch {
            guard !Task.isCancelled else { return }
            failed(error)
        }
    }

    /// Firebase account of the Google account signed in to the app.
    private func firebaseUser() async throws -> User {
        guard let google = survey?.google else { throw CancellationError() }
        return try await GoogleSession.firebaseUser(google)
    }

    func waitForStartup(_ label: String, register: (StartupLoadBarrier) -> Void) async -> Bool {
        let session = snapshotSession
        guard snapshotIsCurrent(session) else { return false }
        let barrier = StartupLoadBarrier()
        startupBarrier = barrier
        let started = Date()
        let signpost = SyncLog.signposts.beginInterval("sync stage", id: SyncLog.signposts.makeSignpostID(), "\(label, privacy: .public)")
        defer { SyncLog.signposts.endInterval("sync stage", signpost) }
        CrashReporting.startupStage(label, state: "begin")
#if DEBUG
        SyncLog.sync.debug("startup begin \(label, privacy: .public)")
#endif
        register(barrier)
        let timeout = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            // A slow mobile response is not an offline launch. Give the server time before using local data.
            if await Self.isOnline() {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            barrier.allowOfflineFallback()
        }
        let result = await barrier.wait()
        timeout.cancel()
        if startupBarrier === barrier { startupBarrier = nil }
        CrashReporting.startupStage(label, state: String(describing: result),
                                    elapsedMilliseconds: Int(Date().timeIntervalSince(started) * 1000))
#if DEBUG
        SyncLog.sync.debug("startup end \(label, privacy: .public): \(String(describing: result), privacy: .public), \(Int(Date().timeIntervalSince(started) * 1000)) ms")
#endif
        guard result != .cancelled, snapshotIsCurrent(session) else { return false }
        return await pauseSnapshotApplication(session)
    }

    func enqueueStartupSnapshot(_ barrier: StartupLoadBarrier?, session: UUID, isFromCache: Bool,
                                apply: @escaping @MainActor () async -> Void) {
        guard snapshotIsCurrent(session) else { return }
        barrier?.received()
        enqueueSnapshotApplication { [weak self] in
            guard let self, self.snapshotIsCurrent(session) else { return }
            await apply()
            barrier?.applied(isFromCache: isFromCache)
        }
    }

    func listenStartupQuery(_ query: Query, barrier: StartupLoadBarrier?,
                            apply: @escaping @MainActor (QuerySnapshot?, Error?) -> Void) {
        let session = snapshotSession
        let registration = query.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                self?.enqueueStartupSnapshot(barrier, session: session, isFromCache: snapshot?.metadata.isFromCache ?? false) {
                    apply(snapshot, error)
                }
            }
        }
        listeners.append(registration)
    }

    func listenStartupDocument(_ document: DocumentReference, barrier: StartupLoadBarrier?,
                               apply: @escaping @MainActor (DocumentSnapshot?, Error?) -> Void) {
        let session = snapshotSession
        let registration = document.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                self?.enqueueStartupSnapshot(barrier, session: session, isFromCache: snapshot?.metadata.isFromCache ?? false) {
                    apply(snapshot, error)
                }
            }
        }
        listeners.append(registration)
    }

    /// Restore missing local projects from Firestore's cache without replacing local edits.
    private func restoreCachedProjects(_ ordered: Query, session: UUID) async -> Set<String> {
        var cursor: DocumentSnapshot?
        var restored = Set<String>()
        while snapshotIsCurrent(session) {
            let remaining = cursor.map { ordered.start(afterDocument: $0) } ?? ordered
            guard let page = try? await remaining.limit(to: 10).getDocuments(source: .cache),
                  snapshotIsCurrent(session), let context else { break }
            guard !page.documents.isEmpty else { break }
            // Compare the optional column directly: coalescing inside IN produces unsupported SQL on iOS.
            let ids = page.documents.map { Optional($0.documentID) }
            guard let existing = try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { ids.contains($0.syncID) })) else { break }
            let localIDs = Set(existing.compactMap(\.syncID))
            let missing = page.documentChanges.filter { change in
                let id = change.document.documentID, key = "\(Job.collection)/\(id)"
                // A known record missing locally may be the user's pending deletion.
                return change.type != .removed && ProjectCacheReconciliation.canRestore(existsLocally: localIDs.contains(id),
                    wasPreviouslySynced: known[key] != nil, hasPendingWrite: unconfirmed[key] != nil)
            }
            await receive(Job.self, missing, session: session)
            restored.formUnion(missing.map { $0.document.documentID })
            guard let last = page.documents.last, page.documents.count == 10 else { break }
            cursor = last
            guard await pauseSnapshotApplication(session) else { break }
        }
#if DEBUG
        SyncLog.sync.debug("restored \(restored.count) missing projects from Firestore cache")
#endif
        return restored
    }

    /// Only a complete server enumeration may reconcile cache records that no longer exist remotely.
    private func reconcileRestoredProjects(_ restored: Set<String>, serverIDs: Set<String>) {
        guard let context else { return }
        let missing = restored.subtracting(serverIDs).map { Optional($0) }
        guard !missing.isEmpty,
              let projects = try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { missing.contains($0.syncID) })) else { return }
        saveUncommittedChanges()
        applyingRemoteSnapshots = true
        for project in projects {
            guard let id = project.syncID else { continue }
            let key = "\(Job.collection)/\(id)"
            if ProjectCacheReconciliation.canRemove(serverContainsID: serverIDs.contains(id), knownFingerprint: known[key],
                                                    localFingerprint: fingerprint(project.record), hasPendingWrite: unconfirmed[key] != nil) {
                known[key] = nil
                syncedRecords[key] = nil
                pending[key] = nil
                context.delete(project)
            }
        }
        saveSnapshotChanges()
    }

    /// Fetch ten projects per request and publish each batch before requesting the next.
    private func loadProjectsInBatches() async throws -> Bool {
        let session = snapshotSession
        guard snapshotIsCurrent(session) else { return false }
        let stage = SyncLog.signposts.beginInterval("sync stage", id: SyncLog.signposts.makeSignpostID(), "projects")
        defer { SyncLog.signposts.endInterval("sync stage", stage) }
        loadingCollections.insert(Job.collection)
        defer {
            if snapshotSession == session {
                loadingCollections.remove(Job.collection)
                initialServerProjectIDs.removeAll()
            }
        }
        let ordered = query(Job.collection).order(by: FieldPath.documentID())
        let restored = await restoreCachedProjects(ordered, session: session)
        guard snapshotIsCurrent(session) else { return false }
        var serverIDs = Set<String>()
        var cursor: DocumentSnapshot?
        var received = 0
        while snapshotIsCurrent(session) {
            let remaining = cursor.map { ordered.start(afterDocument: $0) } ?? ordered
            // A short cached page is not proof that the server has no more projects.
            let request = SyncLog.signposts.beginInterval("project page", id: SyncLog.signposts.makeSignpostID())
            let page = try await remaining.limit(to: 10).getDocuments(source: .server)
            SyncLog.signposts.endInterval("project page", request, "\(page.documents.count) documents")
            guard snapshotIsCurrent(session) else { return false }
            serverIDs.formUnion(page.documents.map(\.documentID))
            await receive(Job.self, page.documentChanges, session: session)
            guard snapshotIsCurrent(session) else { return false }
            if let last = page.documents.last {
                listen(Job.self, queryOverride: remaining.end(atDocument: last))
                cursor = last
            }
            received += page.documents.count
#if DEBUG
            SyncLog.sync.debug("project request \(page.documents.count)/10, loaded \(received), cache \(page.metadata.isFromCache)")
#endif
            if page.documents.count < 10 {
                let tail = cursor.map { ordered.start(afterDocument: $0) } ?? ordered
                listen(Job.self, queryOverride: tail)
                // Include live additions behind a cursor, which may arrive while later pages are fetched.
                reconcileRestoredProjects(restored, serverIDs: serverIDs.union(initialServerProjectIDs))
                saveKnown()
                return true
            }
            guard await pauseSnapshotApplication(session) else { return false }
        }
        return false
    }

    private func listenInitial<M: CloudSynced>(_ type: M.Type, optional: Bool = false, owner: String? = nil) async -> Bool {
        loadingCollections.insert(M.collection)
        return await waitForStartup(M.collection) { barrier in
            listen(type, optional: optional, owner: owner, onFirstSnapshot: { [weak self] in
                self?.loadingCollections.remove(M.collection)
            }, barrier: barrier)
        }
    }

    var knownKey: String { "cloudSync.known.\(uid ?? "")" }

    /// The Firebase account whose `known` matches the records on this device.
    private static let lastUIDKey = "cloudSync.lastUID"
    /// Set by `LocalData` when another team account takes over the device and keeps its records.
    static let carryKnownKey = "cloudSync.carryKnown"

    /// The records stay on the device for the next team account, so what the server has of them does too: without
    /// the previous account's `known`, the first push would send every record again.
    private static func carryKnown(to uid: String) {
        let d = UserDefaults.standard
        if d.bool(forKey: carryKnownKey), let last = d.string(forKey: lastUIDKey), last != uid {
            d.set(d.dictionary(forKey: "cloudSync.known.\(last)"), forKey: "cloudSync.known.\(uid)")
        }
        d.removeObject(forKey: carryKnownKey)
        d.set(uid, forKey: lastUIDKey)
    }

    func saveKnown() {
        guard uid != nil else { return }
        UserDefaults.standard.set(known, forKey: knownKey)
    }

    func recordFingerprintCache<M: CloudSynced>(_ type: M.Type) -> RecordFingerprintCache<M.Record> {
        let id = ObjectIdentifier(type)
        if let cache = recordFingerprintCaches[id] as? RecordFingerprintCache<M.Record> { return cache }
        let cache = RecordFingerprintCache<M.Record>()
        recordFingerprintCaches[id] = cache
        return cache
    }

    func fingerprint<T: Encodable>(_ value: T) -> String {
        Self.recordFingerprint(value)
    }

    nonisolated static func recordFingerprint<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func synced() {
        state = .synced
        lastSync = .now
        refreshFailed = false
    }
}

extension CloudSync.State {
    var title: String {
        switch self {
        case .off: "ปิดอยู่"
        case .connecting: "กำลังเชื่อมต่อ…"
        case .synced: "ซิงค์แล้ว"
        case .failed: "ซิงค์ไม่สำเร็จ"
        }
    }
}
