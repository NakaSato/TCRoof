#if canImport(UIKit)
import Foundation
import UIKit
import AuthenticationServices
import CryptoKit
import Security
import DriveSync

/// Google sign-in for Drive using OAuth 2.0 with PKCE (no third-party SDK).
/// Needs an OAuth client of type "iOS" in Google Cloud Console; paste its client ID in Settings.
public final class GoogleAuth: NSObject, DriveTokenProvider, @unchecked Sendable {
    public var clientID: String { didSet { if clientID != oldValue { signOut() } } }
    public static let scope = "openid email profile https://www.googleapis.com/auth/drive.file"

    private let lock = NSLock()
    private var accessTokenValue: String?
    private var expiry = Date.distantPast
    private var session: ASWebAuthenticationSession?

    public init(clientID: String) { self.clientID = clientID.trimmingCharacters(in: .whitespaces) }

    public var isSignedIn: Bool { Keychain.read("google.refresh") != nil }
    public var email: String? { UserDefaults.standard.string(forKey: "solarSurvey.googleEmail") }
    /// Account holder's name ("Chanthawat Kiriyadee"); nil for accounts signed in before the profile scope was asked.
    public var name: String? { UserDefaults.standard.string(forKey: "solarSurvey.googleName") }

    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
    var redirectScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    var redirectURI: String { redirectScheme + ":/oauth2redirect" }

    public enum Failure: Error, LocalizedError {
        case noClientID, cancelled, badResponse(String)
        public var errorDescription: String? {
            switch self {
            case .noClientID: return "ยังไม่ได้ใส่ Google OAuth Client ID (iOS) ในหน้าตั้งค่า"
            case .cancelled: return "ยกเลิกการลงชื่อเข้าใช้"
            case .badResponse(let s): return "ลงชื่อเข้าใช้ Google ไม่สำเร็จ: \(s)"
            }
        }
    }

    @MainActor
    public func signIn() async throws {
        guard clientID.hasSuffix(".apps.googleusercontent.com") else { throw Failure.noClientID }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [.init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI),
                        .init(name: "response_type", value: "code"), .init(name: "scope", value: Self.scope),
                        .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                        .init(name: "prompt", value: "consent"), .init(name: "access_type", value: "offline")]
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: redirectScheme) { url, err in
                if let url { cont.resume(returning: url) }
                else if let e = err as? ASWebAuthenticationSessionError, e.code == .canceledLogin { cont.resume(throwing: Failure.cancelled) }
                else { cont.resume(throwing: err ?? Failure.cancelled) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            s.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw Failure.badResponse("ไม่มีรหัสยืนยัน")
        }
        let tok = try await token(["code": code, "code_verifier": verifier, "grant_type": "authorization_code", "redirect_uri": redirectURI])
        if let r = tok["refresh_token"] as? String { Keychain.write("google.refresh", r) }
        if let idt = tok["id_token"] as? String { remember(idToken: idt) }
    }

    /// Keeps the email and name from an OpenID token.
    private func remember(idToken: String) {
        let c = Self.claims(fromIDToken: idToken)
        if let mail = c?["email"] as? String { UserDefaults.standard.set(mail, forKey: "solarSurvey.googleEmail") }
        if let n = (c?["name"] as? String)?.trimmingCharacters(in: .whitespaces), !n.isEmpty { UserDefaults.standard.set(n, forKey: "solarSurvey.googleName") }
    }

    public func signOut() {
        clearToken()
        Keychain.delete("google.refresh")
        UserDefaults.standard.removeObject(forKey: "solarSurvey.googleEmail")
        UserDefaults.standard.removeObject(forKey: "solarSurvey.googleName")
    }

    public func accessToken() async throws -> String {
        if let t = cachedToken() { return t }
        guard let refresh = Keychain.read("google.refresh") else { throw DriveError.notSignedIn }
        _ = try await token(["refresh_token": refresh, "grant_type": "refresh_token"])
        guard let t = cachedToken() else { throw DriveError.notSignedIn }
        return t
    }
    /// A fresh OpenID token with its access token, for signing in to Firebase with the same Google account.
    public func idAndAccessToken() async throws -> (idToken: String, accessToken: String) {
        guard let refresh = Keychain.read("google.refresh") else { throw DriveError.notSignedIn }
        let tok = try await token(["refresh_token": refresh, "grant_type": "refresh_token"])
        guard let idToken = tok["id_token"] as? String, let accessToken = tok["access_token"] as? String else {
            throw Failure.badResponse("ไม่มี id_token")
        }
        remember(idToken: idToken)
        return (idToken, accessToken)
    }

    private func cachedToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let t = accessTokenValue, expiry > Date().addingTimeInterval(60) { return t }
        return nil
    }
    private func clearToken() {
        lock.lock(); defer { lock.unlock() }
        accessTokenValue = nil; expiry = .distantPast
    }
    private func setToken(_ t: String, expiresIn: Int) {
        lock.lock(); defer { lock.unlock() }
        accessTokenValue = t
        expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
    }

    @discardableResult
    private func token(_ params: [String: String]) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var all = params; all["client_id"] = clientID
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        r.httpBody = Data(all.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }.joined(separator: "&").utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let at = obj["access_token"] as? String else {
            if (obj["error"] as? String) == "invalid_grant" { signOut() }
            throw Failure.badResponse((obj["error_description"] as? String) ?? (obj["error"] as? String) ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        setToken(at, expiresIn: (obj["expires_in"] as? NSNumber)?.intValue ?? 3600)
        return obj
    }

    static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }
    static func email(fromIDToken t: String) -> String? { claims(fromIDToken: t)?["email"] as? String }
    static func claims(fromIDToken t: String) -> [String: Any]? {
        let parts = t.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var s = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let d = Data(base64Encoded: s), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o
    }
}

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first ?? ASPresentationAnchor()
        }
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum Keychain {
    static let service = "SolarSurvey"
    static func write(_ key: String, _ value: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
                                kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func read(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}
#endif
