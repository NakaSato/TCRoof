#if canImport(UIKit)
import Foundation
import UIKit
import AuthenticationServices
import CryptoKit
import Security
import DriveSync

/// Google sign-in for Drive using OAuth 2.0 with PKCE (no third-party SDK).
/// Needs an OAuth client of type "iOS" in Google Cloud Console; paste its client ID in Settings.
@MainActor
public final class GoogleAuth: NSObject, DriveTokenProvider {
    public var clientID: String {
        get { tokens.clientID }
        set {
            if newValue != tokens.clientID { authorization?.cancel(); authorization = nil }
            tokens.clientID = newValue
        }
    }
    /// Full Drive (not `drive.file`): a TC engineer writes into the company account's center folder, which `drive.file`
    /// can't see since another account made it. Accounts signed in before ask again (`hasFullDrive`).
    public static let scope = "openid email profile https://www.googleapis.com/auth/drive"
    static let fullDrive = "https://www.googleapis.com/auth/drive"
    private static let grantedKey = "solarSurvey.googleScope"

    /// Google granted full Drive to the signed-in account (from the last token's `scope`). False for an account
    /// signed in under `drive.file`: it uploads to its own Drive until it signs in again.
    public var hasFullDrive: Bool {
        (UserDefaults.standard.string(forKey: Self.grantedKey) ?? "").split(separator: " ").contains { $0 == Self.fullDrive }
    }

    private let tokens: OAuthTokenSession
    private var authorization: OAuthBrowserAuthorization?

    public init(clientID: String) {
        tokens = OAuthTokenSession(clientID: clientID.trimmingCharacters(in: .whitespaces),
            readRefresh: { Keychain.read("google.refresh") }, onTokens: { token in
                if let refresh = token.refresh_token { Keychain.write("google.refresh", refresh) }
                if let id = token.id_token { Self.remember(idToken: id) }
                if let scope = token.scope { UserDefaults.standard.set(scope, forKey: Self.grantedKey) }
            }, onSignOut: {
                Keychain.delete("google.refresh")
                UserDefaults.standard.removeObject(forKey: "solarSurvey.googleEmail")
                UserDefaults.standard.removeObject(forKey: "solarSurvey.googleName")
                UserDefaults.standard.removeObject(forKey: Self.grantedKey)
            })
        super.init()
    }

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

    public func signIn() async throws {
        guard clientID.hasSuffix(".apps.googleusercontent.com") else { throw Failure.noClientID }
        let ticket = tokens.beginSignIn()
        authorization?.cancel()
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [.init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI),
                        .init(name: "response_type", value: "code"), .init(name: "scope", value: Self.scope),
                        .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                        .init(name: "prompt", value: "select_account consent"), .init(name: "access_type", value: "offline")]
        let browser = OAuthBrowserAuthorization { [weak self] completion in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: self?.redirectScheme) { url, err in
                if let url { completion(.success(url)) }
                else if let e = err as? ASWebAuthenticationSessionError, e.code == .canceledLogin { completion(.failure(Failure.cancelled)) }
                else { completion(.failure(err ?? Failure.cancelled)) }
            }
            s.presentationContextProvider = self
            // A shared iPad: do not offer the previous person's Safari account.
            s.prefersEphemeralWebBrowserSession = true
            return s
        }
        authorization = browser
        defer {
            if authorization === browser { authorization = nil }
            tokens.cancelSignIn(ticket)
        }
        let callback = try await browser.value()
        try tokens.validate(ticket)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw Failure.badResponse("ไม่มีรหัสยืนยัน")
        }
        try await tokens.exchangeCode(code, verifier: verifier, redirectURI: redirectURI, ticket: ticket)
    }

    /// Keeps the email and name from an OpenID token.
    private static func remember(idToken: String) {
        let c = Self.claims(fromIDToken: idToken)
        if let mail = c?["email"] as? String { UserDefaults.standard.set(mail, forKey: "solarSurvey.googleEmail") }
        if let n = (c?["name"] as? String)?.trimmingCharacters(in: .whitespaces), !n.isEmpty { UserDefaults.standard.set(n, forKey: "solarSurvey.googleName") }
    }

    public func signOut() {
        tokens.signOut()
        authorization?.cancel()
        authorization = nil
    }

    public func accessToken() async throws -> String { try await tokens.accessToken() }

    public func accessToken(validFor seconds: TimeInterval) async throws -> String {
        try await tokens.accessToken(validFor: seconds)
    }

    public func idAndAccessToken() async throws -> (idToken: String, accessToken: String) {
        try await tokens.idAndAccessToken()
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

extension ASWebAuthenticationSession: OAuthBrowserSession {}

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
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
