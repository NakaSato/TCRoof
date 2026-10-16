import XCTest
@testable import TCRoofCore

/// The 7 steps' done rules, their confirmations, the exports and the closing result (`IECReport+Stages`).
final class IECStageTests: XCTestCase {
    func sample() throws -> IECReport {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/iec62446-praek-nam-daeng.json")
        return try IECReport(form: Data(contentsOf: url))
    }

    /// The sample with every reading, photo and record a closed test has (photo ids are made up).
    func complete() throws -> IECReport {
        var r = try sample()
        r.testDate = Date(timeIntervalSinceReferenceDate: 813_000_000); r.tester = "ทีมทดสอบ"
        r.instruments.multimeterClamp = "C1"; r.instruments.insulationTester = "I1"; r.instruments.irradianceMeter = "S1"
        r.module.areaM2 = 2.58
        r.sld = .init(name: "SLD.pdf", version: 1, at: Date(timeIntervalSinceReferenceDate: 812_000_000))
        r.before = .init(ambientC: 34.3, irradianceWm2: 1022, time: "13:00"); r.after = .init(ambientC: 34, irradianceWm2: 1000, time: "13:20")
        r.yrKWhM2Day = 4.24; r.arrayTempC = 59.4; r.irradiancePhoto = "sun"; r.thermalPhotos = ["th1"]
        for i in r.inverters.indices {
            r.inverters[i].continuity = .normal; r.inverters[i].functionalBefore = .normal; r.inverters[i].functionalAfter = .normal
            for n in r.inverters[i].slots.indices where r.inverters[i].slots[n] != nil {
                r.inverters[i].slots[n]?.irPosMOhm = 250; r.inverters[i].slots[n]?.irNegMOhm = 300
                r.inverters[i].slots[n]?.vmpV = 610; r.inverters[i].slots[n]?.impA = 9.5
                for k in IECReport.PhotoKind.allCases { r.inverters[i].slots[n]?.photos[k.rawValue] = "\(i)-\(n)-\(k.rawValue)" }
            }
        }
        return r
    }

    func testTheSampleIsDoneOnlyWhereItHasEverything() throws {
        let r = try sample()
        XCTAssertEqual(r.missing(.setup), ["แบบ SLD", "วันที่ทดสอบ", "ผู้ทดสอบ", "S/N เครื่องมือ"])
        XCTAssertEqual(r.missing(.beforeVoltage), ["รูปแรงดัน / กระแส 24 สตริง"], "Voc, 0 A, polarity and the conditions are in the form")
        XCTAssertEqual(r.missing(.beforeInsulation).first, "IR (MΩ) 24 สตริง")
        XCTAssertEqual(r.missing(.thermal), ["ภาพถ่ายความร้อนอย่างน้อย 1 รูป"])
        XCTAssertEqual(r.missing(.review), ["ขั้นที่ 1, 2, 3, 4, 5, 6 ยังไม่ครบ"])
        let c = try complete()
        for s in IECReport.Stage.allCases { XCTAssertTrue(c.isDone(s), "\(s): \(c.missing(s))") }
    }

    func testAConfirmationHoldsUntilItsStepChanges() throws {
        var r = try complete()
        XCTAssertFalse(r.isConfirmed(.beforeVoltage))
        XCTAssertTrue(r.confirm(.beforeVoltage, by: "ก"))
        XCTAssertTrue(r.isConfirmed(.beforeVoltage))
        // another step's change leaves it confirmed
        r.inverters[0].slots[0]?.vmpV = 600
        XCTAssertTrue(r.isConfirmed(.beforeVoltage))
        XCTAssertFalse(r.isConfirmed(.afterVoltage))
        // its own change doesn't, and putting the value back does again
        r.inverters[0].slots[0]?.vocV = 700
        XCTAssertFalse(r.isConfirmed(.beforeVoltage))
        XCTAssertNil(r.record(.beforeVoltage))
        r.inverters[0].slots[0]?.vocV = 755
        XCTAssertTrue(r.isConfirmed(.beforeVoltage))
        // a step that isn't done can't be confirmed
        r.inverters[0].slots[0]?.vocV = nil
        XCTAssertFalse(r.confirm(.beforeVoltage, by: "ก"))
    }

    func testEveryValueOfAStepCountsInItsFingerprint() throws {
        let base = try complete()
        let changes: [(IECReport.Stage, (inout IECReport) -> Void)] = [
            (.setup, { $0.instruments.thermalCamera = "T9" }), (.setup, { $0.inverters[1].slots[0]?.modules = 15 }),
            (.setup, { $0.sld?.version = 2 }), (.setup, { $0.inverters[0].mppt = 9 }), (.setup, { $0.inverters[0].photos["front"] = "p" }),
            (.beforeVoltage, { $0.inverters[1].slots[2]?.photos["currentBefore"] = "x" }), (.beforeVoltage, { $0.before.time = "13:05" }),
            (.beforeInsulation, { $0.inverters[0].continuity = .abnormal }), (.afterVoltage, { $0.gridOnAt = .now }),
            (.energy, { $0.inverters[0].remark = "" }), (.thermal, { $0.thermalPlaces["th1"] = "ตู้ DC" })]
        for (stage, change) in changes {
            var r = base
            change(&r)
            XCTAssertNotEqual(r.fingerprint(stage), base.fingerprint(stage), "\(stage)")
            XCTAssertNotEqual(r.fingerprint(.review), base.fingerprint(.review), "\(stage) in the whole")
        }
        XCTAssertEqual(try complete().fingerprint(.review), base.fingerprint(.review), "the same values, the same digest")
    }

    func testCompleteLocksAndKeepsThePass() throws {
        var r = try sample()
        XCTAssertFalse(r.submit(by: "ก"), "steps 1–6 aren't done")
        XCTAssertFalse(r.complete(by: "ก"))
        XCTAssertNil(r.result)
        r = try complete()
        XCTAssertFalse(r.complete(by: "ทีมภายใน"), "the team closes only what the contractor sent")
        XCTAssertTrue(r.submit(by: "ผู้รับเหมา"))
        let at = Date(timeIntervalSinceReferenceDate: 813_100_000)
        XCTAssertTrue(r.complete(by: "ทีมทดสอบ", at: at))
        XCTAssertTrue(r.isLocked)
        XCTAssertFalse(r.isAwaitingClose)
        XCTAssertEqual(r.result?.completedAt, at)
        XCTAssertEqual(r.result?.inverters, [.init(before: true, after: true), .init(before: true, after: true)])
        XCTAssertEqual(r.result?.passed, true)
        XCTAssertTrue(IECReport.Stage.allCases.allSatisfy(r.isConfirmed), "closing confirms every step")
        XCTAssertFalse(r.complete(by: "ข"), "closed once")
        XCTAssertFalse(r.resultIsStale)
        r.inverters[0].slots[0]?.vmpV = 1
        XCTAssertTrue(r.resultIsStale)
        r.reopen()
        XCTAssertFalse(r.isLocked)
        XCTAssertNil(r.submission, "reopened, it goes back to the contractor")
        // an IR under 1 MΩ fails the before phase of that inverter
        var bad = try complete()
        bad.inverters[1].slots[0]?.irNegMOhm = 0.5
        XCTAssertTrue(bad.submit(by: "ผู้รับเหมา"))
        XCTAssertTrue(bad.complete(by: "ก"))
        XCTAssertEqual(bad.result?.inverters[1].before, false)
        XCTAssertEqual(bad.result?.passed, false)
    }

    func testExportsKnowWhetherTheyAreCurrent() throws {
        var r = try complete()
        r.recordExport(.excel, name: "a.XLS")
        XCTAssertEqual(r.lastExport(.excel)?.current, true)
        XCTAssertNil(r.lastExport(.word))
        r.arrayTempC = 60
        XCTAssertEqual(r.lastExport(.excel)?.current, false)
        r.recordExport(.excel, name: "b.XLS")
        XCTAssertEqual(r.lastExport(.excel)?.record.name, "b.XLS")
        XCTAssertEqual(r.exports.count, 2)
    }

    func testTheNewFieldsRoundTripAndOldReportsDecode() throws {
        var r = try complete()
        r.gridOnAt = Date(timeIntervalSinceReferenceDate: 813_050_000)
        r.thermalPlaces = ["th1": "หลังคาอาคาร 1"]
        r.confirm(.setup, by: "ก")
        r.recordExport(.excel, name: "a.XLS")
        r.submit(by: "ผู้รับเหมา")
        r.sentBack = .init(at: Date(timeIntervalSinceReferenceDate: 813_060_000), by: "ข", note: "รูป IR ไม่ชัด")
        r.complete(by: "ก")
        let back = try JSONDecoder().decode(IECReport.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
        XCTAssertTrue(back.isConfirmed(.setup) && back.isLocked && !back.resultIsStale, "fingerprints survive the JSON")
        // a report saved before these fields existed
        let old = try JSONEncoder().encode(try sample())
        var json = try JSONSerialization.jsonObject(with: old) as! [String: Any]
        for k in ["gridOnAt", "thermalPlaces", "stageRecords", "exports", "submission", "sentBack", "result"] { json[k] = nil }
        let decoded = try JSONDecoder().decode(IECReport.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.stageRecords.isEmpty && decoded.exports.isEmpty && decoded.result == nil && decoded.thermalPlaces.isEmpty)
        XCTAssertTrue(decoded.submission == nil && decoded.sentBack == nil && !decoded.isLocked)
        // a test closed before the hand-over existed stays closed
        var closed = json
        closed["result"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(back.result!))
        let oldClosed = try JSONDecoder().decode(IECReport.self, from: JSONSerialization.data(withJSONObject: closed))
        XCTAssertTrue(oldClosed.isLocked && !oldClosed.isAwaitingClose && oldClosed.lockedLine == "ปิดการทดสอบแล้ว · ดูได้อย่างเดียว")
    }

    /// The contractor fills and sends; the internal team closes or sends back, like a daily report (fill, then sign).
    func testContractorSendsAndTheTeamClosesOrSendsBack() throws {
        var r = try complete()
        let sentAt = Date(timeIntervalSinceReferenceDate: 813_100_000)
        XCTAssertFalse(r.sendBack(by: "ทีม", note: "x"), "nothing sent yet")
        XCTAssertTrue(r.submit(by: "หัวหน้างานผู้รับเหมา", at: sentAt))
        XCTAssertEqual(r.submission?.by, "หัวหน้างานผู้รับเหมา")
        XCTAssertEqual(r.submission?.submittedAt, sentAt)
        XCTAssertTrue(r.isLocked && r.isAwaitingClose)
        XCTAssertNil(r.result, "sending isn't closing: the MP plan doesn't count it")
        XCTAssertEqual(r.lockedLine, "ส่งผลให้ทีมแล้ว · รอทีมภายในปิด · ดูได้อย่างเดียว")
        XCTAssertTrue(IECReport.Stage.allCases.allSatisfy(r.isConfirmed), "sending confirms every step")
        XCTAssertEqual(r.record(.setup)?.by, "หัวหน้างานผู้รับเหมา")
        XCTAssertFalse(r.submit(by: "หัวหน้างานผู้รับเหมา"), "sent once")

        // sent back with what to fix: open again, the note kept until the next send
        XCTAssertTrue(r.sendBack(by: "วิศวกร", note: "  ถ่ายรูป IR ใหม่ \n"))
        XCTAssertFalse(r.isLocked)
        XCTAssertEqual(r.sentBack?.note, "ถ่ายรูป IR ใหม่")
        XCTAssertFalse(r.complete(by: "วิศวกร"))
        r.inverters[0].slots[0]?.irPosMOhm = 260
        XCTAssertTrue(r.submit(by: "หัวหน้างานผู้รับเหมา"))
        XCTAssertNil(r.sentBack)

        // values changed behind the hand-over (a sync): the team can't close it, only send it back
        var stale = r
        stale.inverters[0].slots[0]?.irPosMOhm = 270
        XCTAssertTrue(stale.submissionIsStale)
        XCTAssertFalse(stale.complete(by: "วิศวกร"))
        XCTAssertTrue(stale.sendBack(by: "วิศวกร", note: ""))

        XCTAssertFalse(r.submissionIsStale)
        XCTAssertTrue(r.complete(by: "วิศวกร"))
        XCTAssertEqual(r.result?.by, "วิศวกร")
        XCTAssertEqual(r.submission?.by, "หัวหน้างานผู้รับเหมา", "who sent it stays on record")
        XCTAssertFalse(r.sendBack(by: "วิศวกร", note: "x"), "closed: reopen instead")
    }
}

final class IECPhotoNameTests: XCTestCase {
    func testPhotosAreNamedAsTheWordLabelsThem() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/iec62446-praek-nam-daeng.json")
        var r = try IECReport(form: Data(contentsOf: url))
        // INV 2's second string is slot 3
        r.inverters[1].slots[2]?.photos["voltageAfter"] = "a"
        r.inverters[0].slots[0]?.photos["insulation"] = "b"
        r.irradiancePhoto = "c"
        r.thermalPhotos = ["d", "e"]; r.thermalPlaces = ["e": "ตู้ DC"]
        XCTAssertEqual(r.photoFileNames(), ["a": "INV2ST2 หลัง แรงดัน.jpg", "b": "INV1ST1 ก่อน IR.jpg", "c": "ความเข้มแสง.jpg",
                                            "d": "ความร้อน 1.jpg", "e": "ความร้อน 2 ตู้ DC.jpg"])
    }
}
