import XCTest
@testable import TCRoofCore

/// Pins `RoofPlan`'s whole output (every op, tag, layout point and PV figure) over a matrix of roofs, so restructuring
/// the drawing code can't change what it draws. Run with `ROOF_GOLDEN_RECORD=1` to print new fingerprints after an
/// intended change to the drawing.
final class RoofPlanGoldenTests: XCTestCase {
    struct Case { let name: String; let values: Values; let mode: RoofPlan.Mode; var portrait: Bool? = nil
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
        if tables { Roof.setPV(&v, rows: 2, perTable: 3, gap: 0.8) }
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
                var land = plain; Roof.setPV(&land, perTable: 0)
                out.append(Case(name: "\(tag)-pv-land", values: land, mode: .pv, portrait: false))
            }
        }
        return out
    }

    static func dump(_ c: Case) -> String {
        let p = RoofPlan(c.values, mode: c.mode, portrait: c.portrait, module: RoofPlan.Module(length: 2.278, width: 1.134, kW: 0.57),
                         chips: c.chips, dragging: c.dragging, highlight: c.highlight)
        var s = "\(p.sketch.width)x\(p.sketch.height)\n"
        for (op, t) in zip(p.sketch.ops, p.tags) { s += "\(t ?? "-") \(op)\n" }
        let l = p.layout
        s += "chips \(l.chips.map { "\($0.axis)\($0.index) \($0.value) \($0.at)" })\n"
        s += "nodes \(l.nodes.map { "\($0.i),\($0.j) \($0.at) \($0.post)" })\n"
        s += "areas \(l.areas.map { "\($0.area) \($0.box)" })\n"
        s += "add \(l.addX) \(l.addY) origin \(l.origin) k \(l.k) \(l.lx) \(l.ly)\n"
        s += "pv \(p.pv.count) \(p.pv.kWp) \(p.pv.tables) \(p.pv.placed) \(p.pv.blocked)\n"
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

    /// Recorded from the drawing before RoofPlan.init was split (4/10/2569).
    static let expected: [String: UInt64] = [
        "c-h-hl1": 0x8fdab8eee450deab,
        "c-h-hl2": 0x12622933c3ec6131,
        "c-h-hl3": 0xe297348bcc1cf2ef,
        "c-h-hl4": 0xb67d1cfce9b25db3,
        "c-h-hl5": 0xe297348bcc1cf2ef,
        "c-h-hl6": 0x6e26c5868a1d74d2,
        "c-h-hl7": 0x5da85243d10956b7,
        "c-h-plan": 0xe297348bcc1cf2ef,
        "c-h-plan-areas-chips": 0x16bbadb58114d873,
        "c-h-plan-drag": 0xc33e05d3681b1f76,
        "c-h-pv": 0x3ac521a2d174d9ac,
        "c-h-pv-full": 0xd1990af4d014022b,
        "c-h-pv-full-drag": 0x47eedd3635a98d,
        "c-h-pv-land": 0xd23ca3b66e50a0be,
        "c-v-hl1": 0x98775f22b77115d7,
        "c-v-hl2": 0xc57af26c8ac43e05,
        "c-v-hl3": 0x49672cbd449528b1,
        "c-v-hl4": 0x8bd1e3ab8a1a1dd1,
        "c-v-hl5": 0x49672cbd449528b1,
        "c-v-hl6": 0xf610f161c24ea510,
        "c-v-hl7": 0x5b1b1c1f6c940fb3,
        "c-v-plan": 0x49672cbd449528b1,
        "c-v-plan-areas-chips": 0x54616a2170e763c7,
        "c-v-plan-drag": 0x5100dd3cb495cd94,
        "c-v-pv": 0xe74085c91cf964f2,
        "c-v-pv-full": 0x4720d414b87310e6,
        "c-v-pv-full-drag": 0xfb30a9809b217ad4,
        "c-v-pv-land": 0xeb6f9385dec9ab7e,
        "k-h-hl1": 0x9612d043883f1153,
        "k-h-hl2": 0xee5a84bb5b23e2cb,
        "k-h-hl3": 0x3104e8d67ac44ea1,
        "k-h-hl4": 0xb354838de8a58b85,
        "k-h-hl5": 0x3104e8d67ac44ea1,
        "k-h-hl6": 0x945743437606a2ec,
        "k-h-hl7": 0x97ecd1d608497509,
        "k-h-plan": 0x3104e8d67ac44ea1,
        "k-h-plan-areas-chips": 0x9c3ae087a04b5f5d,
        "k-h-plan-drag": 0xebf3e107bbb33304,
        "k-h-pv": 0x737f5d20f5963d7b,
        "k-h-pv-full": 0xf67f2b0feebf7f94,
        "k-h-pv-full-drag": 0xd4da10189594fe16,
        "k-h-pv-land": 0xa265245dfe082541,
        "k-v-hl1": 0xbbabb31e13ec8426,
        "k-v-hl2": 0x6f910bd83984ee2,
        "k-v-hl3": 0x9d73cf22ef06a2ae,
        "k-v-hl4": 0xe16a488392c25616,
        "k-v-hl5": 0x9d73cf22ef06a2ae,
        "k-v-hl6": 0x328420066015215d,
        "k-v-hl7": 0xaadff1c65753b360,
        "k-v-plan": 0x9d73cf22ef06a2ae,
        "k-v-plan-areas-chips": 0x3922e36a53c10f20,
        "k-v-plan-drag": 0x9226f7eb52ee97c3,
        "k-v-pv": 0x5b0679d68dd90a9e,
        "k-v-pv-full": 0xcd72dd87e967125e,
        "k-v-pv-full-drag": 0xf10f00e92414fd50,
        "k-v-pv-land": 0x820a77ea868f162a,
        "n-h-hl1": 0xa9bae10368a4f888,
        "n-h-hl2": 0xb9093ff05ef15b92,
        "n-h-hl3": 0xb9093ff05ef15b92,
        "n-h-hl4": 0xb9093ff05ef15b92,
        "n-h-hl5": 0xb9093ff05ef15b92,
        "n-h-hl6": 0xa1309f658c7467c9,
        "n-h-hl7": 0x118a817c7dd1f40e,
        "n-h-plan": 0x74bc650e28d420ce,
        "n-h-plan-areas-chips": 0x189b54a9f473c52c,
        "n-h-plan-drag": 0x845ce39e06c04587,
        "n-h-pv": 0x4761fe58cd7741c9,
        "n-h-pv-full": 0x138062221f74f1be,
        "n-h-pv-full-drag": 0xe996ff8788e01c90,
        "n-h-pv-land": 0xb903bf6f907d22eb,
        "n-v-hl1": 0xbf3fd02a88770fcb,
        "n-v-hl2": 0x96fbdae7b55ee59,
        "n-v-hl3": 0x96fbdae7b55ee59,
        "n-v-hl4": 0x96fbdae7b55ee59,
        "n-v-hl5": 0x96fbdae7b55ee59,
        "n-v-hl6": 0x36503bb84893438e,
        "n-v-hl7": 0xaf789bb4eb8b279b,
        "n-v-plan": 0x351fa1819b94f42f,
        "n-v-plan-areas-chips": 0x9ec6f71cbf72cfd,
        "n-v-plan-drag": 0x86b0ae56992c9efa,
        "n-v-pv": 0x6bf76ae95b02fdb0,
        "n-v-pv-full": 0xb06be413b5f34990,
        "n-v-pv-full-drag": 0xe6b048bcc34076e2,
        "n-v-pv-land": 0x84109d01bde75d10,
        "p-h-hl1": 0xa9bae10368a4f888,
        "p-h-hl2": 0xb9093ff05ef15b92,
        "p-h-hl3": 0xb9093ff05ef15b92,
        "p-h-hl4": 0xb9093ff05ef15b92,
        "p-h-hl5": 0xb9093ff05ef15b92,
        "p-h-hl6": 0xa1309f658c7467c9,
        "p-h-hl7": 0x118a817c7dd1f40e,
        "p-h-plan": 0x74bc650e28d420ce,
        "p-h-plan-areas-chips": 0x189b54a9f473c52c,
        "p-h-plan-drag": 0x845ce39e06c04587,
        "p-h-pv": 0x4761fe58cd7741c9,
        "p-h-pv-full": 0x138062221f74f1be,
        "p-h-pv-full-drag": 0xe996ff8788e01c90,
        "p-h-pv-land": 0xb903bf6f907d22eb,
        "p-v-hl1": 0xbf3fd02a88770fcb,
        "p-v-hl2": 0x96fbdae7b55ee59,
        "p-v-hl3": 0x96fbdae7b55ee59,
        "p-v-hl4": 0x96fbdae7b55ee59,
        "p-v-hl5": 0x96fbdae7b55ee59,
        "p-v-hl6": 0x36503bb84893438e,
        "p-v-hl7": 0xaf789bb4eb8b279b,
        "p-v-plan": 0x351fa1819b94f42f,
        "p-v-plan-areas-chips": 0x9ec6f71cbf72cfd,
        "p-v-plan-drag": 0x86b0ae56992c9efa,
        "p-v-pv": 0x6bf76ae95b02fdb0,
        "p-v-pv-full": 0xb06be413b5f34990,
        "p-v-pv-full-drag": 0xe6b048bcc34076e2,
        "p-v-pv-land": 0x84109d01bde75d10,
        "r-h-hl1": 0xc8129c547677ca9b,
        "r-h-hl2": 0x675437508d41cc87,
        "r-h-hl3": 0x675437508d41cc87,
        "r-h-hl4": 0x675437508d41cc87,
        "r-h-hl5": 0xcefc923affe70c35,
        "r-h-hl6": 0x86f1ea44cf24a124,
        "r-h-hl7": 0xd1a6c4f092b95501,
        "r-h-plan": 0x5d4ae8f077e6b949,
        "r-h-plan-areas-chips": 0x67ad2a3d7baec82d,
        "r-h-plan-drag": 0x453bbb99d588d028,
        "r-h-pv": 0x7c8b078516c9cd75,
        "r-h-pv-full": 0x146173f873ae2172,
        "r-h-pv-full-drag": 0xf38f464103d729ec,
        "r-h-pv-land": 0xf4a420ae3ff5ee5f,
        "r-v-hl1": 0x7377780f1e0666a0,
        "r-v-hl2": 0xc316ffc525da69bc,
        "r-v-hl3": 0xc316ffc525da69bc,
        "r-v-hl4": 0xc316ffc525da69bc,
        "r-v-hl5": 0xb49ae731e94f1072,
        "r-v-hl6": 0xcc04a2a448200ffb,
        "r-v-hl7": 0xdb424c8276397c64,
        "r-v-plan": 0xb1e0a2f28e77368,
        "r-v-plan-areas-chips": 0xed00293f8c9dd7da,
        "r-v-plan-drag": 0x745f01669fdc2fed,
        "r-v-pv": 0x56f898ad5606b280,
        "r-v-pv-full": 0x89cd39433ecd60ac,
        "r-v-pv-full-drag": 0x12f314c8cad6b5de,
        "r-v-pv-land": 0x66b59e6f405018c4,
        "w-h-hl1": 0xa9bae10368a4f888,
        "w-h-hl2": 0xb9093ff05ef15b92,
        "w-h-hl3": 0xb9093ff05ef15b92,
        "w-h-hl4": 0xb9093ff05ef15b92,
        "w-h-hl5": 0xb9093ff05ef15b92,
        "w-h-hl6": 0xa1309f658c7467c9,
        "w-h-hl7": 0x118a817c7dd1f40e,
        "w-h-plan": 0x74bc650e28d420ce,
        "w-h-plan-areas-chips": 0x189b54a9f473c52c,
        "w-h-plan-drag": 0x845ce39e06c04587,
        "w-h-pv": 0x4761fe58cd7741c9,
        "w-h-pv-full": 0x138062221f74f1be,
        "w-h-pv-full-drag": 0xe996ff8788e01c90,
        "w-h-pv-land": 0xb903bf6f907d22eb,
        "w-v-hl1": 0xbf3fd02a88770fcb,
        "w-v-hl2": 0x96fbdae7b55ee59,
        "w-v-hl3": 0x96fbdae7b55ee59,
        "w-v-hl4": 0x96fbdae7b55ee59,
        "w-v-hl5": 0x96fbdae7b55ee59,
        "w-v-hl6": 0x36503bb84893438e,
        "w-v-hl7": 0xaf789bb4eb8b279b,
        "w-v-plan": 0x351fa1819b94f42f,
        "w-v-plan-areas-chips": 0x9ec6f71cbf72cfd,
        "w-v-plan-drag": 0x86b0ae56992c9efa,
        "w-v-pv": 0x6bf76ae95b02fdb0,
        "w-v-pv-full": 0xb06be413b5f34990,
        "w-v-pv-full-drag": 0xe6b048bcc34076e2,
        "w-v-pv-land": 0x84109d01bde75d10,
    ]
}
