import XCTest
@testable import TCRoofCore

/// docs/specs/auto-drawing.md §4.4 and §9.3: C1's Howe truss, its member schedule and the details A / B.
final class RoofTrussTests: XCTestCase {
    /// The ridge along y: B = 16 across it (four 4 m bays in x), 24 m along it (four 6 m bays),
    /// 15°, heel 0.5, eight panels a half.
    func roof(_ f: RoofFrame, bays: Int? = 8) -> Values {
        var v = Values()
        Roof.setSpans(&v, .x, [4, 4, 4, 4]); Roof.setSpans(&v, .y, [6, 6, 6, 6])
        Roof.setRidge(&v, .v); Roof.setFrame(&v, f); Roof.setBays(&v, bays)
        for n in 1...7 { Roof.setMember(&v, n, size: f.members[n - 1].defaultSize) }
        return v
    }

    func testHoweMatchesTheSpecsNumbers() throws {
        // §9.3: Howe with d = 0.5 → n = 8, 17 verticals (the king post too), 16 diagonals, 34 nodes, king post 2.644
        let g = try XCTUnwrap(RoofTruss.geometry(roof(.howe)))
        XCTAssertEqual(g.span, 16); XCTAssertEqual(g.bays, 8)
        XCTAssertEqual(g.rise, 2.144, accuracy: 0.001)
        XCTAssertEqual(g.verticals.count + 1, 17)
        XCTAssertEqual(g.diagonals.count, 16)
        XCTAssertEqual(g.nodes.count, 34)
        XCTAssertEqual(try XCTUnwrap(g.kingPost).length, 2.644, accuracy: 0.001)
        // every diagonal rises toward the ridge: its upper end is the one nearer the middle
        for d in g.diagonals {
            let up = d.a.y > d.b.y ? d.a : d.b, down = d.a.y > d.b.y ? d.b : d.a
            XCTAssertLessThan(abs(up.x - 8), abs(down.x - 8))
            XCTAssertEqual(down.y, 0)
        }
    }

    func testPrattIsHowesMirror() throws {
        let g = try XCTUnwrap(RoofTruss.geometry(roof(.pratt)))
        XCTAssertEqual(g.verticals.count + 1, 17)
        // Pratt skips the panel at each support: its diagonals start at the first inside node
        XCTAssertEqual(g.diagonals.count, 14)
        for d in g.diagonals {
            let up = d.a.y > d.b.y ? d.a : d.b, down = d.a.y > d.b.y ? d.b : d.a
            XCTAssertGreaterThan(abs(up.x - 8), abs(down.x - 8))
        }
        let w = try XCTUnwrap(RoofTruss.geometry(roof(.warren)))
        XCTAssertEqual(w.diagonals.count, 16); XCTAssertEqual(w.verticals.count, 2)
    }

    func testTheSectionDrawsHoweLikeTheGeometry() {
        // the section and the schedule draw the same members: Howe adds diagonals from the supports Pratt doesn't have
        let howe = RoofSection(roof(.howe)).sketch.ops.count, pratt = RoofSection(roof(.pratt)).sketch.ops.count
        XCTAssertEqual(howe - pratt, 2 * 2, "two more diagonals, each drawn dark and light")
        XCTAssertEqual(RoofFrame(rawValue: "h"), .howe)
        XCTAssertTrue(RoofFrame.howe.isTruss)
        XCTAssertEqual(RoofFrame.ordered.count, RoofFrame.allCases.count)
    }

    func testScheduleOfAHoweRoof() throws {
        let v = roof(.howe), s = try XCTUnwrap(RoofTruss.schedule(v))
        // T1 on the three grid lines inside, as the plan draws them
        XCTAssertEqual(s.frames, 3)
        XCTAssertEqual(s.summary, "โครง T1 3 ชุด | ช่วง 16.00 ม. | ยาวตามสัน 24.00 ม. | มุม 15°")
        func row(_ n: Int) throws -> RoofTruss.Row { try XCTUnwrap(s.rows.first { $0.row == n }, "row \(n)") }
        let purlins = Roof.purlinLines(v).count
        XCTAssertEqual(try row(1).count, purlins); XCTAssertEqual(try row(1).length, Double(purlins) * 24, accuracy: 1e-9)
        XCTAssertNil(try row(1).perFrameCount)
        // top chords run to the eave's tip: (8 + 0.70) / cos 15°, two a truss
        XCTAssertEqual(try row(2).perFrameLength!, 2 * 8.7 / cos(15 * Double.pi / 180), accuracy: 1e-9)
        XCTAssertEqual(try row(2).count, 6)
        XCTAssertEqual(try row(3).perFrameLength!, 16)
        XCTAssertEqual(try row(4).perFrameCount, 16)
        XCTAssertEqual(try row(5).perFrameCount, 16)
        XCTAssertEqual(try row(6).length, 48)
        XCTAssertEqual(try row(7).perFrameLength!, 2.644, accuracy: 0.001)
        let plates = try XCTUnwrap(s.rows.first { $0.row == nil })
        XCTAssertEqual(plates.perFrameCount, 34); XCTAssertEqual(plates.count, 102)
        XCTAssertEqual(RoofTruss.totalText(plates), "102 แผ่น")
        XCTAssertEqual(RoofTruss.perFrameText(try row(3)), "1 | 16.00")
        XCTAssertEqual(RoofTruss.totalText(try row(3)), "3 | 48.00 ม.")
    }

    func testSteelWeightsOfAHoweRoof() throws {
        let v = roof(.howe), s = try XCTUnwrap(RoofTruss.schedule(v))
        func row(_ n: Int) throws -> RoofTruss.Row { try XCTUnwrap(s.rows.first { $0.row == n }, "row \(n)") }
        // purlins C-100x50x20x3.2 (5.50 kg/m in the tables), along the ridge: no per-truss weight
        let purlin = try row(1)
        XCTAssertEqual(purlin.size, "C-100x50x20x3.2")
        XCTAssertEqual(try XCTUnwrap(purlin.kgPerMetre), 5.50, accuracy: 0.01)
        XCTAssertNil(purlin.perFrameKg)
        XCTAssertEqual(try XCTUnwrap(purlin.kg), purlin.kgPerMetre! * purlin.length, accuracy: 1e-9)
        XCTAssertEqual(RoofTruss.kgPerMetreText(purlin), "5.50")
        XCTAssertEqual(RoofTruss.perFrameKgText(purlin), "-")
        // top chords 2C-150x50x20x3.2: per truss and three trusses
        let chord = try row(2), k = try XCTUnwrap(chord.kgPerMetre)
        XCTAssertEqual(k, 2 * 6.76, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(chord.perFrameKg), k * chord.perFrameLength!, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(chord.kg), 3 * chord.perFrameKg!, accuracy: 1e-9)
        // the fascia is wood and the plates are the engineer's: no weight, not in the total
        XCTAssertEqual(try row(6).size, "ไม้ 1\"x8\"")
        XCTAssertNil(try row(6).kgPerMetre)
        XCTAssertEqual(RoofTruss.kgText(try row(6)), "-")
        let plates = try XCTUnwrap(s.rows.first { $0.row == nil })
        XCTAssertNil(plates.kg)
        XCTAssertEqual(s.unweighed.map(\.row), [6])
        XCTAssertTrue(RoofTruss.steelNote(s).contains("ไม่คิดน้ำหนัก: เชิงชาย"))
        XCTAssertTrue(RoofTruss.steelNote(s).contains("ไม่รวมแผ่นประกับ"))
        let total = s.rows.compactMap(\.kg).reduce(0, +)
        XCTAssertEqual(s.steelKg, total, accuracy: 1e-9)
        XCTAssertEqual(s.steelPerFrameKg, [2, 3, 4, 5, 7].compactMap { n in s.rows.first { $0.row == n }?.perFrameKg }.reduce(0, +), accuracy: 1e-9)
        XCTAssertGreaterThan(s.steelKg, 1000)
        XCTAssertEqual(RoofTruss.steelKgText(s), "≈ " + RoofTruss.kgFormat(total))
        XCTAssertEqual(RoofTruss.kgFormat(1234.4), "1,234")
        XCTAssertEqual(RoofTruss.kgFormat(999.6), "1,000")
        XCTAssertEqual(RoofTruss.kgFormat(12), "12")
    }

    func testARafterTrussWeighsItsTubesButNotT2() throws {
        let s = try XCTUnwrap(RoofTruss.schedule(roof(.rafterTruss)))
        // tube chords ท่อกลม Ø1" หนา 1.6 (1.28 kg/m); T2 is a truss of its own, not a section
        let chord = try XCTUnwrap(s.rows.first { $0.row == 2 })
        XCTAssertEqual(try XCTUnwrap(chord.kgPerMetre), 1.28, accuracy: 0.01)
        if let t2 = s.rows.first(where: { $0.row == 5 }) {
            XCTAssertTrue(t2.size.hasPrefix("T2"))
            XCTAssertNil(t2.kgPerMetre)
        }
    }

    func testNoSteelSaysDash() throws {
        var v = roof(.howe)
        for n in 1...7 { Roof.setMember(&v, n, size: n == 6 ? "ไม้ 1\"x8\"" : "-") }
        let s = try XCTUnwrap(RoofTruss.schedule(v))
        XCTAssertEqual(RoofTruss.steelKgText(s), "-")
        XCTAssertEqual(RoofTruss.steelPerFrameKgText(s), "-")
    }

    func testRowsNotUsedAreLeftOutAndEmptyOnesSaySo() throws {
        var v = roof(.howe)
        Roof.setMember(&v, 5, size: "-")
        v[Roof.Key.member(4)] = nil
        let s = try XCTUnwrap(RoofTruss.schedule(v))
        XCTAssertNil(s.rows.first { $0.row == 5 })
        XCTAssertEqual(s.rows.first { $0.row == 4 }?.size, "ไม่ระบุขนาด")
    }

    func testRafterFramesCountRaftersAndTies() throws {
        let v = roof(.rafterTie), s = try XCTUnwrap(RoofTruss.schedule(v))
        // rafters @1.00 from 0.50 m in along 24 m: 24 pairs
        XCTAssertEqual(s.frames, 24)
        XCTAssertTrue(s.summary.hasPrefix("จันทัน 24 คู่ @1.00"))
        let tie = try XCTUnwrap(s.rows.first { $0.row == 3 })
        XCTAssertEqual(tie.perFrameLength!, 8, accuracy: 1e-9, "at half the rise the tie spans half the width")
        XCTAssertNil(s.rows.first { $0.row == nil }, "no gusset plates")
        XCTAssertNil(RoofTruss.details(v), "details are for the trusses")
    }

    func testOneBayRoofStillCountsOneTruss() throws {
        var v = roof(.howe)
        Roof.setSpans(&v, .y, [6])
        let s = try XCTUnwrap(RoofTruss.schedule(v))
        XCTAssertEqual(s.frames, 1)
        XCTAssertTrue(s.summary.contains("คิด 1 ชุด"))
    }

    func testDetailsStayInsideAndLabelTheEnteredSizes() throws {
        for f in [RoofFrame.normal, .pratt, .howe, .warren] {
            for bays in [2, 5, 8, 20] {
                for span in [[3.0], [4, 4, 4, 4], [6, 6, 6, 6, 6]] {
                    var v = roof(f, bays: bays)
                    Roof.setSpans(&v, .x, span)
                    let d = try XCTUnwrap(RoofTruss.details(v), "\(f) \(bays) \(span)")
                    for p in d.ops.flatMap(points) {
                        XCTAssertTrue(p.x.isFinite && p.y.isFinite)
                        XCTAssertTrue(p.x >= -1 && p.x <= RoofTruss.detailWidth + 1 && p.y >= -1 && p.y <= RoofTruss.detailHeight + 1,
                                      "\(f) \(bays) \(span): \(p)")
                    }
                }
            }
        }
        let texts = try XCTUnwrap(RoofTruss.details(roof(.howe))).ops.compactMap { op -> String? in
            if case let .textBox(t, _, _, _, _, _) = op { return t }
            if case let .text(t, _, _, _, _, _, _) = op { return t }
            return nil
        }
        XCTAssertTrue(texts.contains("คอร์ดบน 2C-150x50x20x3.2"), texts.joined(separator: " | "))
        XCTAssertTrue(texts.contains("เสากลาง □-100x100x3.2"))
        XCTAssertTrue(texts.contains("ครอบสันหลังคา"))
        XCTAssertTrue(texts.contains { $0.contains("ไม่ใช่แบบก่อสร้าง") })
    }

    func points(_ op: DrawOp) -> [Pt] {
        switch op {
        case let .line(a, b, _, _, _): return [a, b]
        case let .rect(r, _, _, _): return [Pt(r.x, r.y), Pt(r.maxX, r.y + r.h)]
        case let .circle(c, r, _, _, _): return [Pt(c.x - r, c.y - r), Pt(c.x + r, c.y + r)]
        case let .polygon(p, _, _, _), let .polyline(p, _, _, _): return p
        case let .text(_, at, _, _, _, _, _): return [at]
        case let .textBox(_, r, _, _, _, _): return [Pt(r.x, r.y)]
        default: return []
        }
    }

    /// `DRAWINGS_SVG_DIR=<dir>` writes the Howe section and the details of each truss, to look at.
    func testWriteSVGs() throws {
        guard let dir = ProcessInfo.processInfo.environment["DRAWINGS_SVG_DIR"] else { return }
        let url = URL(fileURLWithPath: dir)
        try RoofSection(roof(.howe)).sketch.svg().write(to: url.appendingPathComponent("c1-howe.svg"), atomically: true, encoding: .utf8)
        for f in [RoofFrame.normal, .pratt, .howe, .warren] {
            try XCTUnwrap(RoofTruss.details(roof(f))).svg().write(to: url.appendingPathComponent("c1-details-\(f.rawValue).svg"), atomically: true, encoding: .utf8)
        }
        var big = roof(.howe, bays: nil)
        Roof.setSpans(&big, .x, [6, 6, 6, 6, 6])
        try XCTUnwrap(RoofTruss.details(big)).svg().write(to: url.appendingPathComponent("c1-details-h30.svg"), atomically: true, encoding: .utf8)
    }
}
