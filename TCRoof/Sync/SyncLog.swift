import os

/// Sync's and Drive's log, in place of `print` (CHA-60). Interpolated strings are private by default, so an email or an
/// id is redacted outside a debugger; counts and times stay readable.
enum SyncLog {
    static let sync = Logger(subsystem: "com.tcroof.internal", category: "sync")
    static let photos = Logger(subsystem: "com.tcroof.internal", category: "photos")
    static let drive = Logger(subsystem: "com.tcroof.internal", category: "drive")
    /// Sync start-up timings for Instruments (CHA-57): the whole start, each collection's stage, each page of projects
    /// and each save of received records. Record with the `os_signpost` / Points of Interest instruments.
    static let signposts = OSSignposter(subsystem: "com.tcroof.internal", category: .pointsOfInterest)
}
