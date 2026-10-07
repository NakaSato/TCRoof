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

    func testPhotoLayouts() {
        let area: [Double] = [70.9, 120, 453.6, 662]
        for layout in PhotoLayout.allCases where layout != .auto {
            let cells = layout.cells(in: area, count: layout.capacity)
            XCTAssertEqual(cells.count, layout.capacity, layout.rawValue)
            for (i, a) in cells.enumerated() {
                // inside the area
                XCTAssertGreaterThanOrEqual(a[0], area[0] - 0.001, layout.rawValue)
                XCTAssertGreaterThanOrEqual(a[1], area[1] - 0.001, layout.rawValue)
                XCTAssertLessThanOrEqual(a[0] + a[2], area[0] + area[2] + 0.001, layout.rawValue)
                XCTAssertLessThanOrEqual(a[1] + a[3], area[1] + area[3] + 0.001, layout.rawValue)
                // no two cells overlap
                for b in cells[(i + 1)...] {
                    let apart = a[0] + a[2] <= b[0] + 0.001 || b[0] + b[2] <= a[0] + 0.001
                        || a[1] + a[3] <= b[1] + 0.001 || b[1] + b[3] <= a[1] + 0.001
                    XCTAssertTrue(apart, layout.rawValue)
                }
            }
        }
        XCTAssertEqual(PhotoLayout.auto.resolved(3), .top1bottom2)
        XCTAssertEqual(PhotoLayout.auto.cells(in: area, count: 2).count, 2)
        // fewer photos than cells: only those are placed
        XCTAssertEqual(PhotoLayout.grid4.cells(in: area, count: 3).count, 3)
        // the first cell of a stack starts at the area's top-left, the gap sits between cells
        let stack = PhotoLayout.stack2.cells(in: area, count: 2)
        XCTAssertEqual(stack[0][1], 120, accuracy: 0.001)
        XCTAssertEqual(stack[1][1] - (stack[0][1] + stack[0][3]), 8, accuracy: 0.001)
    }

    func testPrintedPhotosAndOrder() {
        var sc = SelfCertification()
        sc.photos[0] = ["a", "b", "c", "d"]
        XCTAssertEqual(sc.printedPhotos(1), ["a", "b", "c", "d"])      // auto → 2 × 2
        sc.layouts[0] = .stack3
        XCTAssertEqual(sc.printedPhotos(1), ["a", "b", "c"])
        sc.movePhoto(attachment: 1, from: 3, by: -1)
        XCTAssertEqual(sc.photos[0], ["a", "b", "d", "c"])
        sc.movePhoto(attachment: 1, from: 0, by: -1)                 // already first
        XCTAssertEqual(sc.photos[0], ["a", "b", "d", "c"])
    }

    func testOldSelfCertificationStillDecodes() throws {
        let old = #"{"producerName":"ก","photos":[["x.jpg"],[],[],[],[],[],[],[],[],[]]}"#
        let sc = try JSONDecoder().decode(SelfCertification.self, from: Data(old.utf8))
        XCTAssertEqual(sc.producerName, "ก")
        XCTAssertEqual(sc.layouts, Array(repeating: .auto, count: 10))
        XCTAssertEqual(sc.photos[0], ["x.jpg"])
        let round = try JSONDecoder().decode(SelfCertification.self, from: JSONEncoder().encode(sc))
        XCTAssertEqual(round, sc)
    }

    func testPhotoFrame() {
        let cell: [Double] = [0, 0, 200, 114]
        XCTAssertEqual(PhotoFrame.pictureBox(cell: cell, caption: true), [0, 0, 200, 100])
        XCTAssertEqual(PhotoFrame.pictureBox(cell: cell, caption: false), cell)
        XCTAssertEqual(PhotoFrame.captionBox(cell: cell), [0, 100, 200, 14])
        // a 4:3 photo in a 2:1 box
        let box: [Double] = [0, 0, 200, 100]
        let fill = PhotoFrame.placement(size: [400, 300], in: box, fit: .fill)
        XCTAssertEqual(fill[2], 200, accuracy: 0.001)       // covers the width
        XCTAssertEqual(fill[3], 150, accuracy: 0.001)       // overflows the height, centred
        XCTAssertEqual(fill[1], -25, accuracy: 0.001)
        let fit = PhotoFrame.placement(size: [400, 300], in: box, fit: .fit)
        XCTAssertEqual(fit[3], 100, accuracy: 0.001)
        XCTAssertEqual(fit[0], 33.333, accuracy: 0.001)
        XCTAssertEqual(PhotoFrame.highlight([0.5, 0.5, 0.25, 0.1], drawn: [10, 20, 200, 100]), [110, 70, 50, 10])
    }

    func testCaptionsAndDefaults() throws {
        var sc = SelfCertification()
        sc.photos[3] = ["a.jpg", "b.jpg"]
        sc.photoInfo["b.jpg"] = { var i = AttachmentPhotoInfo(); i.caption = " S/N อินเวอร์เตอร์ "; return i }()
        XCTAssertEqual(sc.caption(attachment: 4, index: 0), "รูปที่ 4.1")
        XCTAssertEqual(sc.caption(attachment: 4, index: 1), "รูปที่ 4.2 S/N อินเวอร์เตอร์")
        XCTAssertEqual(sc.fit("a.jpg", attachment: 4), .fill)
        XCTAssertEqual(sc.fit("a.jpg", attachment: 9), .fit)
        XCTAssertTrue(sc.captionsOn(4))
        XCTAssertEqual(SelfCertification.captionSuggestions.count, 10)
        let round = try JSONDecoder().decode(SelfCertification.self, from: JSONEncoder().encode(sc))
        XCTAssertEqual(round, sc)
    }

    func testAttachmentPagesTakePageOneHeading() throws {
        let map = try XCTUnwrap(PermitFormMap.load(PermitFormMap.selfCertification))
        let logos = try XCTUnwrap(map.logos)
        let shifts = try XCTUnwrap(map.shifts)
        XCTAssertEqual(Set(logos.map(\.page)), Set(2...11))          // attachments 1–10, not the statement pages
        XCTAssertEqual(Set(shifts.map(\.page)), Set(2...11))
        for logo in logos {
            // the artwork, place and size of the original page 1
            XCTAssertEqual(logo.rect, [247.95, 48.55, 99.4, 84.35])
            XCTAssertNotNil(PermitFormMap.assetURL(logo.image).flatMap { try? Data(contentsOf: $0) }, logo.image)
            let shift = try XCTUnwrap(shifts.first { $0.page == logo.page })
            XCTAssertGreaterThan(shift.dy, 0)
            let area = try XCTUnwrap(map.areas.first { $0.page == logo.page })
            // the photo area starts where the moved heading ends and still clears the signature line (y ≈ 790)
            XCTAssertEqual(area.rect[1], shift.until + shift.dy, accuracy: 0.05)
            XCTAssertLessThanOrEqual(area.rect[1] + area.rect[3], 782.05)
            XCTAssertGreaterThan(area.rect[3], 400)
            for field in map.fields where field.page == logo.page { XCTAssertGreaterThan(field.baseline - 14, logo.rect[1] + logo.rect[3]) }
            for check in map.checks where check.page == logo.page { XCTAssertGreaterThan(check.rect[1], logo.rect[1] + logo.rect[3]) }
        }
        XCTAssertNil(PermitFormMap.load(PermitFormMap.powerOfAttorney)?.logos)
        XCTAssertNil(PermitFormMap.load(PermitFormMap.powerOfAttorney)?.shifts)
    }
}
