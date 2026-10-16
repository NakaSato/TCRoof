import Foundation

/// Step 1 of the IEC test, `ตั้งค่าระบบ` (docs/ui/iec62446-step1-setup-ipad): the SLD, the inverters with their MPPT
/// count, model, serial and photos, and each string slot used or SPARE with its module count.
public extension IECReport {
    /// The attached single line diagram: a job document named `name`, the `version`th upload.
    struct SLDRef: Codable, Equatable, Sendable {
        public var name: String
        public var version: Int
        public var at: Date
        public init(name: String, version: Int, at: Date) { self.name = name; self.version = version; self.at = at }
    }

    /// The add-inverter sheet's photos; the first two are required.
    enum InverterPhoto: String, CaseIterable, Sendable {
        case front, nameplate, otherSide, back, bottom
        public var title: String {
            switch self {
            case .front: "ด้านหน้า"
            case .nameplate: "ด้านข้าง · ป้าย S/N"
            case .otherSide: "ด้านข้างอีกด้าน"
            case .back: "ด้านหลัง"
            case .bottom: "ด้านล่าง · ขั้วต่อสาย"
            }
        }
        public var required: Bool { self == .front || self == .nameplate }
    }

    struct SetupTotals: Equatable, Sendable {
        public var used: Int
        public var slots: Int
        public var modules: Int
        /// Σ modules × module W: the sheet's AA9.
        public var watts: Double
    }

    func setupTotals(_ inv: Inverter) -> SetupTotals {
        SetupTotals(used: inv.strings.count, slots: inv.slotsInUse, modules: inv.moduleCount, watts: Double(inv.moduleCount) * module.powerW)
    }

    /// What step 1 still needs before `ถัดไป`: the SLD, the date, the tester, and an inverter with a string.
    var setupBlockers: [String] {
        var out: [String] = []
        if sld == nil { out.append("แบบ SLD") }
        if testDate == nil { out.append("วันที่") }
        if tester.trimmingCharacters(in: .whitespaces).isEmpty { out.append("ผู้ทดสอบ") }
        if !inverters.contains(where: { !$0.strings.isEmpty }) { out.append("สตริง") }
        return out
    }

    /// A slot's toggle: used takes a string of `modules` (the station's panel), SPARE removes it with its values.
    mutating func setSlot(_ slot: Int, used: Bool, modules: Int, inverter i: Int) {
        guard inverters.indices.contains(i), (1...inverters[i].slotsInUse).contains(slot) else { return }
        if used {
            if inverters[i].slots[slot - 1] == nil {
                inverters[i].slots[slot - 1] = Slot(modules: max(modules, 1), brand: module.brand.isEmpty ? nil : module.brand)
            }
        } else {
            inverters[i].slots[slot - 1] = nil
        }
    }

    /// The stepper: 1…60 modules.
    mutating func setModules(_ n: Int, slot: Int, inverter i: Int) {
        guard inverters.indices.contains(i), inverters[i].slots.indices.contains(slot - 1), inverters[i].slots[slot - 1] != nil else { return }
        inverters[i].slots[slot - 1]?.modules = min(max(n, 1), 60)
    }

    /// The add-inverter sheet: every slot of the model used at `modules`, then the user sets the SPARE ones.
    @discardableResult
    mutating func addInverter(model: String, ratedKW: Double, mppt: Int, serial: String, modules: Int, photos: [String: String]) -> Int {
        var inv = Inverter(ratedKW: ratedKW, serial: serial)
        inv.model = model
        inv.mppt = min(max(mppt, 1), Self.slotCount / 2)
        inv.photos = photos
        for n in 0..<inv.slotsInUse { inv.slots[n] = Slot(modules: max(modules, 1), brand: module.brand.isEmpty ? nil : module.brand) }
        inverters.append(inv)
        return inverters.count - 1
    }

    /// Removes an inverter (never the last one) and returns the photo ids only it used, for the caller to delete.
    /// The ones after it move up: INV3 becomes INV2, in the app and in the Excel's sheet names.
    mutating func removeInverter(at i: Int) -> [String] {
        guard inverters.count > 1, inverters.indices.contains(i) else { return [] }
        let inv = inverters.remove(at: i)
        return Array(inv.photos.values) + inv.slots.compactMap { $0 }.flatMap { $0.photos.values }
    }

    /// A model's MPPT count changed (or the slots it had are past the new count): slots beyond MPPT × 2 are emptied.
    mutating func setMPPT(_ n: Int, inverter i: Int) {
        guard inverters.indices.contains(i) else { return }
        inverters[i].mppt = min(max(n, 1), Self.slotCount / 2)
        for k in inverters[i].slotsInUse..<Self.slotCount { inverters[i].slots[k] = nil }
    }
}

public extension IECReport {
    /// A serial number in a nameplate photo's recognised text: the longest run of capitals and digits (6 or more,
    /// both kinds), after an `S/N` or `SN` label when there is one. nil when none looks like a serial.
    static func serialCandidate(in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        func tokens(_ s: String) -> [String] {
            s.uppercased().components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
                .filter { $0.count >= 6 && $0.contains(where: \.isNumber) && $0.contains(where: \.isLetter) }
        }
        let labelled = lines.filter { $0.uppercased().contains("S/N") || $0.uppercased().contains("SN") || $0.uppercased().contains("SERIAL") }
            .flatMap { tokens($0.replacingOccurrences(of: "S/N", with: " ", options: .caseInsensitive)) }
        return (labelled.isEmpty ? lines.flatMap(tokens) : labelled).max { $0.count < $1.count }
    }
}
