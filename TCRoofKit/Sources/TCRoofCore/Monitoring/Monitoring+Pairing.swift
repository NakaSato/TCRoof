import Foundation

extension Monitoring {
    /// `จับคู่สถานีกับ Plant ใน Growatt` (issue #259 §7): which of the server's plants a handed-over station is. The
    /// choice itself is `Settings.pairings` (station id → plant id) with `Settings.pairingServers` naming the server it
    /// was found on; this is the picker's side: the plants as rows, the search and the suggestion.
    public enum Pairing {
        /// One plant of `plant/list` as the picker shows it: name, size and city.
        public struct Plant: Identifiable, Hashable, Sendable {
            /// Growatt's `plant_id`, as text (the pairing's value).
            public var id: String
            public var name: String
            /// kWp; 0 when the plant doesn't say.
            public var kWp: Double
            public var city: String

            public init(id: String, name: String, kWp: Double, city: String = "") {
                self.id = id; self.name = name; self.kWp = kWp; self.city = city
            }

            public init(_ p: GrowattAPI.Plant) {
                self.init(id: String(p.id), name: p.name, kWp: p.peakPower, city: p.city)
            }

            /// `120 kWp · นครปฐม`, or what is known.
            public var detail: String {
                [kWp > 0 ? (kWp.rounded() == kWp ? String(format: "%.0f kWp", kWp) : String(format: "%.1f kWp", kWp)) : nil,
                 city.isEmpty ? nil : city].compactMap { $0 }.joined(separator: " · ")
            }
        }

        /// A plant's size counts as the station's when it is under this share of it away (the edge doesn't count: a
        /// 200 kWp station isn't offered its 180 and 220 kWp neighbours).
        public static let sizeTolerance = 0.10

        /// Words a station's name carries that a plant's rarely does: `สถานีผลิตน้ำสามพราน` is matched by `สามพราน`.
        static let stationPrefixes = ["สถานีผลิตน้ำ", "สถานีจ่ายน้ำ", "สถานีสูบน้ำ", "สถานี", "กปภ.สาขา", "กปภ.", "PWA"]

        /// The name's core for matching: lower case, no spaces, without the station words.
        static func core(_ name: String) -> String {
            var s = name.lowercased()
            for p in stationPrefixes { s = s.replacingOccurrences(of: p.lowercased(), with: "") }
            return s.filter { !$0.isWhitespace && $0 != "-" && $0 != "_" && $0 != "·" }
        }

        /// True when the plant's name carries the station's (either's core inside the other's, both at least two
        /// characters) or its size is under `sizeTolerance` from the station's kWp.
        public static func suggests(_ plant: Plant, station name: String, kWp: Double) -> Bool {
            matchesName(plant, station: name) || matchesSize(plant, kWp: kWp)
        }

        public static func matchesName(_ plant: Plant, station name: String) -> Bool {
            let a = core(plant.name), b = core(name)
            guard a.count >= 2, b.count >= 2 else { return false }
            return a.contains(b) || b.contains(a)
        }

        public static func matchesSize(_ plant: Plant, kWp: Double) -> Bool {
            guard kWp > 0, plant.kWp > 0 else { return false }
            return abs(plant.kWp - kWp) < kWp * sizeTolerance
        }

        /// The plants suggested for a station: those matching by name first (in the list's order), then by size.
        public static func suggest(station name: String, kWp: Double, in plants: [Plant]) -> [Plant] {
            plants.filter { matchesName($0, station: name) } + plants.filter { !matchesName($0, station: name) && matchesSize($0, kWp: kWp) }
        }

        /// The picker's order: the suggestions first, then the rest as the server lists them.
        public static func ordered(_ plants: [Plant], station name: String, kWp: Double) -> [Plant] {
            let top = suggest(station: name, kWp: kWp, in: plants)
            let ids = Set(top.map(\.id))
            return top + plants.filter { !ids.contains($0.id) }
        }

        /// The plants whose name, city or id carries the text; every plant for an empty search.
        public static func search(_ plants: [Plant], _ text: String) -> [Plant] {
            let q = text.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return plants }
            return plants.filter { $0.name.lowercased().contains(q) || $0.city.lowercased().contains(q) || $0.id.contains(q) }
        }

        /// Example plants for `-monitoringPairing YES` (no network): one near each of the board's six stations, the
        /// size of one off by a little, and two that belong to no station.
        public static func demoPlants() -> [Plant] {
            [Plant(id: "9001", name: "PWA สามพราน", kWp: 120, city: "นครปฐม"),
             Plant(id: "9002", name: "นครชัยศรี Solar", kWp: 220, city: "นครปฐม"),
             Plant(id: "9003", name: "กปภ. บางเลน", kWp: 180, city: "นครปฐม"),
             Plant(id: "9004", name: "Plant กำแพงแสน", kWp: 199.5, city: "นครปฐม"),
             Plant(id: "9005", name: "ดอนตูม PV", kWp: 95, city: "นครปฐม"),
             Plant(id: "9006", name: "พุทธมณฑล", kWp: 150, city: "นครปฐม"),
             Plant(id: "9007", name: "Test Plant 01", kWp: 5.2, city: "Bangkok"),
             Plant(id: "9008", name: "Growatt Demo", kWp: 30, city: "Shenzhen")]
        }
    }
}
