#if canImport(UIKit)
import SwiftUI
import UIKit
import Network
import TCRoofCore
import TCRoofUI

/// Heat, battery, Low Power Mode, Wi-Fi and free space, turned into `PowerAdvice` (docs/specs/hardware-assist-swift.md §H8).
@MainActor @Observable
final class PowerMonitor {
    static let shared = PowerMonitor()

    private(set) var advice = PowerAdvice(.init())
    /// Runs when uploads were held and no longer are (charging, Wi-Fi, battery back up).
    @ObservationIgnored var onUploadsResume: (() -> Void)?
    @ObservationIgnored private var state = PowerAdvice.State()
    @ObservationIgnored private let path = NWPathMonitor()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let names: [Notification.Name] = [ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange,
                                          UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification,
                                          UIApplication.didBecomeActiveNotification]
        observers = names.map { n in
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PowerMonitor.shared.refresh() }
            }
        }
        path.pathUpdateHandler = { p in
            let wifi = p.status == .satisfied && !p.isExpensive
            DispatchQueue.main.async { PowerMonitor.shared.state.onWiFi = wifi; PowerMonitor.shared.refresh() }
        }
        path.start(queue: DispatchQueue(label: "power.path"))
        refresh()
    }

    func refresh() {
        let held = advice.holdUploads
        let d = UIDevice.current
        state.heat = PowerAdvice.Heat(rawValue: ProcessInfo.processInfo.thermalState.rawValue) ?? .nominal
        state.battery = d.batteryLevel < 0 ? nil : Double(d.batteryLevel)
        state.charging = d.batteryState == .charging || d.batteryState == .full
        state.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let home = URL(fileURLWithPath: NSHomeDirectory())
        state.freeBytes = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        let next = PowerAdvice(state)
        if next != advice { advice = next }
        if held && !next.holdUploads { onUploadsResume?() }
    }
}

/// A thin strip over the editor, only while something is held back: heat, low space or low battery.
struct PowerBanner: View {
    @State private var monitor = PowerMonitor.shared
    var body: some View {
        let notes = monitor.advice.notes
        if !notes.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: monitor.advice.hot ? "thermometer.sun.fill" : monitor.advice.lowStorage ? "externaldrive.badge.exclamationmark" : "battery.25")
                Text(notes.joined(separator: " · ")).lineLimit(2)
                Spacer(minLength: 0)
            }
            .font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.pending)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.warningSoft)
            .accessibilityElement(children: .combine)
        }
    }
}
#endif
