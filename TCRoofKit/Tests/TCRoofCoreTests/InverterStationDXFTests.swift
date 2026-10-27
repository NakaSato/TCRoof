import XCTest
@testable import TCRoofCore

/// B2's DXF after the team's station drawings (reference/inverter-station) and their component library.
final class InverterStationDXFTests: XCTestCase {
    let t = DXFRead()

    func station(_ sizes: [Int], site: InverterStation.Site = .outdoor, length: Double? = 6, height: Double? = 3) -> InverterStation {
        InverterStation(sizes: sizes, width: 2.5, length: length, height: height, site: site)
    }
    func inserts(_ d: Data, _ name: String) -> [[(String, String)]] {
        t.rawEntities(d).filter { $0.first?.1 == "INSERT" && t.value($0, "2") == name }
    }
    func hasText(_ d: Data, _ s: String) -> Bool {
        let key = String(data: SketchDXF.tis620(s), encoding: .isoLatin1)!
        return t.rawEntities(d).contains { $0.first?.1 == "TEXT" && t.value($0, "1") == key }
    }
    func scale(_ e: [(String, String)], _ code: String) -> Double { t.value(e, code).flatMap(Double.init) ?? 1 }

    /// The component library ships and has the blocks the drawing uses.
    func testTheLibraryShips() throws {
        let c = try XCTUnwrap(StationComponents.shared)
        for n in ["TCR_SOLAR_AC_DB_FRONT", "TCR_SOLAR_DC_DB_FRONT", "TCR_ENCLOSURE_630X750_FRONT", "TCR_GROWATT_MAX_125KTL3_LV_FRONT",
                  "TCR_GROWATT_MAX_80KTL3_LV_FRONT", "TCR_GROWATT_40KTL3_X_FRONT", "TCR_INVERTER_GENERIC_SIDE", "TCR_DB_ENCLOSURE_SIDE",
                  "TCR_STEEL_COLUMN_150_PLAN", "TCR_COLUMN_BASE_PLATE_DETAIL_PLAN", "TCR_DOOR_SWING_1100_PLAN",
                  "TCR_TRAY_SECTION_200X100", "TCR_TRAY_SIDE_PERF_H100", "TCR_LADDER_PLAN_W200"] {
            XCTAssertNotNil(c.blocks[n], n)
        }
        // the base plate as the team drew it (Part_1.dxf): 150 × 150
        let p = try XCTUnwrap(c.blocks["TCR_COLUMN_BASE_PLATE_DETAIL_PLAN"])
        XCTAssertEqual(p.width, 0.15, accuracy: 1e-6); XCTAssertEqual(p.height, 0.15, accuracy: 1e-6)
    }

    /// The team's 6.0 × 2.5 m shelter with one 125 kW inverter: the three views and the detail, a column on its plate at
    /// every grid crossing, the team's blocks for the equipment stretched to the catalog's size, hung at their heights.
    func testTheOutdoorStation() throws {
        let s = station([125])
        let d = InverterStationDXF.build(s).data
        for title in ["%%UTOP VIEW / แปลน", "%%UFRONT VIEW / รูปด้านหน้า", "%%USIDE VIEW / รูปด้านข้าง", "%%UDETAIL ฐานเสา / BASE PLATE",
                      "ตารางอุปกรณ์ / EQUIPMENT SCHEDULE", "T8 LED LAMP", "SOLAR AC-DB-01", "INVERTER No.1"] {
            XCTAssertTrue(hasText(d, title), title)
        }
        let grid = s.planSpans.count + 1
        let rackPosts = inserts(d, "TCR_STEEL_COLUMN_150_PLAN").count - 2 * grid
        XCTAssertGreaterThanOrEqual(rackPosts, 6, "rack posts on both edges of the band")
        XCTAssertEqual(rackPosts % 2, 0)
        // a footing under every post in the front view and the side view
        XCTAssertEqual(inserts(d, "TCR_CONCRETE_FOOTING_200X100_ELEVATION").count, grid + rackPosts / 2 + 2 + 2)
        XCTAssertEqual(inserts(d, "TCR_DOOR_SWING_1100_PLAN").count, 1)

        // the front view: the inverter's top 0.10 m above the cabinets' tops, each stretched to the catalog
        let inv = try XCTUnwrap(inserts(d, "TCR_GROWATT_MAX_125KTL3_LV_FRONT").first)
        let ac = try XCTUnwrap(inserts(d, "TCR_SOLAR_AC_DB_FRONT").first)
        let lib = try XCTUnwrap(StationComponents.shared)
        let invBox = lib.blocks["TCR_GROWATT_MAX_125KTL3_LV_FRONT"]!, acBox = lib.blocks["TCR_SOLAR_AC_DB_FRONT"]!
        let invTop = t.double(inv, "20") + invBox.box[3] * scale(inv, "42"), acTop = t.double(ac, "20") + acBox.box[3] * scale(ac, "42")
        XCTAssertEqual(invTop - acTop, InverterStationDXF.inverterTop - InverterStationDXF.rackTop, accuracy: 1e-3)
        let item = s.row.items[0], cat = s.catalog.acCabinet(inverters: 1)
        XCTAssertEqual(acBox.width * scale(ac, "41"), item.w, accuracy: 1e-3)
        XCTAssertEqual(acBox.height * scale(ac, "42"), Double(cat.h) / 1000, accuracy: 1e-3)
        // the side view: the equipment from the generic side blocks, the trays' sections
        XCTAssertEqual(inserts(d, "TCR_INVERTER_GENERIC_SIDE").count, 1)
        XCTAssertEqual(inserts(d, "TCR_DB_ENCLOSURE_SIDE").count, 3)
        // the AC tray's section at its width (100 here, as the DC one)
        XCTAssertEqual(s.trayWidth, 100)
        XCTAssertEqual(inserts(d, "TCR_TRAY_SECTION_100X100").count, 2)
        // the roof: posts, beams, purlins and the sheet on their layers; every entity on a standard layer
        let layers = Set(t.rawEntities(d).compactMap { t.value($0, "8") })
        for l in ["S-COLS-N", "S-BEAM-N", "S-ROOF-PURL-N", "A-ROOF-N", "S-FRAM-N", "S-FTNG-N", "E-EQPM-N", "E-CTRY-N", "E-LITE-N", "A-DOOR-N", "G-GRID", "G-ANNO-DIMS"] {
            XCTAssertTrue(layers.contains(l), l)
        }
        XCTAssertTrue(layers.allSatisfy { CADLayers.named($0) != nil }, "\(layers.filter { CADLayers.named($0) == nil })")
        XCTAssertFalse(layers.contains("A-WALL-E"))
    }

    /// Indoors: the rack against the existing wall, no columns, no roof, no door.
    func testTheWallStation() throws {
        let d = InverterStationDXF.build(station([80], site: .indoor, length: 8)).data
        let layers = Set(t.rawEntities(d).compactMap { t.value($0, "8") })
        XCTAssertTrue(layers.contains("A-WALL-E")); XCTAssertTrue(layers.contains("A-WALL-HATC-E"))
        for l in ["S-COLS-N", "S-BEAM-N", "A-ROOF-N", "A-DOOR-N", "E-LITE-N"] { XCTAssertFalse(layers.contains(l), l) }
        XCTAssertTrue(hasText(d, "SOLAR SEM-DB"), "the indoor row keeps its SEM-DB")
        XCTAssertEqual(inserts(d, "TCR_GROWATT_MAX_80KTL3_LV_FRONT").count, 1)
        XCTAssertEqual(inserts(d, "TCR_GROWATT_MAX_80KTL3_LV_TOP").count, 1)
        // no rack span over the team's 1.40 m, outdoors or on the wall
        for st in [station([80], site: .indoor, length: 8), station([125]), station([125, 40], length: 9)] {
            let p = InverterStationDXF.Geometry(st).rackPosts
            XCTAssertTrue(zip(p, p.dropFirst()).allSatisfy { $1 - $0 <= InverterStationDXF.maxRackSpan + 1e-9 }, "\(p)")
        }
    }

    /// Two inverters (the team's EXL-HV: 125 + 40): each with its DC-DB, the 40 kW one from its own block; a ladder
    /// wider than the library's falls back to the drawn one.
    func testTwoInvertersAndAWideLadder() throws {
        var s = station([125, 40], length: 9)
        s.ladderPick = 900
        let d = InverterStationDXF.build(s).data
        XCTAssertEqual(inserts(d, "TCR_GROWATT_MAX_125KTL3_LV_FRONT").count, 1)
        XCTAssertEqual(inserts(d, "TCR_GROWATT_40KTL3_X_FRONT").count, 1)
        XCTAssertEqual(inserts(d, "TCR_SOLAR_DC_DB_FRONT").count, 2)
        XCTAssertTrue(hasText(d, "SOLAR DC-DB-02"))
        XCTAssertEqual(s.ladderWidth, 900)
        XCTAssertTrue(inserts(d, "TCR_LADDER_PLAN_W900").isEmpty)
        XCTAssertTrue(hasText(d, "AC CABLE LADDER 900x100 (NON COVER)"))
    }

    /// Not measured: drawn with the minimum and said so; short: said so.
    func testNotesSayWhatIsMissing() {
        let d = InverterStationDXF.build(InverterStation(sizes: [125])).data
        XCTAssertTrue(t.rawEntities(d).contains { t.value($0, "1")?.contains("ROOM") == false && $0.first?.1 == "TEXT" })
        let short = InverterStationDXF.build(station([125, 125, 125], length: 6)).data
        let key = String(data: SketchDXF.tis620("พื้นที่จริงสั้นไป"), encoding: .isoLatin1)!
        XCTAssertTrue(t.rawEntities(short).contains { ($0.first?.1 == "TEXT") && (t.value($0, "1")?.contains(key) ?? false) })
    }

    /// Each item carries its catalog height.
    func testItemsHaveTheirHeights() {
        let s = station([125, 60])
        XCTAssertTrue(s.row.items.allSatisfy { $0.h > 0.3 })
        XCTAssertEqual(s.row.items.first { $0.kind == .inverter }?.h ?? 0, Double(s.catalog.inverter(kw: 125).h) / 1000, accuracy: 1e-9)
    }
}
