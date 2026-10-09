import Foundation

/// One row of เทียบ REV (docs/specs/review-lock-revisions-swift.md §3.2).
public struct FieldChange: Hashable, Identifiable, Sendable {
    public enum Kind: Sendable { case changed, added, removed }
    /// scope|field|sub
    public let id: String
    /// "A3 มิเตอร์ หม้อแปลง และตู้ MDB", "B1.2 ตู้ไฟฟ้า · โรงกรอง"
    public let group: String
    /// Field label, with " · TR2" or " · สิ่งกีดขวาง 3" for a row inside a list.
    public let field: String
    /// The field id in its scope; "" for a section added, removed or renamed.
    public let fieldID: String
    /// The section the field is in; nil for the job's own pages.
    public let module: UUID?
    public let kind: Kind
    public let old: String, new: String
    public let oldPhoto: Photo?, newPhoto: Photo?
    public var isPhoto: Bool { oldPhoto != nil || newPhoto != nil }
}

public enum FormDiff {
    /// Left out of the list: they head the รายการแก้ไข page instead.
    static let systemFields: Set<String> = ["rev", "date"]

    public static func changes(from a: FormSnapshot, to b: FormSnapshot) -> [FieldChange] {
        var out: [FieldChange] = []
        for p in Job.coverPages { out += fields(p.group.fields, a.values, b.values, group: p.code + " " + p.title, scope: nil) }

        let ja = a.job, jb = b.job
        let oldSections = Dictionary(ja.sectionsByCategory.flatMap(\.sections).map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        for s in jb.sectionsByCategory.flatMap(\.sections) {
            let key = s.id.uuidString
            guard let o = oldSections[s.id] else {
                out.append(FieldChange(id: key + "|+", group: s.title, field: "เพิ่มหัวข้อ " + s.title, fieldID: "", module: s.id, kind: .added,
                                       old: "—", new: s.title, oldPhoto: nil, newPhoto: nil))
                continue
            }
            if o.module.name.trimmed != s.module.name.trimmed {
                out.append(FieldChange(id: key + "|name", group: s.title, field: "ชื่อหัวข้อ", fieldID: "", module: s.id, kind: .changed,
                                       old: o.module.name.trimmed.isEmpty ? "—" : o.module.name, new: s.module.name.trimmed.isEmpty ? "—" : s.module.name,
                                       oldPhoto: nil, newPhoto: nil))
            }
            out += fields(s.module.spec.fields, o.module.values, s.module.values, group: s.title, scope: s.id)
        }
        let newIDs = Set(b.modules.map(\.id))
        for s in ja.sectionsByCategory.flatMap(\.sections) where !newIDs.contains(s.id) {
            out.append(FieldChange(id: s.id.uuidString + "|-", group: s.title, field: "ลบหัวข้อ " + s.title, fieldID: "", module: s.id, kind: .removed,
                                   old: s.title, new: "—", oldPhoto: nil, newPhoto: nil))
        }

        let f = Job.finalPage
        out += fields(f.group.fields, a.values, b.values, group: f.code + " " + f.title, scope: nil)
        return out
    }

    private static func fields(_ specs: [FieldSpec], _ va: Values, _ vb: Values, group: String, scope: UUID?) -> [FieldChange] {
        var out: [FieldChange] = []
        let prefix = (scope?.uuidString ?? "cover") + "|"
        func row(_ f: FieldSpec, _ sub: String, _ label: String, _ kind: FieldChange.Kind, _ old: String, _ new: String,
                 _ op: Photo? = nil, _ np: Photo? = nil) {
            out.append(FieldChange(id: prefix + f.id + "|" + sub, group: group, field: label, fieldID: f.id, module: scope, kind: kind,
                                   old: old.isEmpty ? "—" : old, new: new.isEmpty ? "—" : new, oldPhoto: op, newPhoto: np))
        }
        for f in specs {
            if scope == nil && systemFields.contains(f.id) { continue }
            switch f.kind {
            case .signature, .plan, .diagram, .note: continue
            default: break
            }
            let visA = f.isVisible(va), visB = f.isVisible(vb)
            if !visA && !visB { continue }
            // a field hidden in one REV counts as empty there
            let a = visA ? va : Values(), b = visB ? vb : Values()
            if visA && !visB {
                if f.isFilled(va) { row(f, "hidden", f.label, .removed, f.displayText(va), "ไม่ใช้แล้ว") }
                continue
            }
            switch f.kind {
            case .photo:
                let p = a.photo(f.id), q = b.photo(f.id)
                guard p?.id != q?.id else { continue }
                let kind: FieldChange.Kind = p == nil ? .added : q == nil ? .removed : .changed
                row(f, "", f.label, kind, p == nil ? "" : "แนบภาพแล้ว", q == nil ? "" : kind == .changed ? "เปลี่ยนภาพ" : "แนบภาพแล้ว", p, q)
            case .photos:
                let pa = a.photos(f.id), pb = b.photos(f.id)
                let ia = Set(pa.map(\.id)), ib = Set(pb.map(\.id))
                for p in pb where !ia.contains(p.id) { row(f, "+" + p.id.uuidString, f.label, .added, "", "เพิ่มภาพ", nil, p) }
                for p in pa where !ib.contains(p.id) { row(f, "-" + p.id.uuidString, f.label, .removed, "ลบภาพ", "", p, nil) }
            case .obstacles:
                list(a.obstacles(f.id), b.obstacles(f.id), name: { o, i in o.label.trimmed.isEmpty ? "สิ่งกีดขวาง \(i + 1)" : o.label },
                     text: obstacleText, f: f, row: row)
            case .transformers:
                list(a.transformers(f.id), b.transformers(f.id), name: { _, i in "TR\(i + 1)" }, text: transformerText, f: f, row: row)
            case .marks:
                marks(a.marks(f.id), b.marks(f.id), f: f, row: row)
            default:
                let s = f.displayText(a).trimmed, t = f.displayText(b).trimmed
                guard s != t else { continue }
                row(f, "", f.label, s.isEmpty ? .added : t.isEmpty ? .removed : .changed, s, t)
            }
        }
        return out
    }

    /// Rows of a list matched by id: one per added, removed or changed entry.
    private static func list<T: Identifiable>(_ a: [T], _ b: [T], name: (T, Int) -> String, text: (T) -> String, f: FieldSpec,
                                              row: (FieldSpec, String, String, FieldChange.Kind, String, String, Photo?, Photo?) -> Void)
    where T.ID == UUID {
        let oldByID = Dictionary(a.enumerated().map { ($1.id, ($0, $1)) }, uniquingKeysWith: { x, _ in x })
        let newIDs = Set(b.map(\.id))
        for (i, e) in b.enumerated() {
            let label = f.label + " · " + name(e, i)
            if let (_, o) = oldByID[e.id] {
                let s = text(o), t = text(e)
                if s != t { row(f, e.id.uuidString, label, .changed, s, t, nil, nil) }
            } else {
                row(f, e.id.uuidString, label, .added, "", text(e), nil, nil)
            }
        }
        for (i, e) in a.enumerated() where !newIDs.contains(e.id) {
            row(f, e.id.uuidString, f.label + " · " + name(e, i), .removed, text(e), "", nil, nil)
        }
    }

    private static func obstacleText(_ o: Obstacle) -> String {
        if o.isAbsent { return "ไม่มีจริง" }
        func v(_ s: String) -> String { s.trimmed.isEmpty ? "?" : s.trimmed }
        return "\(v(o.w))x\(v(o.h)) ม. @\(v(o.x)),\(v(o.y))"
    }

    private static func transformerText(_ t: Transformer) -> String {
        let mdb = t.mdb.enumerated().compactMap { $1.trimmed.isEmpty ? nil : "MDB\($0 + 1)=\($1.trimmed)A" }.joined(separator: " ")
        return ((t.kva.trimmed.isEmpty ? "-" : t.kva.trimmed) + " kVA " + mdb).trimmed
    }

    /// Moved more than 2 % of the picture, or a different rating.
    private static func marks(_ a: [MapMark], _ b: [MapMark], f: FieldSpec,
                              row: (FieldSpec, String, String, FieldChange.Kind, String, String, Photo?, Photo?) -> Void) {
        let old = Dictionary(a.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let newIDs = Set(b.map(\.id))
        func name(_ m: MapMark) -> String { m.label.trimmed.isEmpty ? m.kind.paletteTitle : m.label }
        for m in b {
            let label = f.label + " · " + name(m)
            guard let o = old[m.id] else { row(f, m.id.uuidString, label, .added, "", "เพิ่มสัญลักษณ์", nil, nil); continue }
            if o.value.trimmed != m.value.trimmed { row(f, m.id.uuidString + "|v", label, .changed, o.value, m.value, nil, nil) }
            if max(abs(o.x - m.x), abs(o.y - m.y)) > 0.02 { row(f, m.id.uuidString + "|xy", label, .changed, "ตำแหน่งเดิม", "ย้ายตำแหน่ง", nil, nil) }
        }
        for m in a where !newIDs.contains(m.id) { row(f, m.id.uuidString, f.label + " · " + name(m), .removed, "มีสัญลักษณ์", "", nil, nil) }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
