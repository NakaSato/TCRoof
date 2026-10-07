#if canImport(UIKit)
import UIKit
import CoreLocation
import CoreMotion
import ImageIO
import UniformTypeIdentifiers
import TCRoofCore

/// Position, compass and tilt while the survey camera is open, read when a photo comes back (hardware assist §H4).
/// Location is used only when already allowed; the camera never asks for it.
@MainActor
final class CaptureContext: NSObject, CLLocationManagerDelegate {
    private let location = CLLocationManager()
    private let motion = CMMotionManager()
    private var heading: Double?

    func start() {
        location.delegate = self
        let s = location.authorizationStatus
        if s == .authorizedWhenInUse || s == .authorizedAlways {
            location.desiredAccuracy = kCLLocationAccuracyBest
            location.startUpdatingLocation()
        }
        if CLLocationManager.headingAvailable() { location.startUpdatingHeading() }
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.2
            motion.startDeviceMotionUpdates()
        }
    }

    func stop() {
        location.stopUpdatingLocation()
        location.stopUpdatingHeading()
        motion.stopDeviceMotionUpdates()
    }

    /// What the sensors say now; a fix older than two minutes is left out.
    func snapshot() -> PhotoStamp {
        var s = PhotoStamp(device: Self.model)
        if let l = location.location, l.horizontalAccuracy >= 0, -l.timestamp.timeIntervalSinceNow < 120 {
            s.lat = l.coordinate.latitude; s.lon = l.coordinate.longitude; s.accuracy = l.horizontalAccuracy
        }
        s.heading = heading
        if let g = motion.deviceMotion?.gravity { s.pitch = Orientation.cameraPitch(gz: g.z) }
        return s
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let v = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        MainActor.assumeIsolated { heading = v }
    }

    /// "iPad14,8".
    static let model: String = {
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }()

    /// JPEG with the stamp in its EXIF / GPS dictionaries, so Drive and other apps see where and which way it was taken.
    /// A camera original keeps its orientation as the EXIF flag.
    nonisolated static func jpeg(_ image: UIImage, quality: CGFloat, stamp: PhotoStamp, taken: Date) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        var gps: [CFString: Any] = [:]
        if let lat = stamp.lat, let lon = stamp.lon {
            gps[kCGImagePropertyGPSLatitude] = abs(lat); gps[kCGImagePropertyGPSLatitudeRef] = lat >= 0 ? "N" : "S"
            gps[kCGImagePropertyGPSLongitude] = abs(lon); gps[kCGImagePropertyGPSLongitudeRef] = lon >= 0 ? "E" : "W"
            if let a = stamp.accuracy { gps[kCGImagePropertyGPSHPositioningError] = a }
        }
        if let h = stamp.heading { gps[kCGImagePropertyGPSImgDirection] = h; gps[kCGImagePropertyGPSImgDirectionRef] = "T" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality,
                                      kCGImagePropertyOrientation: CGImagePropertyOrientation(image.imageOrientation).rawValue,
                                      kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: f.string(from: taken)],
                                      kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: stamp.device ?? "", kCGImagePropertyTIFFMake: "Apple"]]
        if !gps.isEmpty { props[kCGImagePropertyGPSDictionary] = gps }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
#endif
