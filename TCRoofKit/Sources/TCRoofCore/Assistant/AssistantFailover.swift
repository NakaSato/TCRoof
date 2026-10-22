import Foundation

public extension Assistant {

    /// What the assistant is asked for, each with its own provider (ตั้งค่า › ผู้ช่วยโครงการ (AI)): the chat, and the
    /// feed's daily summary (`DailyDigest`), which can go to a cheaper model.
    enum Use: String, CaseIterable, Sendable {
        case chat, digest

        public var title: String {
            switch self {
            case .chat: "แชทผู้ช่วยโครงการ"
            case .digest: "สรุปรายวันบนหน้าแรก"
            }
        }
    }

    /// A provider and the model to use with it.
    struct Route: Equatable, Sendable {
        public var provider: Provider
        public var model: String
        public init(provider: Provider, model: String) { self.provider = provider; self.model = model }
        public var label: String { provider.title + " | " + model }
    }

    /// Sends to `primary`, and to `backup` when the primary fails in a way another provider may not: a bad or expired
    /// key, the provider busy or down, its quota used up, an answer it couldn't give. The device's own daily limit is
    /// never passed on, and each request tries the primary again, so a recovered provider is used at once.
    struct Failover: Transport {
        public var primary: Transport
        public var backup: Transport?

        public init(primary: Transport, backup: Transport?) { self.primary = primary; self.backup = backup }

        public func complete(_ request: Request) async throws -> Reply {
            do {
                return try await primary.complete(request)
            } catch {
                guard let backup, Self.passesOn(error) else { throw error }
                var reply = try await backup.complete(request)
                reply.servedBy = reply.servedBy.map { $0 + " | สำรอง" }
                return reply
            }
        }

        /// Failures another provider may not have.
        public static func passesOn(_ error: Error) -> Bool {
            if error is CancellationError { return false }
            guard let f = error as? OpenAI.Failure else { return true }
            switch f {
            case .limit: return false
            case .noKey, .badKey, .busy, .server, .badReply, .freeQuotaUsed: return true
            }
        }
    }
}
