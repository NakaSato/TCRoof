import XCTest

/// What each role sees, by opening a screen with `-role` (which `-screen`, skipping sign-in, applies at launch:
/// `MemberRole.init`). Any simulator:
/// `xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<udid>' -only-testing:TCRoofUITests/RoleUITests -derivedDataPath <scratch>`.
/// The cells checked are those of docs/reference/roles/user-roles.json; the rules side is tools/firestore-rules-tests.
final class RoleUITests: XCTestCase {
    let slow: TimeInterval = 90

    override func setUp() { continueAfterFailure = false }

    private func launch(_ screen: String, role: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", screen, "-role", role, "-noNotificationPrompt", "YES"] + extra
        app.launch()
        return app
    }

    private func text(_ app: XCUIApplication, _ s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    /// `icl.checklist` is view only for an external member: no form, no `แก้ไขใบตรวจรับ`; the team fills it.
    func testICLIsViewOnlyForAContractor() {
        let app = launch("icl", role: "external")
        // either the submitted report (its PDF button) or the line that there is none, whichever the demo job has
        let empty = text(app, "ยังไม่มีใบตรวจรับที่ส่งแล้ว"), report = app.buttons["ส่งออก PDF"]
        let deadline = Date().addingTimeInterval(slow)
        while !empty.exists && !report.exists && Date() < deadline { usleep(500_000) }
        XCTAssertTrue(empty.exists || report.exists, "a contractor sees the submitted report or that there is none")
        XCTAssertFalse(app.buttons["แก้ไขใบตรวจรับ"].exists, "a contractor never reopens the ICL")
        app.terminate()

        let team = launch("icl", role: "internal")
        XCTAssertFalse(text(team, "ยังไม่มีใบตรวจรับที่ส่งแล้ว").waitForExistence(timeout: 15), "the team gets the form")
    }

    /// `job.edit`: a contractor can't create jobs, so the survey home has no `เพิ่มลูกค้าใหม่` (iPhone dock, iPad button);
    /// the team has it.
    func testOnlyTheTeamAddsJobs() {
        let team = launch("survey", role: "internal")
        XCTAssertTrue(team.buttons["เพิ่มลูกค้าใหม่"].firstMatch.waitForExistence(timeout: slow), "the team adds customers")
        team.terminate()

        let contractor = launch("survey", role: "external")
        XCTAssertTrue(contractor.staticTexts.firstMatch.waitForExistence(timeout: slow))
        sleep(3)
        XCTAssertFalse(contractor.buttons["เพิ่มลูกค้าใหม่"].exists, "a contractor never creates a job")
    }

    /// `job.assign_team` and `job.assign_external`: the job's access card is the team's, never a contractor's.
    func testAccessCardIsTheTeams() {
        let team = launch("job", role: "internal")
        XCTAssertTrue(text(team, "ทีมงานของเรา").waitForExistence(timeout: slow), "the team assigns people on the job")
        XCTAssertTrue(text(team, "ผู้รับเหมา / วิศวกรภายนอก").exists)
        team.terminate()

        let contractor = launch("job", role: "external")
        // the screen is up once the job's title is; wait on any static text before checking what's absent
        XCTAssertTrue(contractor.staticTexts.firstMatch.waitForExistence(timeout: slow))
        XCTAssertFalse(text(contractor, "ทีมงานของเรา").waitForExistence(timeout: 5), "a contractor assigns no one")
        XCTAssertFalse(text(contractor, "ผู้รับเหมา / วิศวกรภายนอก").exists)
    }

    /// `mp.setup`: importing a plan file and ตั้งค่าแผน are the team's.
    func testPlanSetupIsTheTeams() {
        let team = launch("mp", role: "internal", ["-mpClear", "YES"])
        XCTAssertTrue(team.buttons["นำเข้าไฟล์แผน (Excel)"].firstMatch.waitForExistence(timeout: slow), "the team imports a plan file")
        team.terminate()

        let contractor = launch("mp", role: "external", ["-mpClear", "YES"])
        XCTAssertTrue(contractor.staticTexts.firstMatch.waitForExistence(timeout: slow))
        XCTAssertFalse(contractor.buttons["นำเข้าไฟล์แผน (Excel)"].firstMatch.waitForExistence(timeout: 5), "a contractor imports no plan")
        XCTAssertFalse(contractor.buttons["ตั้งค่าแผน"].firstMatch.exists, "nor sets one up")
    }

    /// `daily.sign` is per job: on a job that names its team, a team member not on it can't open the sign sheet (the
    /// line says who signs); one on it can, and so can anyone when the job names no one. `-jobTeam` writes the first
    /// installing job's team for good, so the last run leaves it empty.
    func testDailyReportsAreSignedByTheJobsPeople() {
        let sheet = "ลงนามแล้วระบบจะสร้าง PDF"

        let other = launch("daily", role: "internal", ["-jobTeam", "someone@tcroof.test"])
        let sign = other.buttons["dailySign"].firstMatch
        XCTAssertTrue(sign.waitForExistence(timeout: slow))
        sign.tap()
        XCTAssertTrue(text(other, "ทีมงานของงานนี้ ผู้ควบคุมงาน หรือผู้จัดการเป็นผู้ลงนามรายงาน").waitForExistence(timeout: 5),
                      "a team member not on the job is told who signs")
        XCTAssertFalse(text(other, sheet).exists, "and gets no sign sheet")
        other.terminate()

        for team in ["uitest@tcroof.test", "none"] {
            let app = launch("daily", role: "internal", ["-jobTeam", team])
            let button = app.buttons["dailySign"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: slow))
            button.tap()
            XCTAssertTrue(text(app, sheet).waitForExistence(timeout: 10), "the sign sheet opens (-jobTeam \(team))")
            app.terminate()
        }
    }
}
