import XCTest
@testable import TCRoofCore

final class RecentSearchesTests: XCTestCase {
    func testNewestFirst() {
        var list: [String] = []
        list = RecentSearches.adding("นพพร", to: list)
        list = RecentSearches.adding("สยามแพ็คกิ้ง", to: list)
        XCTAssertEqual(list, ["สยามแพ็คกิ้ง", "นพพร"])
    }

    func testDuplicateMovesToFront() {
        let list = RecentSearches.adding("  tcr2569-23404 ", to: ["นพพร", "TCR2569-23404", "กรีนเพลส"])
        XCTAssertEqual(list, ["tcr2569-23404", "นพพร", "กรีนเพลส"])
    }

    func testCapsAtFour() {
        let list = RecentSearches.adding("ใหม่", to: ["a", "b", "c", "d"])
        XCTAssertEqual(list, ["ใหม่", "a", "b", "c"])
    }

    func testBlankQueryIgnored() {
        XCTAssertEqual(RecentSearches.adding("   ", to: ["a"]), ["a"])
    }

    func testRoundTrip() {
        let list = ["นพพร", "TCR2569-23404"]
        XCTAssertEqual(RecentSearches.decode(RecentSearches.encode(list)), list)
        XCTAssertEqual(RecentSearches.decode(""), [])
    }
}
