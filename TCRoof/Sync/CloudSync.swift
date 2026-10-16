import Foundation
import Observation
import SwiftData
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import Network
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

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var survey: SurveyModel?
    @ObservationIgnored private var uid: String?
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var surveyRecords: [UUID: (job: TCRoofCore.Job, record: SurveyRecord, fingerprint: String)] = [:]
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var known: [String: String] = [:]
    /// Writes per document not yet confirmed by the server (offline, or still uploading).
    @ObservationIgnored private var unconfirmed: [String: Int] = [:]
    /// Child records waiting for their job to arrive, keyed like `known`.
    @ObservationIgnored private var pending: [String: () -> Bool] = [:]

    private static let surveyCollection = "pwaSurveys"
    /// One document per issued REV of a survey report (docs/specs/review-lock-revisions-swift.md), written once.
    private static let revisionCollection = "pwaSurveyRevisions"
    /// One document per feed post: the emails of the members who acknowledged it (`รับทราบ`).
    private static let ackCollection = "feedAcks"
    private var db: Firestore { Firestore.firestore() }

    /// Keeps every synced document on the device with no size limit. With the default 100 MB cap, documents
    /// the listeners aren't using get evicted and have to be downloaded again. On a restart the listeners
    /// then start from this cache and download only what changed. Must run before the first Firestore call.
    private static var cacheConfigured = false
    private static func configureCache() {
        guard !cacheConfigured else { return }
        cacheConfigured = true
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited))
        Firestore.firestore().settings = settings
    }

    // MARK: lifecycle

    func start(context: ModelContext, survey: SurveyModel) {
        guard self.context == nil else { return }
        Self.configureCache()
        self.context = context
        self.survey = survey
        // the survey home shows what Firestore still lacks, even before sign-in finishes
        if let u = Auth.auth().currentUser?.uid { known = UserDefaults.standard.dictionary(forKey: "cloudSync.known.\(u)") as? [String: String] ?? [:] }
        survey.cloudPush = { [weak self] in
            guard let self else { return }
            if case .failed = self.state { self.retry() } else { self.push() }
        }
        refreshSurveyPending()
        Task { await connect() }
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        timer?.invalidate(); timer = nil
        pushTask?.cancel(); pushTask = nil
        survey?.onChange = nil
        survey?.cloudPush = nil
        survey?.cloudPending = nil
        FeedAcks.shared.send = nil
        pending = [:]
        unconfirmed = [:]
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
        state = .connecting
        do {
            let user = try await firebaseUser()
            guard context != nil else { return }
            uid = user.uid
            known = UserDefaults.standard.dictionary(forKey: knownKey) as? [String: String] ?? [:]
            listen(Job.self)
            listen(SurveyForm.self)
            listen(ScannedDevice.self)
            listen(InstallLog.self)
            listen(Inspection.self)
            listenSurveys()
            listenRevisions()
            listenFeedAcks()
            observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedulePush() }
            })
            survey?.onChange = { [weak self] in self?.schedulePush() }
            // Catches edits that haven't been autosaved yet.
            timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.push() }
            }
            push()
        } catch {
            failed(error)
        }
    }

    /// Firebase account of the Google account signed in to the app.
    private func firebaseUser() async throws -> User {
        let email = survey?.google.email
        if let user = Auth.auth().currentUser, email == nil || email == "" || user.email == email { return user }
        guard let google = survey?.google else { throw CancellationError() }
        let tokens = try await google.idAndAccessToken()
        GoogleSession.fillUserName() // the fresh token may carry the account's name
        let credential = GoogleAuthProvider.credential(withIDToken: tokens.idToken, accessToken: tokens.accessToken)
        return try await Auth.auth().signIn(with: credential).user
    }

    private var knownKey: String { "cloudSync.known.\(uid ?? "")" }

    private func saveKnown() {
        guard uid != nil else { return }
        UserDefaults.standard.set(known, forKey: knownKey)
    }

    private func fingerprint<T: Encodable>(_ value: T) -> String {
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

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    private struct Change {
        let key: String
        let write: (WriteBatch) throws -> Void
        let fingerprint: String?
    }

    /// Sends every record that changed since it was last in step, and deletes documents removed here.
    private func push() {
        guard let context, let survey, uid != nil else { return }
        var changes: [Change] = []
        var present = Set<String>()
        collect(Job.self, context, &changes, &present)
        collect(SurveyForm.self, context, &changes, &present)
        collect(ScannedDevice.self, context, &changes, &present)
        collect(InstallLog.self, context, &changes, &present)
        collect(Inspection.self, context, &changes, &present)
        for job in survey.jobs {
            let key = "\(Self.surveyCollection)/\(job.id.uuidString)"
            present.insert(key)
            guard let (record, fingerprint) = surveyRecord(job), known[key] != fingerprint else { continue }
            let ref = db.document(key)
            changes.append(Change(key: key, write: { try $0.setData(from: record, forDocument: ref) }, fingerprint: fingerprint))
        }
        surveyRecords = surveyRecords.filter { present.contains("\(Self.surveyCollection)/\($0.key.uuidString)") }
        let revisions = revisionChanges(survey, &present)
        for key in known.keys where !present.contains(key) {
            let ref = db.document(key)
            changes.append(Change(key: key, write: { $0.deleteDocument(ref) }, fingerprint: nil))
        }
        if context.hasChanges { try? context.save() }   // syncIDs given to older records
        defer { refreshSurveyPending() }
        commitRevisions(revisions)
        guard !changes.isEmpty else { return }

        // Firestore takes at most 500 writes per batch.
        for start in stride(from: 0, to: changes.count, by: 400) {
            let slice = changes[start..<min(start + 400, changes.count)]
            let batch = db.batch()
            var previous: [String: String?] = [:]
            for change in slice {
                do { try change.write(batch) } catch { failed(error); continue }
                previous[change.key] = known[change.key]
                known[change.key] = change.fingerprint
                unconfirmed[change.key, default: 0] += 1
            }
            batch.commit { [weak self] error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Firestore calls back once the server has the batch, or has refused it
                    for key in previous.keys {
                        let left = (self.unconfirmed[key] ?? 1) - 1
                        self.unconfirmed[key] = left > 0 ? left : nil
                    }
                    defer { self.refreshSurveyPending() }
                    if let error {
                        // Put back what the server still has so the next push tries again.
                        for (key, old) in previous { self.known[key] = old }
                        self.saveKnown()
                        self.failed(error)
                    } else {
                        self.synced()
                    }
                }
            }
        }
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

    /// Its own batch: a refusal here (rules not deployed yet) must not hold back the jobs. Tried again on the next push.
    private func commitRevisions(_ changes: [Change]) {
        guard !changes.isEmpty else { return }
        let batch = db.batch()
        var previous: [String: String?] = [:]
        for change in changes {
            guard (try? change.write(batch)) != nil else { continue }
            previous[change.key] = known[change.key]
            known[change.key] = change.fingerprint
        }
        batch.commit { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, let error else { return }
                for (key, old) in previous { self.known[key] = old }
                self.saveKnown()
                print("CloudSync: REV upload refused: \(error.localizedDescription)")
            }
        }
    }

    private func collect<M: CloudSynced>(_ type: M.Type, _ context: ModelContext, _ changes: inout [Change], _ present: inout Set<String>) {
        guard let models = try? context.fetch(FetchDescriptor<M>()) else { return }
        for model in models {
            if model.syncID == nil { model.syncID = UUID().uuidString }
            let key = "\(M.collection)/\(model.syncID!)"
            present.insert(key)
            let record = model.record
            let print = fingerprint(record)
            guard known[key] != print else { continue }
            let ref = db.document(key)
            changes.append(Change(key: key, write: { try $0.setData(from: record, forDocument: ref) }, fingerprint: print))
        }
    }

    // MARK: pull

    /// The listeners take metadata changes too: when the cache already matches the server, the only event
    /// after the first (cached) snapshot is `isFromCache` turning false, and without it the state stays `.connecting`.
    private func listen<M: CloudSynced>(_ type: M.Type) {
        let registration = db.collection(M.collection).addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error { return self.failed(error) }
                guard let snapshot else { return }
                self.receive(M.self, snapshot.documentChanges)
                if !snapshot.metadata.isFromCache { self.synced() }
            }
        }
        listeners.append(registration)
    }

    private func receive<M: CloudSynced>(_ type: M.Type, _ changes: [DocumentChange]) {
        guard let context, !changes.isEmpty else { return }
        let local = Dictionary(((try? context.fetch(FetchDescriptor<M>())) ?? []).compactMap { m in m.syncID.map { ($0, m) } },
                               uniquingKeysWith: { a, _ in a })
        for change in changes {
            let id = change.document.documentID
            let key = "\(M.collection)/\(id)"
            if change.type == .removed {
                if let model = local[id] { context.delete(model) }
                known[key] = nil
                pending[key] = nil
                continue
            }
            guard let record = try? change.document.data(as: M.Record.self), known[key] != fingerprint(record) else { continue }
            if !upsert(M.self, id: id, record: record, existing: local[id]) {
                pending[key] = { [weak self] in self?.upsert(M.self, id: id, record: record, existing: nil) ?? true }
            }
        }
        if M.self == Job.self {
            for (key, retry) in pending where retry() { pending[key] = nil }
        }
        try? context.save()
        saveKnown()
    }

    /// Applies a remote record; false when it belongs to a job this device hasn't received yet.
    private func upsert<M: CloudSynced>(_ type: M.Type, id: String, record: M.Record, existing: M?) -> Bool {
        guard let context else { return true }
        let jobs = Dictionary(((try? context.fetch(FetchDescriptor<Job>())) ?? []).compactMap { j in j.syncID.map { ($0, j) } },
                              uniquingKeysWith: { a, _ in a })
        let model: M
        if let existing {
            guard existing.apply(record, jobs: jobs) else { return false }
            model = existing
        } else {
            let found = try? context.fetch(FetchDescriptor<M>()).first { $0.syncID == id }
            if let found {
                guard found.apply(record, jobs: jobs) else { return false }
                model = found
            } else {
                guard let made = M.make(record, jobs: jobs) else { return false }
                made.syncID = id
                context.insert(made)
                _ = made.apply(record, jobs: jobs)
                model = made
            }
        }
        known["\(M.collection)/\(id)"] = fingerprint(model.record)
        return true
    }

    private func listenSurveys() {
        let registration = db.collection(Self.surveyCollection).addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self, let survey = self.survey else { return }
                if let error { return self.failed(error) }
                guard let snapshot else { return }
                for change in snapshot.documentChanges {
                    let key = "\(Self.surveyCollection)/\(change.document.documentID)"
                    if change.type == .removed {
                        if let id = UUID(uuidString: change.document.documentID) { survey.removeRemote(id) }
                        self.known[key] = nil
                        continue
                    }
                    guard let record = try? change.document.data(as: SurveyRecord.self), self.known[key] != record.fingerprint,
                          let job = try? JobStore.decoder.decode(TCRoofCore.Job.self, from: Data(record.json.utf8)) else { continue }
                    survey.applyRemote(job)
                    self.known[key] = SurveyRecord(job)?.fingerprint
                }
                self.saveKnown()
                self.refreshSurveyPending()
                if !snapshot.metadata.isFromCache { self.synced() }
            }
        }
        listeners.append(registration)
    }

    /// REVs issued on other devices: their snapshots are stored next to the job, as if issued here.
    private func listenRevisions() {
        let registration = db.collection(Self.revisionCollection).addSnapshotListener { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self, let survey = self.survey else { return }
                // never fail the whole sync over REVs (rules not deployed yet): the jobs still sync
                if let error { return print("CloudSync: REV listener: \(error.localizedDescription)") }
                for change in snapshot?.documentChanges ?? [] {
                    let key = "\(Self.revisionCollection)/\(change.document.documentID)"
                    if change.type == .removed { self.known[key] = nil; continue }
                    guard let record = try? change.document.data(as: RevisionRecord.self), self.known[key] != record.fingerprint,
                          let job = UUID(uuidString: record.job) else { continue }
                    survey.receiveRevision(SurveyModel.RevisionDoc(job: job, rev: record.rev, json: record.json))
                    self.known[key] = record.fingerprint
                }
                self.saveKnown()
            }
        }
        listeners.append(registration)
    }

    /// The home feed's acknowledgements, live. A toggle adds or removes only its own member (`arrayUnion` /
    /// `arrayRemove`), so two people acknowledging at once never overwrite each other; offline, Firestore keeps the
    /// write and sends it later. Acknowledgements made before they were synced are sent once.
    private func listenFeedAcks() {
        let acks = FeedAcks.shared
        acks.send = { [weak self] post, member, on in
            guard let self else { return }
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
        let registration = db.collection(Self.ackCollection).addSnapshotListener { snapshot, error in
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
        listeners.append(registration)
    }

    /// A post id as a document id: Firestore ids can't hold `/`.
    static func ackKey(_ post: String) -> String {
        "\(ackCollection)/\(post.replacingOccurrences(of: "/", with: "-"))"
    }

    /// A job's document and fingerprint, kept until the job changes: the push runs after every edit and every 20 s,
    /// and encoding and hashing every job each time held the main thread.
    private func surveyRecord(_ job: TCRoofCore.Job) -> (record: SurveyRecord, fingerprint: String)? {
        if let hit = surveyRecords[job.id], hit.job == job { return (hit.record, hit.fingerprint) }
        guard let record = SurveyRecord(job) else { return nil }
        let fingerprint = record.fingerprint
        surveyRecords[job.id] = (job, record, fingerprint)
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

/// A NO.224 survey report job as one document; the job's own JSON keeps every field the survey module has.
private struct SurveyRecord: Codable {
    var projectName: String
    var updated: Int64
    var json: String

    init?(_ job: TCRoofCore.Job) {
        guard let data = try? JobStore.encoder.encode(job), let json = String(data: data, encoding: .utf8) else { return nil }
        self.projectName = job.projectName
        self.updated = job.updated.millis
        self.json = json
    }

    var fingerprint: String { SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined() }
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
