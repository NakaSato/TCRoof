import Foundation
import TCRoofCore

extension Job {
    /// The id the install overview knows this station by: the one its survey reports link to.
    var overviewID: String { syncID ?? code }

    var sentDailyReportToday: Bool { dailyLog(on: .now)?.engineerSignedAt != nil }

    /// This handed-over station for the maintenance overview, before Growatt's figures (`MonitoringStore.maintenanceRow`
    /// adds them for a paired station): no energy or PR.
    var maintenanceSummary: MaintenanceStationSummary {
        MaintenanceStationSummary(id: overviewID, mpNumber: mpNumber, name: projectName, kWp: capacityKW, status: .normal,
                                  note: "ยังไม่มีข้อมูลการผลิต")
    }

    /// Papers signed and not yet sent, over the station's packages.
    var papersWaitingToSend: Int {
        papersWaitingToSend(library: StationDocsStore.loadLibrary())
    }

    func papersWaitingToSend(library: StationDocs.Library) -> Int {
        let station = stationDocs
        let ctx = StationDocs.Context(station, inverterKW: inverterKW ?? (scheduleInput?.over200kVA == true ? 200 : nil))
        let kinds = Set(StationDocs.packages(ctx).flatMap { StationDocs.papers(in: $0, ctx).map(\.id) })
        return kinds.compactMap(StationDocs.kind).filter { StationDocs.state($0, station: station, library: library).status == .signed }.count
    }
}
