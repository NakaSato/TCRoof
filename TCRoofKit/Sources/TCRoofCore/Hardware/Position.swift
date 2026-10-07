import Foundation

/// How good this device's location is (docs/specs/hardware-assist-swift.md §H2): Wi-Fi iPads have no GPS and get a
/// position from nearby networks, often hundreds of metres off.
public enum GPSGrade: String, Codable, Sendable {
    /// No fix taken yet on this device.
    case unknown
    /// A satellite fix: within 20 m.
    case gps
    /// Usable but rough: 20–50 m.
    case rough
    /// Worse than 50 m: a network estimate, typical of a Wi-Fi iPad.
    case approximate

    public static let gpsLimit = 20.0
    public static let warnLimit = 50.0

    public init(accuracy: Double) {
        if accuracy < 0 { self = .unknown }
        else if accuracy <= Self.gpsLimit { self = .gps }
        else if accuracy <= Self.warnLimit { self = .rough }
        else { self = .approximate }
    }

    /// The line under the coordinates once a fix is written: "ความแม่นยำ ± 8 ม.", or the warning past 50 m.
    public static func note(accuracy: Double) -> String {
        let m = Int(accuracy.rounded())
        return GPSGrade(accuracy: accuracy) == .approximate
            ? "ความแม่นยำ ± \(m) ม. (เครื่องไม่มี GPS) · ตรวจในแผนที่ หรือวางลิงก์ Google Maps แทน"
            : "ความแม่นยำ ± \(m) ม."
    }

    /// Settings › เครื่องนี้.
    public var settingsDetail: String {
        switch self {
        case .unknown: return "ตรวจเมื่อกดตำแหน่งปัจจุบันครั้งแรก"
        case .gps: return "GPS ในเครื่อง"
        case .rough: return "ความแม่นยำปานกลาง"
        case .approximate: return "ประมาณการ (ไม่มี GPS) · แนะนำเครื่องรับ GNSS บลูทูธ"
        }
    }
}
