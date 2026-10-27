import Foundation

/// The lists the iPad A3 page offers in its menus (docs/ui/survey-a3-ipad-v3, `assets/sample-data.json`).
/// They are the board's examples, still to be confirmed with the team (CLAUDE_CODE_TASK.md §6 Q2); every menu
/// also takes a typed value, so a value missing here can still be entered.
public enum A3Options {
    // transformer nameplate
    public static let transformerVoltages = ["22k/230-400", "33k/230-400", "24k/230-400", "12k/230-400", "11k/230-400"]
    public static let vectorGroups = ["Dyn11", "Dyn1", "Dyn5", "YNyn0", "Dd0"]
    public static let impedances = ["4", "6"]
    public static let transformerBrands = ["Tirathai", "QTC", "Charoenchai (CTE)", "ABB", "Siemens", "Kyowa"]

    /// ปีผลิต: this year in the Buddhist era, then the `count - 1` years before it.
    public static func years(now: Date = Date(), count: Int = 30) -> [String] {
        let year = Calendar(identifier: .buddhist).component(.year, from: now)
        return (0..<count).map { String(year - $0) }
    }

    // MDB main breaker
    public static let mainAT = ["100", "125", "160", "200", "225", "250", "300", "320", "400", "500", "630", "700", "800",
                                "1000", "1250", "1600", "2000", "2500", "3200", "4000"]
    public static let mainAF = ["100", "125", "160", "250", "400", "630", "800", "1000", "1250", "1600", "2000", "2500", "3200", "4000"]
    public static let mainIcu = ["25", "36", "42", "50", "65", "70", "85", "100", "150"]
    public static let breakerBrands = ["Schneider", "ABB", "Siemens", "Mitsubishi", "LS", "Eaton", "Hitachi", "Fuji"]

    // outgoing breakers (CB ลูกย่อย)
    public static let subAT = ["16", "20", "25", "32", "40", "50", "63", "80", "100", "125", "160", "200", "225", "250", "300",
                               "320", "400", "500", "630", "800"]
    public static let subAF = ["63", "100", "125", "160", "250", "400", "630", "800"]
    public static let subIcu = ["10", "15", "18", "25", "36", "42", "50", "65", "70", "85", "100"]

    // meter
    /// A low-voltage meter's sizes; `meterCT` stands for a CT-connected meter, whose ratio is typed instead.
    public static let meterSizes = ["15(45) A", "30(100) A", "50(150) A"]
    public static let meterCT = "CT"
    /// The meter kV with no transformer (A3 then feeds the boards straight from the meter).
    public static let lowVoltageKV = "0.4"

    /// AF อัตโนมัติ: the smallest frame in `frames` at or above the trip `at`; nil when `at` isn't a number or is above
    /// every frame. Shown as a suggestion only: the breaker's `af` stays empty until a frame is picked.
    public static func autoAF(at: String, frames: [String]) -> String? {
        guard let a = Double(at.trimmingCharacters(in: .whitespaces)), a > 0 else { return nil }
        return frames.compactMap { f in Double(f).map { (f, $0) } }.filter { $0.1 >= a }.min { $0.1 < $1.1 }?.0
    }
}

/// Standard nameplate values for a transformer size, filled into a transformer's empty fields when its size is picked
/// (docs/ui/survey-a3-ipad-v3 §4.2). The board's values: 22 kV (or 33 kV, following the meter) to 230/400 V, Dyn11,
/// %Z 4 up to 630 kVA and 6 above (§6 Q1).
public enum TransformerStandard {
    public struct Values: Equatable, Sendable {
        public var voltage: String
        public var vectorGroup: String
        public var impedance: String
    }

    /// The low-voltage side's line voltage (V) used for `lvCurrent`.
    public static let lowVoltage = 400.0

    /// nil when `kva` isn't a positive number.
    public static func values(kva: String, meterKV: String = "") -> Values? {
        guard let k = number(kva), k > 0 else { return nil }
        let hv = meterKV.trimmingCharacters(in: .whitespaces) == "33" ? "33k/230-400" : "22k/230-400"
        return Values(voltage: hv, vectorGroup: "Dyn11", impedance: k <= 630 ? "4" : "6")
    }

    /// Rated low-voltage current, kVA × 1000 / (√3 × 400), rounded to the ampere.
    public static func lvCurrent(kva: Double) -> Int {
        Int((kva * 1000 / (3.0.squareRoot() * lowVoltage)).rounded())
    }

    /// `lvCurrent` for a kVA as typed; nil when it isn't a positive number.
    public static func lvCurrent(kva: String) -> Int? {
        guard let k = number(kva), k > 0 else { return nil }
        return lvCurrent(kva: k)
    }

    static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ""))
    }
}
