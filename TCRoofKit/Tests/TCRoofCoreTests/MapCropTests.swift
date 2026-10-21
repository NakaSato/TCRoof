import XCTest
@testable import TCRoofCore

/// A1 report frame on the satellite map (docs/ui/survey-a1 SPEC §3, §6).
final class MapCropTests: XCTestCase {
    func testTextRoundTrip() {
        XCTAssertEqual(MapCrop.standard.text, "22,16,54,64")
        XCTAssertEqual(MapCrop("22,16,54,64"), .standard)
        XCTAssertEqual(MapCrop(" 10.5, 20 ,30,40")?.text, "10.5,20,30,40")
        XCTAssertNil(MapCrop(""))
        XCTAssertNil(MapCrop("1,2,3"))
        XCTAssertNil(MapCrop("a,b,c,d"))
        // a stored value out of range is pulled back onto the map
        XCTAssertEqual(MapCrop("90,-5,50,5"), MapCrop(x: 50, y: 0, w: 50, h: 12))
    }

    func testMoveClampsToTheMap() {
        let c = MapCrop.standard
        XCTAssertEqual(c.moved(dx: 10, dy: -4), MapCrop(x: 32, y: 12, w: 54, h: 64))
        XCTAssertEqual(c.moved(dx: 500, dy: 0).x, 100 - c.w)
        XCTAssertEqual(c.moved(dx: -500, dy: 0).x, 0)
        XCTAssertEqual(c.moved(dx: 0, dy: 500).y, 100 - c.h)
        XCTAssertEqual(c.moved(dx: 500, dy: 500).w, c.w, "moving never changes the size")
    }

    func testResizeKeepsTheOppositeCorner() {
        let c = MapCrop.standard
        let nw = c.resized(.nw, dx: 10, dy: 10)
        XCTAssertEqual(nw.x + nw.w, c.x + c.w, accuracy: 1e-9)
        XCTAssertEqual(nw.y + nw.h, c.y + c.h, accuracy: 1e-9)
        XCTAssertEqual(nw, MapCrop(x: 32, y: 26, w: 44, h: 54))
        // shrinking past the minimum stops at 12 % with SE still fixed
        let tiny = c.resized(.nw, dx: 200, dy: 200)
        XCTAssertEqual(tiny.w, MapCrop.minSize); XCTAssertEqual(tiny.h, MapCrop.minSize)
        XCTAssertEqual(tiny.x + tiny.w, c.x + c.w, accuracy: 1e-9)
        XCTAssertEqual(tiny.y + tiny.h, c.y + c.h, accuracy: 1e-9)
        // growing past the edge stops at the map
        let big = c.resized(.nw, dx: -200, dy: -200)
        XCTAssertEqual(big, MapCrop(x: 0, y: 0, w: 76, h: 80))
        let se = c.resized(.se, dx: 200, dy: 200)
        XCTAssertEqual(se, MapCrop(x: 22, y: 16, w: 78, h: 84))
        let ne = c.resized(.ne, dx: -200, dy: -200)
        XCTAssertEqual(ne, MapCrop(x: 22, y: 0, w: 12, h: 80))
        let sw = c.resized(.sw, dx: 5, dy: 6)
        XCTAssertEqual(sw, MapCrop(x: 27, y: 16, w: 49, h: 70))
    }

    /// iPad A1 (docs/ui/survey-a1-ipad): the map fills a box taller than the picture, so its sides are cut off and
    /// the frame stays on the part that shows.
    func testVisiblePartOfAFilledMap() {
        let v = MapCrop.visible(picture: CGSize(width: 640, height: 400), box: CGSize(width: 682, height: 553))
        XCTAssertEqual(v.y, 0); XCTAssertEqual(v.h, 100)
        XCTAssertEqual(v.w, 682.0 / (640 * 553.0 / 400) * 100, accuracy: 1e-9)
        XCTAssertEqual(v.x, (100 - v.w) / 2, accuracy: 1e-9)
        XCTAssertEqual(MapCrop.visible(picture: CGSize(width: 640, height: 400), box: CGSize(width: 320, height: 200)), .full)
        XCTAssertEqual(MapCrop.visible(picture: CGSize(width: 640, height: 400), box: .zero), .full)

        let c = MapCrop.standard
        XCTAssertEqual(c.moved(dx: -50, dy: 0, within: v).x, v.x, accuracy: 1e-9)
        XCTAssertEqual(c.moved(dx: 50, dy: 0, within: v).x + c.w, v.x + v.w, accuracy: 1e-9)
        XCTAssertEqual(c.moved(dx: 3, dy: 2, within: v), c.moved(dx: 3, dy: 2), "inside the visible part it moves as before")
        // the whole map (an old job) shrinks to the visible part on the first move
        let full = MapCrop.full.moved(dx: 0, dy: 0, within: v)
        XCTAssertEqual(full.x, v.x, accuracy: 1e-9); XCTAssertEqual(full.w, v.w, accuracy: 1e-9)

        let grown = c.resized(.nw, dx: -200, dy: -200, within: v)
        XCTAssertEqual(grown.x, v.x, accuracy: 1e-9); XCTAssertEqual(grown.y, 0)
        XCTAssertEqual(grown.x + grown.w, c.x + c.w, accuracy: 1e-9, "the opposite corner stays")
        XCTAssertEqual(c.resized(.se, dx: 200, dy: 0, within: v).x + c.resized(.se, dx: 200, dy: 0, within: v).w, v.x + v.w, accuracy: 1e-9)
    }

    func testLabelInMetres() {
        // 200 m across: w 54 → 108 m, as in the design sample; H uses the map's proportions
        let c = MapCrop.standard
        XCTAssertEqual(c.meters(across: 200, aspect: 332.0 / 620).w, 108)
        XCTAssertEqual(c.meters(across: 200, aspect: 332.0 / 620).h, 69)
        XCTAssertEqual(c.label(across: 200, aspect: 332.0 / 620), "ภาพในรายงาน | 108 × 69 ม.")
        XCTAssertEqual(c.meters(across: 200, aspect: 400.0 / 640).h, 80)
    }

    func testResetIsTheStandardFrame() {
        XCTAssertEqual(MapCrop.standard, MapCrop(x: 22, y: 16, w: 54, h: 64))
        XCTAssertEqual(Job.new(template: JobTemplate.all[0]).values.text(MapCrop.key), "22,16,54,64", "a new job starts with the design's frame")
    }

    /// The cut-out keeps the frame's proportions; the whole frame is the whole picture.
    func testPixelRect() {
        let r = MapCrop.standard.pixelRect(width: 1280, height: 800)
        XCTAssertEqual(r, CGRect(x: 281, y: 128, width: 692, height: 512))
        XCTAssertEqual(r.width / r.height, (1280 * 0.54) / (800 * 0.64), accuracy: 0.01)
        XCTAssertEqual(MapCrop.full.pixelRect(width: 1280, height: 800), CGRect(x: 0, y: 0, width: 1280, height: 800))
        XCTAssertEqual(MapCrop(x: 88, y: 88, w: 12, h: 12).pixelRect(width: 1280, height: 800).maxX, 1280)
    }

    /// Old jobs: the ground-area count stays in the job and its backup but plays no part in A1 completion;
    /// a job without a frame keeps having none.
    func testGroundAreasKeptButNotCounted() throws {
        var old = Job.new(template: JobTemplate.all[2])
        old.values[MapCrop.key] = nil
        let before = old.steps[0].completion
        old.values["groundAreas"] = .text("2")
        XCTAssertEqual(old.steps[0].completion, before)
        let store = JobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("ss-" + UUID().uuidString))
        let back = try WebBackup.importJobs(WebBackup.exportBackup([old], store: store), into: store)[0]
        XCTAssertEqual(back.values.text("groundAreas"), "2")
        XCTAssertNil(back.values[MapCrop.key])
        XCTAssertEqual(back.steps[0].completion, before)
    }

    func testBackupKeepsTheFrame() throws {
        var j = Job.new(template: JobTemplate.all[2])
        j.values[MapCrop.key] = .text("10,20,30,40")
        let store = JobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("ss-" + UUID().uuidString))
        let back = try WebBackup.importJobs(WebBackup.exportBackup([j], store: store), into: store)[0]
        XCTAssertEqual(MapCrop(back.values.text(MapCrop.key)), MapCrop(x: 10, y: 20, w: 30, h: 40))
    }
}
