import Foundation
@_exported import GrowattAPI

extension GrowattAPI {

    /// A plant as a row of the `บำรุงรักษา` overview. Growatt gives no expected energy or PR, so both stay 0 (shown as a
    /// dash); a plant that has never reported is offline. `plant/list` says so with power -1, while `plant/data` gives
    /// the same plant 0, so -1 from either call wins.
    public static func summary(_ plant: Plant, data: PlantData? = nil) -> MaintenanceStationSummary {
        let offline = plant.currentPower < 0 || (data?.currentPower ?? 0) < 0
        let power = max(data?.currentPower ?? plant.currentPower, 0)
        let updated = data.map { String($0.lastUpdate.prefix(16)) } ?? ""
        let note = offline ? "Growatt | ไม่มีข้อมูล" + (updated.isEmpty ? "" : " ตั้งแต่ " + updated)
                           : "Growatt | " + String(format: power.rounded() == power ? "%.0f" : "%.1f", power) + " kW"
        return MaintenanceStationSummary(id: "growatt-\(plant.id)", name: plant.name, kWp: plant.peakPower,
                                         energy: data?.todayEnergy ?? 0, status: offline ? .offline : .normal, note: note,
                                         powerNow: offline ? nil : power,
                                         updated: data.map { String($0.lastUpdate.dropFirst(11).prefix(5)) } ?? "")
    }
}
