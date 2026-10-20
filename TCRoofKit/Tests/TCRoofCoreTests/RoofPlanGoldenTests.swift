import XCTest
@testable import TCRoofCore

/// Pins `RoofPlan`'s whole output (every op, tag, layout point and PV figure) over a matrix of roofs, so restructuring
/// the drawing code can't change what it draws. Run with `ROOF_GOLDEN_RECORD=1` to print new fingerprints after an
/// intended change to the drawing.
final class RoofPlanGoldenTests: XCTestCase {
    struct Case { let name: String; let values: Values; let mode: RoofPlan.Mode
        var chips = false; var dragging: (Double, Double, Double, Double)? = nil; var highlight: Int? = nil }

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
                out.append(Case(name: "\(tag)-pv", values: plain, mode: .pv))
                out.append(Case(name: "\(tag)-pv-full", values: full, mode: .pv))
                out.append(Case(name: "\(tag)-pv-full-drag", values: full, mode: .pv, dragging: (3, 3, 6, 5)))
            }
        }
        return out
    }

    static func dump(_ c: Case) -> String {
        // the PV layout with the old golden module, at 15° N
        var std = RoofMountStandard(); std.moduleLength = 2.278; std.moduleWidth = 1.134; std.moduleWp = 570
        let mount = c.mode == .pv ? RoofMountLayout.best(RoofMount.input(c.values, latitude: 15), standard: std) : nil
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

    func testRoofPlanOutputUnchanged() {
        let got = Dictionary(uniqueKeysWithValues: Self.cases.map { ($0.name, Self.fnv(Self.dump($0))) })
        if ProcessInfo.processInfo.environment["ROOF_GOLDEN_RECORD"] != nil {
            print("ROOF_GOLDEN " + got.keys.sorted().map { "\"\($0)\": 0x\(String(got[$0]!, radix: 16))" }.joined(separator: ", "))
            return
        }
        XCTAssertEqual(got.count, Self.expected.count)
        for (name, h) in got.sorted(by: { $0.key < $1.key }) { XCTAssertEqual(h, Self.expected[name], name) }
    }

    /// Recorded from the drawing before RoofPlan.init was split (4/10/2569); the PV cases again with the roof PV engine
    /// (19/10/2569), and the cases with areas after `Roof.Area` gained `height` (the dump prints it; the drawing is unchanged); the Howe frame's cases added 20/10/2569.
    static let expected: [String: UInt64] = [
        "h-h-hl1": 0xa9bae10368a4f888,
        "h-h-hl2": 0xb9093ff05ef15b92,
        "h-h-hl3": 0xb9093ff05ef15b92,
        "h-h-hl4": 0xb9093ff05ef15b92,
        "h-h-hl5": 0xb9093ff05ef15b92,
        "h-h-hl6": 0xa1309f658c7467c9,
        "h-h-hl7": 0x118a817c7dd1f40e,
        "h-h-plan": 0x74bc650e28d420ce,
        "h-h-plan-areas-chips": 0x227907e1d6ea8296,
        "h-h-plan-drag": 0x845ce39e06c04587,
        "h-h-pv": 0x9122661771e85409,
        "h-h-pv-full": 0x18112d95adf7b61,
        "h-h-pv-full-drag": 0x8c3e1d80a889801f,
        "h-v-hl1": 0xbf3fd02a88770fcb,
        "h-v-hl2": 0x96fbdae7b55ee59,
        "h-v-hl3": 0x96fbdae7b55ee59,
        "h-v-hl4": 0x96fbdae7b55ee59,
        "h-v-hl5": 0x96fbdae7b55ee59,
        "h-v-hl6": 0x36503bb84893438e,
        "h-v-hl7": 0xaf789bb4eb8b279b,
        "h-v-plan": 0x351fa1819b94f42f,
        "h-v-plan-areas-chips": 0xba483ea392fffe0d,
        "h-v-plan-drag": 0x86b0ae56992c9efa,
        "h-v-pv": 0x66a5c9a4d6763701,
        "h-v-pv-full": 0xf866e4389fb0624a,
        "h-v-pv-full-drag": 0xd6b1b95010cb438,
        "c-h-hl1": 0x8fdab8eee450deab,
        "c-h-hl2": 0x12622933c3ec6131,
        "c-h-hl3": 0xe297348bcc1cf2ef,
        "c-h-hl4": 0xb67d1cfce9b25db3,
        "c-h-hl5": 0xe297348bcc1cf2ef,
        "c-h-hl6": 0x6e26c5868a1d74d2,
        "c-h-hl7": 0x5da85243d10956b7,
        "c-h-plan": 0xe297348bcc1cf2ef,
        "c-h-plan-areas-chips": 0x92aebff338122b0b,
        "c-h-plan-drag": 0xc33e05d3681b1f76,
        "c-h-pv": 0xe7b4c502ce90334,
        "c-h-pv-full": 0xf5e4dc7ef93c5767,
        "c-h-pv-full-drag": 0xb654c08126026c6d,
        "c-v-hl1": 0x98775f22b77115d7,
        "c-v-hl2": 0xc57af26c8ac43e05,
        "c-v-hl3": 0x49672cbd449528b1,
        "c-v-hl4": 0x8bd1e3ab8a1a1dd1,
        "c-v-hl5": 0x49672cbd449528b1,
        "c-v-hl6": 0xf610f161c24ea510,
        "c-v-hl7": 0x5b1b1c1f6c940fb3,
        "c-v-plan": 0x49672cbd449528b1,
        "c-v-plan-areas-chips": 0xa947627c28796fe7,
        "c-v-plan-drag": 0x5100dd3cb495cd94,
        "c-v-pv": 0x2aead8f2325c0d37,
        "c-v-pv-full": 0x8c44b33b9992c438,
        "c-v-pv-full-drag": 0x92a172facd263772,
        "k-h-hl1": 0x9612d043883f1153,
        "k-h-hl2": 0xee5a84bb5b23e2cb,
        "k-h-hl3": 0x3104e8d67ac44ea1,
        "k-h-hl4": 0xb354838de8a58b85,
        "k-h-hl5": 0x3104e8d67ac44ea1,
        "k-h-hl6": 0x945743437606a2ec,
        "k-h-hl7": 0x97ecd1d608497509,
        "k-h-plan": 0x3104e8d67ac44ea1,
        "k-h-plan-areas-chips": 0x4e3fa51ec12b086d,
        "k-h-plan-drag": 0xebf3e107bbb33304,
        "k-h-pv": 0xeef9e947a77b689f,
        "k-h-pv-full": 0x95bd1b7702639513,
        "k-h-pv-full-drag": 0xcd9202c1bc225291,
        "k-v-hl1": 0xbbabb31e13ec8426,
        "k-v-hl2": 0x6f910bd83984ee2,
        "k-v-hl3": 0x9d73cf22ef06a2ae,
        "k-v-hl4": 0xe16a488392c25616,
        "k-v-hl5": 0x9d73cf22ef06a2ae,
        "k-v-hl6": 0x328420066015215d,
        "k-v-hl7": 0xaadff1c65753b360,
        "k-v-plan": 0x9d73cf22ef06a2ae,
        "k-v-plan-areas-chips": 0xa193862aef374a12,
        "k-v-plan-drag": 0x9226f7eb52ee97c3,
        "k-v-pv": 0xc3112c87408beebf,
        "k-v-pv-full": 0x92377879877a27ac,
        "k-v-pv-full-drag": 0x8a8d26c7812c6782,
        "n-h-hl1": 0xa9bae10368a4f888,
        "n-h-hl2": 0xb9093ff05ef15b92,
        "n-h-hl3": 0xb9093ff05ef15b92,
        "n-h-hl4": 0xb9093ff05ef15b92,
        "n-h-hl5": 0xb9093ff05ef15b92,
        "n-h-hl6": 0xa1309f658c7467c9,
        "n-h-hl7": 0x118a817c7dd1f40e,
        "n-h-plan": 0x74bc650e28d420ce,
        "n-h-plan-areas-chips": 0x227907e1d6ea8296,
        "n-h-plan-drag": 0x845ce39e06c04587,
        "n-h-pv": 0x9122661771e85409,
        "n-h-pv-full": 0x18112d95adf7b61,
        "n-h-pv-full-drag": 0x8c3e1d80a889801f,
        "n-v-hl1": 0xbf3fd02a88770fcb,
        "n-v-hl2": 0x96fbdae7b55ee59,
        "n-v-hl3": 0x96fbdae7b55ee59,
        "n-v-hl4": 0x96fbdae7b55ee59,
        "n-v-hl5": 0x96fbdae7b55ee59,
        "n-v-hl6": 0x36503bb84893438e,
        "n-v-hl7": 0xaf789bb4eb8b279b,
        "n-v-plan": 0x351fa1819b94f42f,
        "n-v-plan-areas-chips": 0xba483ea392fffe0d,
        "n-v-plan-drag": 0x86b0ae56992c9efa,
        "n-v-pv": 0x66a5c9a4d6763701,
        "n-v-pv-full": 0xf866e4389fb0624a,
        "n-v-pv-full-drag": 0xd6b1b95010cb438,
        "p-h-hl1": 0xa9bae10368a4f888,
        "p-h-hl2": 0xb9093ff05ef15b92,
        "p-h-hl3": 0xb9093ff05ef15b92,
        "p-h-hl4": 0xb9093ff05ef15b92,
        "p-h-hl5": 0xb9093ff05ef15b92,
        "p-h-hl6": 0xa1309f658c7467c9,
        "p-h-hl7": 0x118a817c7dd1f40e,
        "p-h-plan": 0x74bc650e28d420ce,
        "p-h-plan-areas-chips": 0x227907e1d6ea8296,
        "p-h-plan-drag": 0x845ce39e06c04587,
        "p-h-pv": 0x9122661771e85409,
        "p-h-pv-full": 0x18112d95adf7b61,
        "p-h-pv-full-drag": 0x8c3e1d80a889801f,
        "p-v-hl1": 0xbf3fd02a88770fcb,
        "p-v-hl2": 0x96fbdae7b55ee59,
        "p-v-hl3": 0x96fbdae7b55ee59,
        "p-v-hl4": 0x96fbdae7b55ee59,
        "p-v-hl5": 0x96fbdae7b55ee59,
        "p-v-hl6": 0x36503bb84893438e,
        "p-v-hl7": 0xaf789bb4eb8b279b,
        "p-v-plan": 0x351fa1819b94f42f,
        "p-v-plan-areas-chips": 0xba483ea392fffe0d,
        "p-v-plan-drag": 0x86b0ae56992c9efa,
        "p-v-pv": 0x66a5c9a4d6763701,
        "p-v-pv-full": 0xf866e4389fb0624a,
        "p-v-pv-full-drag": 0xd6b1b95010cb438,
        "r-h-hl1": 0xc8129c547677ca9b,
        "r-h-hl2": 0x675437508d41cc87,
        "r-h-hl3": 0x675437508d41cc87,
        "r-h-hl4": 0x675437508d41cc87,
        "r-h-hl5": 0xcefc923affe70c35,
        "r-h-hl6": 0x86f1ea44cf24a124,
        "r-h-hl7": 0xd1a6c4f092b95501,
        "r-h-plan": 0x5d4ae8f077e6b949,
        "r-h-plan-areas-chips": 0xab3601e60e0b97dd,
        "r-h-plan-drag": 0x453bbb99d588d028,
        "r-h-pv": 0xef46cdbcbe2faeed,
        "r-h-pv-full": 0xa05306524d18c77d,
        "r-h-pv-full-drag": 0x2539aa1b18dd12f3,
        "r-v-hl1": 0x7377780f1e0666a0,
        "r-v-hl2": 0xc316ffc525da69bc,
        "r-v-hl3": 0xc316ffc525da69bc,
        "r-v-hl4": 0xc316ffc525da69bc,
        "r-v-hl5": 0xb49ae731e94f1072,
        "r-v-hl6": 0xcc04a2a448200ffb,
        "r-v-hl7": 0xdb424c8276397c64,
        "r-v-plan": 0xb1e0a2f28e77368,
        "r-v-plan-areas-chips": 0x2caef051d137efdc,
        "r-v-plan-drag": 0x745f01669fdc2fed,
        "r-v-pv": 0xe67c96c98e7c071,
        "r-v-pv-full": 0x636f5ef54db90306,
        "r-v-pv-full-drag": 0x7831cfadf86d4dd4,
        "w-h-hl1": 0xa9bae10368a4f888,
        "w-h-hl2": 0xb9093ff05ef15b92,
        "w-h-hl3": 0xb9093ff05ef15b92,
        "w-h-hl4": 0xb9093ff05ef15b92,
        "w-h-hl5": 0xb9093ff05ef15b92,
        "w-h-hl6": 0xa1309f658c7467c9,
        "w-h-hl7": 0x118a817c7dd1f40e,
        "w-h-plan": 0x74bc650e28d420ce,
        "w-h-plan-areas-chips": 0x227907e1d6ea8296,
        "w-h-plan-drag": 0x845ce39e06c04587,
        "w-h-pv": 0x9122661771e85409,
        "w-h-pv-full": 0x18112d95adf7b61,
        "w-h-pv-full-drag": 0x8c3e1d80a889801f,
        "w-v-hl1": 0xbf3fd02a88770fcb,
        "w-v-hl2": 0x96fbdae7b55ee59,
        "w-v-hl3": 0x96fbdae7b55ee59,
        "w-v-hl4": 0x96fbdae7b55ee59,
        "w-v-hl5": 0x96fbdae7b55ee59,
        "w-v-hl6": 0x36503bb84893438e,
        "w-v-hl7": 0xaf789bb4eb8b279b,
        "w-v-plan": 0x351fa1819b94f42f,
        "w-v-plan-areas-chips": 0xba483ea392fffe0d,
        "w-v-plan-drag": 0x86b0ae56992c9efa,
        "w-v-pv": 0x66a5c9a4d6763701,
        "w-v-pv-full": 0xf866e4389fb0624a,
        "w-v-pv-full-drag": 0xd6b1b95010cb438,
    ]
}
