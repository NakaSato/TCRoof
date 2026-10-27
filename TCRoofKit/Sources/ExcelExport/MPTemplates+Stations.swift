import Foundation

/// The 102 PWA stations' plan files (`PlanTemplates`) as stations to add to the app (`เพิ่มสถานีจากไฟล์แผน`,
/// `MPStationFilesSheet`): those no app station already is.
public extension MPTemplates {
    /// An app station as the check needs it.
    struct Existing: Sendable {
        public var name: String
        /// Every text the station keeps a code in (the job's code, the station code `P3-001`).
        public var codes: String
        public var kWp: Double?

        public init(name: String, codes: String, kWp: Double?) {
            self.name = name; self.codes = codes; self.kWp = kWp
        }
    }

    /// The files no station in `existing` is: a station naming a file's code is that file's; else one of the same name
    /// (`MPWorkbook.stationKey`) with its kWp within 5 % of the file's, or with no kWp when no other file shares the name
    /// (P4-001 and P4-031 are both `สถานีผลิตน้ำศูนย์ราชการ`: those need the kWp). In the files' order.
    static func missing(_ existing: [Existing], among cases: [Case]) -> [Case] {
        let keys = Dictionary(grouping: cases.map { MPWorkbook.stationKey($0.name) }, by: { $0 }).mapValues(\.count)
        return cases.filter { c in
            let code = c.id.uppercased(), key = MPWorkbook.stationKey(c.name)
            return !existing.contains { e in
                if e.codes.uppercased().contains(code) { return true }
                guard !key.isEmpty, MPWorkbook.stationKey(e.name) == key else { return false }
                if let a = e.kWp, a > 0, let b = c.kWp, b > 0 { return abs(a - b) <= 0.05 * b }
                return keys[key] == 1
            }
        }
    }
}
