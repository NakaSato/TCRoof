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
    /// Bumped when the signed-in account's local records must be prepared again (its role made external): the app
    /// tears its screens down and runs the account's activation, the removal included, before showing them.
    private(set) var activation = 0
    /// The Drive access this account's role needs and its token doesn't hold (CHA-41), asked on the home
    /// (`DriveAccessAlert`): full Drive for a TC engineer, the narrower contractor access in place of full Drive.
    var driveAccessNeeded: GoogleAuth.DriveAccess?
    /// Why asking for it failed, shown once.
    var driveAccessError: String?
    /// "ภายหลัง" this launch: not asked again until the next one.
    private var driveAccessPostponed = false

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

    private static let operations = SessionOperationGate()

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
        let restoredEmail = Permissions.normalized(google.email ?? "")
        // A refresh token alone does not establish membership after an interrupted first sign-in.
        email = google.isSignedIn && !restoredEmail.isEmpty && MemberRole.wasConfirmed(restoredEmail) ? restoredEmail : nil
        if let email {
            Self.fillUserName()
            LocalData.signedIn(email, role: MemberRole.savedRole(email))
        }
        // the survey module's own sign-out buttons end the app session too
        SurveyModel.shared.signOutHandler = { [weak self] in self?.signOut() }
        // taken off the member list, or suspended by a Maintainer: out at the next sync
        MemberRole.shared.onRemoved = { [weak self] suspended in
            guard let self, let email = self.email else { return }
            self.signOut()
            self.notice = (suspended ? Denied.suspended : Denied.notMember(email)).localizedDescription
        }
        // a manager changed this account's role at the next sync: made external, the team's records synced here go
        // (`LocalData`) before the app shows anything again, then sync brings back only the account's own jobs
        MemberRole.shared.onRoleChanged = { [weak self] email, role in
            guard let self, self.email == email else { return }
            LocalData.signedIn(email, role: role)
            guard LocalData.needsCleanup else { return }
            CloudSync.shared.stop()
            self.activation += 1
        }
        // a contractor still holding full Drive from before (or a member made external) is asked to narrow it
        MemberRole.shared.onConfirmed = { [weak self] in self?.checkDriveAccess(afterSignIn: false) }
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
            if id != survey.google.clientID { Self.operations.invalidate() }
            survey.settings.googleClientID = id
            survey.google.clientID = id
        }
    }

    var hasValidClientID: Bool { clientID.hasSuffix(".apps.googleusercontent.com") }

    /// Google sign-in, then the member list: an account the developer hasn't added is signed out again. Offline, only
    /// an account this device has seen on the list gets in.
    func signIn() async throws {
        // Programmatic account switching must stop the old listeners and UI before OAuth starts.
        signOut()
        let ticket = Self.operations.invalidate()
        notice = nil
        do {
            try await survey.google.signIn()
            try Self.operations.validate(ticket)
            let mail = Permissions.normalized(survey.google.email ?? "")
            guard !mail.isEmpty else { throw Denied.noEmail }
            let membership = try await Self.membership(of: mail, google: survey.google)
            try Self.operations.validate(ticket)
            switch membership {
            case .member: break
            case .notMember: throw Denied.notMember(mail)
            case .suspended: throw Denied.suspended
            case .unknown: guard MemberRole.wasConfirmed(mail) else { throw Denied.offline }
            }
            LocalData.signedIn(mail, role: MemberRole.savedRole(mail))
            email = mail
            MySignature.shared.account = mail
            MemberRole.shared.signedIn(mail)
            Self.fillUserName()
            checkDriveAccess(afterSignIn: true)
        } catch {
            // An older request must never clear a newer account's credentials.
            if Self.operations.generation == ticket {
                Self.operations.invalidate()
                survey.google.signOut()
                try? Auth.auth().signOut()
            }
            throw error
        }
    }

    private static func membership(of email: String, google: GoogleAuth) async throws -> MemberRole.Membership {
        do { _ = try await firebaseUser(google) }
        catch is CancellationError { throw CancellationError() }
        // Surface Firebase authentication failures. Treating these as a membership lookup outage made
        // first-time users see the generic "offline" message even when OAuth/Firebase rejected the login.
        catch { throw error }
        return await MemberRole.shared.membership(of: email)
    }

    /// Firebase has process-wide mutable auth state. Drain stale SDK completions before signing in another account.
    static func firebaseUser(_ google: GoogleAuth) async throws -> User {
        let ticket = operations.generation
        let email = google.email
        let clientID = google.clientID
        return try await operations.run(ticket: ticket, operation: {
            guard google.email == email, google.clientID == clientID, google.isSignedIn else {
                throw CancellationError()
            }
            if let user = Auth.auth().currentUser, let email, !email.isEmpty,
               user.email?.lowercased() == email.lowercased() { return user }
            let tokens = try await google.idAndAccessToken()
            try operations.validate(ticket)
            guard google.email == email, google.clientID == clientID else { throw CancellationError() }
            let credential = GoogleAuthProvider.credential(withIDToken: tokens.idToken, accessToken: tokens.accessToken)
            let user = try await Auth.auth().signIn(with: credential).user
            guard google.email == email, google.clientID == clientID, google.isSignedIn else {
                try? Auth.auth().signOut()
                throw CancellationError()
            }
            return user
        }, discard: { _ in
            // The gate guarantees a newer Firebase sign-in has not started yet.
            try? Auth.auth().signOut()
        })
    }

    /// Whether the token's Drive access matches the role (CHA-41). Sign-in asks for the contractor's access; a TC
    /// engineer is asked for full Drive right after (later from the job screen, `askFullDrive`), and a contractor
    /// holding full Drive from an older sign-in is asked to give it up whenever the role is confirmed.
    func checkDriveAccess(afterSignIn: Bool) {
        guard isSignedIn, survey.google.isSignedIn, !driveAccessPostponed || afterSignIn else { return }
        let google = survey.google
        if MemberRole.shared.permissions.role == .external {
            driveAccessNeeded = google.hasContractorDrive ? nil : .contractor
        } else if afterSignIn, !google.hasFullDrive {
            driveAccessNeeded = .full
        }
    }

    /// The job screen's `อนุญาต Drive กลาง`, for a TC engineer still on their own Drive.
    func askFullDrive() { driveAccessNeeded = .full }

    func postponeDriveAccess() {
        driveAccessNeeded = nil
        driveAccessPostponed = true
    }

    /// Asks Google again for the needed access, for the same account. Cancelled, it keeps the token it had.
    func grantDriveAccess() async {
        guard let access = driveAccessNeeded else { return }
        driveAccessNeeded = nil
        let account = email
        do {
            try await survey.google.requestDrive(access)
        } catch GoogleAuth.Failure.cancelled {
            driveAccessPostponed = true
        } catch is CancellationError {
        } catch {
            guard account == email else { return }
            driveAccessError = error.localizedDescription
        }
    }

    func signOut() {
        Self.operations.invalidate()
        CloudSync.shared.stop()
        survey.google.signOut()
        email = nil
        driveAccessNeeded = nil
        driveAccessPostponed = false
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
