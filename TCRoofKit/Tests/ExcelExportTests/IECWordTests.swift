import XCTest
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import ExcelExport
@testable import TCRoofCore

/// docs/specs/iec62446-word-appendix-swift.md §5, on the แพรกหนามแดง sample with drawn photos.
final class IECWordTests: XCTestCase {
    func sample() throws -> IECReport {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../TCRoofCoreTests/Fixtures/iec62446-praek-nam-daeng.json")
        return try IECReport(form: Data(contentsOf: url))
    }

    /// A small real JPEG (the form's PWA logo) as every photo.
    func photo() throws -> Data { try XCTUnwrap(ZipArchive(IECExcel.template()).data("xl/media/image1.jpeg")) }

    /// The sample with every photo, `missing` kinds left out, and 2 thermal images.
    func withPhotos(missing: Set<IECReport.PhotoKind> = []) throws -> (IECReport, [String: Data]) {
        var r = try sample(), photos: [String: Data] = [:]
        let jpeg = try photo()
        for i in r.inverters.indices {
            for n in r.inverters[i].slots.indices where r.inverters[i].slots[n] != nil {
                for k in IECReport.PhotoKind.allCases where !missing.contains(k) {
                    let id = "\(i)-\(n)-\(k.rawValue)"
                    r.inverters[i].slots[n]?.photos[k.rawValue] = id
                    photos[id] = jpeg
                }
            }
        }
        r.irradiancePhoto = "sun"; photos["sun"] = jpeg
        r.thermalPhotos = ["t1", "t2"]; r.thermalPlaces = ["t2": "ตู้ DC"]; photos["t1"] = jpeg; photos["t2"] = jpeg
        return (r, photos)
    }

    func count(_ s: String, _ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }

    func testThePackageIsWellFormedAndComplete() throws {
        let (r, photos) = try withPhotos()
        let data = try IECWord.export(r, photos: photos)
        // `IEC_WORD_OUT=<path> swift test --filter IECWordTests` keeps the file, to open it in Word
        if let path = ProcessInfo.processInfo.environment["IEC_WORD_OUT"] { try data.write(to: URL(fileURLWithPath: path)) }
        let zip = try ZipArchive(data)
        for p in zip.paths where p.hasSuffix(".xml") || p.hasSuffix(".rels") {
            let parser = XMLParser(data: zip.data(p)!)
            XCTAssertTrue(parser.parse(), "\(p): \(String(describing: parser.parserError))")
        }
        // every relationship target exists, every r:embed has a relationship
        for rels in zip.paths where rels.hasSuffix(".rels") {
            let base = rels.hasPrefix("word/") ? "word/" : ""
            for t in zip.string(rels)!.components(separatedBy: "Target=\"").dropFirst().map({ $0.components(separatedBy: "\"")[0] }) {
                XCTAssertTrue(zip.contains(base + t), "\(rels) → \(t)")
            }
        }
        let doc = zip.string("word/document.xml")!, docRels = zip.string("word/_rels/document.xml.rels")!
        for id in doc.components(separatedBy: "r:embed=\"").dropFirst().map({ $0.components(separatedBy: "\"")[0] }) {
            XCTAssertTrue(docRels.contains("Id=\"\(id)\""), id)
        }
        // pictures: 24 strings × 5 + the irradiance meter + 2 thermal, and the 2 logos in the header
        XCTAssertEqual(count(doc, "<w:drawing>"), 24 * 5 + 1 + 2)
        XCTAssertEqual(count(zip.string("word/header1.xml")!, "<w:drawing>"), 2)
        XCTAssertEqual(zip.paths.filter { $0.hasPrefix("word/media/") }.count, 24 * 5 + 3 + 2)
        XCTAssertTrue(zip.string("word/header1.xml")!.contains(r.stationLine))
    }

    func testOrderLabelsAndPages() throws {
        let (r, photos) = try withPhotos()
        let doc = try ZipArchive(IECWord.export(r, photos: photos)).string("word/document.xml")!
        // INV1ST1 … INV1ST16, then INV2ST1 … INV2ST8, in both phases
        let labels = doc.components(separatedBy: "Voltage testing และ Current testing ").dropFirst().map { $0.components(separatedBy: " ")[0] }
        let expected = (1...16).map { "INV1ST\($0)" } + (1...8).map { "INV2ST\($0)" }
        XCTAssertEqual(labels, expected + expected)
        XCTAssertTrue(doc.contains("Insulation Resistance testing INV2 ST8"))
        XCTAssertTrue(doc.contains("ภาพถ่ายความร้อน 2 | ตู้ DC"))
        // pages: the after cover, 8 + 8 voltage pages (3 strings each), 4 IR pages (6 each), irradiance, thermal
        XCTAssertEqual(count(doc, "<w:pageBreakBefore/>"), 1 + 8 + 8 + 4 + 1 + 1)
        XCTAssertEqual(count(doc, "<w:cantSplit/>"), 8 * 3 * 2 - 0 + 4 * 3 + 1 + 1)
    }

    func testAMissingPhotoLeavesItsFrame() throws {
        let (r, photos) = try withPhotos(missing: [.currentAfter])
        let doc = try ZipArchive(IECWord.export(r, photos: photos)).string("word/document.xml")!
        XCTAssertEqual(count(doc, ">ไม่มีรูป<"), 24, "one frame per string's clamp after the connection")
        XCTAssertEqual(count(doc, "<w:drawing>"), 24 * 4 + 1 + 2)
        XCTAssertThrowsError(try IECWord.export(IECReport(), photos: [:]))
    }

    func testPixelSizes() throws {
        let zip = try ZipArchive(IECExcel.template())
        XCTAssertEqual(IECWord.pixelSize(zip.data("xl/media/image1.jpeg")!).map { [$0.w, $0.h] }, [220, 222])
        XCTAssertEqual(IECWord.pixelSize(zip.data("xl/media/image2.png")!).map { [$0.w, $0.h] }, [375, 250])
        XCTAssertNil(IECWord.pixelSize(Data("nope".utf8)))
        XCTAssertEqual(IECWord.fileName(station: "สถานี/ก", date: Date(timeIntervalSince1970: 1_791_000_000)).suffix(5), ".docx")
    }
}
