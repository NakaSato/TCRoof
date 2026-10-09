#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// A2 on iPhone: the step line, then four full-width bands — picture source and preview, symbols, LIST, site note.
/// The picture is edited full screen (`fullScreenView`, the same editor as the iPad's); the preview here only shows it
/// and opens it. Field ids and storage are the iPad's.
extension SitePageWide {
    var phoneBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                PageStepBar(job: job, here: .site, compact: true, chip: stepChip)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
                PhoneBand(number: "01", title: "ภาพมุมสูง", chip: pictureChip) { pictureFields }
                PhoneBand(number: "02", title: "สัญลักษณ์บนภาพ", chip: PhoneBand<EmptyView>.noteChip("วางแล้ว \(placedCount)/\(paletteTools.count)")) { paletteSection }
                PhoneBand(number: "03", title: "LIST", chip: PhoneBand<EmptyView>.countChip(list.count, Options.list.count)) { listSection }
                PhoneBand(number: "04", title: "หมายเหตุหน้างาน", chip: PhoneBand<EmptyView>.noteChip("ไม่บังคับ"), last: true) { noteSection }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
        #if DEBUG
        .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "surveyScrollEnd") ? .bottom : .top)
        #endif
    }

    /// `ครบ n/m ช่อง` (green) or `ขาด n ช่อง` (orange), from the page's own completion (picture and north).
    var stepChip: (text: String, ok: Bool)? {
        guard let c = job.steps.first(where: { $0.page == .site })?.completion, c.total > 0 else { return nil }
        return c.isComplete ? ("ครบ \(c.filled)/\(c.total) ช่อง", true) : ("ขาด \(c.total - c.filled) ช่อง", false)
    }

    /// Picture and north are the page's required answers.
    var pictureChip: PhoneBand<EmptyView>.Chip {
        let done = (photo != nil ? 1 : 0) + (job.values.text("north").isEmpty ? 0 : 1)
        return PhoneBand<EmptyView>.countChip(done, 2)
    }

    var placedCount: Int { paletteTools.filter(placed).count }

    @ViewBuilder var pictureFields: some View {
        sourceSection
        picturePreview
    }

    /// The picture with its symbols and drawings, not interactive; tapping it opens the full-screen editor.
    var picturePreview: some View {
        Button { fullScreen = true } label: {
            GeometryReader { geo in
                stage(geo.size, full: false).allowsHitTesting(false)
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.hairline))
            .overlay(alignment: .bottomTrailing) {
                Label(photo == nil ? "เลือกภาพก่อน" : "แตะเพื่อแก้ไขเต็มจอ", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Home.primary)
                    .padding(.horizontal, 10).frame(minHeight: 32)
                    .background(Color.white.opacity(0.95), in: Capsule())
                    .shadow(color: Home.navy.opacity(0.2), radius: 2, y: 1)
                    .padding(8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(photo == nil)
        .accessibilityLabel("ภาพสถานที่ติดตั้ง")
        .accessibilityHint("แตะเพื่อเปิดเต็มจอและแก้ไขสัญลักษณ์")
    }
}
#endif
