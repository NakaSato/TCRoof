import Foundation

extension GrowattPortal {
    /// One value the Compare page charts for a device: its label on the page (`STRING VOLTAGE3`), the `params` name
    /// the chart calls send (`vString3`) and its unit. `confirmed` is true for names that answered on the live portal
    /// (captured from the page, or asked on a MAX inverter on 10 Nov 2026); the others follow the same pattern
    /// (`ppv1` answered, so `ppv2`…`ppv10`) and haven't been asked. A name the device doesn't have answers HTTP 500.
    public struct ChartParam: Hashable, Sendable {
        public var label: String
        public var name: String
        public var unit: String
        public var confirmed: Bool

        public init(label: String, name: String, unit: String, confirmed: Bool = false) {
            self.label = label; self.name = name; self.unit = unit; self.confirmed = confirmed
        }

        /// The names that answered on the live portal (10 Nov 2026).
        static let seen: Set<String> = ["pac", "ppv", "pacr", "pacs", "pact", "ppv1", "vpv1", "vString1", "vString2", "vString32",
                                        "vacrs", "vacs", "vact", "ipv1", "currentString1", "currentString32",
                                        "positiveActiveTodayEnergy", "power_factor", "env_temp", "panel_temp", "radiant",
                                        "sensorSingnalGen", "wind_angle"]

        /// A meter's energy taken from the grid today, kWh (the zero-export meter's `positiveActiveTodayEnergy`, seen in a
        /// captured request). Its label on the page isn't known.
        public static let meterImportToday = ChartParam(label: "POSITIVE ACTIVE TODAY ENERGY", name: "positiveActiveTodayEnergy",
                                                        unit: "kWh", confirmed: true)

        /// A meter's power factor (`power_factor`, seen in a captured request; note the underscore, unlike the inverter
        /// names). Its label on the page isn't known.
        public static let meterPowerFactor = ChartParam(label: "POWER FACTOR", name: "power_factor", unit: "", confirmed: true)

        /// The meter values seen so far; the meter's other values haven't been captured.
        public static let meter: [ChartParam] = [meterImportToday, meterPowerFactor]

        /// An environment sensor's air temperature, °C (`env_temp`, seen in a captured request; air, since the same sensor
        /// gives the module's as `panel_temp`).
        public static let envTemperature = ChartParam(label: "AMBIENT TEMPERATURE", name: "env_temp", unit: "°C", confirmed: true)

        /// An environment sensor's module temperature, °C (`panel_temp`, seen in a captured request).
        public static let panelTemperature = ChartParam(label: "PANEL TEMPERATURE", name: "panel_temp", unit: "°C", confirmed: true)

        /// An environment sensor's irradiance, W/m² (`radiant`, seen in a captured request). The unit is the sensor's
        /// usual one, not confirmed from an answer.
        public static let irradiance = ChartParam(label: "IRRADIANCE", name: "radiant", unit: "W/m²", confirmed: true)

        /// An environment sensor's `sensorSingnalGen` (Growatt's spelling, kept: the portal matches it exactly), seen in a
        /// captured request. What it measures and its unit aren't known (perhaps the sensor's raw signal).
        public static let sensorSignal = ChartParam(label: "SENSOR SIGNAL", name: "sensorSingnalGen", unit: "", confirmed: true)

        /// An environment sensor's wind direction, degrees (`wind_angle`, seen in a captured request; the unit is assumed).
        public static let windDirection = ChartParam(label: "WIND DIRECTION", name: "wind_angle", unit: "°", confirmed: true)

        /// The environment sensor values seen so far.
        public static let env: [ChartParam] = [envTemperature, panelTemperature, irradiance, sensorSignal, windDirection]

        /// A MAX / MID-X / MOD-X / MAC-X inverter's values, in the page's order: 10 MPPTs and 32 strings, as the page
        /// lists them for the team's MAX inverters.
        public static let maxInverter: [ChartParam] = {
            var p: [ChartParam] = [
                .init(label: "PAC", name: "pac", unit: "W"),
                .init(label: "MPPT POWER", name: "ppv", unit: "W"),
            ]
            for (phase, suffix) in [("R", "r"), ("S", "s"), ("T", "t")] {
                p.append(.init(label: "\(phase)-PHASE POWER", name: "pac\(suffix)", unit: "W"))
            }
            p += (1...10).map { .init(label: "MPPT\($0)POWER", name: "ppv\($0)", unit: "W") }
            p += (1...10).map { .init(label: "MPPT\($0)VOLTAGE", name: "vpv\($0)", unit: "V") }
            p += (1...32).map { .init(label: "STRING VOLTAGE\($0)", name: "vString\($0)", unit: "V") }
            // `vacr` answers HTTP 500 on a MAX; `vacrs` (R to S, about 416 V) does, while `vacs` and `vact` are about 240 V
            // phase voltages: which one the page's R-PHASE VOLTAGE sends isn't known
            p.append(.init(label: "R-PHASE VOLTAGE", name: "vacrs", unit: "V"))
            p.append(.init(label: "S-PHASE VOLTAGE", name: "vacs", unit: "V"))
            p.append(.init(label: "T-PHASE VOLTAGE", name: "vact", unit: "V"))
            p += (1...10).map { .init(label: "MPPT\($0)CURRENT", name: "ipv\($0)", unit: "A") }
            p += (1...32).map { .init(label: "STRING CURRENT\($0)", name: "currentString\($0)", unit: "A") }
            return p.map { var q = $0; q.confirmed = seen.contains(q.name); return q }
        }()

        /// The MAX value with this page label (`STRING VOLTAGE3`, case and spaces as the page or not: `mppt1 power`).
        public static func max(label: String) -> ChartParam? {
            let key = normalized(label)
            return maxInverter.first { normalized($0.label) == key }
        }

        static func normalized(_ s: String) -> String { s.uppercased().filter { !$0.isWhitespace } }
    }
}

extension GrowattPortal.ChartSeries {
    /// A device's line for one of the page's values: `.init(type: "max", sn: "GKLLEXC006", param: .max(label: "PAC")!)`.
    public init(type: String, sn: String, param: GrowattPortal.ChartParam) {
        self.init(type: type, sn: sn, params: param.name)
    }

    /// A meter's line (`type` `meter`). The portal names a meter by its data logger and its address on the logger's
    /// RS485 bus: `DYDCE9302Z_36` is address 36 on logger `DYDCE9302Z`.
    public static func meter(datalogger: String, address: Int, param: GrowattPortal.ChartParam = .meterImportToday) -> Self {
        .init(type: "meter", sn: "\(datalogger)_\(address)", params: param.name)
    }

    /// An environment sensor's line (`type` `env`), named like a meter: `DYDCE9302Z_6` is address 6 on logger
    /// `DYDCE9302Z`.
    public static func env(datalogger: String, address: Int, param: GrowattPortal.ChartParam = .envTemperature) -> Self {
        .init(type: "env", sn: "\(datalogger)_\(address)", params: param.name)
    }
}
