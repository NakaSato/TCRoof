#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// DEBUG: the `บำรุงรักษา` overview also lists Growatt plants, to try it with live data. Nothing is saved.
/// - `-growattDemo YES`: the web portal's example plants (`GrowattWebDemo`, real home systems on a guest session).
/// - `-growattDemo test`: the OpenAPI test server's sample plants (`GrowattAPI.demo`), which never report.
/// - `-growattToken <token>`: the company's own plants from `openapi.growatt.com`. The token is only ever a launch
///   argument, never in the repo.
/// - The PWA settings' `นักพัฒนา` switch (`GrowattDemoSwitch`) keeps `growattDemo` on in the device's defaults, so the web
///   example plants show without launching from a Mac. A launch argument wins over it for that launch.
/// The plant list comes first, then each plant's figures: 1 s apart on the portal, 6 s on the OpenAPI, which refuses
/// calls closer together.
@MainActor @Observable
final class GrowattDemoFeed {
    enum Source {
        case web(GrowattWebDemo)
        case api(GrowattAPI)
    }

    static var enabled: Bool {
        #if DEBUG
        !demoFlag.isEmpty || !token.isEmpty
        #else
        false
        #endif
    }

    private static var demoFlag: String {
        let v = (UserDefaults.standard.string(forKey: "growattDemo") ?? "").lowercased()
        return ["", "no", "0", "false"].contains(v) ? "" : v
    }

    private static var token: String {
        (UserDefaults.standard.string(forKey: "growattToken") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `enabled` as last seen, so the overview redraws when the settings switch changes (`refresh`).
    private(set) var on = GrowattDemoFeed.enabled
    private(set) var stations: [MaintenanceStationSummary] = []
    private(set) var loading = false
    private(set) var failure: String?
    /// Plants listed whose figures are still being fetched: the overview draws them as skeleton rows.
    private(set) var pending: Set<String> = []
    private var loaded = false
    let source: Source = !token.isEmpty ? .api(.live(token: token)) : demoFlag == "test" ? .api(.demo) : .web(GrowattWebDemo())

    /// Where the rows come from, for the line under them.
    var sourceName: String {
        switch source {
        case .web: "สถานีตัวอย่างจากเว็บ Growatt"
        case .api(let a): a.isDemo ? "สถานีตัวอย่างจาก Growatt test server" : "สถานีจาก Growatt (openapi.growatt.com)"
        }
    }

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
            switch source {
            case .web(let web): try await loadWeb(web)
            case .api(let api): try await loadAPI(api)
            }
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
        for p in plants {
            let id = GrowattWebDemo.summary(id: p.id, name: p.name).id
            if let plant = try? await web.plant(id: p.id, name: p.name) {
                replace(GrowattWebDemo.summary(plant))
            } else {
                failed(id)
            }
            pending.remove(id)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func loadAPI(_ api: GrowattAPI) async throws {
        let plants = try await api.plants()
        stations = plants.map { GrowattAPI.summary($0) }
        loaded = true
        for p in plants {
            try await Task.sleep(nanoseconds: 6_000_000_000)
            // a plant whose data fails keeps its list row
            guard let d = try? await api.data(plantID: p.id) else { continue }
            replace(GrowattAPI.summary(p, data: d))
        }
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
        return .growatt(summary: s, plant: plant, day: day)
    }

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
