import XCTest
@testable import TCRoofCore

/// A3 wide page data: old jobs still open, `mdb[k]` follows `boards[k].at`, deleting a transformer shifts what follows.
final class TransformerBoardsTests: XCTestCase {
    func testOldJSONDecodesAndBuildsBoardsFromMdb() throws {
        let json = #"{"id":"5F2A2D0E-6C55-4B0B-9E0A-3C0D2F1E7A11","kva":"630","mdb":["800","","250"]}"#
        let t = try JSONDecoder().decode(Transformer.self, from: Data(json.utf8))
        XCTAssertEqual(t.kva, "630")
        XCTAssertEqual(t.mdb, ["800", "", "250", "", "", ""])
        XCTAssertTrue(t.boards.isEmpty)
        XCTAssertNil(t.hasLA)
        let b = t.resolvedBoards
        XCTAssertEqual(b.map(\.at), ["800", "", "250"])
        XCTAssertEqual(b.map(\.isMain), [true, false, false])
        XCTAssertEqual(b.first?.name, "MDB1")
    }

    func testOldJSONWithoutIDDecodes() throws {
        let t = try JSONDecoder().decode(Transformer.self, from: Data(#"{"kva":"400"}"#.utf8))
        XCTAssertEqual(t.kva, "400")
        XCTAssertEqual(t.mdb.count, 6)
        XCTAssertTrue(t.resolvedBoards.isEmpty)
    }

    func testSetBoardsMirrorsATToMdb() throws {
        var t = Transformer(kva: "630")
        t.setBoards([Board(name: "MDP-1", at: "800"), Board(name: "SDB", at: "400"), Board(name: "X", at: "63")])
        XCTAssertEqual(t.mdb, ["800", "400", "63", "", "", ""])
        XCTAssertEqual(t.boards.map(\.isMain), [true, false, false])
        // seven boards: only six are kept, as before
        t.setBoards((0..<7).map { Board(name: "B\($0)", at: "\(100 + $0)") })
        XCTAssertEqual(t.boards.count, 6)
        XCTAssertEqual(t.mdb, ["100", "101", "102", "103", "104", "105"])
        // and it survives a round trip
        let back = try JSONDecoder().decode(Transformer.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
    }

    func testRemovingMiddleTransformerShiftsAnswers() {
        var v = Values()
        for i in 0..<3 {
            v["tr\(i)_feed"] = .text("MDP-\(i)")
            v["tr\(i)_feedLoc"] = .text("loc\(i)")
            v["tr\(i)_mdbSpace"] = .photo(Photo(fileName: "p\(i).jpg", width: 1, height: 1))
        }
        v.shiftTransformerAnswers(removed: 1)
        XCTAssertEqual(v.text("tr0_feed"), "MDP-0")
        XCTAssertEqual(v.text("tr1_feed"), "MDP-2")
        XCTAssertEqual(v.text("tr1_feedLoc"), "loc2")
        XCTAssertEqual(v.photo("tr1_mdbSpace")?.fileName, "p2.jpg")
        XCTAssertNil(v["tr2_feed"])
        XCTAssertNil(v.photo("tr2_mdbSpace"))
    }

    func testSolarSpacePhotoIsRequiredPerTransformer() {
        var v = Values()
        v["trafos"] = .transformers([Transformer(kva: "630")])
        let none = Schema.electrical.completion(v)
        v["tr0_mdbSpace"] = .photo(Photo(fileName: "s.jpg", width: 1, height: 1))
        let one = Schema.electrical.completion(v)
        XCTAssertEqual(one.filled, none.filled + 1)
        XCTAssertEqual(one.total, none.total)
        // no transformer, no requirement
        XCTAssertFalse(Schema.electrical.fields.first { $0.id == "tr0_mdbSpace" }!.isRequired(Values()))
    }

    func testNewFieldsDoNotChangeA3Completion() {
        var v = Values()
        v["meterNo"] = .text("020")
        v["trafos"] = .transformers([Transformer(kva: "630")])
        let before = Schema.electrical.completion(v)
        var t = Transformer(kva: "630"); t.vectorGroup = "Dyn11"; t.setBoards([Board(name: "MDP-1", at: "800")])
        v["trafos"] = .transformers([t]); v["meterKV"] = .choice("22", other: "")
        XCTAssertEqual(Schema.electrical.completion(v), before)
    }

    func testBoardPhotosCountAsJobPhotos() {
        var t = Transformer(kva: "400")
        var b = Board(name: "SDB"); b.photos = [Photo(fileName: "sdb.jpg", width: 1, height: 1)]
        t.setBoards([Board(name: "MDP-1", at: "400"), b])
        var v = Values(); v["trafos"] = .transformers([t])
        XCTAssertEqual(v.allPhotos.map(\.fileName), ["sdb.jpg"])
    }
}
