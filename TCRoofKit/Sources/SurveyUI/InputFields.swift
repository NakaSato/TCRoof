#if canImport(UIKit)
import SwiftUI
import CoreLocation
import TCRoofCore
import TCRoofUI

/// The cover's "วันที่" field: a date picker in the Thai calendar, still stored as yyyy-MM-dd.
struct DateInput: View {
    @Binding var text: String

    var body: some View {
        let parsed = ISODate.date(text)
        HStack(spacing: 10) {
            if let d = parsed {
                TCDateField(date: Binding(get: { d }, set: { text = ISODate.string($0) }), accessibilityTitle: "วันที่")
                    .frame(maxWidth: 220)
                Text("ในรายงาน: " + ISODate.thai(text)).font(.caption).foregroundStyle(Theme.inkMuted)
            } else {
                if !text.isEmpty {
                    Text("ค่าเดิม \"\(text)\" อ่านเป็นวันที่ไม่ได้").font(.caption).foregroundStyle(Theme.pending)
                }
                Button(text.isEmpty ? "ใส่วันที่วันนี้" : "เปลี่ยนเป็นวันนี้") { text = ISODate.string(Date()) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
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
    @State private var accuracy: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TCTextField("17.0062, 99.8235", text: $text, keyboard: .numbersAndPunctuation)
                TCLocationButton(working: locating, action: locate)
            }
            switch GPS.check(text) {
            case .invalid:
                Text("รูปแบบไม่ถูกต้อง ใช้ ละติจูด, ลองจิจูด เช่น 17.0062, 99.8235").font(.caption).foregroundStyle(Theme.dangerText)
            case .outsideThailand:
                Text("พิกัดอยู่นอกประเทศไทย ตรวจค่าอีกครั้ง").font(.caption).foregroundStyle(Theme.pending)
            case .swapped(let fixed):
                HStack(spacing: 8) {
                    Text("ดูเหมือนสลับละติจูดกับลองจิจูด").font(.caption).foregroundStyle(Theme.pending)
                    Button("สลับเป็น \(fixed)") { text = fixed }.font(.caption)
                }
            case .ok:
                if let p = GPS.parse(text), let url = URL(string: "https://maps.apple.com/?ll=\(p.lat),\(p.lon)") {
                    Link(destination: url) { Label("ตรวจตำแหน่งในแผนที่", systemImage: "map") }.font(.caption)
                }
            case .empty:
                EmptyView()
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(Theme.dangerText) }
            else if let accuracy {
                Text(GPSGrade.note(accuracy: accuracy)).font(.caption)
                    .foregroundStyle(GPSGrade(accuracy: accuracy) == .approximate ? Theme.pending : Theme.inkMuted)
            }
        }
    }

    private func locate() {
        locating = true
        failure = nil
        locator.request { result in
            locating = false
            switch result {
            case .success(let loc):
                text = GPS.format(loc.coordinate.latitude, loc.coordinate.longitude)
                accuracy = loc.horizontalAccuracy
            case .failure(let error): failure = error.localizedDescription
            }
        }
    }
}

/// One-shot current location; asks for "while using" permission the first time. Main thread only.
/// Listens for fixes until one is within `goodAccuracy`, or until `timeLimit`, then gives the best fix it saw
/// (or an error), so the button never spins forever where the iPad gets no fix (Wi-Fi-only iPad in the field, indoors).
final class GPSLocator: NSObject, CLLocationManagerDelegate {
    struct Denied: LocalizedError {
        var errorDescription: String? { "ไม่ได้รับอนุญาตให้ใช้ตำแหน่ง เปิดได้ที่ การตั้งค่า > TCRoof > ตำแหน่ง" }
    }

    static let goodAccuracy: CLLocationAccuracy = 25
    static let timeLimit: TimeInterval = 12

    /// Made on the first request: a view re-creates its `@State` initial value on every update, and each manager
    /// opens a connection to locationd.
    private var manager: CLLocationManager?
    private var completion: ((Result<CLLocation, Error>) -> Void)?
    /// The best accuracy so far while it listens, for "± 8 ม." on the button.
    var progress: ((CLLocationAccuracy) -> Void)?
    private var best: CLLocation?
    private var started = Date()
    private var timer: Timer?

    func request(_ completion: @escaping (Result<CLLocation, Error>) -> Void) {
        let m = manager ?? CLLocationManager()
        if manager == nil {
            m.delegate = self
            m.desiredAccuracy = kCLLocationAccuracyBest
            manager = m
        }
        self.completion = completion
        switch m.authorizationStatus {
        case .notDetermined: m.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(.failure(Denied()))
        default: start(m)
        }
    }

    /// The time limit runs from here, not while the permission prompt is open.
    private func start(_ m: CLLocationManager) {
        best = nil
        started = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.timeLimit, repeats: false) { [weak self] _ in self?.timeUp() }
        m.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: if timer == nil { start(manager) }
        case .denied, .restricted: finish(.failure(Denied()))
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard completion != nil else { return }
        // skip a fix cached from before this request, and invalid ones
        for l in locations where l.horizontalAccuracy >= 0 && l.timestamp > started.addingTimeInterval(-10) {
            if best.map({ l.horizontalAccuracy < $0.horizontalAccuracy }) ?? true { best = l }
        }
        if let best { progress?(best.horizontalAccuracy) }
        if let best, best.horizontalAccuracy <= Self.goodAccuracy { finish(.success(best)) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // no fix yet: CoreLocation keeps trying while updating, so wait for the time limit
        if (error as? CLError)?.code == .locationUnknown { return }
        finish(best.map { .success($0) } ?? .failure(LocationFailure(error)))
    }

    private func timeUp() {
        finish(best.map { .success($0) } ?? .failure(LocationFailure(CLError(.locationUnknown))))
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timer?.invalidate(); timer = nil
        manager?.stopUpdatingLocation()
        let done = completion
        completion = nil
        if case .success(let l) = result { MainActor.assumeIsolated { DeviceCaps.shared.noteFix(accuracy: l.horizontalAccuracy) } }
        done?(result)
    }
}
/// A CoreLocation failure in words the surveyor can act on, in place of "kCLErrorDomain error 0".
struct LocationFailure: LocalizedError {
    let message: String
    init(_ error: Error) {
        switch (error as? CLError)?.code {
        case .locationUnknown?: message = "ยังหาตำแหน่งไม่ได้ ลองออกไปที่โล่งแล้วกดอีกครั้ง หรือพิมพ์พิกัดเอง"
        case .denied?: message = "ไม่ได้รับอนุญาตให้ใช้ตำแหน่ง เปิดได้ที่ การตั้งค่า > TCRoof > ตำแหน่ง"
        case .network?: message = "เชื่อมต่อเครือข่ายไม่ได้ ลองใหม่อีกครั้ง หรือพิมพ์พิกัดเอง"
        default: message = "หาตำแหน่งไม่สำเร็จ ลองใหม่อีกครั้ง หรือพิมพ์พิกัดเอง"
        }
    }
    var errorDescription: String? { message }
}
#endif
