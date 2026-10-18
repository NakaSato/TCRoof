import XCTest
@testable import TCRoofCore

/// 9 ภาพถ่ายติดตั้งระบบ: the pages follow the roofs and inverters, in the order of the report as sent.
final class IECInstallPhotosTests: XCTestCase {
    func twoInverters() -> IECReport {
        var a = IECReport.Inverter(ratedKW: 125, serial: "GKLRF5N02R"); a.model = "Growatt MAX 125KTL3-X LV"
        let b = IECReport.Inverter(ratedKW: 60, serial: "BUFUEXB009")
        return IECReport(inverters: [a, b])
    }

    func testOneDefaultRoofAndTwoInvertersGiveTwelvePagesInOrder() {
        let r = twoInverters()
        let pages = r.installPages
        XCTAssertEqual(pages.map(\.title), ["หลังคา 1 (1/2)", "หลังคา 1 (2/2)", "Inverter No.1", "Inverter No.2", "ตู้ AC", "ตู้ DC",
                                            "Smart energy", "กราวน์ DC", "กราวน์ AC / Inverter Station", "PQM"])
        XCTAssertEqual(pages.map(\.slots.count), [2, 2, 2, 2, 2, 2, 2, 1, 2, 2])
        XCTAssertEqual(pages[0].group, "หลังคา 1")
        XCTAssertEqual(pages[2].group, "")
        XCTAssertEqual(pages[2].subtitle, "Growatt MAX 125KTL3-X LV · S/N GKLRF5N02R")
        XCTAssertEqual(pages[3].slots[1].caption, "ภาพถ่ายเครื่องแปลงไฟฟ้า Inverter (Serial No.2)")
        XCTAssertEqual(r.installTally, .init(0, 19))
    }

    func testRoofsAddTwoPagesEachAndKeepTheirPhotosWhenRenamed() {
        var r = twoInverters()
        let first = r.installPages[0].slots[0]
        r.setInstallPhoto("p1", for: first)
        r.installPhotos.addRoof("หลังคาอาคารถังน้ำใส 2")
        r.installPhotos.renameRoof(IECReport.InstallPhotos.defaultRoofID, to: "หลังคาอาคารถังน้ำใส 1")
        let pages = r.installPages
        XCTAssertEqual(pages.prefix(4).map(\.title), ["หลังคาอาคารถังน้ำใส 1 (1/2)", "หลังคาอาคารถังน้ำใส 1 (2/2)",
                                                      "หลังคาอาคารถังน้ำใส 2 (1/2)", "หลังคาอาคารถังน้ำใส 2 (2/2)"])
        XCTAssertEqual(pages.count, 12)
        XCTAssertEqual(r.installPhoto(pages[0].slots[0]), "p1", "renaming keeps the roof's photos")

        r.setInstallPhoto("p2", for: pages[2].slots[1])
        XCTAssertEqual(r.installPhotos.removeRoof(r.installPhotos.roofs[1].id), ["p2"], "removing a roof hands back its photos")
        XCTAssertEqual(r.installPages.count, 10)
        XCTAssertEqual(r.installPhotos.removeRoof(r.installPhotos.roofs[0].id), [], "the last roof stays")
    }

    func testAnInvertersPhotosAreStepOnesPhotos() {
        var r = twoInverters()
        r.inverters[1].photos[IECReport.InverterPhoto.nameplate.rawValue] = "sn2"
        let inv2 = r.installPages.first { $0.id == "inv2" }!
        XCTAssertEqual(r.installPhoto(inv2.slots[1]), "sn2")
        r.setInstallPhoto("front2", for: inv2.slots[0])
        XCTAssertEqual(r.inverters[1].photos["front"], "front2")
        XCTAssertTrue(r.installPhotos.photos.isEmpty, "not copied into the report's own photos")
        XCTAssertEqual(r.installTally.done, 2)
    }

    func testFileNamesAndOldReportsDecode() throws {
        var r = twoInverters()
        r.setInstallPhoto("pqm", for: r.installPages.last!.slots[1])
        XCTAssertEqual(r.photoFileNames()["pqm"], "9.10 PQM 2.jpg")
        r.setInstallPhoto("roof", for: r.installPages[0].slots[0])
        XCTAssertEqual(r.photoFileNames()["roof"], "9.1 หลังคา 1 (1-2) 1.jpg")

        let back = try JSONDecoder().decode(IECReport.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.installPhotos, r.installPhotos)
        let old = try JSONDecoder().decode(IECReport.self, from: Data(#"{"stationLine":"x"}"#.utf8))
        XCTAssertEqual(old.installPhotos, .init())
        XCTAssertEqual(old.installPages.count, 8, "no inverters yet: the roof, the cabinets, grounds and PQM")
    }
}
