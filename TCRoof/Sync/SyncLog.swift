import os

/// Sync's and Drive's log, in place of `print` (CHA-60). Interpolated strings are private by default, so an email or an
/// id is redacted outside a debugger; counts and times stay readable.
enum SyncLog {
    static let sync = Logger(subsystem: "com.tcroof.internal", category: "sync")
    static let photos = Logger(subsystem: "com.tcroof.internal", category: "photos")
    static let drive = Logger(subsystem: "com.tcroof.internal", category: "drive")
}
