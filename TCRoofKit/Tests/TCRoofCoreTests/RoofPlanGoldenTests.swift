import XCTest
@testable import TCRoofCore

/// Pins `RoofPlan`'s whole output (every op, tag, layout point and PV figure) over a matrix of roofs, so restructuring
/// the drawing code can't change what it draws. Run with `ROOF_GOLDEN_RECORD=1` to print new fingerprints after an
/// intended change to the drawing.
final class RoofPlanGoldenTests: XCTestCase {
    struct Case { let name: String; let values: Values; let mode: RoofPlan.Mode
        var chips = false; var dragging: (Double, Double, Double, Double)? = nil; var highlight: Int? = nil
        var ridge = Roof.Ridge.h }

    static func roof(_ f: RoofFrame, _ r: Roof.Ridge, areas: Bool, tables: Bool) -> Values {
        var v = Values()
        v["spansX"] = .text("1.5,4,4,4,4,1.5"); v["spansY"] = .text("1.5,4.5,4,4.5,1.5")
        Roof.setRidge(&v, r); Roof.setFrame(&v, f)
        if areas {
            v["obst"] = .obstacles([Obstacle(x: "6.44", y: "1", w: "0.8", h: "6.6", kind: "sky"),
                                    Obstacle(x: "11.76", y: "8.4", w: "0.8", h: "6.6", kind: "sky", canCover: true),
                                    Obstacle(label: "ถังน้ำ", x: "2", y: "2", w: "1.2", h: "1.2")])
            Roof.addArea(&v, kind: Roof.keepOutKind, x1: 14, y1: 9, x2: 18, y2: 12)
        }
        return v
    }

    static var cases: [Case] {
        var out: [Case] = []
        for f in RoofFrame.allCases {
            for r in [Roof.Ridge.h, .v] {
                let plain = roof(f, r, areas: false, tables: false), full = roof(f, r, areas: true, tables: true)
                let tag = "\(f.rawValue)-\(r.rawValue)"
                out.append(Case(name: "\(tag)-plan", values: plain, mode: .structure))
                out.append(Case(name: "\(tag)-plan-areas-chips", values: full, mode: .structure, chips: true))
                out.append(Case(name: "\(tag)-plan-drag", values: plain, mode: .structure, dragging: (2, 2, 5, 4)))
                for n in 1...7 { out.append(Case(name: "\(tag)-hl\(n)", values: plain, mode: .structure, highlight: n)) }
                out.append(Case(name: "\(tag)-pv", values: plain, mode: .pv, ridge: r))
                out.append(Case(name: "\(tag)-pv-full", values: full, mode: .pv, ridge: r))
                out.append(Case(name: "\(tag)-pv-full-drag", values: full, mode: .pv, dragging: (3, 3, 6, 5), ridge: r))
            }
        }
        return out
    }

    /// The PV layout with the old golden module, at 15° N.
    static func mount(_ v: Values) -> RoofMountLayout {
        var std = RoofMountStandard(); std.moduleLength = 2.278; std.moduleWidth = 1.134; std.moduleWp = 570
        return RoofMountLayout.best(RoofMount.input(v, latitude: 15), standard: std)
    }

    static func dump(_ c: Case, mount: RoofMountLayout?) -> String {
        let p = RoofPlan(c.values, mode: c.mode, chips: c.chips, dragging: c.dragging, highlight: c.highlight, mount: mount)
        var s = "\(p.sketch.width)x\(p.sketch.height)\n"
        for (op, t) in zip(p.sketch.ops, p.tags) { s += "\(t ?? "-") \(op)\n" }
        let l = p.layout
        s += "chips \(l.chips.map { "\($0.axis)\($0.index) \($0.value) \($0.at)" })\n"
        s += "nodes \(l.nodes.map { "\($0.i),\($0.j) \($0.at) \($0.post)" })\n"
        s += "areas \(l.areas.map { "\($0.area) \($0.box)" })\n"
        s += "add \(l.addX) \(l.addY) origin \(l.origin) k \(l.k) \(l.lx) \(l.ly)\n"
        if c.mode == .pv {
            s += "pv \(p.pv.count) \(p.pv.kWp) \(l.slots.map { "\($0.ref.face)\($0.ref.row).\($0.ref.column) \($0.module) \($0.outline)" })\n"
        } else {
            s += "pv 0 0.0 0 [] []\n"
        }
        return s
    }

    /// FNV-1a, stable across runs (Swift's `Hasher` is seeded per process).
    static func fnv(_ s: String) -> UInt64 {
        s.utf8.reduce(0xcbf2_9ce4_8422_2325 as UInt64) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }

    /// The cases picked, each against its fingerprint. The PV layout is searched once per roof (a drag doesn't change it).
    func check(_ pick: (Case) -> Bool) {
        let cases = Self.cases.filter(pick)
        var mounts: [String: RoofMountLayout] = [:]
        let got = Dictionary(uniqueKeysWithValues: cases.map { c -> (String, UInt64) in
            var m: RoofMountLayout?
            if c.mode == .pv {
                let key = c.name.replacingOccurrences(of: "-drag", with: "")
                m = mounts[key] ?? Self.mount(c.values)
                mounts[key] = m
            }
            return (c.name, Self.fnv(Self.dump(c, mount: m)))
        })
        if ProcessInfo.processInfo.environment["ROOF_GOLDEN_RECORD"] != nil {
            print("ROOF_GOLDEN " + got.keys.sorted().map { "\"\($0)\": 0x\(String(got[$0]!, radix: 16))" }.joined(separator: ", "))
            return
        }
        XCTAssertFalse(got.isEmpty)
        for (name, h) in got.sorted(by: { $0.key < $1.key }) { XCTAssertEqual(h, Self.expected[name], name) }
    }

    /// Every case has a fingerprint, and every fingerprint a case.
    func testTheCasesAreTheRecordedOnes() {
        XCTAssertEqual(Set(Self.cases.map(\.name)), Set(Self.expected.keys))
    }

    // split so `swift test --parallel` spreads the PV searches
    func testStructurePlanUnchanged() { check { $0.mode == .structure } }
    func testPVPlanUnchangedRidgeAlongX() { check { $0.mode == .pv && $0.ridge == .h } }
    func testPVPlanUnchangedRidgeAlongY() { check { $0.mode == .pv && $0.ridge == .v } }

    /// Recorded from the drawing before RoofPlan.init was split (4/10/2569); the PV cases again with the roof PV engine
    /// (19/10/2569), and the cases with areas after `Roof.Area` gained `height` (the dump prints it; the drawing is unchanged); the Howe frame's cases added 20/10/2569; the cases with labels again after "·" became "|" (21/10/2569); every case again after the labels, the section mark's letter and the purlin callout got their CAD layers (22/10/2569: the ops are unchanged, only their tags).
    static let expected: [String: UInt64] = [
        "h-h-hl1": 0x9f5aed772410ffb8,
        "h-h-hl2": 0x3a088d42e47fdc82,
        "h-h-hl3": 0x3a088d42e47fdc82,
        "h-h-hl4": 0x3a088d42e47fdc82,
        "h-h-hl5": 0x3a088d42e47fdc82,
        "h-h-hl6": 0xc122341263064c19,
        "h-h-hl7": 0x4dd640da642847fe,
        "h-h-plan": 0x9bfb89ad30c123be,
        "h-h-plan-areas-chips": 0x85a2250a03d611a3,
        "h-h-plan-drag": 0xee84b967170150ff,
        "h-h-pv": 0x8c2fb6775e19b048,
        "h-h-pv-full": 0x14ebd4c9fa97b05,
        "h-h-pv-full-drag": 0x709a68aef29f15e3,
        "h-v-hl1": 0xdc609142df2ecc4e,
        "h-v-hl2": 0xf1f22f4303bd5da8,
        "h-v-hl3": 0xf1f22f4303bd5da8,
        "h-v-hl4": 0xf1f22f4303bd5da8,
        "h-v-hl5": 0xf1f22f4303bd5da8,
        "h-v-hl6": 0x6eb108a936f8000d,
        "h-v-hl7": 0x1723cb2c4ac7cd2a,
        "h-v-plan": 0x2c4e772f533c0a2e,
        "h-v-plan-areas-chips": 0xcf48705599996273,
        "h-v-plan-drag": 0x7213c88087b63059,
        "h-v-pv": 0x74546735cc2cefaa,
        "h-v-pv-full": 0x775c9a04f4e85c76,
        "h-v-pv-full-drag": 0x22799c2216a328,
        "c-h-hl1": 0xe97346717a7a52d9,
        "c-h-hl2": 0x6f7383cd2627045f,
        "c-h-hl3": 0x7e5f1fbac881a6f5,
        "c-h-hl4": 0xa6a3f807f90bd6c9,
        "c-h-hl5": 0x7e5f1fbac881a6f5,
        "c-h-hl6": 0x24241cfd2af14f8,
        "c-h-hl7": 0x133253b4de4d5c7d,
        "c-h-plan": 0x7e5f1fbac881a6f5,
        "c-h-plan-areas-chips": 0x2718b617e7042572,
        "c-h-plan-drag": 0x7889ca5a7b7dd9bc,
        "c-h-pv": 0x63f91030a63b77e3,
        "c-h-pv-full": 0x231e705d649bd975,
        "c-h-pv-full-drag": 0xcd97c0432475bcf,
        "c-v-hl1": 0xb8e986e61ca48fe3,
        "c-v-hl2": 0x331fd8a7dbd0f761,
        "c-v-hl3": 0x2c7f61b5a69356dd,
        "c-v-hl4": 0xa9cb5bc436f9ecd,
        "c-v-hl5": 0x2c7f61b5a69356dd,
        "c-v-hl6": 0x545408980d893444,
        "c-v-hl7": 0x109f0db5d25c537f,
        "c-v-plan": 0x2c7f61b5a69356dd,
        "c-v-plan-areas-chips": 0xc9ceb6a926ca4134,
        "c-v-plan-drag": 0x834da7dd33d88438,
        "c-v-pv": 0xaece4039b53cbeac,
        "c-v-pv-full": 0x1b4ffba86c2b0022,
        "c-v-pv-full-drag": 0xe8441683a741b36c,
        "k-h-hl1": 0xd4dff661fc0a8e27,
        "k-h-hl2": 0x35dfcbc3857376cf,
        "k-h-hl3": 0x9f3477df0e0b6205,
        "k-h-hl4": 0xfa744c248771d819,
        "k-h-hl5": 0x9f3477df0e0b6205,
        "k-h-hl6": 0x57f2f406f71caa8,
        "k-h-hl7": 0x49bb49f42e03840d,
        "k-h-plan": 0x9f3477df0e0b6205,
        "k-h-plan-areas-chips": 0xee2818d75e089a02,
        "k-h-plan-drag": 0xb1bb532943351a8,
        "k-h-pv": 0x51ebf68f9bc10a1e,
        "k-h-pv-full": 0x3848686cede2ff67,
        "k-h-pv-full-drag": 0xcbec3480db358f25,
        "k-v-hl1": 0x711f8e2297ced30c,
        "k-v-hl2": 0x411dee5384776808,
        "k-v-hl3": 0xb195fa2319a371ac,
        "k-v-hl4": 0xe229ea5db4e37bfc,
        "k-v-hl5": 0xb195fa2319a371ac,
        "k-v-hl6": 0xc40fa30fcefb2b43,
        "k-v-hl7": 0xc4d9eede22e5a7ee,
        "k-v-plan": 0xb195fa2319a371ac,
        "k-v-plan-areas-chips": 0x799f8f710c1fea3d,
        "k-v-plan-drag": 0xdffe65251df34031,
        "k-v-pv": 0x3d40294c84c1fee0,
        "k-v-pv-full": 0xabed6c2d16adfd18,
        "k-v-pv-full-drag": 0x44b475cfb55e9732,
        "n-h-hl1": 0x9f5aed772410ffb8,
        "n-h-hl2": 0x3a088d42e47fdc82,
        "n-h-hl3": 0x3a088d42e47fdc82,
        "n-h-hl4": 0x3a088d42e47fdc82,
        "n-h-hl5": 0x3a088d42e47fdc82,
        "n-h-hl6": 0xc122341263064c19,
        "n-h-hl7": 0x4dd640da642847fe,
        "n-h-plan": 0x9bfb89ad30c123be,
        "n-h-plan-areas-chips": 0x85a2250a03d611a3,
        "n-h-plan-drag": 0xee84b967170150ff,
        "n-h-pv": 0x8c2fb6775e19b048,
        "n-h-pv-full": 0x14ebd4c9fa97b05,
        "n-h-pv-full-drag": 0x709a68aef29f15e3,
        "n-v-hl1": 0xdc609142df2ecc4e,
        "n-v-hl2": 0xf1f22f4303bd5da8,
        "n-v-hl3": 0xf1f22f4303bd5da8,
        "n-v-hl4": 0xf1f22f4303bd5da8,
        "n-v-hl5": 0xf1f22f4303bd5da8,
        "n-v-hl6": 0x6eb108a936f8000d,
        "n-v-hl7": 0x1723cb2c4ac7cd2a,
        "n-v-plan": 0x2c4e772f533c0a2e,
        "n-v-plan-areas-chips": 0xcf48705599996273,
        "n-v-plan-drag": 0x7213c88087b63059,
        "n-v-pv": 0x74546735cc2cefaa,
        "n-v-pv-full": 0x775c9a04f4e85c76,
        "n-v-pv-full-drag": 0x22799c2216a328,
        "p-h-hl1": 0x9f5aed772410ffb8,
        "p-h-hl2": 0x3a088d42e47fdc82,
        "p-h-hl3": 0x3a088d42e47fdc82,
        "p-h-hl4": 0x3a088d42e47fdc82,
        "p-h-hl5": 0x3a088d42e47fdc82,
        "p-h-hl6": 0xc122341263064c19,
        "p-h-hl7": 0x4dd640da642847fe,
        "p-h-plan": 0x9bfb89ad30c123be,
        "p-h-plan-areas-chips": 0x85a2250a03d611a3,
        "p-h-plan-drag": 0xee84b967170150ff,
        "p-h-pv": 0x8c2fb6775e19b048,
        "p-h-pv-full": 0x14ebd4c9fa97b05,
        "p-h-pv-full-drag": 0x709a68aef29f15e3,
        "p-v-hl1": 0xdc609142df2ecc4e,
        "p-v-hl2": 0xf1f22f4303bd5da8,
        "p-v-hl3": 0xf1f22f4303bd5da8,
        "p-v-hl4": 0xf1f22f4303bd5da8,
        "p-v-hl5": 0xf1f22f4303bd5da8,
        "p-v-hl6": 0x6eb108a936f8000d,
        "p-v-hl7": 0x1723cb2c4ac7cd2a,
        "p-v-plan": 0x2c4e772f533c0a2e,
        "p-v-plan-areas-chips": 0xcf48705599996273,
        "p-v-plan-drag": 0x7213c88087b63059,
        "p-v-pv": 0x74546735cc2cefaa,
        "p-v-pv-full": 0x775c9a04f4e85c76,
        "p-v-pv-full-drag": 0x22799c2216a328,
        "r-h-hl1": 0xdc90f088826b52a5,
        "r-h-hl2": 0xca7b8ea7fa0b5931,
        "r-h-hl3": 0xca7b8ea7fa0b5931,
        "r-h-hl4": 0xca7b8ea7fa0b5931,
        "r-h-hl5": 0x2e23d561e9d9244f,
        "r-h-hl6": 0x7f9fdd697290bd1e,
        "r-h-hl7": 0x968f1a0ea2b069b,
        "r-h-plan": 0x9f85b98264ac15e3,
        "r-h-plan-areas-chips": 0x76f90b2bb3d1ce18,
        "r-h-plan-drag": 0x276cf3060a4efbb6,
        "r-h-pv": 0xe9a9c566065cdd8c,
        "r-h-pv-full": 0x5644c44b1e2976c1,
        "r-h-pv-full-drag": 0x9f5d85557a7e8927,
        "r-v-hl1": 0xa7e6f70faa54f36e,
        "r-v-hl2": 0xcd161c9791088222,
        "r-v-hl3": 0xcd161c9791088222,
        "r-v-hl4": 0xcd161c9791088222,
        "r-v-hl5": 0x2e5a55d599689250,
        "r-v-hl6": 0xb719de3235a8acd1,
        "r-v-hl7": 0x83a033568acc98b2,
        "r-v-plan": 0xf4097c710c7a9b8e,
        "r-v-plan-areas-chips": 0x4f8d0ad56ffaa507,
        "r-v-plan-drag": 0xe500c0c5f292f2b,
        "r-v-pv": 0x48573438f7b8d1fe,
        "r-v-pv-full": 0x21d1a23d006d54f2,
        "r-v-pv-full-drag": 0xb8577d23e071ac4,
        "w-h-hl1": 0x9f5aed772410ffb8,
        "w-h-hl2": 0x3a088d42e47fdc82,
        "w-h-hl3": 0x3a088d42e47fdc82,
        "w-h-hl4": 0x3a088d42e47fdc82,
        "w-h-hl5": 0x3a088d42e47fdc82,
        "w-h-hl6": 0xc122341263064c19,
        "w-h-hl7": 0x4dd640da642847fe,
        "w-h-plan": 0x9bfb89ad30c123be,
        "w-h-plan-areas-chips": 0x85a2250a03d611a3,
        "w-h-plan-drag": 0xee84b967170150ff,
        "w-h-pv": 0x8c2fb6775e19b048,
        "w-h-pv-full": 0x14ebd4c9fa97b05,
        "w-h-pv-full-drag": 0x709a68aef29f15e3,
        "w-v-hl1": 0xdc609142df2ecc4e,
        "w-v-hl2": 0xf1f22f4303bd5da8,
        "w-v-hl3": 0xf1f22f4303bd5da8,
        "w-v-hl4": 0xf1f22f4303bd5da8,
        "w-v-hl5": 0xf1f22f4303bd5da8,
        "w-v-hl6": 0x6eb108a936f8000d,
        "w-v-hl7": 0x1723cb2c4ac7cd2a,
        "w-v-plan": 0x2c4e772f533c0a2e,
        "w-v-plan-areas-chips": 0xcf48705599996273,
        "w-v-plan-drag": 0x7213c88087b63059,
        "w-v-pv": 0x74546735cc2cefaa,
        "w-v-pv-full": 0x775c9a04f4e85c76,
        "w-v-pv-full-drag": 0x22799c2216a328,
    ]
}
