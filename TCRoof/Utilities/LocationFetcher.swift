import CoreLocation

/// One-shot current location, asking for "while using" permission the first time.
/// Create and call it on the main thread; the completion runs there too.
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    enum Failure: LocalizedError {
        case denied
        var errorDescription: String? {
            "ไม่ได้รับอนุญาตให้ใช้ตำแหน่ง เปิดได้ที่ การตั้งค่า > TCRoof > ตำแหน่ง"
        }
    }

    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocation, Error>) -> Void)?
    private var retries = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func request(_ completion: @escaping (Result<CLLocation, Error>) -> Void) {
        self.completion = completion
        retries = 0
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(.failure(Failure.denied))
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: finish(.failure(Failure.denied))
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last { finish(.success(location)) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // no fix yet (indoors, just woke up, simulator without a location): CoreLocation keeps trying, so ask again a few times
        if (error as? CLError)?.code == .locationUnknown, retries < 3 {
            retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.manager.requestLocation() }
            return
        }
        finish(.failure(LocationFailure(error)))
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        let done = completion
        completion = nil
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
