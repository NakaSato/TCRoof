import Foundation

/// Which builds may still sync. The rules and the console switches change what Firestore accepts, and a device on an
/// older build keeps writing what it always did: refused writes leave its sync stuck, and accepted ones undo the change
/// (a job sent with its contacts after `contactsSplit`). `config/app.minSyncVersion`, set in the Firebase console,
/// stops such a build: it shows `ต้องอัปเดตแอป` and pushes nothing until it is updated, while its edits stay on the
/// device for the new build to send.
///
/// The number is not the App Store version (the project keeps 1.0 / build 1, and builds made in Xcode would be stopped
/// too). Raise `syncVersion` in a change that needs every device to run it before its rules or switch go live, then
/// set `minSyncVersion` to it once that build is out.
public enum AppCompat {
    /// What this build writes. 1: the roles (per-job daily signing, the IEC hand-over, `jobContacts`, the team directory).
    /// 2: the Maintainer, suspended accounts (signed out at the next sync) and the role overrides (`config/roleOverrides`),
    /// which builds before it read as the internal team, keep signed in, and ignore.
    /// 3: contractors send the weekly request R1 (`weeklyRequests` signed `weeklyRequestsBy`, `WeeklyRequest.sentAt`).
    /// Builds before it drop `sentAt` when they save a request and take a contractor's change to a sent or approved
    /// week as it comes (`WeeklyRequest.trusting`).
    public static let syncVersion = 3

    /// A build is outdated when the console asks for more than it has; no minimum (or a bad one) stops nothing.
    public static func isOutdated(minimum: Int?, current: Int = syncVersion) -> Bool {
        guard let minimum, minimum > 0 else { return false }
        return current < minimum
    }
}
