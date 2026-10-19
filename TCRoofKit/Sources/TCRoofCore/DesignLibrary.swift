import Foundation

/// The standard design library (docs/specs/standard-designs.md §2): the designs the team saved from checked tanks
/// (the two supplied sheets are `TankDesign.seeds`, never stored here). Kept in a JSON file the app names
/// (`configure`), and synced through Firestore by the app (`onChange` out, `receive` in): the higher revision wins.
public final class DesignLibrary: @unchecked Sendable {
    public static let shared = DesignLibrary()

    private let lock = NSLock()
    private var saved: [TankDesign] = []
    private var url: URL?
    /// Called with each design saved, renamed, archived or imported here (not with ones received).
    public var onChange: ((TankDesign) -> Void)?

    public init() {}

    /// Reads the library from `url` (a missing or unreadable file is an empty library).
    public func configure(url: URL) {
        lock.lock(); defer { lock.unlock() }
        self.url = url
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        saved = (try? Data(contentsOf: url)).flatMap { try? dec.decode([TankDesign].self, from: $0) } ?? []
    }

    /// Every saved tank design, archived ones too (settings lists them).
    public var tanks: [TankDesign] { lock.lock(); defer { lock.unlock() }; return saved }

    /// Saves a new design, or an edit of one (its revision raised).
    public func save(_ design: TankDesign) {
        guard !design.isSeed else { return }
        var d = design
        lock.lock()
        if let i = saved.firstIndex(where: { $0.id == d.id }) {
            d.revision = saved[i].revision + 1
            saved[i] = d
        } else {
            saved.append(d)
        }
        persist()
        lock.unlock()
        onChange?(d)
    }

    public func rename(_ id: String, to name: String) { edit(id) { $0.name = name } }
    public func archive(_ id: String, _ on: Bool = true) { edit(id) { $0.archived = on } }
    public func setSheet(_ id: String, _ pages: [Photo]) { edit(id) { $0.sheet = pages } }

    func edit(_ id: String, _ f: (inout TankDesign) -> Void) {
        guard var d = tanks.first(where: { $0.id == id }) else { return }
        f(&d)
        d.savedAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        save(d)
    }

    /// A design from another device: kept when it's new or has a higher revision (the same revision: the later save).
    @discardableResult
    public func receive(_ d: TankDesign) -> Bool {
        guard !d.isSeed else { return false }
        lock.lock(); defer { lock.unlock() }
        if let i = saved.firstIndex(where: { $0.id == d.id }) {
            let old = saved[i]
            let newer = d.revision > old.revision || (d.revision == old.revision && (d.savedAt ?? .distantPast) > (old.savedAt ?? .distantPast))
            guard newer else { return false }
            saved[i] = d
        } else {
            saved.append(d)
        }
        persist()
        return true
    }

    /// Imports a `.tcdesign` file: a design already here is replaced only by a higher revision.
    @discardableResult
    public func importFile(_ data: Data) throws -> TankDesign {
        let d = try TankDesign.imported(data)
        if receive(d) { onChange?(d) }
        return d
    }

    // MARK: the scanned sheet (§3.4)

    /// Where a design's sheet pages are kept: next to the library file.
    public var sheetFolder: URL? {
        lock.lock(); defer { lock.unlock() }
        return url?.deletingLastPathComponent().appendingPathComponent("standard-design-sheets", isDirectory: true)
    }
    public func sheetURL(_ p: Photo) -> URL? { sheetFolder?.appendingPathComponent(p.fileName) }
    public func hasSheetPage(_ p: Photo) -> Bool { sheetURL(p).map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    /// Stores a page's JPEG (from the app, or received from another device) and returns it as a sheet photo.
    @discardableResult
    public func storeSheetPage(_ jpeg: Data, width: Int, height: Int, id: UUID = UUID()) -> Photo? {
        let p = Photo(id: id, fileName: id.uuidString + ".jpg", width: width, height: height)
        guard let dir = sheetFolder, let u = sheetURL(p) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard (try? jpeg.write(to: u, options: .atomic)) != nil else { return nil }
        return p
    }

    /// Empties the library (tests, sign-out).
    public func reset() { lock.lock(); saved = []; persist(); lock.unlock() }

    private func persist() {
        guard let url else { return }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? e.encode(saved).write(to: url, options: .atomic)
    }
}
