import Foundation

/// What the app holds back on a long day outdoors (docs/specs/hardware-assist-swift.md §H8), from the device's state.
public struct PowerAdvice: Equatable, Sendable {
    public enum Heat: Int, Sendable, Comparable {
        case nominal, fair, serious, critical
        public static func < (a: Heat, b: Heat) -> Bool { a.rawValue < b.rawValue }
    }

    public struct State: Equatable, Sendable {
        public var heat: Heat = .nominal
        /// 0…1, or nil when unknown (simulator, battery monitoring off).
        public var battery: Double?
        public var charging = false
        public var lowPowerMode = false
        public var onWiFi = true
        /// Free space for important data, in bytes; nil when unknown.
        public var freeBytes: Int64?
        public init(heat: Heat = .nominal, battery: Double? = nil, charging: Bool = false, lowPowerMode: Bool = false,
                    onWiFi: Bool = true, freeBytes: Int64? = nil) {
            self.heat = heat; self.battery = battery; self.charging = charging; self.lowPowerMode = lowPowerMode
            self.onWiFi = onWiFi; self.freeBytes = freeBytes
        }
    }

    public static let lowBattery = 0.20
    public static let lowStorage: Int64 = 2_000_000_000

    /// Hot: map pictures are not fetched (the camera stays available).
    public let hot: Bool
    /// Low battery or Low Power Mode, not charging and not on Wi-Fi: Drive uploads wait.
    public let holdUploads: Bool
    public let lowBattery: Bool
    public let lowStorage: Bool

    public init(_ s: State) {
        hot = s.heat >= .serious
        lowBattery = s.lowPowerMode || (s.battery.map { $0 < Self.lowBattery } ?? false)
        holdUploads = lowBattery && !s.charging && !s.onWiFi
        lowStorage = s.freeBytes.map { $0 < Self.lowStorage } ?? false
    }

    /// Lines for the banner, most urgent first; empty when all is well.
    public var notes: [String] {
        var out: [String] = []
        if hot { out.append("เครื่องร้อน พักในที่ร่ม · หยุดโหลดแผนที่ชั่วคราว") }
        if lowStorage { out.append("พื้นที่ในเครื่องเหลือน้อยกว่า 2 GB · ย้ายงานที่ส่งแล้วขึ้น Drive") }
        if holdUploads { out.append("แบตเตอรี่ต่ำ · รออัปโหลดรูปเมื่อชาร์จหรือต่อ Wi-Fi") }
        else if lowBattery { out.append("แบตเตอรี่ต่ำ") }
        return out
    }
}
