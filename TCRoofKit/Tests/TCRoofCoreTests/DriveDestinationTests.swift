import XCTest
@testable import TCRoofCore

final class DriveDestinationTests: XCTestCase {
    func testTCEngineersWithFullDriveWriteIntoTheCenterFolder() {
        for role in [UserRole.manager, .internalTeam, .maintainer] {
            XCTAssertEqual(DriveDestination.center(role: role, hasFullDrive: true, centerFolder: "1AbC"), "1AbC", "\(role)")
        }
    }

    func testAContractorWritesIntoTheirOwnDrive() {
        XCTAssertNil(DriveDestination.center(role: .external, hasFullDrive: true, centerFolder: "1AbC"))
    }

    func testAnEngineerWithoutFullDriveOrACenterFolderWritesIntoTheirOwn() {
        XCTAssertNil(DriveDestination.center(role: .internalTeam, hasFullDrive: false, centerFolder: "1AbC"))
        XCTAssertNil(DriveDestination.center(role: .manager, hasFullDrive: true, centerFolder: nil))
        XCTAssertNil(DriveDestination.center(role: .manager, hasFullDrive: true, centerFolder: ""))
    }

    func testConstructionRecordsGoUnderTheirFolderOnTheCenterDrive() {
        XCTAssertEqual(DriveDestination.construction(["รายงานประจำวัน"], onCenter: true),
                       [HandoverFolders.construction, "รายงานประจำวัน"])
        XCTAssertEqual(DriveDestination.construction(["รายงานประจำวัน"], onCenter: false), ["รายงานประจำวัน"])
        XCTAssertEqual(DriveDestination.construction([], onCenter: true), [HandoverFolders.construction])
    }

    func testAFolderIDIsReadFromALinkOrTakenAsIs() {
        XCTAssertEqual(DriveDestination.folderID(from: "https://drive.google.com/drive/folders/1A-b_C9?usp=sharing"), "1A-b_C9")
        XCTAssertEqual(DriveDestination.folderID(from: "https://drive.google.com/drive/u/0/folders/1XyZ"), "1XyZ")
        XCTAssertEqual(DriveDestination.folderID(from: "  1XyZ \n"), "1XyZ")
        XCTAssertNil(DriveDestination.folderID(from: ""))
        XCTAssertNil(DriveDestination.folderID(from: "https://drive.google.com/file/d/1XyZ/view"))
        XCTAssertNil(DriveDestination.folderID(from: "https://drive.google.com/drive/folders/"))
    }
}
