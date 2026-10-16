import XCTest
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DriveSync
@testable import TCRoofCore

/// Fake Drive: remembers folders and files in memory.
final class FakeDrive: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var items: [[String: Any]] = []
    nonisolated(unsafe) static var log: [String] = []
    /// Ids never repeat, even after a test removes an item.
    nonisolated(unsafe) static var made = 0
    /// Answers every metadata request with this status (a 500 for a Drive hiccup), when set.
    nonisolated(unsafe) static var metadataStatus: Int?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    static func body(_ r: URLRequest) -> Data {
        if let b = r.httpBody { return b }
        guard let s = r.httpBodyStream else { return Data() }
        s.open(); defer { s.close() }
        var d = Data(); var buf = [UInt8](repeating: 0, count: 65536)
        while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
        return d
    }
    override func startLoading() {
        let r = request, url = r.url!, comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let method = r.httpMethod ?? "GET"
        Self.log.append("\(method) \(url.path)")
        var out: Any = [:]
        if method == "GET", url.path.hasSuffix("/files") {
            let q = comps.queryItems?.first { $0.name == "q" }?.value ?? ""
            out = ["files": Self.items.filter { i in
                if q.contains("survey-data") { return (i["name"] as! String).contains("survey-data") }
                return q.contains("name = '\(i["name"] as! String)'") && q.contains("'\(i["parent"] as! String)' in parents")
            }]
        } else if method == "GET", comps.queryItems?.contains(where: { $0.name == "alt" }) == true {
            let id = url.lastPathComponent
            out = Self.items.first { $0["id"] as? String == id }?["data"] as? Data ?? Data()
        } else if method == "GET", let status = Self.metadataStatus {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self); return
        } else if method == "GET" {
            let id = url.lastPathComponent
            out = Self.items.first { $0["id"] as? String == id } ?? [:]
            if (out as! [String: Any]).isEmpty { client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data("{}".utf8)); client?.urlProtocolDidFinishLoading(self); return }
        } else {
            let body = Self.body(r)
            var name = "", parent = "", mime = "", data = Data()
            if url.path.contains("/upload/") {
                let s = String(decoding: body, as: UTF8.self)
                let meta = s.components(separatedBy: "\r\n\r\n")[1].components(separatedBy: "\r\n--")[0]
                let m = try! JSONSerialization.jsonObject(with: Data(meta.utf8)) as! [String: Any]
                name = m["name"] as! String; parent = (m["parents"] as! [String])[0]; mime = m["mimeType"] as! String
                let parts = body.split(separator: Data("\r\n\r\n".utf8))
                _ = parts
                if let r1 = body.range(of: Data("Content-Type: \(mime)\r\n\r\n".utf8), options: [], in: body.index(body.startIndex, offsetBy: 10)..<body.endIndex),
                   let r2 = body.range(of: Data("\r\n--survey-".utf8), options: .backwards) { data = body[r1.upperBound..<r2.lowerBound] }
            } else {
                let m = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
                name = m["name"] as! String; parent = (m["parents"] as! [String])[0]; mime = m["mimeType"] as! String
            }
            Self.made += 1
            var item: [String: Any] = ["id": "id\(Self.made)", "name": name, "mimeType": mime, "parent": parent, "data": data]
            if url.path.contains("/upload/") { item["md5Checksum"] = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined() }
            Self.items.append(item); out = item
        }
        var json = out
        if var d = json as? [String: Any] { d.removeValue(forKey: "data"); d.removeValue(forKey: "parent"); json = d }
        if var d = json as? [String: [[String: Any]]] { d["files"] = d["files"]!.map { var x = $0; x.removeValue(forKey: "data"); x.removeValue(forKey: "parent"); return x }; json = d }
        let data = (json as? Data) ?? (try! JSONSerialization.data(withJSONObject: json))
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

struct FixedToken: DriveTokenProvider { func accessToken() async throws -> String { "t" } }

final class DriveSyncTests: XCTestCase {
    /// Each test starts on an empty Drive: the tests look items up by name.
    override func setUp() { FakeDrive.items = []; FakeDrive.metadataStatus = nil }

    func testSaveAndOpen() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FakeDrive.self]
        let sync = DriveSync(client: DriveClient(tokens: FixedToken(), session: URLSession(configuration: cfg)))
        let store = JobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("dr-" + UUID().uuidString))
        var job = Job.new(template: JobTemplate.all[1])
        job.values["docNo"] = .text("215"); job.values["projectName"] = .text("สถานีทดสอบ")
        try store.save(job)
        let json = try WebBackup.exportDriveData(job, store: store)
        let (link, files) = try await sync.save(job, kinds: [.json, .pdf], build: { k in k == .json ? json : Data("%PDF".utf8) })
        XCTAssertEqual(link.folderName, "NO.215 สถานีทดสอบ")
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files[0].name.hasPrefix("survey-data NO.215 "))
        job.drive = link
        // second save reuses the folders
        let before = FakeDrive.items.filter { $0["mimeType"] as? String == DriveClient.folderMime }.count
        _ = try await sync.save(job, kinds: [.json], build: { _ in json })
        XCTAssertEqual(FakeDrive.items.filter { $0["mimeType"] as? String == DriveClient.folderMime }.count, before)
        // open on "another iPad"
        let saves = try await sync.listSaves()
        XCTAssertEqual(saves.count, 2)
        let other = JobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("dr2-" + UUID().uuidString))
        let opened = try await sync.open(saves[0], into: other)
        XCTAssertEqual(opened.projectName, "สถานีทดสอบ")
        XCTAssertEqual(opened.id, job.id)
    }

    func testPhotosGoToSectionFoldersOnce() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FakeDrive.self]
        let sync = DriveSync(client: DriveClient(tokens: FixedToken(), session: URLSession(configuration: cfg)))
        var job = Job.new(template: JobTemplate.all[1])
        job.values["docNo"] = .text("301"); job.values["projectName"] = .text("รูปทดสอบ")
        job.values["siteMap"] = .photo(Photo(fileName: "a.jpg", width: 10, height: 10))
        job.values["surveyorSign"] = .photo(Photo(fileName: "s.png", width: 10, height: 10))
        let folders = job.photoFolders
        XCTAssertEqual(folders.map(\.name), ["A2 ภาพสถานที่ติดตั้ง"], "signatures stay out of the photo folders")
        XCTAssertTrue(folders[0].photos[0].fileName.hasPrefix("01 ภาพสถานที่ติดตั้ง"))

        let (link, _) = try await sync.save(job, kinds: [], build: { _ in Data() }, photos: folders, photoData: { _ in Data("jpg".utf8) })
        XCTAssertNotNil(link.photosFolderID)
        XCTAssertEqual(link.photoFiles?.count, 1)
        let photoFolder = FakeDrive.items.first { $0["id"] as? String == link.photosFolderID }
        XCTAssertEqual(photoFolder?["name"] as? String, "รูปภาพ")
        XCTAssertEqual(photoFolder?["parent"] as? String, link.folderID)
        let section = FakeDrive.items.first { $0["name"] as? String == "A2 ภาพสถานที่ติดตั้ง" }
        XCTAssertEqual(section?["parent"] as? String, link.photosFolderID)

        // a second save sends only the photo added since
        job.drive = link
        job.values["siteMap"] = .photo(folders[0].photos[0].photo)
        job.modules[0].values["photos"] = .photos([Photo(fileName: "b.jpg", width: 10, height: 10)])
        let uploadsBefore = FakeDrive.log.filter { $0.contains("/upload/") }.count
        let steps = StepLog()
        let (again, _) = try await sync.save(job, kinds: [], build: { _ in Data() }, photos: job.photoFolders,
                                             photoData: { _ in Data("jpg".utf8) }, progress: { steps.add($0) })
        let sent = FakeDrive.log.filter { $0.contains("/upload/") }.count - uploadsBefore
        XCTAssertEqual(again.photosFolderID, link.photosFolderID)
        XCTAssertEqual(sent, again.photoFiles!.count - 1)
        XCTAssertEqual(steps.lastTotal, sent)
    }
}

extension DriveSyncTests {
    /// Issued REV files go to REV/ inside the job folder, each once; a REV folder that is gone is made and filled again.
    func testRevisionsGoToTheRevFolderOnce() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FakeDrive.self]
        let sync = DriveSync(client: DriveClient(tokens: FixedToken(), session: URLSession(configuration: cfg)))
        var job = Job.new(template: JobTemplate.all[1])
        job.values["docNo"] = .text("402"); job.values["projectName"] = .text("REV ทดสอบ")
        let rev00 = [DriveSync.RevisionUpload(key: "REV00.pdf", name: "REV00 a.pdf"), DriveSync.RevisionUpload(key: "REV00.json", name: "REV00 a.json")]
        let data: @Sendable (DriveSync.RevisionUpload) -> Data? = { Data($0.key.utf8) }

        let link = try await sync.syncPhotos(job, photos: [], photoData: { _ in nil }, revisions: rev00, revisionData: data)
        let folder = FakeDrive.items.first { $0["id"] as? String == link.revisionsFolderID }
        XCTAssertEqual(folder?["name"] as? String, "REV")
        XCTAssertEqual(folder?["parent"] as? String, link.folderID)
        XCTAssertEqual(Set(link.revisionFiles?.keys ?? [:].keys), ["REV00.pdf", "REV00.json"])
        let pdf = FakeDrive.items.first { $0["id"] as? String == link.revisionFiles?["REV00.pdf"] }
        XCTAssertEqual(pdf?["mimeType"] as? String, "application/pdf")
        XCTAssertEqual(pdf?["parent"] as? String, link.revisionsFolderID)

        // the next save sends only REV 01, and a file the device doesn't have is skipped
        job.drive = link
        let rev01 = rev00 + [DriveSync.RevisionUpload(key: "REV01.pdf", name: "REV01 a.pdf"), DriveSync.RevisionUpload(key: "REV01.json", name: "gone")]
        let before = FakeDrive.log.filter { $0.contains("/upload/") }.count
        let (again, _) = try await sync.save(job, kinds: [], build: { _ in Data() }, revisions: rev01,
                                             revisionData: { $0.name == "gone" ? nil : Data($0.key.utf8) })
        XCTAssertEqual(FakeDrive.log.filter { $0.contains("/upload/") }.count - before, 1)
        XCTAssertEqual(again.revisionsFolderID, link.revisionsFolderID)
        XCTAssertEqual(again.revisionFiles?.count, 3)

        // REV folder deleted on Drive: made again and every file sent again
        FakeDrive.items.removeAll { $0["id"] as? String == again.revisionsFolderID }
        job.drive = again
        let refilled = try await sync.syncPhotos(job, photos: [], photoData: { _ in nil }, revisions: rev00, revisionData: data)
        XCTAssertNotEqual(refilled.revisionsFolderID, again.revisionsFolderID)
        XCTAssertEqual(refilled.revisionFiles?.count, 2)
    }
}

extension DriveSyncTests {
    /// A file already in the folder with the same name and content is reused; another content is uploaded.
    func testUploadOnceReusesTheSameFile() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FakeDrive.self]
        let client = DriveClient(tokens: FixedToken(), session: URLSession(configuration: cfg))
        let folder = try await client.ensureFolder("ครั้งเดียว", parent: "root")
        let uploads = { FakeDrive.log.filter { $0.contains("/upload/") }.count }
        let before = uploads()
        let first = try await client.uploadOnce(Data("jpg-1".utf8), name: "a.jpg", mimeType: "image/jpeg", parent: folder.id)
        let again = try await client.uploadOnce(Data("jpg-1".utf8), name: "a.jpg", mimeType: "image/jpeg", parent: folder.id)
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(uploads() - before, 1)
        let other = try await client.uploadOnce(Data("jpg-2".utf8), name: "a.jpg", mimeType: "image/jpeg", parent: folder.id)
        XCTAssertNotEqual(other.id, first.id, "a different photo of the same name still goes up")
        XCTAssertEqual(uploads() - before, 2)
    }

    /// A Drive hiccup never passes for a deleted photo folder, and a stale list of sent photos sends none twice.
    func testPhotosAreNeverSentTwice() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FakeDrive.self]
        let sync = DriveSync(client: DriveClient(tokens: FixedToken(), session: URLSession(configuration: cfg)))
        var job = Job.new(template: JobTemplate.all[1])
        job.values["docNo"] = .text("303"); job.values["projectName"] = .text("ไม่ซ้ำ")
        job.values["siteMap"] = .photo(Photo(fileName: "a.jpg", width: 10, height: 10))
        let photo: @Sendable (Photo) -> Data? = { Data("jpg-\($0.id)".utf8) }
        let link = try await sync.syncPhotos(job, photos: job.photoFolders, photoData: photo, revisions: [], revisionData: { _ in nil })
        XCTAssertEqual(link.photoFiles?.count, 1)
        let uploads = { FakeDrive.log.filter { $0.contains("/upload/") }.count }

        // the folder check fails: the save stops instead of starting the photos over
        job.drive = link
        let before = uploads()
        FakeDrive.metadataStatus = 500
        defer { FakeDrive.metadataStatus = nil }
        do {
            _ = try await sync.syncPhotos(job, photos: job.photoFolders, photoData: photo, revisions: [], revisionData: { _ in nil })
            XCTFail("a failed folder check stops the upload")
        } catch {}
        FakeDrive.metadataStatus = nil
        XCTAssertEqual(uploads(), before)

        // another device's copy of the job lacks the photo: Drive's file is found and reused
        var stale = link; stale.photoFiles = [:]
        job.drive = stale
        let again = try await sync.syncPhotos(job, photos: job.photoFolders, photoData: photo, revisions: [], revisionData: { _ in nil })
        XCTAssertEqual(uploads(), before)
        XCTAssertEqual(again.photoFiles, link.photoFiles)
    }
}

final class StepLog: @unchecked Sendable {
    private var totals: [Int] = []
    func add(_ s: DriveSync.Step) { if case .photos(_, let t) = s { totals.append(t) } }
    var lastTotal: Int? { totals.last }
}
