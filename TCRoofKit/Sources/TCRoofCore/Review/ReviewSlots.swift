import Foundation

/// Where a photo slot's field lives: the job's own answers (A1–A4, E1) or one section.
public enum SlotScope: Hashable, Sendable {
    case cover, module(UUID)
}

/// One place a photo goes, for ตรวจรูปทั้งหมด.
public struct ReviewSlot: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case photo, photosItem, photosAdd, signature, leftover }
    public var id: String {
        let s: String
        switch scope { case .cover: s = "cover"; case .module(let m): s = m.uuidString }
        return "\(s)|\(fieldID)|\(index.map(String.init) ?? "-")"
    }
    public let scope: SlotScope
    /// "tr0_plate", "structPhotos", "surveyorSign" …; "" for a leftover photo.
    public let fieldID: String
    /// "TR1 ภาพป้ายพิกัด (Nameplate)", "ภาพโครงสร้าง (ใต้หลังคา) 2"
    public let label: String
    public let kind: Kind
    /// Position inside a `.photos` field (the add slot's is the next free one).
    public let index: Int?
    public let photo: Photo?
    public let required: Bool
    /// Required and still empty: the red frame.
    public var isMissing: Bool { required && photo == nil }
}

public struct ReviewSlotGroup: Identifiable, Sendable {
    /// "A1", "A3", "B1.2", "C1", "E1"; "อื่นๆ" for photos no field claims.
    public let id: String
    /// "A3 มิเตอร์ หม้อแปลง และตู้ MDB"
    public let title: String
    public let slots: [ReviewSlot]
    public var missingRequired: Int { slots.filter(\.isMissing).count }
    /// Required slots in this group and how many are filled ("10/12" on the header).
    public var requiredCount: Int { slots.filter(\.required).count }
    public var filledRequired: Int { slots.filter { $0.required && $0.photo != nil }.count }
}

public extension Job {
    /// The cover pages in report order, with the code and title the editor and Drive folders use.
    static var coverPages: [(code: String, title: String, group: GroupSpec)] {
        [("A1", "ข้อมูลโครงการ", Schema.info), ("A2", "ภาพสถานที่ติดตั้ง", Schema.site),
         ("A3", "มิเตอร์ หม้อแปลง และตู้ MDB", Schema.electrical), ("A4", "ประวัติน้ำท่วม", Schema.flood)]
    }
    static var finalPage: (code: String, title: String, group: GroupSpec) { ("E1", "สรุปผลและลงนาม", Schema.final) }

    /// Every photo slot of the visible fields, grouped A1–A4, sections, E1 as `photoFolders`, then leftover photos.
    var photoSlots: [ReviewSlotGroup] {
        var placed = Set<UUID>()
        func slots(_ fields: [FieldSpec], _ v: Values, _ scope: SlotScope) -> [ReviewSlot] {
            var out: [ReviewSlot] = []
            for f in fields where f.isVisible(v) {
                let required = f.isRequired(v)
                switch f.kind {
                case .photo:
                    let p = v.photo(f.id)
                    out.append(ReviewSlot(scope: scope, fieldID: f.id, label: f.label, kind: .photo, index: nil, photo: p, required: required))
                case .signature:
                    let p = v.photo(f.id)
                    out.append(ReviewSlot(scope: scope, fieldID: f.id, label: f.label, kind: .signature, index: nil, photo: p, required: required))
                case .photos(let max):
                    let list = v.photos(f.id)
                    for (i, p) in list.enumerated() {
                        out.append(ReviewSlot(scope: scope, fieldID: f.id, label: list.count > 1 ? "\(f.label) \(i + 1)" : f.label,
                                             kind: .photosItem, index: i, photo: p, required: required))
                    }
                    if list.count < max {
                        // a required, empty field needs its first photo: that add slot is the red one
                        out.append(ReviewSlot(scope: scope, fieldID: f.id, label: f.label, kind: .photosAdd, index: list.count, photo: nil,
                                             required: required && list.isEmpty))
                    }
                default: break
                }
            }
            for s in out { if let p = s.photo { placed.insert(p.id) } }
            return out
        }
        var groups: [ReviewSlotGroup] = []
        func add(_ id: String, _ title: String, _ s: [ReviewSlot]) { if !s.isEmpty { groups.append(ReviewSlotGroup(id: id, title: title, slots: s)) } }
        for p in Self.coverPages { add(p.code, p.code + " " + p.title, slots(p.group.fields, values, .cover)) }
        for s in sectionsByCategory.flatMap(\.sections) { add(s.number, s.title, slots(s.module.spec.fields, s.module.values, .module(s.id))) }
        add(Self.finalPage.code, Self.finalPage.code + " " + Self.finalPage.title, slots(Self.finalPage.group.fields, values, .cover))
        let rest = allPhotos.filter { !placed.contains($0.id) }
        add("อื่นๆ", "อื่นๆ", rest.enumerated().map { i, p in
            ReviewSlot(scope: .cover, fieldID: "", label: "รูป \(i + 1)", kind: .leftover, index: i, photo: p, required: false)
        })
        return groups
    }

    var missingRequiredPhotos: Int { photoSlots.reduce(0) { $0 + $1.missingRequired } }

    /// Writes a photo into its slot: `.photo` / `.signature` set, `.photos` append (add slot) or replace at the index.
    mutating func setPhoto(_ p: Photo, slot: ReviewSlot) {
        guard slot.kind != .leftover else { return }
        func write(_ v: inout Values) {
            switch slot.kind {
            case .photo, .signature: v[slot.fieldID] = .photo(p)
            case .photosAdd: v[slot.fieldID] = .photos(v.photos(slot.fieldID) + [p])
            case .photosItem:
                var list = v.photos(slot.fieldID)
                if let i = slot.index, list.indices.contains(i) { list[i] = p } else { list.append(p) }
                v[slot.fieldID] = .photos(list)
            case .leftover: break
            }
        }
        switch slot.scope {
        case .cover: write(&values)
        case .module(let id): if let i = modules.firstIndex(where: { $0.id == id }) { write(&modules[i].values) }
        }
    }

    /// Removes the photo in a filled slot.
    mutating func removePhoto(slot: ReviewSlot) {
        guard let p = slot.photo, slot.kind != .leftover else { return }
        func clear(_ v: inout Values) {
            switch slot.kind {
            case .photosItem: v[slot.fieldID] = .photos(v.photos(slot.fieldID).filter { $0.id != p.id })
            default: v[slot.fieldID] = nil
            }
        }
        switch slot.scope {
        case .cover: clear(&values)
        case .module(let id): if let i = modules.firstIndex(where: { $0.id == id }) { clear(&modules[i].values) }
        }
    }
}
