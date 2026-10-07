#if canImport(UIKit)
import SwiftUI
import Photos
import CoreLocation
import TCRoofCore

/// Every photo taken with the app's camera also goes to the device's photo library, full size, with where and which
/// way it was taken, so the shot stays on the iPhone / iPad outside the app. On unless turned off in Settings.
public enum CameraRoll {
    public static let defaultsKey = "photos.saveToLibrary"
    public static var isOn: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }

    /// Saves in the background; the first time asks for add-only access, and a refusal is left alone.
    public static func save(_ image: UIImage, stamp: PhotoStamp, taken: Date) {
        guard isOn else { return }
        Task.detached(priority: .utility) {
            let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard access == .authorized || access == .limited,
                  let data = CaptureContext.jpeg(image, quality: 0.9, stamp: stamp, taken: taken) else { return }
            try? await PHPhotoLibrary.shared().performChanges {
                let r = PHAssetCreationRequest.forAsset()
                r.addResource(with: .photo, data: data, options: nil)
                r.creationDate = taken
                if let lat = stamp.lat, let lon = stamp.lon {
                    r.location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: 0,
                                            horizontalAccuracy: stamp.accuracy ?? 0, verticalAccuracy: -1,
                                            course: stamp.heading ?? -1, speed: -1, timestamp: taken)
                }
            }
        }
    }
}

/// The system camera for photos outside the survey (install logs, inspections): the JPEG carries where and which way
/// it was taken, like the survey camera's, and the full-size shot also goes to the photo library (`CameraRoll`).
public struct StampedCamera: View {
    let maxSide: CGFloat
    let quality: CGFloat
    let done: (Data) -> Void
    @State private var sensors = CaptureContext()

    public init(maxSide: CGFloat = 1600, quality: CGFloat = 0.7, done: @escaping (Data) -> Void) {
        self.maxSide = maxSide; self.quality = quality; self.done = done
    }

    public var body: some View {
        CameraPicker { img in
            guard let img else { return }
            let stamp = sensors.snapshot(), taken = Date()
            let small = img.scaled(maxSide: maxSide)
            let stamped = stamp.isEmpty ? nil : CaptureContext.jpeg(small, quality: quality, stamp: stamp, taken: taken)
            if let data = stamped ?? small.jpegData(compressionQuality: quality) { done(data) }
            CameraRoll.save(img, stamp: stamp, taken: taken)
        }
        .ignoresSafeArea()
        .onAppear { sensors.start() }
        .onDisappear { sensors.stop() }
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif
