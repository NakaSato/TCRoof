import XCTest
@testable import TCRoofCore

/// docs/specs/review-lock-revisions-swift.md §6: photo slots, REV diff, hash, revisions on disk and the lock.
final class ReviewLockTests: XCTestCase {
    func tmpStore() -> JobStore {
        JobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("rl-" + UUID().uuidString))
    }
    func photo(_ name: String = UUID().uuidString, png: Bool = false) -> Photo {
        Photo(fileName: name + (png ? ".png" : ".jpg"), width: 10, height: 10)
    }
    func station() -> Job { Job.new(template: JobTemplate.all[0], now: Date(timeIntervalSince1970: 1_790_000_000)) }
    func roof(_ j: Job) -> Int { j.modules.firstIndex { $0.type == .roof }! }

    // MARK: photo slots

    func testStationSlotGroups() {
        let j = station()
        let groups = j.photoSlots
        XCTAssertEqual(groups.map(\.id), ["A2", "A3", "B1", "B2", "B3", "B4", "B5", "C1", "E1"].filter { id in groups.contains { $0.id == id } })
        XCTAssertEqual(groups.first?.id, "A2")
        XCTAssertEqual(groups.last?.id, "E1")
        // no transformer yet: A3 has only the meter picture
        XCTAssertEqual(groups.first { $0.id == "A3" }?.slots.map(\.fieldID), ["meterPic"])
        XCTAssertEqual(groups.first { $0.id == "E1" }?.slots.map(\.kind), [.signature, .signature])
        XCTAssertEqual(j.missingRequiredPhotos, groups.reduce(0) { $0 + $1.missingRequired })
    }

    func testTransformerPhotosOnlyWhenPresent() {
        var j = station()
        j.values["trafos"] = .transformers([Transformer(kva: "250")])
        let a3 = j.photoSlots.first { $0.id == "A3" }!
        XCTAssertTrue(a3.slots.contains { $0.fieldID == "tr0_plate" && $0.required })
        XCTAssertFalse(a3.slots.contains { $0.fieldID.hasPrefix("tr1_") })
        j.values["trafos"] = .transformers([Transformer(kva: "250"), Transformer(kva: "160")])
        XCTAssertTrue(j.photoSlots.first { $0.id == "A3" }!.slots.contains { $0.fieldID == "tr1_plate" })
    }

    func testRequiredEmptyPhotosGivesOneRedSlot() {
        var j = station()
        let c1 = j.photoSlots.first { $0.id == "C1" }!
        let structs = c1.slots.filter { $0.fieldID == "structPhotos" }
        XCTAssertEqual(structs.map(\.kind), [.photosAdd])
        XCTAssertEqual(structs.filter(\.isMissing).count, 1)
        // one photo in: the photo plus a grey add slot
        j.modules[roof(j)].values["structPhotos"] = .photos([photo()])
        let after = j.photoSlots.first { $0.id == "C1" }!.slots.filter { $0.fieldID == "structPhotos" }
        XCTAssertEqual(after.map(\.kind), [.photosItem, .photosAdd])
        XCTAssertEqual(after.filter(\.isMissing).count, 0)
        // full (max 4): no add slot
        j.modules[roof(j)].values["structPhotos"] = .photos((0..<4).map { _ in photo() })
        XCTAssertFalse(j.photoSlots.first { $0.id == "C1" }!.slots.contains { $0.fieldID == "structPhotos" && $0.kind == .photosAdd })
    }

    func testSetPhotoWritesIntoItsScope() {
        var j = station()
        let c1 = j.photoSlots.first { $0.id == "C1" }!
        let add = c1.slots.first { $0.fieldID == "structPhotos" }!
        let p = photo(), q = photo()
        j.setPhoto(p, slot: add)
        XCTAssertEqual(j.modules[roof(j)].values.photos("structPhotos"), [p])
        XCTAssertTrue(j.values.photos("structPhotos").isEmpty)
        // replace in place
        let item = j.photoSlots.first { $0.id == "C1" }!.slots.first { $0.fieldID == "structPhotos" && $0.kind == .photosItem }!
        j.setPhoto(q, slot: item)
        XCTAssertEqual(j.modules[roof(j)].values.photos("structPhotos"), [q])
        j.removePhoto(slot: j.photoSlots.first { $0.id == "C1" }!.slots.first { $0.photo == q }!)
        XCTAssertTrue(j.modules[roof(j)].values.photos("structPhotos").isEmpty)
        // a cover photo
        let site = j.photoSlots.first { $0.id == "A2" }!.slots.first { $0.fieldID == "siteMap" }!
        j.setPhoto(p, slot: site)
        XCTAssertEqual(j.values.photo("siteMap"), p)
    }

    func testLeftoverPhotosListedLast() {
        var j = station()
        var tr = Transformer(kva: "250")
        var b = Board(name: "SDB1")
        b.photos = [photo()]
        tr.setBoards([Board(name: "MDB1"), b])
        j.values["trafos"] = .transformers([tr])
        let last = j.photoSlots.last!
        XCTAssertEqual(last.id, "อื่นๆ")
        XCTAssertEqual(last.slots.map(\.kind), [.leftover])
        XCTAssertEqual(last.missingRequired, 0)
    }

    // MARK: diff

    func testIdenticalSnapshotsGiveNoRows() {
        let j = station()
        XCTAssertEqual(FormDiff.changes(from: j.snapshot, to: j.snapshot), [])
    }

    func testDiffRows() {
        var a = station()
        a.values["projectName"] = .text("สถานีแพรกหนามแดง")
        a.values["internet"] = .choice("มี", other: "")
        let old = photo(), keep = photo()
        a.values["siteMap"] = .photo(old)
        a.modules[roof(a)].values["structPhotos"] = .photos([keep])
        let ob = Obstacle(label: "V9", x: "1", y: "2", w: "1", h: "1")
        a.modules[roof(a)].values["obst"] = .obstacles([ob])
        var tr = Transformer(kva: "250")
        a.values["trafos"] = .transformers([tr])
        a.values["surveyorSign"] = .photo(photo(png: true))
        let removed = a.modules.first { $0.type == .fts }!

        var b = a
        b.values["projectName"] = .text("สถานีแพรกหนามแดง ")         // whitespace only: no change
        b.values["internet"] = .choice("อื่นๆ", other: "4G")
        b.values["siteMap"] = .photo(photo())
        b.modules[roof(b)].values["structPhotos"] = .photos([keep, photo(), photo()])
        var moved = ob; moved.x = "3"
        b.modules[roof(b)].values["obst"] = .obstacles([moved])
        tr.kva = "500"
        b.values["trafos"] = .transformers([tr])
        b.values["surveyorSign"] = .photo(photo(png: true))       // signatures are not listed
        b.values["rev"] = .text("01"); b.values["date"] = .text("2026-10-09")
        b.modules.removeAll { $0.id == removed.id }
        b.modules.append(SurveyModule(type: .tank))
        b.modules[roof(b)].name = "โรงสูบ"

        let all = FormDiff.changes(from: a.snapshot, to: b.snapshot)
        func rows(_ id: String) -> [FieldChange] { all.filter { $0.fieldID == id } }
        XCTAssertTrue(rows("projectName").isEmpty)
        XCTAssertEqual(rows("internet").map(\.new), ["อื่นๆ: 4G"])
        XCTAssertEqual(rows("siteMap").map(\.kind), [.changed])
        XCTAssertEqual(rows("siteMap").first?.oldPhoto, old)
        XCTAssertEqual(rows("structPhotos").map(\.kind), [.added, .added])
        XCTAssertEqual(rows("obst").map(\.old), ["1x1 ม. @1,2"])
        XCTAssertEqual(rows("obst").map(\.new), ["1x1 ม. @3,2"])
        XCTAssertEqual(rows("trafos").map(\.field), ["หม้อแปลงไฟฟ้าและตู้ MDB (สูงสุด 5 × 6) · TR1"])
        XCTAssertEqual(rows("trafos").map(\.new), ["500 kVA"])
        XCTAssertTrue(rows("surveyorSign").isEmpty)
        XCTAssertTrue(rows("rev").isEmpty && rows("date").isEmpty)
        XCTAssertEqual(all.filter { $0.field.hasPrefix("ลบหัวข้อ") }.count, 1)
        XCTAssertEqual(all.filter { $0.field.hasPrefix("เพิ่มหัวข้อ") }.count, 1)
        XCTAssertEqual(all.filter { $0.field == "ชื่อหัวข้อ" }.map(\.new), ["โรงสูบ"])
        // report order: A pages, sections, E1
        XCTAssertEqual(all.first?.group.prefix(2), "A1")
    }

    func testHiddenFieldIsNoLongerUsed() {
        var a = station()
        a.values["trafos"] = .transformers([Transformer(kva: "250")])
        a.values["tr0_plate"] = .photo(photo())
        var b = a
        b.values["trafos"] = .transformers([])
        let rows = FormDiff.changes(from: a.snapshot, to: b.snapshot).filter { $0.fieldID == "tr0_plate" }
        XCTAssertEqual(rows.map(\.new), ["ไม่ใช้แล้ว"])
    }

    // MARK: hash

    func testHashStableAndSensitive() throws {
        var j = station()
        let p = photo(), s = photo(png: true)
        j.values["siteMap"] = .photo(p)
        j.values["surveyorSign"] = .photo(s)
        var files: [UUID: Data] = [p.id: Data([1, 2, 3]), s.id: Data([9])]
        let h = FormHash.of(j.snapshot) { files[$0.id] }
        XCTAssertNotNil(h)
        // encode / decode round trip and a rebuilt dictionary give the same hash
        let round = try JobStore.decoder.decode(FormSnapshot.self, from: JobStore.encoder.encode(j.snapshot))
        XCTAssertEqual(FormHash.of(round) { files[$0.id] }, h)
        var rebuilt = j.snapshot
        rebuilt.values.storage = Dictionary(uniqueKeysWithValues: j.values.storage.reversed().map { ($0.key, $0.value) })
        XCTAssertEqual(FormHash.of(rebuilt) { files[$0.id] }, h)
        // any value, any photo byte, a signature
        var v = j; v.values["engineer"] = .text("ก")
        XCTAssertNotEqual(FormHash.of(v.snapshot) { files[$0.id] }, h)
        files[p.id] = Data([1, 2, 4])
        XCTAssertNotEqual(FormHash.of(j.snapshot) { files[$0.id] }, h)
        files[p.id] = Data([1, 2, 3]); files[s.id] = Data([8])
        XCTAssertNotEqual(FormHash.of(j.snapshot) { files[$0.id] }, h)
        // a photo not on this device: no hash rather than a wrong one
        XCTAssertNil(FormHash.of(j.snapshot) { $0.id == p.id ? nil : files[$0.id] })
        XCTAssertEqual(FormHash.short("a1b2c3d4e5"), "A1B2-C3D4")
    }

    /// NIST FIPS 180-2 examples: the fallback matches CryptoKit.
    func testPureSHA256() {
        let vectors = [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        ]
        for (msg, hex) in vectors {
            XCTAssertEqual(FormHash.hex(SHA256Pure.hash(Data(msg.utf8))), hex)
            XCTAssertEqual(FormHash.hex(FormHash.sha256(Data(msg.utf8))), hex)
        }
        let million = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
        XCTAssertEqual(FormHash.hex(SHA256Pure.hash(million)), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    // MARK: revisions on disk

    func testSaveRevisionRefusesOverwrite() throws {
        let s = tmpStore(), j = station()
        try s.saveRevision(j.snapshot, rev: "00", job: j.id)
        XCTAssertThrowsError(try s.saveRevision(j.snapshot, rev: "00", job: j.id))
        XCTAssertEqual(s.loadRevision(rev: "00", job: j.id), j.snapshot)
        XCTAssertNil(s.loadRevision(rev: "01", job: j.id))
    }

    /// A REV received from another device is stored as sent, once; garbage is refused.
    func testReceivedRevision() throws {
        let here = tmpStore(), there = tmpStore(), j = station()
        try here.saveRevision(j.snapshot, rev: "00", job: j.id)
        let sent = try XCTUnwrap(here.revisionData(rev: "00", job: j.id))
        try there.saveRevisionData(sent, rev: "00", job: j.id)
        XCTAssertEqual(there.loadRevision(rev: "00", job: j.id), j.snapshot)
        XCTAssertThrowsError(try there.saveRevisionData(sent, rev: "00", job: j.id))
        XCTAssertThrowsError(try there.saveRevisionData(Data("x".utf8), rev: "01", job: j.id))
        XCTAssertNil(there.revisionData(rev: "01", job: j.id))
    }

    func testPurgeKeepsIssuedPhotos() throws {
        let s = tmpStore()
        var j = station()
        let p = try s.addPhoto(Data([1]), width: 1, height: 1, to: j.id)
        j.values["siteMap"] = .photo(p)
        try s.save(j)
        try s.saveRevision(j.snapshot, rev: "00", job: j.id)
        // REV 01 replaces the picture: the REV 00 file stays
        let q = try s.addPhoto(Data([2]), width: 1, height: 1, to: j.id)
        j.values["siteMap"] = .photo(q)
        XCTAssertEqual(s.purgeUnusedPhotos(of: j), 0)
        XCTAssertTrue(s.hasPhoto(p, in: j.id))
    }

    func testDuplicateDropsRevisionsAndSignatures() throws {
        let s = tmpStore()
        var j = station()
        j.values["surveyorSign"] = .photo(photo(png: true))
        j.values["customerSign"] = .photo(photo(png: true))
        j.values["reviewer"] = .text("ผู้ตรวจ")
        j.issue(hash: "abc", pdfFile: nil)
        j.openNextRevision(reason: "แก้", updateDate: false)
        j.issue(hash: "def", pdfFile: nil)
        let copy = try s.duplicate(j)
        XCTAssertNil(copy.revisions); XCTAssertNil(copy.lock); XCTAssertNil(copy.pendingReason)
        XCTAssertEqual(copy.rev, "00")
        XCTAssertFalse(copy.bothSigned)
        XCTAssertEqual(copy.values.text("reviewer"), "ผู้ตรวจ")
    }

    func testNextRevRule() {
        XCTAssertEqual(RevisionRule.next(after: "00"), "01")
        XCTAssertEqual(RevisionRule.next(after: "09"), "10")
        XCTAssertEqual(RevisionRule.next(after: "99"), "100")
        XCTAssertEqual(RevisionRule.next(after: "A"), "A-1")
        XCTAssertEqual(RevisionRule.next(after: "A-1"), "A-2")
        XCTAssertEqual(RevisionRule.next(after: ""), "01")
    }

    // MARK: lock

    func testIssueAndOpenNextRevision() {
        var j = station()
        j.values["engineer"] = .text("วิศวกร ก")
        j.values["reviewer"] = .text("ผู้ตรวจ")
        j.values["surveyorSign"] = .photo(photo(png: true))
        j.values["customerSign"] = .photo(photo(png: true))
        XCTAssertTrue(j.signedUnlocked)
        j.issue(hash: "a1b2c3d4ff", pdfFile: "revisions/REV00.pdf", now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(j.isLocked)
        XCTAssertEqual(j.lock?.rev, "00")
        XCTAssertEqual(j.revisions?.map(\.rev), ["00"])
        XCTAssertEqual(j.revisions?.first?.issuedBy, "วิศวกร ก")
        XCTAssertEqual(j.revisions?.first?.shortCode, "A1B2-C3D4")
        XCTAssertNil(j.previousRevision)

        j.openNextRevision(reason: "สถานีแจ้งขนาดหม้อแปลงใหม่", updateDate: true, now: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertFalse(j.isLocked)
        XCTAssertEqual(j.rev, "01")
        XCTAssertFalse(j.bothSigned)
        XCTAssertNil(j.values.photo("surveyorSign"))
        XCTAssertEqual(j.values.text("reviewer"), "ผู้ตรวจ")
        XCTAssertEqual(j.values.text("date"), ISODate.string(Date(timeIntervalSince1970: 1_790_000_000)))
        XCTAssertEqual(j.previousRevision?.rev, "00")

        j.issue(hash: "ff", pdfFile: nil)
        XCTAssertEqual(j.revisions?.map(\.reason), ["", "สถานีแจ้งขนาดหม้อแปลงใหม่"])
        XCTAssertNil(j.pendingReason)
        XCTAssertEqual(j.previousRevision?.rev, "00")
    }

    func testContentDiffersIgnoresSignatures() {
        var a = station()
        a.values["surveyorSign"] = .photo(photo(png: true))
        var b = a
        b.values["customerSign"] = .photo(photo(png: true))
        XCTAssertFalse(a.contentDiffers(from: b))
        b.values["remarks"] = .text("x")
        XCTAssertTrue(a.contentDiffers(from: b))
        var c = a
        c.modules[0].name = "y"
        XCTAssertTrue(a.contentDiffers(from: c))
    }

    /// A job.json from before this change decodes unlocked, without revisions, and encodes without the new keys.
    func testOldJobDecodes() throws {
        let j = station()
        var obj = try JSONSerialization.jsonObject(with: JobStore.encoder.encode(j)) as! [String: Any]
        XCTAssertNil(obj["lock"]); XCTAssertNil(obj["revisions"]); XCTAssertNil(obj["pendingReason"])
        obj["stage"] = nil
        let old = try JobStore.decoder.decode(Job.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertFalse(old.isLocked)
        XCTAssertNil(old.revisions)
        // and a locked one round-trips
        var locked = j
        locked.issue(hash: "ab", pdfFile: nil)
        XCTAssertEqual(try JobStore.decoder.decode(Job.self, from: JobStore.encoder.encode(locked)), locked)
    }
}
