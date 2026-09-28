import Foundation

/// A photo with the file name it gets outside the app ("03 TR1 ภาพป้ายพิกัด (Nameplate).jpg").
public struct NamedPhoto: Sendable {
    public let fileName: String
    public let photo: Photo
}

/// Photos of one section, filed together (Drive: รูปภาพ/<section>/).
public struct PhotoFolder: Sendable {
    public let name: String
    public let photos: [NamedPhoto]
}

public extension Job {
    /// Every photo grouped by section in app order, named after its field; photos no field claims go to "อื่นๆ".
    var photoFolders: [PhotoFolder] {
        var placed = Set<UUID>()
        func collect(_ fields: [FieldSpec], _ v: Values) -> [NamedPhoto] {
            var named: [(String, Photo)] = []
            for f in fields {
                switch f.kind {
                case .photo: if let p = v.photo(f.id) { named.append((f.label, p)) }
                case .photos: let list = v.photos(f.id); for (i, p) in list.enumerated() { named.append((list.count > 1 ? "\(f.label) \(i + 1)" : f.label, p)) }
                // signatures belong in the report, not in the photo folders
                case .signature: if let p = v.photo(f.id) { placed.insert(p.id) }
                default: break
                }
            }
            return named.enumerated().map { i, e in
                placed.insert(e.1.id)
                return NamedPhoto(fileName: String(format: "%02d ", i + 1) + e.0 + (e.1.isPNG ? ".png" : ".jpg"), photo: e.1)
            }
        }
        var out: [PhotoFolder] = []
        func add(_ name: String, _ photos: [NamedPhoto]) { if !photos.isEmpty { out.append(PhotoFolder(name: name, photos: photos)) } }
        add("A1 ข้อมูลโครงการ", collect(Schema.info.fields, values))
        add("A2 ภาพสถานที่ติดตั้ง", collect(Schema.site.fields, values))
        add("A3 มิเตอร์ หม้อแปลง และตู้ MDB", collect(Schema.electrical.fields, values))
        add("A4 ประวัติน้ำท่วม", collect(Schema.flood.fields, values))
        for s in sectionsByCategory.flatMap(\.sections) { add(s.title, collect(s.module.spec.fields, s.module.values)) }
        add("E1 สรุปผลและลงนาม", collect(Schema.final.fields, values))
        let rest = allPhotos.filter { !placed.contains($0.id) }
        add("อื่นๆ", rest.enumerated().map { i, p in NamedPhoto(fileName: String(format: "%02d รูป", i + 1) + (p.isPNG ? ".png" : ".jpg"), photo: p) })
        return out
    }
}
