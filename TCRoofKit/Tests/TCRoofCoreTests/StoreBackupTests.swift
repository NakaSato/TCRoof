import XCTest
@testable import TCRoofCore

final class StoreBackupTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("store-backup-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testTheStoreAndItsLogMoveTogether() throws {
        let root = try folder()
        let store = root.appendingPathComponent("default.store")
        for file in StoreBackup.files(of: store) { try Data(file.lastPathComponent.utf8).write(to: file) }
        let date = Date(timeIntervalSince1970: 1_762_600_000)
        let backup = try StoreBackup.moveAside(store, into: root.appendingPathComponent("StoreBackups"), at: date)
        XCTAssertEqual(backup.lastPathComponent, "store-20251108-110640")
        for file in StoreBackup.files(of: store) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            let moved = backup.appendingPathComponent(file.lastPathComponent)
            XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), file.lastPathComponent)
        }
    }

    func testMissingLogFilesAreSkipped() throws {
        let root = try folder()
        let store = root.appendingPathComponent("default.store")
        try Data("s".utf8).write(to: store)
        let backup = try StoreBackup.moveAside(store, into: root)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backup.path), ["default.store"])
    }

    func testASecondBackupAtTheSameSecondGetsItsOwnFolder() throws {
        let root = try folder()
        let store = root.appendingPathComponent("default.store")
        let date = Date(timeIntervalSince1970: 1_762_600_000)
        try Data("1".utf8).write(to: store)
        let first = try StoreBackup.moveAside(store, into: root, at: date)
        try Data("2".utf8).write(to: store)
        let second = try StoreBackup.moveAside(store, into: root, at: date)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "store-20251108-110640-2")
    }
}
