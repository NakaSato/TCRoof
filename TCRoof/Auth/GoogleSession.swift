import Foundation
import Observation
import TCRoofUI

/// App sign-in with a Google account. The same account receives project files on Google Drive
@MainActor
@Observable
final class GoogleSession {
    /// Signed-in account; nil shows the login page. Empty when Google didn't return an email.
    private(set) var email: String?

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
        // the survey module's own sign-out buttons end the app session too
        SurveyModel.shared.signOutHandler = { [weak self] in self?.signOut() }
        #if DEBUG
        // `-screen <name>` skips sign-in for simulator checks; `-screen login` shows the login page.
        if let screen = UserDefaults.standard.string(forKey: "screen") {
            email = screen == "login" ? nil : "demo@survey.co.th"
        }
        #endif
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

    func signIn() async throws {
        try await survey.google.signIn()
        email = survey.google.email ?? ""
        Self.fillUserName()
    }

    func signOut() {
        CloudSync.shared.stop()
        survey.google.signOut()
        email = nil
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
