import Foundation

/// Paces every call made through the `GrowattAPI`s that share it, so Growatt's limit isn't reached instead of retried
/// against. Growatt answers 10012 (`error_frequently_access`) to the same call again within about 5 minutes; how it
/// counts (per call and plant, per plant, per token) hasn't been checked on the live server, so the gate holds to the
/// strictest it can without stopping the app:
/// - the same call (path and query or form: the same plant, day, page) at most once per `window`;
/// - any two calls on one token at least `spacing` apart, waiting for it rather than refusing;
/// - a 10012 holds that endpoint (its path, any query) on the token for `hold` and isn't retried (each retry is a
///   call Growatt counts too, and each restarts its wait);
/// - a call that never reached Growatt's API (no network, cancelled, an HTTP error) doesn't count.
///
/// A call refused is `Failure.tooFrequent` at once, with nothing sent; `freeAt` says until when. With a `Storage`
/// (the app's `shared`), the waits outlive a relaunch, so reopening the app doesn't send a call into one. Only a hash
/// of each key is stored, never the token.
public actor GrowattGate {
    /// Where the waits are kept between launches: what is free when, by hashed key, as seconds since 1970.
    public struct Storage: Sendable {
        public var load: @Sendable () -> [String: Double]
        public var save: @Sendable ([String: Double]) -> Void

        public init(load: @escaping @Sendable () -> [String: Double], save: @escaping @Sendable ([String: Double]) -> Void) {
            self.load = load; self.save = save
        }

        /// The device's defaults, under `key`.
        public static func defaults(_ key: String = "growatt.gate") -> Storage {
            Storage(load: { (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:] },
                    save: { UserDefaults.standard.set($0, forKey: key) })
        }
    }

    public static let shared = GrowattGate(storage: .defaults())

    /// Growatt's 5 minutes, less 30 s: a backstop under callers that pace themselves to the 5 minutes (Monitoring's
    /// poll keeps 4:45 a call and marks it just before), so it never refuses a call on their time.
    public static let window: TimeInterval = 5 * 60 - 30
    /// After a 10012: Growatt's whole 5 minutes and a little, since its wait started at the call it refused.
    public static let hold: TimeInterval = 5 * 60 + 15
    public static let spacing: TimeInterval = 1.5

    /// When each call (`call|…`) or held endpoint (`path|…`) is free again.
    private var until: [String: Date]
    private var lastOnToken: [String: Date] = [:]
    private let clock: @Sendable () -> Date
    private let window: TimeInterval
    private let hold: TimeInterval
    private let spacing: TimeInterval
    private let storage: Storage?

    public init(window: TimeInterval = GrowattGate.window, hold: TimeInterval = GrowattGate.hold,
                spacing: TimeInterval = GrowattGate.spacing, storage: Storage? = nil,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.window = window; self.hold = hold; self.spacing = spacing; self.storage = storage; self.clock = clock
        let now = clock()
        until = (storage?.load() ?? [:]).reduce(into: [:]) { out, e in
            let at = Date(timeIntervalSince1970: e.value)
            if at > now { out[e.key] = at }
        }
    }

    /// Whether `call` could go now (for a caller deciding what to read).
    public func isFree(token: String, call: String) -> Bool { freeAt(token: token, call: call) == nil }

    /// When `call` is free again (its own window, or its endpoint held after a 10012); nil when it is now.
    public func freeAt(token: String, call: String) -> Date? {
        let at = [until[Self.callKey(token, call)], until[Self.pathKey(token, Self.path(of: call))]].compactMap { $0 }.max()
        return at.flatMap { $0 > clock() ? $0 : nil }
    }

    /// When the endpoint `path` (`plant/list`) is free again on the token after a 10012; nil when it isn't held.
    public func freeAt(token: String, path: String) -> Date? {
        until[Self.pathKey(token, path)].flatMap { $0 > clock() ? $0 : nil }
    }

    /// Lets `call` go, after waiting out `spacing` since the token's last call, or throws `tooFrequent` when the same
    /// call went within `window` or its endpoint is held. The call is counted from here.
    public func admit(token: String, call: String) async throws {
        guard isFree(token: token, call: call) else { throw GrowattAPI.Failure.tooFrequent }
        let key = Self.callKey(token, call)
        // taken before waiting, so two calls asking together don't both pass
        until[key] = clock().addingTimeInterval(window)
        if let last = lastOnToken[token] {
            let wait = spacing - clock().timeIntervalSince(last)
            lastOnToken[token] = clock().addingTimeInterval(max(wait, 0))
            if wait > 0 {
                do { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) } catch {
                    until[key] = nil  // cancelled before it was sent
                    throw error
                }
            }
        } else {
            lastOnToken[token] = clock()
        }
        until[key] = clock().addingTimeInterval(window)
        persist()
    }

    /// The admitted call never reached Growatt's API (no network, cancelled, an HTTP error): it may go again at once.
    /// It was free when admitted, so nothing earlier is lost.
    public func release(token: String, call: String) {
        until[Self.callKey(token, call)] = nil
        persist()
    }

    /// Growatt answered 10012: the call waits a whole window from now, and its endpoint on the token `hold`.
    public func refused(token: String, call: String) {
        let now = clock()
        until[Self.callKey(token, call)] = now.addingTimeInterval(max(window, hold))
        until[Self.pathKey(token, Self.path(of: call))] = now.addingTimeInterval(hold)
        persist()
    }

    private func persist() {
        guard let storage else { return }
        let now = clock()
        until = until.filter { $0.value > now }
        storage.save(until.mapValues { $0.timeIntervalSince1970 })
    }

    /// `plant/list` of `plant/list?page=1`.
    static func path(of call: String) -> String { String(call.prefix { $0 != "?" }) }

    private static func callKey(_ token: String, _ call: String) -> String { "call|" + hash(token + " " + call) }
    private static func pathKey(_ token: String, _ path: String) -> String { "path|" + hash(token + " " + path) }

    /// FNV-1a, 64 bits, as hex: keys that can be stored without the token in them, the same on every launch.
    static func hash(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return String(h, radix: 16)
    }
}
