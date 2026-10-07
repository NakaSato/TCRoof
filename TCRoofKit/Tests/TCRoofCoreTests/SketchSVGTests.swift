import XCTest
@testable import TCRoofCore

final class SketchSVGTests: XCTestCase {
    private func svg(_ ops: [DrawOp], href: @escaping (Photo) -> String? = { _ in nil }) -> String {
        Sketch(width: 200, height: 100, ops: ops).svg(photoHref: href)
    }
    private func count(_ needle: String, in s: String) -> Int { s.components(separatedBy: needle).count - 1 }

    func testHatchIsClippedToItsBoxWithOwnClipIds() {
        let s = svg([.hatch(Box(0, 0, 40, 20), color: .red, spacing: 10), .hatch(Box(50, 0, 10, 10), color: .red, spacing: 5)])
        XCTAssertTrue(s.contains(##"<clipPath id="h1">"##))
        XCTAssertTrue(s.contains(##"<clipPath id="h2">"##))
        XCTAssertTrue(s.contains(##"clip-path="url(#h2)""##))
        // diagonals start one box-height left of the box and step `spacing` until past its width: (40 + 20) / 10 and (10 + 10) / 5
        XCTAssertEqual(count("stroke-width=\"1.4\"", in: s), 6 + 4)
    }

    func testPolylinePolygonAndDashes() {
        let s = svg([
            .polyline([Pt(0, 0), Pt(10, 5.5), Pt(20, 0)], width: 2, color: .black, dash: [4, 2]),
            .polyline([Pt(0, 0), Pt(1, 1)], width: 1, color: .black),
            .polygon([Pt(0, 0), Pt(10, 0), Pt(5, 8)], stroke: .blue, fill: nil, width: 1.5),
        ])
        XCTAssertTrue(s.contains(##"points="0,0 10,5.5 20,0" fill="none" stroke="#000000" stroke-width="2" stroke-dasharray="4 2""##))
        XCTAssertEqual(count("stroke-dasharray", in: s), 1, "no dash attribute on a solid line")
        XCTAssertTrue(s.contains(##"<polygon points="0,0 10,0 5,8" fill="none" stroke="#1F4E79" stroke-width="1.5"/>"##))
    }

    func testSeeThroughFillsKeepTheirAlpha() {
        let s = svg([.rect(Box(0, 0, 10, 10), stroke: nil, fill: RGBA(1, 0, 0, 0.25))])
        XCTAssertTrue(s.contains(##"fill="rgba(255,0,0,0.25)" stroke="none""##))
    }

    func testTextBoxWrapsAlignsAndDropsLinesThatDoNotFit() {
        // 10 pt text, 1.3 line height: a 30-pt box holds two lines
        let long = "หนึ่ง สอง สาม สี่ ห้า หก เจ็ด แปด เก้า สิบ"
        let left = svg([.textBox(long, Box(10, 0, 40, 30), size: 10)])
        XCTAssertGreaterThan(ApproxText.wrap(long, width: 40, size: 10).count, 2)
        XCTAssertEqual(count("<text ", in: left), 2)
        XCTAssertTrue(left.contains(##"x="10""##))
        XCTAssertTrue(left.contains(##"text-anchor="start""##))

        let centre = svg([.textBox("A", Box(10, 0, 40, 30), size: 10, bold: true, align: .center)])
        XCTAssertTrue(centre.contains(##"x="30" y="10""##))
        XCTAssertTrue(centre.contains(##"text-anchor="middle" font-weight="bold""##))
        let right = svg([.textBox("A", Box(10, 0, 40, 30), size: 10, align: .right)])
        XCTAssertTrue(right.contains(##"x="50""##))
        XCTAssertTrue(right.contains(##"text-anchor="end""##))
    }

    func testTextIsEscapedAndRotated() {
        let s = svg([.text("R&D <A>", at: Pt(20, 40), size: 10, align: .right, angle: -90),
                      .textBox("x < y & z", Box(0, 0, 200, 20), size: 10)])
        XCTAssertTrue(s.contains("R&amp;D &lt;A&gt;"))
        XCTAssertTrue(s.contains("x &lt; y &amp; z"))
        XCTAssertTrue(s.contains(##"transform="rotate(-90 20 40)""##))
        XCTAssertFalse(s.contains("<A>"))
    }

    func testPhotosFitTheirBoxOrShowAPlaceholder() {
        let wide = Photo(fileName: "a.jpg", width: 400, height: 100)
        let box = Box(0, 0, 100, 100)
        let linked = svg([.photo(wide, box)]) { "photos/" + $0.fileName }
        // 4:1 inside a square: full width, a quarter of the height, centred
        XCTAssertTrue(linked.contains(##"<image x="0" y="37.5" width="100" height="25" xlink:href="photos/a.jpg""##))
        let missing = svg([.photo(wide, box)])
        XCTAssertTrue(missing.contains(##"<rect x="0" y="37.5" width="100" height="25" fill="#cfd8dc"/>"##))
        XCTAssertFalse(missing.contains("<image"))
    }

    func testCheckboxesShowTheTickOnlyWhenOn() {
        let on = svg([.checkbox(Box(0, 0, 10, 10), on: true)])
        XCTAssertTrue(on.contains(##"fill="#70AD47""##))
        XCTAssertEqual(count("<polyline", in: on), 1)
        let off = svg([.checkbox(Box(0, 0, 10, 10), on: false)])
        XCTAssertTrue(off.contains(##"fill="#FFFFFF""##))
        XCTAssertEqual(count("<polyline", in: off), 0)
    }

    func testEveryKindOfOpMakesWellFormedXML() throws {
        let s = svg([
            .line(Pt(0, 0), Pt(10, 10), width: 1, color: .black, dash: [2, 2]),
            .rect(Box(0, 0, 5, 5), stroke: .black, fill: .white),
            .hatch(Box(0, 0, 20, 10), color: .black),
            .circle(Pt(5, 5), r: 3, stroke: .black, fill: nil),
            .polygon([Pt(0, 0), Pt(1, 0), Pt(0, 1)], stroke: nil, fill: .black),
            .polyline([Pt(0, 0), Pt(1, 1)], width: 1, color: .black),
            .text("ก & ข", at: Pt(1, 1), size: 8),
            .textBox("<ทดสอบ>", Box(0, 0, 50, 20), size: 8),
            .photo(Photo(fileName: "p.jpg", width: 3, height: 2), Box(0, 0, 30, 30)),
            .checkbox(Box(0, 0, 6, 6), on: true),
        ]) { _ in "data:image/png;base64,AAAA" }
        let parser = XMLParser(data: Data(s.utf8))
        XCTAssertTrue(parser.parse(), parser.parserError.map(String.init(describing:)) ?? "")
        XCTAssertTrue(s.hasPrefix(##"<svg xmlns="http://www.w3.org/2000/svg""##))
        XCTAssertTrue(s.contains(##"viewBox="0 0 200 100""##))
    }
}
