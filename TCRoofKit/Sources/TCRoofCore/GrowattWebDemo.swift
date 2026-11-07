import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Growatt's web portal example plants (`server.growatt.com/login/toViewExamlePlant`, the login page's demo link): a
/// guest session on a demo account whose plants are real home systems, names partly hidden. It reads them through the
/// portal's own calls, which Growatt doesn't document and may change, so this is for trying the maintenance overview
/// only; a company's stations go through the OpenAPI (`GrowattAPI`).
///
/// One `GrowattWebDemo` keeps its session's cookies: `openGuest()` first, then `plantList()` and `plant(_:)`.
public struct GrowattWebDemo: Sendable {
    public struct Device: Equatable, Sendable {
        public var sn: String
        public var model: String
        /// `tlx`, `mix`, `max`, …
        public var typeName: String
        /// The portal's status: 3 is a fault; -1 lost contact.
        public var status: Int?
        /// kWh.
        public var eToday: Double
        public var eMonth: Double
        public var eTotal: Double
        /// Power now, W.
        public var pac: Double
        /// W.
        public var nominalPower: Double
        /// The plant's own clock: `yyyy-MM-dd HH:mm:ss`.
        public var lastUpdate: String
        public var datalogger: String = ""
        /// e.g. `ShineWiLan-X2`.
        public var dataloggerType: String = ""

        /// The portal's status in Thai: 3 a fault, -1 lost contact, 0 waiting; the rest (1, and 5–8 on a hybrid) running.
        public var statusText: String {
            switch status {
            case 3: "Fault"
            case -1: "ออฟไลน์"
            case 0: "รอ"
            default: "ปกติ"
            }
        }
        public var isError: Bool { status == 3 || status == -1 }
    }

    public struct Plant: Equatable, Sendable {
        public var id: String
        public var name: String
        /// W; 0 when the plant gives none.
        public var nominalPower: Double
        /// kWh.
        public var eTotal: Double
        public var devices: [Device]
    }

    public var baseURL = URL(string: "https://server.growatt.com/")!
    public var timeout: TimeInterval = 25
    public let session: URLSession

    /// A session with its own cookies, so the guest login stays in it.
    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    // MARK: calls

    /// Opens the guest session on the demo account.
    public func openGuest() async throws {
        _ = try await send("login/toViewExamlePlant", post: false)
    }

    /// The demo account's plants: id and (hidden) name. The portal keeps two lists: the home dashboard's
    /// (`index/getPlantListTitle`, residential plants) and the business dashboard's (`indexbC/getPlantListTitle`,
    /// commercial ones); the ids of both work with `plant(id:name:)`. A failed business list leaves the home plants.
    public func plantList() async throws -> [(id: String, name: String)] {
        let home = try Self.parseList(try await send("index/getPlantListTitle"))
        let business = (try? Self.parseList(try await send("indexbC/getPlantListTitle"))) ?? []
        return Self.merged(home, business)
    }

    /// Both lists, each plant once, home plants first.
    static func merged(_ home: [(id: String, name: String)], _ business: [(id: String, name: String)]) -> [(id: String, name: String)] {
        var seen = Set<String>()
        return (home + business).filter { seen.insert($0.id).inserted }
    }

    /// One plant's totals and its devices.
    public func plant(id: String, name: String) async throws -> Plant {
        let info = try await send("panel/getPlantData", query: ["plantId": id])
        let devices = try await send("panel/getDevicesByPlantList", form: ["plantId": id, "currPage": "1"])
        return try Self.parsePlant(info, devices: devices, id: id, name: name)
    }

    /// The plant's power through a day (`yyyy-MM-dd`, the plant's own date): 288 samples 5 min apart, W; nil for times
    /// not reached yet.
    public func dayPower(plantID: String, date: String) async throws -> [Double?] {
        let json = #"[{"type":"plant","sn":"\#(plantID)","params":"pac"}]"#
        return try Self.parseDay(try await send("energy/compare/getDevicesDayChart", form: ["plantId": plantID, "date": date, "jsonData": json]))
    }

    func send(_ path: String, post: Bool = true, query: [String: String] = [:], form: [String: String] = [:]) async throws -> Data {
        var c = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: c.url!, timeoutInterval: timeout)
        if post {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            var body = URLComponents()
            body.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw GrowattAPI.Failure.offline }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw GrowattAPI.Failure.http(http.statusCode) }
        return data
    }

    // MARK: parsing

    static func parseList(_ data: Data) throws -> [(id: String, name: String)] {
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { throw GrowattAPI.Failure.badResponse }
        return rows.compactMap { r in
            guard let id = text(r["id"]), !id.isEmpty else { return nil }
            return (id, text(r["plantName"]) ?? "Plant \(id)")
        }
    }

    /// The portal answers `{ result: 1, obj: … }`; a page about logging in when the session is gone.
    static func object(_ data: Data) throws -> [String: Any] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              GrowattAPI.number(o["result"]) == 1, let obj = o["obj"] as? [String: Any] else { throw GrowattAPI.Failure.badResponse }
        return obj
    }

    static func parsePlant(_ info: Data, devices: Data, id: String, name: String) throws -> Plant {
        let p = try object(info)
        let rows = (try object(devices)["datas"] as? [[String: Any]]) ?? []
        let list = rows.map { d in
            Device(sn: text(d["sn"]) ?? "", model: text(d["deviceModel"]) ?? text(d["showDeviceModel"]) ?? "",
                   typeName: text(d["deviceTypeName"]) ?? "", status: GrowattAPI.number(d["status"]).map { Int($0) },
                   eToday: GrowattAPI.number(d["eToday"]) ?? 0, eMonth: GrowattAPI.number(d["eMonth"]) ?? 0,
                   eTotal: GrowattAPI.number(d["eTotal"]) ?? 0, pac: GrowattAPI.number(d["pac"]) ?? 0,
                   nominalPower: GrowattAPI.number(d["nominalPower"]) ?? 0, lastUpdate: text(d["lastUpdateTime"]) ?? "",
                   datalogger: text(d["datalogSn"]) ?? "", dataloggerType: text(d["datalogTypeTest"]) ?? "")
        }
        // the device list names the plant as the list does; getPlantData's name is hidden differently
        return Plant(id: id, name: name, nominalPower: GrowattAPI.number(p["nominalPower"]) ?? 0,
                     eTotal: GrowattAPI.number(p["eTotal"]) ?? 0, devices: list)
    }

    static func parseDay(_ data: Data) throws -> [Double?] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], GrowattAPI.number(o["result"]) == 1,
              let first = (o["obj"] as? [[String: Any]])?.first, let pac = (first["datas"] as? [String: Any])?["pac"] as? [Any]
        else { throw GrowattAPI.Failure.badResponse }
        return pac.map { GrowattAPI.number($0) }
    }

    /// The hours 06:00 … 18:00 of a day's 5-minute samples as the station page's 13 bars: each hour's mean, kW.
    public static func hourly(_ samples: [Double?], from first: Int = 6, count: Int = 13) -> [Double] {
        let perHour = 12
        return (first..<(first + count)).map { h in
            let slice = samples.dropFirst(h * perHour).prefix(perHour).compactMap { $0 }
            return slice.isEmpty ? 0 : slice.reduce(0, +) / Double(slice.count) / 1000
        }
    }

    static func text(_ v: Any?) -> String? {
        switch v {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        default: nil
        }
    }

    // MARK: overview

    /// The plant's row before its data is in: the name only.
    public static func summary(id: String, name: String) -> MaintenanceStationSummary {
        MaintenanceStationSummary(id: "growatt-web-\(id)", name: name, note: "Growatt | กำลังโหลด…")
    }

    /// A plant as a row of the `บำรุงรักษา` overview: kWp from the plant, else its inverters; today's energy and power
    /// now summed over them. A fault (3) is an alarm, lost contact (-1) or no inverter offline. No expected energy or PR.
    public static func summary(_ p: Plant) -> MaintenanceStationSummary {
        let kWp = (p.nominalPower > 0 ? p.nominalPower : p.devices.reduce(0) { $0 + $1.nominalPower }) / 1000
        let power = p.devices.reduce(0) { $0 + max($1.pac, 0) } / 1000
        let status: MaintenanceStationSummary.Status = p.devices.isEmpty || p.devices.allSatisfy { $0.status == -1 } ? .offline
            : p.devices.contains { $0.status == 3 } ? .alarm : .normal
        let updated = p.devices.map(\.lastUpdate).max().map { String($0.dropFirst(11).prefix(5)) } ?? ""
        let note = ["Growatt", String(format: "%.2f kW", power), updated.isEmpty ? "" : "อัปเดต " + updated]
            .filter { !$0.isEmpty }.joined(separator: " | ")
        return MaintenanceStationSummary(id: "growatt-web-\(p.id)", name: p.name, kWp: kWp,
                                         energy: p.devices.reduce(0) { $0 + $1.eToday }, status: status,
                                         openRepairs: 0, note: note)
    }
}

extension MaintenanceStationDetail {
    /// The station page of a Growatt example plant: its inverters, the day's hourly power and this month's energy. Growatt
    /// has no expected energy, PR, repairs or PM, so those stay empty; CO₂ is 0.5 kg per kWh, as the sample page counts it.
    /// Without `plant` (still loading) only the row's figures are shown.
    public static func growatt(summary: MaintenanceStationSummary, plant: GrowattWebDemo.Plant? = nil, day: [Double?] = []) -> MaintenanceStationDetail {
        let s = plant.map(GrowattWebDemo.summary) ?? summary
        let devices = plant?.devices ?? []
        let hourly = GrowattWebDemo.hourly(day)
        let month = devices.reduce(0) { $0 + $1.eMonth }
        let total = devices.reduce(0) { $0 + $1.eTotal }
        let inverters = devices.enumerated().map { i, d in
            InverterItem(id: d.sn.isEmpty ? "inv\(i)" : d.sn, name: "INV \(i + 1)",
                         model: [d.model, d.sn.isEmpty ? "" : "SN …" + d.sn.suffix(4)].filter { !$0.isEmpty }.joined(separator: " | "),
                         power: d.isError ? "—" : kW(d.pac / 1000), statusText: d.statusText, isError: d.isError)
        }
        var groups: [EquipmentGroup] = []
        if !devices.isEmpty {
            groups.append(EquipmentGroup(title: "อินเวอร์เตอร์", rows: devices.enumerated().map { i, d in
                EquipmentRow(key: "INV \(i + 1) | \(d.model)", value: d.statusText)
            }))
            let loggers = devices.filter { !$0.datalogger.isEmpty }
            if !loggers.isEmpty {
                groups.append(EquipmentGroup(title: "สื่อสาร", rows: loggers.map {
                    EquipmentRow(key: [$0.dataloggerType, $0.datalogger].filter { !$0.isEmpty }.joined(separator: " | "), value: "Growatt")
                }))
            }
        }
        let updated = devices.map(\.lastUpdate).max().map { String($0.dropFirst(11).prefix(5)) } ?? ""
        let issue: (String, String)? = switch s.status {
        case .alarm: ("อินเวอร์เตอร์แจ้ง Fault", "จาก Growatt | " + devices.filter { $0.status == 3 }.map(\.model).joined(separator: ", "))
        case .offline: ("สถานีออฟไลน์", "ไม่มีข้อมูลจาก Growatt")
        case .normal: nil
        }
        return MaintenanceStationDetail(
            summary: s, handoverDate: "—", contractor: "Growatt (ตัวอย่าง)", contractorShort: "Growatt", contractorPhone: "",
            issueTitle: issue?.0, issueSubtitle: issue?.1, ctaText: "แจ้งซ่อม / ออกใบงาน",
            expectedHourly: Array(repeating: 0, count: 13), actualHourly: hourly,
            hourlyMax: max(hourly.max() ?? 0, s.kWp * 0.8, 0.1), lastUpdated: updated.isEmpty ? "—" : updated,
            prToday: 0, prTarget: 80,
            energyThisMonth: kWh(month), energyExpectedThisMonth: "ทั้งหมด " + kWh(total),
            co2SavedThisMonth: month * 0.5 >= 1000 ? String(format: "%.1f t", month * 0.5 / 1000) : String(format: "%.0f kg", month * 0.5),
            inverters: inverters, tickets: [], nextPM: nil, pmHistory: [], equipmentGroups: groups)
    }

    private static func kW(_ v: Double) -> String { String(format: "%.2f kW", v) }

    private static func kWh(_ v: Double) -> String { v >= 1000 ? String(format: "%.1f MWh", v / 1000) : String(format: "%.1f kWh", v) }
}
