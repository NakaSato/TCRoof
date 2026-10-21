#if canImport(UIKit)
import Foundation
import Observation
import UIKit
import CryptoKit
import TCRoofCore

/// The signed-in account's own signature, drawn once (Settings › ลายเซ็นของฉัน, or `จำลายเซ็นนี้` on a sign sheet) and
/// offered as `ใช้ลายเซ็นของฉัน` wherever that person signs. Kept on this device only: never synced, uploaded or backed up,
/// one PNG per account (`Application Support/MySignature/<sha256 of the email>.png`), so on a shared iPad each person sees
/// only their own. A report signed with it keeps its own copy, as with a drawn one.
@MainActor
@Observable
public final class MySignature {
    public static let shared = MySignature()

    /// The signed-in email; the app sets it on sign-in and sign-out. Nil: no saved signature is offered.
    public var account: String? {
        didSet { if account != oldValue { load() } }
    }
    /// The saved PNG of `account`.
    public private(set) var png: Data?

    public var image: UIImage? { png.flatMap(UIImage.init(data:)) }
    public var hasSignature: Bool { png != nil }

    private init() {}

    public func save(_ data: Data) {
        guard let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var dir = url.deletingLastPathComponent()
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
            png = data
        } catch {
            png = nil
        }
    }

    public func save(_ image: UIImage) {
        if let data = image.pngData() { save(data) }
    }

    public func remove() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        png = nil
    }

    private func load() {
        png = fileURL.flatMap { try? Data(contentsOf: $0) }
    }

    private var fileURL: URL? {
        guard let account, !account.isEmpty,
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let key = SHA256.hash(data: Data(Permissions.normalized(account).utf8)).map { String(format: "%02x", $0) }.joined()
        return base.appendingPathComponent("MySignature", isDirectory: true).appendingPathComponent(key + ".png")
    }
}
#endif
