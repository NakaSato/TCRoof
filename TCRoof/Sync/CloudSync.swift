import Foundation
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

    @ObservationIgnored private let performance = OSSignposter(subsystem: "com.tcroof.internal", category: "CloudSync")

    enum State: Equatable {
        case off, connecting, synced
        case failed(String)
    }

    private(set) var state = State.off
    private(set) var lastSync: Date?
    /// The last pull to refresh found no network or couldn't reach the server; the feed says it shows what's here.
    private(set) var refreshFailed = false
    /// Pulls to refresh so far: the feed rebuilds after each, at the time it ends.
    private(set) var refreshes = 0
    private(set) var loadingCollections = Set<String>()

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var survey: SurveyModel?
    @ObservationIgnored private var uid: String?
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var listeningCollections = Set<String>()
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var startupBarrier: StartupLoadBarrier?
    @ObservationIgnored private var initialServerProjectIDs = Set<String>()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var recordFingerprintCaches: [ObjectIdentifier: Any] = [:]
    @ObservationIgnored private var surveyRecords: [UUID: (job: TCRoofCore.Job, externals: [String]?, record: SurveyRecord, fingerprint: String)] = [:]
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var uploadScans = UploadScanState()
    /// Preserve listener order while preparing remote values off-main, then commit bounded main-actor chunks.
    /// Relationship lookups are shared across each queued burst.
    @ObservationIgnored private var pendingSnapshotWork: [@MainActor () async -> Void] = []
    @ObservationIgnored private var snapshotApplyTask: Task<Void, Never>?
    /// Invalidates callbacks already queued by Firestore when a session stops or restarts.
    @ObservationIgnored private var snapshotSession = UUID()
    private static let snapshotWorker = SnapshotPreparationWorker()
    @ObservationIgnored private var snapshotJobIndex: [String: Job]?
    @ObservationIgnored private var applyingRemoteSnapshots = false
    @ObservationIgnored private var remoteSavePushSuppressions = Set<ObjectIdentifier>()
    @ObservationIgnored private var pendingModelIndexes: [ObjectIdentifier: Any] = [:]
    @ObservationIgnored private var known: [String: String] = [:]
    /// Writes per document not yet confirmed by the server (offline, or still uploading).
    @ObservationIgnored private var unconfirmed: [String: Int] = [:]
    /// Child records waiting for their job to arrive, keyed like `known`.
    @ObservationIgnored private var pending: [String: () -> Bool] = [:]
    @ObservationIgnored private var pendingRetryScheduled = false
    @ObservationIgnored private var pendingRetryAgain = false
    /// The signed-in email when the member is external (roles): the listeners then ask only for the documents that
    /// list it in `externals`, which is all firestore.rules lets them read, and the push sends only what they may change.
    @ObservationIgnored private var external: String?

    private static let surveyCollection = "pwaSurveys"
    /// One document per issued REV of a survey report, written once.
    private static let revisionCollection = "pwaSurveyRevisions"
    /// One document per feed post: the emails of the members who acknowledged it (`รับทราบ`).
    private static let ackCollection = "feedAcks"
    /// One document per job: the customer's phone and address, for the team only (`JobContactRecord`).
    private static let contactCollection = "jobContacts"
    /// Each person's travel log (`Trip`, `Expense`, `ClaimMonth`).
    private static let travelCollections = [Trip.collection, Expense.collection, ClaimMonth.collection]
    private static let toolCollections = [ToolEvent.collection, CompanyVehicle.collection]
    /// `config/app`: switches set in the Firebase console (`contactsSplit`).
    private static let configDocument = "config/app"
    private static let contactsSplitKey = "cloudSync.contactsSplit"
    private var db: Firestore { Firestore.firestore() }

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
        TeamDirectory.shared.clear()
        PhotoSync.shared.stop()
        pending = [:]
        pendingRetryScheduled = false
        pendingRetryAgain = false
        unconfirmed = [:]
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
            // Start each collection after its first received data has applied; retain its live listener afterward.
            guard try await loadProjectsInBatches() else { return }
            guard await listenInitial(SurveyForm.self) else { return }
            guard await listenInitial(InstallLog.self) else { return }
            guard await listenInitial(Inspection.self) else { return }
            guard await listenInitial(PhotoAsset.self, optional: true) else { return }
            // Secondary collections also wait for their initial application, rather than overlapping on timers.
            if external == nil, !me.email.isEmpty {
                guard await waitForStartup("claim reviews", register: { listenClaimReviews(owner: me.email, barrier: $0) }) else { return }
            }
            guard await listenSurveysInitial() else { return }
            if external == nil {
                guard await waitForStartup("survey revisions", register: { listenRevisions(barrier: $0) }) else { return }
            }
            guard await waitForStartup("feed acknowledgements", register: { listenFeedAcks(barrier: $0) }) else { return }
            guard await waitForStartup("designs", register: { listenDesigns(barrier: $0) }) else { return }
            guard await waitForStartup("design sheets", register: { listenDesignSheets(barrier: $0) }) else { return }
            guard await waitForStartup("tank standard", register: { listenTankStandard(barrier: $0) }) else { return }
            if external == nil {
                guard await waitForStartup("contacts", register: { listenContacts(barrier: $0) }) else { return }
                guard await waitForStartup("directory", register: { listenDirectory(barrier: $0) }) else { return }
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

    private func waitForStartup(_ label: String, register: (StartupLoadBarrier) -> Void) async -> Bool {
        let session = snapshotSession
        guard snapshotIsCurrent(session) else { return false }
        let barrier = StartupLoadBarrier()
        startupBarrier = barrier
        let started = Date()
        CrashReporting.startupStage(label, state: "begin")
#if DEBUG
        print("CloudSync: startup begin \(label)")
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
        print("CloudSync: startup end \(label): \(result), \(Int(Date().timeIntervalSince(started) * 1000)) ms")
#endif
        guard result != .cancelled, snapshotIsCurrent(session) else { return false }
        return await pauseSnapshotApplication(session)
    }

    private func enqueueStartupSnapshot(_ barrier: StartupLoadBarrier?, session: UUID, isFromCache: Bool,
                                        apply: @escaping @MainActor () async -> Void) {
        guard snapshotIsCurrent(session) else { return }
        barrier?.received()
        enqueueSnapshotApplication { [weak self] in
            guard let self, self.snapshotIsCurrent(session) else { return }
            await apply()
            barrier?.applied(isFromCache: isFromCache)
        }
    }

    private func listenStartupQuery(_ query: Query, barrier: StartupLoadBarrier?,
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

    private func listenStartupDocument(_ document: DocumentReference, barrier: StartupLoadBarrier?,
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
        print("CloudSync: restored \(restored.count) missing projects from Firestore cache")
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
            let page = try await remaining.limit(to: 10).getDocuments(source: .server)
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
            print("CloudSync: project request \(page.documents.count)/10, loaded \(received), cache \(page.metadata.isFromCache)")
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

    private var knownKey: String { "cloudSync.known.\(uid ?? "")" }

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

    private func saveKnown() {
        guard uid != nil else { return }
        UserDefaults.standard.set(known, forKey: knownKey)
    }

    private func recordFingerprintCache<M: CloudSynced>(_ type: M.Type) -> RecordFingerprintCache<M.Record> {
        let id = ObjectIdentifier(type)
        if let cache = recordFingerprintCaches[id] as? RecordFingerprintCache<M.Record> { return cache }
        let cache = RecordFingerprintCache<M.Record>()
        recordFingerprintCaches[id] = cache
        return cache
    }

    private func fingerprint<T: Encodable>(_ value: T) -> String {
        Self.recordFingerprint(value)
    }

    nonisolated private static func recordFingerprint<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func synced() {
        state = .synced
        lastSync = .now
        refreshFailed = false
    }

    // MARK: pull to refresh

    /// The home's pull to refresh. The listeners already bring every change in, so this restarts a failed sync or
    /// pushes what's waiting, then waits up to 8 s for the server. Offline, Firestore keeps serving its cache and the
    /// state stays `.synced`, so the network is checked too.
    func refresh() async {
        defer { refreshes += 1 }
        guard context != nil else { return }
        if case .failed = state { retry() } else { push() }
        for _ in 0..<32 where state != .synced { try? await Task.sleep(for: .milliseconds(250)) }
        let online = await Self.isOnline()
        refreshFailed = !online || state != .synced
    }

    /// Before the account signs out: sends what is waiting, then waits up to `seconds` for the server to confirm
    /// every write Firestore holds for this account, those queued in earlier launches too. False offline or on
    /// timeout; the writes then stay queued under this account until it signs in here again.
    func flush(seconds: Double = 10) async -> Bool {
        guard context != nil, Auth.auth().currentUser != nil else { return true }
        if case .failed = state { retry() } else { push() }
        let done = Flag()
        return await withCheckedContinuation { cont in
            db.waitForPendingWrites { error in
                MainActor.assumeIsolated { if done.set() { cont.resume(returning: error == nil) } }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                if done.set() { cont.resume(returning: false) }
            }
        }
    }

    /// Resumes a continuation once, from whichever of two callbacks comes first.
    @MainActor private final class Flag {
        private var isSet = false
        func set() -> Bool { defer { isSet = true }; return !isSet }
    }

    private static func isOnline() async -> Bool {
        await withCheckedContinuation { done in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                done.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue(label: "cloudSync.path"))
        }
    }

    private func failed(_ error: Error) {
        let e = error as NSError
        if e.domain == FirestoreErrorDomain, e.code == FirestoreErrorCode.permissionDenied.rawValue {
            // firestore.rules only lets in accounts listed under members/
            let who = survey?.google.email.flatMap { $0.isEmpty ? nil : $0 } ?? "บัญชีนี้"
            state = .failed("\(who) ยังไม่ได้รับสิทธิ์ใช้ข้อมูลทีม — ติดต่อผู้ดูแลให้เพิ่มในรายชื่อสมาชิก")
        } else {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: push

    private func schedulePush(collections: Set<String>? = nil) {
        guard !applyingRemoteSnapshots else { return }
        uploadScans.mark(collections)
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.push(fullScan: false)
        }
    }

    private func saveUncommittedChanges() {
        guard let context, context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("CloudSync: local save: \(error.localizedDescription)")
        }
    }

    private func enqueueSnapshotApplication(_ work: @escaping @MainActor () async -> Void) {
        pendingSnapshotWork.append(work)
        guard snapshotApplyTask == nil else { return }
        let session = snapshotSession
        snapshotApplyTask = Task { @MainActor [weak self] in
            // Let the other collection listeners deliver their initial cache/server snapshots into this same batch.
            try? await Task.sleep(for: .milliseconds(50))
            guard let self, self.snapshotIsCurrent(session) else { return }
            // Callbacks can arrive while decoding or between apply chunks. Drain them before releasing the task.
            while !self.pendingSnapshotWork.isEmpty {
                let batch = self.pendingSnapshotWork
                self.pendingSnapshotWork.removeAll(keepingCapacity: true)
                self.snapshotJobIndex = nil
                self.pendingModelIndexes.removeAll(keepingCapacity: true)
                for apply in batch {
                    guard self.snapshotIsCurrent(session) else { return }
                    await apply()
                }
                guard self.snapshotIsCurrent(session) else { return }
                self.saveKnown()
                self.snapshotJobIndex = nil
                self.pendingModelIndexes.removeAll(keepingCapacity: true)
            }
            self.refreshSurveyPending()
            self.snapshotApplyTask = nil
        }
    }

    private func snapshotIsCurrent(_ session: UUID) -> Bool {
        snapshotSession == session && context != nil && !Task.isCancelled
    }

    /// A yield may immediately resume this task. Leave a frame interval between database batches instead.
    private func pauseSnapshotApplication(_ session: UUID) async -> Bool {
        do { try await Task.sleep(for: .milliseconds(24)) }
        catch { return false }
        return snapshotIsCurrent(session)
    }

    /// No suspension occurs between applying a chunk and saving it. UI edits between chunks are saved separately.
    private func saveSnapshotChanges() {
        if let context, context.hasChanges {
            let contextID = ObjectIdentifier(context)
            // Startup saves have no upload observer yet; don't let their marker swallow the first later UI edit.
            if !observers.isEmpty { remoteSavePushSuppressions.insert(contextID) }
            do {
                try context.save()
            } catch {
                remoteSavePushSuppressions.remove(contextID)
                print("CloudSync: remote save: \(error.localizedDescription)")
            }
        }
        applyingRemoteSnapshots = false
    }

    private func jobIndexForSnapshotBatch() -> [String: Job] {
        if let snapshotJobIndex { return snapshotJobIndex }
        let jobs = (try? context?.fetch(FetchDescriptor<Job>())) ?? []
        let index = Dictionary(jobs.compactMap { job in job.syncID.map { ($0, job) } },
                               uniquingKeysWith: { first, _ in first })
        snapshotJobIndex = index
        return index
    }

    private struct Change {
        let key: String
        let write: (WriteBatch) throws -> Void
        let fingerprint: String?
    }

    /// Scheduled saves inspect affected collections. Startup, manual refresh and config changes recover with a full scan.
    private func push(fullScan: Bool = true) {
        // an outdated build sends nothing (`config/app.minSyncVersion`); its edits wait here for the update
        guard let context, let survey, uid != nil, !AppGate.shared.outdated else { return }
        // A partial initial download must never be mistaken for local deletions during an upload scan.
        guard !loadingCollections.contains(Job.collection) else { return }
        guard survey.hasLoaded, !survey.isLoading, snapshotApplyTask == nil, pendingSnapshotWork.isEmpty else { schedulePush(); return }
        let interval = performance.beginInterval("Push")
        defer { performance.endInterval("Push", interval) }
        guard let plan = uploadScans.takePlan(fullScan: fullScan) else { return }
        let session = snapshotSession
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
    private func commitSeparately(_ changes: [Change], _ label: String, size: Int = 400) {
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
            let session = snapshotSession
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
    private enum Upload { case full, readOnly, iecOnly }
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
            guard model.syncs else { continue }
            let key = "\(M.collection)/\(model.syncID!)"
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

    // MARK: pull

    /// The listeners take metadata changes too: when the cache already matches the server, the only event
    /// after the first (cached) snapshot is `isFromCache` turning false, and without it the state stays `.connecting`.
    /// `optional`: a refused listener (its rule not deployed yet) is logged and the rest still syncs.
    /// `owner`: only the documents of that person (`ownerEmail`), the one query the rules allow for the travel log.
    private func listen<M: CloudSynced>(_ type: M.Type, optional: Bool = false, owner: String? = nil,
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
    private func listenOnDemand<M: CloudSynced>(_ type: M.Type, optional: Bool = false, owner: String? = nil) {
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

    private func receive<M: CloudSynced>(_ type: M.Type, _ documents: [DocumentChange], session: UUID) async {
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

    private func listenSurveysInitial() async -> Bool {
        await waitForStartup("surveys") { listenSurveys(barrier: $0) }
    }

    private func listenSurveys(barrier: StartupLoadBarrier? = nil) {
        let session = snapshotSession
        let registration = query(Self.surveyCollection).addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            guard MainActor.assumeIsolated({ self?.snapshotSession == session }) else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.enqueueStartupSnapshot(barrier, session: session, isFromCache: snapshot?.metadata.isFromCache ?? false) { [weak self] in
                    guard let self else { return }
                    if let error { self.failed(error); return }
                    guard let snapshot else { return }
                    await self.receiveSurveys(snapshot.documentChanges, session: session)
                    guard self.snapshotIsCurrent(session) else { return }
                    if !snapshot.metadata.isFromCache { self.synced() }
                }
            }
        }
        listeners.append(registration)
    }

    private struct PreparedSurvey: Sendable {
        let job: TCRoofCore.Job
        let fingerprint: String
    }

    private func receiveSurveys(_ changes: [DocumentChange], session: UUID) async {
        guard let survey else { return }
        await survey.waitForReload()
        guard snapshotIsCurrent(session), survey.hasLoaded else { return }
        let interval = performance.beginInterval("ReceiveSurveys")
        defer { performance.endInterval("ReceiveSurveys", interval) }
        let before = Dictionary(survey.jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let started = Date()
        var nextIndex = 0
        var preparedCount = 0
        var longestChunk = 0.0
        while nextIndex < changes.count {
            guard snapshotIsCurrent(session) else { return }
            let batch = try? await Self.snapshotWorker.prepareBatch(changes, startingAt: nextIndex, limit: 8) { change -> PreparedDocumentChange<PreparedSurvey>? in
                let id = change.document.documentID
                if change.type == .removed { return .removed(id: id) }
                guard let record = try? change.document.data(as: SurveyRecord.self),
                      let job = try? JSONDecoder().decode(TCRoofCore.Job.self, from: Data(record.json.utf8)) else { return nil }
                let fingerprint = record.fingerprint
                return .updated(id: id, record: PreparedSurvey(job: job, fingerprint: fingerprint), fingerprint: fingerprint)
            }
            guard let batch, snapshotIsCurrent(session) else { return }
            nextIndex = batch.nextIndex
            let prepared = batch.values
            preparedCount += prepared.count
            var acknowledgements: [String: String] = [:]
            var removals = Set<String>()
            var chunkStart = Date()
            var chunkCount = 0
            for (offset, change) in prepared.enumerated() {
                guard snapshotIsCurrent(session) else { return }
                let key = "\(Self.surveyCollection)/\(change.id)"
                let id = UUID(uuidString: change.id)
                // An edit made during worker preparation or between chunks must still upload.
                let unchanged = id.map { survey.job($0) == before[$0] } ?? false
                switch change {
                case .removed:
                    if unchanged, let id { survey.removeRemote(id) }
                    removals.insert(key)
                case .updated(_, let value, let fingerprint):
                    if known[key] != fingerprint || survey.needsRemoteRecovery(value.job.id) {
                        if unchanged {
                            do {
                                let applied = try await survey.applyRemote(value.job)
                                guard snapshotIsCurrent(session) else { return }
                                guard applied else { continue }
                            } catch {
                                guard snapshotIsCurrent(session) else { return }
                                failed(error)
                                continue // A failed local save must not acknowledge the cloud record.
                            }
                            acknowledgements[key] = survey.job(value.job.id).flatMap { surveyRecord($0)?.fingerprint }
                            // Project cards need photo counts, not image bytes. Editor/export fetch on demand.
                        } else {
                            acknowledgements[key] = fingerprint
                        }
                    }
                }
                chunkCount += 1
                let elapsed = Date().timeIntervalSince(chunkStart)
                if chunkCount >= 8 || elapsed >= 0.008 {
                    longestChunk = max(longestChunk, elapsed)
                    if offset + 1 < prepared.count {
                        guard await pauseSnapshotApplication(session) else { return }
                    }
                    chunkStart = Date()
                    chunkCount = 0
                }
            }
            longestChunk = max(longestChunk, Date().timeIntervalSince(chunkStart))
            guard snapshotIsCurrent(session) else { return }
            for key in removals { known[key] = nil }
            known.merge(acknowledgements, uniquingKeysWith: { _, latest in latest })
            guard await pauseSnapshotApplication(session) else { return }
        }
        refreshSurveyPending()
#if DEBUG
        print("CloudSync: surveys \(preparedCount), local \(survey.jobs.count), total \(Int(Date().timeIntervalSince(started) * 1000)) ms, max apply chunk \(Int(longestChunk * 1000)) ms")
#endif
    }

    /// A whole collection for the team; for an external member only the documents of their jobs, the one query
    /// firestore.rules allows them.
    private func query(_ collection: String) -> Query {
        let all = db.collection(collection)
        guard let external else { return all }
        return all.whereField("externals", arrayContains: external)
    }

    /// REVs issued on other devices: their snapshots are stored next to the job, as if issued here. The team's only.
    private func listenRevisions(barrier: StartupLoadBarrier? = nil) {
        guard external == nil else { return }
        let session = snapshotSession
        listenStartupQuery(db.collection(Self.revisionCollection), barrier: barrier) { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self, let survey = self.survey else { return }
                // never fail the whole sync over REVs (rules not deployed yet): the jobs still sync
                if let error { return print("CloudSync: REV listener: \(error.localizedDescription)") }
                for change in snapshot?.documentChanges ?? [] {
                    let key = "\(Self.revisionCollection)/\(change.document.documentID)"
                    if change.type == .removed { self.known[key] = nil; continue }
                    guard let record = try? change.document.data(as: RevisionRecord.self), self.known[key] != record.fingerprint,
                          let job = UUID(uuidString: record.job) else { continue }
                    self.enqueueSnapshotApplication { [weak self] in
                        guard let self, self.snapshotSession == session else { return }
                        let saved = await survey.receiveRevision(SurveyModel.RevisionDoc(job: job, rev: record.rev, json: record.json))
                        guard saved, self.snapshotSession == session, !Task.isCancelled else { return }
                        self.known[key] = record.fingerprint
                    }
                }
                self.saveKnown()
            }
        }
    }

    /// The home feed's acknowledgements, live. A toggle adds or removes only its own member (`arrayUnion` /
    /// `arrayRemove`), so two people acknowledging at once never overwrite each other; offline, Firestore keeps the
    /// write and sends it later. Acknowledgements made before they were synced are sent once.
    /// The standard design library (docs/specs/standard-designs.md §2): every member takes the designs saved on other
    /// devices (the higher revision wins); a design saved, renamed, archived or imported here is sent, by the team only
    /// (`design.library`; firestore.rules refuses anyone else and an older revision).
    private func listenDesigns(barrier: StartupLoadBarrier? = nil) {
        let session = snapshotSession
        let collection = db.collection("standardDesigns")
        DesignLibrary.shared.onChange = { [weak self] d in
            guard let self, self.snapshotSession == session, self.external == nil else { return }
            let json = String(decoding: d.exported(), as: UTF8.self)
            collection.document(d.id).setData(["json": json, "revision": d.revision, "savedBy": d.savedBy ?? "",
                                               "updatedAt": FieldValue.serverTimestamp()]) { error in
                if let error { print("CloudSync: design upload: \(error.localizedDescription)") }
            }
            // its scanned sheet: each page once, as a JPEG in its own document
            let sent = Set(UserDefaults.standard.stringArray(forKey: "cloudSync.designSheetsSent") ?? [])
            for p in d.sheet where !sent.contains(p.id.uuidString) {
                guard let u = DesignLibrary.shared.sheetURL(p), let data = try? Data(contentsOf: u) else { continue }
                self.db.collection("standardDesignSheets").document(p.id.uuidString)
                    .setData(["design": d.id, "data": data.base64EncodedString(), "width": p.width, "height": p.height]) { [weak self] error in
                        guard MainActor.assumeIsolated({ self?.snapshotSession == session }) else { return }
                        if let error { return print("CloudSync: design sheet upload: \(error.localizedDescription)") }
                        let done = (UserDefaults.standard.stringArray(forKey: "cloudSync.designSheetsSent") ?? []) + [p.id.uuidString]
                        UserDefaults.standard.set(done, forKey: "cloudSync.designSheetsSent")
                    }
            }
        }
        // building roofs (C1, §7) share the collection, marked `kind: roof`
        DesignLibrary.shared.onRoofChange = { [weak self] d in
            guard let self, self.snapshotSession == session, self.external == nil else { return }
            collection.document(d.id).setData(["json": String(decoding: d.exported(), as: UTF8.self), "kind": "roof", "revision": d.revision,
                                               "savedBy": d.savedBy ?? "", "updatedAt": FieldValue.serverTimestamp()]) { error in
                if let error { print("CloudSync: roof design upload: \(error.localizedDescription)") }
            }
        }
        listenStartupQuery(collection, barrier: barrier) { snapshot, error in
            // never fail the whole sync over designs (rules not deployed yet): the jobs still sync
            if let error { return print("CloudSync: design listener: \(error.localizedDescription)") }
            for change in snapshot?.documentChanges ?? [] where change.type != .removed {
                let data = change.document.data()
                guard let json = data["json"] as? String else { continue }
                if data["kind"] as? String == "roof" {
                    if let r = try? RoofDesign.imported(Data(json.utf8)) { DesignLibrary.shared.receiveRoof(r) }
                } else if let d = try? TankDesign.imported(Data(json.utf8)) {
                    DesignLibrary.shared.receive(d)
                }
            }
        }
    }

    private func listenDesignSheets(barrier: StartupLoadBarrier? = nil) {
        listenStartupQuery(db.collection("standardDesignSheets"), barrier: barrier) { snapshot, error in
            if let error { return print("CloudSync: design sheet listener: \(error.localizedDescription)") }
            for change in snapshot?.documentChanges ?? [] where change.type != .removed {
                let data = change.document.data()
                guard let id = UUID(uuidString: change.document.documentID), let b64 = data["data"] as? String,
                      let jpeg = Data(base64Encoded: b64) else { continue }
                let probe = Photo(id: id, fileName: id.uuidString + ".jpg", width: 0, height: 0)
                if DesignLibrary.shared.hasSheetPage(probe) { continue }
                DesignLibrary.shared.storeSheetPage(jpeg, width: data["width"] as? Int ?? 0, height: data["height"] as? Int ?? 0, id: id)
            }
        }
    }

    /// The team's tank structure standard (`config/tankStandard`, docs/specs/tank-mounting-layout.md §1): every member
    /// takes a newer revision; a manager's save here is sent (`tank.standard`; firestore.rules refuses anyone else and
    /// an older revision).
    private func listenTankStandard(barrier: StartupLoadBarrier? = nil) {
        let session = snapshotSession
        let ref = db.document("config/tankStandard")
        TankStandard.Store.shared.onChange = { [weak self] s in
            guard self?.snapshotSession == session, MemberRole.shared.permissions.can(.tankStandard) else { return }
            ref.setData(["json": s.json, "revision": s.revision, "savedBy": s.savedBy ?? "", "updatedAt": FieldValue.serverTimestamp()]) { error in
                if let error { print("CloudSync: tank standard refused: \(error.localizedDescription)") }
            }
        }
        listenStartupDocument(ref, barrier: barrier) { snapshot, error in
            // never fail the whole sync over the standard (rules not deployed yet): the jobs still sync
            if let error { return print("CloudSync: tank standard listener: \(error.localizedDescription)") }
            guard let json = snapshot?.data()?["json"] as? String, let s = TankStandard.decode(json) else { return }
            TankStandard.Store.shared.receive(s)
        }
    }

    private func listenFeedAcks(barrier: StartupLoadBarrier? = nil) {
        let session = snapshotSession
        let acks = FeedAcks.shared
        acks.send = { [weak self] post, member, on in
            guard let self, self.snapshotSession == session else { return }
            self.db.document(Self.ackKey(post)).setData(
                ["post": post, "members": on ? FieldValue.arrayUnion([member]) : FieldValue.arrayRemove([member])], merge: true
            ) { error in
                if let error { print("CloudSync: acknowledgement refused: \(error.localizedDescription)") }
            }
        }
        let uploaded = "feed.acks.uploaded.\(uid ?? "")"
        if !UserDefaults.standard.bool(forKey: uploaded), let me = survey?.google.email, !me.isEmpty {
            for (post, set) in acks.members where set.contains(me) { acks.send?(post, me, true) }
            UserDefaults.standard.set(true, forKey: uploaded)
        }
        listenStartupQuery(db.collection(Self.ackCollection), barrier: barrier) { snapshot, error in
            MainActor.assumeIsolated {
                // never fail the whole sync over acknowledgements (rule not deployed yet): the jobs still sync
                if let error { return print("CloudSync: acknowledgement listener: \(error.localizedDescription)") }
                for change in snapshot?.documentChanges ?? [] {
                    let data = change.document.data()
                    guard let post = data["post"] as? String else { continue }
                    acks.receive(post, change.type == .removed ? [] : Set(data["members"] as? [String] ?? []))
                }
            }
        }
    }

    /// The team's names and emails (team only, `TeamDirectory`): this member's own entry goes up first, with the name in
    /// settings, so the people invited before the directory existed are listed too.
    /// Managers' decisions on this person's submitted months (`ClaimReviews`); refused until the rule is deployed.
    private func listenClaimReviews(owner email: String, barrier: StartupLoadBarrier? = nil) {
        ClaimReviews.shared.start(owner: email)
        let q = db.collection(ClaimReviews.collection).whereField("ownerEmail", isEqualTo: Permissions.normalized(email))
        listenStartupQuery(q, barrier: barrier) { snapshot, error in
            MainActor.assumeIsolated {
                if let error { return print("CloudSync: claimReviews listener: \(error.localizedDescription)") }
                if let snapshot { ClaimReviews.shared.receive(snapshot.documents) }
            }
        }
    }

    private func listenDirectory(barrier: StartupLoadBarrier? = nil) {
        guard external == nil else { return TeamDirectory.shared.clear() }
        let me = MemberRole.shared.permissions.email
        if !me.isEmpty {
            let name = UserDefaults.standard.string(forKey: GoogleSession.userNameKey)
            db.document("\(TeamDirectory.collection)/\(me)").setData(TeamDirectory.entry(email: me, name: name), merge: true) { error in
                if let error { print("CloudSync: directory entry refused: \(error.localizedDescription)") }
            }
        }
        listenStartupQuery(db.collection(TeamDirectory.collection), barrier: barrier) { snapshot, error in
            MainActor.assumeIsolated {
                // never fail the whole sync over the directory (rule not deployed yet): the jobs still sync
                if let error { return print("CloudSync: directory listener: \(error.localizedDescription)") }
                TeamDirectory.shared.receive(snapshot?.documents ?? [])
            }
        }
    }

    /// The customers' phones and addresses (team only). A contact whose job hasn't arrived yet waits for it.
    private func listenContacts(barrier: StartupLoadBarrier? = nil) {
        guard external == nil else { return }
        listenStartupQuery(db.collection(Self.contactCollection), barrier: barrier) { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self, let context = self.context else { return }
                // never fail the whole sync over contacts (rule not deployed yet): the jobs still sync
                if let error { return print("CloudSync: contact listener: \(error.localizedDescription)") }
                for change in snapshot?.documentChanges ?? [] {
                    let id = change.document.documentID
                    let key = "\(Self.contactCollection)/\(id)"
                    if change.type == .removed { self.known[key] = nil; self.pending[key] = nil; continue }
                    guard let record = try? change.document.data(as: JobContactRecord.self), self.known[key] != self.fingerprint(record) else { continue }
                    let apply = { [weak self] () -> Bool in
                        guard let self, let context = self.context,
                              let job = try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.syncID == id })).first else { return false }
                        record.apply(to: job)
                        self.known[key] = self.fingerprint(record)
                        return true
                    }
                    if !apply() { self.pending[key] = apply }
                }
                try? context.save()
                self.saveKnown()
            }
        }
    }

    /// `config/app`, set in the Firebase console: `centerDriveFolder`, `driveShareWith` and `claimShareWith` (`DriveConfig`),
    /// `minSyncVersion` and `installLink` (`AppGate`: an older build stops sending), and `contactsSplit`, switched on
    /// once every device runs this version: the jobs are then sent again without their phone and address.
    private func listenConfig(barrier: StartupLoadBarrier? = nil) {
        listenStartupDocument(db.document(Self.configDocument), barrier: barrier) { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error { return print("CloudSync: config listener: \(error.localizedDescription)") }
                // the center Drive (a folder id or link) and the team emails a contractor's job folder is shared with
                DriveConfig.set(center: snapshot?.get("centerDriveFolder") as? String,
                                shareWith: snapshot?.get("driveShareWith") as? [String] ?? [],
                                claimShareWith: snapshot?.get("claimShareWith") as? [String] ?? [])
                // a build the console has let through again sends what waited
                if AppGate.shared.update(minimum: (snapshot?.get("minSyncVersion") as? NSNumber)?.intValue,
                                         installLink: snapshot?.get("installLink") as? String) {
                    self.push()
                }
                let split = snapshot?.get("contactsSplit") as? Bool ?? false
                guard split != Job.contactsSplit else { return }
                Job.contactsSplit = split
                UserDefaults.standard.set(split, forKey: Self.contactsSplitKey)
                self.push()
            }
        }
    }

    /// A post id as a document id: Firestore ids can't hold `/`.
    static func ackKey(_ post: String) -> String {
        "\(ackCollection)/\(post.replacingOccurrences(of: "/", with: "-"))"
    }

    /// A job's document and fingerprint, kept until the job changes: the push runs after every edit and every 20 s,
    /// and encoding and hashing every job each time held the main thread.
    private func surveyRecord(_ job: TCRoofCore.Job) -> (record: SurveyRecord, fingerprint: String)? {
        // none is nil, so a survey with no one assigned keeps the document and fingerprint it had before roles
        let externals = survey?.access(job)?.externals.nilIfEmpty
        if let hit = surveyRecords[job.id], hit.job == job, hit.externals == externals { return (hit.record, hit.fingerprint) }
        guard let record = SurveyRecord(job, externals: externals) else { return nil }
        let fingerprint = record.fingerprint
        surveyRecords[job.id] = (job, externals, record, fingerprint)
        return (record, fingerprint)
    }

    /// Survey reports whose latest version Firestore doesn't have yet — never sent, edited since, or not confirmed.
    private func refreshSurveyPending() {
        guard let survey else { return }
        let now = Set(survey.jobs.filter { job in
            let key = "\(Self.surveyCollection)/\(job.id.uuidString)"
            return unconfirmed[key] != nil || known[key] != surveyRecord(job)?.fingerprint
        }.map(\.id))
        // the 20 s push timer calls this too — only touch the observed value when it changes
        if survey.cloudPending != now { survey.cloudPending = now }
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}

/// A NO.224 survey report job as one document; the job's own JSON keeps every field the survey module has.
private struct SurveyRecord: Codable, Sendable {
    var projectName: String
    var updated: Int64
    var json: String
    /// The linked job's external people (roles), so an external member's device can ask for the surveys of their jobs.
    var externals: [String]?

    init?(_ job: TCRoofCore.Job, externals: [String]? = nil) {
        guard let data = try? JobStore.encoder.encode(job), let json = String(data: data, encoding: .utf8) else { return nil }
        self.projectName = job.projectName
        self.updated = job.updated.millis
        self.json = json
        self.externals = externals
    }

    /// The survey's own JSON, and the external people when it has any (so a survey with none keeps its old fingerprint).
    var fingerprint: String {
        let text = externals.map { json + "\n" + $0.joined(separator: ",") } ?? json
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// One issued REV: the snapshot's JSON exactly as stored on the device that issued it.
private struct RevisionRecord: Codable {
    var job: String
    var rev: String
    var json: String

    init(_ doc: SurveyModel.RevisionDoc) { job = doc.job.uuidString; rev = doc.rev; json = doc.json }

    var fingerprint: String { SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined() }
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
