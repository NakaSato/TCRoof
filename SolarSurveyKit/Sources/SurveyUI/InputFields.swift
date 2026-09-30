#if canImport(UIKit)
import SwiftUI
import CoreLocation
import TCRoofCore

/// The cover's "วันที่" field: a date picker in the Thai calendar, still stored as yyyy-MM-dd.
struct DateInput: View {
    @Binding var text: String

    var body: some View {
        let parsed = ISODate.date(text)
        HStack(spacing: 10) {
            if let d = parsed {
                DatePicker("วันที่", selection: Binding(get: { d }, set: { text = ISODate.string($0) }), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "th_TH"))
                    .environment(\.calendar, Calendar(identifier: .buddhist))
                Text("ในรายงาน: " + ISODate.thai(text)).font(.caption).foregroundStyle(.secondary)
            } else {
                if !text.isEmpty {
                    Text("ค่าเดิม \"\(text)\" อ่านเป็นวันที่ไม่ได้").font(.caption).foregroundStyle(.orange)
                }
                Button(text.isEmpty ? "ใส่วันที่วันนี้" : "เปลี่ยนเป็นวันนี้") { text = ISODate.string(Date()) }
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// The cover's GPS field: typed or taken from the iPad, checked against Thailand's bounds.
struct GPSInput: View {
    @Binding var text: String

    @State private var locator = GPSLocator()
    @State private var locating = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("17.0062, 99.8235", text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder).foregroundStyle(Paper.value)
                Button(action: locate) {
                    if locating { ProgressView() } else { Label("ตำแหน่งปัจจุบัน", systemImage: "location.fill") }
                }
                .buttonStyle(.bordered).disabled(locating)
            }
            switch GPS.check(text) {
            case .invalid:
                Text("รูปแบบไม่ถูกต้อง ใช้ ละติจูด, ลองจิจูด เช่น 17.0062, 99.8235").font(.caption).foregroundStyle(.red)
            case .outsideThailand:
                Text("พิกัดอยู่นอกประเทศไทย ตรวจค่าอีกครั้ง").font(.caption).foregroundStyle(.orange)
            case .swapped(let fixed):
                HStack(spacing: 8) {
                    Text("ดูเหมือนสลับละติจูดกับลองจิจูด").font(.caption).foregroundStyle(.orange)
                    Button("สลับเป็น \(fixed)") { text = fixed }.font(.caption)
                }
            case .ok:
                if let p = GPS.parse(text), let url = URL(string: "https://maps.apple.com/?ll=\(p.lat),\(p.lon)") {
                    Link(destination: url) { Label("ตรวจตำแหน่งในแผนที่", systemImage: "map") }.font(.caption)
                }
            case .empty:
                EmptyView()
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
    }

    private func locate() {
        locating = true
        failure = nil
        locator.request { result in
            locating = false
            switch result {
            case .success(let loc): text = GPS.format(loc.coordinate.latitude, loc.coordinate.longitude)
            case .failure(let error): failure = error.localizedDescription
            }
        }
    }
}

/// One-shot current location; asks for "while using" permission the first time. Main thread only.
final class GPSLocator: NSObject, CLLocationManagerDelegate {
    struct Denied: LocalizedError {
        var errorDescription: String? { "ไม่ได้รับอนุญาตให้ใช้ตำแหน่ง เปิดได้ที่ การตั้งค่า > TCRoof > ตำแหน่ง" }
    }

    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocation, Error>) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func request(_ completion: @escaping (Result<CLLocation, Error>) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(.failure(Denied()))
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: finish(.failure(Denied()))
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last { finish(.success(location)) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        let done = completion
        completion = nil
        done?(result)
    }
}
#endif
