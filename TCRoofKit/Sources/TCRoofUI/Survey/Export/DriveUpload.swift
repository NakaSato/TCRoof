#if canImport(UIKit)
import Foundation
import DriveSync
import TCRoofCore

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

    /// Finds or creates `<name>/` in a folder another account shares with this one (the company's center folder).
    func driveFolder(_ name: String, in parentID: String) async throws -> (id: String, url: URL) {
        let folder = try await DriveClient(tokens: google).ensureFolder(name, parent: parentID)
        let link = folder.webViewLink ?? "https://drive.google.com/drive/folders/\(folder.id)"
        return (folder.id, URL(string: link) ?? URL(string: "https://drive.google.com")!)
    }

    /// Lets `emails` read a folder and everything in it (a contractor's job folder, for the team).
    func driveShare(_ folderID: String, with emails: [String]) async throws {
        let client = DriveClient(tokens: google)
        for email in emails { try await client.share(folderID, with: email) }
    }

    /// Shares Drive refused this run ("<folder> <email>").
    @MainActor static var refusedShares: Set<String> = []

    /// Lets everyone who can open a job read its Drive folder, so their devices download the photos its report prints:
    /// each address once per folder (remembered on this device), never this account's own. An address Google refuses
    /// is tried again next time; the others go on.
    public func shareJobFolder(_ folderID: String, with emails: [String]) async {
        let key = "drive.sharedTo.\(folderID)"
        var done = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let me = google.email.map(Permissions.normalized)
        let todo = Set(emails.map(Permissions.normalized)).subtracting(done)
            .filter { $0.contains("@") && $0 != me && !Self.refusedShares.contains(folderID + " " + $0) }
        guard !todo.isEmpty else { return }
        let client = DriveClient(tokens: google)
        for email in todo.sorted() {
            do { try await client.share(folderID, with: email); done.insert(email) }
            catch {
                // another account's folder, or an address Google doesn't know: not again until the app starts again
                Self.refusedShares.insert(folderID + " " + email)
                print("Drive: share \(folderID) with \(email): \(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(done.sorted(), forKey: key)
    }

    /// Finds or creates the folders of `path` under a folder from `driveFolder`, one inside the next, and returns the last id.
    func driveSubfolder(_ path: [String], under parentID: String) async throws -> String {
        let client = DriveClient(tokens: google)
        var id = parentID
        for name in path where !name.isEmpty { id = try await client.ensureFolder(name, parent: id).id }
        return id
    }

    /// Uploads one file into a folder from `driveFolder` and returns its id; the same file already there is reused.
    func driveUpload(_ file: DriveUpload, to folderID: String) async throws -> String {
        try await DriveClient(tokens: google).uploadOnce(file.data, name: file.name, mimeType: file.mimeType, parent: folderID).id
    }

    /// Downloads one file by id, such as a photo another device uploaded.
    func driveDownload(_ fileID: String) async throws -> Data {
        try await DriveClient(tokens: google).download(fileID)
    }
}
#endif
