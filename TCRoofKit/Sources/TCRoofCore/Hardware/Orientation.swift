import Foundation

/// Roof pitch and facing from the iPad lying on the roof sheet (docs/specs/hardware-assist-swift.md §H3).
/// Gravity is in device axes as Core Motion gives it: x to the right of the screen, y to its top, z out of the screen,
/// in g. Lying face up on a slope, gravity's part along the screen points down the slope.
public enum Orientation {
    /// Pitch of the surface the iPad lies on, in degrees: gravity (0, −0.259, −0.966) is 15°.
    public static func tilt(gx: Double, gy: Double, gz: Double) -> Double {
        atan2((gx * gx + gy * gy).squareRoot(), abs(gz)) * 180 / .pi
    }

    /// Downhill direction on the screen, clockwise from the iPad's top edge, 0–360°:
    /// 180° when the top edge points up the slope.
    public static func downhill(gx: Double, gy: Double) -> Double {
        normalised(atan2(gx, gy) * 180 / .pi)
    }

    /// Compass direction the slope (and the panels on it) faces: the heading of the iPad's top edge plus the downhill
    /// direction on the screen.
    public static func facing(heading: Double, gx: Double, gy: Double) -> Double {
        normalised(heading + downhill(gx: gx, gy: gy))
    }

    /// Below this pitch the downhill direction is noise and no facing is given.
    public static let minimumTiltForFacing = 2.0

    /// A reading is steady when the last second of pitch samples varies by under 0.3° (standard deviation).
    public static func isSteady(_ samples: [Double], limit: Double = 0.3) -> Bool {
        guard samples.count >= 10 else { return false }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count)
        return variance.squareRoot() < limit
    }

    /// Compass headings worse than this are flagged "ตรวจทิศอีกครั้ง (ใกล้โลหะ)".
    public static let headingAccuracyLimit = 15.0

    /// Directions the form names (`Options.facing`), by their compass bearing.
    static let named: [(name: String, bearing: Double)] = [
        ("เหนือ", 0), ("ตะวันออกเฉียงเหนือ", 45), ("ตะวันออก", 90), ("ใต้", 180), ("ตะวันตกเฉียงใต้", 225), ("ตะวันตก", 270),
    ]
    /// Thai names of the eight directions, for the อื่นๆ text and the live readout.
    static let eight = ["เหนือ", "ตะวันออกเฉียงเหนือ", "ตะวันออก", "ตะวันออกเฉียงใต้", "ใต้", "ตะวันตกเฉียงใต้", "ตะวันตก", "ตะวันตกเฉียงเหนือ"]

    /// "ใต้ 195°": the nearest of the eight directions and the bearing.
    public static func describe(_ bearing: Double) -> String {
        let b = normalised(bearing)
        return "\(eight[Int((b / 45).rounded()) % 8]) \(Int(b.rounded()) % 360)°"
    }

    /// The facing answer for a bearing: one of the form's directions when it is the nearest of the eight (within 22.5°),
    /// otherwise อื่นๆ with the direction written out ("ตะวันออกเฉียงใต้ 135°").
    public static func facingChoice(_ bearing: Double) -> (choice: String, other: String) {
        let b = normalised(bearing)
        let nearest = eight[Int((b / 45).rounded()) % 8]
        if named.contains(where: { $0.name == nearest }) { return (nearest, "") }
        return ("อื่นๆ", describe(b))
    }

    static func normalised(_ d: Double) -> Double {
        let r = d.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
