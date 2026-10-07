import XCTest
@testable import TCRoofCore

final class ImageQualityPowerTests: XCTestCase {
    func testTilt() throws {
        XCTAssertEqual(try XCTUnwrap(ImageQuality.tilt(gx: 0, gy: -1)), 0, accuracy: 0.001, "upright portrait")
        XCTAssertEqual(try XCTUnwrap(ImageQuality.tilt(gx: -1, gy: 0)), 0, accuracy: 0.001, "landscape")
        let r = 15 * Double.pi / 180
        XCTAssertEqual(try XCTUnwrap(ImageQuality.tilt(gx: sin(r), gy: -cos(r))), 15, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ImageQuality.tilt(gx: -cos(r), gy: -sin(r))), 15, accuracy: 0.001, "landscape rolled the other way")
        XCTAssertNil(ImageQuality.tilt(gx: 0.1, gy: -0.2), "pointing at the floor: no roll")
        XCTAssertEqual(ImageQuality.Issue.tilted.message, "ภาพเอียง ถ่ายใหม่?")
    }

    func testPhotoShot() {
        XCTAssertEqual(PhotoShot.of("tr2_plate"), .straight)
        XCTAssertEqual(PhotoShot.of("tr0_mdbBreaker"), .straight)
        XCTAssertEqual(PhotoShot.of("photoBreaker"), .straight)
        XCTAssertEqual(PhotoShot.of("meterPic"), .straight)
        XCTAssertEqual(PhotoShot.of("tr1_wide"), .wide)
        XCTAssertEqual(PhotoShot.of("photoWide"), .wide)
        XCTAssertEqual(PhotoShot.of("tr0_front"), .any)
        XCTAssertEqual(PhotoShot.of("aerialPhoto"), .any)
    }

    private let w = 64, h = 48

    /// A checkerboard of 4-px squares: hard edges everywhere.
    private func checker(dark: UInt8 = 30, light: UInt8 = 220) -> [UInt8] {
        (0..<(w * h)).map { i in ((i % w) / 4 + (i / w) / 4) % 2 == 0 ? dark : light }
    }
    /// The same board after a 5×5 box blur.
    private func blurred(_ src: [UInt8]) -> [UInt8] {
        (0..<(w * h)).map { i in
            let x = i % w, y = i / w
            var s = 0, n = 0
            for dy in -2...2 { for dx in -2...2 {
                let xx = min(max(x + dx, 0), w - 1), yy = min(max(y + dy, 0), h - 1)
                s += Int(src[yy * w + xx]); n += 1
            } }
            return UInt8(s / n)
        }
    }

    func testSharpAndBlurred() throws {
        let sharp = try XCTUnwrap(ImageQuality(grey: checker(), width: w, height: h))
        let soft = try XCTUnwrap(ImageQuality(grey: blurred(checker()), width: w, height: h))
        XCTAssertGreaterThan(sharp.sharpness, 10 * soft.sharpness)
        XCTAssertEqual(sharp.issues, [])
        let flat = try XCTUnwrap(ImageQuality(grey: Array(repeating: 128, count: w * h), width: w, height: h))
        XCTAssertEqual(flat.sharpness, 0, accuracy: 0.0001)
        XCTAssertEqual(flat.issues, [.blurry], "a featureless frame has no edges to focus on")
    }

    func testDark() throws {
        let night = try XCTUnwrap(ImageQuality(grey: checker(dark: 5, light: 60), width: w, height: h))
        XCTAssertLessThan(night.brightness, ImageQuality.darkLimit)
        XCTAssertTrue(night.issues.contains(.dark))
        XCTAssertEqual(try XCTUnwrap(ImageQuality(grey: Array(repeating: 255, count: 9), width: 3, height: 3)).brightness, 1)
        XCTAssertNil(ImageQuality(grey: [1, 2], width: 1, height: 2), "too small to measure")
        XCTAssertEqual(ImageQuality.Issue.dark.message, "มืดเกินไป ถ่ายใหม่โดยเปิดแฟลช?")
    }

    func testPowerAdvice() {
        XCTAssertEqual(PowerAdvice(.init(battery: 0.8)).notes, [])
        XCTAssertTrue(PowerAdvice(.init(heat: .serious)).hot)
        XCTAssertFalse(PowerAdvice(.init(heat: .fair)).hot)

        // low battery holds uploads only off Wi-Fi and off the charger
        XCTAssertTrue(PowerAdvice(.init(battery: 0.15, onWiFi: false)).holdUploads)
        XCTAssertFalse(PowerAdvice(.init(battery: 0.15, charging: true, onWiFi: false)).holdUploads)
        XCTAssertFalse(PowerAdvice(.init(battery: 0.15, onWiFi: true)).holdUploads)
        XCTAssertTrue(PowerAdvice(.init(battery: 0.9, lowPowerMode: true, onWiFi: false)).holdUploads, "Low Power Mode counts")
        XCTAssertFalse(PowerAdvice(.init(battery: nil, onWiFi: false)).lowBattery, "unknown battery is not low")

        let all = PowerAdvice(.init(heat: .critical, battery: 0.1, onWiFi: false, freeBytes: 1_500_000_000))
        XCTAssertEqual(all.notes.count, 3)
        XCTAssertTrue(all.notes[0].hasPrefix("เครื่องร้อน"))
        XCTAssertTrue(PowerAdvice(.init(battery: 0.1, onWiFi: true)).notes == ["แบตเตอรี่ต่ำ"])
    }
}
