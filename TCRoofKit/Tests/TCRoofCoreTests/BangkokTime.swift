import Foundation

/// The tests are written in Bangkok time, the app's own (`FeedBuilder.calendar`, `MasterSchedule.calendar`). Code that
/// reads the device's local time (`ISODate`, the notifications' `HH:mm`, `Calendar.current`) would otherwise follow the
/// Mac's time zone and fail elsewhere (CHA-54). Set the default time zone, which existing formatters and new calendars
/// follow, from the `setUp` of a test case that touches local time; the Linux script sets `TZ` the same way.
enum BangkokTime {
    static let zone = TimeZone(identifier: "Asia/Bangkok")!

    static func pin() {
        if NSTimeZone.default != zone { NSTimeZone.default = zone }
    }
}
