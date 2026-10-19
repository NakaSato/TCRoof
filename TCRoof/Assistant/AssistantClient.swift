import Foundation
import FirebaseAuth
import FirebaseCore
import TCRoofCore

/// The `assistant` Cloud Function (functions/src/index.ts), which holds the Qwen key. A callable function is a JSON POST
/// of `{"data": …}` with the account's ID token, answered by `{"result": …}` or `{"error": {status, message}}`, so this
/// needs no FirebaseFunctions SDK.
struct AssistantClient: Assistant.Transport {
    static let region = "asia-southeast1"

    enum Failure: LocalizedError, Equatable {
        case signedOut
        /// The function isn't deployed yet (404) or answered something else than a callable reply.
        case unavailable
        /// The function's refusal; its message is already Thai (functions/src/guard.ts, index.ts).
        case server(status: String, message: String)

        var errorDescription: String? {
            switch self {
            case .signedOut: "ต้องเข้าสู่ระบบก่อนใช้ผู้ช่วย"
            case .unavailable: "ผู้ช่วยยังไม่พร้อมใช้งาน ลองอีกครั้งภายหลัง"
            case .server(_, let message): message.isEmpty ? "ผู้ช่วยขัดข้อง ลองอีกครั้ง" : message
            }
        }
    }

    private struct Envelope: Encodable { let data: Assistant.Request }
    private struct Result: Decodable { let result: Assistant.Reply }
    private struct ErrorReply: Decodable {
        struct Body: Decodable { let status: String?; let message: String? }
        let error: Body
    }

    func complete(_ request: Assistant.Request) async throws -> Assistant.Reply {
        guard let user = Auth.auth().currentUser, let project = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://\(Self.region)-\(project).cloudfunctions.net/assistant") else { throw Failure.signedOut }
        let token = try await user.getIDToken()
        var r = URLRequest(url: url, timeoutInterval: 100)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.httpBody = try JSONEncoder().encode(Envelope(data: request))
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: r) } catch let e as URLError {
            throw e.code == .timedOut ? Failure.server(status: "DEADLINE_EXCEEDED", message: "ผู้ช่วยตอบช้าเกินไป ลองอีกครั้ง")
                : Failure.server(status: "UNAVAILABLE", message: "ติดต่อผู้ช่วยไม่ได้ ตรวจสอบอินเทอร์เน็ต")
        }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> Assistant.Reply {
        if let ok = try? JSONDecoder().decode(Result.self, from: data) { return ok.result }
        if let e = try? JSONDecoder().decode(ErrorReply.self, from: data) {
            throw Failure.server(status: e.error.status ?? "", message: e.error.message ?? "")
        }
        throw Failure.unavailable
    }
}
