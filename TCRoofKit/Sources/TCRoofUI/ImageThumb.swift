#if canImport(UIKit)
import ImageIO
import UIKit

/// A downscaled copy of an image, decoded by ImageIO without loading the full picture, turned upright by its EXIF
/// orientation. Safe off the main actor.
public enum ImageThumb {
    public nonisolated static func make(data: Data, maxPixel: Int) -> UIImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { make(source: $0, maxPixel: maxPixel) }
    }

    public nonisolated static func make(url: URL, maxPixel: Int) -> UIImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { make(source: $0, maxPixel: maxPixel) }
    }

    public nonisolated static func make(source: CGImageSource, maxPixel: Int) -> UIImage? {
        cgImage(source: source, maxPixel: maxPixel).map { UIImage(cgImage: $0) }
    }

    public nonisolated static func cgImage(source: CGImageSource, maxPixel: Int) -> CGImage? {
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
    }
}
#endif
