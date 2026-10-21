import XCTest
@testable import TCRoofCore

/// Nameplate parsing, roof orientation and answer sources (docs/specs/hardware-assist-swift.md §6).
final class HardwareAssistTests: XCTestCase {
    // MARK: nameplates (recognised text as Live Text returns it: lines joined, OCR spacing)

    func testTransformerPlate() {
        let text = """
        THREE PHASE TRANSFORMER
        RATED POWER 630 kVA  FREQ 50 Hz
        HV 22000 V  LV 416/240 V
        VECTOR GROUP Dyn11   IMPEDANCE VOLTAGE 4.0 %
        YEAR 2022  SERIAL No. 6S-2207-0153
        """
        let r = NameplateParser.read(text)
        XCTAssertEqual(r.kva, "630")
        XCTAssertEqual(r.vectorGroup, "Dyn11")
        XCTAssertEqual(r.impedance, "4.0")
        XCTAssertEqual(r.hvVolts, 22000)
        XCTAssertEqual(r.lvVolts, 240)
        XCTAssertEqual(r.yearBE, 2565, "2022 is written in B.E.")
        XCTAssertEqual(r.lvText, "416/240", "A3 writes the LV pair")
        XCTAssertEqual(NameplateParser.transformerFields(r).map(\.key), ["kva", "voltage", "vectorGroup", "impedance", "year"])
        XCTAssertEqual(NameplateParser.transformerFields(r).map(\.display), ["630 kVA", "416/240 V", "Dyn11", "4.0 %", "2565"])
        XCTAssertEqual(NameplateParser.transformerFields(r).map(\.value), ["630", "416/240", "Dyn11", "4.0", "2565"])
    }

    func testTransformerPlateWithOCRSpacingAndThousands() {
        let r = NameplateParser.read("1,000 k VA 22 kV / 0.4 kV  Uk = 6,0 %  DYN 11  ผลิตปี 2564")
        XCTAssertEqual(r.kva, "1000")
        XCTAssertEqual(r.impedance, "6.0")
        XCTAssertEqual(r.vectorGroup, "Dyn11")
        XCTAssertEqual(r.hvVolts, 22000)
        XCTAssertEqual(r.lvVolts, 400)
        XCTAssertEqual(r.yearBE, 2564, "a B.E. year stays as it is")
        XCTAssertEqual(r.lvText, "400")
    }

    func testPEAPlateInThaiDigits() {
        XCTAssertEqual(NameplateParser.value(.kva, in: "หม้อแปลง ๑๖๐ kVA ๒๒ kV"), "160")
    }

    func testBreakerLabels() {
        let mccb = NameplateParser.read("NF250-SW  In = 225 A  250 AF  Icu 36 kA 415V  IEC 60947-2")
        XCTAssertEqual(mccb.breakerAT, "225")
        XCTAssertEqual(mccb.breakerAF, "250")
        XCTAssertEqual(mccb.breakerKA, "36")
        XCTAssertNil(mccb.kva)
        XCTAssertNil(mccb.yearBE, "the standard's number is no year")

        XCTAssertEqual(NameplateParser.value(.breakerAT, in: "ABN 103c 100AT 100AF"), "100")
        XCTAssertEqual(NameplateParser.value(.breakerAT, in: "Ue 690V In=1600A Icu=65kA"), "1600")
    }

    func testMeterNumber() {
        XCTAssertEqual(NameplateParser.value(.meterNumber, in: "PEA kWh METER 5(100)A No. 1234-5678-90 230V"), "1234-5678-90")
        XCTAssertEqual(NameplateParser.value(.meterNumber, in: "การไฟฟ้าส่วนภูมิภาค เลขที่ 0012345678"), "0012345678")
        // without a label, the longest run of 8–12 that is no reading
        XCTAssertEqual(NameplateParser.value(.meterNumber, in: "15(45)A 230V 50Hz 1600 imp/kWh 21004587 CLASS 1"), "21004587")
        XCTAssertNil(NameplateParser.value(.meterNumber, in: "15(45)A 230V"))
    }

    func testNothingToRead() {
        XCTAssertEqual(NameplateParser.read("ห้ามเปิด อันตราย"), NameplateParser.Reading())
        XCTAssertTrue(NameplateParser.transformerFields(NameplateParser.Reading()).isEmpty)
        XCTAssertEqual(NameplateParser.Target.kva.display("630"), "630 kVA")
        XCTAssertEqual(NameplateParser.Target.breakerAT.display("225"), "225 AT")
    }

    // MARK: orientation

    func testTiltFromGravity() {
        XCTAssertEqual(Orientation.tilt(gx: 0, gy: -0.259, gz: -0.966), 15.0, accuracy: 0.05)
        XCTAssertEqual(Orientation.tilt(gx: 0, gy: 0, gz: -1), 0, accuracy: 0.001)
        XCTAssertEqual(Orientation.tilt(gx: 0.5, gy: 0, gz: -0.866), 30.0, accuracy: 0.05, "a sideways slope tilts as much")
    }

    func testFacingFromHeadingAndSlope() {
        // top edge up the slope: the slope faces the opposite way to the top edge
        XCTAssertEqual(Orientation.downhill(gx: 0, gy: -0.259), 180, accuracy: 0.001)
        XCTAssertEqual(Orientation.facing(heading: 15, gx: 0, gy: -0.259), 195, accuracy: 0.001)
        // slope running off the right edge: 90° clockwise from the top edge
        XCTAssertEqual(Orientation.facing(heading: 300, gx: 0.3, gy: 0), 30, accuracy: 0.001)
    }

    func testFacingChoices() {
        XCTAssertEqual(Orientation.facingChoice(195).choice, "ใต้")
        XCTAssertEqual(Orientation.facingChoice(225).choice, "ตะวันตกเฉียงใต้")
        XCTAssertEqual(Orientation.facingChoice(350).choice, "เหนือ")
        XCTAssertEqual(Orientation.facingChoice(-90).choice, "ตะวันตก")
        // south-east and north-west are not on the form: อื่นๆ with the bearing
        let se = Orientation.facingChoice(140)
        XCTAssertEqual(se.choice, "อื่นๆ")
        XCTAssertEqual(se.other, "ตะวันออกเฉียงใต้ 140°")
        XCTAssertEqual(Orientation.facingChoice(315).other, "ตะวันตกเฉียงเหนือ 315°")
        for c in Orientation.named.map(\.name) { XCTAssertTrue(Options.facing.contains(c), c) }
    }

    func testSteadyReading() {
        XCTAssertTrue(Orientation.isSteady(Array(repeating: 14.8, count: 50)))
        XCTAssertTrue(Orientation.isSteady((0..<50).map { 14.8 + ($0 % 2 == 0 ? 0.2 : -0.2) }))
        XCTAssertFalse(Orientation.isSteady((0..<50).map { 14 + Double($0) * 0.05 }), "still moving")
        XCTAssertFalse(Orientation.isSteady([14.8, 14.8]), "too few samples")
    }

    // MARK: sources

    func testConfirmedReadingsKeepTheirSourceUntilTypedOver() {
        var v = Values()
        v.set("meterNo", .text("1234-5678-90"), source: .nameplate)
        XCTAssertEqual(v.source("meterNo"), .nameplate)
        v["meterNo"] = .text("1234-5678-91")
        XCTAssertNil(v.source("meterNo"), "typing over the reading makes it typed")
        XCTAssertNil(v.sources, "no empty map left behind")

        v.markSource("tr1_kva", .nameplate)
        v.markSource("tr2_kva", .sensor)
        v.markSource("tr2_vectorGroup", .nameplate)
        v.shiftTransformerAnswers(removed: 1)
        XCTAssertEqual(v.source("tr1_kva"), .sensor, "transformer 3 moved up to 2")
        XCTAssertEqual(v.source("tr1_vectorGroup"), .nameplate)
        XCTAssertNil(v.source("tr2_kva"))
        XCTAssertNil(v.source("tr2_vectorGroup"))
        v.markSource("tr1_kva", .typed)
        XCTAssertNil(v.source("tr1_kva"))
        XCTAssertEqual(FillSource.nameplate.chip, "จากป้าย")
        XCTAssertNil(FillSource.typed.chip)
    }

    func testOldAnswersDecodeWithoutSources() throws {
        let old = try JSONDecoder().decode(Values.self, from: Data(#"{"storage":{"roofAngle":{"text":{"_0":"15"}}}}"#.utf8))
        XCTAssertEqual(old.text("roofAngle"), "15")
        XCTAssertNil(old.sources)
        var v = Values()
        v.set("roofAngle", .text("14.8"), source: .sensor)
        let back = try JSONDecoder().decode(Values.self, from: JSONEncoder().encode(v))
        XCTAssertEqual(back.source("roofAngle"), .sensor)
    }
}

final class PositionTests: XCTestCase {
    func testGradesAndNotes() {
        XCTAssertEqual(GPSGrade(accuracy: 8), .gps)
        XCTAssertEqual(GPSGrade(accuracy: 20), .gps)
        XCTAssertEqual(GPSGrade(accuracy: 35), .rough)
        XCTAssertEqual(GPSGrade(accuracy: 120), .approximate)
        XCTAssertEqual(GPSGrade(accuracy: -1), .unknown, "Core Location's invalid fix")
        XCTAssertEqual(GPSGrade.note(accuracy: 7.6), "ความแม่นยำ ± 8 ม.")
        XCTAssertTrue(GPSGrade.note(accuracy: 120).hasPrefix("ความแม่นยำ ± 120 ม. (เครื่องไม่มี GPS)"))
        XCTAssertTrue(GPSGrade.approximate.settingsDetail.contains("GNSS"))
    }
}

final class PhotoStampTests: XCTestCase {
    func testStampLine() throws {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 29; c.hour = 10; c.minute = 42
        let taken = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: c))
        var p = Photo(fileName: "a.jpg", width: 4, height: 3, takenAt: taken)
        XCTAssertNil(p.stampLine, "a library photo has nothing to print")
        p.apply(PhotoStamp(lat: 17.00621, lon: 99.82354, accuracy: 6, heading: 195.4, pitch: -12, device: "iPad14,8"))
        XCTAssertEqual(p.stampLine, "17.0062, 99.8235 | หันทิศ 195° | 29/9/2569 10:42")
        XCTAssertEqual(p.device, "iPad14,8")
        p.lat = nil; p.lon = nil
        XCTAssertEqual(p.stampLine, "หันทิศ 195° | 29/9/2569 10:42")
        XCTAssertTrue(PhotoStamp().isEmpty)
    }

    func testOldPhotosDecodeAndNewOnesRoundTrip() throws {
        let old = try JSONDecoder().decode(Photo.self, from: Data(#"{"id":"6B1F3C0E-2D6F-4F0E-9E1B-1C2D3E4F5A6B","fileName":"x.jpg","width":10,"height":8,"takenAt":0}"#.utf8))
        XCTAssertNil(old.lat)
        XCTAssertNil(old.heading)
        var p = Photo(fileName: "y.jpg", width: 1, height: 1)
        p.apply(PhotoStamp(lat: 13.7, lon: 100.5, heading: 90))
        let back = try JSONDecoder().decode(Photo.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.lat, 13.7)
        XCTAssertEqual(back.heading, 90)
    }

    func testCameraPitch() {
        XCTAssertEqual(Orientation.cameraPitch(gz: 0), 0, accuracy: 0.001)
        XCTAssertEqual(Orientation.cameraPitch(gz: -1), -90, accuracy: 0.001, "lying face up, the camera looks down")
        XCTAssertEqual(Orientation.cameraPitch(gz: 0.5), 30, accuracy: 0.001)
    }
}
