import XCTest
@testable import TCRoofCore

final class TCRoofCoreTests: XCTestCase {
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

    /// Station template: A1–A4, B1–B5, C1, E1 in workbook order; the first unfinished step is "current".
    func testSteps() {
        var j = Job.new(template: JobTemplate.all[0])
        XCTAssertEqual(j.steps.map(\.code), ["A1", "A2", "A3", "A4", "B1", "B2", "B3", "B4", "B5", "C1", "E1"])
        XCTAssertEqual(j.nextStep?.page, .info)
        XCTAssertEqual(j.stepStatuses.first?.status, .current)
        // fill every required A1 field: A2 becomes current, A1 complete
        for f in Schema.info.fields where f.isRequired(j.values) { j.values[f.id] = .text("1") }
        XCTAssertEqual(j.nextStep?.page, .site)
        XCTAssertEqual(j.stepStatuses.map(\.status).prefix(3), [.complete, .current, .notStarted])
        // a section started but short shows as missing
        let roof = j.modules.last!.spec.groups.flatMap(\.fields).first { $0.isRequired(j.modules.last!.values) }!
        j.modules[j.modules.count - 1].values[roof.id] = .text("1")
        XCTAssertEqual(j.stepStatuses.first { $0.step.code == "C1" }?.status, .missing)
    }

    /// Unsaved until a Drive save is newer than the last edit.
    func testNeedsDriveSave() {
        var j = Job.new(template: JobTemplate.all[1])
        XCTAssertTrue(j.needsDriveSave)
        var link = DriveLink(); link.folderID = "f"
        j.drive = link
        XCTAssertTrue(j.needsDriveSave, "photos uploaded but no save yet")
        j.drive?.lastSaved = j.updated.addingTimeInterval(1)
        XCTAssertFalse(j.needsDriveSave)
        j.updated = j.updated.addingTimeInterval(2)
        XCTAssertTrue(j.needsDriveSave)
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

    /// A1's ground-area count and map zoom aren't schema fields but must survive a backup and restore.
    func testBackupKeepsExtraCoverKeys() throws {
        var j = Job.new(template: JobTemplate.all[2])
        j.values["groundAreas"] = .text("2"); j.values["mapZoom"] = .text("18")
        let s = tmpStore()
        let back = try WebBackup.importJobs(WebBackup.exportBackup([j], store: s), into: tmpStore())[0]
        XCTAssertEqual(back.values.text("groundAreas"), "2")
        XCTAssertEqual(back.values.text("mapZoom"), "18")
        // a backup without them leaves them unset rather than empty
        let plain = try WebBackup.importJobs(WebBackup.exportBackup([Job.new(template: JobTemplate.all[2])], store: s), into: tmpStore())[0]
        XCTAssertNil(plain.values["groundAreas"])
    }

    func testHelpers() {
        XCTAssertEqual(parseSpans("1.5, 4,4/4"), [1.5, 4, 4, 4])
        XCTAssertEqual(fmt(4), "4"); XCTAssertEqual(fmt(1.50), "1.5")
        XCTAssertEqual(ISODate.thai("2026-09-28"), "28/9/2569")
    }

    /// job.json written before stages existed has no "stage" or "install" key: it opens as a survey.
    func testDecodeJobWithoutStage() throws {
        let old = """
        {"created":780000000,"drive":{"folderID":"f1"},"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","jobSyncID":"tc-12",
         "modules":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"","type":"roof","values":{"storage":{}}}],
         "updated":780000100,"values":{"storage":{"projectName":{"text":{"_0":"การประปาทดสอบ"}}}}}
        """
        let j = try JobStore.decoder.decode(Job.self, from: Data(old.utf8))
        XCTAssertEqual(j.stage, .survey)
        XCTAssertNil(j.install)
        XCTAssertEqual(j.projectName, "การประปาทดสอบ")
        XCTAssertEqual(j.modules.first?.type, .roof)
        XCTAssertEqual(j.drive?.folderID, "f1")
        XCTAssertEqual(j.jobSyncID, "tc-12")
        // saved again, the stage travels with it
        var moved = j; moved.stage = .install; moved.install = InstallInfo(doneSteps: 3, currentFraction: 0.5, team: "TCR02", movedAt: Date(timeIntervalSinceReferenceDate: 0))
        let back = try JobStore.decoder.decode(Job.self, from: JobStore.encoder.encode(moved))
        XCTAssertEqual(back, moved)
    }

    /// Only a complete survey moves to installation; a copy of it starts over as a survey.
    func testMoveToInstall() throws {
        var j = Job.new(template: JobTemplate.all[2])
        XCTAssertFalse(j.moveToInstall())
        XCTAssertEqual(j.stage, .survey)
        for g in Schema.jobGroups { for f in g.fields where f.isRequired(j.values) { j.values[f.id] = .text("1") } }
        XCTAssertTrue(j.completion.isComplete)
        XCTAssertTrue(j.moveToInstall())
        XCTAssertEqual(j.stage, .install)
        XCTAssertEqual(j.install?.doneSteps, 0)
        XCTAssertFalse(j.moveToInstall())
        XCTAssertEqual(InstallInfo(doneSteps: 3, currentFraction: 0.5).percent, 50)
        XCTAssertEqual(InstallInfo(doneSteps: 3).currentStep, "เดินสาย DC · ตู้ DC")
        XCTAssertEqual(InstallInfo(doneSteps: 7, currentFraction: 0.5).percent, 100)
        // Drive data / backups keep the stage
        let s = tmpStore()
        j.install?.team = "TCR02"
        let back = try WebBackup.importJobs(WebBackup.exportBackup([j], store: s), into: tmpStore())[0]
        XCTAssertEqual(back.stage, .install)
        XCTAssertEqual(back.install?.team, "TCR02")
        XCTAssertEqual(try s.duplicate(j).stage, .survey)
    }

    /// Moving back undoes the move: the survey is editable again and the installation progress is gone.
    func testMoveBackToSurvey() {
        var j = Job.new(template: JobTemplate.all[2])
        XCTAssertFalse(j.moveBackToSurvey())
        for g in Schema.jobGroups { for f in g.fields where f.isRequired(j.values) { j.values[f.id] = .text("1") } }
        XCTAssertTrue(j.moveToInstall())
        j.install?.doneSteps = 2; j.install?.team = "TCR02"
        XCTAssertTrue(j.moveBackToSurvey())
        XCTAssertEqual(j.stage, .survey)
        XCTAssertNil(j.install)
        XCTAssertTrue(j.canMoveToInstall)
    }
}
