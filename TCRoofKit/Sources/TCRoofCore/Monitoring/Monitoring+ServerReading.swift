import Foundation

extension Monitoring {
    /// A station as the server's poll last read it (`monitoring/{station}`, CHA-93): the Cloud Function reads Growatt
    /// every `pollMinutes` whether or not an iPad is open, and keeps each answer as Growatt wrote it, so the iPad maps it
    /// as it maps its own (`GrowattMap.station`). An iPad polls Growatt itself only for a station whose server reading
    /// isn't `fresh` (the function not deployed yet, stopped, or without the token).
    public struct ServerReading: Equatable, Sendable {
        public var stationID: String
        public var plantID: Int
        /// When `plant/data` last came back; nil when it never has.
        public var readAt: Date?
        public var reading: GrowattReading
        /// Why the last poll couldn't read the plant, in the app's words (`GrowattAPI.Failure.message`).
        public var failure: String?

        public init(stationID: String, plantID: Int, readAt: Date?, reading: GrowattReading, failure: String? = nil) {
            self.stationID = stationID; self.plantID = plantID; self.readAt = readAt; self.reading = reading
            self.failure = failure
        }

        /// The document's fields (`readAt` already a `Date`): each answer's text parsed as `GrowattAPI` parses a reply,
        /// a part nil when it is missing or unreadable. Nil without a station id or plant.
        public init?(fields: [String: Any], readAt: Date?) {
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
            self.init(stationID: id, plantID: plant, readAt: readAt, reading: r, failure: failure)
        }

        /// Whether this reading stands for the station: it is for the plant the station is paired with now, and
        /// `plant/data` came back within two polls and a minute (the function runs every 5 minutes, a station is due
        /// every `pollMinutes`). Past that the iPad reads Growatt itself.
        public func fresh(now: Date, plantID: Int, pollMinutes: Int) -> Bool {
            guard plantID == self.plantID, let readAt else { return false }
            let poll = max(pollMinutes, Monitoring.minimumPollMinutes)
            return now.timeIntervalSince(readAt) <= Double(2 * poll * 60 + 60)
        }
    }
}
