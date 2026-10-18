import XCTest
@testable import PDFReport
@testable import TCRoofCore

/// IEC 62446 · 9 ภาพถ่ายติดตั้งระบบ: the cover lists every page, each page keeps its frames, empty or not.
final class InstallPhotoPagesTests: XCTestCase {
    private func texts(_ ops: [DrawOp]) -> [String] {
        ops.compactMap {
            switch $0 {
            case let .text(t, _, _, _, _, _, _), let .textBox(t, _, _, _, _, _): t
            default: nil
            }
        }
    }

    private func photos(_ ops: [DrawOp]) -> Int { ops.filter { if case .photo = $0 { true } else { false } }.count }

    private func report() -> InstallPhotoPages {
        var r = IECReport(inverters: [.init(ratedKW: 125, serial: "A1"), .init(ratedKW: 60, serial: "B2")])
        r.installPhotos.renameRoof(IECReport.InstallPhotos.defaultRoofID, to: "หลังคาอาคารถังน้ำใส 1")
        r.installPhotos.addRoof("หลังคาอาคารถังน้ำใส 2")
        let shot = Photo(fileName: "a.jpg", width: 4000, height: 3000)
        let pages = r.installPages.enumerated().map { n, p in
            InstallPhotoPages.Page(title: p.title, group: p.group, slots: p.slots.map { .init(caption: $0.caption, photo: n == 0 ? shot : nil) })
        }
        return InstallPhotoPages(station: "สถานีจ่ายน้ำแพรกหนามแดง การประปาส่วนภูมิภาคสาขาสมุทรสงคราม", capacity: "209.76",
                                 month: "ตุลาคม 2569", pages: pages)
    }

    func testCoverThenTwelvePages() {
        let out = report().render()
        XCTAssertEqual(out.count, 13)
        let cover = texts(out[0].ops)
        XCTAssertTrue(cover.contains("ภาพถ่ายติดตั้งระบบผลิตไฟฟ้า"))
        XCTAssertTrue(cover.contains("สารบัญ"))
        XCTAssertTrue(cover.contains("9.12"))
        XCTAssertTrue(cover.contains("PQM"))
        XCTAssertTrue(cover.contains("ตุลาคม 2569"))
        XCTAssertTrue(cover.contains("ขนาดกำลังการผลิตติดตั้ง 209.76 กิโลวัตต์"))
    }

    func testPagesKeepEmptyFramesAndTheirNumber() {
        let out = report().render()
        let first = out[1].ops, gdc = out[10].ops
        XCTAssertEqual(photos(first), 2)
        XCTAssertTrue(texts(first).contains("หลังคาอาคารถังน้ำใส 1"), "the roof's name above its photos")
        XCTAssertTrue(texts(first).contains("1 / 12"))
        XCTAssertEqual(photos(gdc), 0)
        XCTAssertEqual(texts(gdc).filter { $0 == "ยังไม่มีรูป" }.count, 1, "กราวน์ DC has one tall frame")
        XCTAssertTrue(texts(gdc).contains("ภาพถ่ายกราวน์กระแสตรง"))
        // the station line gets the PWA prefix only when it lacks it
        XCTAssertTrue(texts(first).contains("สถานีจ่ายน้ำแพรกหนามแดง การประปาส่วนภูมิภาคสาขาสมุทรสงคราม"))
        var bare = report(); bare.station = "สถานีผลิตน้ำบางไทร"
        XCTAssertTrue(texts(bare.render()[1].ops).contains("การประปาส่วนภูมิภาค สถานีผลิตน้ำบางไทร"))
    }

    func testLongLinesShrinkToTheColumn() {
        let p = report()
        let long = String(repeating: "ภาพถ่ายตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสสลับ ", count: 4)
        XCTAssertLessThan(p.fit(long, 20.72), InstallPhotoPages.size(20.72))
        XCTAssertEqual(p.fit("PQM", 20.72), InstallPhotoPages.size(20.72))
    }
}
