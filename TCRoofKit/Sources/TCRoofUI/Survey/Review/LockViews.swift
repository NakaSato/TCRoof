#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// Banners and sheets of ล็อกหลังลงนาม (docs/specs/review-lock-revisions-swift.md §4).

/// Top of every page of a locked job: 🔒 REV nn ลงนามแล้ว · ล็อก, the check code and แก้ไข (เปิด REV nn+1).
struct LockBanner: View {
    let job: Job
    var openNext: () -> Void
    var body: some View {
        let lock = job.lock
        let layout = ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.m) { text(lock); Spacer(minLength: Space.s); button }
            VStack(alignment: .leading, spacing: Space.s) { text(lock); button }
        }
        return layout
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
    }
    func text(_ lock: FormLock?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("REV \(lock?.rev ?? job.rev) ลงนามแล้ว · ล็อก", systemImage: "lock.fill")
                .font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
            Text("รหัสตรวจสอบ \(FormHash.short(lock?.hash ?? "")) · แก้ไขได้เมื่อเปิด REV ใหม่").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
        }
    }
    var button: some View {
        TCButton("แก้ไข (เปิด REV \(RevisionRule.next(after: job.rev)))", systemImage: "pencil", kind: .secondary, size: .card, action: openNext)
            .fixedSize()
    }
}

/// A locked job whose answers no longer hash to what was signed.
struct IntegrityBanner: View {
    let rev: String
    var compare: () -> Void
    var openNext: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("ข้อมูลไม่ตรงกับที่ลงนามใน REV \(rev)", systemImage: "exclamationmark.octagon.fill")
                .font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.dangerText)
            Text("ไฟล์งานถูกแก้นอกแอป หรือกู้คืนจากข้อมูลอื่น · ฟอร์มยังล็อกอยู่").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.dangerText)
            HStack(spacing: Space.s) {
                TCButton("เทียบกับ REV \(rev)", systemImage: "arrow.left.arrow.right", kind: .secondary, size: .card, action: compare).fixedSize()
                TCButton("เปิด REV ใหม่", systemImage: "pencil", kind: .danger, size: .card, action: openNext).fixedSize()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.danger))
    }
}

/// E1: both have signed but the form isn't locked (an older job, or ยังไม่ล็อก).
struct SignedUnlockedBanner: View {
    var lock: () -> Void
    var body: some View {
        HStack(spacing: Space.m) {
            Label("ลงนามครบแต่ยังไม่ล็อก · แก้ข้อมูลแล้วต้องลงนามใหม่", systemImage: "signature")
                .font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.pending)
            Spacer(minLength: Space.s)
            TCButton("ล็อกตอนนี้", systemImage: "lock", kind: .primary, size: .card, action: lock).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.pendingSoft, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// E1 before the first signature: required photos still missing (signing is still allowed).
struct MissingPhotosBanner: View {
    let missing: Int
    var review: () -> Void
    var body: some View {
        HStack(spacing: Space.m) {
            Label("ยังขาดรูปบังคับ \(missing) รูป", systemImage: "camera.badge.ellipsis")
                .font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.dangerText)
            Spacer(minLength: Space.s)
            TCButton("ไปตรวจรูป", systemImage: "photo.on.rectangle", kind: .secondary, size: .card, action: review).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// ลงนามครบแล้ว · ล็อกฟอร์ม REV nn: the gaps as warnings that don't block, then lock or keep editing.
struct LockSheet: View {
    let job: Job
    let changes: Int?
    var lock: () -> Void
    var notNow: () -> Void
    var body: some View {
        let missing = job.missingItems.count, photos = job.missingRequiredPhotos
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("ลายเซ็นทั้งสองตรงกับข้อมูลฉบับนี้ เมื่อล็อกแล้วจะแก้ไขได้เฉพาะเมื่อเปิด REV ใหม่ และ REV \(job.rev) จะถูกเก็บไว้พร้อม PDF ตามที่ลงนาม")
                    .font(.sarabun(16, relativeTo: .callout)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Space.s) {
                    row(missing == 0 ? "กรอกครบทุกช่องบังคับ" : "ยังไม่กรอก \(missing) รายการ", ok: missing == 0)
                    row(photos == 0 ? "รูปบังคับครบ" : "ยังขาดรูปบังคับ \(photos) รูป", ok: photos == 0)
                    if let changes { row("แก้จาก REV \(job.previousRevision?.rev ?? "") \(changes) รายการ", ok: true, symbol: "arrow.left.arrow.right") }
                }
                Spacer(minLength: 0)
                TCButton("ล็อกและออก REV \(job.rev)", systemImage: "lock.fill", kind: .primary, fullWidth: true, action: lock)
                TCButton("ยังไม่ล็อก", kind: .secondary, fullWidth: true, action: notNow)
            }
            .padding(Space.xl)
            .navigationTitle("ลงนามครบแล้ว · ล็อกฟอร์ม REV \(job.rev)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
    func row(_ text: String, ok: Bool, symbol: String? = nil) -> some View {
        Label(text, systemImage: symbol ?? (ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
            .font(.sarabun(17, .semibold, relativeTo: .body)).foregroundStyle(ok ? Theme.okText : Theme.pending)
    }
}

/// แก้ไข (เปิด REV nn+1): the reason is required; the date moves to today unless turned off.
struct NextRevisionSheet: View {
    let job: Job
    var confirm: (_ reason: String, _ updateDate: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var updateDate = true
    var body: some View {
        let next = RevisionRule.next(after: job.rev)
        let ok = !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        NavigationStack {
            PadForm(maxWidth: 640) {
                PadSection("เหตุผลที่แก้ไข (ต้องกรอก)") {
                    TextField("เช่น สถานีแจ้งขนาดหม้อแปลงใหม่", text: $reason, axis: .vertical).lineLimit(2...5)
                        .accessibilityIdentifier("nextRevision.reason")
                } footer: {
                    Text("REV \(job.rev) และ PDF ที่ลงนามไว้จะเก็บไว้ตามเดิม · ลายเซ็นทั้งสองจะถูกล้างเพื่อลงนามใหม่สำหรับ REV \(next)")
                }
                PadSection { Toggle("อัปเดตวันที่เป็นวันนี้", isOn: $updateDate) }
            }
            .navigationTitle("เปิดแก้ไขเป็น REV \(next)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เปิด REV \(next)") { confirm(reason, updateDate); dismiss() }.disabled(!ok)
                }
            }
        }
    }
}
#endif
