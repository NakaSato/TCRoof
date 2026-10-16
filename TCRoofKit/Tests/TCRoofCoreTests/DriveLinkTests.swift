import XCTest
@testable import TCRoofCore

/// Two devices saving one survey: the Drive files either side sent count as sent, so none goes up twice.
final class DriveLinkTests: XCTestCase {
    func link(photos: String?, files: [String: String]?, revisions: [String: String]? = nil) -> DriveLink {
        var l = DriveLink()
        l.rootID = "root"; l.folderID = "job"; l.photosFolderID = photos; l.photoFiles = files
        l.revisionsFolderID = revisions == nil ? nil : "rev"; l.revisionFiles = revisions
        return l
    }

    func testMergeKeepsEverySentPhoto() {
        let remote = link(photos: "p", files: ["a": "1"])
        let local = link(photos: "p", files: ["a": "1", "b": "2"], revisions: ["REV00.pdf": "9"])
        let m = remote.merged(with: local)
        XCTAssertEqual(m.photoFiles, ["a": "1", "b": "2"])
        XCTAssertEqual(m.revisionsFolderID, "rev")
        XCTAssertEqual(m.revisionFiles, ["REV00.pdf": "9"])
    }

    func testMergeTakesTheOtherFolderWhenThisHasNone() {
        let m = DriveLink().merged(with: link(photos: "p", files: ["a": "1"]))
        XCTAssertEqual(m.folderID, "job")
        XCTAssertEqual(m.photosFolderID, "p")
        XCTAssertEqual(m.photoFiles, ["a": "1"])
    }

    /// A photo folder made again elsewhere (the old one deleted): the old folder's files don't count.
    func testMergeDropsFilesOfAReplacedFolder() {
        let m = link(photos: "new", files: ["a": "5"]).merged(with: link(photos: "old", files: ["a": "1", "b": "2"]))
        XCTAssertEqual(m.photosFolderID, "new")
        XCTAssertEqual(m.photoFiles, ["a": "5"])
    }

    func testMergeOfNothingStaysNil() {
        XCTAssertNil(DriveLink().merged(with: DriveLink()).photoFiles)
    }
}
