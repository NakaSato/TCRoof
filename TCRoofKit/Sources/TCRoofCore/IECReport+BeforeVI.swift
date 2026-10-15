import Foundation

/// Step 2 of the IEC test, `ก่อนออน · แรงดัน / กระแส` (docs/ui/iec62446-step2-before-vi-ipad): each string's Voc against
/// the median of the strings with as many modules, its open-circuit current (0 A before the grid connection), its
/// polarity (from the Voc's sign unless set by hand), and where its values and photos go in Excel and the report.
public extension IECReport {
    /// A slot as step 2 shows it: no string, still missing a value, every value fine, or a value that fails.
    enum BeforeVIStatus: Equatable, Sendable { case empty, todo, pass, fail }

    struct BeforeVITally: Equatable, Sendable {
        /// Strings with Voc, current and polarity.
        public var done: Int
        public var total: Int
        public var failed: Int
        public var isComplete: Bool { total > 0 && done == total }
    }

    /// Voc within `vocTolerance` of its module-count group's median (exactly 5 % passes); nil without a Voc. A
    /// string with no other string of its module count has nothing to compare to and passes.
    func vocPasses(_ inv: Inverter, slot: Int) -> Bool? {
        guard inv.slots.indices.contains(slot - 1), inv.slots[slot - 1]?.vocV != nil else { return nil }
        return vocDeviation(inv, slot: slot).map { abs($0) <= Self.vocTolerance } ?? true
    }

    /// Before the connection the circuit is open: exactly 0 A passes, anything else fails.
    static func currentPassesBefore(_ amps: Double) -> Bool { amps == 0 }

    func beforeVIStatus(_ inv: Inverter, slot: Int) -> BeforeVIStatus {
        guard inv.slots.indices.contains(slot - 1), let s = inv.slots[slot - 1] else { return .empty }
        if !beforeVIFailures(inv, slot: slot).isEmpty { return .fail }
        return s.vocV != nil && s.iBeforeA != nil && s.polarityOK != nil ? .pass : .todo
    }

    /// Why a string fails, as the alert says it: `Voc 712.0 V ต่างจากมัธยฐาน −5.4% (เกณฑ์ ±5%)`.
    func beforeVIFailures(_ inv: Inverter, slot: Int) -> [String] {
        guard inv.slots.indices.contains(slot - 1), let s = inv.slots[slot - 1] else { return [] }
        var out: [String] = []
        if vocPasses(inv, slot: slot) == false, let v = s.vocV, let d = vocDeviation(inv, slot: slot) {
            out.append("Voc \(String(format: "%.1f", v)) V ต่างจากมัธยฐาน \(Self.signedPercent(d)) (เกณฑ์ ±\(Int(Self.vocTolerance * 100))%)")
        }
        if let a = s.iBeforeA, !Self.currentPassesBefore(a) { out.append("กระแส \(String(format: "%.2f", a)) A · ก่อนออนต้องเป็น 0 A") }
        if s.polarityOK == false { out.append("ขั้วสายกลับ") }
        return out
    }

    /// `+0.3%`, `−5.4%` (a real minus sign), one decimal.
    static func signedPercent(_ fraction: Double) -> String {
        let p = (fraction * 1000).rounded() / 10
        return (p < 0 ? "−" : "+") + String(format: "%.1f", abs(p)) + "%"
    }

    func beforeVITally(_ inv: Inverter) -> BeforeVITally {
        let states = inv.strings.map { beforeVIStatus(inv, slot: $0.slot) }
        let done = inv.strings.filter { $0.value.vocV != nil && $0.value.iBeforeA != nil && $0.value.polarityOK != nil }.count
        return BeforeVITally(done: done, total: states.count, failed: states.filter { $0 == .fail }.count)
    }

    /// The median Voc of each module-count group with readings, the larger strings first (`มัธยฐาน 16 แผง`).
    func vocMedians(_ inv: Inverter) -> [(modules: Int, median: Double)] {
        let strings = inv.strings.map(\.value)
        return Set(strings.map(\.modules)).sorted(by: >).compactMap { m in
            let v = strings.filter { $0.modules == m }.compactMap(\.vocV).sorted()
            guard !v.isEmpty else { return nil }
            return (m, v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2)
        }
    }

    /// The Excel column of a 1-based slot: slot 1 is E, whatever string sits there.
    static func excelColumn(slot: Int) -> String {
        var n = 4 + slot - 1, s = ""
        repeat { s = String(UnicodeScalar(UInt8(65 + n % 26))) + s; n = n / 26 - 1 } while n >= 0
        return s
    }

    /// The page of the Word appendix's before part a string's photos go to: 3 strings a page after the cover,
    /// counted over the station's strings in inverter order.
    func reportPage(inverter i: Int, seq: Int) -> Int {
        let before = inverters.prefix(i).reduce(0) { $0 + $1.strings.count }
        return 1 + (before + seq + 2) / 3
    }

    /// Types a Voc: a negative reading means the leads are reversed, so the value is kept positive and the polarity
    /// set to reversed, unless the polarity was set by hand. Clearing the Voc leaves the polarity as it is.
    mutating func setVoc(_ v: Double?, inverter i: Int, slot: Int) {
        guard inverters.indices.contains(i), inverters[i].slots.indices.contains(slot - 1), inverters[i].slots[slot - 1] != nil else { return }
        inverters[i].slots[slot - 1]?.vocV = v.map(abs)
        if let v, inverters[i].slots[slot - 1]?.polarityByHand != true { inverters[i].slots[slot - 1]?.polarityOK = v >= 0 }
    }

    /// The ✓ ถูกต้อง / ✗ กลับขั้ว segment: wins over the Voc's sign from then on.
    mutating func setPolarity(_ ok: Bool, inverter i: Int, slot: Int) {
        guard inverters.indices.contains(i), inverters[i].slots.indices.contains(slot - 1), inverters[i].slots[slot - 1] != nil else { return }
        inverters[i].slots[slot - 1]?.polarityOK = ok
        inverters[i].slots[slot - 1]?.polarityByHand = true
    }

    /// The reading on a meter's screen in a photo's recognised text: the number with the most digits that isn't part
    /// of a label (`INV1ST1`, `F15`). `753.0`, `-753.0`, `0.00`; nil when there is none.
    static func meterReading(in text: String) -> Double? {
        let pattern = #"(?<![A-Za-z0-9.])-?\d+(?:[.,]\d+)?(?![0-9])"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let found = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range).replacingOccurrences(of: ",", with: ".") }
        let best = found.enumerated().max { a, b in
            let (x, y) = (a.element.filter(\.isNumber).count, b.element.filter(\.isNumber).count)
            return x == y ? a.offset > b.offset : x < y
        }
        return best.flatMap { Double($0.element) }
    }

    /// The typed value is off the photo's reading by more than 1 % (the board's assumption): the tile warns.
    static func differsFromReading(_ typed: Double, _ read: Double) -> Bool {
        let base = max(abs(read), 1e-9)
        return read == 0 ? typed != 0 : abs(typed - read) / base > 0.01
    }
}
