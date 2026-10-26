import XCTest
@testable import TCRoofCore

/// Every size C1's member pickers offer (each frame type's list and `ขนาดอื่น ›`), on every row of every frame type,
/// goes through what the page works out after a pick: the member schedule and its texts, the details, the DXF.
final class RoofMemberSizesTests: XCTestCase {
    func roof(_ f: RoofFrame, xs: [Double], ys: [Double]) -> Values {
        var v = Values()
        Roof.setSpans(&v, .x, xs); Roof.setSpans(&v, .y, ys)
        Roof.setRidge(&v, .v); Roof.setFrame(&v, f)
        return v
    }

    func testEverySizeOnEveryRow() {
        let all = StructureSizes.sections.flatMap(\.items)
        for f in RoofFrame.allCases {
            for (xs, ys) in [([4.0, 4, 4, 4], [6.0, 6, 6, 6]), ([3.0], [2.0]), ([1.5, 4, 4, 1.5], [1, 9, 9, 1])] {
                for n in 1...7 {
                    for size in f.members[n - 1].sizes + all {
                        var v = roof(f, xs: xs, ys: ys)
                        for k in 1...7 { Roof.setMember(&v, k, size: f.members[k - 1].defaultSize) }
                        Roof.setMember(&v, n, size: size)
                        _ = Roof.memberOffList(v, n); _ = Roof.profile(size); _ = Roof.memberNote(v)
                        _ = SteelSection.parse(size)?.kgPerMetre
                        if let s = RoofTruss.schedule(v) {
                            for r in s.rows {
                                _ = RoofTruss.perFrameText(r); _ = RoofTruss.kgPerMetreText(r); _ = RoofTruss.perFrameKgText(r)
                                _ = RoofTruss.kgText(r); _ = RoofTruss.totalText(r)
                            }
                            _ = RoofTruss.steelKgText(s); _ = RoofTruss.steelPerFrameKgText(s); _ = RoofTruss.steelNote(s)
                        }
                        _ = RoofTruss.details(v)
                    }
                }
            }
        }
    }
}
