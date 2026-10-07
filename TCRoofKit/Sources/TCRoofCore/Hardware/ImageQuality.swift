import Foundation

/// Quick checks on a photo right after it is taken (docs/specs/hardware-assist-swift.md §H4): blur and darkness,
/// measured on a small grey copy (about 512 px on the long side). Plain loops, so the tests run anywhere.
public struct ImageQuality: Equatable, Sendable {
    /// Mean luminance, 0…1.
    public let brightness: Double
    /// Variance of the 4-neighbour Laplacian over the grey values (0…255): low means few sharp edges.
    public let sharpness: Double

    public enum Issue: String, Sendable, CaseIterable {
        case blurry, dark, tilted

        public var message: String {
            switch self {
            case .blurry: return "ภาพไม่ชัด ถ่ายใหม่?"
            case .dark: return "มืดเกินไป ถ่ายใหม่โดยเปิดแฟลช?"
            case .tilted: return "ภาพเอียง ถ่ายใหม่?"
            }
        }
    }

    /// Roll beyond which a square-on photo (`PhotoShot.straight`) counts as tilted, in degrees.
    public static let tiltLimit = 12.0

    /// How far the device is rolled off the nearest upright or sideways position, 0…45°, from `deviceMotion.gravity`.
    /// nil when the camera points steeply up or down (under 0.5 g in the screen plane), where roll means nothing.
    public static func tilt(gx: Double, gy: Double) -> Double? {
        guard (gx * gx + gy * gy).squareRoot() >= 0.5 else { return nil }
        let angle = atan2(gx, -gy) * 180 / .pi
        return abs(remainder(angle, 90))
    }

    /// Below this mean luminance a photo is too dark to read.
    public static let darkLimit = 0.18
    /// Laplacian variance below which a photo counts as blurred. A starting value: tune it on the team's photos.
    public static let blurLimit = 40.0

    public var issues: [Issue] {
        var out: [Issue] = []
        if sharpness < Self.blurLimit { out.append(.blurry) }
        if brightness < Self.darkLimit { out.append(.dark) }
        return out
    }

    /// `grey` holds `width × height` luminance values row by row.
    public init?(grey: [UInt8], width: Int, height: Int) {
        guard width >= 3, height >= 3, grey.count >= width * height else { return nil }
        var sum = 0
        for v in grey.prefix(width * height) { sum += Int(v) }
        brightness = Double(sum) / Double(width * height) / 255

        var n = 0.0, mean = 0.0, m2 = 0.0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let i = row + x
                let lap = Double(Int(grey[i - 1]) + Int(grey[i + 1]) + Int(grey[i - width]) + Int(grey[i + width]) - 4 * Int(grey[i]))
                n += 1
                let d = lap - mean
                mean += d / n
                m2 += d * (lap - mean)
            }
        }
        sharpness = n > 0 ? m2 / n : 0
    }
}

/// How a photo field should be shot (§H4): square-on (nameplates, breakers, meters, bills), a wide view, or either.
public enum PhotoShot: Sendable {
    case any, straight, wide

    /// The shot for a schema photo field id ("tr0_plate", "photoBreaker" …).
    public static func of(_ field: String) -> PhotoShot {
        let key = field.split(separator: "_").last.map(String.init) ?? field
        if field.contains("_") ? ["plate", "mdbBreaker"].contains(key) : straightFields.contains(field) { return .straight }
        if field.contains("_") ? key == "wide" : wideFields.contains(field) { return .wide }
        return .any
    }

    static let straightFields: Set<String> = ["meterPic", "photoBreaker", "photoRating", "breakerPhoto", "meterPhoto", "billPhoto"]
    static let wideFields: Set<String> = ["photoWide", "underRoofPhoto"]
}
