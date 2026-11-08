import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

/// The copy of a photo that goes to Drive (CHA-53). Job folders are shared read only with the job's contractors, so a
/// photo's GPS position and compass heading (EXIF GPS) stay on the device: the app keeps them in the photo's own stamp
/// and its local file, never reads them back from a Drive copy, and the station's or customer's location is on the job.
public enum PhotoPrivacy {
    /// `data` without its GPS dictionary, copied without re-encoding (the pixels, orientation and other EXIF stay).
    /// Anything that isn't an image, or has no GPS, comes back as it was.
    public static func withoutLocation(_ data: Data, mimeType: String) -> Data {
        #if canImport(ImageIO)
        guard mimeType.lowercased().hasPrefix("image/"),
              let src = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(src),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              props[kCGImagePropertyGPSDictionary] != nil else { return data }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return data }
        // merging nothing into the source's metadata keeps all of it (without a merge ImageIO writes none), but the GPS
        let opts: [CFString: Any] = [kCGImageDestinationMergeMetadata: true, kCGImageDestinationMetadata: CGImageMetadataCreateMutable(),
                                     kCGImageMetadataShouldExcludeGPS: true]
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dest, src, opts as CFDictionary, &error) else { return data }
        return out as Data
        #else
        return data
        #endif
    }
}
