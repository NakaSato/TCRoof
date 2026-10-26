import Foundation
import SwiftData
import TCRoofCore

/// One sheet of a PWA station's site ICL (`SiteICL.Sheet`, ICL ตรวจหน้างาน): a group of the checklist, or for group 2.1
/// one installation point. The contractor fills and sends it, the team signs it. Kept as the sheet's JSON, one Firestore
/// document each (`iclSheets`, with its hand-over `state` beside it for the rules), so two people on two sheets never
/// overwrite each other. Its photos are `PhotoAsset`s tagged `SiteICL.photoTag(sheet:item:)`.
@Model
final class ICLSheet {
    var sheetJSON: String
    var updatedAt: Date
    var job: Job?
    var syncID: String?
    @Relationship(deleteRule: .cascade, inverse: \PhotoAsset.iclSheet) var photos: [PhotoAsset] = []

    init(_ sheet: SiteICL.Sheet) {
        self.sheetJSON = Self.encode(sheet) ?? "{}"
        self.updatedAt = .now
        self.syncID = UUID().uuidString
    }

    /// The sheet, or an empty one of group `?` when the JSON can't be read (an app version newer than this one).
    var sheet: SiteICL.Sheet {
        get { (try? JSONDecoder().decode(SiteICL.Sheet.self, from: Data(sheetJSON.utf8))) ?? SiteICL.Sheet(group: "?") }
        set {
            guard let text = Self.encode(newValue), text != sheetJSON else { return }
            sheetJSON = text
            updatedAt = .now
        }
    }

    func photos(for item: SiteICL.Item) -> [PhotoAsset] {
        let tag = SiteICL.photoTag(sheet: sheet.id, item: item.id)
        return photos.filter { $0.tag == tag }.sorted { $0.createdAt < $1.createdAt }
    }

    /// The sheet's items for its mounting. The job doesn't keep its zero-export side, so a sheet shows both the HV and
    /// the LV items and the other side's are marked `ไม่เกี่ยว`.
    var items: [SiteICL.Item] { SiteICL.catalog.items(for: sheet) }

    var progress: (done: Int, total: Int) {
        let s = sheet
        return s.progress(items) { photos(for: $0).count }
    }

    private static func encode(_ sheet: SiteICL.Sheet) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(sheet)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

extension Job {
    /// The site ICL's sheets in the checklist's order (group, then installation point).
    var siteICL: [ICLSheet] {
        let order = Dictionary(uniqueKeysWithValues: SiteICL.catalog.groups.enumerated().map { ($1.id, $0) })
        return iclSheets.sorted {
            let a = $0.sheet, b = $1.sheet
            return (order[a.group] ?? 99, a.point ?? "") < (order[b.group] ?? 99, b.point ?? "")
        }
    }

    func iclSheet(_ id: String) -> ICLSheet? { iclSheets.first { $0.sheet.id == id } }

    /// Signed sheets over all sheets, for the job's card.
    var siteICLTally: (signed: Int, total: Int) {
        (iclSheets.filter { $0.sheet.lockState == .closed }.count, iclSheets.count)
    }
}
