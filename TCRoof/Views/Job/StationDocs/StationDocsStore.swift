import Foundation
import TCRoofCore

/// Papers shared by every PWA station (org, branch, project and company scope), kept once on this device in
/// `Documents/StationDocs/`: the states in `library.json`, the files in `files/`. They can hold the grantor's and
/// grantee's ID cards, so they are written with complete file protection and are not synced or uploaded.
enum StationDocsStore {
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StationDocs", isDirectory: true)
    }
    static var filesFolder: URL { folder.appendingPathComponent("files", isDirectory: true) }
    private static var libraryURL: URL { folder.appendingPathComponent("library.json") }

    private static func ensure(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
    }

    /// The library, read from disk once per change of its file: screens call this in their bodies (the install page,
    /// the home's plan rows, the MP overview), so the decoded copy is kept while the file's date and size stay the
    /// same. A stat is all a call costs; a save, or the folder removed on an account switch, reads it again.
    static func loadLibrary() -> StationDocs.Library {
        let attrs = try? FileManager.default.attributesOfItem(atPath: libraryURL.path)
        let stamp = attrs.map { Stamp(modified: $0[.modificationDate] as? Date, size: ($0[.size] as? NSNumber)?.intValue ?? -1) }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let stamp, let cached, cached.stamp == stamp { return cached.library }
        guard let stamp, let data = try? Data(contentsOf: libraryURL),
              let lib = try? JSONDecoder().decode(StationDocs.Library.self, from: data) else {
            cached = nil
            return .init()
        }
        cached = (stamp, lib)
        return lib
    }

    /// Changes when the library's file does: a cache of what was made from it compares this.
    static func libraryStamp() -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: libraryURL.path)
        let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        return "\(modified)-\((attrs?[.size] as? NSNumber)?.intValue ?? -1)"
    }

    private struct Stamp: Equatable { let modified: Date?; let size: Int }
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cached: (stamp: Stamp, library: StationDocs.Library)?

    static func save(_ library: StationDocs.Library) {
        ensure(folder)
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: libraryURL, options: [.atomic, .completeFileProtection])
        cacheLock.lock(); cached = nil; cacheLock.unlock()
    }

    /// Writes a shared paper's file and returns the name it was kept under (one file per kind; a new file replaces it).
    static func keepFile(_ data: Data, kindID: String, ext: String) -> String? {
        ensure(filesFolder)
        removeFiles(kindID: kindID)
        let name = kindID + "." + (ext.isEmpty ? "pdf" : ext.lowercased())
        do {
            try data.write(to: filesFolder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            return name
        } catch { return nil }
    }

    static func fileURL(_ name: String) -> URL? {
        let url = filesFolder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func removeFiles(kindID: String) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: filesFolder.path)) ?? []
        for n in names where (n as NSString).deletingPathExtension == kindID {
            try? FileManager.default.removeItem(at: filesFolder.appendingPathComponent(n))
        }
    }
}
