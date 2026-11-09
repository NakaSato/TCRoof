import Foundation

extension Monitoring {
    /// A station as the server's poll last read it (`monitoring/{station}`, CHA-93): the Cloud Function reads Growatt
    /// whether or not an iPad is open, and keeps each answer as Growatt wrote it, so the iPad maps it as it maps its own
    /// (`GrowattMap.station`). It reads the station's detail every `Settings.detailMinutes` (every `pollMinutes` while
    /// it is in alarm or offline) and the whole fleet's power every `pollMinutes` (`listPower`, from `plant/list`). An
    /// iPad polls Growatt itself only for a station whose server reading isn't `fresh` (the function not deployed yet,
    /// stopped, or without the token).
    public struct ServerReading: Equatable, Sendable {
        public var stationID: String
        public var plantID: Int
        /// When `plant/data` last came back; nil when it never has.
        public var readAt: Date?
        public var reading: GrowattReading
        /// Why the last poll couldn't read the plant, in the app's words (`GrowattAPI.Failure.message`).
        public var failure: String?
        /// The plant's power now from the fleet read (`plant/list`, kW; -1 never reported) and when it came; newer than
        /// `readAt` between detail reads. Already in `reading.data` when newer (see `init(fields:readAt:listAt:)`).
        public var listPower: Double?
        public var listAt: Date?

        public init(stationID: String, plantID: Int, readAt: Date?, reading: GrowattReading, failure: String? = nil) {
            self.stationID = stationID; self.plantID = plantID; self.readAt = readAt; self.reading = reading
            self.failure = failure
        }

        /// The document's fields (`readAt` and `listAt` already `Date`s): each answer's text parsed as `GrowattAPI` parses
        /// a reply, a part nil when it is missing or unreadable. A fleet power newer than `plant/data` stands in for
        /// its `current_power` (the power now), unless it says the plant never reported. Nil without a station id or plant.
        public init?(fields: [String: Any], readAt: Date?, listAt: Date? = nil) {
            guard let id = fields["stationID"] as? String, !id.isEmpty,
                  let plant = GrowattAPI.number(fields["plantID"]).map({ Int($0) }) else { return nil }
            func text(_ key: String) -> Data? { (fields[key] as? String).map { Data($0.utf8) } }
            var r = GrowattReading()
            r.data = text("data").flatMap { try? GrowattAPI.parseData($0) }
            r.power = text("power").flatMap { try? GrowattAPI.parsePower($0) }
            r.yesterdayPower = text("yesterdayPower").flatMap { try? GrowattAPI.parsePower($0) }
            r.devices = text("devices").flatMap { try? GrowattAPI.parseDevices($0) }
            r.days = text("days").flatMap { try? GrowattAPI.parseEnergy($0) }
            r.months = text("months").flatMap { try? GrowattAPI.parseEnergy($0) }
            let failure = (fields["failure"] as? [String: Any])?["message"] as? String
            let listPower = GrowattAPI.number(fields["listPower"])
            if let power = listPower, power >= 0, let at = listAt, at > (readAt ?? .distantPast), r.data != nil {
                r.data?.currentPower = power
            }
            self.init(stationID: id, plantID: plant, readAt: readAt, reading: r, failure: failure)
            self.listPower = listPower
            self.listAt = listAt
        }

        /// Whether this reading stands for the station: it is for the plant the station is paired with now, and
        /// `plant/data` came back within two detail reads and a minute (`detailMinutes`, `Settings.detailMinutes`; a
        /// station in alarm is read every poll, so sooner). Past that the iPad reads Growatt itself.
        public func fresh(now: Date, plantID: Int, detailMinutes: Int) -> Bool {
            guard plantID == self.plantID, let readAt else { return false }
            let every = max(detailMinutes, Monitoring.minimumPollMinutes)
            return now.timeIntervalSince(readAt) <= Double(2 * every * 60 + 60)
        }
    }
}
