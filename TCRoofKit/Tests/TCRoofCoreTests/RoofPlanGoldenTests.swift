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

    /// The dump with every decimal rounded to 4 places, so the last-digit differences between Darwin's and Linux's maths
    /// libraries (the PV layout's sun angles) don't change the fingerprint. 0.1 mm is far below anything drawn.
    static func rounded(_ s: String) -> String {
        let re = try! NSRegularExpression(pattern: #"-?\d+\.\d+(e[-+]?\d+)?"#)
        var out = "", last = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            let r = Range(m.range, in: s)!
            out += s[last..<r.lowerBound]
            let v = (Double(s[r]) ?? 0) * 10_000
            out += String(format: "%.4f", (v.rounded() == 0 ? 0 : v.rounded()) / 10_000)
            last = r.upperBound
        }
        return out + s[last...]
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
            return (c.name, Self.fnv(Self.rounded(Self.dump(c, mount: m))))
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
    /// (19/10/2569), and the cases with areas after `Roof.Area` gained `height` (the dump prints it; the drawing is unchanged); the Howe frame's cases added 20/10/2569; the cases with labels again after "·" became "|" (21/10/2569); every case again after the labels, the section mark's letter and the purlin callout got their CAD layers (22/10/2569: the ops are unchanged, only their tags); every case again after the dump rounds decimals to 4 places (23/10/2569), since the cloud (Linux) and macOS gave different PV fingerprints.
    static let expected: [String: UInt64] = [
        "h-h-hl1": 0x5b1fd84cab532885,
        "h-h-hl2": 0x248099ba78d53a61,
        "h-h-hl3": 0x248099ba78d53a61,
        "h-h-hl4": 0x248099ba78d53a61,
        "h-h-hl5": 0x248099ba78d53a61,
        "h-h-hl6": 0x67a73830732009ed,
        "h-h-hl7": 0xa02f956b92a070eb,
        "h-h-plan": 0x4c2bdfdaa4d1d83b,
        "h-h-plan-areas-chips": 0x1cbbed8d4495171d,
        "h-h-plan-drag": 0x6681a2541e29294,
        "h-h-pv": 0x25f17278310505bc,
        "h-h-pv-full": 0x798abdea72dbe5f5,
        "h-h-pv-full-drag": 0xa2ec92bec2739879,
        "h-v-hl1": 0xb1cf43e68a403df1,
        "h-v-hl2": 0x5113045561123eb3,
        "h-v-hl3": 0x5113045561123eb3,
        "h-v-hl4": 0x5113045561123eb3,
        "h-v-hl5": 0x5113045561123eb3,
        "h-v-hl6": 0xe3be314c677d3a37,
        "h-v-hl7": 0xc61f3fe0f80243a1,
        "h-v-plan": 0xcd2cf6159bc70235,
        "h-v-plan-areas-chips": 0x7d4376de939a2c11,
        "h-v-plan-drag": 0xe601a7172a660a38,
        "h-v-pv": 0x2d93bed3ecad7501,
        "h-v-pv-full": 0x6d345b503c8e92de,
        "h-v-pv-full-drag": 0x3c2d7d594b8647ba,
        "c-h-hl1": 0xbbb79e084cf2b96a,
        "c-h-hl2": 0x3db9d75a01cb2c2f,
        "c-h-hl3": 0x7453743620a9a6e6,
        "c-h-hl4": 0x2b979282126bd9f2,
        "c-h-hl5": 0x7453743620a9a6e6,
        "c-h-hl6": 0x641c8af472ba5452,
        "c-h-hl7": 0x263a35a918dee02a,
        "c-h-plan": 0x7453743620a9a6e6,
        "c-h-plan-areas-chips": 0x178ea1002c05ef32,
        "c-h-plan-drag": 0x6762c158018292e5,
        "c-h-pv": 0xac0847b8097a9e2d,
        "c-h-pv-full": 0x28447252b0459446,
        "c-h-pv-full-drag": 0xa56921e923bbea32,
        "c-v-hl1": 0xf8068b592e59cb06,
        "c-v-hl2": 0x9a0077a311e9a898,
        "c-v-hl3": 0x15547842e0361938,
        "c-v-hl4": 0xfe0f69e113f12914,
        "c-v-hl5": 0x15547842e0361938,
        "c-v-hl6": 0x5f40890f6c69d42c,
        "c-v-hl7": 0x9552db0cba6b7e86,
        "c-v-plan": 0x15547842e0361938,
        "c-v-plan-areas-chips": 0x8606374b7ceee7a0,
        "c-v-plan-drag": 0x4c1018bc3b473467,
        "c-v-pv": 0xe9c90edbc79f2db2,
        "c-v-pv-full": 0xbcb5b2dc16dc736a,
        "c-v-pv-full-drag": 0xbe3b25e370d4b4fe,
        "k-h-hl1": 0x7c2eace91da4698f,
        "k-h-hl2": 0xc271cbf79f8bd032,
        "k-h-hl3": 0x19ccd4144a8df67d,
        "k-h-hl4": 0xb40d14df46919a49,
        "k-h-hl5": 0x19ccd4144a8df67d,
        "k-h-hl6": 0x5ae7c8c32c9c5517,
        "k-h-hl7": 0x79e76efbd30cc93d,
        "k-h-plan": 0x19ccd4144a8df67d,
        "k-h-plan-areas-chips": 0xea104df067bb19eb,
        "k-h-plan-drag": 0xdc066530f05834b2,
        "k-h-pv": 0xb1f1e846d8293412,
        "k-h-pv-full": 0x25f297ffb0f3ed4b,
        "k-h-pv-full-drag": 0x23a5d3fc6666cfcf,
        "k-v-hl1": 0x6333cac85006f5ac,
        "k-v-hl2": 0x3f8e8457789061e8,
        "k-v-hl3": 0x8a925cda4cb31748,
        "k-v-hl4": 0x493a12eb4c862124,
        "k-v-hl5": 0x8a925cda4cb31748,
        "k-v-hl6": 0x5f7c088f816be25c,
        "k-v-hl7": 0x4055f6c53559b2d6,
        "k-v-plan": 0x8a925cda4cb31748,
        "k-v-plan-areas-chips": 0x954d601e7aa0b510,
        "k-v-plan-drag": 0xae76b0d8e6a35b17,
        "k-v-pv": 0x130dc433941d005b,
        "k-v-pv-full": 0xcb3cc75d12cc64e4,
        "k-v-pv-full-drag": 0x9d67722c857d9b30,
        "n-h-hl1": 0x5b1fd84cab532885,
        "n-h-hl2": 0x248099ba78d53a61,
        "n-h-hl3": 0x248099ba78d53a61,
        "n-h-hl4": 0x248099ba78d53a61,
        "n-h-hl5": 0x248099ba78d53a61,
        "n-h-hl6": 0x67a73830732009ed,
        "n-h-hl7": 0xa02f956b92a070eb,
        "n-h-plan": 0x4c2bdfdaa4d1d83b,
        "n-h-plan-areas-chips": 0x1cbbed8d4495171d,
        "n-h-plan-drag": 0x6681a2541e29294,
        "n-h-pv": 0x25f17278310505bc,
        "n-h-pv-full": 0x798abdea72dbe5f5,
        "n-h-pv-full-drag": 0xa2ec92bec2739879,
        "n-v-hl1": 0xb1cf43e68a403df1,
        "n-v-hl2": 0x5113045561123eb3,
        "n-v-hl3": 0x5113045561123eb3,
        "n-v-hl4": 0x5113045561123eb3,
        "n-v-hl5": 0x5113045561123eb3,
        "n-v-hl6": 0xe3be314c677d3a37,
        "n-v-hl7": 0xc61f3fe0f80243a1,
        "n-v-plan": 0xcd2cf6159bc70235,
        "n-v-plan-areas-chips": 0x7d4376de939a2c11,
        "n-v-plan-drag": 0xe601a7172a660a38,
        "n-v-pv": 0x2d93bed3ecad7501,
        "n-v-pv-full": 0x6d345b503c8e92de,
        "n-v-pv-full-drag": 0x3c2d7d594b8647ba,
        "p-h-hl1": 0x5b1fd84cab532885,
        "p-h-hl2": 0x248099ba78d53a61,
        "p-h-hl3": 0x248099ba78d53a61,
        "p-h-hl4": 0x248099ba78d53a61,
        "p-h-hl5": 0x248099ba78d53a61,
        "p-h-hl6": 0x67a73830732009ed,
        "p-h-hl7": 0xa02f956b92a070eb,
        "p-h-plan": 0x4c2bdfdaa4d1d83b,
        "p-h-plan-areas-chips": 0x1cbbed8d4495171d,
        "p-h-plan-drag": 0x6681a2541e29294,
        "p-h-pv": 0x25f17278310505bc,
        "p-h-pv-full": 0x798abdea72dbe5f5,
        "p-h-pv-full-drag": 0xa2ec92bec2739879,
        "p-v-hl1": 0xb1cf43e68a403df1,
        "p-v-hl2": 0x5113045561123eb3,
        "p-v-hl3": 0x5113045561123eb3,
        "p-v-hl4": 0x5113045561123eb3,
        "p-v-hl5": 0x5113045561123eb3,
        "p-v-hl6": 0xe3be314c677d3a37,
        "p-v-hl7": 0xc61f3fe0f80243a1,
        "p-v-plan": 0xcd2cf6159bc70235,
        "p-v-plan-areas-chips": 0x7d4376de939a2c11,
        "p-v-plan-drag": 0xe601a7172a660a38,
        "p-v-pv": 0x2d93bed3ecad7501,
        "p-v-pv-full": 0x6d345b503c8e92de,
        "p-v-pv-full-drag": 0x3c2d7d594b8647ba,
        "r-h-hl1": 0x26aab593b4d9711a,
        "r-h-hl2": 0x46b3f206347b9a71,
        "r-h-hl3": 0x46b3f206347b9a71,
        "r-h-hl4": 0x46b3f206347b9a71,
        "r-h-hl5": 0x7b1809acbd2bd490,
        "r-h-hl6": 0x6e1ba136e31a356c,
        "r-h-hl7": 0xc9b3d55b215026c8,
        "r-h-plan": 0xbbc118803d54c230,
        "r-h-plan-areas-chips": 0x81f112c1bc0438cc,
        "r-h-plan-drag": 0x47e2fca84ae81233,
        "r-h-pv": 0xe24a62b65f3c93c4,
        "r-h-pv-full": 0x41f185b430d0c895,
        "r-h-pv-full-drag": 0x3fced9fc9d26e949,
        "r-v-hl1": 0xe4f9ca2f9f09b3c1,
        "r-v-hl2": 0x46104d149d1cbd7d,
        "r-v-hl3": 0x46104d149d1cbd7d,
        "r-v-hl4": 0x46104d149d1cbd7d,
        "r-v-hl5": 0x450f27370c9dab1e,
        "r-v-hl6": 0x5cd8e0107bc2e287,
        "r-v-hl7": 0xb5e663873bf7c6e9,
        "r-v-plan": 0xd373ec43a4abb7e5,
        "r-v-plan-areas-chips": 0x3578e217cd9a3fb,
        "r-v-plan-drag": 0x9161ae9e058705fe,
        "r-v-pv": 0xb70bf42475521b25,
        "r-v-pv-full": 0x2d9f8a272d25a326,
        "r-v-pv-full-drag": 0xc556adcaa4fd2722,
        "w-h-hl1": 0x5b1fd84cab532885,
        "w-h-hl2": 0x248099ba78d53a61,
        "w-h-hl3": 0x248099ba78d53a61,
        "w-h-hl4": 0x248099ba78d53a61,
        "w-h-hl5": 0x248099ba78d53a61,
        "w-h-hl6": 0x67a73830732009ed,
        "w-h-hl7": 0xa02f956b92a070eb,
        "w-h-plan": 0x4c2bdfdaa4d1d83b,
        "w-h-plan-areas-chips": 0x1cbbed8d4495171d,
        "w-h-plan-drag": 0x6681a2541e29294,
        "w-h-pv": 0x25f17278310505bc,
        "w-h-pv-full": 0x798abdea72dbe5f5,
        "w-h-pv-full-drag": 0xa2ec92bec2739879,
        "w-v-hl1": 0xb1cf43e68a403df1,
        "w-v-hl2": 0x5113045561123eb3,
        "w-v-hl3": 0x5113045561123eb3,
        "w-v-hl4": 0x5113045561123eb3,
        "w-v-hl5": 0x5113045561123eb3,
        "w-v-hl6": 0xe3be314c677d3a37,
        "w-v-hl7": 0xc61f3fe0f80243a1,
        "w-v-plan": 0xcd2cf6159bc70235,
        "w-v-plan-areas-chips": 0x7d4376de939a2c11,
        "w-v-plan-drag": 0xe601a7172a660a38,
        "w-v-pv": 0x2d93bed3ecad7501,
        "w-v-pv-full": 0x6d345b503c8e92de,
        "w-v-pv-full-drag": 0x3c2d7d594b8647ba,
    ]
}
