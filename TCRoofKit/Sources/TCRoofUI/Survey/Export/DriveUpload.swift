#if canImport(UIKit)
import Foundation
import DriveSync

/// A file the host app puts in one of its own project folders on Google Drive.
public struct DriveUpload: Sendable {
    public let name: String
    public let data: Data
    public let mimeType: String
    public init(name: String, data: Data, mimeType: String) {
        self.name = name; self.data = data; self.mimeType = mimeType
    }
}

/// Uploads for the host app (TCRoof project documents), using the same Google sign-in as the survey module.
public extension SurveyModel {
    /// Finds or creates `<root>/<name>/` on the signed-in Drive and returns the folder id and its web link.
    func driveFolder(_ name: String, root: String) async throws -> (id: String, url: URL) {
        let client = DriveClient(tokens: google)
        let parent = try await client.ensureFolder(root, parent: "root")
        let folder = try await client.ensureFolder(name, parent: parent.id)
        let link = folder.webViewLink ?? "https://drive.google.com/drive/folders/\(folder.id)"
        return (folder.id, URL(string: link) ?? URL(string: "https://drive.google.com")!)
    }

    /// Finds or creates the folders of `path` under a folder from `driveFolder`, one inside the next, and returns the last id.
    func driveSubfolder(_ path: [String], under parentID: String) async throws -> String {
        let client = DriveClient(tokens: google)
        var id = parentID
        for name in path where !name.isEmpty { id = try await client.ensureFolder(name, parent: id).id }
        return id
    }

    /// Uploads one file into a folder from `driveFolder` and returns the new file's id.
    func driveUpload(_ file: DriveUpload, to folderID: String) async throws -> String {
        try await DriveClient(tokens: google).upload(file.data, name: file.name, mimeType: file.mimeType, parent: folderID).id
    }

    /// Downloads one file by id, such as a photo another device uploaded.
    func driveDownload(_ fileID: String) async throws -> Data {
        try await DriveClient(tokens: google).download(fileID)
    }
}
#endif
