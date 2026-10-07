import XCTest
@testable import TCRoofCore

/// งานบ้าน: residential workflow and its document list.
final class HomeWorkflowTests: XCTestCase {

    func testSelfUsePPIMSlotsMatchTheScreen() {
        let job = HomeJob()                                    // self-use by default
        let slots = job.ppimSlots
        XCTAssertEqual(slots.compactMap(\.ppimSlot), [1, 2, 3, 4, 5, 6, 8, 9])
        XCTAssertEqual(slots.compactMap(\.maxMB), [5, 5, 5, 5, 50, 50, 5, 25])
        XCTAssertEqual(slots.first?.ppimFile, "1. ใบแจ้งค่าไฟฟ้า.pdf")
        // file names are unique and numbered by their slot
        for s in slots { XCTAssertTrue(s.ppimFile?.hasPrefix("\(s.ppimSlot!). ") == true, s.id) }
    }

    func testRouteDecidesTheDocuments() {
        var job = HomeJob()
        let selfUse = Set(job.checklist.map(\.id))
        XCTAssertTrue(selfUse.contains("installCert"))
        XCTAssertFalse(selfUse.contains("contract"))
        XCTAssertFalse(selfUse.contains("houseReg"))
        XCTAssertTrue(selfUse.contains("exportLimiter"))        // zero export on every self-use job

        job.mode = .sell
        let sell = Set(job.checklist.map(\.id))
        XCTAssertTrue(sell.isSuperset(of: ["houseReg", "feeReceipt", "contract", "selfCert", "ercNotice", "eBill"]))
        XCTAssertFalse(sell.contains("installCert"))
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
}
