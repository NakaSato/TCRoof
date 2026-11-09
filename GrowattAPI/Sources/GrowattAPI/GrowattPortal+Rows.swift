import Foundation

/// Typed readings of the portal's rows, from live answers (a company account, 10 Nov 2026). Each keeps only what was
/// seen; the whole row stays in `GrowattPortal.Page.rows`.
extension GrowattPortal {
    /// One row of `selectPlant/getPlantList`.
    public struct PlantRow: Equatable, Sendable {
        public var id: String
        public var name: String
        /// `currentPac`: the plant's power now, as the portal writes it (its unit isn't confirmed).
        public var currentPac: Double?
        /// `eToday`: today's energy, kWh.
        public var eToday: Double?
        /// `onlineNum`: devices reporting.
        public var online: Int?
        public var plantType: Int?
        public var account: String
    }

    /// One event of `log/getNewPlantFaultLog`: `code` is the portal's (`Error 125`, `Warning 203(0)`), `name` its text
    /// (`PV Isolation Low`).
    public struct FaultEvent: Equatable, Sendable {
        public var id: String
        public var code: String
        public var name: String
        /// `eventType` 1; 0 is an error.
        public var isWarning: Bool
        public var deviceSN: String
        /// `MAX 80KTL3 LV`.
        public var deviceModel: String
        /// `MAX/MID/MAC`.
        public var deviceType: String
        public var alias: String
        public var plantID: String
        public var plantName: String
        /// When it happened, the plant's clock: `yyyy-MM-dd HH:mm:ss`.
        public var time: String
        /// When it cleared, as written; empty while it hasn't (`recoveryTime` null).
        public var recovered: String
        /// The portal's fix steps (`solution`, or `eventSolution`).
        public var solution: String
        /// `readFlag` 1: read on the portal.
        public var isRead: Bool

        /// The number in `code` (`125` of `Error 125`, `203` of `Warning 203(0)`), the app's `AlarmCatalog` key.
        public var number: String {
            let digits = code.drop { !$0.isNumber }.prefix { $0.isNumber }
            return String(digits)
        }
    }

    /// A device the Compare page offers: its chart `type` (`max`, `meter`, `env`), serial number (a meter or sensor:
    /// its logger and bus address, `DYDCE9302Z_36`), name on the page (`INVERTER 2`, `CHNT_THREE`, `ENV_DEVICE`), the
    /// portal's status (`-1` lost, `0`, `1`), its data logger, and a last figure whose meaning isn't known.
    public struct CompareDevice: Equatable, Sendable {
        public var type: String
        public var sn: String
        public var alias: String
        public var status: Int?
        public var datalogger: String
        public var extra: String

        /// This device's line for one of the page's values.
        public func series(_ param: ChartParam) -> ChartSeries { ChartSeries(type: type, sn: sn, params: param.name) }
    }

    // MARK: calls

    /// `energy/compare/getNewPlantDevices`, typed: every device of the plant, grouped as the portal answers (meters,
    /// inverters, sensors), each group's devices by serial number.
    public func compareDevices(plantID: String) async throws -> [CompareDevice] {
        try Self.parseCompareDevices(try await post("energy/compare/getNewPlantDevices", ["plantId": plantID]))
    }

    // MARK: parsing

    public static func plants(in page: Page) -> [PlantRow] {
        page.rows.compactMap { r in
            guard let id = r["id"]?.text, !id.isEmpty else { return nil }
            return PlantRow(id: id, name: r["plantName"]?.text ?? "", currentPac: r["currentPac"]?.number, eToday: r["eToday"]?.number,
                            online: r["onlineNum"]?.int, plantType: r["plantType"]?.int, account: r["accountName"]?.text ?? "")
        }
    }

    public static func faults(in page: Page) -> [FaultEvent] {
        page.rows.compactMap { r in
            guard let code = r["eventId"]?.text, !code.isEmpty else { return nil }
            func t(_ k: String) -> String { r[k]?.text ?? "" }
            return FaultEvent(id: t("id"), code: code, name: t("eventName"), isWarning: r["eventType"]?.int == 1,
                              deviceSN: r["deviceSn"]?.text ?? t("sn"), deviceModel: t("deviceModelName"), deviceType: t("deviceType"),
                              alias: t("alias"), plantID: t("plantId"), plantName: t("plantName"), time: t("time"),
                              recovered: t("recoveryTime"), solution: r["solution"]?.text ?? t("eventSolution"),
                              isRead: r["readFlag"]?.int == 1)
        }
    }

    /// `{ result: 1, obj: [ { deviceTypeName, devices: { <sn>: [[sn, alias, status, logger, logger, …]] } } ] }`.
    public static func parseCompareDevices(_ data: Data) throws -> [CompareDevice] {
        let page = try parsePage(data)
        return page.rows.flatMap { group -> [CompareDevice] in
            let type = group["deviceTypeName"]?.text ?? ""
            let devices = group["devices"]?.object ?? [:]
            return devices.keys.sorted().compactMap { key in
                let row = devices[key]?.array?.first?.array ?? []
                func at(_ i: Int) -> String { i < row.count ? (row[i].text ?? "") : "" }
                let sn = at(0).isEmpty ? key : at(0)
                return CompareDevice(type: type, sn: sn, alias: at(1), status: Int(at(2)), datalogger: at(3), extra: at(5))
            }
        }
    }
}
