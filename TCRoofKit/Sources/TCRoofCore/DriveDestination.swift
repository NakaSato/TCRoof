import Foundation

/// Where a job's files go on Google Drive, by role (the user, 2026-10-17; the app's `DriveRoute` runs it):
/// - a TC engineer (manager or internal team) signed in with full Drive writes into the company's center folder,
///   `<job>/1. เอกสารส่งมอบ/` laid out as the PWA hand-over (`HandoverFolders`) and `<job>/2. เอกสารระหว่างก่อสร้าง/`
///   for the construction records;
/// - an external contractor, or a TC engineer with no center folder set or signed in before full Drive was asked,
///   writes into their own Drive's `TCRoof Projects/<job>/`.
public enum DriveDestination {
    /// The center folder this account's uploads go into; nil for its own Drive.
    public static func center(role: UserRole, hasFullDrive: Bool, centerFolder: String?) -> String? {
        guard role != .external, hasFullDrive, let centerFolder, !centerFolder.isEmpty else { return nil }
        return centerFolder
    }

    /// A construction record's folders below the job's folder: on the center Drive inside `2. เอกสารระหว่างก่อสร้าง`.
    public static func construction(_ path: [String], onCenter: Bool) -> [String] {
        onCenter ? [HandoverFolders.construction] + path : path
    }

    /// A folder id typed in the console (`config/app.centerDriveFolder`): the id itself, or the id in a
    /// `drive.google.com/drive/folders/<id>` link; nil for anything else.
    public static func folderID(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let r = t.range(of: "/folders/") {
            let id = t[r.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            return id.isEmpty ? nil : String(id)
        }
        return t.contains("/") ? nil : t
    }
}
