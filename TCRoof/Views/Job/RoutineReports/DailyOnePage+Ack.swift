import SwiftUI
import TCRoofUI
import TCRoofCore

// The TC team's view of a sent report (docs/ui/daily-report-ipad-v4): the `ลงนามรับทราบ` card in place of the
// reporter's sign card, and a bar that acknowledges or sends the report back. The acknowledgement is the one the
// daily list and the feed record (`Job.recordInspectorAck`), signed through the same `InspectorAckSheet`.

/// A line's photos full screen, from the TC view's thumbnails.
struct ViewedPhotos: Identifiable {
    let id = UUID()
    let images: [Data]
    let start: Int
}

/// `ลงนามรับทราบ`: who sent the report, the inspector's signature box, and the inspector's name.
struct DailyAckCard: View {
    let page: DailyOnePage

    private var engineer: String { page.settings.siteEngineer }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ลงนามรับทราบ").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
            reporterRow
            Group {
                if let at = page.ackAt { signedBox(at) } else { idleBox }
            }
            .frame(height: 170)
            nameField
        }
        .padding(16)
        .dailyCard()
    }

    private var reporterRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                .frame(width: 26, height: 26).background(Theme.success, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text("ผู้รายงาน " + engineer).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Text("SITE ENGINEER ผู้รับเหมา ลงนามและส่งแล้ว " + (page.signedAt.map { ThaiFormat.time.string(from: $0) } ?? ""))
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.successText).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).frame(height: 52)
        .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.success, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// The hairline the inspector signs on, 40 pt above the box's bottom, with a small × at its left end.
    private func signLine(_ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                .padding(.leading, 2)
            Rectangle().fill(color).frame(height: 1)
        }
        .padding(.horizontal, 18).padding(.bottom, 40)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var idleBox: some View {
        Button(action: page.actions.acknowledge) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.permitFill)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.inkFaint, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                signLine(Theme.borderOutdoor)
                VStack(spacing: 2) {
                    Image(systemName: "signature").font(.system(size: 20, weight: .semibold))
                    Text("แตะเพื่อเซ็นรับทราบ").font(.sarabunFixed(15, .bold))
                    Text("ตรวจงานในหน้านี้และ PDF ก่อนเซ็น").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                }
                .foregroundStyle(Theme.planInspect)
                .padding(.bottom, 36)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ผู้ตรวจงาน แตะเพื่อเซ็นรับทราบ")
        .accessibilityIdentifier("dailyAck")
    }

    private func signedBox(_ at: Date) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.planInspectSoft.opacity(0.5))
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.planInspect, lineWidth: 1)
            signLine(Theme.planInspect.opacity(0.3))
            signature
                .padding(.bottom, 34)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .overlay(alignment: .topLeading) {
            Label("รับทราบแล้ว " + ThaiFormat.time.string(from: at), systemImage: "checkmark")
                .font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.planInspect)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Theme.planInspectSoft, in: Capsule())
                .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: page.clearAck) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ล้างลายเซ็นรับทราบ")
        }
        .accessibilityIdentifier("dailyAckSigned")
    }

    /// The drawn signature when there is one, else the name in italics.
    @ViewBuilder private var signature: some View {
        let name = page.settings.inspector
        if let drawn = page.ackDrawn, let image = UIImage(data: drawn) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 220, maxHeight: 82)
                .accessibilityLabel("ลายเซ็นรับทราบ " + name)
        } else {
            Text(name.isEmpty ? "รับทราบแล้ว" : name)
                .font(.sarabunFixed(22, .bold)).italic().foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 24)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ชื่อผู้ตรวจงาน").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
            TextField("ชื่อผู้ตรวจงาน ทีม TC", text: inspectorName)
                .font(.sarabunFixed(17)).multilineTextAlignment(.center)
                .textFieldStyle(OutlinedFieldStyle(dense: true))
                .frame(minHeight: 48)
        }
    }

    private var inspectorName: Binding<String> {
        let job = page.job
        return Binding(get: { job.routineSettings.inspector }, set: { v in
            var s = job.routineSettings
            s.inspector = v
            job.routineSettings = s
        })
    }
}

/// The TC view's bottom bar: the report's state, `ส่งกลับให้แก้`, the PDF preview and `ยืนยันรับทราบ`.
struct DailyAckBar: View {
    let page: DailyOnePage

    private var acked: Bool { page.ackAt != nil }

    var body: some View {
        HStack(spacing: 12) {
            status
            Spacer(minLength: 12)
            sendBackButton
            previewButton
            confirmButton
        }
        .padding(.horizontal, 63).padding(.vertical, 10)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }

    private var status: some View {
        let sent = page.signedAt.map { ThaiFormat.time.string(from: $0) } ?? ""
        return HStack(spacing: 12) {
            Image(systemName: acked ? "checkmark" : "exclamationmark").font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.onPrimary).frame(width: 28, height: 28)
                .background(acked ? Theme.planInspect : Theme.warning, in: Circle())
            Text(acked ? "เซ็นรับทราบแล้ว | ส่งกลับไปยังผู้รับเหมาและลงใน PDF หน้า 3"
                       : "ผู้รับเหมาส่งรายงานแล้ว \(sent) | รอทีม TC ตรวจและเซ็นรับทราบ")
                .font(.sarabunFixed(14)).foregroundStyle(acked ? Theme.planInspect : Theme.navy)
                .lineLimit(2).minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
    }

    private var sendBackButton: some View {
        Button { page.askSendBack = true } label: {
            Text("ส่งกลับให้แก้").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.pending).frame(width: 150, height: 44)
        }
        .buttonStyle(TCButtonStyle(.secondary, size: .card))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Theme.pending.opacity(0.6)))
        .accessibilityIdentifier("dailySendBack")
    }

    private var previewButton: some View {
        Button(action: page.actions.preview) {
            VStack(spacing: 0) {
                Text("PDF 3 หน้า").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                Text("ดูตัวอย่างรายงาน").font(.sarabunFixed(16, .bold))
            }
            .frame(width: 190, height: 44)
        }
        .buttonStyle(TCButtonStyle(.secondary, size: .card))
    }

    private var confirmButton: some View {
        Button(action: page.confirmAck) {
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text(acked ? "เซ็นแล้ว" : "ยังไม่ได้เซ็นรับทราบ").font(.sarabunFixed(12)).opacity(0.85).lineLimit(1)
                    Text("ยืนยันรับทราบ").font(.sarabunFixed(16, .bold))
                }
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
            }
            .frame(width: 190, height: 44)
        }
        .buttonStyle(TCButtonStyle(.primary, size: .card, tint: Theme.planInspect))
        .disabled(!acked)
        .accessibilityIdentifier("dailyAckConfirm")
    }
}
