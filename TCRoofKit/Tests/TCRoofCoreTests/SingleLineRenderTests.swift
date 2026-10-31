import XCTest
@testable import TCRoofCore

private actor DiagramBuildGate {
    private var blockFirst = true
    private var release: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var jobs: [UUID] = []
    private var active = 0
    private(set) var maximumActive = 0

    func make(_ job: Job, hv: Bool?) async -> SingleLineRender.Result {
        active += 1
        maximumActive = max(maximumActive, active)
        jobs.append(job.id)
        defer { active -= 1 }
        if blockFirst {
            blockFirst = false
            await withCheckedContinuation { continuation in
                release = continuation
                started?.resume(); started = nil
            }
        }
        let line = SingleLine.build(job, hvOverride: hv)
        return SingleLineRender.Result(line: line, drawing: SingleLineLayout.draw(line))
    }

    func waitForStart() async {
        if jobs.isEmpty { await withCheckedContinuation { started = $0 } }
    }

    func finishFirst() { release?.resume(); release = nil }
}

@MainActor
final class SingleLineRenderTests: XCTestCase {
    func testInitialReadsDoNotBuildAndFirstResultIsAsynchronous() async throws {
        let gate = DiagramBuildGate()
        let render = SingleLineRender { await gate.make($0, hv: $1) }
        for _ in 0..<5 { XCTAssertNil(render.result) }
        let before = await gate.jobs
        XCTAssertTrue(before.isEmpty)
        render.update(Job(), now: true)
        XCTAssertNil(render.result)
        await gate.waitForStart()
        XCTAssertNil(render.result)
        await gate.finishFirst()
        await render.waitForUpdate()
        let result = try XCTUnwrap(render.result)
        XCTAssertFalse(result.drawing.sketch.ops.isEmpty)
    }

    func testRapidUpdatesBuildOnlyFirstAndLatestWithoutOverlap() async throws {
        let gate = DiagramBuildGate()
        let render = SingleLineRender { await gate.make($0, hv: $1) }
        let first = Job()
        render.update(first, now: true)
        await gate.waitForStart()
        var latest = first
        for i in 1...20 {
            latest.id = UUID()
            latest.values["projectName"] = .text("edit-\(i)")
            render.update(latest, now: true)
        }
        await gate.finishFirst()
        await render.waitForUpdate()
        let jobs = await gate.jobs
        let maximum = await gate.maximumActive
        XCTAssertEqual(jobs, [first.id, latest.id])
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(render.result?.line.projectLine, "edit-20")
    }

    func testSameInputDoesNotQueueDuplicateInitialOrCompletedBuild() async {
        let gate = DiagramBuildGate()
        let render = SingleLineRender { await gate.make($0, hv: $1) }
        let job = Job()
        render.update(job, now: true)
        render.update(job, now: true)
        await gate.waitForStart()
        await gate.finishFirst()
        await render.waitForUpdate()
        render.update(job, now: true)
        await render.waitForUpdate()
        let jobs = await gate.jobs
        XCTAssertEqual(jobs, [job.id])
    }

    func testCancellationPreventsPublicationAndAllowsSameInputToRestart() async {
        let gate = DiagramBuildGate()
        let render = SingleLineRender { await gate.make($0, hv: $1) }
        let job = Job()
        render.update(job, now: true)
        await gate.waitForStart()
        render.cancel()
        await gate.finishFirst()
        await render.waitForUpdate()
        XCTAssertNil(render.result)
        render.update(job, now: true)
        await render.waitForUpdate()
        XCTAssertNotNil(render.result)
        let jobs = await gate.jobs
        XCTAssertEqual(jobs, [job.id, job.id])
    }

    func testDefaultBuilderKeepsLastResultWhileUpdatingPreview() async throws {
        let render = SingleLineRender()
        let job = Job()
        render.update(job, hv: false, now: true)
        await render.waitForUpdate()
        XCTAssertFalse(try XCTUnwrap(render.result).line.zeroExportHV)
        render.update(job, hv: true, now: true)
        XCTAssertFalse(try XCTUnwrap(render.result).line.zeroExportHV)
        await render.waitForUpdate()
        let result = try XCTUnwrap(render.result)
        XCTAssertTrue(result.line.zeroExportHV)
        XCTAssertEqual(result.drawing.width, SingleLineLayout.width)
    }

    func testInFlightBuildDoesNotRetainRenderer() async {
        let gate = DiagramBuildGate()
        var render: SingleLineRender? = SingleLineRender { await gate.make($0, hv: $1) }
        render?.update(Job(), now: true)
        await gate.waitForStart()
        weak let released = render
        render = nil
        XCTAssertNil(released)
        await gate.finishFirst()
    }
}
