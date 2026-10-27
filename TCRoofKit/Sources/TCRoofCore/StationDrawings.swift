import Foundation

/// A construction drawing of one station (docs/ui/install-tracking-ipad-settings §5 item 6): the SLD, the roof layout,
/// the mounting… Every change is uploaded as a new revision; earlier ones stay in its history. The job keeps the list
/// as `Job.drawingsJSON`, and each revision's file with the job's documents under `StationDrawings.folder`.
public struct StationDrawing: Codable, Equatable, Identifiable, Sendable {
    /// The drawing's code, `E-01`.
    public var id: String
    public var title: String
    /// The latest file's extension, lowercased: `pdf`, `dwg`, `jpg`, `png`.
    public var ext: String
    /// Oldest first.
    public var revisions: [Revision]

    public struct Revision: Codable, Equatable, Sendable {
        /// `00`, `01`, …
        public var rev: String
        public var date: Date
        /// Empty for REV 00; required from REV 01.
        public var reason: String
        /// The uploader's email.
        public var by: String
        /// The file's name among the job's documents.
        public var file: String
        /// Its Google Drive file id, once the job's documents were uploaded.
        public var driveID: String?

        public init(rev: String, date: Date, reason: String, by: String, file: String, driveID: String? = nil) {
            self.rev = rev; self.date = date; self.reason = reason; self.by = by; self.file = file; self.driveID = driveID
        }

        enum CodingKeys: String, CodingKey { case rev, date, reason, by, file, driveID }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rev = try c.decodeIfPresent(String.self, forKey: .rev) ?? StationDrawing.firstRev
            date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
            reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
            by = try c.decodeIfPresent(String.self, forKey: .by) ?? ""
            file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
            driveID = try c.decodeIfPresent(String.self, forKey: .driveID)
        }
    }

    public init(id: String, title: String, ext: String, revisions: [Revision] = []) {
        self.id = id; self.title = title; self.ext = ext.lowercased(); self.revisions = revisions
    }

    enum CodingKeys: String, CodingKey { case id, title, ext, revisions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        ext = try c.decodeIfPresent(String.self, forKey: .ext) ?? ""
        revisions = try c.decodeIfPresent([Revision].self, forKey: .revisions) ?? []
    }

    /// A new drawing's first revision.
    public static let firstRev = "00"

    public var latest: Revision? { revisions.last }

    /// The number the next upload takes: `00` for a drawing with none.
    public var nextRev: String { latest.map { Self.next(after: $0.rev) } ?? Self.firstRev }

    /// `00` → `01`, `09` → `10`: two digits at least.
    public static func next(after rev: String) -> String {
        let r = rev.trimmingCharacters(in: .whitespaces)
        guard let n = Int(r) else { return r.isEmpty ? firstRev : RevisionRule.next(after: r) }
        return String(format: "%02d", n + 1)
    }

    /// Every revision after the first says why it was made.
    public static func needsReason(_ rev: String) -> Bool { rev != firstRev }
}

public enum StationDrawings {
    /// The folder below the job's Drive folder (`2. เอกสารระหว่างก่อสร้าง/แบบก่อสร้าง/` on the center Drive).
    public static let folder = "แบบก่อสร้าง"

    /// The file types an upload takes.
    public static let extensions = ["pdf", "dwg", "jpg", "jpeg", "png"]

    public static func decode(_ json: String?) -> [StationDrawing] {
        json.flatMap { try? JSONDecoder().decode([StationDrawing].self, from: Data($0.utf8)) } ?? []
    }

    public static func encode(_ list: [StationDrawing]) -> String? {
        (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The revision's file name: `A-01 REV 02.pdf`, unique per drawing and revision so none replaces another.
    public static func fileName(id: String, rev: String, ext: String) -> String {
        let safe = id.replacingOccurrences(of: "/", with: "-")
        return "\(safe) REV \(rev).\(ext.lowercased())"
    }

    /// A code for a new drawing named without one: `D-01`, `D-02` … not taken yet.
    public static func newID(in list: [StationDrawing]) -> String {
        let taken = Set(list.map(\.id))
        var n = 1
        while taken.contains(String(format: "D-%02d", n)) { n += 1 }
        return String(format: "D-%02d", n)
    }

    /// An upload: onto `drawing` (an existing code), or a new drawing named `newTitle` (and coded `newID`, optional).
    public struct Upload: Equatable, Sendable {
        public var drawing: String?
        public var newID: String
        public var newTitle: String
        /// The picked file's extension; nil before a file is picked.
        public var ext: String?
        public var reason: String

        public init(drawing: String? = nil, newID: String = "", newTitle: String = "", ext: String? = nil, reason: String = "") {
            self.drawing = drawing; self.newID = newID; self.newTitle = newTitle; self.ext = ext; self.reason = reason
        }
    }

    /// The revision `upload` would make in `list`.
    public static func rev(of upload: Upload, in list: [StationDrawing]) -> String {
        upload.drawing.flatMap { id in list.first { $0.id == id } }?.nextRev ?? StationDrawing.firstRev
    }

    /// Why `upload` can't go yet, or nil when it can: a file, a name for a new drawing (its code not taken), and a
    /// reason from REV 01.
    public static func problem(_ upload: Upload, in list: [StationDrawing]) -> String? {
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let id = upload.drawing {
            if !list.contains(where: { $0.id == id }) { return "ไม่พบแบบนี้" }
        } else {
            if trim(upload.newTitle).isEmpty { return "ใส่ชื่อแบบ" }
            let code = trim(upload.newID)
            if !code.isEmpty, list.contains(where: { $0.id == code }) { return "รหัสแบบนี้มีแล้ว" }
        }
        guard let ext = upload.ext, extensions.contains(ext.lowercased()) else { return "เลือกไฟล์ PDF, DWG หรือรูป" }
        if StationDrawing.needsReason(rev(of: upload, in: list)), trim(upload.reason).isEmpty { return "ใส่เหตุผลการแก้ไข" }
        return nil
    }

    /// `list` with the upload appended as a new revision (a new drawing starts at REV 00); nil when it can't go
    /// (`problem`). An upload never replaces a revision.
    public static func appending(_ upload: Upload, to list: [StationDrawing], by: String, date: Date) -> (list: [StationDrawing], revision: StationDrawing.Revision, drawing: String)? {
        guard problem(upload, in: list) == nil, let ext = upload.ext?.lowercased() else { return nil }
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var out = list
        let index: Int
        if let id = upload.drawing, let i = out.firstIndex(where: { $0.id == id }) {
            index = i
        } else {
            let code = trim(upload.newID)
            out.append(StationDrawing(id: code.isEmpty ? newID(in: list) : code, title: trim(upload.newTitle), ext: ext))
            index = out.count - 1
        }
        let rev = out[index].nextRev
        let r = StationDrawing.Revision(rev: rev, date: date, reason: trim(upload.reason), by: by,
                                        file: fileName(id: out[index].id, rev: rev, ext: ext))
        out[index].revisions.append(r)
        out[index].ext = ext
        return (out, r, out[index].id)
    }

    /// `list` with each revision's Drive id taken from `uploaded` (file name → Drive id) where it had none.
    public static func recordingDriveIDs(_ list: [StationDrawing], uploaded: [String: String]) -> [StationDrawing] {
        list.map { d in
            var d = d
            d.revisions = d.revisions.map { r in
                var r = r
                if r.driveID == nil, let id = uploaded[r.file] { r.driveID = id }
                return r
            }
            return d
        }
    }
}
