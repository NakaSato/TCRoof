import XCTest
@testable import TCRoofCore

/// `HandoverFolders` is the `folders` tree of the PWA project file, folder for folder and name for name.
final class HandoverFoldersTests: XCTestCase {
    private struct Folder: Decodable {
        struct File: Decodable { var doc: String; var name: String }
        var path: String
        var files: [File]?
        var children: [Folder]?
    }
    private struct Project: Decodable { var folders: [Folder] }

    private func reference() throws -> [(folder: [String], doc: String, name: String)] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../docs/reference/forms/pwa/projects/solar-rooftop-energy-mgmt/project.json")
        let project = try JSONDecoder().decode(Project.self, from: Data(contentsOf: url))
        var out: [([String], String, String)] = []
        func walk(_ folders: [Folder], _ above: [String]) {
            for f in folders {
                let path = above + [f.path]
                for file in f.files ?? [] {
                    for doc in file.doc.split(separator: "|") { out.append((path, String(doc), file.name)) }
                }
                walk(f.children ?? [], path)
            }
        }
        walk(project.folders, [])
        return out
    }

    func testSlotsMatchTheProjectFile() throws {
        let ref = try reference()
        var expected: [String: [HandoverFolders.Slot]] = [:]
        for r in ref { expected[r.doc, default: []].append(.init(folder: r.folder, name: r.name)) }
        XCTAssertEqual(HandoverFolders.slots, expected)
    }

    func testEveryFolderWithFilesIsMade() throws {
        let made = Set(HandoverFolders.folders(over200kVA: true))
        for r in try reference() { XCTAssertTrue(made.contains([HandoverFolders.handover] + r.folder), r.folder.joined(separator: " / ")) }
        XCTAssertTrue(made.contains { $0.last?.contains("พค.2") == true })
        XCTAssertFalse(HandoverFolders.folders(over200kVA: false).contains { $0.last?.contains("พค.2") == true })
    }

    func testPlaceFillsTheName() throws {
        let p = try XCTUnwrap(HandoverFolders.place("asbuilt", station: "สถานีโชคชัย", branch: "สาขาปากช่อง"))
        XCTAssertEqual(p.folder, [HandoverFolders.handover, "3. แบบ As-Built Drawing"])
        XCTAssertEqual(p.name, "AS-Built สถานีโชคชัย สาขาปากช่อง.pdf")
        XCTAssertEqual(HandoverFolders.place("asbuilt", station: "สถานีโชคชัย")?.name, "AS-Built สถานีโชคชัย.pdf")
        XCTAssertEqual(HandoverFolders.place("electric_bill", station: "x", ext: "JPG")?.name, "1. ใบแจ้งค่าไฟฟ้า.jpg")
        XCTAssertEqual(HandoverFolders.place("install_photo_report", station: "x")?.folder.count, 3, "the first of its two folders")
        XCTAssertNil(HandoverFolders.place("not_a_paper", station: "x"))
    }
}
