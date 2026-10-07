import Foundation
import TCRoofCore

/// Permit form answers and photos of one job, on this device only (`Documents/Permits/<job>/`).
/// They hold national ID numbers, so they are written with complete file protection and are not synced.
struct PermitStore {
    let folder: URL

    init(job: Job) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let key = (job.syncID ?? job.code).replacingOccurrences(of: "/", with: "-")
        folder = docs.appendingPathComponent("Permits", isDirectory: true).appendingPathComponent(key, isDirectory: true)
    }

    private func ensureFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
    }

    func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name + ".json")) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, _ name: String) {
        ensureFolder()
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name + ".json"), options: [.atomic, .completeFileProtection])
    }

    /// Stores a (compressed) photo and returns its file name.
    func addPhoto(_ data: Data) -> String {
        ensureFolder()
        let name = UUID().uuidString + ".jpg"
        try? data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }

    /// Stores any file (PDF, image) and returns its file name.
    func addFile(_ data: Data, ext: String) -> String {
        ensureFolder()
        let name = UUID().uuidString + "." + (ext.isEmpty ? "dat" : ext.lowercased())
        try? data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }

    func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    func photo(_ name: String) -> Data? { try? Data(contentsOf: folder.appendingPathComponent(name)) }

    func deletePhoto(_ name: String) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }

    /// Writes the filled PDF to a temporary file for sharing or printing.
    func exportURL(_ data: Data, fileName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }
}
