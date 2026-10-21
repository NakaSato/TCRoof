import XCTest
@testable import TCRoofCore

final class SingleLineTests: XCTestCase {
    // MARK: fixture

    static func breaker(at: String = "", af: String = "", ic: String = "", brand: String = "", target: String = "", condition: String = "") -> Breaker {
        Breaker(at: at, af: af, ic: ic, poles: "3P", brand: brand, target: target, condition: condition)
    }

    /// The survey the previews were drawn from: 5 transformers, MDP-1 with three outgoing breakers, 2 × 60 kW of PV.
    static func fixture() -> Job {
        var v = Values()
        v["capacity"] = .text("120")
        v["projectName"] = .text("สถานีสูบน้ำ"); v["docNo"] = .text("215")
        v["meterNo"] = .text("020-123456"); v["meterKV"] = .choice("22", other: ""); v["meterPhase"] = .choice("3 เฟส", other: "")
        v["meterCA"] = .text("020012345678"); v["meterRate"] = .text("4.2.2 TOU"); v["meterCT"] = .text("400/5")

        var t1 = Transformer(kva: "630")
        t1.type = "oil"; t1.voltage = "22k/230-400"; t1.vectorGroup = "Dyn11"; t1.impedance = "4.14"; t1.brand = "Tirathai"; t1.serial = "63-1234"; t1.year = "2558"
        t1.hasLA = true; t1.condition = "พอใช้"; t1.conditionNote = "น้ำมันซึมที่วาล์วถ่าย"; t1.hvProtection = "Drop Out Fuse"
        var mdp = Board(name: "MDP-1", isMain: true, at: "800")
        mdp.mainType = "ACB"; mdp.af = "800"; mdp.icu = "50"; mdp.brand = "Schneider MTZ1 08"; mdp.condition = "พอใช้"; mdp.location = "ห้องไฟฟ้า อาคารสูบน้ำ"
        mdp.breakers = [breaker(at: "400", af: "400", ic: "36", brand: "Schneider", target: "ตู้ไฟฟ้า โรงสูบน้ำ (B1)", condition: "ดี"),
                        breaker(at: "250", af: "250", ic: "25", brand: "LS", target: "ตู้ไฟฟ้า โรงกรอง (B1)", condition: "ชำรุด"),
                        breaker(at: "100", target: "ตู้ไฟฟ้า อาคารสำนักงาน (B1)", condition: "ดี")]
        var sdb = Board(name: "SDB ระบบกรอง", at: "400"); sdb.location = "โรงกรอง"
        t1.setBoards([mdp, sdb])

        var t2 = Transformer(kva: "250"); t2.voltage = "22k/230-400"; t2.setBoards([Board(name: "MDB-ADMIN", isMain: true, at: "400")])
        let t3 = Transformer(kva: "400"), t4 = Transformer(kva: "250"), t5 = Transformer(kva: "160")
        v["trafos"] = .transformers([t1, t2, t3, t4, t5])

        let b1a = SurveyModule(type: .panel, name: "โรงสูบน้ำ", values: Values(["loadKW": .text("85"), "loadTime": .text("10 น.")]))
        let b1b = SurveyModule(type: .panel, name: "โรงกรอง")
        let b1c = SurveyModule(type: .panel, name: "อาคารสำนักงาน", values: Values(["loadKW": .text("22"), "loadTime": .text("10 น.")]))
        let b2 = SurveyModule(type: .inverter, values: Values(["inverterCount": .text("2")]))
        let b4 = SurveyModule(type: .backfeed, values: Values(["level": .choice("กันย้อนที่แรงต่ำ", other: "")]))
        return Job(values: v, modules: [b1a, b1b, b1c, b2, b4])
    }

    // MARK: calculations

    func testBreakerSizing() {
        XCTAssertEqual(SingleLine.breakerAT(kw: 60), 125)
        XCTAssertEqual(SingleLine.breakerAT(kw: 120), 250)
        XCTAssertEqual(SingleLine.breakerAF(at: 125), 125)
        XCTAssertEqual(SingleLine.standardInverter(60), 60)
        XCTAssertEqual(SingleLine.standardInverter(61), 75)
        XCTAssertEqual(SingleLine.standardInverter(500), 110)
        XCTAssertEqual(SingleLine.cable(forAT: 125), "CV 4×35 + G16")
        XCTAssertEqual(SingleLine.cable(forAT: 250), "CV 4×120 + G25")
        XCTAssertEqual(SingleLine.busbar(forAT: 250), "25 × 5")
    }

    func testShortCircuit() throws {
        let isc = try XCTUnwrap(SingleLine.shortCircuit(kva: 630, zPercent: 4.14))
        XCTAssertEqual(isc, 22.0, accuracy: 0.05)
        XCTAssertNil(SingleLine.shortCircuit(kva: 630, zPercent: 0))
        XCTAssertEqual(SingleLine.requiredIC(isc: 22.7), 25)
        XCTAssertEqual(SingleLine.requiredIC(isc: 26), 36)
    }

    func testBreakerCheckClassification() {
        XCTAssertEqual(SingleLine.classify(ic: 50, isc: 22), .ok)
        XCTAssertEqual(SingleLine.classify(ic: 36, isc: 22), .ok)
        XCTAssertEqual(SingleLine.classify(ic: 25, isc: 22), .marginal)
        XCTAssertEqual(SingleLine.classify(ic: 22, isc: 22), .marginal)
        XCTAssertEqual(SingleLine.classify(ic: 15, isc: 22), .insufficient)
        XCTAssertEqual(SingleLine.classify(ic: nil, isc: 22), .unknown)
        XCTAssertEqual(SingleLine.classify(ic: 50, isc: nil), .unknown)
    }

    // MARK: model

    func testFixtureModel() throws {
        let m = SingleLine.build(Self.fixture())
        XCTAssertEqual(m.transformers.count, 5)
        XCTAssertFalse(m.zeroExportHV)
        XCTAssertTrue(m.hasB4)
        XCTAssertEqual(m.sourceLabel, "ระบบจำหน่าย กฟภ. 22 kV, 3Ø 3W, 50 Hz")
        XCTAssertEqual(m.pv.inverterKW, 60)
        XCTAssertEqual(m.pv.inverterAT, 125)
        XCTAssertEqual(m.pv.totalAT, 250)
        XCTAssertEqual(m.pv.requiredIC, 25)
        XCTAssertEqual(try XCTUnwrap(m.isc), 22.0, accuracy: 0.05)
        XCTAssertFalse(m.iscAssumedZ)
        // TX3…5 have only kVA: collapsed nameplate
        XCTAssertFalse(m.transformers[0].collapsed)
        XCTAssertTrue(m.transformers[2].collapsed)
        XCTAssertEqual(m.transformers[2].lines.last?.text, "ป้ายพิกัดยังไม่ครบ")
        // breaker check: main (50), 36, 25, and the one without IC
        XCTAssertEqual(m.checks.map(\.state), [.ok, .ok, .marginal, .unknown])
        XCTAssertEqual(m.checks.last?.value, "ยังไม่รู้")
        // loads come from B1
        let cb = try XCTUnwrap(m.connectionBoard)
        XCTAssertEqual(cb.breakers[0].destination.last?.text, "โหลด 85 kW @10 น.")
        XCTAssertEqual(cb.breakers[1].destination.last?.text, "โหลด ? (B1)")
        XCTAssertTrue(m.assumptions.contains { $0.id == "length" })
    }

    func testMissingItems() {
        let m = SingleLine.build(Self.fixture())
        // blocking: CB3 IC/AF/brand on the connection bus, %Z of TX2…5
        let blocking = m.blocking.map(\.label)
        XCTAssertTrue(blocking.contains { $0.contains("CB3") && $0.contains("IC kA") && $0.contains("AF") && $0.contains("ยี่ห้อ") }, "\(blocking)")
        XCTAssertEqual(m.blocking.filter { $0.id.hasPrefix("z") }.count, 4)
        XCTAssertFalse(m.blocking.contains { $0.id == "capacity" || $0.id == "invCount" })
        XCTAssertEqual(m.missing.count, m.blocking.count + m.others.count)
        // fixing the IC / AF / brand of CB3 removes its item
        var job = Self.fixture()
        var ts = job.values.transformers("trafos")
        ts[0].boards[0].breakers[2].ic = "25"; ts[0].boards[0].breakers[2].af = "100"; ts[0].boards[0].breakers[2].brand = "ABB"
        job.values["trafos"] = .transformers(ts)
        let after = SingleLine.build(job)
        XCTAssertEqual(after.missing.count, m.missing.count - 1)
        XCTAssertFalse(after.blocking.contains { $0.label.contains("CB3") })
    }

    func testPVFromB2Sizes() throws {
        var job = Self.fixture()
        let i = try XCTUnwrap(job.modules.firstIndex { $0.type == .inverter })
        job.modules[i].values["invSizes"] = .text("60,60,80")
        job.modules[i].values["inverterCount"] = .text("3")
        let m = SingleLine.build(job)
        XCTAssertEqual(m.pv.inverterSizes, [60, 60, 80])
        XCTAssertNil(m.pv.inverterKW)
        XCTAssertEqual(m.pv.inverterAT, 200)
        XCTAssertEqual(m.pv.totalAT, 500)
        XCTAssertEqual(m.pv.mainCable, "2×(4×1C 120) + G35")
        XCTAssertEqual(m.pv.inverterSummary, "60 + 60 + 80 kW")
        XCTAssertFalse(m.assumptions.contains { $0.id == "invKW" })
        // without sizes the SLD keeps its A1 ÷ B2 fallback
        XCTAssertTrue(SingleLine.build(Self.fixture()).assumptions.contains { $0.id == "invKW" })
        // equal sizes give the per-inverter kW
        job.modules[i].values["invSizes"] = .text("60,60"); job.modules[i].values["inverterCount"] = .text("2")
        let e = SingleLine.build(job)
        XCTAssertEqual(e.pv.inverterKW, 60)
        XCTAssertEqual(e.pv.totalAT, 250)
        XCTAssertEqual(e.pv.mainCable, "4×1C 120 + G25")
    }

    func testPVBlockingWhenA1AndB2Empty() {
        var job = Self.fixture()
        job.values["capacity"] = nil
        job.modules.removeAll { $0.type == .inverter }
        let m = SingleLine.build(job)
        XCTAssertTrue(m.blocking.contains { $0.id == "capacity" })
        XCTAssertTrue(m.blocking.contains { $0.id == "invCount" })
        XCTAssertNil(m.pv.totalAT)
        XCTAssertTrue(m.pv.rows.dropFirst().allSatisfy { $0.value.isMissing })
    }

    func testAssumedZWhenImpedanceMissing() throws {
        var job = Self.fixture()
        var ts = job.values.transformers("trafos")
        ts[0].impedance = ""
        job.values["trafos"] = .transformers(ts)
        let m = SingleLine.build(job)
        XCTAssertTrue(m.iscAssumedZ)
        XCTAssertEqual(try XCTUnwrap(m.isc), 22.7, accuracy: 0.1)
        XCTAssertTrue(m.blocking.contains { $0.id == "z0" })
    }

    func testHVOverrideAndSelection() {
        var job = Self.fixture()
        XCTAssertTrue(SingleLine.build(job, hvOverride: true).zeroExportHV)
        job.modules.removeAll { $0.type == .backfeed }
        let m = SingleLine.build(job)
        XCTAssertFalse(m.hasB4)
        XCTAssertFalse(m.zeroExportHV)
        // connect at TX2 (sldTransformer) — its %Z is missing, so Isc uses the assumed 4 %
        job.values["sldTransformer"] = .text("1")
        let m2 = SingleLine.build(job)
        XCTAssertEqual(m2.connection.trafo, 1)
        XCTAssertTrue(m2.iscAssumedZ)
        XCTAssertEqual(m2.connectionBoard?.name, "MDB-ADMIN")
    }

    func testOldJobBuilds() {
        var v = Values()
        v["trafos"] = .transformers([Transformer(kva: "630", mdb: ["800", "", "250"])])
        let m = SingleLine.build(Job(values: v))
        XCTAssertEqual(m.transformers.count, 1)
        XCTAssertEqual(m.transformers[0].boards.map(\.name), ["MDB1", "MDB2", "MDB3"])
        XCTAssertNotNil(m.isc)
        XCTAssertTrue(m.iscAssumedZ)
        _ = SingleLineLayout.draw(m)
        // and a job with nothing at all
        let empty = SingleLine.build(Job())
        XCTAssertTrue(empty.transformers.isEmpty)
        let d = SingleLineLayout.draw(empty)
        XCTAssertGreaterThan(d.height, 100)
    }

    // MARK: layout

    func testLayoutHitsAndHeight() {
        let d = SingleLineLayout.draw(SingleLine.build(Self.fixture()))
        XCTAssertEqual(d.width, 1560)
        XCTAssertGreaterThan(d.height, 1400)
        XCTAssertTrue(d.hits.contains { $0.target.trafo == 0 && $0.target.board == nil })
        XCTAssertTrue(d.hits.contains { $0.target.breaker != nil })
        XCTAssertTrue(d.hits.contains { $0.target.page == .module(.inverter) })
        for n in 1...5 {
            var job = Self.fixture()
            job.values["trafos"] = .transformers(Array(job.values.transformers("trafos").prefix(n)))
            XCTAssertGreaterThan(SingleLineLayout.draw(SingleLine.build(job)).height, 1000)
            XCTAssertGreaterThan(SingleLineLayout.draw(SingleLine.build(job, hvOverride: true)).height, 1000)
        }
    }

    /// Writes the diagram as SVG for a visual check: `SLD_SVG=/tmp/sld swift test --filter testWriteSVG`.
    func testWriteSVG() throws {
        guard let dir = ProcessInfo.processInfo.environment["SLD_SVG"] else { throw XCTSkip("set SLD_SVG to a folder") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var demo = Self.fixture()
        demo.updated = Date().addingTimeInterval(86_400 * 365)
        try JobStore.encoder.encode(demo).write(to: URL(fileURLWithPath: dir + "/job.json"))
        for (name, hv) in [("lv", false), ("hv", true)] {
            let d = SingleLineLayout.draw(SingleLine.build(Self.fixture(), hvOverride: hv))
            try Self.svg(d.sketch).write(toFile: dir + "/\(name).svg", atomically: true, encoding: .utf8)
            let l2 = SingleLineLayout.draw(SingleLine.build(Self.level2(), hvOverride: hv))
            try Self.svg(l2.sketch).write(toFile: dir + "/level2-\(name).svg", atomically: true, encoding: .utf8)
        }
        // 14 feeders (a continuation row) and one transformer with four sub-boards side by side
        var wide = Self.level2()
        var trs = wide.values.transformers("trafos")
        var b = trs[0].boards
        b[0].breakers += (0..<10).map { k in var br = Self.breaker(at: "63", af: "100", ic: "25", brand: "LS"); br.load = "LC\(k + 40)"; br.cable = "4x16,1x6-IEC01"; return br }
        trs[0].setBoards(b + (2...4).map { Board(name: "SDB \($0)", at: "100") })
        wide.values["trafos"] = .transformers(Array(trs.prefix(1)))
        let w = SingleLineLayout.draw(SingleLine.build(wide))
        try Self.svg(w.sketch).write(toFile: dir + "/level2-wrap.svg", atomically: true, encoding: .utf8)
    }

    static func svg(_ s: Sketch) -> String {
        func c(_ x: RGBA) -> String { String(format: "rgb(%d,%d,%d)", Int(x.r * 255), Int(x.g * 255), Int(x.b * 255)) }
        func esc(_ t: String) -> String { t.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") }
        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(s.width)\" height=\"\(s.height)\" viewBox=\"0 0 \(s.width) \(s.height)\" font-family=\"Thonburi, Helvetica\">\n"
        for op in s.ops {
            switch op {
            case let .line(a, b, w, col, dash):
                out += "<line x1=\"\(a.x)\" y1=\"\(a.y)\" x2=\"\(b.x)\" y2=\"\(b.y)\" stroke=\"\(c(col))\" stroke-width=\"\(w)\"" + (dash.isEmpty ? "" : " stroke-dasharray=\"\(dash.map { String($0) }.joined(separator: " "))\"") + "/>\n"
            case let .rect(r, st, f, w):
                out += "<rect x=\"\(r.x)\" y=\"\(r.y)\" width=\"\(r.w)\" height=\"\(r.h)\" fill=\"\(f.map(c) ?? "none")\" stroke=\"\(st.map(c) ?? "none")\" stroke-width=\"\(w)\"/>\n"
            case let .circle(p, r, st, f, w):
                out += "<circle cx=\"\(p.x)\" cy=\"\(p.y)\" r=\"\(r)\" fill=\"\(f.map(c) ?? "none")\" stroke=\"\(st.map(c) ?? "none")\" stroke-width=\"\(w)\"/>\n"
            case let .polygon(ps, st, f, w):
                out += "<polygon points=\"\(ps.map { "\($0.x),\($0.y)" }.joined(separator: " "))\" fill=\"\(f.map(c) ?? "none")\" stroke=\"\(st.map(c) ?? "none")\" stroke-width=\"\(w)\"/>\n"
            case let .text(t, at, size, bold, col, al, angle):
                let anchor = al == .left ? "start" : al == .center ? "middle" : "end"
                out += "<text x=\"\(at.x)\" y=\"\(at.y + size * 0.35)\" font-size=\"\(size)\" font-weight=\"\(bold ? 700 : 400)\" fill=\"\(c(col))\" text-anchor=\"\(anchor)\"" + (angle == 0 ? "" : " transform=\"rotate(\(angle) \(at.x) \(at.y))\"") + ">\(esc(t))</text>\n"
            default: break
            }
        }
        return out + "</svg>\n"
    }

    // MARK: decided 2026-10-19

    func testHVProtectionSymbols() {
        func texts(_ ops: [DrawOp]) -> [String] { ops.compactMap { if case let .text(t, _, _, _, _, _, _) = $0 { return t }; return nil } }
        func polygons(_ ops: [DrawOp]) -> Int { ops.filter { if case .polygon = $0 { return true }; return false }.count }
        XCTAssertTrue(texts(SLSymbols.hvDevice("VCB", x: 0, y: 0)).contains("VCB"))
        XCTAssertEqual(polygons(SLSymbols.hvDevice("DO fuse", x: 0, y: 0)), 1)
        XCTAssertEqual(polygons(SLSymbols.hvDevice("Drop Out Fuse", x: 0, y: 0)), 1)
        XCTAssertEqual(SLSymbols.hvDevice("DS", x: 0, y: 0).count, SLSymbols.openSwitch(x: 0, y: 0).count)
        // each transformer draws its own; the tap draws the one they share
        var job = Self.fixture()
        var trs = job.values.transformers("trafos")
        for i in trs.indices { trs[i].hvProtection = "VCB" }
        job.values["trafos"] = .transformers(trs)
        let sl = SingleLine.build(job)
        XCTAssertEqual(sl.protectionKind, "VCB")
        XCTAssertTrue(sl.transformers.allSatisfy { $0.protection == "VCB" })
        let ops = SingleLineLayout.draw(sl).sketch.ops
        // each transformer's symbol, the tap's symbol and the tap's protection label
        XCTAssertEqual(texts(ops).filter { $0 == "VCB" }.count, sl.transformers.count + 2)
    }

    func testFTSOnlyWithB5() {
        var job = Self.fixture()
        job.modules.removeAll { $0.type == .fts }
        let without = SingleLineLayout.draw(SingleLine.build(job))
        XCTAssertNil(without.ftsBox)
        let texts = without.sketch.ops.compactMap { op -> String? in if case let .text(t, _, _, _, _, _, _) = op { return t }; return nil }
        XCTAssertFalse(texts.contains("ปุ่ม Emergency"))
        XCTAssertFalse(texts.contains { $0.contains("FTS") })
        job.modules.append(SurveyModule(type: .fts))
        XCTAssertNotNil(SingleLineLayout.draw(SingleLine.build(job)).ftsBox)
    }

    // MARK: level 2 — detailed MDP

    /// The fixture with the level 2 answers of `img/sld.py` on MDP-1: cables, conduits, loads, floors, a spare, busbar, ground.
    static func level2() -> Job {
        var job = fixture()
        var trs = job.values.transformers("trafos")
        var b = trs[0].boards
        b[0].busbar = "4x300A. Cu. BUSBAR W/GROUND BUS"; b[0].ground = "1x35-IEC01 ø20 PVC."
        b[0].breakers[0].cable = "4x50,1x10-IEC01"; b[0].breakers[0].conduit = "IN WIRE WAY"
        b[0].breakers[0].load = "LC11"; b[0].breakers[0].floor = "1st FL."
        b[0].breakers[1].cable = "4x50,1x10-IEC01"; b[0].breakers[1].conduit = "ø50mm. UPVC"; b[0].breakers[1].floor = "2nd FL."
        var spare = breaker(at: "30", af: "100", ic: "25", brand: "LS"); spare.spare = true; spare.cable = "ignored"; spare.load = "ignored"
        b[0].breakers.append(spare)
        trs[0].setBoards(b)
        job.values["trafos"] = .transformers(trs)
        return job
    }

    static func texts(_ ops: [DrawOp]) -> [(String, Double)] {
        ops.compactMap { if case let .text(t, _, _, _, _, _, angle) = $0 { return (t, angle) }; return nil }
    }

    func testLevel2FieldsDecodeFromOldJSON() throws {
        let old = #"{"at":"100","af":"100","ic":"25","poles":"3P","brand":"LS","target":"x","condition":"ดี","count":2}"#
        let br = try JSONDecoder().decode(Breaker.self, from: Data(old.utf8))
        XCTAssertEqual([br.cable, br.conduit, br.load, br.floor], ["", "", "", ""])
        XCTAssertFalse(br.spare)
        XCTAssertEqual(br.count, 2)
        let bd = try JSONDecoder().decode(Board.self, from: Data(#"{"name":"MDP","at":"800"}"#.utf8))
        XCTAssertEqual([bd.busbar, bd.ground], ["", ""])
        // and they round-trip
        let job = Self.level2()
        let back = try JSONDecoder().decode(Job.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(back.values.transformers("trafos"), job.values.transformers("trafos"))
    }

    func testLevel2FieldsLeaveCompletionAndMissingAlone() {
        let a = Self.fixture(), b = Self.level2()
        // the spare breaker added in level2() is a whole breaker; compare with the same breaker unmarked
        var plain = a
        var trs = plain.values.transformers("trafos")
        var bd = trs[0].boards
        bd[0].breakers.append(Self.breaker(at: "30", af: "100", ic: "25", brand: "LS"))
        trs[0].setBoards(bd)
        plain.values["trafos"] = .transformers(trs)
        XCTAssertEqual(plain.completion.filled, b.completion.filled)
        XCTAssertEqual(plain.completion.total, b.completion.total)
        XCTAssertEqual(a.completion.total, b.completion.total)
        let missA = Set(SingleLine.build(plain).missing.map(\.label)), missB = Set(SingleLine.build(b).missing.map(\.label))
        // the only difference: a spare breaker has no load to look up in B1
        XCTAssertTrue(missB.isSubset(of: missA))
        XCTAssertEqual(Array(missA.subtracting(missB)), ["โหลด CB4  (B1)"])
        XCTAssertEqual(SingleLine.build(b).blocking.map(\.label), SingleLine.build(plain).blocking.map(\.label))
    }

    func testLevel2Model() throws {
        let m = SingleLine.build(Self.level2())
        let cb = try XCTUnwrap(m.connectionBoard)
        XCTAssertEqual(cb.busbar, "4x300A. Cu. BUSBAR W/GROUND BUS")
        XCTAssertEqual(cb.ground, "1x35-IEC01 ø20 PVC.")
        XCTAssertEqual(cb.breakers[0].feeder, "4x50,1x10-IEC01, IN WIRE WAY")
        XCTAssertEqual(cb.breakers[0].destination.map(\.text).prefix(2), ["LC11", "(1st FL.)"])
        XCTAssertTrue(cb.breakers[0].destination[0].bold)
        // no load name: the level 1 lines, then the floor
        XCTAssertEqual(cb.breakers[1].destination.map(\.text).prefix(3), ["ตู้ไฟฟ้า", "โรงกรอง", "(2nd FL.)"])
        let spare = cb.breakers[3]
        XCTAssertTrue(spare.spare)
        XCTAssertEqual(spare.feeder, "")
        XCTAssertTrue(spare.destination.isEmpty)
        XCTAssertEqual(spare.name, "SPARE")
    }

    func testLevel2Drawing() {
        let ops = SingleLineLayout.draw(SingleLine.build(Self.level2())).sketch.ops
        let t = Self.texts(ops)
        XCTAssertTrue(t.contains { $0.0 == "4x50,1x10-IEC01, IN WIRE WAY" && $0.1 == -90 })
        XCTAssertTrue(t.contains { $0.0 == "4x50,1x10-IEC01, ø50mm. UPVC" && $0.1 == -90 })
        XCTAssertTrue(t.contains { $0.0 == "1x35-IEC01 ø20 PVC." && $0.1 == -90 })
        for s in ["SPARE", "LC11", "(1st FL.)", "4x300A. Cu. BUSBAR W/GROUND BUS", "GROUND ROD", "N", "G"] {
            XCTAssertTrue(t.contains { $0.0 == s }, s)
        }
        XCTAssertFalse(t.contains { $0.0.contains("ignored") })
        // three load blocks for three breakers in use; the spare has none
        let loads = ops.filter { if case let .rect(b, nil, _, _) = $0 { return b.w == 36 && b.h == 18 }; return false }
        XCTAssertEqual(loads.count, 3)
        // level 1 draws none of it
        let plain = Self.texts(SingleLineLayout.draw(SingleLine.build(Self.fixture())).sketch.ops)
        XCTAssertFalse(plain.contains { $0.0 == "GROUND ROD" || $0.0 == "SPARE" })
    }

    func testLevel2Notes() throws {
        let m = SingleLine.build(Self.level2())
        func note(_ id: String) throws -> SLNote { try XCTUnwrap(m.notes.first { $0.id == id }, id) }
        XCTAssertEqual(try note("flc").text, "กระแสพิกัดหม้อแปลง TX1 630 kVA ที่ 400 V = 909 A")
        // 800 AT / 909 A = 0.88: inside 0.8–1.25
        XCTAssertFalse(try note("mainFLC").flagged)
        XCTAssertEqual(try note("feeders").text, "วงจรย่อย MDP-1 4 วงจร (ใช้งาน 3 | สำรอง 1)")
        // CB3 has no AT? it has 100; no diversity: 400 + 250 + 100
        XCTAssertEqual(try note("sumAT").text, "รวมพิกัดวงจรที่ใช้งาน 750 AT (ไม่คิด diversity)")
        // 2 inverters of 60 kW from A1 ÷ B2 → 120 kW on 630 kVA
        XCTAssertEqual(try note("pvShare").text, "กำลัง PV ต่อหม้อแปลง 120 kW ÷ 630 kVA = 19 %")
        XCTAssertTrue(try note("pvBus").text.hasSuffix("(ตรวจพิกัดบัสบาร์กับวิศวกร)"))
        XCTAssertTrue(try note("pvBus").text.contains("เมน 800 AT"))
        XCTAssertFalse(m.notes.contains { $0.id.hasPrefix("af") })
        // notes are drawn under the diagram and add no missing item
        XCTAssertTrue(Self.texts(SingleLineLayout.draw(m).sketch.ops).contains { $0.0 == "• " + (try! note("flc")).text })

        // AT over AF, the main far from the full-load current and PV over the transformer are flagged, never missing
        var job = Self.level2()
        var trs = job.values.transformers("trafos")
        var b = trs[0].boards
        b[0].at = "300"; b[0].af = "250"
        b[0].breakers[0].af = "250"
        trs[0].setBoards(b); trs[0].kva = "100"
        job.values["trafos"] = .transformers(trs)
        let f = SingleLine.build(job)
        XCTAssertTrue(f.notes.first { $0.id == "mainFLC" }!.flagged)
        XCTAssertTrue(f.notes.first { $0.id == "pvShare" }!.flagged)
        XCTAssertEqual(f.notes.filter { $0.id.hasPrefix("af") && $0.flagged }.count, 2)
        XCTAssertEqual(f.missing.count, m.missing.count)
    }

    func testFeedersWrapOrNarrow() {
        func job(_ n: Int) -> Job {
            var j = Self.fixture()
            var trs = j.values.transformers("trafos")
            var b = trs[0].boards
            b[0].breakers = (0..<n).map { _ in Self.breaker(at: "100", af: "100", ic: "36", brand: "LS") }
            trs[0].setBoards(b)
            j.values["trafos"] = .transformers(trs)
            return j
        }
        func feederXs(_ d: SingleLineDrawing) -> [Double] {
            d.hits.filter { $0.target.breaker != nil && $0.box.h == 250 }.map { $0.box.x + 20 }
        }
        // 10 feeders: one row, at least 60 apart, all inside the page and clear of the PV breaker
        let ten = SingleLineLayout.draw(SingleLine.build(job(10)))
        let xs = feederXs(ten).sorted()
        XCTAssertEqual(xs.count, 10)
        XCTAssertEqual(Set(ten.hits.filter { $0.target.breaker != nil && $0.box.h == 250 }.map(\.box.y)).count, 1)
        XCTAssertGreaterThanOrEqual(zip(xs, xs.dropFirst()).map { $1 - $0 }.min()!, 60 - 1e-9)
        XCTAssertLessThan(xs.last!, 1330 - 116)
        XCTAssertFalse(Self.texts(ten.sketch.ops).contains { $0.0.hasSuffix("…ต่อ") })
        // 14 feeders: a continuation row, every breaker still drawn and tappable; the page grows
        let fourteen = SingleLineLayout.draw(SingleLine.build(job(14)))
        XCTAssertEqual(feederXs(fourteen).count, 14)
        XCTAssertEqual(Set(fourteen.hits.filter { $0.target.breaker != nil && $0.box.h == 250 }.map(\.box.y)).count, 2)
        XCTAssertTrue(Self.texts(fourteen.sketch.ops).contains { $0.0 == "MDP-1 …ต่อ" })
        XCTAssertGreaterThan(fourteen.height, ten.height + 300)
        XCTAssertTrue(fourteen.hits.allSatisfy { $0.box.maxX <= 1560 })
    }

    func testBoardsSideBySideOnOneTransformer() {
        var job = Self.fixture()
        var trs = job.values.transformers("trafos")
        let main = trs[0].boards[0]
        trs[0].setBoards([main] + (1...4).map { Board(name: "SDB \($0)", at: "100") })
        job.values["trafos"] = .transformers(Array(trs.prefix(1)))
        let d = SingleLineLayout.draw(SingleLine.build(job))
        let frames = d.hits.filter { $0.target.trafo == 0 && $0.target.board != nil && $0.target.board! > 0 && $0.target.breaker == nil && $0.box.w == 180 }
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(Set(frames.map(\.box.y)).count, 1, "one row on a common LV line")
        XCTAssertTrue(frames.allSatisfy { $0.box.maxX <= 1500 })
        // five transformers have no room: their boards still stack
        var five = Self.fixture()
        var t5 = five.values.transformers("trafos")
        t5[1].setBoards([t5[1].boards[0], Board(name: "SDB A", at: "100"), Board(name: "SDB B", at: "100")])
        five.values["trafos"] = .transformers(t5)
        let f = SingleLineLayout.draw(SingleLine.build(five)).hits.filter { $0.target.trafo == 1 && $0.target.breaker == nil && $0.box.w == 180 }
        XCTAssertEqual(Set(f.map(\.box.x)).count, 1)
    }

    func testTheBreakerRuleIsNotAnAssumption() {
        let sl = SingleLine.build(Self.fixture())
        XCTAssertFalse(sl.assumptions.contains { $0.text.hasPrefix("เบรกเกอร์ = I × 1.25") })
        XCTAssertEqual(SLConstants.breakerFactor, 1.25)
    }
}

