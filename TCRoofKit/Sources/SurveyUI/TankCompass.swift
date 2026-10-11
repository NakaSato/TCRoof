#if canImport(UIKit)
import SwiftUI
import UIKit
import AVFoundation
import CoreLocation
import TCRoofCore
import TCRoofUI

/// D1 "วัดด้วย iPad" (docs/ui/survey-d1-size, states/08): aim the camera along wall A from corner A-1, hold still for
/// 2 s and the heading locks; the top wall faces that heading − 90°. Without a compass (the simulator) the azimuth is
/// typed instead.
struct TankCompassView: View {
    /// The far corner's column number on line A (A-17 for 16 spans).
    let lastColumn: Int
    let close: () -> Void
    /// The azimuth and the compass accuracy; nil accuracy for a typed value.
    let save: (Int, Double?) -> Void
    @State var reader = HeadingReader()
    @State var typed = ""

    static let yellow = Color(red: 1, green: 0.831, blue: 0.231)
    static let green = Color(red: 0.180, green: 0.761, blue: 0.494)
    static let panel = Color(red: 0.122, green: 0.161, blue: 0.216).opacity(0.92)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if reader.available {
                CameraPreview().ignoresSafeArea()
                guide
            } else {
                manualEntry
            }
            VStack(spacing: 0) {
                header
                Spacer()
                if reader.available { lockPanel }
            }
            .padding(16)
        }
        .foregroundStyle(.white)
        .onAppear { reader.start() }
        .onDisappear { reader.stop() }
    }

    var corner: String { "A-\(lastColumn)" }

    var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .bold))
                    .frame(width: 48, height: 48).background(Color.black.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("ปิด")
            VStack(alignment: .leading, spacing: 2) {
                Text("เล็งแนวผนัง A").font(.system(size: 18, weight: .bold))
                Text("ยืนที่มุม A-1 · ให้เส้นเหลืองทับขอบผนังที่วิ่งไปมุม \(corner)").font(.system(size: 14)).lineLimit(2)
            }
            .shadow(color: .black.opacity(0.6), radius: 3)
            Spacer(minLength: 8)
            if reader.available {
                Text(reader.heading.map { "\(Int($0.rounded()) % 360)°" } ?? "—").font(.system(size: 30, weight: .bold)).monospacedDigit()
                    .padding(.horizontal, 18).frame(minHeight: 50).background(Color.black.opacity(0.65), in: Capsule())
                    .accessibilityLabel("ทิศที่เล็ง " + (reader.heading.map { "\(Int($0.rounded()) % 360) องศา" } ?? "ยังไม่มีค่า"))
                if let a = reader.accuracy {
                    Text(a < 0 ? "±?" : "±\(Int(a.rounded()))°").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(reader.accuracyOK ? Self.green : Theme.danger)
                        .padding(.horizontal, 12).frame(minHeight: 36).background(Color.black.opacity(0.65), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 4)
    }

    /// The vertical yellow line, the reticle and the far corner's label.
    var guide: some View {
        GeometryReader { geo in
            let x = geo.size.width / 2, y = geo.size.height * 0.48
            ZStack {
                Path { p in p.move(to: CGPoint(x: x, y: 90)); p.addLine(to: CGPoint(x: x, y: geo.size.height)) }
                    .stroke(Self.yellow, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                A2Icon(name: "d1-aim-reticle", fallback: "scope", size: 44).foregroundStyle(Self.yellow).position(x: x, y: y)
                Text("มุม \(corner)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.navy)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                    .position(x: x + 46, y: y - 70)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    var lockPanel: some View {
        let wall = reader.locked ?? reader.heading
        let az = wall.map { Tank.azimuth(wall: $0) }
        let ok = reader.locked != nil && reader.accuracyOK
        return HStack(spacing: 16) {
            if reader.locked != nil {
                A2Icon(name: "d1-heading-locked", fallback: "checkmark.circle", size: 60).foregroundStyle(Self.green)
            } else {
                ProgressView().tint(.white).frame(width: 60, height: 60)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(reader.locked != nil ? "ถือนิ่งครบ 2 วินาที · จับค่าแล้ว" : "ถือเครื่องนิ่ง 2 วินาที")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(reader.locked != nil ? Self.green : .white)
                if let wall {
                    Text("แนวผนัง A \(Int(wall.rounded()) % 360)° − 90° = ผนังบนหันไปทิศ").font(.system(size: 14))
                }
                Text("ยืนห่างเหล็กเสริม ราวเหล็ก ท่อ ≥ 1 ม. · เกิน ±10° ให้หมุนเครื่องเป็นเลข 8")
                    .font(.system(size: 13, weight: reader.accuracyOK ? .regular : .bold))
                    .foregroundStyle(reader.accuracyOK ? Self.yellow : Theme.danger)
            }
            Spacer(minLength: 8)
            if let az {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(az)°").font(.system(size: 34, weight: .bold)).monospacedDigit()
                    Text(Tank.directionName(az)).font(.system(size: 16, weight: .bold))
                }
            }
            if reader.locked != nil {
                Button { reader.unlock() } label: {
                    Text("วัดใหม่").font(.system(size: 15, weight: .bold)).padding(.horizontal, 14).frame(minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.6)))
                }
                .buttonStyle(.plain)
            }
            Button { if let az { save(az, reader.accuracy) } } label: {
                Text("บันทึกมุม").font(.system(size: 17, weight: .bold)).padding(.horizontal, 22).frame(minHeight: 52)
                    .background(ok ? Theme.primary : Theme.progressZero, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain).disabled(!ok)
        }
        .padding(16)
        .background(Self.panel, in: RoundedRectangle(cornerRadius: 16))
    }

    /// No compass here (the simulator, or a device without a magnetometer): type the azimuth.
    var manualEntry: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.north.circle").font(.system(size: 54)).foregroundStyle(Theme.disabledText)
            Text("อุปกรณ์นี้ไม่มีเข็มทิศ · ป้อนมุมเอง").font(.system(size: 20, weight: .bold))
            Text("ผนังบน (แนว A) หันไปทิศ (องศา 0–359)").font(.system(size: 15)).foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 10) {
                TextField("เช่น 90", text: $typed).keyboardType(.numberPad)
                    .font(.system(size: 24, weight: .bold)).monospacedDigit().multilineTextAlignment(.center)
                    .foregroundStyle(Theme.navy)
                    .frame(width: 140, height: 52).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                if let a = typedAzimuth { Text(Tank.directionName(a)).font(.system(size: 17, weight: .bold)) }
            }
            Button { if let a = typedAzimuth { save(a, nil) } } label: {
                Text("บันทึกมุม").font(.system(size: 17, weight: .bold)).padding(.horizontal, 28).frame(minHeight: 52)
                    .background(typedAzimuth != nil ? Theme.primary : Theme.progressZero, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain).disabled(typedAzimuth == nil)
        }
        .padding(32)
    }

    var typedAzimuth: Int? { NumberInput.value(typed).flatMap { $0 >= 0 && $0 < 360 ? Int($0.rounded()) % 360 : nil } }
}

/// The device heading: `trueHeading` when location is allowed, else `magneticHeading`. Locks when every reading of the
/// last 2 s is within ±2° of their mean.
@Observable final class HeadingReader: NSObject, CLLocationManagerDelegate {
    var heading: Double?
    var accuracy: Double?
    var locked: Double?
    let available: Bool
    @ObservationIgnored let manager = CLLocationManager()
    @ObservationIgnored var lock = HeadingLock()

    override init() {
        #if targetEnvironment(simulator)
        available = false
        #else
        available = CLLocationManager.headingAvailable()
        #endif
        super.init()
    }

    /// Accuracy known and within ±10°.
    var accuracyOK: Bool { HeadingLock.accuracyOK(accuracy) }

    func start() {
        guard available else { return }
        manager.delegate = self
        manager.headingFilter = kCLHeadingFilterNone
        manager.headingOrientation = Self.orientation
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }
    func stop() { manager.stopUpdatingHeading(); manager.stopUpdatingLocation() }
    func unlock() { lock.reset(); locked = nil }

    /// The camera looks out of the back, so the heading is the device's top edge turned by the interface orientation.
    static var orientation: CLDeviceOrientation {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch scene?.interfaceOrientation {
        case .landscapeLeft?: return .landscapeRight
        case .landscapeRight?: return .landscapeLeft
        case .portraitUpsideDown?: return .portraitUpsideDown
        default: return .portrait
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let value = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        heading = value; accuracy = h.headingAccuracy
        if locked == nil { locked = lock.add(value) }
    }
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}

/// The back camera's live picture (no capture).
struct CameraPreview: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        let session = AVCaptureSession()
        override func layoutSubviews() {
            super.layoutSubviews()
            if let c = preview.connection, let scene = window?.windowScene {
                let angle: CGFloat = switch scene.interfaceOrientation {
                case .landscapeLeft: 180
                case .landscapeRight: 0
                case .portraitUpsideDown: 270
                default: 90
                }
                if c.isVideoRotationAngleSupported(angle) { c.videoRotationAngle = angle }
            }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.preview.videoGravity = .resizeAspectFill
        v.preview.session = v.session
        let session = v.session
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok, let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: cam) else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                session.beginConfiguration()
                if session.canAddInput(input) { session.addInput(input) }
                session.commitConfiguration()
                session.startRunning()
            }
        }
        return v
    }

    func updateUIView(_ v: PreviewView, context: Context) {}

    static func dismantleUIView(_ v: PreviewView, coordinator: ()) {
        let session = v.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }
}
#endif
