import Foundation

/// Sets aside a SwiftData store that won't open, so the app can start an empty one and sync bring the records back.
/// The store's files (the store and SQLite's write-ahead log and shared memory) move together into a dated folder,
/// kept for recovering what hadn't synced.
public enum StoreBackup {
    /// The store's files, whether or not each exists.
    public static func files(of store: URL) -> [URL] {
        [store, URL(fileURLWithPath: store.path + "-wal"), URL(fileURLWithPath: store.path + "-shm")]
    }

    /// Moves the store's files that exist into a new folder under `folder`, named by `date`; returns that folder.
    @discardableResult
    public static func moveAside(_ store: URL, into folder: URL, at date: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "store-\(formatter.string(from: date))"
        var target = folder.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(name)-\(n)", isDirectory: true)
            n += 1
        }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for file in files(of: store) where fm.fileExists(atPath: file.path) {
            try fm.moveItem(at: file, to: target.appendingPathComponent(file.lastPathComponent))
        }
        return target
    }
}
