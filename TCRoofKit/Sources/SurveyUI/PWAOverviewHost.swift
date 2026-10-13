#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// What the host app gives the iPhone survey home's overviews (docs/ui/pwa-solar-survey-iphone-v2 §4–5): the MP plans
/// and daily reports are the app's, so it hands them over as values. Without a host the install overview is made from
/// each job's `InstallInfo`, with no plan.
public struct PWAOverviewHost {
    /// The PWA project's stations being installed; nil when the host has none to give.
    public var installStations: [InstallStationSummary]?
    /// Opens a station that has no survey job in the installation stage here.
    public var openStation: ((InstallStationSummary) -> Void)?
    /// Opens the daily report list from the overview's strip.
    public var openDailyReports: (() -> Void)?
    /// Handed-over stations. There is no monitoring feed yet, so a host leaves it empty.
    public var maintenanceStations: [MaintenanceStationSummary]
    public var maintenanceTasks: [MaintenanceTask]

    public init(installStations: [InstallStationSummary]? = nil, openStation: ((InstallStationSummary) -> Void)? = nil,
                openDailyReports: (() -> Void)? = nil, maintenanceStations: [MaintenanceStationSummary] = [],
                maintenanceTasks: [MaintenanceTask] = []) {
        self.installStations = installStations; self.openStation = openStation; self.openDailyReports = openDailyReports
        self.maintenanceStations = maintenanceStations; self.maintenanceTasks = maintenanceTasks
    }
}

private struct PWAOverviewKey: EnvironmentKey {
    static var defaultValue: PWAOverviewHost { PWAOverviewHost() }
}

public extension EnvironmentValues {
    var pwaOverview: PWAOverviewHost {
        get { self[PWAOverviewKey.self] }
        set { self[PWAOverviewKey.self] = newValue }
    }
}
#endif
