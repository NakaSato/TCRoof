#if canImport(UIKit)
import SwiftUI
import CoreMotion
import CoreLocation
import TCRoofCore

/// "วัดด้วยเครื่อง" beside the roof pitch and facing fields (docs/specs/hardware-assist-swift.md §H3).
/// Both come from one reading: the iPad lying on the roof sheet, top edge up the slope.
struct RoofSensorButton: View {
    enum Reading { case pitch, facing }
    let reading: Reading
    /// Pitch: "14.8". Facing: the form's choice and its อื่นๆ text.
    let apply: (_ value: String, _ other: String) -> Void
    @State private var open = false
    @State private var caps = DeviceCaps.shared

    var body: some View {
        if caps.roofSensors && (reading == .pitch || caps.compass) {
            Button { open = true } label: {
                Label("วัดด้วยเครื่อง", systemImage: reading == .pitch ? "level" : "location.north.line")
                    .font(.system(size: 14, weight: .semibold)).frame(minHeight: 44)
            }
            .buttonStyle(.plain).foregroundStyle(Home.primary)
            .sheet(isPresented: $open) {
                RoofSensorSheet(reading: reading) { v, o in
                    open = false
                    if let v { apply(v, o) }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

struct RoofSensorSheet: View {
    let reading: RoofSensorButton.Reading
    let done: (String?, String) -> Void
    @State private var sensor = RoofSensorModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("วาง iPad ราบบนแผ่นหลังคา ให้ขอบด้านบนของจอชี้ขึ้นตามแนวลาด · บนหลังคาลอนให้วางขวางลอน")
                    .font(.callout).foregroundStyle(Home.muted).multilineTextAlignment(.center)
                VStack(spacing: 4) {
                    Text(String(format: "%.1f°", sensor.tilt)).font(.system(size: 56, weight: .bold).monospacedDigit())
                        .foregroundStyle(reading == .pitch ? Home.navy : Home.muted)
                    Text("มุมเอียง").font(.footnote).foregroundStyle(Home.muted)
                }
                VStack(spacing: 4) {
                    Text(sensor.facing.map(Orientation.describe) ?? "–").font(.system(size: reading == .facing ? 34 : 22, weight: .bold))
                        .foregroundStyle(reading == .facing ? Home.navy : Home.muted)
                    Text(sensor.trueNorth ? "หลังคาหันไปทางทิศ (ทิศจริง)" : "หลังคาหันไปทางทิศ (ทิศแม่เหล็ก)").font(.footnote).foregroundStyle(Home.muted)
                }
                status
                Button { confirm() } label: {
                    Text("ใช้ค่านี้").bold().frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ready)
            }
            .padding(24)
            .navigationTitle(reading == .pitch ? "วัดมุมเอียงหลังคา" : "วัดทิศของหลังคา")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { done(nil, "") } } }
        }
        .onAppear { sensor.start(heading: reading == .facing) }
        .onDisappear { sensor.stop() }
    }

    @ViewBuilder private var status: some View {
        if reading == .facing, sensor.tilt < Orientation.minimumTiltForFacing {
            Label("หลังคาเกือบราบ บอกทิศไม่ได้", systemImage: "exclamationmark.triangle").foregroundStyle(Home.orange)
        } else if reading == .facing, sensor.headingDisturbed {
            Label("ตรวจทิศอีกครั้ง (ใกล้โลหะ) ± \(Int(sensor.headingAccuracy))°", systemImage: "exclamationmark.triangle").foregroundStyle(Home.orange)
        } else if sensor.steady {
            Label("ค่านิ่งแล้ว", systemImage: "checkmark.circle.fill").foregroundStyle(Home.ok)
        } else {
            Label("ถือนิ่ง ๆ สักครู่", systemImage: "hand.raised").foregroundStyle(Home.muted)
        }
    }

    private var ready: Bool {
        guard sensor.steady else { return false }
        return reading == .pitch || (sensor.facing != nil && sensor.tilt >= Orientation.minimumTiltForFacing)
    }

    private func confirm() {
        switch reading {
        case .pitch:
            done(String(format: "%.1f", sensor.tilt), "")
        case .facing:
            guard let f = sensor.facing else { return }
            let c = Orientation.facingChoice(f)
            done(c.choice, c.other)
        }
    }
}

/// Gravity at 50 Hz for the pitch and the downhill direction; the compass for the heading of the iPad's top edge.
@MainActor @Observable
final class RoofSensorModel: NSObject, CLLocationManagerDelegate {
    private(set) var tilt = 0.0
    private(set) var steady = false
    private(set) var facing: Double?
    private(set) var headingAccuracy = 0.0
    private(set) var trueNorth = true
    var headingDisturbed: Bool { headingAccuracy < 0 || headingAccuracy > Orientation.headingAccuracyLimit }

    private let motion = CMMotionManager()
    private let location = CLLocationManager()
    private var samples: [Double] = []
    private var gravity = (x: 0.0, y: 0.0)
    private var heading: Double?

    func start(heading wantsHeading: Bool) {
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            self.gravity = (g.x, g.y)
            self.tilt = Orientation.tilt(gx: g.x, gy: g.y, gz: g.z)
            self.samples.append(self.tilt)
            if self.samples.count > 50 { self.samples.removeFirst(self.samples.count - 50) }
            self.steady = Orientation.isSteady(self.samples)
            self.updateFacing()
        }
        guard wantsHeading, CLLocationManager.headingAvailable() else { return }
        location.delegate = self
        // true north needs location; without permission the magnetic heading is used and labelled
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
        location.headingFilter = 1
        location.startUpdatingHeading()
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        location.stopUpdatingHeading()
    }

    private func updateFacing() {
        guard let heading, tilt >= Orientation.minimumTiltForFacing else { facing = nil; return }
        facing = Orientation.facing(heading: heading, gx: gravity.x, gy: gravity.y)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let trueHeading = h.trueHeading, magnetic = h.magneticHeading, accuracy = h.headingAccuracy
        MainActor.assumeIsolated {
            trueNorth = trueHeading >= 0
            heading = trueNorth ? trueHeading : magnetic
            headingAccuracy = accuracy
            updateFacing()
        }
    }
}
#endif
