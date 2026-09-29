import XCTest
@testable import SurveyCore

final class SurveyCoreTests: XCTestCase {
    func tmpStore() -> JobStore {
        JobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("ss-" + UUID().uuidString))
    }

    /// A job synced from another iPad refers to photos whose files aren't here until they are downloaded.
    func testPhotoFromAnotherDevice() throws {
        let store = tmpStore(), job = UUID()
        let p = Photo(fileName: UUID().uuidString + ".jpg", width: 10, height: 10)
        XCTAssertFalse(store.hasPhoto(p, in: job))
        XCTAssertNil(store.data(of: p, in: job))
        try store.writePhoto(Data([1, 2, 3]), for: p, in: job)
        XCTAssertTrue(store.hasPhoto(p, in: job))
        XCTAssertEqual(store.data(of: p, in: job), Data([1, 2, 3]))
    }

    /// Signatures stay out of the photo folders but still go to Drive, so another iPad can draw them in the report.
    func testDriveFoldersIncludeSignatures() {
        var j = Job.new(template: JobTemplate.all[0])
        let sign = Photo(fileName: "s.png", width: 10, height: 10)
        j.values["surveyorSign"] = .photo(sign)
        XCTAssertFalse(j.photoFolders.flatMap(\.photos).contains { $0.photo.id == sign.id })
        let folder = j.driveFolders.last
        XCTAssertEqual(folder?.name, "ลายเซ็น")
        XCTAssertEqual(folder?.photos.map(\.photo.id), [sign.id])
        XCTAssertEqual(folder?.photos.first?.fileName, "01 ลายเซ็น.png")
    }

    func testNewJobAndProgress() throws {
        var j = Job.new(template: JobTemplate.all[0])
        XCTAssertEqual(j.modules.map(\.type), [.panel, .inverter, .water, .backfeed, .fts, .roof])
        let before = j.completion
        XCTAssertGreaterThan(before.total, 40)
        j.values["docNo"] = .text("215")
        XCTAssertEqual(j.completion.filled, before.filled + 1)
        // conditional field appears only when chosen
        var m = SurveyModule(type: .backfeed)
        let t0 = m.completion.total
        m.values["level"] = .choice("กันย้อนที่แรงสูง", other: "")
        XCTAssertEqual(m.completion.total, t0 + 1)
    }

    func testStoreRoundTrip() throws {
        let s = tmpStore()
        var j = Job.new(template: JobTemplate.all[1])
        let p = try s.addPhoto(Data([0xFF, 0xD8, 0xFF, 0xD9]), width: 10, height: 20, to: j.id)
        j.modules[0].values["aerialPhoto"] = .photo(p)
        j.values["gps"] = .text("17.0, 99.8")
        try s.save(j)
        let loaded = try XCTUnwrap(s.load(j.id))
        XCTAssertEqual(loaded, j)
        let dup = try s.duplicate(j)
        XCTAssertNotNil(s.data(of: p, in: dup.id))
        XCTAssertEqual(s.loadAll().count, 2)
        j.modules[0].values["aerialPhoto"] = nil
        XCTAssertEqual(s.purgeUnusedPhotos(of: j), 1)
    }

    func testJobLinkSurvivesStoreAndDriveData() throws {
        let s = tmpStore()
        var j = Job.new(template: JobTemplate.all[1])
        j.jobSyncID = "tc-job-42"
        try s.save(j)
        XCTAssertEqual(s.loadAll().first { $0.id == j.id }?.jobSyncID, "tc-job-42")
        // survey-data files opened on another iPad keep the link too
        let other = tmpStore()
        let back = try WebBackup.importJobs(WebBackup.exportDriveData(j, store: s), into: other)
        XCTAssertEqual(back.first?.jobSyncID, "tc-job-42")
        // reports saved before linking existed decode as unlinked
        var plain = j; plain.jobSyncID = nil
        let json = try JSONSerialization.jsonObject(with: JobStore.encoder.encode(plain)) as! [String: Any]
        XCTAssertNil(json["jobSyncID"])
        XCTAssertNil(try JobStore.decoder.decode(Job.self, from: JSONSerialization.data(withJSONObject: json)).jobSyncID)
    }

    func testWebImportExport() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../ExcelExportTests/Fixtures/job215.json")
        let s = tmpStore()
        let jobs = try WebBackup.importJobs(Data(contentsOf: url), into: s)
        XCTAssertEqual(jobs.count, 1)
        let j = jobs[0]
        XCTAssertEqual(j.docNo, "215")
        XCTAssertEqual(j.values.choice("verdict"), "ติดตั้งได้ (มีเงื่อนไข)")
        XCTAssertEqual(j.values.transformers("trafos").first?.kva, "800")
        XCTAssertGreaterThan(j.photoCount, 20)
        XCTAssertEqual(j.values.photo("siteMap")?.width, 1299)
        // re-import gives the same ids
        let again = try WebBackup.importJobs(Data(contentsOf: url), into: s)
        XCTAssertEqual(again[0].id, j.id)
        // export → import again preserves values
        let data = try WebBackup.exportBackup([j], store: s)
        let s2 = tmpStore()
        let back = try WebBackup.importJobs(data, into: s2)[0]
        XCTAssertEqual(back.id, j.id)
        XCTAssertEqual(back.modules.count, j.modules.count)
        XCTAssertEqual(back.photoCount, j.photoCount)
        XCTAssertEqual(back.values.text("projectName"), j.values.text("projectName"))
    }

    func testHelpers() {
        XCTAssertEqual(parseSpans("1.5, 4,4/4"), [1.5, 4, 4, 4])
        XCTAssertEqual(fmt(4), "4"); XCTAssertEqual(fmt(1.50), "1.5")
        XCTAssertEqual(ISODate.thai("2026-09-28"), "28/9/2569")
    }
}
