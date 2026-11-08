#if canImport(ImageIO)
import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import DriveSync

final class PhotoPrivacyTests: XCTestCase {
    /// A 4 × 4 JPEG stamped like the app's camera: GPS position and heading, and the time taken.
    private func stampedJPEG() throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try XCTUnwrap(ctx.makeImage())
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        let props: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 13.75, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 100.5, kCGImagePropertyGPSLongitudeRef: "E",
                                            kCGImagePropertyGPSImgDirection: 182.0, kCGImagePropertyGPSImgDirectionRef: "T"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:09 10:30:00"],
            kCGImagePropertyOrientation: 6,
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func properties(_ data: Data) throws -> [CFString: Any] {
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
    }

    func testDriveCopyHasNoGPSButKeepsTheRest() throws {
        let photo = try stampedJPEG()
        XCTAssertNotNil(try properties(photo)[kCGImagePropertyGPSDictionary], "the fixture carries GPS")
        let copy = PhotoPrivacy.withoutLocation(photo, mimeType: "image/jpeg")
        let props = try properties(copy)
        XCTAssertNil(props[kCGImagePropertyGPSDictionary], "no position or heading on Drive")
        XCTAssertEqual((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String,
                       "2026:11:09 10:30:00", "the time taken stays")
        XCTAssertEqual(props[kCGImagePropertyOrientation] as? Int, 6, "the orientation stays")
        XCTAssertEqual(PhotoPrivacy.withoutLocation(copy, mimeType: "image/jpeg"), copy, "a copy without GPS is left as it is")
    }

    func testOtherFilesAreUntouched() throws {
        let pdf = Data("%PDF-1.4 not an image".utf8)
        XCTAssertEqual(PhotoPrivacy.withoutLocation(pdf, mimeType: "application/pdf"), pdf)
        let photo = try stampedJPEG()
        XCTAssertEqual(PhotoPrivacy.withoutLocation(photo, mimeType: "application/octet-stream"), photo, "only images are copied")
    }

    func testTheUploadBodyCarriesTheCopy() throws {
        let photo = try stampedJPEG()
        let (_, body) = try DriveClient.multipart(photo, name: "a.jpg", mimeType: "image/jpeg", parent: "p")
        let copy = PhotoPrivacy.withoutLocation(photo, mimeType: "image/jpeg")
        XCTAssertNotNil(body.range(of: copy), "the multipart body holds the copy without GPS")
        XCTAssertNil(body.range(of: photo), "and not the original")
    }
}
#endif
