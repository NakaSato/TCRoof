import XCTest
@testable import TCRoofCore

/// งานบ้าน: residential workflow and its document list.
final class HomeWorkflowTests: XCTestCase {

    func testSelfUsePPIMSlotsMatchTheScreen() {
        let job = HomeJob()                                    // self-use by default
        let slots = job.ppimSlots
        XCTAssertEqual(slots.map(\.slot.number), [1, 2, 3, 4, 5, 6, 8, 9])   // no 7 for solar
        XCTAssertEqual(slots.map(\.slot.maxMB), [5, 5, 5, 5, 50, 50, 5, 25])
        XCTAssertEqual(slots.first?.slot.file, "1. ใบแจ้งค่าไฟฟ้า.pdf")
        XCTAssertEqual(Set(slots.map(\.slot.group)), ["เอกสารหลัก", "พลังงานแสงอาทิตย์"])
        for s in slots {
            XCTAssertTrue(s.slot.file.hasPrefix("\(s.slot.number). "), s.slot.file)
            XCTAssertFalse(s.documents.isEmpty, "slot \(s.slot.number) has a document")
        }
        // several documents share one file, in file order
        XCTAssertEqual(slots.first { $0.slot.number == 2 }?.documents.map(\.id), ["idCard", "houseReg"])
        XCTAssertEqual(slots.first { $0.slot.number == 6 }?.documents.map(\.id), ["sld", "engineerDocs"])
        XCTAssertEqual(HomeCatalog.spec("sitePhotos")?.ppim?.number, 4)
        XCTAssertEqual(HomeCatalog.spec("sitePhotos")?.form, .photoReport)
    }

    func testRouteDecidesTheDocuments() {
        var job = HomeJob()
        let selfUse = Set(job.checklist.map(\.id))
        XCTAssertTrue(selfUse.contains("installCert"))
        XCTAssertFalse(selfUse.contains("contract"))
        XCTAssertTrue(selfUse.contains("houseReg"))            // filed with the ID card in slot 2, optional
        XCTAssertTrue(HomeCatalog.spec("houseReg")!.isOptional(for: job))
        XCTAssertFalse(job.missing(in: .survey).contains { $0.id == "houseReg" })
        XCTAssertTrue(selfUse.contains("engineerDocs"))
        XCTAssertTrue(selfUse.contains("exportLimiter"))        // zero export on every self-use job

        job.mode = .sell
        let sell = Set(job.checklist.map(\.id))
        XCTAssertTrue(sell.isSuperset(of: ["houseReg", "feeReceipt", "contract", "selfCert", "ercNotice", "eBill"]))
        XCTAssertFalse(sell.contains("installCert"))
        XCTAssertFalse(HomeCatalog.spec("houseReg")!.isOptional(for: job))
        XCTAssertFalse(sell.contains("exportLimiter"))          // unknown until sizes and phase are in
        job.inverterKW = "10"; job.sellKW = "5"; job.phase = .single
        XCTAssertTrue(Set(job.checklist.map(\.id)).contains("exportLimiter"))
        job.phase = .multi
        XCTAssertFalse(Set(job.checklist.map(\.id)).contains("exportLimiter"))

        job.teamFiles = false
        XCTAssertFalse(job.checklist.contains { $0.id == "poa" })
    }

    func testBuildingPermitAndTax() {
        var job = HomeJob()
        XCTAssertNil(job.needsBuildingPermit)
        XCTAssertFalse(job.checklist.contains { $0.id == "buildingPermit" })
        job.roofKgPerM2 = 21
        XCTAssertTrue(job.checklist.contains { $0.id == "buildingPermit" })
        job.roofKgPerM2 = 14.2
        XCTAssertFalse(job.checklist.contains { $0.id == "buildingPermit" })

        XCTAssertFalse(job.taxEligible)
        job.pvKWp = "9.9"
        XCTAssertTrue(job.checklist.contains { $0.id == "eTax" })
        job.pvKWp = "12.35"
        XCTAssertFalse(job.taxEligible)
    }

    func testStagesAndProgress() {
        var job = HomeJob()
        XCTAssertEqual(job.currentStage, .survey)
        for spec in job.checklist where spec.stage == .survey {
            var d = HomeDocument(); d.status = .received; job.documents[spec.id] = d
        }
        XCTAssertTrue(job.missing(in: .survey).isEmpty)
        XCTAssertEqual(job.currentStage, .design)
        let p = job.progress(.survey)
        XCTAssertEqual(p.done, p.total)
        // optional documents never block
        XCTAssertFalse(job.missing(in: .connect).contains { $0.id == "ercNoticeSelfUse" })
    }

    func testResidentialOnly() {
        var job = HomeJob()
        XCTAssertTrue(job.issues.contains("ยืนยันว่าเป็นบ้านอยู่อาศัย"))
        job.residentialConfirmed = true
        job.caRateCode = "2214"
        XCTAssertEqual(job.rateCodeIsResidential, false)
        XCTAssertTrue(job.issues.contains { $0.hasPrefix("CA ไม่ได้ขึ้นต้นด้วย 1") })
        job.caRateCode = "1125"
        XCTAssertTrue(job.issues.isEmpty)
    }

    func testRoofWeightAndDecoding() throws {
        // 16 panels of 28 kg, 2.58 m², with 70 kg of rails
        let w = try XCTUnwrap(RoofWeight.kgPerM2(panelKg: 28, panelAreaM2: 2.58, panelCount: 16, mountingKg: 70, otherKg: 0))
        XCTAssertEqual(w, 12.55, accuracy: 0.01)
        XCTAssertNil(RoofWeight.kgPerM2(panelKg: 28, panelAreaM2: 0, panelCount: 16, mountingKg: 0, otherKg: 0))

        let old = #"{"mode":"sell","documents":{"bill":{"status":"received"}}}"#
        let job = try JSONDecoder().decode(HomeJob.self, from: Data(old.utf8))
        XCTAssertEqual(job.mode, .sell)
        XCTAssertTrue(job.teamFiles)
        XCTAssertEqual(job.document("bill").status, .received)
        XCTAssertEqual(try JSONDecoder().decode(HomeJob.self, from: JSONEncoder().encode(job)), job)
    }

    func testEngineerCertificateExpires() throws {
        var job = HomeJob()
        XCTAssertNil(job.coeCertDaysLeft())
        let cal = Calendar(identifier: .gregorian)
        let issued = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 1, day: 22)))
        job.coeCertIssued = issued
        XCTAssertEqual(job.coeCertDaysLeft(on: issued), 120)
        XCTAssertEqual(job.coeCertDaysLeft(on: cal.date(byAdding: .day, value: 120, to: issued)!), 0)
        XCTAssertEqual(job.coeCertDaysLeft(on: cal.date(byAdding: .day, value: 121, to: issued)!), -1)
        job.coeCertIssued = cal.date(byAdding: .day, value: -200, to: Date())
        XCTAssertTrue(job.issues.contains { $0.hasPrefix("หนังสือรับรองสภาวิศวกรหมดอายุ") })
    }

    func testPPIMEntry() {
        var e = PPIMEntry()
        XCTAssertNil(e.panelKWp)
        e.panels[0].watt = "570"; e.panels[0].count = "17"
        e.inverters[0].kW = "10"
        XCTAssertEqual(e.panelKWp!, 9.69, accuracy: 0.0001)
        XCTAssertEqual(e.inverterKW, 10)
        e.latitude = "7.025"; e.longitude = "100.49"
        XCTAssertTrue(e.issues.isEmpty)
        e.latitude = "100.49"; e.longitude = "7.025"
        XCTAssertEqual(e.issues, ["ละติจูดกับลองจิจูดสลับกัน"])
        e.latitude = "35"; e.longitude = "139"
        XCTAssertEqual(e.issues, ["พิกัดไม่อยู่ในประเทศไทย"])
        XCTAssertEqual(PPIMEntry.meterVoltage(.multi), "380 V (3 phase)")
    }

    func testPhotoReportPagesAndGeometry() throws {
        var r = PhotoReport()
        XCTAssertEqual(r.missing.count, 9)
        XCTAssertTrue(r.pages.isEmpty)
        for s in r.sections where s.required { r.add("\(s.id).jpg", to: s.id) }
        r.add("sn2.jpg", to: "inverterSN"); r.add("sn3.jpg", to: "inverterSN")   // third is ignored
        XCTAssertEqual(r.sections.first { $0.id == "inverterSN" }?.photos, ["inverterSN.jpg", "sn2.jpg"])
        XCTAssertTrue(r.missing.isEmpty)
        XCTAssertEqual(r.pages.map(\.count), [2, 2, 2, 2, 1])               // 9 sections on 5 pages
        r.remove("sn2.jpg")
        XCTAssertEqual(r.photoCount, 9)

        r.address = "บ้านเลขที่ ตัวอย่าง"
        XCTAssertEqual(r.header(kWp: 9.69), [PhotoReport.defaultTitle, "บ้านเลขที่ ตัวอย่าง", "ขนาดกำลังการผลิตติดตั้ง 9.69 กิโลวัตต์"])
        XCTAssertEqual(r.header(kWp: 10).last, "ขนาดกำลังการผลิตติดตั้ง 10 กิโลวัตต์")

        XCTAssertEqual(PhotoReport.layout(aspects: [1.5, 1.33]), .stack2)
        XCTAssertEqual(PhotoReport.layout(aspects: [0.75, 1.5]), .side2)
        let rects = PhotoReport.photoRects(slot: 1, aspects: [0.75, 0.75])
        let area = PhotoReport.frame(slot: 1).area
        XCTAssertEqual(rects.count, 2)
        for rect in rects {
            XCTAssertEqual(rect[2] / rect[3], 0.75, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(rect[0], area[0] - 0.001)
            XCTAssertLessThanOrEqual(rect[1] + rect[3], area[1] + area[3] + 0.001)
        }
        XCTAssertLessThan(rects[0][0] + rects[0][2], rects[1][0])           // side by side, apart

        // old saved reports pick up sections added later; old jobs decode
        let old = #"{"sections":[{"id":"panels","title":"x","photos":["a.jpg"]}]}"#
        let decoded = try JSONDecoder().decode(PhotoReport.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.sections.count, PhotoReport.standard.count)
        XCTAssertEqual(decoded.sections.first?.photos, ["a.jpg"])
        let job = try JSONDecoder().decode(HomeJob.self, from: Data(#"{"mode":"selfUse"}"#.utf8))
        XCTAssertEqual(job.photoReport, PhotoReport())
        XCTAssertEqual(job.ppim, PPIMEntry())
    }
}

/// Selling route: second request, deadlines from the announcement, sizes locked at the sell request.
final class HomeSellRouteTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)
    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

    func sellJob() -> HomeJob {
        var j = HomeJob()
        j.residentialConfirmed = true
        j.caRateCode = "1125"
        j.mode = .sell
        j.pvKWp = "6.84"; j.inverterKW = "5"; j.sellKW = "5"; j.phase = .single
        return j
    }

    func testDocumentsOfEachRoute() {
        var j = sellJob()
        let ids = Set(j.checklist.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["sellRequest", "connectRequest", "peaApproval"]))
        XCTAssertFalse(ids.contains("ppimRequest"))
        j.mode = .selfUse
        let own = Set(j.checklist.map(\.id))
        XCTAssertTrue(own.contains("ppimRequest"))
        XCTAssertFalse(own.contains("sellRequest") || own.contains("connectRequest"))
    }

    func testRateCodeVoltageAndWindow() {
        var j = sellJob()
        XCTAssertEqual(j.rateCodeIsLowVoltage, true)
        XCTAssertTrue(j.issues(on: day(2026, 10, 7)).isEmpty)
        j.caRateCode = "1124"
        XCTAssertTrue(j.issues(on: day(2026, 10, 7)).contains { $0.hasPrefix("Rate code หลักที่ 4") })
        j.caRateCode = "1125"
        XCTAssertTrue(j.issues(on: day(2027, 12, 1)).contains { $0.hasPrefix("อยู่นอกช่วงเปิดรับ") })
        j.ppimRequestNo = "PPIM1A6000001"                     // filed in time: the window no longer matters
        XCTAssertFalse(j.issues(on: day(2027, 12, 1)).contains { $0.hasPrefix("อยู่นอกช่วงเปิดรับ") })
        j.mode = .selfUse; j.caRateCode = "1124"
        XCTAssertTrue(j.issues(on: day(2027, 12, 1)).isEmpty)  // self-use has neither rule
    }

    func testDeadlinesFromAnnouncement() {
        var j = sellJob()
        XCTAssertTrue(j.sellDeadlines.isEmpty)
        j.announcedOn = day(2026, 9, 1)
        let d = j.sellDeadlines
        XCTAssertEqual(d.map(\.id), ["fee", "contract"])
        XCTAssertEqual(d[0].due, day(2026, 10, 1))
        XCTAssertEqual(d[0].daysLeft(on: day(2026, 9, 21)), 10)
        XCTAssertTrue(j.issues(on: day(2026, 10, 2)).contains("เลยกำหนด: ชำระค่าตรวจสอบการเชื่อมต่อ 2,140 บาท"))
        var paid = HomeDocument(); paid.status = .received
        j.documents["feeReceipt"] = paid
        j.documents["contract"] = paid
        XCTAssertFalse(j.issues(on: day(2026, 10, 2)).contains { $0.hasPrefix("เลยกำหนด") })

        j.scod = day(2027, 6, 30)
        XCTAssertEqual(j.sellDeadlines.last?.id, "scod")
        XCTAssertFalse(j.sellDeadlines.last!.done)
        j.cod = day(2027, 5, 1)
        XCTAssertTrue(j.sellDeadlines.last!.done)
        j.mode = .selfUse
        XCTAssertTrue(j.sellDeadlines.isEmpty)
    }

    func testOfferLock() throws {
        var j = sellJob()
        j.sellKW = ""
        XCTAssertFalse(j.lockOffer())
        j.sellKW = "5"
        XCTAssertTrue(j.lockOffer(on: day(2026, 8, 1)))
        XCTAssertEqual(j.offer?.inverterKW, 5)
        XCTAssertTrue(j.offerIssues.isEmpty)
        j.inverterKW = "6"; j.pvKWp = "6.5"
        XCTAssertEqual(j.offerIssues, ["อินเวอร์เตอร์ kW เกินที่ยื่นขอขายไฟ (6 > 5)"])
        XCTAssertTrue(j.issues(on: day(2026, 10, 7)).contains(j.offerIssues[0]))

        let back = try JSONDecoder().decode(HomeJob.self, from: JSONEncoder().encode(j))
        XCTAssertEqual(back, j)
        let old = try JSONDecoder().decode(HomeJob.self, from: Data(#"{"mode":"sell"}"#.utf8))
        XCTAssertNil(old.offer); XCTAssertNil(old.announcedOn); XCTAssertEqual(old.connectRequestNo, "")
    }
}

/// The company library and the "ต้องทำต่อ" list.
final class HomeLibraryTests: XCTestCase {
    func library() -> HomeLibrary {
        var lib = HomeLibrary()
        var eng = HomeLibrary.Item(id: "eng", kind: .engineer, name: "วิศวกร ก")
        eng.files = ["e.pdf"]; eng.issued = Calendar(identifier: .gregorian).date(byAdding: .day, value: -10, to: Date())
        var pv = HomeLibrary.Item(id: "pv", kind: .pvSpec, name: "ZXM7 UHLD144")
        pv.files = ["pv.pdf"]
        var inv = HomeLibrary.Item(id: "inv", kind: .inverterSpec, name: "SUN2000-10K-MAP0")
        inv.files = ["inv.pdf"]
        let empty = HomeLibrary.Item(id: "inv2", kind: .inverterSpec, name: "SUN2000-5K-MAP0")   // no files: never used
        var eq1 = HomeLibrary.Item(id: "eq1", kind: .equipment, name: "Huawei 3 เฟส"); eq1.files = ["a.pdf"]
        var eq2 = HomeLibrary.Item(id: "eq2", kind: .equipment, name: "Huawei 1 เฟส"); eq2.files = ["b.pdf"]
        lib.items = [eng, pv, inv, empty, eq1, eq2]
        return lib
    }

    func testSuggestionsByModelAndDefault() {
        var job = HomeJob()
        let lib = library()
        XCTAssertNil(lib.suggestion(for: "pvSpec", job: job))           // no model typed yet
        job.ppim.panels[0].model = "ZXM7-UHLD144 Series"
        job.ppim.inverters[0].model = "SUN2000-10K-MAP0"
        XCTAssertEqual(lib.suggestion(for: "pvSpec", job: job)?.id, "pv")
        XCTAssertEqual(lib.suggestion(for: "inverterSpec", job: job)?.id, "inv")
        XCTAssertEqual(lib.suggestion(for: "engineerDocs", job: job)?.id, "eng")   // the only one
        XCTAssertNil(lib.suggestion(for: "equipment", job: job))                  // two sets, no default
        var withDefault = lib
        withDefault.items[5].isDefault = true
        XCTAssertEqual(withDefault.suggestion(for: "equipment", job: job)?.id, "eq2")
        XCTAssertNil(lib.suggestion(for: "bill", job: job))
    }

    func testApplyLibraryFillsEmptyDocuments() throws {
        var job = HomeJob()
        job.ppim.panels[0].model = "ZXM7-UHLD144"
        var own = HomeDocument(); own.files = ["mine.pdf"]; own.status = .received
        job.documents["inverterSpec"] = own                                        // the job's own file wins
        job.ppim.inverters[0].model = "SUN2000-10K-MAP0"
        let picked = job.applyLibrary(library())
        XCTAssertEqual(Set(picked), ["pvSpec", "engineerDocs"])
        XCTAssertEqual(job.libraryPicks["pvSpec"], "pv")
        XCTAssertNil(job.libraryPicks["inverterSpec"])
        XCTAssertEqual(job.document("pvSpec").status, .received)
        XCTAssertEqual(job.coeCertDaysLeft(), 110)

        var smaller = library(); smaller.items.removeAll { $0.id == "pv" }
        job.applyLibrary(smaller)
        XCTAssertNil(job.libraryPicks["pvSpec"])                                   // item gone, pick dropped
        job.libraryPicks["engineerDocs"] = ""                                      // team detached it
        job.documents["engineerDocs"] = HomeDocument()
        job.applyLibrary(library())
        XCTAssertEqual(job.libraryPicks["engineerDocs"], "")
        XCTAssertEqual(job.document("engineerDocs").status, .missing)
        let back = try JSONDecoder().decode(HomeJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(back.libraryPicks, job.libraryPicks)
    }

    func testNextActionsOrder() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))!
        var job = HomeJob()
        job.residentialConfirmed = true
        job.caRateCode = "1125"
        let first = job.nextActions(on: today)
        XCTAssertEqual(first.count, 5)
        XCTAssertTrue(first.allSatisfy { $0.kind == .document })
        XCTAssertEqual(first.first?.docID, "survey")

        job.mode = .sell
        job.pvKWp = "5"; job.inverterKW = "5"; job.sellKW = "6"; job.phase = .single
        job.announcedOn = cal.date(byAdding: .day, value: -35, to: today)          // fee and contract 5 days late
        let sell = job.nextActions(on: today, limit: 10)
        XCTAssertEqual(sell.prefix(2).map(\.kind), [.overdue, .overdue])
        XCTAssertEqual(sell[0].detail, "เลยกำหนด 5 วัน")
        XCTAssertEqual(sell[2].kind, .issue)                                       // sells over 5 kW
        XCTAssertFalse(sell.contains { $0.kind == .issue && $0.title.hasPrefix("เลยกำหนด") })

        job.announcedOn = cal.date(byAdding: .day, value: -25, to: today)
        XCTAssertTrue(job.nextActions(on: today, limit: 10).contains { $0.kind == .deadline && $0.detail == "เหลือ 5 วัน" })
    }
}
