import XCTest
@testable import TCRoofCore

/// The drawing NO.224's roof and tank sheets take in their one picture box (docs/specs/auto-drawing.md, open question
/// 3): the plan with section A-A under it, or the tank plan with sections 1–1 and 2–2.
final class PlanWithSectionsTests: XCTestCase {
    func texts(_ s: Sketch) -> [String] {
        s.ops.compactMap { if case let .text(t, _, _, _, _, _, _) = $0 { t } else { nil } }
    }

    /// The plan's size once the picture is fitted into the sheets' box (792 × 614 px).
    func fitted(_ s: Sketch, planWidth: Double) -> Double { min(792 / s.width, 614 / s.height) * planWidth }

    func testARoofWithAFrameAddsSectionAA() throws {
        // a long building: its plan is wide and leaves the box's lower half empty
        var v = Values()
        v["spansX"] = .text("1.5,4,4,4,4,4,4,4,4,1.5"); v["spansY"] = .text("1.5,4.5,4.5,1.5")
        Roof.setRidge(&v, .h); Roof.setFrame(&v, .pratt)
        let plan = try XCTUnwrap(Drawings.plan(v, tank: false, width: 1100))
        let both = try XCTUnwrap(Drawings.planWithSections(v, tank: false, width: 1100))
        XCTAssertTrue(texts(both).contains { $0.hasPrefix("รูปตัด A-A | ") })
        XCTAssertGreaterThanOrEqual(fitted(both, planWidth: 1100), 0.75 * fitted(plan, planWidth: 1100), "the plan keeps most of its size")
    }

    func testThePlanNeverShrinksMuch() throws {
        var v = Values()
        v["spansX"] = .text("1.5,4,4,4,4,1.5"); v["spansY"] = .text("1.5,4.5,4,4.5,1.5")
        Roof.setRidge(&v, .h); Roof.setFrame(&v, .pratt)
        let plan = try XCTUnwrap(Drawings.plan(v, tank: false, width: 1100))
        let picked = try XCTUnwrap(Drawings.planWithSections(v, tank: false, width: 1100))
        // whichever layout it picks, the plan is drawn at three quarters of its size alone or more
        XCTAssertGreaterThanOrEqual(fitted(picked, planWidth: 1100), 0.75 * fitted(plan, planWidth: 1100) - 1e-9)
        // with no shrink allowed, it is the plan alone
        XCTAssertEqual(Drawings.planWithSections(v, tank: false, width: 1100, keep: 1.01)?.height, plan.height)
    }

    func testARoofWithoutAFrameIsThePlanAlone() throws {
        var v = Values()
        v["spansX"] = .text("4,4"); v["spansY"] = .text("5,5")
        let plan = try XCTUnwrap(Drawings.plan(v, tank: false, width: 1100))
        XCTAssertEqual(Drawings.planWithSections(v, tank: false, width: 1100)?.height, plan.height)
        XCTAssertNil(Drawings.planWithSections(Values(), tank: false), "no spans, no drawing")
    }

    func testATankAddsBothSectionsOnceItHasAHeight() throws {
        var v = TankDXFTests.sample()
        let plan = try XCTUnwrap(Drawings.plan(v, tank: true, width: 1100))
        XCTAssertEqual(Drawings.planWithSections(v, tank: true, width: 1100)?.height, plan.height,
                       "no height: the sections would only say to enter one")
        v["tankHeight"] = .text("4.5")
        let both = try XCTUnwrap(Drawings.planWithSections(v, tank: true, width: 1100))
        let t = texts(both)
        XCTAssertTrue(t.contains { $0.hasPrefix("รูปตัด 1–1") || $0.contains("1–1") })
        XCTAssertTrue(t.contains { $0.contains("2–2") })
        XCTAssertGreaterThanOrEqual(fitted(both, planWidth: 1100), 0.75 * fitted(plan, planWidth: 1100) - 1e-9)
    }
}
