import Foundation

extension GrowattAPI {
    /// One plant of `plant/list` or `plant/user_plant_list`. `currentPower` is -1 when the plant has never reported.
    public struct Plant: Equatable, Sendable {
        public var id: Int
        public var name: String
        /// kWp.
        public var peakPower: Double
        /// kW.
        public var currentPower: Double
        /// kWh.
        public var totalEnergy: Double
        /// `status` isn't described in either PDF; kept as given.
        public var status: Int?
        public var city: String
        public var country: String
        public var latitude: Double?
        public var longitude: Double?
        public var userID: Int?
        /// `create_date`, as written.
        public var created: String
        public var installer: String

        public init(id: Int, name: String, peakPower: Double, currentPower: Double, totalEnergy: Double, status: Int?,
                    city: String, country: String, latitude: Double?, longitude: Double?, userID: Int? = nil,
                    created: String = "", installer: String = "") {
            self.id = id; self.name = name; self.peakPower = peakPower; self.currentPower = currentPower
            self.totalEnergy = totalEnergy; self.status = status; self.city = city; self.country = country
            self.latitude = latitude; self.longitude = longitude; self.userID = userID; self.created = created
            self.installer = installer
        }
    }

    /// `plant/data`: the plant's energy so far, kWh, and its power now, kW.
    public struct PlantData: Equatable, Sendable {
        public var todayEnergy: Double
        public var monthlyEnergy: Double
        public var yearlyEnergy: Double
        public var totalEnergy: Double
        public var currentPower: Double
        /// The plant's own clock (`timezone`, e.g. GMT+8), as Growatt writes it: `yyyy-MM-dd HH:mm:ss`.
        public var lastUpdate: String
        /// `GMT+8`, `GMT+7`: the zone `lastUpdate` (and `plant/power`'s times) are written in; empty when not given.
        public var timezone: String = ""
        /// `peak_power_actual`, kW; nil when not given.
        public var peakPowerActual: Double? = nil
        /// `carbon_offset`, tonnes of CO2; nil when not given.
        public var carbonOffset: Double? = nil

        public init(todayEnergy: Double, monthlyEnergy: Double, yearlyEnergy: Double, totalEnergy: Double,
                    currentPower: Double, lastUpdate: String, timezone: String = "", peakPowerActual: Double? = nil,
                    carbonOffset: Double? = nil) {
            self.todayEnergy = todayEnergy; self.monthlyEnergy = monthlyEnergy; self.yearlyEnergy = yearlyEnergy
            self.totalEnergy = totalEnergy; self.currentPower = currentPower; self.lastUpdate = lastUpdate
            self.timezone = timezone; self.peakPowerActual = peakPowerActual; self.carbonOffset = carbonOffset
        }
    }

    /// `plant/details`: the plant's settings. The answer carries more (its arrays and inverters as configured), kept
    /// in `fields`.
    public struct PlantDetails: Equatable, Sendable {
        public var name: String
        public var userID: Int?
        public var country: String
        public var city: String
        public var latitude: Double?
        public var longitude: Double?
        public var created: String
        /// kWp.
        public var peakPower: Double?
        public var currency: String
        public var timezone: String
        public var imageURL: String
        public var fields: [String: JSONValue]
    }

    /// One reading of `plant/power`: the plant's power at `time` (the plant's clock, `yyyy-MM-dd HH:mm`); nil when the
    /// slot has no value.
    public struct PowerPoint: Equatable, Sendable {
        public var time: String
        public var power: Double?

        public init(time: String, power: Double?) { self.time = time; self.power = power }
    }

    /// One row of `plant/energy`: the energy of a day (`yyyy-MM-dd`), month (`yyyy-MM`) or year, kWh; nil when not given.
    public struct EnergyPoint: Equatable, Sendable {
        public var date: String
        public var energy: Double?

        public init(date: String, energy: Double?) { self.date = date; self.energy = energy }
    }

    public enum EnergyUnit: String, Sendable { case day, month, year }

    // MARK: calls

    /// `plant/list`: the token's plants, at most 100 a page. `search` narrows them by name (`search_type=name`).
    public func plants(page: Int = 1, perPage: Int = 100, search: String? = nil) async throws -> [Plant] {
        try await plantPage(page: page, perPage: perPage, search: search).items
    }

    /// `plant/list` with its total count.
    public func plantPage(page: Int = 1, perPage: Int = 100, search: String? = nil) async throws -> Page<Plant> {
        var q = ["page": "\(max(page, 1))", "perpage": Self.perPage(perPage)]
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty { q["search_type"] = "name"; q["search_keyword"] = s }
        let data = try await get("plant/list", q)
        return Page(items: try Self.parsePlants(data), count: Self.count(data))
    }

    /// Every plant of the token, page after page (100 a page) until `count` is reached or a page comes back short.
    public func allPlants(maxPages: Int = 50) async throws -> [Plant] {
        var out: [Plant] = []
        for page in 1...max(maxPages, 1) {
            let p = try await plantPage(page: page, perPage: Self.maxPerPage)
            out += p.items
            if p.items.count < Self.maxPerPage || (p.count.map { out.count >= $0 } ?? false) { break }
        }
        return out
    }

    /// `plant/user_plant_list` (a POST in the guide): the plants of one end user's account, by its user name.
    public func userPlants(userName: String, page: Int = 1, perPage: Int = 100) async throws -> Page<Plant> {
        let data = try await post("plant/user_plant_list", ["user_name": userName, "page": "\(max(page, 1))", "perpage": Self.perPage(perPage)])
        return Page(items: try Self.parsePlants(data), count: Self.count(data))
    }

    /// `plant/details`: the plant's settings.
    public func details(plantID: Int) async throws -> PlantDetails {
        try Self.parseDetails(try await get("plant/details", ["plant_id": "\(plantID)"]))
    }

    /// `plant/data`: one plant's energy today, this month, this year and in all.
    public func data(plantID: Int) async throws -> PlantData {
        try Self.parseData(try await get("plant/data", ["plant_id": "\(plantID)"]))
    }

    /// `plant/power`: the plant's power through one day (`yyyy-MM-dd`, the plant's clock), every 5 minutes.
    public func power(plantID: Int, date: String) async throws -> [PowerPoint] {
        try Self.parsePower(try await get("plant/power", ["plant_id": "\(plantID)", "date": date]))
    }

    /// `plant/energy`: the plant's energy per day, month or year from `start` to `end` (`yyyy-MM-dd`). The guide
    /// limits the range (10004 past it): ask for days a week at a time.
    public func energy(plantID: Int, start: String, end: String, unit: EnergyUnit) async throws -> [EnergyPoint] {
        try Self.parseEnergy(try await get("plant/energy", ["plant_id": "\(plantID)", "start_date": start, "end_date": end,
                                                             "time_unit": unit.rawValue]))
    }

    // MARK: parsing

    /// `data.count`, nil when not given.
    static func count(_ data: Data) -> Int? { (try? body(data)).flatMap { number($0["count"]) }.map { Int($0) } }

    public static func parsePlants(_ data: Data) throws -> [Plant] {
        guard let rows = try body(data)["plants"] as? [[String: Any]] else { throw Failure.badResponse }
        return rows.compactMap { r in
            guard let id = number(r["plant_id"]) else { return nil }
            return Plant(id: Int(id), name: (r["name"] as? String) ?? "Plant \(Int(id))",
                         peakPower: number(r["peak_power"]) ?? 0, currentPower: number(r["current_power"]) ?? -1,
                         totalEnergy: number(r["total_energy"]) ?? 0, status: number(r["status"]).map { Int($0) },
                         city: (r["city"] as? String) ?? "", country: (r["country"] as? String) ?? "",
                         latitude: number(r["latitude"]), longitude: number(r["longitude"]),
                         userID: number(r["user_id"]).map { Int($0) }, created: (r["create_date"] as? String) ?? "",
                         installer: (r["installer"] as? String) ?? "")
        }
    }

    public static func parseDetails(_ data: Data) throws -> PlantDetails {
        let o = try dataObject(data)
        func t(_ k: String) -> String { o[k]?.text ?? "" }
        return PlantDetails(name: t("name"), userID: o["user_id"]?.int, country: t("country"), city: t("city"),
                            latitude: o["latitude"]?.number, longitude: o["longitude"]?.number, created: t("create_date"),
                            peakPower: o["peak_power"]?.number, currency: t("currency"), timezone: t("timezone"),
                            imageURL: t("image_url"), fields: o)
    }

    public static func parseData(_ data: Data) throws -> PlantData {
        let b = try body(data)
        return PlantData(todayEnergy: number(b["today_energy"]) ?? 0, monthlyEnergy: number(b["monthly_energy"]) ?? 0,
                         yearlyEnergy: number(b["yearly_energy"]) ?? 0, totalEnergy: number(b["total_energy"]) ?? 0,
                         currentPower: number(b["current_power"]) ?? -1, lastUpdate: (b["last_update_time"] as? String) ?? "",
                         timezone: (b["timezone"] as? String) ?? "", peakPowerActual: number(b["peak_power_actual"]),
                         carbonOffset: number(b["carbon_offset"]))
    }

    /// `data.powers`: `[{ time, power }]`, the day's readings in order; an unknown power is nil, never 0.
    public static func parsePower(_ data: Data) throws -> [PowerPoint] {
        guard let rows = try body(data)["powers"] as? [[String: Any]] else { throw Failure.badResponse }
        return rows.compactMap { r in
            guard let t = r["time"] as? String, !t.isEmpty else { return nil }
            return PowerPoint(time: t, power: number(r["power"]))
        }
    }

    /// `data.energys`: `[{ date, energy }]`.
    public static func parseEnergy(_ data: Data) throws -> [EnergyPoint] {
        guard let rows = try body(data)["energys"] as? [[String: Any]] else { throw Failure.badResponse }
        return rows.compactMap { r in
            guard let d = r["date"] as? String, !d.isEmpty else { return nil }
            return EnergyPoint(date: d, energy: number(r["energy"]))
        }
    }
}
