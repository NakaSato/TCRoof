#if canImport(UIKit)
import SwiftUI
import UIKit
import Observation
import TCRoofCore
import ExcelExport
import PDFReport
import DriveSync

/// State of the survey-report feature: jobs on disk, photo cache, exports and settings.
@MainActor @Observable
public final class SurveyModel {
    public let store: JobStore
    public private(set) var jobs: [Job] = []
    public var settings: SurveySettings { didSet { settings.save() } }
    public let google: GoogleAuth
    /// Set by a host app whose own login is this Google account, so signing out here also ends its session.
    @ObservationIgnored public var signOutHandler: (@MainActor () -> Void)?

    @ObservationIgnored private var pendingSave: [UUID: Task<Void, Never>] = [:]
    /// Called after a job is created, edited, duplicated or deleted here (not for `applyRemote`/`removeRemote`).
    @ObservationIgnored public var onChange: (() -> Void)?
    /// Jobs the host app's cloud (TCRoof: Firestore) doesn't hold in their latest form yet.
    /// nil without a cloud — the home screen then counts jobs not yet saved to Google Drive.
    public var cloudPending: Set<UUID>?
    /// Sends the pending jobs to the host's cloud now.
    @ObservationIgnored public var cloudPush: (() -> Void)?
    /// Called after a Drive save succeeds, with the saved job (its `drive` link updated), the file kinds and
    /// whether photos were sent. TCRoof posts `บันทึกขึ้น Drive แล้ว` from here.
    @ObservationIgnored public var onDriveSaved: ((Job, [DriveSync.Kind], Bool) -> Void)?
    /// Called with a survey's linked job (`jobSyncID`) once it has moved to installation. TCRoof sets that job to
    /// `กำลังติดตั้ง` from here.
    @ObservationIgnored public var onMovedToInstall: ((String) -> Void)?
    let cache = NSCache<NSString, UIImage>()
    /// Download progress per job of photos taken on another iPad.
    public internal(set) var photoFetch: [UUID: PhotoTransfer] = [:]
    var photoRevision = 0
    /// Bumped when an issued REV arrives from another device, so pages showing REVs read the files again.
    public internal(set) var revisionArrivals = 0

    /// Upload progress per job; kept after a failure so the editor can say it will retry.
    public internal(set) var photoUpload: [UUID: PhotoTransfer] = [:]
    @ObservationIgnored var uploadWait: [UUID: Task<Void, Never>] = [:]
    /// Jobs whose photo upload waits for the battery (`PowerMonitor`).
    @ObservationIgnored var heldUploads: Set<UUID> = []
    /// The sensors' reading for the photo the survey camera just returned (`CheckedCamera` / `WideCamera` → `addPhoto`);
    /// `strip` marks three wide shots side by side, kept larger.
    @ObservationIgnored var captureStamp: (stamp: PhotoStamp, at: Date, strip: Bool)?
    @ObservationIgnored var uploadRun: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var manualDriveSave: Set<UUID> = []

    public init(store: JobStore = .documents()) {
        self.store = store
        let s = SurveySettings.load()
        self.settings = s
        self.google = GoogleAuth(clientID: s.googleClientID)
        reload()
        // the standard design library (docs/specs/standard-designs.md §5), next to the app's other support files
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        DesignLibrary.shared.configure(url: support.appendingPathComponent("standard-designs.json"))
    }

    public func reload() {
        for id in Array(pendingSave.keys) { flush(id) }
        jobs = store.loadAll()
    }

    public func job(_ id: UUID) -> Job? { jobs.first { $0.id == id } }

    // MARK: editing

    public func create(_ template: JobTemplate, engineer: String = "") -> Job {
        var j = Job.new(template: template)
        if !engineer.isEmpty { j.values["engineer"] = .text(engineer) }
        jobs.insert(j, at: 0)
        try? store.save(j)
        onChange?()
        return j
    }

    /// Keeps the list current at once and writes to disk shortly after the last change.
    @discardableResult
    public func update(_ job: Job) -> Bool {
        var j = job
        // only answers count as an edit — a Drive link landing after a save mustn't make the job look unsaved again
        if let old = self.job(j.id), old.values == j.values, old.modules == j.modules, old.jobSyncID == j.jobSyncID,
           old.stage == j.stage, old.install == j.install { j.updated = old.updated }
        else { j.updated = Date() }
        if let i = jobs.firstIndex(where: { $0.id == j.id }) { jobs[i] = j } else { jobs.insert(j, at: 0) }
        pendingSave[j.id]?.cancel()
        let snapshot = j
        pendingSave[j.id] = Task { [store, snapshot] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            try? store.save(snapshot)
        }
        onChange?()
        return true
    }

    public func flush(_ id: UUID) {
        pendingSave[id]?.cancel(); pendingSave[id] = nil
        if let j = job(id) { try? store.save(j); store.purgeUnusedPhotos(of: j) }
    }

    public func delete(_ id: UUID) {
        pendingSave[id]?.cancel()
        try? store.delete(id)
        jobs.removeAll { $0.id == id }
        onChange?()
    }

    public func duplicate(_ id: UUID) {
        guard let j = job(id), let copy = try? store.duplicate(j) else { return }
        jobs.insert(copy, at: 0)
        onChange?()
    }

    // MARK: project stages

    /// Jobs of one home tab. Surveys include those moved on, which stay listed there.
    public func jobs(in stage: JobStage) -> [Job] {
        stage == .survey ? jobs.filter { $0.stage != .maintenance } : jobs.filter { $0.stage == stage }
    }

    /// Makes a survey an installation job (an unfinished one only with `evenIfIncomplete`); it saves and waits for sync
    /// like any edit.
    @discardableResult
    public func moveToInstall(_ id: UUID, evenIfIncomplete: Bool = false) -> Bool {
        guard var j = job(id), j.moveToInstall(evenIfIncomplete: evenIfIncomplete) else { return false }
        update(j)
        flush(id)
        if let link = j.jobSyncID { onMovedToInstall?(link) }
        return true
    }

    /// Returns an installation job to the survey stage, dropping its installation progress.
    @discardableResult
    public func moveBackToSurvey(_ id: UUID) -> Bool {
        guard var j = job(id), j.moveBackToSurvey() else { return false }
        update(j)
        flush(id)
        return true
    }

    /// Hands an installation job over to maintenance.
    @discardableResult
    public func moveToMaintenance(_ id: UUID) -> Bool {
        guard var j = job(id), j.moveToMaintenance() else { return false }
        update(j)
        flush(id)
        return true
    }

    /// Returns a handed-over job to the installation stage.
    @discardableResult
    public func moveBackToInstall(_ id: UUID) -> Bool {
        guard var j = job(id), j.moveBackToInstall() else { return false }
        update(j)
        flush(id)
        return true
    }

    // MARK: link to the host app's jobs

    /// Reports that belong to one host-app job, newest first.
    public func jobs(linkedTo syncID: String) -> [Job] { jobs.filter { $0.jobSyncID == syncID } }

    /// Host-app answers the report can start from; only blank fields are filled, so nothing typed is overwritten.
    public struct Prefill: Sendable {
        public var projectName = "", coordinator = "", phone = "", address = "", capacityKW = 0.0
        public var date: Date?
        public init(projectName: String = "", coordinator: String = "", phone: String = "", address: String = "", capacityKW: Double = 0, date: Date? = nil) {
            self.projectName = projectName; self.coordinator = coordinator; self.phone = phone; self.address = address
            self.capacityKW = capacityKW; self.date = date
        }
    }

    /// Links a report to a host job (or unlinks it with nil) and fills its blank cover fields from `prefill`.
    public func link(_ id: UUID, to syncID: String?, prefill: Prefill? = nil) {
        guard var j = job(id) else { return }
        j.jobSyncID = syncID
        if let p = prefill { Self.fill(&j.values, from: p) }
        update(j)
    }

    /// A new report for a host job, started from its customer details.
    public func create(_ template: JobTemplate, engineer: String = "", linkedTo syncID: String, prefill: Prefill) -> Job {
        var j = create(template, engineer: engineer)
        j.jobSyncID = syncID
        // a new report is dated on the job's survey appointment rather than today
        if let d = prefill.date { j.values["date"] = .text(ISODate.string(d)) }
        Self.fill(&j.values, from: prefill)
        update(j)
        return j
    }

    static func fill(_ v: inout Values, from p: Prefill) {
        func put(_ key: String, _ s: String) {
            let s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty, v.text(key).trimmingCharacters(in: .whitespaces).isEmpty { v[key] = .text(s) }
        }
        put("projectName", p.projectName); put("coordinator", p.coordinator); put("phone", p.phone); put("address", p.address)
        if p.capacityKW > 0 { put("capacity", p.capacityKW.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))) }
        if let d = p.date { put("date", ISODate.string(d)) }
    }

    /// Host-supplied name of a linked job ("TC-0012 · สถานีสูบน้ำ"), shown on the report cards; nil when it isn't found.
    @ObservationIgnored public var linkedJobLabel: ((String) -> String?)?
    /// Host-supplied external people and supervising engineer of a linked job (by its syncID), for the role checks.
    @ObservationIgnored public var linkedJobAccess: ((String) -> JobAccess?)?
    /// Host-supplied: everyone who should read a survey's photos on Drive (the team, and the linked job's contractors
    /// and supervisor). Their folder is shared with them after each upload.
    @ObservationIgnored public var driveReaders: ((Job) -> [String])?

    /// Who a survey's linked job is open to; nil for a survey with no linked job.
    public func access(_ job: Job) -> JobAccess? {
        job.jobSyncID.flatMap { linkedJobAccess?($0) }
    }

    /// A job changed on another device; replaces the local copy, except that the Drive files either side knows of are
    /// kept (`DriveLink.merged`): a copy saved before this device's upload landed would otherwise send those photos again.
    /// Photo files don't travel with it — the editor downloads them from Drive (`fetchMissingPhotos`).
    public func applyRemote(_ job: Job) {
        pendingSave[job.id]?.cancel(); pendingSave[job.id] = nil
        var job = job
        if let local = self.job(job.id)?.drive { job.drive = job.drive.map { $0.merged(with: local) } ?? local }
        if let i = jobs.firstIndex(where: { $0.id == job.id }) { jobs[i] = job } else { jobs.insert(job, at: 0) }
        try? store.save(job)
    }

    /// A job deleted on another device.
    public func removeRemote(_ id: UUID) {
        pendingSave[id]?.cancel(); pendingSave[id] = nil
        try? store.delete(id)
        jobs.removeAll { $0.id == id }
    }
}

public struct SurveySettings: Codable, Equatable {
    public var company = "TC Roof"
    public var googleClientID = ""
    public var driveRoot = "Solar Survey Projects"
    public var engineer = ""
    /// Mapbox access token for site pictures, the first map source; empty = the build's `MapboxAccessToken`
    /// (git-ignored Secrets.xcconfig), else Mapbox is skipped.
    public var mapboxToken = ""
    /// Google Maps Static API key, used when Mapbox has no token or doesn't answer; empty = skip Google.
    public var googleMapsKey = ""
    /// GISTDA flood API key for A4; empty = use the build's `GISTDAAPIKey` (git-ignored Secrets.xcconfig), else the lookup is off.
    public var gistdaKey = ""
    /// Map zoom for site pictures: 20 ≈ 90 m across, 19 ≈ 180 m, 18 ≈ 360 m (at latitude 15°).
    public var mapZoom = 20
    /// Send new photos to Google Drive in the background so other iPads can download them.
    public var autoUploadPhotos = true
    /// PV module rating used for W/panel → kWp (variant id in `PVModuleCatalog`, e.g. "zxm7-uhldd144-580").
    public var pvModule = PVModuleCatalog.defaultVariantID
    /// Print each camera photo's position, direction and time under it in the PDF report (hardware assist §H4).
    public var printPhotoStamps = false
    /// Percent under its MP plan at which a station counts as `ช้ากว่าแผน` (PWA settings page, the install overview).
    public var behindThreshold = InstallOverview.defaultThreshold
    /// PWA settings page, `รายงานประจำวัน`: remind before the daily report deadline, and when the inspector hasn't acknowledged.
    public var remindDailyDeadline = true
    public var remindInspectorPending = true

    public init() {}
    public init(from decoder: Decoder) throws {
        // settings saved by an older version miss the newer keys — keep defaults for those
        let c = try decoder.container(keyedBy: CodingKeys.self)
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? company
        gistdaKey = try c.decodeIfPresent(String.self, forKey: .gistdaKey) ?? gistdaKey
        googleClientID = try c.decodeIfPresent(String.self, forKey: .googleClientID) ?? googleClientID
        driveRoot = try c.decodeIfPresent(String.self, forKey: .driveRoot) ?? driveRoot
        engineer = try c.decodeIfPresent(String.self, forKey: .engineer) ?? engineer
        googleMapsKey = try c.decodeIfPresent(String.self, forKey: .googleMapsKey) ?? googleMapsKey
        mapboxToken = try c.decodeIfPresent(String.self, forKey: .mapboxToken) ?? mapboxToken
        mapZoom = try c.decodeIfPresent(Int.self, forKey: .mapZoom) ?? mapZoom
        autoUploadPhotos = try c.decodeIfPresent(Bool.self, forKey: .autoUploadPhotos) ?? autoUploadPhotos
        pvModule = try c.decodeIfPresent(String.self, forKey: .pvModule) ?? pvModule
        printPhotoStamps = try c.decodeIfPresent(Bool.self, forKey: .printPhotoStamps) ?? printPhotoStamps
        behindThreshold = try c.decodeIfPresent(Double.self, forKey: .behindThreshold) ?? behindThreshold
        remindDailyDeadline = try c.decodeIfPresent(Bool.self, forKey: .remindDailyDeadline) ?? remindDailyDeadline
        remindInspectorPending = try c.decodeIfPresent(Bool.self, forKey: .remindInspectorPending) ?? remindInspectorPending
    }
    static let key = "solarSurvey.settings"

    /// Mapbox token from the git-ignored xcconfig (Info.plist `MapboxAccessToken`); empty when none is built in.
    static var bundledMapboxToken: String {
        (Bundle.main.object(forInfoDictionaryKey: "MapboxAccessToken") as? String).map { $0.hasPrefix("$(") ? "" : $0 } ?? ""
    }

    /// Keys for `MapImage.fetch`: the token typed in Settings, else the built-in one.
    var mapKeys: MapImage.Keys {
        let typed = mapboxToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return MapImage.Keys(mapbox: typed.isEmpty ? Self.bundledMapboxToken : typed, google: googleMapsKey)
    }
    static func load() -> SurveySettings {
        guard let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(SurveySettings.self, from: d) else { return SurveySettings() }
        return s
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) } }
}

extension UIImage {
    func scaled(maxSide: CGFloat, opaque: Bool = true) -> UIImage {
        let px = CGSize(width: size.width * scale, height: size.height * scale)
        let k = min(1, maxSide / max(px.width, px.height))
        let target = CGSize(width: (px.width * k).rounded(), height: (px.height * k).rounded())
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = opaque
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
#endif
