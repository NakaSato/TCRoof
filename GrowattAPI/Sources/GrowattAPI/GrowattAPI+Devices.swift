import Foundation

extension GrowattAPI {
    /// One device of `device/list`. Growatt's types: 1 inverter, 2 storage, 3 other equipment (a meter, a sensor),
    /// 4 MAX, 5 MIX / SPH, 6 SPA, 7 MIN / TLX, 8 PCS, 9 HPS, 10 PBD. `status` is the portal's: 0 waiting, 1 normal,
    /// 3 fault, -1 lost contact (`GrowattWebDemo.Device`); `lost` is the data logger's contact. Neither is confirmed
    /// against the guide for every type, so a status this doesn't know counts as running.
    public struct Device: Equatable, Sendable {
        public var sn: String
        public var type: Int?
        public var model: String
        public var status: Int?
        public var lost: Bool?
        /// The plant's clock, `yyyy-MM-dd HH:mm:ss`; empty when never.
        public var lastUpdate: String
        public var datalogger: String
        /// `device_id`, the guide's unique id; nil when not given.
        public var deviceID: Int?
        public var manufacturer: String

        public init(sn: String, type: Int? = nil, model: String = "", status: Int? = nil, lost: Bool? = nil,
                    lastUpdate: String = "", datalogger: String = "", deviceID: Int? = nil, manufacturer: String = "") {
            self.sn = sn; self.type = type; self.model = model; self.status = status; self.lost = lost
            self.lastUpdate = lastUpdate; self.datalogger = datalogger; self.deviceID = deviceID
            self.manufacturer = manufacturer
        }

        /// Anything but a battery (2) or other equipment (3); a type not given counts.
        public var isInverter: Bool { type.map { $0 != 2 && $0 != 3 } ?? true }
        public var isFault: Bool { status == 3 }
        public var isLost: Bool { lost == true || status == -1 }
        /// Reporting without a fault (a waiting inverter at night counts).
        public var isOnline: Bool { !isLost && !isFault }
    }

    /// One data logger (collector) of `device/datalogger/list`.
    public struct Datalogger: Equatable, Sendable {
        public var sn: String
        public var type: Int?
        public var manufacturer: String
        public var model: String
        /// As written; empty when never.
        public var lastUpdate: String

        public init(sn: String, type: Int? = nil, manufacturer: String = "", model: String = "", lastUpdate: String = "") {
            self.sn = sn; self.type = type; self.manufacturer = manufacturer; self.model = model; self.lastUpdate = lastUpdate
        }
    }

    // MARK: calls

    /// `device/list`: the plant's devices (inverters, loggers' contact, their status), at most 100 a page.
    public func devices(plantID: Int, page: Int = 1, perPage: Int = 100) async throws -> [Device] {
        try await devicePage(plantID: plantID, page: page, perPage: perPage).items
    }

    /// `device/list` with its total count.
    public func devicePage(plantID: Int, page: Int = 1, perPage: Int = 100) async throws -> Page<Device> {
        let data = try await get("device/list", ["plant_id": "\(plantID)", "page": "\(max(page, 1))", "perpage": Self.perPage(perPage)])
        return Page(items: try Self.parseDevices(data), count: Self.count(data))
    }

    /// `device/datalogger/list`: the plant's data loggers.
    public func dataloggers(plantID: Int, page: Int = 1, perPage: Int = 100) async throws -> Page<Datalogger> {
        let data = try await get("device/datalogger/list", ["plant_id": "\(plantID)", "page": "\(max(page, 1))",
                                                            "perpage": Self.perPage(perPage)])
        return Page(items: try Self.parseDataloggers(data), count: Self.count(data))
    }

    // MARK: parsing

    /// `data.devices`: one per device; a row without a serial number is skipped.
    public static func parseDevices(_ data: Data) throws -> [Device] {
        guard let rows = try body(data)["devices"] as? [[String: Any]] else { throw Failure.badResponse }
        return rows.compactMap { r in
            guard let sn = r["device_sn"] as? String, !sn.isEmpty else { return nil }
            return Device(sn: sn, type: number(r["type"]).map { Int($0) }, model: (r["model"] as? String) ?? "",
                          status: number(r["status"]).map { Int($0) }, lost: bool(r["lost"]),
                          lastUpdate: (r["last_update_time"] as? String) ?? "", datalogger: (r["datalogger_sn"] as? String) ?? "",
                          deviceID: number(r["device_id"]).map { Int($0) }, manufacturer: (r["manufacturer"] as? String) ?? "")
        }
    }

    /// `data.dataloggers`; a row without a serial number is skipped.
    public static func parseDataloggers(_ data: Data) throws -> [Datalogger] {
        guard let rows = try dataObject(data)["dataloggers"]?.array else { throw Failure.badResponse }
        return rows.compactMap { r in
            guard let sn = r["sn"]?.text, !sn.isEmpty else { return nil }
            return Datalogger(sn: sn, type: r["type"]?.int, manufacturer: r["manufacturer"]?.text ?? "",
                              model: r["model"]?.text ?? "", lastUpdate: r["last_update_time"]?.text ?? "")
        }
    }
}
