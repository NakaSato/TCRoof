import Foundation
import SwiftData
import CryptoKit
import FirebaseFirestore
import os
import TCRoofCore
import TCRoofUI

extension CloudSync {
    // MARK: specialized listeners

    func listenSurveysInitial() async -> Bool {
        await waitForStartup("surveys") { listenSurveys(barrier: $0) }
    }

    func listenSurveys(barrier: StartupLoadBarrier? = nil) {
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

    func receiveSurveys(_ changes: [DocumentChange], session: UUID) async {
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
    func query(_ collection: String) -> Query {
        let all = db.collection(collection)
        guard let external else { return all }
        return all.whereField("externals", arrayContains: external)
    }

    /// REVs issued on other devices: their snapshots are stored next to the job, as if issued here. The team's only.
    func listenRevisions(barrier: StartupLoadBarrier? = nil) {
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

    /// The standard design library (docs/specs/standard-designs.md §2): every member takes the designs saved on other
    /// devices (the higher revision wins); a design saved, renamed, archived or imported here is sent, by the team only
    /// (`design.library`; firestore.rules refuses anyone else and an older revision).
    func listenDesigns(barrier: StartupLoadBarrier? = nil) {
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

    func listenDesignSheets(barrier: StartupLoadBarrier? = nil) {
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
    func listenTankStandard(barrier: StartupLoadBarrier? = nil) {
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

    func listenFeedAcks(barrier: StartupLoadBarrier? = nil) {
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

    /// Managers' decisions on this person's submitted months (`ClaimReviews`); refused until the rule is deployed.
    func listenClaimReviews(owner email: String, barrier: StartupLoadBarrier? = nil) {
        ClaimReviews.shared.start(owner: email)
        let q = db.collection(ClaimReviews.collection).whereField("ownerEmail", isEqualTo: Permissions.normalized(email))
        listenStartupQuery(q, barrier: barrier) { snapshot, error in
            MainActor.assumeIsolated {
                if let error { return print("CloudSync: claimReviews listener: \(error.localizedDescription)") }
                if let snapshot { ClaimReviews.shared.receive(snapshot.documents) }
            }
        }
    }

    func listenDirectory(barrier: StartupLoadBarrier? = nil) {
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
    func listenContacts(barrier: StartupLoadBarrier? = nil) {
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
    func listenConfig(barrier: StartupLoadBarrier? = nil) {
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
    func surveyRecord(_ job: TCRoofCore.Job) -> (record: SurveyRecord, fingerprint: String)? {
        // none is nil, so a survey with no one assigned keeps the document and fingerprint it had before roles
        let externals = survey?.access(job)?.externals.nilIfEmpty
        if let hit = surveyRecords[job.id], hit.job == job, hit.externals == externals { return (hit.record, hit.fingerprint) }
        guard let record = SurveyRecord(job, externals: externals) else { return nil }
        let fingerprint = record.fingerprint
        surveyRecords[job.id] = (job, externals, record, fingerprint)
        return (record, fingerprint)
    }

    /// Survey reports whose latest version Firestore doesn't have yet — never sent, edited since, or not confirmed.
    func refreshSurveyPending() {
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
struct SurveyRecord: Codable, Sendable {
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
struct RevisionRecord: Codable {
    var job: String
    var rev: String
    var json: String

    init(_ doc: SurveyModel.RevisionDoc) { job = doc.job.uuidString; rev = doc.rev; json = doc.json }

    var fingerprint: String { SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined() }
}
