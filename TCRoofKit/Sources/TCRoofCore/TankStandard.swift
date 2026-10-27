import Foundation

/// The team's tank-roof structure standard (docs/specs/tank-mounting-layout.md §1, open question 7): the module and the
/// structure values `TankLayout` lays out with. One standard for the team, kept in Firestore `config/tankStandard` and
/// changed by managers only (`tank.standard`); the app syncs it through `Store` (`onChange` out, `receive` in, the
/// higher revision wins). A job keeps a copy of the standard its layout was made with (`TankLayout.Key.standard`), so a
/// change reaches a job only when its layout is made again. The vent height is a measurement of the tank, not part of it.
public struct TankStandard: Codable, Equatable, Sendable {
    /// Module (m, kW), portrait along the slope.
    public var moduleL, moduleW, moduleKW: Double
    /// Top of the front / back post, front → back post on plan, back post → next front post.
    public var hFront, hBack, postDY, rowGap: Double
    /// Post pairs along a table, rail overhang past the end posts, front post → lower panel edge (slope).
    public var postDX, endOver, frontOver: Double
    /// Tank edge → panel, opening → panel, footing edge → opening, footing size, clearance over a vent.
    public var clearance, openClear, legClear, footing, underClear: Double
    /// End pair → table end, least spacing between pairs.
    public var maxCantilever, minPairGap: Double
    /// Raised by each save; who saved it and when.
    public var revision = 0
    public var savedBy: String?
    public var savedAt: Date?

    /// The reference sheets' values with the catalogue's default module: the standard until a manager changes it,
    /// and what a job laid out before the standard was editable was made with.
    public static var builtIn: TankStandard {
        var p = TankLayout.Params(); let m = RoofPlan.Module.catalogDefault
        p.moduleL = m.length; p.moduleW = m.width; p.moduleKW = m.kW
        return TankStandard(p)
    }

    /// The standard of `p` (its row gap is the standard's, not a wider one the energy search picked).
    public init(_ p: TankLayout.Params) {
        moduleL = p.moduleL; moduleW = p.moduleW; moduleKW = p.moduleKW
        hFront = p.hFront; hBack = p.hBack; postDY = p.postDY; rowGap = p.standardGap
        postDX = p.postDX; endOver = p.endOver; frontOver = p.frontOver
        clearance = p.clearance; openClear = p.openClear; legClear = p.legClear; footing = p.footing; underClear = p.underClear
        maxCantilever = p.maxCantilever; minPairGap = p.minPairGap
        revision = p.standardRevision
    }

    /// The layout's parameters (vent height 1.00 m, offsets 0).
    public var params: TankLayout.Params {
        var p = TankLayout.Params()
        p.moduleL = moduleL; p.moduleW = moduleW; p.moduleKW = moduleKW
        p.hFront = hFront; p.hBack = hBack; p.postDY = postDY; p.rowGap = rowGap; p.standardGap = rowGap
        p.postDX = postDX; p.endOver = endOver; p.frontOver = frontOver
        p.clearance = clearance; p.openClear = openClear; p.legClear = legClear; p.footing = footing; p.underClear = underClear
        p.maxCantilever = maxCantilever; p.minPairGap = minPairGap
        p.standardRevision = revision
        return p
    }

    /// The same values, whatever the revision and who saved them.
    public func sameValues(_ o: TankStandard) -> Bool {
        Self.fields.allSatisfy { abs(self[keyPath: $0.key] - o[keyPath: $0.key]) < 1e-9 }
    }

    // MARK: the editor's fields

    public struct Field: @unchecked Sendable {
        public let key: WritableKeyPath<TankStandard, Double>
        public let label: String
        /// The unit shown and the factor from the stored value (W shows kW × 1000).
        public let unit: String, scale: Double
        public let range: ClosedRange<Double>, step: Double
        public let group: String
    }

    public static let fields: [Field] = [
        Field(key: \.moduleL, label: "แผงยาว", unit: "ม.", scale: 1, range: 1.5...2.6, step: 0.001, group: "แผง"),
        Field(key: \.moduleW, label: "แผงกว้าง", unit: "ม.", scale: 1, range: 0.9...1.4, step: 0.001, group: "แผง"),
        Field(key: \.moduleKW, label: "กำลังแผง", unit: "W", scale: 1000, range: 0.3...0.8, step: 0.005, group: "แผง"),
        Field(key: \.hFront, label: "คานที่แนวขาหน้า สูง", unit: "ม.", scale: 1, range: 0.5...2.5, step: 0.05, group: "เสาและแถว"),
        Field(key: \.hBack, label: "เสาหลังสูง", unit: "ม.", scale: 1, range: 0.6...3.5, step: 0.05, group: "เสาและแถว"),
        Field(key: \.postDY, label: "แนวขาหน้า → เสาหลัง", unit: "ม.", scale: 1, range: 1.5...4.5, step: 0.05, group: "เสาและแถว"),
        Field(key: \.rowGap, label: "เสาหลัง → แถวถัดไป", unit: "ม.", scale: 1, range: 1.5...6, step: 0.05, group: "เสาและแถว"),
        Field(key: \.postDX, label: "ระยะคู่เสาตามแถว (สูงสุด)", unit: "ม.", scale: 1, range: 1.5...4, step: 0.05, group: "เสาและแถว"),
        Field(key: \.endOver, label: "รางยื่นพ้นเสาปลาย", unit: "ม.", scale: 1, range: 0...1, step: 0.05, group: "เสาและแถว"),
        Field(key: \.frontOver, label: "แนวขาหน้า → ขอบแผงล่าง (ตามลาด)", unit: "ม.", scale: 1, range: 0...1.5, step: 0.01, group: "เสาและแถว"),
        Field(key: \.maxCantilever, label: "คู่เสาปลาย → ปลายโต๊ะ (สูงสุด)", unit: "ม.", scale: 1, range: 0.3...2, step: 0.05, group: "เสาและแถว"),
        Field(key: \.minPairGap, label: "ระยะคู่เสาต่ำสุด", unit: "ม.", scale: 1, range: 0.3...2, step: 0.05, group: "เสาและแถว"),
        Field(key: \.clearance, label: "ขอบถัง → แผง", unit: "ม.", scale: 1, range: 0.3...3, step: 0.05, group: "ระยะเว้น"),
        Field(key: \.openClear, label: "ช่องเปิด → แผง", unit: "ม.", scale: 1, range: 0...2, step: 0.05, group: "ระยะเว้น"),
        Field(key: \.legClear, label: "ฐานรากห่างช่องเปิด", unit: "ม.", scale: 1, range: 0.1...1.5, step: 0.05, group: "ระยะเว้น"),
        Field(key: \.footing, label: "ฐานรากกว้าง", unit: "ม.", scale: 1, range: 0.15...0.8, step: 0.05, group: "ระยะเว้น"),
        Field(key: \.underClear, label: "ระยะเหนือปล่องใต้แผง", unit: "ม.", scale: 1, range: 0...0.5, step: 0.05, group: "ระยะเว้น"),
    ]

    /// What keeps the standard from being saved, in Thai; empty when it can be.
    public var problems: [String] {
        var out = Self.fields.compactMap { f -> String? in
            let v = self[keyPath: f.key]
            guard v.isFinite, f.range.contains(v) else {
                return "\(f.label) ต้องอยู่ระหว่าง \(fmt(f.range.lowerBound * f.scale)) – \(fmt(f.range.upperBound * f.scale)) \(f.unit)"
            }
            return nil
        }
        if hBack <= hFront + 0.05 { out.append("เสาหลังต้องสูงกว่าคานที่แนวขาหน้าอย่างน้อย 0.05 ม.") }
        if minPairGap > postDX { out.append("ระยะคู่เสาต่ำสุดต้องไม่เกินระยะคู่เสาตามแถว") }
        if moduleW > moduleL { out.append("แผงวางแนวตั้ง: ความยาวต้องไม่น้อยกว่าความกว้าง") }
        return out
    }

    /// `เอียง 19.7° | ระยะแถว 5.50 ม. | แผง 570 W`
    public var summary: String {
        let p = params
        return String(format: "เอียง %.1f° | ระยะแถว %.2f ม. | แผง %.0f W", p.tilt, p.rowPitch, moduleKW * 1000)
    }

    // MARK: Codable (a field missing from an older or newer document keeps the built-in value)

    enum CodingKeys: String, CodingKey {
        case moduleL, moduleW, moduleKW, hFront, hBack, postDY, rowGap, postDX, endOver, frontOver
        case clearance, openClear, legClear, footing, underClear, maxCantilever, minPairGap, revision, savedBy, savedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = TankStandard(TankLayout.Params())
        func d(_ k: CodingKeys, _ path: WritableKeyPath<TankStandard, Double>) throws {
            if let v = try c.decodeIfPresent(Double.self, forKey: k) { self[keyPath: path] = v }
        }
        let b = RoofPlan.Module.catalogDefault
        moduleL = b.length; moduleW = b.width; moduleKW = b.kW
        try d(.moduleL, \.moduleL); try d(.moduleW, \.moduleW); try d(.moduleKW, \.moduleKW)
        try d(.hFront, \.hFront); try d(.hBack, \.hBack); try d(.postDY, \.postDY); try d(.rowGap, \.rowGap)
        try d(.postDX, \.postDX); try d(.endOver, \.endOver); try d(.frontOver, \.frontOver)
        try d(.clearance, \.clearance); try d(.openClear, \.openClear); try d(.legClear, \.legClear)
        try d(.footing, \.footing); try d(.underClear, \.underClear)
        try d(.maxCantilever, \.maxCantilever); try d(.minPairGap, \.minPairGap)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        savedBy = try c.decodeIfPresent(String.self, forKey: .savedBy)
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        for (k, path) in [(CodingKeys.moduleL, \TankStandard.moduleL), (.moduleW, \.moduleW), (.moduleKW, \.moduleKW),
                          (.hFront, \.hFront), (.hBack, \.hBack), (.postDY, \.postDY), (.rowGap, \.rowGap), (.postDX, \.postDX),
                          (.endOver, \.endOver), (.frontOver, \.frontOver), (.clearance, \.clearance), (.openClear, \.openClear),
                          (.legClear, \.legClear), (.footing, \.footing), (.underClear, \.underClear),
                          (.maxCantilever, \.maxCantilever), (.minPairGap, \.minPairGap)] {
            try c.encode(self[keyPath: path], forKey: k)
        }
        try c.encode(revision, forKey: .revision)
        try c.encodeIfPresent(savedBy, forKey: .savedBy)
        try c.encodeIfPresent(savedAt, forKey: .savedAt)
    }

    public var json: String {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys; e.dateEncodingStrategy = .iso8601
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
    public static func decode(_ json: String) -> TankStandard? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(TankStandard.self, from: Data(json.utf8))
    }

    // MARK: the team's standard on this device

    /// The standard this device lays out with: the last one saved here or received, kept in a JSON file the app names.
    public final class Store: @unchecked Sendable {
        public static let shared = Store()
        private let lock = NSLock()
        private var value: TankStandard?
        private var url: URL?
        /// Called with each standard saved here (not with ones received), for the app to send.
        public var onChange: ((TankStandard) -> Void)?

        public init() {}

        public func configure(url: URL) {
            lock.lock(); defer { lock.unlock() }
            self.url = url
            value = (try? String(contentsOf: url, encoding: .utf8)).flatMap(TankStandard.decode)
        }

        /// The team's standard, the built-in one until a manager saves another.
        public var current: TankStandard { lock.lock(); defer { lock.unlock() }; return value ?? .builtIn }

        /// Saves `s` as the next revision, signed by `by`; nil and nothing saved when it has problems.
        @discardableResult
        public func save(_ s: TankStandard, by: String?, at date: Date = Date()) -> TankStandard? {
            guard s.problems.isEmpty else { return nil }
            var s = s
            lock.lock()
            s.revision = (value?.revision ?? 0) + 1
            s.savedBy = by; s.savedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
            value = s
            persist()
            lock.unlock()
            onChange?(s)
            return s
        }

        /// A standard from Firestore: kept when of a higher revision (the same: the later save). Never one with problems.
        @discardableResult
        public func receive(_ s: TankStandard) -> Bool {
            guard s.problems.isEmpty else { return false }
            lock.lock(); defer { lock.unlock() }
            if let old = value {
                guard s.revision > old.revision || (s.revision == old.revision && (s.savedAt ?? .distantPast) > (old.savedAt ?? .distantPast))
                else { return false }
            }
            value = s
            persist()
            return true
        }

        /// Tests: forget the saved standard.
        func reset() { lock.lock(); value = nil; lock.unlock() }

        private func persist() {
            guard let url, let value else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? value.json.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
