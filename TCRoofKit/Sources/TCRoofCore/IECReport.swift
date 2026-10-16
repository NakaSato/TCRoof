import Foundation

/// One station's IEC 62446 test before and after the grid connection (docs/specs/iec62446-excel-export-swift.md §2,
/// docs/forms/iec62446-pwa): per inverter 20 string slots in Excel order (10 MPPT × 2), the checks, the 7-day energy and
/// the test conditions. Stored on the job as JSON; every field decodes with a default so older reports keep loading.
/// Calculated values (kWp, Yf, PR, efficiency, the IR summary) are never stored, only derived.
public struct IECReport: Codable, Equatable, Sendable {
    public enum Check: String, Codable, Sendable { case normal, abnormal }
    public enum Phase: String, Codable, CaseIterable, Sendable { case before, after }

    /// A photo of one string; the value kept per kind is the stored photo's id.
    public enum PhotoKind: String, Codable, CaseIterable, Sendable {
        case voltageBefore, currentBefore, voltageAfter, currentAfter, insulation
    }

    public struct Module: Codable, Equatable, Sendable {
        public var brand = ""
        public var powerW: Double = 0
        /// From the datasheet; needed for the system efficiency.
        public var areaM2: Double?
        public init(brand: String = "", powerW: Double = 0, areaM2: Double? = nil) { self.brand = brand; self.powerW = powerW; self.areaM2 = areaM2 }
        enum CodingKeys: String, CodingKey { case brand, powerW, areaM2 }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
            powerW = try c.decodeIfPresent(Double.self, forKey: .powerW) ?? 0
            areaM2 = try c.decodeIfPresent(Double.self, forKey: .areaM2)
        }
    }

    /// The weather when a phase was tested (rows 29–30 of the sheet).
    public struct Conditions: Codable, Equatable, Sendable {
        public var ambientC: Double?
        public var irradianceWm2: Double?
        /// `HH:mm`.
        public var time: String?
        public init(ambientC: Double? = nil, irradianceWm2: Double? = nil, time: String? = nil) {
            self.ambientC = ambientC; self.irradianceWm2 = irradianceWm2; self.time = time
        }
        public var isComplete: Bool { ambientC != nil && irradianceWm2 != nil && !(time ?? "").isEmpty }
    }

    /// Serials of the instruments used; the original form has none (its README §4 item 5).
    public struct Instruments: Codable, Equatable, Sendable {
        public var multimeterClamp = ""
        public var insulationTester = ""
        public var irradianceMeter = ""
        public var thermalCamera = ""
        public init() {}
        enum CodingKeys: String, CodingKey { case multimeterClamp, insulationTester, irradianceMeter, thermalCamera }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            multimeterClamp = try c.decodeIfPresent(String.self, forKey: .multimeterClamp) ?? ""
            insulationTester = try c.decodeIfPresent(String.self, forKey: .insulationTester) ?? ""
            irradianceMeter = try c.decodeIfPresent(String.self, forKey: .irradianceMeter) ?? ""
            thermalCamera = try c.decodeIfPresent(String.self, forKey: .thermalCamera) ?? ""
        }
        public var isComplete: Bool { ![multimeterClamp, insulationTester, irradianceMeter].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    /// One string in its Excel column. Before the connection: Voc and 0 A; after: Vmp and Imp.
    public struct Slot: Codable, Equatable, Sendable {
        public var brand: String?
        public var modules: Int
        public var optimizers: Int?
        public var polarityOK: Bool?
        /// The polarity was set on the ✓ / ✗ segment, so a Voc typed later doesn't set it from its sign (step 2).
        public var polarityByHand: Bool?
        public var irTestV: Int?
        public var irPosMOhm: Double?
        public var irNegMOhm: Double?
        public var vocV: Double?
        public var iBeforeA: Double?
        public var vmpV: Double?
        public var impA: Double?
        /// `PhotoKind` raw value → stored photo id.
        public var photos: [String: String]

        public init(modules: Int, brand: String? = nil, optimizers: Int? = nil, polarityOK: Bool? = nil, irTestV: Int? = 1000,
                    irPosMOhm: Double? = nil, irNegMOhm: Double? = nil, vocV: Double? = nil, iBeforeA: Double? = nil,
                    vmpV: Double? = nil, impA: Double? = nil, photos: [String: String] = [:]) {
            self.modules = modules; self.brand = brand; self.optimizers = optimizers; self.polarityOK = polarityOK
            self.irTestV = irTestV; self.irPosMOhm = irPosMOhm; self.irNegMOhm = irNegMOhm; self.vocV = vocV
            self.iBeforeA = iBeforeA; self.vmpV = vmpV; self.impA = impA; self.photos = photos
        }

        enum CodingKeys: String, CodingKey {
            case brand, modules, optimizers, polarityOK, irTestV, irPosMOhm, irNegMOhm, vocV, iBeforeA, vmpV, impA, photos
            case polarityByHand
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            brand = try c.decodeIfPresent(String.self, forKey: .brand)
            modules = try c.decodeIfPresent(Int.self, forKey: .modules) ?? 0
            optimizers = try c.decodeIfPresent(Int.self, forKey: .optimizers)
            polarityOK = try c.decodeIfPresent(Bool.self, forKey: .polarityOK)
            irTestV = try c.decodeIfPresent(Int.self, forKey: .irTestV)
            irPosMOhm = try c.decodeIfPresent(Double.self, forKey: .irPosMOhm)
            irNegMOhm = try c.decodeIfPresent(Double.self, forKey: .irNegMOhm)
            vocV = try c.decodeIfPresent(Double.self, forKey: .vocV)
            iBeforeA = try c.decodeIfPresent(Double.self, forKey: .iBeforeA)
            vmpV = try c.decodeIfPresent(Double.self, forKey: .vmpV)
            impA = try c.decodeIfPresent(Double.self, forKey: .impA)
            photos = try c.decodeIfPresent([String: String].self, forKey: .photos) ?? [:]
            polarityByHand = try c.decodeIfPresent(Bool.self, forKey: .polarityByHand)
        }

        public func photo(_ kind: PhotoKind) -> String? { photos[kind.rawValue] }

        /// Both IR readings in, the lower one at least 1 MΩ (IEC 62446-1 for systems over 500 V tested at 1000 V).
        public var irPass: Bool? {
            guard let p = irPosMOhm, let n = irNegMOhm else { return nil }
            return min(p, n) >= IECReport.irMinimumMOhm
        }
    }

    public struct Inverter: Codable, Equatable, Sendable {
        public var ratedKW: Double
        public var serial: String
        /// Exactly `slotCount`: slot n is Excel column E + n − 1; nil = no string there.
        public var slots: [Slot?]
        public var continuity: Check?
        public var functionalBefore: Check?
        public var functionalAfter: Check?
        public var energy7dKWh: Double?
        public var remark: String
        /// From the add-inverter sheet (step 1): the model, its MPPT count (slots = MPPT × 2; nil = the sheet's 10)
        /// and its photos by `InverterPhoto` raw value. None of them has an Excel cell.
        public var model: String?
        public var mppt: Int?
        public var photos: [String: String] = [:]

        public init(ratedKW: Double = 0, serial: String = "", slots: [Slot?] = Array(repeating: nil, count: IECReport.slotCount),
                    continuity: Check? = nil, functionalBefore: Check? = nil, functionalAfter: Check? = nil,
                    energy7dKWh: Double? = nil, remark: String = "") {
            self.ratedKW = ratedKW; self.serial = serial; self.slots = IECReport.padded(slots)
            self.continuity = continuity; self.functionalBefore = functionalBefore; self.functionalAfter = functionalAfter
            self.energy7dKWh = energy7dKWh; self.remark = remark
        }

        enum CodingKeys: String, CodingKey { case ratedKW, serial, slots, continuity, functionalBefore, functionalAfter, energy7dKWh, remark, model, mppt, photos }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ratedKW = try c.decodeIfPresent(Double.self, forKey: .ratedKW) ?? 0
            serial = try c.decodeIfPresent(String.self, forKey: .serial) ?? ""
            slots = IECReport.padded(try c.decodeIfPresent([Slot?].self, forKey: .slots) ?? [])
            continuity = try c.decodeIfPresent(Check.self, forKey: .continuity)
            functionalBefore = try c.decodeIfPresent(Check.self, forKey: .functionalBefore)
            functionalAfter = try c.decodeIfPresent(Check.self, forKey: .functionalAfter)
            energy7dKWh = try c.decodeIfPresent(Double.self, forKey: .energy7dKWh)
            remark = try c.decodeIfPresent(String.self, forKey: .remark) ?? ""
            model = try c.decodeIfPresent(String.self, forKey: .model)
            mppt = try c.decodeIfPresent(Int.self, forKey: .mppt)
            photos = try c.decodeIfPresent([String: String].self, forKey: .photos) ?? [:]
        }

        /// MPPTs on the sheet: the model's, or all 10 when it isn't known.
        public var mpptCount: Int { min(max(mppt ?? IECReport.slotCount / 2, 1), IECReport.slotCount / 2) }
        /// The slots this inverter has, MPPT × 2 (slots past them stay empty).
        public var slotsInUse: Int { mpptCount * 2 }

        /// The used slots with their 1-based slot number and the Word label's sequence (`INV{i}ST{seq}`).
        public var strings: [(slot: Int, seq: Int, value: Slot)] {
            var seq = 0
            return slots.enumerated().compactMap { i, s in
                guard let s else { return nil }
                seq += 1
                return (i + 1, seq, s)
            }
        }

        public var moduleCount: Int { slots.compactMap { $0 }.reduce(0) { $0 + $1.modules } }
    }

    public static let slotCount = 20
    public static let irMinimumMOhm = 1.0
    /// A string whose Voc is this far from the median of strings with as many modules is flagged.
    public static let vocTolerance = 0.05
    /// The PR the after-test passes at; the PWA form sets none (docs/ui/iec62446-test "ค่าที่ยังเป็นสมมติฐาน").
    public static let defaultPRThreshold = 0.70

    public var stationLine: String
    public var module: Module
    public var inverters: [Inverter]
    public var before: Conditions
    public var after: Conditions
    /// Average irradiation over the 7 days, kWh/m²/day (= Yr in hours).
    public var yrKWhM2Day: Double?
    public var arrayTempC: Double?
    public var testDate: Date?
    public var tester: String
    public var instruments: Instruments
    /// Photo ids: the irradiance meter's screen, and the thermal images.
    public var irradiancePhoto: String?
    public var thermalPhotos: [String]
    /// Set on example data copied from another station (the app's demo of the แพรกหนามแดง form): that station's
    /// name, so an export of it can't pass for this job's test. nil on a real test.
    public var sampleName: String?
    /// When the system was switched on to the grid (the after phase is measured from then).
    public var gridOnAt: Date?
    /// Thermal photo id → where it was taken (`หลังคาอาคาร 1`, `ตู้ DC` …); a photo without one has no entry.
    public var thermalPlaces: [String: String] = [:]
    /// `Stage` raw value → who confirmed it complete and when (`IECReport+Stages`).
    public var stageRecords: [String: StageRecord] = [:]
    /// Every Excel / Word file exported, oldest first.
    public var exports: [ExportRecord] = []
    /// Set by `เสร็จ`: the test is closed and locked until reopened.
    public var result: TestResult?
    /// The single line diagram attached in step 1 (the file is a job document; this says which and which version).
    public var sld: SLDRef?

    public init(stationLine: String = "", module: Module = .init(), inverters: [Inverter] = [], before: Conditions = .init(),
                after: Conditions = .init(), yrKWhM2Day: Double? = nil, arrayTempC: Double? = nil, testDate: Date? = nil,
                tester: String = "", instruments: Instruments = .init(), irradiancePhoto: String? = nil, thermalPhotos: [String] = []) {
        self.stationLine = stationLine; self.module = module; self.inverters = inverters; self.before = before; self.after = after
        self.yrKWhM2Day = yrKWhM2Day; self.arrayTempC = arrayTempC; self.testDate = testDate; self.tester = tester
        self.instruments = instruments; self.irradiancePhoto = irradiancePhoto; self.thermalPhotos = thermalPhotos
    }

    enum CodingKeys: String, CodingKey {
        case stationLine, module, inverters, before, after, yrKWhM2Day, arrayTempC, testDate, tester, instruments, irradiancePhoto, thermalPhotos
        case sampleName, gridOnAt, thermalPlaces, stageRecords, exports, result, sld
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stationLine = try c.decodeIfPresent(String.self, forKey: .stationLine) ?? ""
        module = try c.decodeIfPresent(Module.self, forKey: .module) ?? .init()
        inverters = try c.decodeIfPresent([Inverter].self, forKey: .inverters) ?? []
        before = try c.decodeIfPresent(Conditions.self, forKey: .before) ?? .init()
        after = try c.decodeIfPresent(Conditions.self, forKey: .after) ?? .init()
        yrKWhM2Day = try c.decodeIfPresent(Double.self, forKey: .yrKWhM2Day)
        arrayTempC = try c.decodeIfPresent(Double.self, forKey: .arrayTempC)
        testDate = try c.decodeIfPresent(Date.self, forKey: .testDate)
        tester = try c.decodeIfPresent(String.self, forKey: .tester) ?? ""
        instruments = try c.decodeIfPresent(Instruments.self, forKey: .instruments) ?? .init()
        irradiancePhoto = try c.decodeIfPresent(String.self, forKey: .irradiancePhoto)
        thermalPhotos = try c.decodeIfPresent([String].self, forKey: .thermalPhotos) ?? []
        sampleName = try c.decodeIfPresent(String.self, forKey: .sampleName)
        gridOnAt = try c.decodeIfPresent(Date.self, forKey: .gridOnAt)
        thermalPlaces = try c.decodeIfPresent([String: String].self, forKey: .thermalPlaces) ?? [:]
        stageRecords = try c.decodeIfPresent([String: StageRecord].self, forKey: .stageRecords) ?? [:]
        exports = try c.decodeIfPresent([ExportRecord].self, forKey: .exports) ?? []
        result = try c.decodeIfPresent(TestResult.self, forKey: .result)
        sld = try c.decodeIfPresent(SLDRef.self, forKey: .sld)
    }

    /// The sheet's station line doesn't name this job's station (`stationName`): the job was renamed after the test
    /// was set up, or the line was edited. Example data says what it is instead (`sampleName`), so it never counts.
    public func namesAnotherStation(than stationName: String) -> Bool {
        let name = stationName.trimmingCharacters(in: .whitespaces)
        guard sampleName == nil, !name.isEmpty, !stationLine.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return !stationLine.contains(name)
    }

    static func padded(_ s: [Slot?]) -> [Slot?] {
        Array((s + Array(repeating: nil, count: max(0, slotCount - s.count))).prefix(slotCount))
    }

    /// 2 decimals, as the form shows them; each derived value is rounded before the next step uses it (spec §2).
    public static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// `INV1ST8`.
    public static func label(inverter: Int, seq: Int) -> String { "INV\(inverter)ST\(seq)" }
    /// The MPPT of a 1-based slot: slots 1–2 are MPPT 1.
    public static func mppt(slot: Int) -> Int { (slot + 1) / 2 }
}

// MARK: - Derived values

public extension IECReport {
    var stringCount: Int { inverters.reduce(0) { $0 + $1.strings.count } }
    var moduleCount: Int { inverters.reduce(0) { $0 + $1.moduleCount } }
    /// Σ modules × module power, kWp.
    var installedKWp: Double { Double(moduleCount) * module.powerW / 1000 }
    func installedKWp(_ inv: Inverter) -> Double { Double(inv.moduleCount) * module.powerW / 1000 }

    /// Average kWh a day over the 7 days.
    func dailyKWh(_ inv: Inverter) -> Double? { inv.energy7dKWh.map { Self.round2($0 / 7) } }

    /// Final yield, kWh/kWp/day.
    func yf(_ inv: Inverter) -> Double? {
        let kWp = installedKWp(inv)
        guard let d = dailyKWh(inv), kWp > 0 else { return nil }
        return Self.round2(d / kWp)
    }

    /// Performance ratio, Yf ÷ Yr.
    func pr(_ inv: Inverter) -> Double? {
        guard let yf = yf(inv), let yr = yrKWhM2Day, yr > 0 else { return nil }
        return Self.round2(yf / yr)
    }

    /// kWh a day ÷ (Yr × module area), as a fraction; nil without the module area.
    func efficiency(_ inv: Inverter) -> Double? {
        guard let d = dailyKWh(inv), let yr = yrKWhM2Day, yr > 0, let area = module.areaM2, area > 0, inv.moduleCount > 0 else { return nil }
        return Self.round2(d / (yr * Double(inv.moduleCount) * area))
    }

    /// E14: normal when every used string's lower IR reading is at least 1 MΩ; nil while any is missing.
    func irSummary(_ inv: Inverter) -> Check? {
        let passes = inv.strings.map(\.value.irPass)
        guard !passes.isEmpty, !passes.contains(nil) else { return nil }
        return passes.allSatisfy { $0 == true } ? .normal : .abnormal
    }

    /// How far a string's Voc is from the median Voc of the inverter's strings with as many modules, as a signed
    /// fraction; nil without a reading or with no other string to compare to.
    func vocDeviation(_ inv: Inverter, slot: Int) -> Double? {
        guard inv.slots.indices.contains(slot - 1), let s = inv.slots[slot - 1], let v = s.vocV else { return nil }
        let peers = inv.slots.compactMap { $0 }.filter { $0.modules == s.modules }.compactMap(\.vocV).sorted()
        guard peers.count > 1 else { return nil }
        let m = peers.count % 2 == 1 ? peers[peers.count / 2] : (peers[peers.count / 2 - 1] + peers[peers.count / 2]) / 2
        return m > 0 ? (v - m) / m : nil
    }

    /// The strings whose Voc is off by more than `vocTolerance`.
    func vocOutliers(_ inv: Inverter) -> [Int] {
        inv.strings.compactMap { s in vocDeviation(inv, slot: s.slot).flatMap { abs($0) > Self.vocTolerance ? s.slot : nil } }
    }

    /// The phase passes: before = continuity, polarity, IR and the inverter check all fine; after = the inverter check
    /// fine and PR at least `prThreshold`. nil while something is missing.
    func passes(_ inv: Inverter, _ phase: Phase, prThreshold: Double = defaultPRThreshold) -> Bool? {
        switch phase {
        case .before:
            let polarity = inv.strings.map(\.value.polarityOK)
            guard let c = inv.continuity, let f = inv.functionalBefore, let ir = irSummary(inv), !polarity.contains(nil) else { return nil }
            return c == .normal && f == .normal && ir == .normal && polarity.allSatisfy { $0 == true }
        case .after:
            guard let f = inv.functionalAfter, let pr = pr(inv) else { return nil }
            return f == .normal && pr >= prThreshold
        }
    }
}

// MARK: - Progress

public extension IECReport {
    /// Readings per string: Voc, current before, IR (both), Vmp, Imp.
    static let readingsPerString = 5

    struct Tally: Equatable, Sendable {
        public var done: Int
        public var total: Int
        public init(_ done: Int, _ total: Int) { self.done = done; self.total = total }
        public var isComplete: Bool { total > 0 && done >= total }
        public var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
    }

    /// One reading kind over an inverter's strings.
    enum Reading: CaseIterable, Sendable { case vocAndCurrent, insulation, vmpAndImp }

    func tally(_ inv: Inverter, _ r: Reading) -> Tally {
        let s = inv.strings.map(\.value)
        let done: Int = switch r {
        case .vocAndCurrent: s.filter { $0.vocV != nil && $0.iBeforeA != nil }.count
        case .insulation: s.filter { $0.irPosMOhm != nil && $0.irNegMOhm != nil }.count
        case .vmpAndImp: s.filter { $0.vmpV != nil && $0.impA != nil }.count
        }
        return Tally(done, s.count)
    }

    /// `ค่าที่วัดแล้ว`: every reading of every string.
    var readings: Tally {
        let s = inverters.flatMap { $0.strings.map(\.value) }
        let done = s.reduce(0) { n, x in
            n + [x.vocV, x.iBeforeA, x.vmpV, x.impA].compactMap { $0 }.count + (x.irPosMOhm != nil && x.irNegMOhm != nil ? 1 : 0)
        }
        return Tally(done, s.count * Self.readingsPerString)
    }

    /// `รูปถ่าย`: five a string, and the irradiance meter's screen.
    var photos: Tally {
        let s = inverters.flatMap { $0.strings.map(\.value) }
        let done = s.reduce(0) { n, x in n + PhotoKind.allCases.filter { x.photo($0) != nil }.count } + (irradiancePhoto != nil ? 1 : 0)
        return Tally(done, s.count * PhotoKind.allCases.count + 1)
    }

    /// What still blocks the export, in the order of `ยังขาดก่อนส่งออก`.
    enum Missing: Equatable, Sendable {
        case insulation(strings: Int)
        case vocAndCurrent(strings: Int)
        case vmpAndImp(strings: Int)
        case checks(Int)
        case energy(inverters: Int)
        case conditions
        case moduleArea
        case testRecord(Int)

        public var title: String {
            switch self {
            case .insulation(let n): "ค่า IR (MΩ) \(n) สตริง"
            case .vocAndCurrent(let n): "Voc / กระแส ก่อนเชื่อมต่อ \(n) สตริง"
            case .vmpAndImp(let n): "Vmp / Imp หลังเชื่อมต่อ \(n) สตริง"
            case .checks(let n): "ผลตรวจ Continuity / Inverter testing \(n) ช่อง"
            case .energy(let n): "พลังงาน 7 วัน \(n) inverter"
            case .conditions: "สภาพการทดสอบ (อุณหภูมิ แสง เวลา Yr)"
            case .moduleArea: "พื้นที่แผงต่อแผ่น (จาก datasheet)"
            case .testRecord(let n): "วันที่ทดสอบ ผู้ทดสอบ serial เครื่องมือ · \(n) ช่อง"
            }
        }
    }

    var missing: [Missing] {
        var out: [Missing] = []
        func left(_ r: Reading) -> Int { inverters.reduce(0) { let t = tally($1, r); return $0 + t.total - t.done } }
        if case let n = left(.insulation), n > 0 { out.append(.insulation(strings: n)) }
        if case let n = left(.vocAndCurrent), n > 0 { out.append(.vocAndCurrent(strings: n)) }
        if case let n = left(.vmpAndImp), n > 0 { out.append(.vmpAndImp(strings: n)) }
        let checks = inverters.reduce(0) { $0 + [$1.continuity, $1.functionalBefore, $1.functionalAfter].filter { $0 == nil }.count }
        if checks > 0 { out.append(.checks(checks)) }
        let energy = inverters.filter { $0.energy7dKWh == nil }.count
        if energy > 0 { out.append(.energy(inverters: energy)) }
        if !before.isComplete || !after.isComplete || yrKWhM2Day == nil || arrayTempC == nil { out.append(.conditions) }
        if module.areaM2 == nil { out.append(.moduleArea) }
        let record = (testDate == nil ? 1 : 0) + (tester.trimmingCharacters(in: .whitespaces).isEmpty ? 1 : 0) + (instruments.isComplete ? 0 : 1)
        if record > 0 { out.append(.testRecord(record)) }
        return out
    }

    /// Done over everything the export asks for, 0…1: readings, photos, checks, energy and the test record.
    var completion: Double {
        let checks = inverters.reduce(0) { $0 + [$1.continuity, $1.functionalBefore, $1.functionalAfter].compactMap { $0 }.count }
        let energy = inverters.filter { $0.energy7dKWh != nil }.count
        let station = [before.isComplete, after.isComplete, yrKWhM2Day != nil, arrayTempC != nil, module.areaM2 != nil,
                       testDate != nil, !tester.isEmpty, instruments.isComplete].filter { $0 }.count
        let done = readings.done + photos.done + checks + energy + station
        let total = readings.total + photos.total + inverters.count * 4 + 8
        return total > 0 ? Double(done) / Double(total) : 0
    }
}
