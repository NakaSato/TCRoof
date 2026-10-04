import Foundation

/// A photo or signature saved as a file inside the job's folder.
extension Array {
    public subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

public struct Photo: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var fileName: String
    public var width: Int
    public var height: Int
    public var takenAt: Date
    public init(id: UUID = UUID(), fileName: String, width: Int, height: Int, takenAt: Date = Date()) {
        self.id = id; self.fileName = fileName; self.width = width; self.height = height; self.takenAt = takenAt
    }
    public var isPNG: Bool { fileName.lowercased().hasSuffix(".png") }
}

/// Obstacle on a roof or tank plan, in metres from the top-left corner.
public struct Obstacle: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var label = ""
    public var x = ""
    public var y = ""
    public var w = ""
    public var h = ""
    /// What it is on the C1 plan (docs/ui/survey-c1): "" an obstacle, `sky` a skylight sheet, `keep` a keep-out zone
    /// drawn for the PV layout. Older entries are obstacles. On the D1 tank (docs/ui/survey-d1-obstacles-iphone): `vent`
    /// a vent, `hatch` an access hatch.
    public var kind = ""
    /// A skylight panels may cover (วางทับได้); false keeps panels off it (ห้ามวางทับ).
    public var canCover = false
    /// D1 check on site: "" not checked yet, `ok` present (มีตรงแบบ), `absent` not there (ไม่มีจริง; left out of the drawings).
    public var status = ""
    /// D1: `standard` from the tank's standard layout, `added` on site; "" an older entry.
    public var origin = ""
    /// D1: where a standard point is on the standard layout (metres, as `x` / `y`), to tell it moved.
    public var stdX = ""
    public var stdY = ""
    public init(label: String = "", x: String = "", y: String = "", w: String = "", h: String = "", kind: String = "", canCover: Bool = false,
                status: String = "", origin: String = "", stdX: String = "", stdY: String = "") {
        self.label = label; self.x = x; self.y = y; self.w = w; self.h = h; self.kind = kind; self.canCover = canCover
        self.status = status; self.origin = origin; self.stdX = stdX; self.stdY = stdY
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        x = try c.decodeIfPresent(String.self, forKey: .x) ?? ""
        y = try c.decodeIfPresent(String.self, forKey: .y) ?? ""
        w = try c.decodeIfPresent(String.self, forKey: .w) ?? ""
        h = try c.decodeIfPresent(String.self, forKey: .h) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        canCover = try c.decodeIfPresent(Bool.self, forKey: .canCover) ?? false
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        origin = try c.decodeIfPresent(String.self, forKey: .origin) ?? ""
        stdX = try c.decodeIfPresent(String.self, forKey: .stdX) ?? ""
        stdY = try c.decodeIfPresent(String.self, forKey: .stdY) ?? ""
    }
}

/// One outgoing breaker of a board (A3 wide page). `count` > 1 groups equal breakers of a sub-board ("100 A × 2").
public struct Breaker: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var at = ""
    public var af = ""
    public var ic = ""
    public var poles = ""
    public var brand = ""
    /// Where it feeds ("ตู้ไฟฟ้า โรงสูบน้ำ (B1)").
    public var target = ""
    /// ดี / พอใช้ / ชำรุด
    public var condition = ""
    public var count = 1
    public init(at: String = "", af: String = "", ic: String = "", poles: String = "", brand: String = "", target: String = "", condition: String = "", count: Int = 1) {
        self.at = at; self.af = af; self.ic = ic; self.poles = poles; self.brand = brand; self.target = target; self.condition = condition; self.count = count
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        at = try c.decodeIfPresent(String.self, forKey: .at) ?? ""
        af = try c.decodeIfPresent(String.self, forKey: .af) ?? ""
        ic = try c.decodeIfPresent(String.self, forKey: .ic) ?? ""
        poles = try c.decodeIfPresent(String.self, forKey: .poles) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? ""
        condition = try c.decodeIfPresent(String.self, forKey: .condition) ?? ""
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
    }
}

/// A distribution board (MDB / SDB) under a transformer. The first board (k = 0) is the main one; its name, location and
/// front photo live in the old `tr{i}_feed`, `tr{i}_feedLoc`, `tr{i}_feedPhoto` answers, so those keep their meaning.
public struct Board: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name = ""
    public var isMain = false
    /// ACB / MCCB
    public var mainType = ""
    /// Main breaker trip (AT) — mirrored to `Transformer.mdb[k]`.
    public var at = ""
    public var af = ""
    public var icu = ""
    /// 3P / 4P
    public var poles = ""
    public var brand = ""
    public var breakers: [Breaker] = []
    public var condition = ""
    public var conditionNote = ""
    public var location = ""
    /// Sub-boards: one optional photo. The main board's four photos are `tr{i}_feedPhoto`, `_mdbOpen`, `_mdbBreaker`, `_mdbSpace`.
    public var photos: [Photo] = []
    public init(name: String = "", isMain: Bool = false, at: String = "") { self.name = name; self.isMain = isMain; self.at = at }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        isMain = try c.decodeIfPresent(Bool.self, forKey: .isMain) ?? false
        mainType = try c.decodeIfPresent(String.self, forKey: .mainType) ?? ""
        at = try c.decodeIfPresent(String.self, forKey: .at) ?? ""
        af = try c.decodeIfPresent(String.self, forKey: .af) ?? ""
        icu = try c.decodeIfPresent(String.self, forKey: .icu) ?? ""
        poles = try c.decodeIfPresent(String.self, forKey: .poles) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        breakers = try c.decodeIfPresent([Breaker].self, forKey: .breakers) ?? []
        condition = try c.decodeIfPresent(String.self, forKey: .condition) ?? ""
        conditionNote = try c.decodeIfPresent(String.self, forKey: .conditionNote) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        photos = try c.decodeIfPresent([Photo].self, forKey: .photos) ?? []
    }
}

/// A transformer with up to six MDB breaker sizes (A). Everything after `mdb` is new in the A3 wide page and optional,
/// so jobs saved before it (only `kva` and `mdb`) still decode.
public struct Transformer: Codable, Hashable, Identifiable, Sendable {
    /// A3 holds at most five (Excel's slots).
    public static let maxTransformers = 5
    public static let maxBoards = 6
    public var id = UUID()
    public var kva = ""
    public var mdb: [String] = Array(repeating: "", count: 6)
    /// oil / dry
    public var type = ""
    public var voltage = ""
    public var vectorGroup = ""
    public var impedance = ""
    public var brand = ""
    public var serial = ""
    public var year = ""
    /// DO fuse / DS / VCB
    public var hvProtection = ""
    /// nil = not answered
    public var hasLA: Bool?
    public var condition = ""
    public var conditionNote = ""
    /// Empty for jobs from before the wide page — use `resolvedBoards`.
    public var boards: [Board] = []
    public init(kva: String = "", mdb: [String] = Array(repeating: "", count: 6)) {
        self.kva = kva; self.mdb = mdb + Array(repeating: "", count: max(0, 6 - mdb.count))
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kva = try c.decodeIfPresent(String.self, forKey: .kva) ?? ""
        let m = try c.decodeIfPresent([String].self, forKey: .mdb) ?? []
        mdb = m + Array(repeating: "", count: max(0, 6 - m.count))
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        voltage = try c.decodeIfPresent(String.self, forKey: .voltage) ?? ""
        vectorGroup = try c.decodeIfPresent(String.self, forKey: .vectorGroup) ?? ""
        impedance = try c.decodeIfPresent(String.self, forKey: .impedance) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        serial = try c.decodeIfPresent(String.self, forKey: .serial) ?? ""
        year = try c.decodeIfPresent(String.self, forKey: .year) ?? ""
        hvProtection = try c.decodeIfPresent(String.self, forKey: .hvProtection) ?? ""
        hasLA = try c.decodeIfPresent(Bool.self, forKey: .hasLA)
        condition = try c.decodeIfPresent(String.self, forKey: .condition) ?? ""
        conditionNote = try c.decodeIfPresent(String.self, forKey: .conditionNote) ?? ""
        boards = try c.decodeIfPresent([Board].self, forKey: .boards) ?? []
    }

    /// The boards to show: `boards`, or for an older job one board per filled `mdb[k]` slot (k keeps its place; the first is the main one).
    public var resolvedBoards: [Board] {
        if !boards.isEmpty { return boards }
        guard let last = mdb.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return [] }
        return (0...last).map { k in Board(name: "MDB\(k + 1)", isMain: k == 0, at: mdb[k]) }
    }
    /// Stores boards (at most 6) and writes each one's AT to `mdb[k]`, so Excel, PDF and the A2 symbols read the same values as before.
    public mutating func setBoards(_ new: [Board]) {
        var b = Array(new.prefix(Self.maxBoards))
        for k in b.indices { b[k].isMain = k == 0 }
        boards = b
        mdb = (0..<Self.maxBoards).map { b[safe: $0]?.at ?? "" }
    }
}

/// The value of one form field.
public enum FieldValue: Codable, Hashable, Sendable {
    case text(String)
    case choice(String, other: String)
    case multi([String])
    case photo(Photo)
    case photos([Photo])
    case obstacles([Obstacle])
    case transformers([Transformer])
    case marks([MapMark])
    /// Lines and areas drawn on the A2 site picture.
    case shapes([SiteShape])
}

/// Answers for one scope (the job cover or one section), keyed by field id.
public struct Values: Codable, Hashable, Sendable {
    public var storage: [String: FieldValue] = [:]
    public init(_ storage: [String: FieldValue] = [:]) { self.storage = storage }
    public subscript(_ id: String) -> FieldValue? {
        get { storage[id] }
        set { storage[id] = newValue }
    }
    public func text(_ id: String) -> String {
        if case .text(let s)? = storage[id] { return s }
        return ""
    }
    public func choice(_ id: String) -> String? {
        if case .choice(let s, _)? = storage[id] { return s }
        return nil
    }
    public func other(_ id: String) -> String {
        if case .choice(let s, let o)? = storage[id], s == "อื่นๆ" { return o }
        return ""
    }
    public func multi(_ id: String) -> [String] {
        if case .multi(let a)? = storage[id] { return a }
        return []
    }
    public func photo(_ id: String) -> Photo? {
        if case .photo(let p)? = storage[id] { return p }
        return nil
    }
    public func photos(_ id: String) -> [Photo] {
        if case .photos(let a)? = storage[id] { return a }
        return []
    }
    public func obstacles(_ id: String) -> [Obstacle] {
        if case .obstacles(let a)? = storage[id] { return a }
        return []
    }
    public func transformers(_ id: String) -> [Transformer] {
        if case .transformers(let a)? = storage[id] { return a }
        return []
    }
    public func marks(_ id: String) -> [MapMark] {
        if case .marks(let a)? = storage[id] { return a }
        return []
    }
    public func shapes(_ id: String) -> [SiteShape] {
        if case .shapes(let a)? = storage[id] { return a }
        return []
    }
    /// After transformer `i` is removed, move the photos and feed answers of the ones after it down by one (keys are by position).
    public mutating func shiftTransformerAnswers(removed i: Int) {
        let suffixes = ["front", "back", "left", "right", "plate", "wide", "feed", "feedLoc", "feedPhoto", "mdbOpen", "mdbBreaker", "mdbSpace"]
        for j in i..<5 {
            for s in suffixes { storage["tr\(j)_\(s)"] = storage["tr\(j + 1)_\(s)"] }
        }
    }
    public func number(_ id: String) -> Double? { NumberInput.value(text(id)) }
    /// Every photo referenced by these answers (for copying, deleting and counting).
    public var allPhotos: [Photo] {
        storage.values.flatMap { v -> [Photo] in
            switch v {
            case .photo(let p): return [p]
            case .photos(let a): return a
            case .transformers(let a): return a.flatMap { $0.boards.flatMap(\.photos) }
            default: return []
            }
        }
    }
}

public enum ModuleType: String, Codable, CaseIterable, Identifiable, Sendable {
    case panel, inverter, water, backfeed, fts, roof, tank, sed, house, roofForm
    public var id: String { rawValue }
    /// Sections that fill fixed slots of the station sheet ("ระบบไฟฟ้า").
    public static let station: [ModuleType] = [.panel, .inverter, .water, .backfeed, .fts]
    public var isStation: Bool { Self.station.contains(self) }
}

public struct SurveyModule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var type: ModuleType
    public var name: String
    public var values: Values
    public init(id: UUID = UUID(), type: ModuleType, name: String = "", values: Values = Values()) {
        self.id = id; self.type = type; self.name = name; self.values = values
    }
}

public struct DriveLink: Codable, Hashable, Sendable {
    public var rootID: String?
    public var folderID: String?
    public var folderURL: String?
    public var folderName: String?
    public var lastSaved: Date?
    /// "รูปภาพ" folder inside the job folder.
    public var photosFolderID: String?
    /// Photo id → Drive file id of photos already uploaded, so each save sends only new ones.
    public var photoFiles: [String: String]?
    public init() {}
}

public struct Job: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var created: Date
    public var updated: Date
    /// Cover, site, electrical and summary answers.
    public var values: Values
    public var modules: [SurveyModule]
    public var drive: DriveLink?
    /// Sync id of the host app's job this report belongs to (TCRoof `Job.syncID`); nil when it stands alone.
    public var jobSyncID: String?
    /// Where the project is: a survey moved to installation is locked and read-only.
    public var stage: JobStage = .survey
    /// Installation progress, set when the survey moves to `.install`.
    public var install: InstallInfo?
    public init(id: UUID = UUID(), created: Date = Date(), updated: Date = Date(), values: Values = Values(), modules: [SurveyModule] = [],
                drive: DriveLink? = nil, jobSyncID: String? = nil, stage: JobStage = .survey, install: InstallInfo? = nil) {
        self.id = id; self.created = created; self.updated = updated; self.values = values; self.modules = modules; self.drive = drive
        self.jobSyncID = jobSyncID; self.stage = stage; self.install = install
    }
    public init(from decoder: Decoder) throws {
        // jobs saved before stages existed have no stage or install — they are surveys
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        created = try c.decode(Date.self, forKey: .created)
        updated = try c.decode(Date.self, forKey: .updated)
        values = try c.decode(Values.self, forKey: .values)
        modules = try c.decode([SurveyModule].self, forKey: .modules)
        drive = try c.decodeIfPresent(DriveLink.self, forKey: .drive)
        jobSyncID = try c.decodeIfPresent(String.self, forKey: .jobSyncID)
        stage = try c.decodeIfPresent(JobStage.self, forKey: .stage) ?? .survey
        install = try c.decodeIfPresent(InstallInfo.self, forKey: .install)
    }

    /// Only a survey filled in completely can become an installation job.
    public var canMoveToInstall: Bool { stage == .survey && completion.isComplete }

    /// Moves a complete survey to installation; false (and unchanged) otherwise.
    @discardableResult
    public mutating func moveToInstall(now: Date = Date()) -> Bool {
        guard canMoveToInstall else { return false }
        stage = .install
        install = InstallInfo(movedAt: now)
        return true
    }
    /// Undoes `moveToInstall`: the installation progress is dropped and the survey opens for editing again.
    @discardableResult
    public mutating func moveBackToSurvey() -> Bool {
        guard stage == .install else { return false }
        stage = .survey
        install = nil
        return true
    }
    public var docNo: String { values.text("docNo") }
    public var projectName: String { values.text("projectName") }
    public var allPhotos: [Photo] { values.allPhotos + modules.flatMap { $0.values.allPhotos } }

    /// A new job from one of the starting templates.
    public static func new(template: JobTemplate, now: Date = Date()) -> Job {
        var v = Values()
        v["date"] = .text(ISODate.string(now))
        v["rev"] = .text("00")
        // the report picture starts as the design's frame; older jobs have none and use the whole map
        v[MapCrop.key] = .text(MapCrop.standard.text)
        return Job(created: now, updated: now, values: v, modules: template.modules.map { SurveyModule(type: $0) })
    }
}

/// The three stages of a project, one home-screen tab each.
public enum JobStage: String, Codable, CaseIterable, Sendable {
    case survey, install, maintenance
}

/// Installation progress of a job moved out of the survey stage.
public struct InstallInfo: Codable, Hashable, Sendable {
    /// Steps finished, 0…7.
    public var doneSteps: Int
    /// How far the step in progress is, 0–1.
    public var currentFraction: Double
    public var team: String
    public var dueDate: Date?
    public var movedAt: Date
    public init(doneSteps: Int = 0, currentFraction: Double = 0, team: String = "", dueDate: Date? = nil, movedAt: Date = Date()) {
        self.doneSteps = doneSteps; self.currentFraction = currentFraction; self.team = team; self.dueDate = dueDate; self.movedAt = movedAt
    }

    public static let steps = ["ส่งวัสดุเข้าหน้างาน", "ติดตั้งโครงสร้างราง", "ติดตั้งแผงโซลาร์", "เดินสาย DC · ตู้ DC",
                               "ติดตั้งอินเวอร์เตอร์ · ตู้ AC", "ทดสอบระบบ", "ขนานไฟ · ส่งมอบ"]

    public var isDone: Bool { doneSteps >= Self.steps.count }
    /// Step in progress; nil once handed over.
    public var currentStep: String? { Self.steps[safe: doneSteps] }
    public var percent: Int {
        let n = Double(Self.steps.count)
        return Int((min(Double(doneSteps) + (isDone ? 0 : currentFraction), n) / n * 100).rounded())
    }
}

public struct JobTemplate: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let detail: String
    public let modules: [ModuleType]
    public static let all: [JobTemplate] = [
        .init(id: "station", label: "สถานี / โรงงาน / อาคารขนาดใหญ่", detail: "B1–B5 ระบบไฟฟ้า (ตู้ไฟฟ้า อินเวอร์เตอร์ น้ำล้างแผง กันย้อน FTS) และ C1 หลังคา",
              modules: [.panel, .inverter, .water, .backfeed, .fts, .roof]),
        .init(id: "house", label: "บ้านพักอาศัย / อาคารขนาดเล็ก", detail: "C3 บ้าน / อาคารขนาดเล็ก (แบบฟอร์มข้อ 1–24)", modules: [.house]),
        .init(id: "blank", label: "เริ่มแบบว่าง", detail: "เพิ่มหัวข้อสำรวจเองทีละรายการ", modules: []),
    ]
}

public enum ISODate {
    /// yyyy-MM-dd in the local calendar (Gregorian).
    public static func string(_ d: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }
    public static func date(_ s: String) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
    /// "28/9/2569" — Thai Buddhist-era date as written on the form.
    public static func thai(_ s: String) -> String {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return s }
        return "\(p[2])/\(p[1])/\(p[0] + 543)"
    }
}
