#if canImport(UIKit)
import SwiftUI
import VisionKit
import CoreLocation
import CoreMotion
import ARKit
import AVFoundation
import TCRoofCore

/// What this iPad or iPhone can do for the survey (docs/specs/hardware-assist-swift.md §1). Each hardware button
/// reads it to show itself only where it works; Settings › เครื่องนี้ lists it so the team can see why one is missing.
@MainActor @Observable
final class DeviceCaps {
    static let shared = DeviceCaps()

    /// Live Text in the camera (VisionKit's data scanner): reads nameplates.
    private(set) var liveText = false
    private(set) var compass = false
    private(set) var motion = false
    private(set) var lidar = false
    private(set) var ultraWide = false
    /// From the last location fix on this device; Wi-Fi iPads come out `.approximate`.
    private(set) var gpsGrade = GPSGrade(rawValue: UserDefaults.standard.string(forKey: "deviceCaps.gpsGrade") ?? "") ?? .unknown

    private init() { refresh() }

    /// Hardware doesn't change, but the scanner's availability follows the camera permission.
    func refresh() {
        liveText = DataScannerViewController.isSupported
        compass = CLLocationManager.headingAvailable()
        motion = CMMotionManager().isDeviceMotionAvailable
        lidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        ultraWide = !AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera], mediaType: .video, position: .back).devices.isEmpty
    }

    /// Remembers how good the last fix was, for Settings › เครื่องนี้.
    func noteFix(accuracy: Double) {
        let g = GPSGrade(accuracy: accuracy)
        guard g != .unknown else { return }
        gpsGrade = g
        UserDefaults.standard.set(g.rawValue, forKey: "deviceCaps.gpsGrade")
    }

    /// The roof pitch and facing readings need the motion sensors; facing also needs the compass.
    var roofSensors: Bool { motion }

    /// Rows for Settings › เครื่องนี้.
    var rows: [(title: String, detail: String, on: Bool)] {
        [("อ่านตัวเลขจากป้ายอุปกรณ์", liveText ? "Live Text ในกล้อง" : "เครื่องนี้ไม่รองรับ | พิมพ์เอง", liveText),
         ("วัดมุมเอียงหลังคา", motion ? "เซนเซอร์การเคลื่อนไหว" : "ไม่มีเซนเซอร์ | พิมพ์เอง", motion),
         ("เข็มทิศ (ทิศของหลังคา)", compass ? "ตรวจความแม่นยำทุกครั้ง" : "ไม่มีเข็มทิศ | เลือกทิศเอง", compass),
         ("ตำแหน่ง (GPS)", gpsGrade.settingsDetail, gpsGrade == .gps || gpsGrade == .rough),
         ("LiDAR", lidar ? "มี" : "ไม่มี", lidar),
         ("เลนส์มุมกว้างพิเศษ (0.5×)", ultraWide ? "มี" : "ไม่มี", ultraWide)]
    }
}

/// "จากป้าย", "จากเซนเซอร์": how a value was filled, beside the field.
struct SourceChip: View {
    let source: FillSource?
    var body: some View {
        if let text = source?.chip {
            Text(text).font(.sarabunFixed(10.5, .bold)).foregroundStyle(Theme.primary)
                .padding(.horizontal, 6).frame(height: 18)
                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 5))
                .fixedSize()
                .accessibilityLabel("ค่า\(text)")
        }
    }
}

/// Settings › เครื่องนี้.
struct DeviceCapsSection: View {
    @State private var caps = DeviceCaps.shared
    var body: some View {
        PadSection("เครื่องนี้") {
            ForEach(caps.rows, id: \.title) { r in
                HStack {
                    Image(systemName: r.on ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(r.on ? Theme.success : Theme.inkMuted)
                    Text(r.title)
                    Spacer()
                    Text(r.detail).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        } footer: {
            Text("ปุ่มอ่านจากป้ายและวัดด้วยเครื่องจะแสดงเฉพาะเมื่อเครื่องนี้ทำได้")
        }
        .onAppear { caps.refresh() }
    }
}
#endif
