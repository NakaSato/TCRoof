#if canImport(UIKit)
import SwiftUI
import UIKit
import Observation
import SurveyCore
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
    private let cache = NSCache<NSString, UIImage>()

    public init(store: JobStore = .documents()) {
        self.store = store
        let s = SurveySettings.load()
        self.settings = s
        self.google = GoogleAuth(clientID: s.googleClientID)
        reload()
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
    public func update(_ job: Job) {
        var j = job
        j.updated = Date()
        if let i = jobs.firstIndex(where: { $0.id == j.id }) { jobs[i] = j } else { jobs.insert(j, at: 0) }
        pendingSave[j.id]?.cancel()
        let snapshot = j
        pendingSave[j.id] = Task { [store, snapshot] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            try? store.save(snapshot)
        }
        onChange?()
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

    /// A job changed on another device; replaces the local copy as is.
    /// Photo files don't travel with it — the editor downloads them from Drive (`fetchMissingPhotos`).
    public func applyRemote(_ job: Job) {
        pendingSave[job.id]?.cancel(); pendingSave[job.id] = nil
        if let i = jobs.firstIndex(where: { $0.id == job.id }) { jobs[i] = job } else { jobs.insert(job, at: 0) }
        try? store.save(job)
    }

    /// A job deleted on another device.
    public func removeRemote(_ id: UUID) {
        pendingSave[id]?.cancel(); pendingSave[id] = nil
        try? store.delete(id)
        jobs.removeAll { $0.id == id }
    }

    // MARK: photos

    /// Scales a picked or captured image to at most `maxSide` px and stores it as JPEG (PNG for signatures).
    public func addPhoto(_ image: UIImage, to job: UUID, maxSide: CGFloat = 1600, png: Bool = false) -> Photo? {
        let img = image.scaled(maxSide: maxSide, opaque: !png)
        guard let data = png ? img.pngData() : img.jpegData(compressionQuality: 0.8) else { return nil }
        let px = CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
        return try? store.addPhoto(data, width: Int(px.width), height: Int(px.height), png: png, to: job)
    }

    public func image(_ p: Photo, in job: UUID) -> UIImage? {
        _ = photoRevision  // views showing an empty frame look again once a download lands
        let key = "\(job.uuidString)/\(p.fileName)" as NSString
        if let i = cache.object(forKey: key) { return i }
        guard let d = store.data(of: p, in: job), let i = UIImage(data: d) else { return nil }
        cache.setObject(i, forKey: key)
        return i
    }

    // MARK: photos taken on another device

    /// Progress of downloading one job's missing photos from Drive.
    public struct PhotoFetch: Equatable, Sendable {
        public var total = 0, done = 0, failed = 0
        public var error: String?
        public var running: Bool { done + failed < total }
    }
    public private(set) var photoFetch: [UUID: PhotoFetch] = [:]
    private var photoRevision = 0

    /// Photos the job refers to whose files aren't on this device (taken on another iPad).
    public func missingPhotos(_ job: Job) -> [Photo] { job.allPhotos.filter { !store.hasPhoto($0, in: job.id) } }

    /// The missing photos that the device which took them already saved to Drive, with their Drive file ids.
    public func downloadablePhotos(_ job: Job) -> [(photo: Photo, fileID: String)] {
        let files = job.drive?.photoFiles ?? [:]
        return missingPhotos(job).compactMap { p in files[p.id.uuidString].map { (p, $0) } }
    }

    /// Downloads the job's missing photos from its Drive folder, four at a time. Does nothing while signed out.
    public func fetchMissingPhotos(_ id: UUID) async {
        guard photoFetch[id]?.running != true, google.isSignedIn, let job = job(id) else { return }
        let todo = downloadablePhotos(job)
        guard !todo.isEmpty else { return }
        photoFetch[id] = PhotoFetch(total: todo.count)
        let client = DriveClient(tokens: google), store = self.store
        await withTaskGroup(of: String?.self) { group in
            var next = todo.makeIterator()
            func start() -> Bool {
                guard let (p, fileID) = next.next() else { return false }
                group.addTask {
                    do { try store.writePhoto(try await client.download(fileID), for: p, in: id); return nil }
                    catch { return error.localizedDescription }
                }
                return true
            }
            for _ in 0..<4 { if !start() { break } }
            for await failure in group {
                if let failure { photoFetch[id]?.failed += 1; photoFetch[id]?.error = failure }
                else { photoFetch[id]?.done += 1; photoRevision += 1 }
                _ = start()
            }
        }
    }

    /// Satellite picture centred on the job's GPS, stored like any other photo.
    public func mapPhoto(gps: String, for job: UUID) async throws -> Photo {
        let img = try await MapImage.fetch(gps: gps, zoom: settings.mapZoom, googleKey: settings.googleMapsKey)
        guard let p = addPhoto(img, to: job, maxSide: 1600) else { throw MapImage.Failure.badResponse("บันทึกภาพไม่ได้") }
        return p
    }

    // MARK: exports

    public struct ExportFile: Identifiable { public let id = UUID(); public let url: URL; public let summary: String }

    private func tempURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
    static func safeName(_ s: String) -> String { s.replacingOccurrences(of: "[/\\\\:*?\"<>|]", with: "-", options: .regularExpression) }
    func baseName(_ j: Job) -> String { Self.safeName("แบบสำรวจ NO.\(j.docNo.isEmpty ? "-" : j.docNo) \(j.projectName)".trimmingCharacters(in: .whitespaces)) }

    func excelData(_ job: Job) throws -> ExcelExporter.Result {
        let store = self.store
        return try ExcelExporter().export(job, photoData: { store.data(of: $0, in: job.id) }, planImage: { m in
            guard let sk = Drawings.plan(m.values, tank: m.type == .tank, width: 1100), let r = PDFRenderer.png(sk, scale: 1.5) else { return nil }
            return ExcelImage(data: r.0, width: r.1, height: r.2, isPNG: true)
        }, siteMapImage: markedSiteMap(job))
    }

    /// The site picture with its symbols drawn in, for the Excel frame (the PDF draws them as vectors).
    func markedSiteMap(_ job: Job) -> ExcelImage? {
        let marks = job.values.marks("siteMarks")
        guard !marks.isEmpty, let p = job.values.photo("siteMap"), let img = image(p, in: job.id) else { return nil }
        let base = img.scaled(maxSide: 1600)
        let pic = base.size
        // legend strip below the picture, scaled to the picture's width
        let kinds = SiteMarks.usedKinds(marks), fs = max(9, Double(pic.width) * 0.014)
        let lh = SiteMarks.legendHeight(kinds, width: Double(pic.width), size: fs)
        let size = CGSize(width: pic.width, height: pic.height + CGFloat(lh))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let out = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            base.draw(in: CGRect(origin: .zero, size: pic))
            PDFRenderer.draw(SiteMarks.ops(marks, in: Box(0, 0, Double(pic.width), Double(pic.height))), in: ctx.cgContext, photo: { _ in nil })
            PDFRenderer.draw(SiteMarks.legend(kinds, in: Box(0, Double(pic.height), Double(pic.width), lh), size: fs), in: ctx.cgContext, photo: { _ in nil })
        }
        guard let data = out.jpegData(compressionQuality: 0.85) else { return nil }
        return ExcelImage(data: data, width: Int(size.width), height: Int(size.height), isPNG: false)
    }

    public func exportExcel(_ job: Job) throws -> ExportFile {
        flush(job.id)
        let r = try excelData(job)
        let url = tempURL(baseName(job) + ".xlsx")
        try r.data.write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "Excel \(r.sheets.count) แผ่น · \(r.pictures) รูป")
    }

    var reportHeader: ReportHeader { ReportHeader(company: settings.company) }

    public func pdfData(_ job: Job) -> Data {
        PDFRenderer.render(job: job, header: reportHeader, photo: { [weak self] p in self?.image(p, in: job.id) })
    }

    public func exportSummaryPDF(_ job: Job) throws -> ExportFile {
        flush(job.id)
        let url = tempURL("สรุป " + baseName(job) + ".pdf")
        try PDFRenderer.renderSummary(job: job, header: reportHeader, photo: { [weak self] p in self?.image(p, in: job.id) }).write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "PDF สรุป 1 หน้า")
    }

    public func exportPDF(_ job: Job) throws -> ExportFile {
        flush(job.id)
        let url = tempURL(baseName(job) + ".pdf")
        try pdfData(job).write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "รายงาน PDF")
    }

    public func exportBackup(_ ids: [UUID]? = nil) throws -> ExportFile {
        let list = ids.map { set in jobs.filter { set.contains($0.id) } } ?? jobs
        let url = tempURL("solar-survey-backup-\(ISODate.string(Date())).json")
        try WebBackup.exportBackup(list, store: store).write(to: url, options: .atomic)
        return ExportFile(url: url, summary: "สำรองข้อมูล \(list.count) งาน")
    }

    /// Imports a backup or survey-data file (from this app or the web version).
    public func importFile(_ url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let imported = try WebBackup.importJobs(Data(contentsOf: url), into: store)
        reload()
        return imported.count
    }

    // MARK: Google Drive

    public var drive: DriveSync { DriveSync(client: DriveClient(tokens: google), rootName: settings.driveRoot) }

    public func saveToDrive(_ job: Job, kinds: [DriveSync.Kind], photos: Bool = false,
                            progress: @escaping @Sendable (DriveSync.Step) -> Void) async throws -> [DriveFile] {
        flush(job.id)
        let excel = try kinds.contains(.xlsx) ? excelData(job).data : Data()
        let pdf = kinds.contains(.pdf) ? pdfData(job) : Data()
        let json = try kinds.contains(.json) ? WebBackup.exportDriveData(job, store: store) : Data()
        let store = self.store, id = job.id
        do {
            let (link, files) = try await drive.save(job, kinds: kinds, build: { k in k == .xlsx ? excel : k == .pdf ? pdf : json },
                                                     photos: photos ? job.photoFolders : [], photoData: { store.data(of: $0, in: id) },
                                                     progress: progress)
            keepLink(link, for: id)
            return files
        } catch let e as DriveSync.Interrupted {
            // remember the photos that did upload so a retry sends only the rest
            keepLink(e.link, for: id)
            throw e
        }
    }

    private func keepLink(_ link: DriveLink, for id: UUID) {
        if var j = self.job(id) { j.drive = link; update(j); flush(j.id) }
    }

    public func openFromDrive(_ file: DriveFile) async throws -> Job {
        let j = try await drive.open(file, into: store)
        reload()
        return j
    }
}

public struct SurveySettings: Codable, Equatable {
    public var company = "TC Roof"
    public var googleClientID = ""
    public var driveRoot = "Solar Survey Projects"
    public var engineer = ""
    /// Google Maps Static API key; empty = Apple Maps satellite imagery.
    public var googleMapsKey = ""
    /// Map zoom for site pictures: 20 ≈ 90 m across, 19 ≈ 180 m, 18 ≈ 360 m (at latitude 15°).
    public var mapZoom = 20

    public init() {}
    public init(from decoder: Decoder) throws {
        // settings saved by an older version miss the newer keys — keep defaults for those
        let c = try decoder.container(keyedBy: CodingKeys.self)
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? company
        googleClientID = try c.decodeIfPresent(String.self, forKey: .googleClientID) ?? googleClientID
        driveRoot = try c.decodeIfPresent(String.self, forKey: .driveRoot) ?? driveRoot
        engineer = try c.decodeIfPresent(String.self, forKey: .engineer) ?? engineer
        googleMapsKey = try c.decodeIfPresent(String.self, forKey: .googleMapsKey) ?? googleMapsKey
        mapZoom = try c.decodeIfPresent(Int.self, forKey: .mapZoom) ?? mapZoom
    }
    static let key = "solarSurvey.settings"
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
