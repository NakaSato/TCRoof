import Foundation
import Observation
import FirebaseAuth
import TCRoofCore
import TCRoofUI

/// App sign-in with a Google account. The same account receives project files on Google Drive
@MainActor
@Observable
final class GoogleSession {
    /// Signed-in account; nil shows the login page. Empty when Google didn't return an email.
    private(set) var email: String?
    /// Why the app signed out by itself (removed from the member list), for the login page.
    var notice: String?

    /// Sign-in refused: only accounts the developer lists under `members/` in Firebase may use the app.
    enum Denied: Error, LocalizedError {
        case notMember(String), suspended, offline, noEmail
        var errorDescription: String? {
            switch self {
            case .notMember(let email): return "\(email) ยังไม่ได้รับสิทธิ์ใช้แอปนี้ ติดต่อผู้ดูแลระบบให้เพิ่มบัญชีในรายชื่อสมาชิก"
            case .suspended: return "บัญชีนี้ถูกระงับ | ติดต่อผู้ดูแลระบบ"
            case .offline: return "ต่ออินเทอร์เน็ตเพื่อตรวจสิทธิ์บัญชีในการเข้าสู่ระบบครั้งแรก"
            case .noEmail: return "Google ไม่ได้ส่งอีเมลของบัญชีมา ลองเข้าสู่ระบบอีกครั้ง"
            }
        }
    }

    var survey: SurveyModel { SurveyModel.shared }

    /// TCRoof's OAuth client (type iOS, bundle com.tcroof.internal). Client IDs of installed apps are public, not secrets.
    static let defaultClientID = "926127001416-cam8rjtsgrkugh8r76o2m3s7tkj696ud.apps.googleusercontent.com"
    /// Clients deleted in Google Cloud; a saved copy is swapped for the current default.
    private static let retiredClientIDs: Set = ["926127001416-p5fg8u0eehad4258nlsgi862ladt6g1s.apps.googleusercontent.com"]

    init() {
        let saved = SurveyModel.shared.settings.googleClientID
        if !saved.hasSuffix(".apps.googleusercontent.com") || Self.retiredClientIDs.contains(saved) {
            SurveyModel.shared.settings.googleClientID = Self.defaultClientID
            SurveyModel.shared.google.clientID = Self.defaultClientID
        }
        let google = SurveyModel.shared.google
        email = google.isSignedIn ? (google.email ?? "") : nil
        if google.isSignedIn { Self.fillUserName() }
        if let email, !email.isEmpty { LocalData.adopt(Permissions.normalized(email)) }
        // the survey module's own sign-out buttons end the app session too
        SurveyModel.shared.signOutHandler = { [weak self] in self?.signOut() }
        // taken off the member list, or suspended by a Maintainer: out at the next sync
        MemberRole.shared.onRemoved = { [weak self] suspended in
            guard let self, let email = self.email else { return }
            self.signOut()
            self.notice = (suspended ? Denied.suspended : Denied.notMember(email)).localizedDescription
        }
        #if DEBUG
        // `-screen <name>` skips sign-in for simulator checks; `-screen login` shows the login page.
        if let screen = UserDefaults.standard.string(forKey: "screen") {
            email = screen == "login" ? nil : (UserDefaults.standard.string(forKey: "roleEmail") ?? (MemberRole.override != nil ? "uitest@tcroof.test" : "demo@survey.co.th"))
        }
        #endif
        if let email { MemberRole.shared.signedIn(email) }
        MySignature.shared.account = email
    }

    var isSignedIn: Bool { email != nil }

    /// OAuth client ID of type iOS from Google Cloud Console (also editable in the survey module's settings).
    var clientID: String {
        get { survey.settings.googleClientID }
        set {
            let id = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            survey.settings.googleClientID = id
            survey.google.clientID = id
        }
    }

    var hasValidClientID: Bool { clientID.hasSuffix(".apps.googleusercontent.com") }

    /// Google sign-in, then the member list: an account the developer hasn't added is signed out again. Offline, only
    /// an account this device has seen on the list gets in.
    func signIn() async throws {
        notice = nil
        try await survey.google.signIn()
        let mail = Permissions.normalized(survey.google.email ?? "")
        do {
            guard !mail.isEmpty else { throw Denied.noEmail }
            switch await Self.membership(of: mail, google: survey.google) {
            case .member: break
            case .notMember: throw Denied.notMember(mail)
            case .suspended: throw Denied.suspended
            case .unknown: guard MemberRole.wasConfirmed(mail) else { throw Denied.offline }
            }
        } catch {
            survey.google.signOut()
            try? Auth.auth().signOut()
            throw error
        }
        LocalData.signedIn(mail, role: MemberRole.savedRole(mail))
        email = mail
        MySignature.shared.account = mail
        MemberRole.shared.signedIn(mail)
        Self.fillUserName()
    }

    private static func membership(of email: String, google: GoogleAuth) async -> MemberRole.Membership {
        guard (try? await firebaseUser(google)) != nil else { return .unknown }
        return await MemberRole.shared.membership(of: email)
    }

    /// Firebase account of the Google account signed in to the app; firestore.rules check its verified email.
    static func firebaseUser(_ google: GoogleAuth) async throws -> User {
        let email = google.email
        if let user = Auth.auth().currentUser, email == nil || email == "" || user.email?.lowercased() == email?.lowercased() { return user }
        let tokens = try await google.idAndAccessToken()
        fillUserName() // the fresh token may carry the account's name
        let credential = GoogleAuthProvider.credential(withIDToken: tokens.idToken, accessToken: tokens.accessToken)
        return try await Auth.auth().signIn(with: credential).user
    }

    func signOut() {
        CloudSync.shared.stop()
        survey.google.signOut()
        email = nil
        MySignature.shared.account = nil
        MemberRole.shared.signedOut()
        // the display name belongs to the account; the next person signs in with their own
        UserDefaults.standard.removeObject(forKey: Self.userNameKey)
        UserDefaults.standard.removeObject(forKey: Self.userNameAutoKey)
    }

    static let userNameKey = "userName"
    private static let userNameAutoKey = "userNameFromAccount"

    /// Signs ICLs, install logs, scans and surveys with the Google account's name (or the part of the email before @)
    /// unless the user typed their own. Replaces the old "สมชาย" placeholder left by earlier versions.
    static func fillUserName() {
        let d = UserDefaults.standard, google = SurveyModel.shared.google
        let current = d.string(forKey: userNameKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard current.isEmpty || current == "สมชาย" || d.bool(forKey: userNameAutoKey) else { return }
        let fromEmail = google.email.flatMap { $0.split(separator: "@").first.map(String.init) }
        guard let name = google.name ?? fromEmail, !name.isEmpty, name != current else { return }
        d.set(name, forKey: userNameKey)
        d.set(true, forKey: userNameAutoKey)
    }

    /// The user typed a name in Settings — keep it from now on.
    static func userNameEdited() { UserDefaults.standard.set(false, forKey: userNameAutoKey) }
}
