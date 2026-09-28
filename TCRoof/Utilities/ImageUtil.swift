import UIKit
import Vision
import AVFoundation

enum ImageUtil {
    /// Downscales to at most `maxDimension` and re-encodes as JPEG to keep the store small.
    static func compressed(_ data: Data, maxDimension: CGFloat = 1600) -> Data {
        guard let image = UIImage(data: data) else { return data }
        return compressed(image, maxDimension: maxDimension)
    }

    static func compressed(_ image: UIImage, maxDimension: CGFloat = 1600) -> Data {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7) ?? Data()
    }

    /// Writes photos to temporary files so they can be shared / saved.
    static func exportFiles(_ datas: [Data], prefix: String) -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(prefix, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return datas.enumerated().compactMap { index, data in
            let url = dir.appendingPathComponent(String(format: "%@-%02d.jpg", prefix, index + 1))
            return (try? data.write(to: url)) != nil ? url : nil
        }
    }

    static func detectBarcodes(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            try? handler.perform([request])
            let payloads = (request.results ?? []).compactMap(\.payloadStringValue)
            var seen = Set<String>()
            return payloads.filter { seen.insert($0).inserted }
        }.value
    }

    static func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    static var hasTorch: Bool { AVCaptureDevice.default(for: .video)?.hasTorch ?? false }

    /// Placeholder site photo used by the sample data.
    static func placeholder(symbol: String, hue: CGFloat) -> Data {
        let size = CGSize(width: 800, height: 800)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(hue: hue, saturation: 0.25, brightness: 0.85, alpha: 1).cgColor,
                          UIColor(hue: hue, saturation: 0.45, brightness: 0.55, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let config = UIImage.SymbolConfiguration(pointSize: 260, weight: .light)
            if let symbolImage = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
                let s = symbolImage.size
                symbolImage.draw(in: CGRect(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2, width: s.width, height: s.height))
            }
        }
        return image.jpegData(compressionQuality: 0.6) ?? Data()
    }
}
