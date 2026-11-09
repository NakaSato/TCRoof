import Foundation

extension GrowattAPI {
    /// One alarm of `device/inverter/alarm` or `device/storage/alarm_data`. `code` is Growatt's as text: a number
    /// (`124`, `201`) or a bit name (`bit1`, in the guide's example). The times are as written: `yyyy-MM-dd HH:mm:ss.0`
    /// in the storage example, `2015-12-08T11:05:00Z` in the inverter one. `status` isn't described by the guide.
    public struct Alarm: Equatable, Sendable {
        public var code: String
        public var message: String
        public var start: String
        public var end: String
        public var status: Int?

        public init(code: String, message: String, start: String, end: String = "", status: Int? = nil) {
            self.code = code; self.message = message; self.start = start; self.end = end; self.status = status
        }
    }

    /// `device/inverter/data`: an inverter's readings over at most 7 days. `nextPageStartID` asks for the next page.
    public struct History: Equatable, Sendable {
        public var sn: String
        public var datalogger: String
        public var nextPageStartID: String?
        public var readings: [Readings]
    }

    /// One inverter's latest readings (`device/inverter/last_new_data`, or one of `invs_data`'s). The common fields
    /// are named; every field Growatt sent is in `readings` (`ppv1`, `vString3`, `warnCode`, …).
    public struct Latest: Equatable, Sendable {
        public var sn: String
        public var datalogger: String
        public var readings: Readings

        /// 0 waiting, 1 normal, 3 fault.
        public var status: Int? { readings["status"]?.int }
        /// W.
        public var power: Double? { readings.number("pac") }
        /// kWh.
        public var energyToday: Double? { readings.number("powerToday") }
        /// kWh.
        public var energyTotal: Double? { readings.number("powerTotal") }
        public var faultType: Int? { readings["faultType"]?.int }
        public var warnCode: Int? { readings["warnCode"]?.int }
        public var time: String { readings.time }
    }

    // MARK: calls

    /// `device/inverter/alarm`: an inverter's alarms by its serial number, at most 100 a page. The protocol PDF names
    /// the parameter `device_id`, the guide's example `device_sn`; the example's is sent.
    public func alarms(deviceSN: String, page: Int = 1, perPage: Int = 100) async throws -> Page<Alarm> {
        let data = try await get("device/inverter/alarm", ["device_sn": deviceSN, "page": "\(max(page, 1))", "perpage": Self.perPage(perPage)])
        return try Self.parseAlarms(data)
    }

    /// `device/inverter/data`: an inverter's readings from `start` to `end` (`yyyy-MM-dd`, at most 7 days apart),
    /// up to 1000 a page.
    public func inverterHistory(deviceSN: String, start: String, end: String, page: Int = 1, perPage: Int = 100) async throws -> History {
        try Self.parseHistory(try await get("device/inverter/data", ["device_sn": deviceSN, "start_date": start, "end_date": end,
                                                                    "page": "\(max(page, 1))", "perpage": Self.perPage(perPage, max: 1000)]))
    }

    /// `device/inverter/last_new_data`: an inverter's latest readings.
    public func latest(deviceSN: String) async throws -> Latest {
        try Self.parseLatest(try await get("device/inverter/last_new_data", ["device_sn": deviceSN]), sn: deviceSN)
    }

    /// `device/inverter/invs_data` (a POST in the guide): up to 100 inverters' latest readings at once, by serial
    /// number. The guide shows `inverters` as an array without saying how a form carries it; it is sent as a JSON
    /// array (`["SN1","SN2"]`), which is unconfirmed.
    public func latest(deviceSNs: [String], page: Int = 1) async throws -> [String: Latest] {
        let sns = Array(deviceSNs.prefix(100))
        let list = String(decoding: (try? JSONEncoder().encode(sns)) ?? Data("[]".utf8), as: UTF8.self)
        return try Self.parseLatestBatch(try await post("device/inverter/invs_data", ["pageNum": "\(max(page, 1))", "inverters": list]))
    }

    /// `device/inverter/inv_data_info`: an inverter's settings and state as the portal keeps them (`nominalPower`,
    /// `fwVersion`, `lost`, `status`, …).
    public func info(deviceSN: String) async throws -> Readings {
        Readings(fields: try Self.dataObject(try await get("device/inverter/inv_data_info", ["device_sn": deviceSN])))
    }

    // MARK: parsing

    /// `data.alarms` and `data.count`.
    public static func parseAlarms(_ data: Data) throws -> Page<Alarm> {
        let o = try dataObject(data)
        guard let rows = o["alarms"]?.array else { throw Failure.badResponse }
        let items = rows.compactMap { r -> Alarm? in
            guard r.object != nil else { return nil }
            return Alarm(code: r["alarm_code"]?.text ?? "", message: r["alarm_message"]?.text ?? "",
                         start: r["start_time"]?.text ?? "", end: r["end_time"]?.text ?? "", status: r["status"]?.int)
        }
        return Page(items: items, count: o["count"]?.int)
    }

    public static func parseHistory(_ data: Data) throws -> History {
        let o = try dataObject(data)
        guard let rows = o["datas"]?.array else { throw Failure.badResponse }
        return History(sn: o["sn"]?.text ?? o["storage_sn"]?.text ?? "", datalogger: o["datalogger_sn"]?.text ?? "",
                       nextPageStartID: o["next_page_start_id"]?.text,
                       readings: rows.compactMap { $0.object.map(Readings.init(fields:)) })
    }

    /// `{ device_sn, dataloggerSn, data: { … } }`.
    static func parseLatest(_ data: Data, sn: String) throws -> Latest {
        let doc = try document(data)
        guard let fields = doc["data"]?.object else { throw Failure.badResponse }
        return Latest(sn: doc["device_sn"]?.text ?? fields["inverterId"]?.text ?? sn,
                      datalogger: doc["dataloggerSn"]?.text ?? fields["dataloggerSn"]?.text ?? "",
                      readings: Readings(fields: fields))
    }

    /// `data: { <sn>: { dataloggerSn, <sn>: { … } } }`: each inverter's readings under its own serial number, twice.
    static func parseLatestBatch(_ data: Data) throws -> [String: Latest] {
        let o = try dataObject(data)
        var out: [String: Latest] = [:]
        for (sn, entry) in o {
            guard let e = entry.object else { continue }
            let fields = e[sn]?.object ?? e
            out[sn] = Latest(sn: sn, datalogger: e["dataloggerSn"]?.text ?? fields["dataloggerSn"]?.text ?? "",
                             readings: Readings(fields: fields))
        }
        return out
    }
}
