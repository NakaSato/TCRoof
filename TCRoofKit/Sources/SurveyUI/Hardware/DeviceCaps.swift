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

    private init() { refresh() }

    /// Hardware doesn't change, but the scanner's availability follows the camera permission.
    func refresh() {
        liveText = DataScannerViewController.isSupported
        compass = CLLocationManager.headingAvailable()
        motion = CMMotionManager().isDeviceMotionAvailable
        lidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        ultraWide = !AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera], mediaType: .video, position: .back).devices.isEmpty
    }

    /// The roof pitch and facing readings need the motion sensors; facing also needs the compass.
    var roofSensors: Bool { motion }

    /// Rows for Settings › เครื่องนี้.
    var rows: [(title: String, detail: String, on: Bool)] {
        [("อ่านตัวเลขจากป้ายอุปกรณ์", liveText ? "Live Text ในกล้อง" : "เครื่องนี้ไม่รองรับ · พิมพ์เอง", liveText),
         ("วัดมุมเอียงหลังคา", motion ? "เซนเซอร์การเคลื่อนไหว" : "ไม่มีเซนเซอร์ · พิมพ์เอง", motion),
         ("เข็มทิศ (ทิศของหลังคา)", compass ? "ตรวจความแม่นยำทุกครั้ง" : "ไม่มีเข็มทิศ · เลือกทิศเอง", compass),
         ("LiDAR", lidar ? "มี" : "ไม่มี", lidar),
         ("เลนส์มุมกว้างพิเศษ (0.5×)", ultraWide ? "มี" : "ไม่มี", ultraWide)]
    }
}

/// "จากป้าย", "จากเซนเซอร์": how a value was filled, beside the field.
struct SourceChip: View {
    let source: FillSource?
    var body: some View {
        if let text = source?.chip {
            Text(text).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Home.primary)
                .padding(.horizontal, 6).frame(height: 18)
                .background(Home.primarySoft, in: RoundedRectangle(cornerRadius: 5))
                .fixedSize()
                .accessibilityLabel("ค่า\(text)")
        }
    }
}

/// Settings › เครื่องนี้.
struct DeviceCapsSection: View {
    @State private var caps = DeviceCaps.shared
    var body: some View {
        Section {
            ForEach(caps.rows, id: \.title) { r in
                HStack {
                    Image(systemName: r.on ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(r.on ? Home.ok : Home.muted)
                    Text(r.title)
                    Spacer()
                    Text(r.detail).font(.footnote).foregroundStyle(Home.muted).multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        } header: { Text("เครื่องนี้") } footer: {
            Text("ปุ่มอ่านจากป้ายและวัดด้วยเครื่องจะแสดงเฉพาะเมื่อเครื่องนี้ทำได้")
        }
        .onAppear { caps.refresh() }
    }
}
#endif
