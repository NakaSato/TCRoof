import Foundation

extension GrowattAPI {
    /// One end user of a business account (`user/c_user_list`).
    public struct EndUser: Equatable, Sendable {
        public var id: Int
        public var email: String
        public var name: String
        public var phone: String
        /// `c_user_regtime`, as written.
        public var registered: String

        public init(id: Int, email: String = "", name: String = "", phone: String = "", registered: String = "") {
            self.id = id; self.email = email; self.name = name; self.phone = phone; self.registered = registered
        }
    }

    /// `user/c_user_list`: the end users under the token's business account.
    public func endUsers(page: Int = 1, perPage: Int = 100) async throws -> Page<EndUser> {
        try Self.parseEndUsers(try await get("user/c_user_list", ["page": "\(max(page, 1))", "perpage": Self.perPage(perPage)]))
    }

    /// `data.c_user` and `data.count`; a row without an id is skipped.
    public static func parseEndUsers(_ data: Data) throws -> Page<EndUser> {
        let o = try dataObject(data)
        guard let rows = o["c_user"]?.array else { throw Failure.badResponse }
        return Page(items: rows.compactMap { r in
            guard let id = r["c_user_id"]?.int else { return nil }
            return EndUser(id: id, email: r["c_user_email"]?.text ?? "", name: r["c_user_name"]?.text ?? "",
                           phone: r["c_user_tel"]?.text ?? "", registered: r["c_user_regtime"]?.text ?? "")
        }, count: o["count"]?.int)
    }
}
