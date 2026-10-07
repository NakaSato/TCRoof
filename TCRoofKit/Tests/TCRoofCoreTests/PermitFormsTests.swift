import XCTest
@testable import TCRoofCore

/// PEA permit forms drawn over the original PDFs (Resources/PermitForms).
final class PermitFormsTests: XCTestCase {

    func testMapsLoadAndCoverEveryAnswer() throws {
        let poaMap = try XCTUnwrap(PermitFormMap.load(PermitFormMap.powerOfAttorney))
        XCTAssertNotNil(PermitFormMap.templateURL(PermitFormMap.powerOfAttorney))
        XCTAssertEqual(poaMap.pages, 1)
        XCTAssertEqual(poaMap.checks.count, 7)
        let poaKeys = Set(poaMap.fields.map(\.key))
        XCTAssertEqual(Set(PowerOfAttorney().values.keys).subtracting(poaKeys), [])

        let scMap = try XCTUnwrap(PermitFormMap.load(PermitFormMap.selfCertification))
        XCTAssertEqual(scMap.pages, 12)
        XCTAssertEqual(scMap.areas.count, 10)
        var sc = SelfCertification()
        sc.producerSignDate = .now; sc.engineerSignDate = .now
        XCTAssertEqual(Set(sc.values.keys).subtracting(scMap.fields.map(\.key)), [])
        // every field sits on the A4 page
        for f in poaMap.fields + scMap.fields {
            XCTAssertLessThan(f.x0, f.x1, f.key)
            XCTAssertLessThan(f.x1, 595.4, f.key)
            XCTAssertLessThan(f.baseline, 842, f.key)
        }
    }

    func testThaiID() {
        XCTAssertTrue(ThaiID.isValid("1100100000000"))
        XCTAssertTrue(ThaiID.isValid("3-1001-00000-00-6"))
        XCTAssertFalse(ThaiID.isValid("1100100000001"))
        XCTAssertFalse(ThaiID.isValid("110010000000"))
        XCTAssertEqual(ThaiID.formatted("1100100000000"), "1-1001-00000-00-0")
        XCTAssertEqual(ThaiID.formatted("11001"), "1-1001")
        XCTAssertEqual(ThaiID.digits("๑๒๓"), "123")
    }

    func testPowerOfAttorneyPresetsAndIssues() {
        var poa = PowerOfAttorney()
        XCTAssertTrue(poa.issues.contains("ทำเครื่องหมาย ✓ หรือ – ให้ครบข้อ 1–5"))
        poa.apply(.connectOnly)
        XCTAssertEqual(poa.marks["power_3"], .yes)
        XCTAssertEqual(poa.marks["power_1"], PermitMark.no)
        XCTAssertFalse(poa.issues.contains("ทำเครื่องหมาย ✓ หรือ – ให้ครบข้อ 1–5"))
        // item 6's reference prints only when item 6 is granted
        poa.item6Ref = "1, 2"
        XCTAssertEqual(poa.values["item6_ref"], "")
        poa.powers[5] = .yes
        XCTAssertEqual(poa.values["item6_ref"], "1, 2")

        poa.grantor.nationalID = "1100100000000"
        poa.grantee.nationalID = "1100100000000"
        XCTAssertTrue(poa.issues.contains("ผู้มอบและผู้รับมอบเป็นคนเดียวกัน"))
        XCTAssertEqual(poa.values["grantor.national_id"], "1-1001-00000-00-0")
    }

    func testExportLimiterRule() {
        var sc = SelfCertification()
        XCTAssertNil(sc.exportLimiter)
        sc.inverterKW = "10"; sc.sellKW = "5"; sc.phase = .single
        XCTAssertEqual(sc.exportLimiter, .singleOver7)
        XCTAssertEqual(sc.marks["el_single"], .yes)
        sc.phase = .multi
        XCTAssertEqual(sc.exportLimiter, .notRequired)          // 10 kW is not more than 10
        XCTAssertFalse(sc.requiredAttachments.contains(2))
        sc.inverterKW = "12"
        XCTAssertEqual(sc.exportLimiter, .multiOver10)
        sc.sellKW = "12"
        XCTAssertEqual(sc.exportLimiter, .notRequired)          // not more than the power sold
        sc.inverterKW = "5"; sc.sellKW = "5"; sc.phase = .single
        XCTAssertEqual(sc.exportLimiter, .notRequired)
    }

    func testSelfCertificationIssues() {
        var sc = SelfCertification()
        sc.latitude = "14.97"; sc.longitude = "102.10"
        XCTAssertTrue(sc.coordinatesValid)
        sc.longitude = "2.10"
        XCTAssertFalse(sc.coordinatesValid)
        sc.sellKW = "6"
        XCTAssertTrue(sc.issues.contains("ปริมาณเสนอขายเกิน 5 kW"))
        XCTAssertTrue(sc.issues.contains("แนบ 10: ยังไม่มีรูป"))
    }
}
