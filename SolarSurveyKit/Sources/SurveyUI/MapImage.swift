#if canImport(UIKit)
import UIKit
import MapKit
import CoreLocation

/// Satellite picture of the site for "ภาพสถานที่ติดตั้ง": Google Maps Static API when an API key is set,
/// otherwise Apple Maps satellite imagery (no key needed). Same centre, zoom and framing either way.
enum MapImage {
    enum Failure: Error, LocalizedError {
        case noGPS, badResponse(String)
        var errorDescription: String? {
            switch self {
            case .noGPS: return "ยังไม่มีพิกัด GPS — กรอกที่ ข้อมูลโครงการ › พิกัดดาวเทียม Google Map (เช่น 17.0062, 99.8235 หรือวางลิงก์ Google Maps)"
            case .badResponse(let s): return "ดึงภาพแผนที่ไม่สำเร็จ: \(s)"
            }
        }
    }

    /// Frame of the site photo on the sheet is landscape; 640 px is the Static API's free-tier maximum width.
    static let size = CGSize(width: 640, height: 400)

    /// "17.0062, 99.8235", "17.0062 99.8235", or a Google Maps link containing "@lat,lng" or "q=lat,lng".
    static func coordinate(from text: String) -> CLLocationCoordinate2D? {
        let t = text.removingPercentEncoding ?? text
        let patterns = ["@(-?\\d+\\.\\d+),\\s*(-?\\d+\\.\\d+)", "[?&](?:q|query|ll|center)=(-?\\d+\\.\\d+),\\s*(-?\\d+\\.\\d+)", "(-?\\d{1,2}\\.\\d+)\\s*[, ]\\s*(-?\\d{1,3}\\.\\d+)"]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let r1 = Range(m.range(at: 1), in: t), let r2 = Range(m.range(at: 2), in: t),
                  let lat = Double(t[r1]), let lng = Double(t[r2]),
                  abs(lat) <= 90, abs(lng) <= 180 else { continue }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return nil
    }

    /// Ground width in metres shown by a Web-Mercator map `px` pixels wide at `zoom`.
    static func metersAcross(lat: Double, zoom: Int, px: Double = 640) -> Double {
        156_543.033_92 * cos(lat * .pi / 180) * px / pow(2, Double(zoom))
    }

    static func fetch(gps: String, zoom: Int, googleKey: String) async throws -> UIImage {
        guard let c = coordinate(from: gps) else { throw Failure.noGPS }
        let key = googleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? try await apple(c, zoom: zoom) : try await google(c, zoom: zoom, key: key)
    }

    static func google(_ c: CLLocationCoordinate2D, zoom: Int, key: String) async throws -> UIImage {
        var u = URLComponents(string: "https://maps.googleapis.com/maps/api/staticmap")!
        let center = String(format: "%.6f,%.6f", c.latitude, c.longitude)
        u.queryItems = [.init(name: "center", value: center), .init(name: "zoom", value: String(zoom)),
                        .init(name: "size", value: "\(Int(size.width))x\(Int(size.height))"), .init(name: "scale", value: "2"),
                        .init(name: "maptype", value: "satellite"), .init(name: "markers", value: "color:red|\(center)"),
                        .init(name: "key", value: key)]
        let (data, resp) = try await URLSession.shared.data(from: u.url!)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let img = UIImage(data: data) else {
            let msg = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw Failure.badResponse("Google Maps HTTP \(status) \(msg)".trimmingCharacters(in: .whitespaces))
        }
        return img
    }

    static func apple(_ c: CLLocationCoordinate2D, zoom: Int) async throws -> UIImage {
        let w = metersAcross(lat: c.latitude, zoom: zoom), h = w * Double(size.height / size.width)
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: c, latitudinalMeters: h, longitudinalMeters: w)
        o.size = size
        o.scale = 2
        o.preferredConfiguration = MKImageryMapConfiguration()
        let shot = try await MKMapSnapshotter(options: o).start()
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            shot.image.draw(at: .zero)
            let p = shot.point(for: c)
            let pin = UIBezierPath(ovalIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
            UIColor.systemRed.setFill(); pin.fill()
            UIColor.white.setStroke(); pin.lineWidth = 2.5; pin.stroke()
        }
    }
}
#endif
