#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

/// ตรวจรูปทั้งหมด and REV และรายการแก้ไข in the editor.
extension JobEditorView {
    /// Every edit passes here before it is saved.
    func jobChanged(_ old: Job, _ new: Job) {
        var j = new
        j.drive = model.job(new.id)?.drive ?? new.drive
        model.update(j)
    }

    /// E1 above the page: signed and not issued yet (ออก REV), or required photos missing before the first signature.
    @ViewBuilder var finalBanners: some View {
        if job.bothSigned && unissued && permissions.can(.surveySignRev, on: model.access(job)) {
            IssueRevisionBanner(rev: job.nextIssueRev) { showIssueSheet = true }
        } else if job.values.photo("surveyorSign") == nil && job.values.photo("customerSign") == nil, job.missingRequiredPhotos > 0 {
            MissingPhotosBanner(missing: job.missingRequiredPhotos) { photoFilter = .missing; select(.photos) }
        }
    }

    /// ตรวจรูปทั้งหมด and REV และรายการแก้ไข, under the steps.
    var reviewRows: some View {
        let photos = job.photoSlots.flatMap(\.slots).filter(\.required)
        let filled = photos.filter { $0.photo != nil }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("ตรวจก่อนส่ง").font(.sarabun(12, .heavy, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 6).padding(.top, 4)
            row(SidebarItem(page: .photos, code: "", title: "ตรวจรูปทั้งหมด", completion: Completion(filled: filled, total: photos.count)),
                symbol: "photo.on.rectangle.angled")
            if !(job.revisions ?? []).isEmpty {
                row(SidebarItem(page: .revisions, code: "", title: "REV และรายการแก้ไข", completion: Completion()), symbol: "clock.arrow.circlepath")
            }
        }
    }

    /// Pages that differ from the previous issued REV, with how many rows: the orange dot on their sidebar row.
    var changedPages: [Page: Int] {
        guard let base = revisionBase else { return [:] }
        var out: [Page: Int] = [:]
        for c in FormDiff.changes(from: base, to: job.snapshot) {
            let p: Page = c.module.map { .module($0) } ?? Self.coverPage(code: String(c.group.prefix(2)))
            out[p, default: 0] += 1
        }
        return out
    }

    static func coverPage(code: String) -> Page {
        switch code { case "A1": return .info; case "A2": return .site; case "A3": return .electrical; case "A4": return .flood; default: return .final }
    }

    /// The page that holds a photo slot's field.
    func openField(_ s: ReviewSlot) {
        switch s.scope {
        case .module(let id): select(.module(id))
        case .cover:
            let code = Job.coverPages.first { p in p.group.fields.contains { $0.id == s.fieldID } }?.code ?? "E1"
            select(Self.coverPage(code: code))
        }
    }

    @ViewBuilder var reviewDetail: some View {
        if page == .photos {
            PhotoReviewPage(job: $job, filter: $photoFilter, width: detailSize.width, openField: openField)
        } else {
            RevisionsPage(job: job, openPDF: { url, title in preview = PDFPreviewItem(url: url, title: title) }, from: revisionCompare)
                .id(revisionCompare)
        }
    }

    /// These answers aren't an issued REV: none is issued yet, or they differ from the last one. A last REV whose
    /// snapshot hasn't reached this device counts as issued.
    var unissued: Bool {
        guard job.lastRevision != nil else { return true }
        return revisionBase.map { $0 != job.snapshot } ?? false
    }

    /// ออก REV nn; the change dots then compare with it.
    func issueRevision(_ reason: String) {
        run("กำลังออก REV \(job.nextIssueRev)…") {
            try model.issue(job.id, reason: reason)
            if let j = model.job(job.id) { job = j }
            loadRevisionBase()
        }
    }

    func loadRevisionBase() {
        revisionBase = job.previousRevision.flatMap { model.snapshot(job, rev: $0.rev) }
    }
}
#endif
