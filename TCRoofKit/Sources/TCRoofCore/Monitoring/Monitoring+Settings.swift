import Foundation

extension Monitoring {
    /// `ตั้งค่า Monitoring` (the board's dialog): where the readings come from, how often, what raises an alert, who
    /// hears it and the electricity rate. Managers edit it. A server's token is never kept here, only its last four
    /// characters to show; the token itself stays in the manager's Keychain.
    public struct Settings: Codable, Equatable, Sendable {
        public struct Server: Codable, Equatable, Identifiable, Sendable {
            public var id: UUID
            /// `Growatt · บัญชีเฟส 3`.
            public var name: String
            /// `https://openapi.growatt.com/v1/`.
            public var url: String
            /// The token's last four characters, for `Token •••• 3f2a`; empty without one.
            public var tokenSuffix: String
            /// Plants the token reached at the last test, and when it ran and whether it worked.
            public var plants: Int?
            public var testedAt: Date?
            public var testOK: Bool?

            public init(id: UUID = UUID(), name: String, url: String, tokenSuffix: String = "", plants: Int? = nil,
                        testedAt: Date? = nil, testOK: Bool? = nil) {
                self.id = id; self.name = name; self.url = url; self.tokenSuffix = tokenSuffix; self.plants = plants
                self.testedAt = testedAt; self.testOK = testOK
            }

            /// `openapi.growatt.com`.
            public var host: String { URL(string: url)?.host ?? url }

            /// The last four characters of a token, for `tokenSuffix`.
            public static func suffix(of token: String) -> String {
                String(token.trimmingCharacters(in: .whitespacesAndNewlines).suffix(4))
            }
        }

        public static let pollChoices = [5, 10, 15]
        public static let loggerChoices = [15, 30, 60]
        public static let stringChoices = [10, 20, 30]
        public static let belowExpectedChoices = [80, 85, 90]
        /// ฿/kWh until a manager sets the company's own (issue #259 decision 1): a PEA business rate with Ft.
        public static let defaultRate = 4.18
        public static let prChoices = [65, 70, 75]

        public var servers: [Server]
        /// Minutes between polls; never under `minimumPollMinutes`.
        public var pollMinutes: Int
        /// Keep the 5-minute readings every night (Growatt keeps them about 95 days).
        public var archiveNightly: Bool
        /// A logger silent this many minutes is offline.
        public var loggerOfflineMinutes: Int
        /// A string this many percent under its inverter's median for 30 minutes.
        public var stringLowPercent: Int
        /// A day under this percent of the forecast.
        public var belowExpectedPercent: Int
        /// PR under this percent (stations with an irradiance sensor only).
        public var prLowPercent: Int
        public var notifyMaintenance: Bool
        public var notifySupervisor: Bool
        public var notifyContractor: Bool
        /// Baht per kWh, for `มูลค่าไฟที่ผลิตได้`; nil until a manager picks one, and the value reads `—`.
        public var rate: Double?
        /// Station id → Growatt plant id.
        public var pairings: [String: String]
        /// Station id → the server (`Server.id`) its plant is read from; a pairing without one is read from the first
        /// server.
        public var pairingServers: [String: UUID]

        public init(servers: [Server] = [], pollMinutes: Int = 5, archiveNightly: Bool = true, loggerOfflineMinutes: Int = 30,
                    stringLowPercent: Int = 20, belowExpectedPercent: Int = 85, prLowPercent: Int = 70,
                    notifyMaintenance: Bool = true, notifySupervisor: Bool = true, notifyContractor: Bool = false,
                    rate: Double? = Settings.defaultRate, pairings: [String: String] = [:], pairingServers: [String: UUID] = [:]) {
            self.servers = servers; self.pollMinutes = max(pollMinutes, Monitoring.minimumPollMinutes)
            self.archiveNightly = archiveNightly; self.loggerOfflineMinutes = loggerOfflineMinutes
            self.stringLowPercent = stringLowPercent; self.belowExpectedPercent = belowExpectedPercent
            self.prLowPercent = prLowPercent; self.notifyMaintenance = notifyMaintenance
            self.notifySupervisor = notifySupervisor; self.notifyContractor = notifyContractor
            self.rate = rate; self.pairings = pairings; self.pairingServers = pairingServers
        }

        private enum CodingKeys: String, CodingKey {
            case servers, pollMinutes, archiveNightly, loggerOfflineMinutes, stringLowPercent, belowExpectedPercent
            case prLowPercent, notifyMaintenance, notifySupervisor, notifyContractor, rate, pairings, pairingServers
        }

        /// Every field optional, so a settings file from an older build still reads.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Settings()
            self.init(servers: try c.decodeIfPresent([Server].self, forKey: .servers) ?? d.servers,
                      pollMinutes: try c.decodeIfPresent(Int.self, forKey: .pollMinutes) ?? d.pollMinutes,
                      archiveNightly: try c.decodeIfPresent(Bool.self, forKey: .archiveNightly) ?? d.archiveNightly,
                      loggerOfflineMinutes: try c.decodeIfPresent(Int.self, forKey: .loggerOfflineMinutes) ?? d.loggerOfflineMinutes,
                      stringLowPercent: try c.decodeIfPresent(Int.self, forKey: .stringLowPercent) ?? d.stringLowPercent,
                      belowExpectedPercent: try c.decodeIfPresent(Int.self, forKey: .belowExpectedPercent) ?? d.belowExpectedPercent,
                      prLowPercent: try c.decodeIfPresent(Int.self, forKey: .prLowPercent) ?? d.prLowPercent,
                      notifyMaintenance: try c.decodeIfPresent(Bool.self, forKey: .notifyMaintenance) ?? d.notifyMaintenance,
                      notifySupervisor: try c.decodeIfPresent(Bool.self, forKey: .notifySupervisor) ?? d.notifySupervisor,
                      notifyContractor: try c.decodeIfPresent(Bool.self, forKey: .notifyContractor) ?? d.notifyContractor,
                      rate: try c.decodeIfPresent(Double.self, forKey: .rate) ?? d.rate,
                      pairings: try c.decodeIfPresent([String: String].self, forKey: .pairings) ?? d.pairings,
                      pairingServers: try c.decodeIfPresent([String: UUID].self, forKey: .pairingServers) ?? d.pairingServers)
        }

        /// The poll interval as used: one of the choices, never under Growatt's limit.
        public var pollInterval: TimeInterval { TimeInterval(max(pollMinutes, Monitoring.minimumPollMinutes) * 60) }

        /// `6/6 สถานีจับคู่กับ Plant ใน Growatt แล้ว`: how many of these stations are paired.
        public func paired(of stationIDs: [String]) -> Int { stationIDs.filter { pairings[$0] != nil }.count }

        /// The server a station's plant is read from: the one recorded for it, else the first; nil without servers.
        public func server(for stationID: String) -> Server? {
            if let id = pairingServers[stationID], let s = servers.first(where: { $0.id == id }) { return s }
            return servers.first
        }

        /// Pairs the station with a plant on a server (nil: the first server).
        public mutating func pair(_ stationID: String, plant plantID: String, server: UUID?) {
            pairings[stationID] = plantID
            pairingServers[stationID] = server
        }

        /// `เลิกจับคู่`.
        public mutating func unpair(_ stationID: String) {
            pairings[stationID] = nil
            pairingServers[stationID] = nil
        }

        /// A station's pairing: its plant and the server it is read from (`server(for:)`); nil when the station isn't
        /// paired, its plant id isn't a number, or there is no server to read it from.
        public func pairing(of stationID: String) -> (server: Server, plantID: Int)? {
            guard let raw = pairings[stationID], let plant = Int(raw.trimmingCharacters(in: .whitespaces)),
                  let server = server(for: stationID) else { return nil }
            return (server, plant)
        }
    }
}
