import XCTest
@testable import TCRoof
import TCRoofCore

/// A job edited here and not pushed yet, meeting another device's change (`CloudSync.mergeUnpushed`).
final class CloudMergeTests: XCTestCase {
    private func makeJob() -> Job {
        Job(code: "MP-189", projectName: "สถานีผลิตน้ำบางไทร", customerName: "กปภ. สาขาบางไทร", province: "พระนครศรีอยุธยา",
            capacityKW: 100, team: .t1, status: .installing, surveyDate: Date(millis: 1_730_000_000_000),
            installStart: Date(millis: 1_730_100_000_000), installDays: 30)
    }

    func testAJobRecordComesBackWholeFromAMerge() throws {
        let base = makeJob().record
        var local = base
        local.projectName = "สถานีผลิตน้ำบางไทร (แก้ในเครื่องนี้)"
        var remote = base
        remote.capacityKW = 163.02
        remote.teamMembers = ["eng@tcroof.test"]
        let result = try XCTUnwrap(RecordMerge.merge(base: base, local: local, remote: remote))
        var expected = local
        expected.capacityKW = 163.02
        expected.teamMembers = ["eng@tcroof.test"]
        XCTAssertEqual(result.merged, expected)
        XCTAssertEqual(result.conflicts, [])
    }

    func testApplyingAMergeKeepsAContractorsChangesUnsent() {
        let job = makeJob()
        job.weeklyRequestsJSON = "[]"
        job.weeklyRequestsUnsent = true
        job.wbsTicksUnsent = true
        var merged = job.record
        merged.projectName = "ชื่อจากอีกเครื่อง"
        XCTAssertTrue(job.applyMerged(merged, jobs: [:]))
        XCTAssertEqual(job.projectName, "ชื่อจากอีกเครื่อง")
        XCTAssertTrue(job.weeklyRequestsUnsent)
        XCTAssertTrue(job.wbsTicksUnsent)
        // the same record through `apply` is Firestore's echo of them: sent
        XCTAssertTrue(job.apply(merged, jobs: [:]))
        XCTAssertFalse(job.weeklyRequestsUnsent)
        XCTAssertFalse(job.wbsTicksUnsent)
    }
}
