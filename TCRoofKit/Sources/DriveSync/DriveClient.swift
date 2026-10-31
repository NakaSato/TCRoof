import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Supplies a fresh OAuth access token (the app target implements this with Google Sign-In).
public protocol DriveTokenProvider: Sendable {
    func accessToken() async throws -> String
    /// A token that stays valid for at least `seconds`: an upload handed to a background session may only start later.
    func accessToken(validFor seconds: TimeInterval) async throws -> String
}

public extension DriveTokenProvider {
    func accessToken(validFor seconds: TimeInterval) async throws -> String { try await accessToken() }
}

/// Sends an upload's bytes outside the app's own life: the app's background URLSession (`DriveBackgroundTransfer`),
/// which iOS goes on with while the app is in the background or after the system ends it.
public protocol DriveTransfer: Sendable {
    /// Starts sending `body` with `request` and returns the id to wait on.
    func enqueue(_ request: URLRequest, body: Data) throws -> Int
    /// The response's body and status once the upload has finished.
    func result(_ id: Int) async throws -> (data: Data, status: Int)
}

public struct DriveFile: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let mimeType: String?
    public let modifiedTime: String?
    public let size: String?
    public let webViewLink: String?
    public let trashed: Bool?
    /// Content checksum Drive keeps for each uploaded file (none for folders).
    public let md5Checksum: String?
    public var isFolder: Bool { mimeType == DriveClient.folderMime }
    public var modified: Date? {
        guard let s = modifiedTime else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

public enum DriveError: Error, LocalizedError {
    case notSignedIn
    case http(Int, String)
    case badResponse
    public var errorDescription: String? {
        switch self {
        case .notSignedIn: return "ยังไม่ได้ลงชื่อเข้าใช้ Google"
        case .http(401, _): return "การเชื่อมต่อ Google หมดอายุ — ลงชื่อเข้าใช้ใหม่"
        case .http(403, let m): return "Google Drive ไม่อนุญาต: \(m)"
        case .http(404, _): return "ไม่พบไฟล์หรือโฟลเดอร์ใน Google Drive (อาจถูกลบ)"
        case .http(let c, let m): return "Google Drive แจ้งข้อผิดพลาด \(c): \(m)"
        case .badResponse: return "Google Drive ตอบกลับไม่ถูกต้อง"
        }
    }
}

/// Google Drive REST v3 — only the calls the app needs.
public struct DriveClient: Sendable {
    public static let folderMime = "application/vnd.google-apps.folder"
    static let api = URL(string: "https://www.googleapis.com/drive/v3/files")!
    static let upload = URL(string: "https://www.googleapis.com/upload/drive/v3/files")!
    static let fields = "id,name,mimeType,modifiedTime,size,webViewLink,trashed,md5Checksum"

    let tokens: DriveTokenProvider
    let session: URLSession
    /// Where `startUploadOnce` sends the bytes; nil sends them on `session` while the app waits.
    let transfer: (any DriveTransfer)?
    /// Set once by the app at launch (`DriveBackgroundTransfer.shared`); every client made after takes it.
    nonisolated(unsafe) public static var backgroundTransfer: (any DriveTransfer)?
    /// How long the token of an upload handed to the transfer must last: iOS may start it a while later.
    static let transferTokenLife: TimeInterval = 30 * 60

    public init(tokens: DriveTokenProvider, session: URLSession = .shared,
                transfer: (any DriveTransfer)? = DriveClient.backgroundTransfer) {
        self.tokens = tokens; self.session = session; self.transfer = transfer
    }

    static func q(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") }

    private func send(_ req: URLRequest) async throws -> Data {
        var r = req
        r.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: r)
        guard let h = resp as? HTTPURLResponse else { throw DriveError.badResponse }
        try Self.check(h.statusCode, data)
        return data
    }

    /// Throws Drive's own message for a status outside 2xx.
    static func check(_ status: Int, _ data: Data) throws {
        guard !(200..<300).contains(status) else { return }
        let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
        throw DriveError.http(status, msg ?? String(decoding: data.prefix(200), as: UTF8.self))
    }

    public func search(_ query: String, orderBy: String? = nil, pageSize: Int = 100) async throws -> [DriveFile] {
        guard var c = URLComponents(url: Self.api, resolvingAgainstBaseURL: false) else { throw DriveError.badResponse }
        c.queryItems = [.init(name: "q", value: query), .init(name: "fields", value: "files(\(Self.fields))"),
                        .init(name: "pageSize", value: String(pageSize)), .init(name: "spaces", value: "drive")]
        if let o = orderBy { c.queryItems?.append(.init(name: "orderBy", value: o)) }
        guard let url = c.url else { throw DriveError.badResponse }
        struct List: Decodable { let files: [DriveFile] }
        return try JSONDecoder().decode(List.self, from: try await send(URLRequest(url: url))).files
    }

    public func metadata(_ id: String) async throws -> DriveFile {
        guard var c = URLComponents(url: Self.api.appendingPathComponent(id), resolvingAgainstBaseURL: false) else { throw DriveError.badResponse }
        c.queryItems = [.init(name: "fields", value: Self.fields)]
        guard let url = c.url else { throw DriveError.badResponse }
        return try JSONDecoder().decode(DriveFile.self, from: try await send(URLRequest(url: url)))
    }

    /// True when the file or folder still exists and is not in the trash.
    public func exists(_ id: String) async -> Bool {
        guard let f = try? await metadata(id) else { return false }
        return f.trashed != true
    }

    /// True only when Drive says the file or folder is gone (not found, or in the trash). Any other failure throws (a
    /// lost connection, an expired sign-in, a 403 rate limit), so it never passes for a deleted folder and starts its
    /// uploads over.
    public func isGone(_ id: String) async throws -> Bool {
        do { return try await metadata(id).trashed == true }
        catch DriveError.http(404, _) { return true }
    }

    public func findFolder(_ name: String, parent: String) async throws -> DriveFile? {
        try await search("name = '\(Self.q(name))' and mimeType = '\(Self.folderMime)' and '\(Self.q(parent))' in parents and trashed = false").first
    }

    public func createFolder(_ name: String, parent: String) async throws -> DriveFile {
        var c = URLComponents(url: Self.api, resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "fields", value: Self.fields)]
        var r = URLRequest(url: c.url!); r.httpMethod = "POST"
        r.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "mimeType": Self.folderMime, "parents": [parent]])
        return try JSONDecoder().decode(DriveFile.self, from: try await send(r))
    }

    /// Gives `email` access to a file or folder (a folder's files inherit it), without an email from Drive.
    public func share(_ id: String, with email: String, role: String = "reader") async throws {
        var c = URLComponents(url: Self.api.appendingPathComponent(id).appendingPathComponent("permissions"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "sendNotificationEmail", value: "false"), .init(name: "fields", value: "id")]
        var r = URLRequest(url: c.url!); r.httpMethod = "POST"
        r.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["role": role, "type": "user", "emailAddress": email])
        _ = try await send(r)
    }

    public func ensureFolder(_ name: String, parent: String) async throws -> DriveFile {
        if let f = try await findFolder(name, parent: parent) { return f }
        return try await createFolder(name, parent: parent)
    }

    /// The request and body of a multipart upload (no token yet).
    static func multipart(_ data: Data, name: String, mimeType: String, parent: String) throws -> (request: URLRequest, body: Data) {
        var c = URLComponents(url: Self.upload, resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "uploadType", value: "multipart"), .init(name: "fields", value: Self.fields)]
        let boundary = "survey-" + UUID().uuidString
        var body = Data()
        let meta = try JSONSerialization.data(withJSONObject: ["name": name, "parents": [parent], "mimeType": mimeType])
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)); body.append(meta)
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n".utf8)); body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var r = URLRequest(url: c.url!); r.httpMethod = "POST"
        r.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.timeoutInterval = 300
        return (r, body)
    }

    /// Multipart upload of a new file (Drive keeps earlier versions as separate files). With a `transfer`, the bytes go
    /// through it, so an upload under way when the person leaves the app still lands.
    public func upload(_ data: Data, name: String, mimeType: String, parent: String) async throws -> DriveFile {
        if let transfer { return try await handOver(data, name: name, mimeType: mimeType, parent: parent, to: transfer).value }
        let (request, body) = try Self.multipart(data, name: name, mimeType: mimeType, parent: parent)
        var r = request
        r.httpBody = body
        return try JSONDecoder().decode(DriveFile.self, from: try await send(r))
    }

    /// Hands the upload to `transfer` and returns the wait for its file.
    private func handOver(_ data: Data, name: String, mimeType: String, parent: String,
                          to transfer: any DriveTransfer) async throws -> Task<DriveFile, Error> {
        let (request, body) = try Self.multipart(data, name: name, mimeType: mimeType, parent: parent)
        var r = request
        r.setValue("Bearer \(try await tokens.accessToken(validFor: Self.transferTokenLife))", forHTTPHeaderField: "Authorization")
        let id = try transfer.enqueue(r, body: body)
        return Task {
            let (out, status) = try await transfer.result(id)
            try Self.check(status, out)
            return try JSONDecoder().decode(DriveFile.self, from: out)
        }
    }

    /// The file of that name with the same content already in `parent`, if any.
    func existing(_ data: Data, name: String, parent: String) async throws -> DriveFile? {
        #if canImport(CryptoKit)
        let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let same = try await search("name = '\(Self.q(name))' and '\(Self.q(parent))' in parents and trashed = false")
        return same.first { $0.md5Checksum == md5 }
        #else
        return nil
        #endif
    }

    /// Uploads unless `parent` already holds a file of that name with the same content, which it returns instead: an
    /// upload whose answer was lost, or a photo a stale list says was never sent, never lands on Drive twice.
    public func uploadOnce(_ data: Data, name: String, mimeType: String, parent: String) async throws -> DriveFile {
        if let f = try await existing(data, name: name, parent: parent) { return f }
        return try await upload(data, name: name, mimeType: mimeType, parent: parent)
    }

    /// `uploadOnce` in two steps: this returns once the bytes are handed over (or the same file is found), and the task
    /// it returns gives the file when it lands. With a `transfer`, iOS goes on sending while the app is in the
    /// background or after the system ends it, so a caller starts every file before waiting on any. A file that lands
    /// while nothing waits (the app was ended) is found by the same check on the next pass, not sent again.
    public func startUploadOnce(_ data: Data, name: String, mimeType: String, parent: String) async throws -> Task<DriveFile, Error> {
        if let f = try await existing(data, name: name, parent: parent) { return Task { f } }
        guard let transfer else {
            let client = self
            return Task { try await client.upload(data, name: name, mimeType: mimeType, parent: parent) }
        }
        return try await handOver(data, name: name, mimeType: mimeType, parent: parent, to: transfer)
    }

    public func download(_ id: String) async throws -> Data {
        var c = URLComponents(url: Self.api.appendingPathComponent(id), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "alt", value: "media")]
        var r = URLRequest(url: c.url!); r.timeoutInterval = 300
        return try await send(r)
    }
}
