import Foundation

/// Reads and writes the JSON used by the web version of the app
/// ({app:"solar-survey", version, jobs:[…]} backups and {app, version, job} Drive data files),
/// so jobs move freely between the web app and the iPad app.
public enum WebBackup {
    public enum Failure: Error, LocalizedError {
        case notSurveyFile
        public var errorDescription: String? { "ไฟล์นี้ไม่ใช่ข้อมูลแบบสำรวจ (solar-survey)" }
    }

    // MARK: import

    /// Imports every job in a backup or Drive data file. Photos are written through `store`.
    /// Web jobs keep their ids stable by hashing the web id into a UUID, so re-importing replaces rather than duplicates.
    public static func importJobs(_ data: Data, into store: JobStore) throws -> [Job] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["app"] as? String == "solar-survey" else { throw Failure.notSurveyFile }
        var raw: [[String: Any]] = []
        if let a = root["jobs"] as? [[String: Any]] { raw = a }
        if let j = root["job"] as? [String: Any] { raw = [j] }
        var out: [Job] = []
        for r in raw {
            let job = try importJob(r, into: store)
            try store.save(job)
            out.append(job)
        }
        return out
    }

    static func importJob(_ r: [String: Any], into store: JobStore) throws -> Job {
        let webID = (r["id"] as? String) ?? UUID().uuidString
        let id = UUID(uuidString: webID) ?? stableUUID(webID)
        let created = date(r["created"]) ?? Date()
        let updated = date(r["updated"]) ?? created
        let d = (r["data"] as? [String: Any]) ?? [:]
        var job = Job(id: id, created: created, updated: updated)
        job.values = try values(d, fields: Schema.jobGroups.flatMap(\.fields), job: id, store: store)
        for m in (d["modules"] as? [[String: Any]]) ?? [] {
            guard let t = (m["type"] as? String).flatMap(ModuleType.init(rawValue:)) else { continue }
            let mid = (m["id"] as? String).map { UUID(uuidString: $0) ?? stableUUID(webID + "/" + $0) } ?? UUID()
            let v = try values((m["data"] as? [String: Any]) ?? [:], fields: Schema.spec(t).fields, job: id, store: store)
            job.modules.append(SurveyModule(id: mid, type: t, name: (m["name"] as? String) ?? "", values: v))
        }
        if let dr = d["drive"] as? [String: Any] {
            var link = DriveLink()
            link.rootID = dr["rootId"] as? String; link.folderID = dr["folderId"] as? String
            link.folderURL = dr["folderUrl"] as? String; link.folderName = dr["folderName"] as? String
            link.lastSaved = date(dr["lastSaved"])
            job.drive = link
        }
        job.jobSyncID = d["jobSyncId"] as? String
        return job
    }

    static func values(_ d: [String: Any], fields: [FieldSpec], job: UUID, store: JobStore) throws -> Values {
        var v = Values()
        for f in fields {
            guard let x = d[f.id] else { continue }
            switch f.kind {
            case .text, .number, .textarea, .member, .pick:
                if let s = x as? String { v[f.id] = .text(s) } else if let n = x as? NSNumber { v[f.id] = .text(n.stringValue) }
            case .choice:
                if let c = x as? [String: Any], let o = c["opt"] as? String, !o.isEmpty { v[f.id] = .choice(o, other: (c["other"] as? String) ?? "") }
            case .checks:
                if let a = x as? [String] { v[f.id] = .multi(a) }
            case .photo, .signature:
                if let p = try photo(x, job: job, store: store) { v[f.id] = .photo(p) }
            case .photos:
                let a = try ((x as? [Any]) ?? []).compactMap { try photo($0, job: job, store: store) }
                if !a.isEmpty { v[f.id] = .photos(a) }
            case .obstacles:
                let a = ((x as? [[String: Any]]) ?? []).map { o in
                    Obstacle(label: str(o["label"]), x: str(o["x"]), y: str(o["y"]), w: str(o["w"]), h: str(o["h"]))
                }
                if !a.isEmpty { v[f.id] = .obstacles(a) }
            case .transformers:
                let a = ((x as? [[String: Any]]) ?? []).map { t in
                    Transformer(kva: str(t["kva"]), mdb: ((t["mdb"] as? [Any]) ?? []).map(str))
                }
                if !a.isEmpty { v[f.id] = .transformers(a) }
            case .marks:
                let a = ((x as? [[String: Any]]) ?? []).compactMap { m -> MapMark? in
                    guard let k = (m["k"] as? String).flatMap(MarkKind.init(rawValue:)),
                          let mx = (m["x"] as? NSNumber)?.doubleValue, let my = (m["y"] as? NSNumber)?.doubleValue else { return nil }
                    return MapMark(kind: k, x: mx, y: my, value: str(m["v"]))
                }
                if !a.isEmpty { v[f.id] = .marks(a) }
            case .plan, .diagram, .note: break
            }
        }
        return v
    }

    static func photo(_ x: Any, job: UUID, store: JobStore) throws -> Photo? {
        guard let o = x as? [String: Any], let url = o["dataUrl"] as? String, let (bytes, png) = decodeDataURL(url) else { return nil }
        var w = (o["w"] as? NSNumber)?.intValue ?? 0, h = (o["h"] as? NSNumber)?.intValue ?? 0
        if w == 0 || h == 0, let s = ImageSize.of(bytes) { w = s.width; h = s.height }
        return try store.addPhoto(bytes, width: w, height: h, png: png, takenAt: date(o["at"]) ?? Date(), to: job)
    }

    // MARK: export

    /// A backup file the web app can restore (Settings → กู้คืน).
    public static func exportBackup(_ jobs: [Job], store: JobStore) throws -> Data {
        let root: [String: Any] = ["app": "solar-survey", "version": 4, "exported": iso(Date()), "jobs": jobs.map { exportJob($0, store: store) }]
        return try JSONSerialization.data(withJSONObject: root, options: [])
    }

    /// The survey-data.json saved in the job's Drive folder.
    public static func exportDriveData(_ job: Job, store: JobStore) throws -> Data {
        let root: [String: Any] = ["app": "solar-survey", "version": 3, "exported": iso(Date()), "job": exportJob(job, store: store)]
        return try JSONSerialization.data(withJSONObject: root, options: [])
    }

    static func exportJob(_ job: Job, store: JobStore) -> [String: Any] {
        var d = exportValues(job.values, fields: Schema.jobGroups.flatMap(\.fields), job: job.id, store: store)
        d["_v"] = 4
        d["modules"] = job.modules.map { m -> [String: Any] in
            ["id": m.id.uuidString, "type": m.type.rawValue, "name": m.name,
             "data": exportValues(m.values, fields: m.spec.fields, job: job.id, store: store)]
        }
        if let l = job.drive {
            var dr: [String: Any] = [:]
            dr["rootId"] = l.rootID; dr["folderId"] = l.folderID; dr["folderUrl"] = l.folderURL; dr["folderName"] = l.folderName
            if let s = l.lastSaved { dr["lastSaved"] = iso(s) }
            d["drive"] = dr
        }
        if let s = job.jobSyncID { d["jobSyncId"] = s }
        return ["id": job.id.uuidString, "created": iso(job.created), "updated": iso(job.updated), "data": d]
    }

    static func exportValues(_ v: Values, fields: [FieldSpec], job: UUID, store: JobStore) -> [String: Any] {
        var d: [String: Any] = [:]
        for f in fields {
            guard let x = v[f.id] else { continue }
            switch x {
            case .text(let s): d[f.id] = s
            case .choice(let s, let o): d[f.id] = ["opt": s, "other": o]
            case .multi(let a): d[f.id] = a
            case .photo(let p): if let e = exportPhoto(p, job: job, store: store) { d[f.id] = e }
            case .photos(let a): d[f.id] = a.compactMap { exportPhoto($0, job: job, store: store) }
            case .obstacles(let a): d[f.id] = a.map { ["label": $0.label, "x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h] }
            case .transformers(let a): d[f.id] = a.map { ["kva": $0.kva, "mdb": $0.mdb] as [String: Any] }
            case .marks(let a): d[f.id] = a.map { ["k": $0.kind.rawValue, "x": $0.x, "y": $0.y, "v": $0.value] as [String: Any] }
            }
        }
        return d
    }

    static func exportPhoto(_ p: Photo, job: UUID, store: JobStore) -> [String: Any]? {
        guard let bytes = store.data(of: p, in: job) else { return nil }
        return ["dataUrl": "data:image/\(p.isPNG ? "png" : "jpeg");base64," + bytes.base64EncodedString(),
                "w": p.width, "h": p.height, "name": p.fileName, "at": iso(p.takenAt)]
    }

    // MARK: helpers

    public static func decodeDataURL(_ s: String) -> (Data, png: Bool)? {
        guard s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") else { return nil }
        let head = s[s.startIndex..<comma]
        guard let d = Data(base64Encoded: String(s[s.index(after: comma)...]), options: .ignoreUnknownCharacters) else { return nil }
        return (d, head.contains("png"))
    }

    static func str(_ x: Any?) -> String {
        if let s = x as? String { return s }
        if let n = x as? NSNumber { return n.stringValue }
        return ""
    }

    static func date(_ x: Any?) -> Date? {
        if let n = x as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue / 1000) }
        guard let s = x as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s) ?? ISODate.date(s)
    }

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    /// Deterministic UUID (name-based) for web ids such as "muk7y0k8bja16".
    static func stableUUID(_ s: String) -> UUID {
        // FNV-1a 128 split into two 64-bit lanes
        var a: UInt64 = 0xcbf29ce484222325, b: UInt64 = 0x84222325cbf29ce4
        for byte in s.utf8 { a = (a ^ UInt64(byte)) &* 0x100000001b3; b = (b ^ UInt64(byte)) &* 0x100000001b3 &+ 0x9e3779b97f4a7c15 }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8(truncatingIfNeeded: a >> (8 * UInt64(i))); bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (8 * UInt64(i))) }
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Pixel size from JPEG/PNG headers (no image decoding, works on Linux too).
public enum ImageSize {
    public static func of(_ d: Data) -> (width: Int, height: Int)? {
        let b = [UInt8](d.prefix(512 * 1024))
        if b.count > 24, b[0] == 0x89, b[1] == 0x50 {
            let w = Int(b[16]) << 24 | Int(b[17]) << 16 | Int(b[18]) << 8 | Int(b[19])
            let h = Int(b[20]) << 24 | Int(b[21]) << 16 | Int(b[22]) << 8 | Int(b[23])
            return (w, h)
        }
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let m = b[i + 1]
            if m == 0xD8 || m == 0x01 || (0xD0...0xD7).contains(m) { i += 2; continue }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if (0xC0...0xCF).contains(m) && m != 0xC4 && m != 0xC8 && m != 0xCC {
                return (Int(b[i + 7]) << 8 | Int(b[i + 8]), Int(b[i + 5]) << 8 | Int(b[i + 6]))
            }
            i += 2 + len
        }
        return nil
    }
}
