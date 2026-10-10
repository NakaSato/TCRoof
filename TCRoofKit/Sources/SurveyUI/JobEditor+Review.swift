#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// ตรวจรูปทั้งหมด, REV และรายการแก้ไข and the lock after signing in the editor
/// (docs/specs/review-lock-revisions-swift.md).
extension JobEditorView {
    /// Every edit passes here before it is saved: a locked job refuses it, and an edit to a signed form asks first,
    /// because the signatures were given for the data before it.
    func jobChanged(_ old: Job, _ new: Job) {
        let stored = model.job(new.id)
        if let stored, stored.signedUnlocked, new.bothSigned, stored.contentDiffers(from: new) {
            pendingSignedEdit = new
            job = stored
            return
        }
        var j = new
        j.drive = stored?.drive ?? new.drive
        guard model.update(j) else {
            // a stray write to a locked job (a page filling a derived field): show what is stored again
            if let stored { job = stored }
            return
        }
        // the second signature, in either order: offer to lock
        if old.id == new.id, !old.bothSigned, new.bothSigned, !new.isLocked { showLockSheet = true }
    }

    /// The banner above every page: moved to installation, or locked (with the integrity warning).
    @ViewBuilder var readOnlyBanner: some View {
        if job.stage != .survey {
            stageBanner
        } else if job.isLocked {
            VStack(spacing: 10) {
                if integrityBroken, let rev = job.lock?.rev {
                    IntegrityBanner(rev: rev, compare: { revisionCompare = rev; select(.revisions) }, openNext: { showNextRevision = true })
                }
                LockBanner(job: job) { showNextRevision = true }
            }
        }
    }

    /// E1 above the page: signed but not locked, or required photos missing before the first signature.
    @ViewBuilder var finalBanners: some View {
        if !readOnly && job.signedUnlocked {
            SignedUnlockedBanner { showLockSheet = true }
        } else if !readOnly && job.values.photo("surveyorSign") == nil && job.values.photo("customerSign") == nil, job.missingRequiredPhotos > 0 {
            MissingPhotosBanner(missing: job.missingRequiredPhotos) { photoFilter = .missing; select(.photos) }
        }
    }

    /// ตรวจรูปทั้งหมด and REV และรายการแก้ไข, under the steps.
    var reviewRows: some View {
        let photos = job.photoSlots.flatMap(\.slots).filter(\.required)
        let filled = photos.filter { $0.photo != nil }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("ตรวจก่อนส่ง").font(.caption.weight(.heavy)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 6).padding(.top, 4)
            row(SidebarItem(page: .photos, code: "", title: "ตรวจรูปทั้งหมด", completion: Completion(filled: filled, total: photos.count)),
                symbol: "photo.on.rectangle.angled")
            if !(job.revisions ?? []).isEmpty {
                row(SidebarItem(page: .revisions, code: "", title: "REV และรายการแก้ไข", completion: Completion()), symbol: "clock.arrow.circlepath")
            }
        }
    }

    /// Pages that differ from the previous issued REV, with how many rows: the orange dot on their sidebar row.
    var changedPages: [Page: Int] {
        guard !job.isLocked, let base = revisionBase else { return [:] }
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
            VStack(spacing: 0) {
                if readOnly { readOnlyBanner.padding(.horizontal, 16).padding(.top, 16) }
                PhotoReviewPage(job: $job, filter: $photoFilter, readOnly: readOnly, width: detailSize.width, openField: openField)
            }
        } else {
            VStack(spacing: 0) {
                if readOnly { readOnlyBanner.padding(.horizontal, 16).padding(.top, 16) }
                RevisionsPage(job: job, openPDF: { url, title in preview = PDFPreviewItem(url: url, title: title) }, from: revisionCompare)
                    .id(revisionCompare)
            }
        }
    }

    // MARK: actions

    func issueRevision() {
        showLockSheet = false
        run("กำลังออก REV \(job.rev)…") {
            try model.issue(job.id)
            if let j = model.job(job.id) { job = j }
            integrityBroken = false
        }
    }

    func openNextRevision(reason: String, updateDate: Bool) {
        model.openNextRevision(job.id, reason: reason, updateDate: updateDate)
        if let j = model.job(job.id) { job = j }
        integrityBroken = false
        loadRevisionBase()
    }

    /// The signatures go; the edit stays.
    func confirmSignedEdit() {
        guard var j = pendingSignedEdit else { return }
        for f in RevisionRule.signatureIDs { j.values[f] = nil }
        pendingSignedEdit = nil
        job = j
    }

    func loadRevisionBase() {
        revisionBase = job.previousRevision.flatMap { model.snapshot(job, rev: $0.rev) }
    }

    func checkIntegrity() {
        guard job.isLocked else { integrityBroken = false; return }
        integrityBroken = model.integrityBroken(job)
    }
}

/// The editor's sheets and dialogs of the review lock, kept off `body` so it type-checks.
struct ReviewLockModifiers: ViewModifier {
    let editor: JobEditorView
    func body(content: Content) -> some View {
        let e = editor
        content
            .sheet(isPresented: e.$showLockSheet) {
                LockSheet(job: e.job, changes: e.job.previousRevision == nil ? nil : e.model.revisionChanges(e.job).count,
                          lock: { e.issueRevision() }, notNow: { e.showLockSheet = false })
            }
            .sheet(isPresented: e.$showNextRevision) {
                NextRevisionSheet(job: e.job) { reason, date in e.openNextRevision(reason: reason, updateDate: date) }
            }
            .confirmationDialog("การแก้ไขนี้จะล้างลายเซ็นทั้งสอง", isPresented: Binding(get: { e.pendingSignedEdit != nil }, set: { if !$0 { e.pendingSignedEdit = nil } }),
                                titleVisibility: .visible) {
                Button("ล้างลายเซ็นและแก้ไข", role: .destructive) { e.confirmSignedEdit() }
                Button("ยกเลิก", role: .cancel) { e.pendingSignedEdit = nil }
            } message: { Text("ลายเซ็นต้องตรงกับข้อมูลที่ลงนาม · แก้แล้วต้องลงนามใหม่ทั้งสองฝ่าย") }
            .task(id: "\(e.job.previousRevision?.rev ?? "")|\(e.model.revisionArrivals)") { e.loadRevisionBase(); e.checkIntegrity() }
            .onAppear { e.checkIntegrity() }
    }
}
#endif
