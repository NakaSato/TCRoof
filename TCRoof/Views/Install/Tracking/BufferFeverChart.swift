import SwiftUI
import TCRoofUI
import TCRoofCore

/// The buffer-consumption ("fever") chart (CHA-87, `ScheduleBuffer`): % of the work done across, % of the schedule
/// buffer used up; green under the diagonal (the buffer used no faster than the work), amber up to a third ahead,
/// red beyond or once it is all used. The weekly points join into a line ending on today's dot. Vector, as every plan.
struct BufferFeverChart: View {
    let status: ScheduleBuffer.Status
    /// Axis labels and the zone names; off for the small inline chart.
    var labelled = true

    private var top: Double { max(120, (status.history.map(\.used).max() ?? 0) + 10) }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, top = self.top
            func p(_ done: Double, _ used: Double) -> CGPoint { CGPoint(x: w * done / 100, y: h * (1 - min(used, top) / top)) }
            let m = ScheduleBuffer.redMargin
            func shape(_ pts: [CGPoint]) -> Path { Path { $0.addLines(pts); $0.closeSubpath() } }
            // red everywhere; amber up to a third ahead of the work; green at or under the diagonal; red again once all is used
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.dangerSoft))
            ctx.fill(shape([p(0, 0), p(100, 100), p(100, 100 + m), p(0, m)]), with: .color(Theme.warningSoft))
            ctx.fill(shape([p(0, 0), p(100, 0), p(100, 100)]), with: .color(Theme.successSoft))
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: p(0, 100).y)), with: .color(Theme.dangerSoft))
            ctx.stroke(Path { $0.move(to: p(0, 100)); $0.addLine(to: p(100, 100)) }, with: .color(Theme.dangerLine), lineWidth: 1)
            var line = Path()
            for (i, pt) in status.history.enumerated() {
                i == 0 ? line.move(to: p(pt.done, pt.used)) : line.addLine(to: p(pt.done, pt.used))
            }
            ctx.stroke(line, with: .color(Theme.navy), lineWidth: labelled ? 1.5 : 1.2)
            let now = p(status.now.done, status.now.used), r: CGFloat = labelled ? 5 : 3.5
            ctx.fill(Path(ellipseIn: CGRect(x: now.x - r, y: now.y - r, width: 2 * r, height: 2 * r)), with: .color(Self.ink(status.zone)))
        }
        .overlay(alignment: .bottomTrailing) {
            if labelled { axisLabel("งานเสร็จ %").padding(4) }
        }
        .overlay(alignment: .topLeading) {
            if labelled { axisLabel("บัฟเฟอร์ใช้ไป %").padding(4) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(status))
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text).font(.sarabun(10)).foregroundStyle(Theme.inkMuted)
    }

    static func ink(_ zone: ScheduleBuffer.Zone) -> Color {
        switch zone {
        case .green: Theme.successInk
        case .amber: Theme.warningInk
        case .red: Theme.dangerText
        }
    }

    static func title(_ zone: ScheduleBuffer.Zone) -> String {
        switch zone {
        case .green: "ปกติ"
        case .amber: "ใช้เร็วกว่างาน"
        case .red: "วิกฤต"
        }
    }

    /// `ใช้ 40%`.
    static func used(_ s: ScheduleBuffer.Status) -> String { "ใช้ \(Int(s.now.used.rounded()))%" }

    /// `เหลือ 6 จาก 19 วัน`, or `เกิน 3 วัน` past the protected date.
    static func left(_ s: ScheduleBuffer.Status) -> String {
        s.remainingDays >= 0 ? "เหลือ \(s.remainingDays) จาก \(s.size.total) วัน" : "เกิน \(-s.remainingDays) วัน"
    }

    static func summary(_ s: ScheduleBuffer.Status) -> String {
        "บัฟเฟอร์กำหนดการ \(used(s)) \(left(s)) งานเสร็จ \(Int(s.now.done.rounded()))% \(title(s.zone))"
    }
}

/// The popover the iPad's `บัฟเฟอร์` KPI cell opens: the chart, the buffer's make-up and the protected date.
struct BufferExplanation: View {
    let status: ScheduleBuffer.Status

    var body: some View {
        let s = status
        VStack(alignment: .leading, spacing: 10) {
            Text("บัฟเฟอร์กำหนดการ").font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
            BufferFeverChart(status: s).frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("\(BufferFeverChart.used(s)) | \(BufferFeverChart.left(s)) | งานเสร็จ \(Int(s.now.done.rounded()))%")
                .font(.sarabun(13, .bold)).foregroundStyle(BufferFeverChart.ink(s.zone)).monospacedDigit()
            Text("สำรองความเสี่ยงงานราชการ \(s.size.contingency) วัน + สำรองบริหาร 10% \(s.size.management) วัน | ป้องกันวันที่ \(ThaiFormat.numericDate.string(from: s.protectedDate))")
                .font(.sarabun(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            Text("เขียว ใช้ไม่เร็วกว่างาน · เหลือง ใช้เร็วกว่างาน · แดง เร็วกว่างานเกิน 33% หรือใช้หมด")
                .font(.sarabun(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(Theme.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kpi.buffer.popover")
    }
}
