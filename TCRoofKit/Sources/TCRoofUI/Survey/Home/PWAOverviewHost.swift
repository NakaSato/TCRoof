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
    /// Handed-over stations. There is no monitoring feed yet, so a host gives them without energy or PR.
    public var maintenanceStations: [MaintenanceStationSummary]
    public var maintenanceTasks: [MaintenanceTask]
    /// Opens a handed-over station from its row of the maintenance overview.
    public var openMaintenanceStation: ((MaintenanceStationSummary) -> Void)?
    /// Hands one of `installStations` over to maintenance, by its id; `returnToInstall` undoes it.
    public var handOver: ((String) -> Void)?
    public var returnToInstall: ((String) -> Void)?
    /// Opens the `แผนงาน` page from the home's nav; nil leaves the segment out.
    public var openPlan: (() -> Void)?
    /// iPad: the plan page for the home to show under its nav, with `แผนงาน` selected, given the header's search
    /// text. Without it the segment calls `openPlan`.
    public var planBody: ((String) -> AnyView)?
    /// The header's bell: the unread count and the notifications screen. nil leaves the bell out.
    public var unread = 0
    public var openNotifications: (() -> Void)?
    /// `งานของฉัน`: the app jobs (`Job.jobSyncID`) that name the signed-in member, on their team, as supervisor or as an
    /// assigned external. nil leaves the filter out.
    public var mine: Set<String>?

    public init(installStations: [InstallStationSummary]? = nil, openStation: ((InstallStationSummary) -> Void)? = nil,
                openDailyReports: (() -> Void)? = nil, maintenanceStations: [MaintenanceStationSummary] = [],
                maintenanceTasks: [MaintenanceTask] = [], openMaintenanceStation: ((MaintenanceStationSummary) -> Void)? = nil,
                handOver: ((String) -> Void)? = nil, returnToInstall: ((String) -> Void)? = nil,
                openPlan: (() -> Void)? = nil, planBody: ((String) -> AnyView)? = nil, unread: Int = 0,
                openNotifications: (() -> Void)? = nil, mine: Set<String>? = nil) {
        self.planBody = planBody
        self.handOver = handOver; self.returnToInstall = returnToInstall
        self.installStations = installStations; self.openStation = openStation; self.openDailyReports = openDailyReports
        self.maintenanceStations = maintenanceStations; self.maintenanceTasks = maintenanceTasks
        self.openMaintenanceStation = openMaintenanceStation; self.openPlan = openPlan
        self.unread = unread; self.openNotifications = openNotifications
        self.mine = mine
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
