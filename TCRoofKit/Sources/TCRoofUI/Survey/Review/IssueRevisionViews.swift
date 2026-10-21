#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// E1: both have signed and these answers aren't issued yet: ออก REV nn. Issuing locks nothing.
struct IssueRevisionBanner: View {
    let rev: String
    var issue: () -> Void
    var body: some View {
        HStack(spacing: Space.m) {
            Label("ลงนามครบแล้ว | ยังไม่ออก REV \(rev)", systemImage: "signature")
                .font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
            Spacer(minLength: Space.s)
            TCButton("ออก REV \(rev)", systemImage: "doc.badge.plus", kind: .primary, size: .card, action: issue).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// ออก REV nn: the gaps as warnings that don't block, the reason from the second REV on, then issue. The REV is kept
/// with its PDF; the form stays editable, and the next issue takes the next number.
struct IssueRevisionSheet: View {
    let job: Job
    /// Rows changed since the last issued REV; nil before the first.
    let changes: Int?
    var issue: (_ reason: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    var body: some View {
        let rev = job.nextIssueRev
        let missing = job.missingItems.count, photos = job.missingRequiredPhotos
        let ok = !job.issueNeedsReason || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        NavigationStack {
            PadForm(maxWidth: 640) {
                PadSection {
                    row(missing == 0 ? "กรอกครบทุกช่องบังคับ" : "ยังไม่กรอก \(missing) รายการ", ok: missing == 0)
                    row(photos == 0 ? "รูปบังคับครบ" : "ยังขาดรูปบังคับ \(photos) รูป", ok: photos == 0)
                    if let changes, let prev = job.lastRevision { row("แก้จาก REV \(prev.rev) \(changes) รายการ", ok: true, symbol: "arrow.left.arrow.right") }
                } footer: {
                    Text("REV \(rev) จะเก็บไว้พร้อม PDF ตามข้อมูลและลายเซ็นตอนนี้ | ฟอร์มยังแก้ไขได้ และครั้งต่อไปจะออกเป็น REV \(RevisionRule.next(after: rev))")
                }
                if job.issueNeedsReason {
                    PadSection("เหตุผลที่แก้ไข (ต้องกรอก)") {
                        TextField("เช่น สถานีแจ้งขนาดหม้อแปลงใหม่", text: $reason, axis: .vertical).lineLimit(2...5)
                            .accessibilityIdentifier("issueRevision.reason")
                    } footer: {
                        Text("ตรวจว่าลายเซ็นทั้งสองเป็นของข้อมูลฉบับนี้")
                    }
                }
            }
            .navigationTitle("ออก REV \(rev)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ออก REV \(rev)") { issue(reason); dismiss() }.disabled(!ok)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    func row(_ text: String, ok: Bool, symbol: String? = nil) -> some View {
        Label(text, systemImage: symbol ?? (ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
            .font(.sarabun(17, .semibold, relativeTo: .body)).foregroundStyle(ok ? Theme.okText : Theme.pending)
    }
}
#endif
