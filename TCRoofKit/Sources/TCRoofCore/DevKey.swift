import Foundation
import CommonCrypto

/// The developer key that opens จัดการผู้ใช้และสิทธิ์ (`config/devKey`): a PBKDF2-SHA256 hash of 6 digits and its salt,
/// never the digits. A Maintainer sets it in the Firebase console (`tools/dev-key`), and only a Maintainer can read it
/// (firestore.rules). It is a gate on the page; the rules decide what the page's changes may do.
public struct DevKey: Equatable, Sendable {
    public static let length = 6
    /// Wrong keys before the pad locks, and for how long.
    public static let maxTries = 5
    public static let lockout: TimeInterval = 10 * 60
    /// How long one unlock lasts.
    public static let unlockWindow: TimeInterval = 15 * 60

    public var hash: Data
    public var salt: Data
    public var iterations: Int
    public var expiresAt: Date?
    public var setBy: String?
    public var setAt: Date?

    public init(hash: Data, salt: Data, iterations: Int, expiresAt: Date? = nil, setBy: String? = nil, setAt: Date? = nil) {
        self.hash = hash
        self.salt = salt
        self.iterations = iterations
        self.expiresAt = expiresAt
        self.setBy = setBy
        self.setAt = setAt
    }

    /// From the document's fields: `hash` and `salt` in base64, `iterations` a number. Nil when any is missing or bad.
    public init?(hash: String?, salt: String?, iterations: Int?, expiresAt: Date? = nil, setBy: String? = nil, setAt: Date? = nil) {
        guard let h = hash.flatMap({ Data(base64Encoded: $0) }), !h.isEmpty,
              let s = salt.flatMap({ Data(base64Encoded: $0) }), !s.isEmpty,
              let n = iterations, n > 0 else { return nil }
        self.init(hash: h, salt: s, iterations: n, expiresAt: expiresAt, setBy: setBy, setAt: setAt)
    }

    /// A key made here from its digits (the demo and the tests).
    public static func make(digits: String, salt: Data, iterations: Int, expiresAt: Date? = nil) -> DevKey {
        DevKey(hash: derive(digits, salt: salt, iterations: iterations), salt: salt, iterations: iterations, expiresAt: expiresAt)
    }

    public static func derive(_ digits: String, salt: Data, iterations: Int, length: Int = 32) -> Data {
        let password = Array(digits.utf8)
        var out = [UInt8](repeating: 0, count: length)
        let status = salt.withUnsafeBytes { s in
            password.withUnsafeBufferPointer { p in
                p.baseAddress!.withMemoryRebound(to: Int8.self, capacity: password.count) { pw in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw, password.count,
                                         s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                         &out, length)
                }
            }
        }
        return status == kCCSuccess ? Data(out) : Data()
    }

    /// The digits give this key's hash (compared in constant time).
    public func matches(_ digits: String) -> Bool {
        guard digits.count == Self.length, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return false }
        let h = Self.derive(digits, salt: salt, iterations: iterations, length: hash.count)
        guard h.count == hash.count else { return false }
        return zip(h, hash).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    public func isExpired(now: Date = .now) -> Bool { expiresAt.map { $0 <= now } ?? false }
}

/// Wrong keys on this device: 5 lock the pad for 10 minutes. Kept on the device (UserDefaults), never synced.
public struct DevKeyAttempts: Codable, Equatable, Sendable {
    public var failures = 0
    public var lockedUntil: Date?

    public init(failures: Int = 0, lockedUntil: Date? = nil) {
        self.failures = failures
        self.lockedUntil = lockedUntil
    }

    public func isLocked(now: Date = .now) -> Bool { lockedUntil.map { $0 > now } ?? false }

    /// Tries left before the lock.
    public var left: Int { max(0, DevKey.maxTries - failures) }

    /// A wrong key. The fifth locks the pad and starts the count again for after the lock.
    public mutating func fail(now: Date = .now) {
        if let until = lockedUntil, until <= now { lockedUntil = nil; failures = 0 }
        failures += 1
        if failures >= DevKey.maxTries { lockedUntil = now.addingTimeInterval(DevKey.lockout) }
    }

    /// The right key, or the lock ran out.
    public mutating func reset() { self = DevKeyAttempts() }
}
