import Foundation

extension GrowattAPI {
    /// `device/storage/alarm_data` (a POST in the guide): a storage unit's alarms on one day (`yyyy-MM-dd`).
    public func storageAlarms(storageSN: String, date: String, page: Int = 1, perPage: Int = 100) async throws -> Page<Alarm> {
        try Self.parseAlarms(try await post("device/storage/alarm_data", ["storage_sn": storageSN, "date": date,
                                                                          "page": "\(max(page, 1))", "perpage": Self.perPage(perPage)]))
    }

    /// `device/storage/storage_last_data` (POST): a storage unit's latest readings (`status` 0 operating, 1 charge,
    /// 2 discharge, 3 fault, 4 flash; `capacity` %, `pCharge` / `pDischarge` W, …).
    public func storageLatest(storageSN: String) async throws -> Latest {
        try Self.parseLatest(try await post("device/storage/storage_last_data", ["storage_sn": storageSN]), sn: storageSN)
    }

    /// `device/storage/storage_data` (POST): a storage unit's readings from `start` to `end` (at most 7 days apart).
    public func storageHistory(storageSN: String, start: String, end: String, page: Int = 1, perPage: Int = 100) async throws -> History {
        try Self.parseHistory(try await post("device/storage/storage_data", ["storage_sn": storageSN, "start_date": start, "end_date": end,
                                                                            "page": "\(max(page, 1))", "perpage": Self.perPage(perPage, max: 1000)]))
    }
}
