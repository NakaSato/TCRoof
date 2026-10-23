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
        "h-h-hl1": 0x780a1b358da4c06d,
        "h-h-hl2": 0x29cfa45744400ba9,
        "h-h-hl3": 0x29cfa45744400ba9,
        "h-h-hl4": 0x29cfa45744400ba9,
        "h-h-hl5": 0x29cfa45744400ba9,
        "h-h-hl6": 0x59cbfded6ed210b5,
        "h-h-hl7": 0xc935e7ede86c46e3,
        "h-h-plan": 0x70205da87c3bf0a3,
        "h-h-plan-areas-chips": 0xa2fc780322752595,
        "h-h-plan-drag": 0x14876ac04bce336c,
        "h-h-pv": 0x25f17278310505bc,
        "h-h-pv-full": 0x798abdea72dbe5f5,
        "h-h-pv-full-drag": 0xa2ec92bec2739879,
        "h-v-hl1": 0x688b30a71755d4d1,
        "h-v-hl2": 0xb9fbccc4a2c1be93,
        "h-v-hl3": 0xb9fbccc4a2c1be93,
        "h-v-hl4": 0xb9fbccc4a2c1be93,
        "h-v-hl5": 0xb9fbccc4a2c1be93,
        "h-v-hl6": 0x7bbc0a06a26b15d7,
        "h-v-hl7": 0x7fcbb7df1daaf801,
        "h-v-plan": 0x74cc85fae54e1215,
        "h-v-plan-areas-chips": 0xf7e5e7a3b9448631,
        "h-v-plan-drag": 0x551d4424754773d8,
        "h-v-pv": 0x2d93bed3ecad7501,
        "h-v-pv-full": 0x6d345b503c8e92de,
        "h-v-pv-full-drag": 0x3c2d7d594b8647ba,
        "c-h-hl1": 0x8dbba85e38f6e052,
        "c-h-hl2": 0x31c86ff5325a0fe7,
        "c-h-hl3": 0xb63a058d47660fae,
        "c-h-hl4": 0x481c80a9c4541cfa,
        "c-h-hl5": 0xb63a058d47660fae,
        "c-h-hl6": 0x94bd9fc91942bd7a,
        "c-h-hl7": 0xef68a136bc1c4542,
        "c-h-plan": 0xb63a058d47660fae,
        "c-h-plan-areas-chips": 0x65718b73766f6f7a,
        "c-h-plan-drag": 0x5232b23b010af2dd,
        "c-h-pv": 0xac0847b8097a9e2d,
        "c-h-pv-full": 0x28447252b0459446,
        "c-h-pv-full-drag": 0xa56921e923bbea32,
        "c-v-hl1": 0xa98ae197178e0e36,
        "c-v-hl2": 0xca1bf295a75f9748,
        "c-v-hl3": 0xa265ecd9601ed7a8,
        "c-v-hl4": 0xaaf422a659bbcd84,
        "c-v-hl5": 0xa265ecd9601ed7a8,
        "c-v-hl6": 0x5d474013eb50ec7c,
        "c-v-hl7": 0xee7683ff8e7119b6,
        "c-v-plan": 0xa265ecd9601ed7a8,
        "c-v-plan-areas-chips": 0xe514c0fe100f63f0,
        "c-v-plan-drag": 0x56d96baf0a050f37,
        "c-v-pv": 0xe9c90edbc79f2db2,
        "c-v-pv-full": 0xbcb5b2dc16dc736a,
        "c-v-pv-full-drag": 0xbe3b25e370d4b4fe,
        "k-h-hl1": 0x82592e5434dc6777,
        "k-h-hl2": 0xe2fc32444c7b35aa,
        "k-h-hl3": 0x5e20ef7a132146c5,
        "k-h-hl4": 0x2575467a40ed4191,
        "k-h-hl5": 0x5e20ef7a132146c5,
        "k-h-hl6": 0x6cccfb0631664ddf,
        "k-h-hl7": 0x7b9dd099e4b437b5,
        "k-h-plan": 0x5e20ef7a132146c5,
        "k-h-plan-areas-chips": 0x808104feafbf14d3,
        "k-h-plan-drag": 0x85e5893750e3004a,
        "k-h-pv": 0xb1f1e846d8293412,
        "k-h-pv-full": 0x25f297ffb0f3ed4b,
        "k-h-pv-full-drag": 0x23a5d3fc6666cfcf,
        "k-v-hl1": 0xdaeb457deebc751c,
        "k-v-hl2": 0xe906190d354468d8,
        "k-v-hl3": 0x4fa2b48ce98c9f78,
        "k-v-hl4": 0xbbcbec2835b2fd54,
        "k-v-hl5": 0x4fa2b48ce98c9f78,
        "k-v-hl6": 0x851c4723a9b86c,
        "k-v-hl7": 0xfbd649cb75c042c6,
        "k-v-plan": 0x4fa2b48ce98c9f78,
        "k-v-plan-areas-chips": 0x1d70b1565a338d60,
        "k-v-plan-drag": 0xdbbe99078f3c8327,
        "k-v-pv": 0x130dc433941d005b,
        "k-v-pv-full": 0xcb3cc75d12cc64e4,
        "k-v-pv-full-drag": 0x9d67722c857d9b30,
        "n-h-hl1": 0x780a1b358da4c06d,
        "n-h-hl2": 0x29cfa45744400ba9,
        "n-h-hl3": 0x29cfa45744400ba9,
        "n-h-hl4": 0x29cfa45744400ba9,
        "n-h-hl5": 0x29cfa45744400ba9,
        "n-h-hl6": 0x59cbfded6ed210b5,
        "n-h-hl7": 0xc935e7ede86c46e3,
        "n-h-plan": 0x70205da87c3bf0a3,
        "n-h-plan-areas-chips": 0xa2fc780322752595,
        "n-h-plan-drag": 0x14876ac04bce336c,
        "n-h-pv": 0x25f17278310505bc,
        "n-h-pv-full": 0x798abdea72dbe5f5,
        "n-h-pv-full-drag": 0xa2ec92bec2739879,
        "n-v-hl1": 0x688b30a71755d4d1,
        "n-v-hl2": 0xb9fbccc4a2c1be93,
        "n-v-hl3": 0xb9fbccc4a2c1be93,
        "n-v-hl4": 0xb9fbccc4a2c1be93,
        "n-v-hl5": 0xb9fbccc4a2c1be93,
        "n-v-hl6": 0x7bbc0a06a26b15d7,
        "n-v-hl7": 0x7fcbb7df1daaf801,
        "n-v-plan": 0x74cc85fae54e1215,
        "n-v-plan-areas-chips": 0xf7e5e7a3b9448631,
        "n-v-plan-drag": 0x551d4424754773d8,
        "n-v-pv": 0x2d93bed3ecad7501,
        "n-v-pv-full": 0x6d345b503c8e92de,
        "n-v-pv-full-drag": 0x3c2d7d594b8647ba,
        "p-h-hl1": 0x780a1b358da4c06d,
        "p-h-hl2": 0x29cfa45744400ba9,
        "p-h-hl3": 0x29cfa45744400ba9,
        "p-h-hl4": 0x29cfa45744400ba9,
        "p-h-hl5": 0x29cfa45744400ba9,
        "p-h-hl6": 0x59cbfded6ed210b5,
        "p-h-hl7": 0xc935e7ede86c46e3,
        "p-h-plan": 0x70205da87c3bf0a3,
        "p-h-plan-areas-chips": 0xa2fc780322752595,
        "p-h-plan-drag": 0x14876ac04bce336c,
        "p-h-pv": 0x25f17278310505bc,
        "p-h-pv-full": 0x798abdea72dbe5f5,
        "p-h-pv-full-drag": 0xa2ec92bec2739879,
        "p-v-hl1": 0x688b30a71755d4d1,
        "p-v-hl2": 0xb9fbccc4a2c1be93,
        "p-v-hl3": 0xb9fbccc4a2c1be93,
        "p-v-hl4": 0xb9fbccc4a2c1be93,
        "p-v-hl5": 0xb9fbccc4a2c1be93,
        "p-v-hl6": 0x7bbc0a06a26b15d7,
        "p-v-hl7": 0x7fcbb7df1daaf801,
        "p-v-plan": 0x74cc85fae54e1215,
        "p-v-plan-areas-chips": 0xf7e5e7a3b9448631,
        "p-v-plan-drag": 0x551d4424754773d8,
        "p-v-pv": 0x2d93bed3ecad7501,
        "p-v-pv-full": 0x6d345b503c8e92de,
        "p-v-pv-full-drag": 0x3c2d7d594b8647ba,
        "r-h-hl1": 0x507fe6e334246652,
        "r-h-hl2": 0x3bb4f11c858e3539,
        "r-h-hl3": 0x3bb4f11c858e3539,
        "r-h-hl4": 0x3bb4f11c858e3539,
        "r-h-hl5": 0x21bb520b4d91a828,
        "r-h-hl6": 0x57aa82fa6a02824,
        "r-h-hl7": 0x1864590e8bbba340,
        "r-h-plan": 0x2b8c7ab8829ec5e8,
        "r-h-plan-areas-chips": 0x8e8bc910625719e4,
        "r-h-plan-drag": 0xbf62fd4775c5455b,
        "r-h-pv": 0xe24a62b65f3c93c4,
        "r-h-pv-full": 0x41f185b430d0c895,
        "r-h-pv-full-drag": 0x3fced9fc9d26e949,
        "r-v-hl1": 0x306137675b0f4f21,
        "r-v-hl2": 0xdda55e0bba702a5d,
        "r-v-hl3": 0xdda55e0bba702a5d,
        "r-v-hl4": 0xdda55e0bba702a5d,
        "r-v-hl5": 0x9e0554ec7c5a11be,
        "r-v-hl6": 0x3b7c1cde847cd127,
        "r-v-hl7": 0xe92435a5de584349,
        "r-v-plan": 0x74086c2cdf3a2445,
        "r-v-plan-areas-chips": 0x9f3230717123279b,
        "r-v-plan-drag": 0xe6ae640700984c9e,
        "r-v-pv": 0xb70bf42475521b25,
        "r-v-pv-full": 0x2d9f8a272d25a326,
        "r-v-pv-full-drag": 0xc556adcaa4fd2722,
        "w-h-hl1": 0x780a1b358da4c06d,
        "w-h-hl2": 0x29cfa45744400ba9,
        "w-h-hl3": 0x29cfa45744400ba9,
        "w-h-hl4": 0x29cfa45744400ba9,
        "w-h-hl5": 0x29cfa45744400ba9,
        "w-h-hl6": 0x59cbfded6ed210b5,
        "w-h-hl7": 0xc935e7ede86c46e3,
        "w-h-plan": 0x70205da87c3bf0a3,
        "w-h-plan-areas-chips": 0xa2fc780322752595,
        "w-h-plan-drag": 0x14876ac04bce336c,
        "w-h-pv": 0x25f17278310505bc,
        "w-h-pv-full": 0x798abdea72dbe5f5,
        "w-h-pv-full-drag": 0xa2ec92bec2739879,
        "w-v-hl1": 0x688b30a71755d4d1,
        "w-v-hl2": 0xb9fbccc4a2c1be93,
        "w-v-hl3": 0xb9fbccc4a2c1be93,
        "w-v-hl4": 0xb9fbccc4a2c1be93,
        "w-v-hl5": 0xb9fbccc4a2c1be93,
        "w-v-hl6": 0x7bbc0a06a26b15d7,
        "w-v-hl7": 0x7fcbb7df1daaf801,
        "w-v-plan": 0x74cc85fae54e1215,
        "w-v-plan-areas-chips": 0xf7e5e7a3b9448631,
        "w-v-plan-drag": 0x551d4424754773d8,
        "w-v-pv": 0x2d93bed3ecad7501,
        "w-v-pv-full": 0x6d345b503c8e92de,
        "w-v-pv-full-drag": 0x3c2d7d594b8647ba,
    ]
}
