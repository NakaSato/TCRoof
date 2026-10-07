#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// The survey camera with a quick check after each shot (docs/specs/hardware-assist-swift.md §H4): a blurred or dark
/// photo is shown again with "ภาพไม่ชัด ถ่ายใหม่?" and เก็บไว้ / ถ่ายใหม่. It never blocks: เก็บไว้ keeps the photo.
struct CheckedCamera: View {
    let done: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shot: UIImage?
    @State private var issues: [ImageQuality.Issue] = []
    @State private var attempt = 0
    @State private var flash = false

    var body: some View {
        ZStack {
            if let shot, !issues.isEmpty {
                review(shot)
            } else {
                CameraPicker(dismissOnFinish: false, flash: flash) { img in check(img) }
                    .id(attempt)
                    .ignoresSafeArea()
            }
        }
    }

    private func check(_ img: UIImage?) {
        guard let img else { return finish(nil) }
        Task {
            let found = await PhotoCheck.issues(img)
            if found.isEmpty { finish(img) } else { shot = img; issues = found }
        }
    }

    private func finish(_ img: UIImage?) {
        done(img)
        dismiss()
    }

    private func review(_ img: UIImage) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: .infinity)
            ForEach(issues, id: \.self) { i in
                Label(i.message, systemImage: i == .dark ? "moon.fill" : "camera.metering.unknown")
                    .font(.headline).foregroundStyle(Home.orange)
            }
            HStack(spacing: 12) {
                Button { finish(img) } label: { Text("เก็บไว้").frame(maxWidth: .infinity, minHeight: 50) }
                    .buttonStyle(.bordered)
                Button {
                    flash = issues.contains(.dark)
                    shot = nil; issues = []; attempt += 1
                } label: { Text("ถ่ายใหม่").bold().frame(maxWidth: .infinity, minHeight: 50) }
                    .buttonStyle(.borderedProminent)
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
