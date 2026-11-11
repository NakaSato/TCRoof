#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// DEBUG demo: the `บำรุงรักษา` overview also lists Growatt's web portal example plants (`GrowattWebDemo`, real home
/// systems on a guest session), to try it without a paired station. Nothing is saved. Off unless asked for:
/// `-growattDemo YES`, or the PWA settings' `นักพัฒนา` switch (`GrowattDemoSwitch`), which keeps `growattDemo` on in the
/// device's defaults (a launch argument wins over it for that launch).
/// Real plants don't come through here: a handed-over station paired with its plant in ตั้งค่า Monitoring shows what
/// the Monitoring poll read from Growatt's OpenAPI (`GrowattAPI`, `MonitoringStore.maintenanceRow`).
/// What Growatt doesn't give (expected energy, PR, PM, repairs, modules) is sample data (`MaintenanceMock`).
/// The plant list comes first, then every plant's figures at once.
@MainActor @Observable
final class GrowattDemoFeed {
    static var enabled: Bool {
        #if DEBUG
        let v = (UserDefaults.standard.string(forKey: "growattDemo") ?? "").lowercased()
        return !["", "no", "0", "false"].contains(v)
        #else
        false
        #endif
    }

    /// `enabled` as last seen, so the overview redraws when the settings switch changes (`refresh`).
    private(set) var on = GrowattDemoFeed.enabled
    private(set) var stations: [MaintenanceStationSummary] = []
    private(set) var loading = false
    private(set) var failure: String?
    /// Plants listed whose figures are still being fetched: the overview draws them as skeleton rows.
    private(set) var pending: Set<String> = []
    private var loaded = false
    private let web = GrowattWebDemo()

    /// Where the rows come from, for the line under them.
    let sourceName = "สถานีตัวอย่างจากเว็บ Growatt"

    func isPending(_ id: String) -> Bool { pending.contains(id) }

    /// Picks up the settings switch: called when the device's defaults change.
    func refresh() {
        let e = Self.enabled
        if e != on { on = e }
    }

    func load(force: Bool = false) async {
        guard Self.enabled, !loading, force || !loaded else { return }
        loading = true; failure = nil
        defer { loading = false }
        do {
            try await loadWeb(web)
        } catch is CancellationError {
            // left before the figures were in: the next visit fetches again
            loaded = false
        } catch let f as GrowattAPI.Failure {
            failure = f.message
        } catch {
            failure = GrowattAPI.Failure.badResponse.message
        }
        pending = []
    }

    private func loadWeb(_ web: GrowattWebDemo) async throws {
        try await web.openGuest()
        let plants = try await web.plantList()
        stations = plants.map { GrowattWebDemo.summary(id: $0.id, name: $0.name) }
        pending = Set(stations.map(\.id))
        loaded = true
        // every plant at once, each row filled as it comes: one plant the portal is slow on mustn't hold up the rest
        await withTaskGroup(of: (String, MaintenanceStationSummary?).self) { group in
            for p in plants {
                group.addTask { (GrowattWebDemo.summary(id: p.id, name: p.name).id, await Self.webRow(web, id: p.id, name: p.name)) }
            }
            for await (id, row) in group {
                if let row { replace(Self.mocked(row)) }
                // a request cancelled with the load is no failure of the plant
                else if !Task.isCancelled { failed(id) }
                pending.remove(id)
            }
        }
        try Task.checkCancellation()
    }

    /// A plant's row with today's curve for the card's sparkline (on the plant's own date; the row shows without it).
    /// Nil when the plant's figures fail.
    nonisolated private static func webRow(_ web: GrowattWebDemo, id: String, name: String) async -> MaintenanceStationSummary? {
        guard let plant = try? await web.plant(id: id, name: name) else { return nil }
        var row = GrowattWebDemo.summary(plant)
        if let date = plant.devices.map(\.lastUpdate).max().map({ String($0.prefix(10)) }), !date.isEmpty,
           let day = try? await web.dayPower(plantID: id, date: date) {
            row.hourly = GrowattWebDemo.hourly(day)
        }
        return row
    }

    // MARK: station page

    /// A row of the web portal's example plants.
    static func isGrowatt(_ s: MaintenanceStationSummary) -> Bool { s.id.hasPrefix(webPrefix) }

    private static let webPrefix = "growatt-web-"

    /// The station page of an example plant: a guest session of its own, the plant's inverters, then its power through
    /// the plant's day (its own date, from the inverters' last update). Nil for other stations or when the portal fails,
    /// so the page keeps what it shows.
    static func detail(for s: MaintenanceStationSummary) async -> MaintenanceStationDetail? {
        guard enabled, isGrowatt(s) else { return nil }
        let web = GrowattWebDemo(), id = String(s.id.dropFirst(webPrefix.count))
        guard (try? await web.openGuest()) != nil, let plant = try? await web.plant(id: id, name: s.name) else { return nil }
        let date = plant.devices.map(\.lastUpdate).max().map { String($0.prefix(10)) } ?? ""
        let day = date.isEmpty ? [] : (try? await web.dayPower(plantID: id, date: date)) ?? []
        return MaintenanceMock.fill(.growatt(summary: s, plant: plant, day: day), seed: s.id)
    }

    /// Growatt gives no expected energy, PR, PM or repairs: the demo fills them (`MaintenanceMock`), the same for a plant
    /// every time, and keeps every figure Growatt gave.
    static func mocked(_ s: MaintenanceStationSummary) -> MaintenanceStationSummary { MaintenanceMock.fill(s, seed: s.id) }

    private func failed(_ id: String) {
        if let i = stations.firstIndex(where: { $0.id == id }) { stations[i].note = "Growatt | โหลดข้อมูลไม่ได้" }
    }

    private func replace(_ s: MaintenanceStationSummary) {
        if let i = stations.firstIndex(where: { $0.id == s.id }) { stations[i] = s }
    }
}

/// DEBUG: the PWA settings' switch for the Growatt example plants in `บำรุงรักษา` (`growattDemo` in the device's defaults).
struct GrowattDemoSwitch: View {
    @AppStorage("growattDemo") private var on = false

    var body: some View {
        TCSettingsRow("สถานีตัวอย่าง Growatt", detail: "แสดงสถานีตัวอย่างจากเว็บ Growatt ในหน้าบำรุงรักษา") {
            Toggle("สถานีตัวอย่าง Growatt", isOn: $on).labelsHidden().tint(Theme.success)
        }
    }
}
#endif
