import Foundation

/// ถ่ายต่อกัน 3 ภาพ for wide rooms on a camera without an ultra-wide lens (docs/specs/hardware-assist-swift.md §H4.3):
/// left → centre → right with 30 % overlap. The gyroscope's turn about the vertical is added up after the first shot
/// and says when the next one lines up.
public struct PanoramaGuide: Sendable {
    public static let shots = 3
    public static let overlap = 0.3
    /// How close to the next position, in degrees, counts as lined up.
    public static let tolerance = 3.0
    static let names = ["ซ้าย", "กลาง", "ขวา"]

    /// Degrees to turn between shots.
    public let step: Double
    /// Degrees turned to the right since the first shot.
    public private(set) var turned = 0.0
    public private(set) var taken = 0

    public init(horizontalFOV: Double) { step = horizontalFOV * (1 - Self.overlap) }

    /// The camera's horizontal field of view, from the format's (landscape) field of view and how the device is held.
    public static func horizontalFOV(sensorFOV: Double, portrait: Bool, aspect: Double = 4.0 / 3) -> Double {
        guard portrait else { return sensorFOV }
        return 2 * atan(tan(sensorFOV / 2 * .pi / 180) / aspect) * 180 / .pi
    }

    /// Adds one motion sample: `rate` (rad/s) and `gravity` (g) in device axes, as CoreMotion gives them. Turning
    /// clockwise seen from above (to the right) is the rotation rate along gravity.
    public mutating func turn(rate: SIMD3<Double>, gravity: SIMD3<Double>, dt: Double) {
        let g = (gravity * gravity).sum().squareRoot()
        guard taken > 0, !done, g > 0.1 else { return }
        turned += (rate * gravity).sum() / g * dt * 180 / .pi
    }

    /// Where the next shot should be, in degrees right of the first.
    public var target: Double { Double(taken) * step }
    /// + when turned past the next position.
    public var offset: Double { turned - target }
    public var ready: Bool { !done && (taken == 0 || abs(offset) <= Self.tolerance) }
    public var done: Bool { taken >= Self.shots }

    public mutating func shot() {
        guard !done else { return }
        if taken == 0 { turned = 0 }
        taken += 1
    }

    /// The line on the camera: which shot, and which way to turn.
    public var cue: String {
        if done { return "ครบ 3 ภาพ" }
        let name = "ภาพ\(Self.names[taken]) (\(taken + 1)/\(Self.shots))"
        if taken == 0 { return "เริ่มจากด้านซ้ายของห้อง แล้วถ่าย" + name }
        if ready { return "ตรงแล้ว ถ่าย" + name }
        let left = Int(abs(offset).rounded())
        return offset < 0 ? "หมุนไปทางขวาอีก \(left)° เพื่อถ่าย" + name : "เลยมา \(left)° หมุนกลับทางซ้าย"
    }
}
