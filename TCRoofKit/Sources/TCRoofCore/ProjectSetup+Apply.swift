import Foundation

/// Taking a plan file's project facts into a job (the import's `ตั้งค่าโครงการจากไฟล์`): each fact the file has and the
/// job doesn't already hold is a `Change`; one that fills an empty field is ticked by default, one that would replace
/// what the team typed is offered unticked.
extension ProjectSetup {
    /// The part of a job a plan file can set. The app reads it from its `Job` and writes it back after `apply`.
    public struct Target: Equatable, Sendable {
        public var stationName: String
        public var kWp: Double
        /// The job's customer, which a PWA station holds its branch in (`StationList` writes it so).
        public var customerName: String
        public var inverterKW: Double?
        public var station: StationDocs.Station
        public var routine: RoutineReport.Settings

        public init(stationName: String = "", kWp: Double = 0, customerName: String = "", inverterKW: Double? = nil,
                    station: StationDocs.Station = .init(), routine: RoutineReport.Settings = .init()) {
            self.stationName = stationName; self.kWp = kWp; self.customerName = customerName; self.inverterKW = inverterKW
            self.station = station; self.routine = routine
        }
    }

    public enum Field: String, CaseIterable, Identifiable, Sendable {
        case stationName, kWp, code, branch, area, peaZone, inverter, zeroExport, ppimRequest, engineer, admin, contractor
        case owner, locations

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .stationName: "ชื่อสถานี"
            case .kWp: "ขนาด"
            case .code: "รหัสสถานี"
            case .branch: "สาขา กปภ."
            case .area: "ภาค"
            case .peaZone: "กฟภ. ที่เชื่อมต่อ"
            case .inverter: "Inverter"
            case .zeroExport: "กันย้อน (Zero export)"
            case .ppimRequest: "เลขที่คำขอ PPIM"
            case .engineer: "วิศวกรหน้างาน"
            case .admin: "Admin"
            case .contractor: "ผู้รับเหมาช่วง"
            case .owner: "ผู้ว่าจ้าง (รายงานประจำ)"
            case .locations: "จุดติดตั้ง (รายงานประจำวัน)"
            }
        }
    }

    /// One fact the file would change.
    public struct Change: Identifiable, Equatable, Sendable {
        public var field: Field
        /// What the job holds now, as shown ("" when nothing).
        public var current: String
        public var proposed: String
        /// The job has nothing for it yet (or only the app's default): taking it loses nothing.
        public var fills: Bool

        public var id: String { field.rawValue }
    }

    /// The facts this file has that the job doesn't hold already, in the fields' order.
    public func changes(for t: Target) -> [Change] {
        Field.allCases.compactMap { f in
            guard let proposed = shown(f), !proposed.isEmpty else { return nil }
            let current = Self.shown(f, of: t)
            guard !same(f, as: t) else { return nil }
            let fills = current.isEmpty || (f == .owner && t.routine.employer == RoutineReport.Settings().employer)
            return Change(field: f, current: current, proposed: proposed, fills: fills)
        }
    }

    /// Writes the chosen facts into the target; a field the file has nothing for is left as it was.
    public func apply(_ fields: Set<Field>, to t: inout Target) {
        for f in Field.allCases where fields.contains(f) {
            switch f {
            case .stationName: if let stationName { t.stationName = stationName }
            case .kWp: if let kWp { t.kWp = kWp }
            case .code: if let code { t.station.code = code }
            case .branch:
                guard let branch else { break }
                t.customerName = branch
                t.station.branch = "สาขา" + Self.branchName(branch)
            case .area: if let area { t.station.area = area }
            case .peaZone: if let peaZone { t.station.peaZone = peaZone }
            case .inverter:
                if let inverterKW { t.inverterKW = inverterKW }
                // พค.2 follows the inverter size; the file's own word is kept only where the two disagree
                if let needsPK2 {
                    let bySize = (t.inverterKW ?? 0) >= 200
                    t.station.over200kVA = needsPK2 == bySize && t.inverterKW != nil ? nil : needsPK2
                }
            case .zeroExport: if let zeroExport { t.station.zeroExport = zeroExport }
            case .ppimRequest: if let ppimRequest { t.station.ppimRequest = ppimRequest }
            case .engineer: if let engineer { t.routine.siteEngineer = engineer }
            case .admin: if let admin { t.station.admin = admin }
            case .contractor: if let contractor { t.routine.subcontractor = contractor }
            case .owner: if let owner { t.routine.employer = owner }
            case .locations: if !points.isEmpty { t.routine.locations = locations }
            }
        }
    }

    /// What a job holds, as the facts its plan file's lines state: for export to write back (`rewrite`). A fact the job
    /// has nothing for stays nil, so the file keeps its own.
    public init(_ t: Target) {
        self.init()
        func text(_ s: String?) -> String? {
            guard let s = s.map(Self.clean), !s.isEmpty else { return nil }
            return s
        }
        code = text(t.station.code)
        stationName = text(t.stationName)
        kWp = t.kWp > 0 ? t.kWp : nil
        let branchName = Self.branchName(t.station.branch.isEmpty ? (t.customerName.contains("สาขา") ? t.customerName : "") : t.station.branch)
        branch = branchName.isEmpty ? nil : "กปภ.สาขา" + branchName
        area = text(t.station.area)
        peaZone = text(t.station.peaZone)
        inverterKW = t.inverterKW.flatMap { $0 > 0 ? $0 : nil }
        if let kw = inverterKW { needsPK2 = t.station.over200kVA ?? (kw >= 200) } else { needsPK2 = t.station.over200kVA }
        zeroExport = text(t.station.zeroExport)
        ppimRequest = text(t.station.ppimRequest)
        engineer = text(t.routine.siteEngineer)
        admin = text(t.station.admin)
        contractor = text(t.routine.subcontractor)
    }

    /// The fields worth ticking by default: the ones that only fill gaps.
    public static func defaultFields(_ changes: [Change]) -> Set<Field> { Set(changes.filter(\.fills).map(\.field)) }

    /// The file's value of a field as the list shows it; nil when the file has none.
    func shown(_ f: Field) -> String? {
        switch f {
        case .stationName: stationName
        case .kWp: kWp.map { Self.format($0) + " kWp" }
        case .code: code
        case .branch: branch
        case .area: area
        case .peaZone: peaZone
        case .inverter: inverterKW.map { kw in
            Self.format(kw) + " kW" + (needsPK2.map { $0 ? " | ต้องยื่น พค.2" : " | ไม่ต้องยื่น พค.2" } ?? "")
        }
        case .zeroExport: zeroExport
        case .ppimRequest: ppimRequest
        case .engineer: engineer
        case .admin: admin
        case .contractor: contractor
        case .owner: owner
        case .locations: points.isEmpty ? nil : locations.joined(separator: ", ")
        }
    }

    /// The job's value of a field as the list shows it.
    static func shown(_ f: Field, of t: Target) -> String {
        switch f {
        case .stationName: return clean(t.stationName)
        case .kWp: return t.kWp > 0 ? format(t.kWp) + " kWp" : ""
        case .code: return t.station.code ?? ""
        case .branch:
            if !t.station.branch.isEmpty { return t.station.branch }
            return t.customerName.contains("สาขา") ? t.customerName : ""
        case .area: return t.station.area ?? ""
        case .peaZone: return t.station.peaZone ?? ""
        case .inverter: return t.inverterKW.map { format($0) + " kW" } ?? ""
        case .zeroExport: return t.station.zeroExport ?? ""
        case .ppimRequest: return t.station.ppimRequest ?? ""
        case .engineer: return t.routine.siteEngineer
        case .admin: return t.station.admin ?? ""
        case .contractor: return t.routine.subcontractor
        case .owner: return t.routine.employer
        case .locations: return t.routine.locations.joined(separator: ", ")
        }
    }

    /// The job already holds what the file says.
    func same(_ f: Field, as t: Target) -> Bool {
        switch f {
        case .kWp: return kWp.map { abs($0 - t.kWp) < 0.005 } ?? true
        case .inverter:
            let kwSame = inverterKW.map { kw in t.inverterKW.map { abs($0 - kw) < 0.005 } ?? false } ?? true
            let pk2Same = needsPK2.map { $0 == (t.station.over200kVA ?? ((t.inverterKW ?? inverterKW ?? 0) >= 200)) } ?? true
            return kwSame && pk2Same
        case .branch:
            guard let branch else { return true }
            let mine = Self.shown(.branch, of: t)
            // both kept places agree with the file
            return !mine.isEmpty && Self.branchName(mine) == Self.branchName(branch)
                && Self.branchName(t.station.branch) == Self.branchName(branch)
                && Self.branchName(t.customerName) == Self.branchName(branch)
        case .locations: return points.isEmpty || t.routine.locations == locations
        default: return Self.clean(shown(f) ?? "") == Self.clean(Self.shown(f, of: t))
        }
    }
}
