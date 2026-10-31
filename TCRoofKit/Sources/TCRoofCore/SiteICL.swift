import Foundation

/// The site inspection checklist of a PWA station (ICL ตรวจหน้างาน, docs/specs/master-plan/icl-site-items.json): 69
/// items in 10 groups, from the กปภ. standard drawings and IEC 62446, the same list as the Master Plan's `ICL ตรวจหน้างาน`
/// sheet. The contractor fills a sheet (results, values, photos) and sends it (`ผรม. R`); the team's engineer signs it
/// or sends it back (`วศ. A`), the same hand-over as the IEC test (`IECReport+Stages`). Group 2.1 (structure) has one
/// sheet per installation point, since each roof or tank has its own mounting; the other groups one per station.
/// A failed item is fixed and inspected again on the same sheet: rework is not a new WBS item (NASA §3.5.2, DOE).
public enum SiteICL {
    /// ITP hold points: H stops work until the engineer has inspected, W asks the engineer to witness, R is reviewed
    /// from photos or documents.
    public enum Hold: String, Codable, Sendable, CaseIterable {
        case hold = "H", witness = "W", review = "R"
        public var title: String {
            switch self {
            case .hold: "Hold: หยุดรอ วศ. ตรวจก่อนทำต่อ"
            case .witness: "Witness: แจ้ง วศ. มาดู"
            case .review: "Review: ตรวจจากรูป / เอกสาร"
            }
        }
    }

    public struct Group: Codable, Equatable, Sendable, Identifiable {
        /// The WBS work package, `2.1` … `3.1`.
        public var id: String
        /// The WBS row the signed sheet completes (`2.1.7`).
        public var wbs: String
        public var title: String
        public var applies: String
        /// One sheet per installation point (2.1) rather than one per station.
        public var perPoint: Bool
    }

    public struct Item: Codable, Equatable, Sendable, Identifiable {
        /// `ICL-2.1-03`
        public var id: String
        public var group: String
        public var title: String
        public var criterion: String
        public var method: String
        public var hold: Hold
        /// What to photograph or attach.
        public var evidence: String
        public var reference: String
        public var applies: String
        /// The step of the residential ICL it matches (`InspectionStep.id`), for reports that count both.
        public var appStep: String?
        /// A measured value's unit; nil when the item is a visual check.
        public var unit: String?
        /// The mounting types the item is for (group 2.1); nil for every type.
        public var mounts: [String]?
        /// `HV` or `LV`: only stations with that zero-export side; nil for both.
        public var zeroExport: String?
    }

    public struct Catalog: Codable, Equatable, Sendable {
        public var version: Int
        public var mounts: [String]
        public var groups: [Group]
        public var items: [Item]

        public init(version: Int = 0, mounts: [String] = [], groups: [Group] = [], items: [Item] = []) {
            self.version = version
            self.mounts = mounts
            self.groups = groups
            self.items = items
        }

        public init(json: Data) throws { self = try JSONDecoder().decode(Catalog.self, from: json) }

        public func group(_ id: String) -> Group? { groups.first { $0.id == id } }

        /// A sheet's items: the group's, less those for another mounting type or zero-export side.
        public func items(for sheet: Sheet, zeroExport: String? = nil) -> [Item] {
            items.filter { i in
                i.group == sheet.group
                    && (i.mounts == nil || sheet.mount == nil || i.mounts!.contains(sheet.mount!))
                    && (i.zeroExport == nil || zeroExport == nil || i.zeroExport == zeroExport)
            }
        }
    }

    /// The bundled catalog.
    public static let catalog: Catalog = {
        guard let url = Bundle.module.url(forResource: "icl-site-items", withExtension: "json"),
              let data = try? Data(contentsOf: url), let c = try? Catalog(json: data)
        else { return Catalog.empty }
        return c
    }()

    // MARK: - A filled sheet

    public struct Result: Codable, Equatable, Sendable {
        /// The measured value, as typed (`12`, `0.8`).
        public var value: String
        public var passed: Bool?
        /// `ไม่เกี่ยว`: the item doesn't apply here; it needs no result or photo.
        public var notApplicable: Bool
        public var instrumentSerial: String
        public var note: String
        public var checkedAt: Date?
        public var by: String

        public init(value: String = "", passed: Bool? = nil, notApplicable: Bool = false, instrumentSerial: String = "",
                    note: String = "", checkedAt: Date? = nil, by: String = "") {
            self.value = value; self.passed = passed; self.notApplicable = notApplicable
            self.instrumentSerial = instrumentSerial; self.note = note; self.checkedAt = checkedAt; self.by = by
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
            passed = try c.decodeIfPresent(Bool.self, forKey: .passed)
            notApplicable = try c.decodeIfPresent(Bool.self, forKey: .notApplicable) ?? false
            instrumentSerial = try c.decodeIfPresent(String.self, forKey: .instrumentSerial) ?? ""
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
            checkedAt = try c.decodeIfPresent(Date.self, forKey: .checkedAt)
            by = try c.decodeIfPresent(String.self, forKey: .by) ?? ""
        }
    }

    /// Who sent the sheet, signed it or sent it back, and when.
    public struct Mark: Codable, Equatable, Sendable {
        public var at: Date
        public var by: String
        public var note: String
        /// The sheet's values then, so a later change shows the mark is stale.
        public var fingerprint: String
        public init(at: Date, by: String, note: String = "", fingerprint: String) {
            self.at = at; self.by = by; self.note = note; self.fingerprint = fingerprint
        }
    }

    /// Where the hand-over stands; the sheet's Firestore document carries it beside the sheet, so the rules can refuse a
    /// contractor's edit of a sent or signed sheet, or a signature they made themselves.
    public enum LockState: String, Codable, Sendable { case open, sent, closed }

    public struct Sheet: Codable, Equatable, Sendable, Identifiable {
        /// `2.2`, or `2.1/R1` for an installation point.
        public var id: String
        public var group: String
        /// The installation point's code (`R1`, `T1`) and name, group 2.1 only.
        public var point: String?
        public var pointName: String?
        /// The point's mounting type (`SiteICL.Catalog.mounts`), which picks its items.
        public var mount: String?
        public var results: [String: Result]
        public var submission: Mark?
        public var signoff: Mark?
        public var sendBack: Mark?

        public init(group: String, point: String? = nil, pointName: String? = nil, mount: String? = nil) {
            self.group = group; self.point = point; self.pointName = pointName; self.mount = mount
            self.id = point.map { "\(group)/\($0)" } ?? group
            self.results = [:]
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let g = try c.decode(String.self, forKey: .group), p = try c.decodeIfPresent(String.self, forKey: .point)
            group = g; point = p
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? p.map { "\(g)/\($0)" } ?? g
            pointName = try c.decodeIfPresent(String.self, forKey: .pointName)
            mount = try c.decodeIfPresent(String.self, forKey: .mount)
            results = try c.decodeIfPresent([String: Result].self, forKey: .results) ?? [:]
            submission = try c.decodeIfPresent(Mark.self, forKey: .submission)
            signoff = try c.decodeIfPresent(Mark.self, forKey: .signoff)
            sendBack = try c.decodeIfPresent(Mark.self, forKey: .sendBack)
        }

        public var title: String {
            let g = SiteICL.catalog.group(group)?.title ?? group
            guard let point else { return "\(group) \(g)" }
            return "\(group) \(g): \(point)" + (pointName.map { " \($0)" } ?? "")
        }

        public func result(_ item: Item) -> Result { results[item.id] ?? Result() }

        public var lockState: LockState { signoff != nil ? .closed : submission != nil ? .sent : .open }
        /// Sent or signed: the contractor no longer changes it.
        public var isLocked: Bool { lockState != .open }

        /// An item is done when it doesn't apply, or has a result, its value when it is measured, and a photo.
        public func isDone(_ item: Item, photos: Int) -> Bool {
            let r = result(item)
            if r.notApplicable { return true }
            guard r.passed != nil, photos > 0 else { return false }
            return item.unit == nil || !r.value.trimmingCharacters(in: .whitespaces).isEmpty
        }

        public func progress(_ items: [Item], photos: (Item) -> Int) -> (done: Int, total: Int) {
            (items.filter { isDone($0, photos: photos($0)) }.count, items.count)
        }

        /// Every item done: the contractor may send it.
        public func isComplete(_ items: [Item], photos: (Item) -> Int) -> Bool {
            let p = progress(items, photos: photos)
            return p.total > 0 && p.done == p.total
        }

        public func failed(_ items: [Item]) -> [Item] { items.filter { result($0).passed == false && !result($0).notApplicable } }

        /// Signed with no failed item.
        public func passed(_ items: [Item]) -> Bool { signoff != nil && failed(items).isEmpty }

        // MARK: hand-over

        /// `ส่งให้ วศ.`: the contractor's hand-over; clears an earlier send-back.
        public mutating func submit(by: String, at: Date = .now) {
            submission = Mark(at: at, by: by, fingerprint: fingerprint)
            sendBack = nil
        }

        /// `ลงนามรับรอง`: the engineer signs a sent sheet.
        public mutating func sign(by: String, at: Date = .now) {
            if submission == nil { submission = Mark(at: at, by: by, fingerprint: fingerprint) }
            signoff = Mark(at: at, by: by, fingerprint: fingerprint)
        }

        /// `ส่งกลับให้แก้`: back to the contractor with what to fix.
        public mutating func returnForFix(by: String, note: String, at: Date = .now) {
            sendBack = Mark(at: at, by: by, note: note, fingerprint: fingerprint)
            submission = nil; signoff = nil
        }

        /// `แก้ไข` on a signed sheet (the team): open again, to be sent and signed again.
        public mutating func reopen() { submission = nil; signoff = nil }

        /// The sheet as it arrives from Firestore with its document's `state`: a signature the document doesn't record
        /// was never made by the team (only they can set `closed`), so it is dropped. Nil keeps it as it came.
        public func trusting(_ state: LockState?) -> Sheet {
            guard let state, state != .closed, signoff != nil else { return self }
            var s = self
            s.signoff = nil
            return s
        }

        /// Values changed after the signature (a device that hadn't seen the lock).
        public var signoffIsStale: Bool { signoff.map { $0.fingerprint != fingerprint } ?? false }

        /// A stable digest of the results (FNV-1a, the same on every device).
        public var fingerprint: String {
            var text = "\(id)|\(mount ?? "-")"
            for key in results.keys.sorted() {
                let r = results[key]!
                text += "|\(key):\(r.value),\(r.passed.map { $0 ? "1" : "0" } ?? "-"),\(r.notApplicable ? "n" : ""),\(r.instrumentSerial),\(r.note)"
            }
            var h: UInt64 = 0xcbf2_9ce4_8422_2325
            for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
            return String(h, radix: 16)
        }
    }

    /// The tag of a photo of an item on a sheet (`PhotoAsset.tag`).
    public static func photoTag(sheet: String, item: String) -> String { "\(sheet)#\(item)" }

    /// A photo's Drive folder and name: `ICL หน้างาน/2.1 R1/ICL-2.1-03 2.jpg`.
    public static let photoFolder = ["ICL หน้างาน"]
    public static func photoName(sheet: String, item: String, index: Int) -> String {
        "\(sheet.replacingOccurrences(of: "/", with: " ")) \(item) \(index).jpg"
    }
}

extension SiteICL.Catalog {
    static let empty = SiteICL.Catalog()
}
