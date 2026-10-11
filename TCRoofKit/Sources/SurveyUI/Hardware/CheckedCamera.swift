#if canImport(UIKit)
import SwiftUI
import TCRoofCore
import TCRoofUI

/// The survey camera with a quick check after each shot (docs/specs/hardware-assist-swift.md §H4): a blurred or dark
/// photo is shown again with "ภาพไม่ชัด ถ่ายใหม่?" and เก็บไว้ / ถ่ายใหม่. It never blocks: เก็บไว้ keeps the photo.
/// For a square-on field (`PhotoShot.straight`) a roll over `ImageQuality.tiltLimit` also counts ("ภาพเอียง").
struct CheckedCamera: View {
    var shot: PhotoShot = .any
    let done: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(SurveyModel.self) private var model
    @State private var sensors = CaptureContext()
    @State private var stamp: PhotoStamp?
    @State private var taken: UIImage?
    @State private var issues: [ImageQuality.Issue] = []
    @State private var attempt = 0
    @State private var flash = false

    var body: some View {
        ZStack {
            if let taken, !issues.isEmpty {
                review(taken)
            } else {
                CameraPicker(dismissOnFinish: false, flash: flash) { img in check(img) }
                    .id(attempt)
                    .ignoresSafeArea()
            }
        }
        .onAppear { sensors.start() }
        .onDisappear { sensors.stop() }
    }

    private func check(_ img: UIImage?) {
        guard let img else { return finish(nil) }
        stamp = sensors.snapshot()
        let tilted = shot == .straight && (sensors.tilt() ?? 0) > ImageQuality.tiltLimit
        Task {
            let found = await PhotoCheck.issues(img) + (tilted ? [.tilted] : [])
            if found.isEmpty { finish(img) } else { taken = img; issues = found }
        }
    }

    /// The page saves the image with `model.addPhoto` right away; the stamp waits there for it and marks it as a camera shot.
    private func finish(_ img: UIImage?) {
        if img != nil { model.captureStamp = (stamp ?? PhotoStamp(), Date(), false) }
        done(img)
        dismiss()
    }

    private func review(_ img: UIImage) -> some View {
        PhotoReview(image: img, issues: issues, keep: { finish(img) }, retake: {
            flash = issues.contains(.dark)
            taken = nil; issues = []; attempt += 1
        })
    }
}

/// A shot with problems, shown again with the reasons and เก็บไว้ / ถ่ายใหม่.
struct PhotoReview: View {
    let image: UIImage
    let issues: [ImageQuality.Issue]
    let keep: () -> Void
    let retake: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: .infinity)
            ForEach(issues, id: \.self) { i in
                Label(i.message, systemImage: i == .dark ? "moon.fill" : i == .tilted ? "level" : "camera.metering.unknown")
                    .font(.headline).foregroundStyle(Theme.pending)
            }
            HStack(spacing: 12) {
                Button(action: keep) { Text("เก็บไว้").frame(maxWidth: .infinity, minHeight: 50) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
                Button(action: retake) { Text("ถ่ายใหม่").bold().frame(maxWidth: .infinity, minHeight: 50) }
                    .buttonStyle(TCButtonStyle(.primary, size: .card))
            }
            .frame(maxWidth: 520)
        }
        .padding(20)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}

/// Measures a photo on a 512-px grey copy, off the main thread.
enum PhotoCheck {
    static func issues(_ image: UIImage) async -> [ImageQuality.Issue] {
        guard let cg = image.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) { () -> [ImageQuality.Issue] in
            let k = min(1, 512 / Double(max(cg.width, cg.height)))
            let w = max(3, Int(Double(cg.width) * k)), h = max(3, Int(Double(cg.height) * k))
            var grey = [UInt8](repeating: 0, count: w * h)
            let drawn = grey.withUnsafeMutableBytes { buf -> Bool in
                guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                ctx.interpolationQuality = .medium
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return [] }
            return ImageQuality(grey: grey, width: w, height: h)?.issues ?? []
        }.value
    }
}
#endif
