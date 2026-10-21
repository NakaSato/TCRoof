#if canImport(UIKit) && DEBUG
import SwiftUI

/// Section 4 of the board (sections/04-status.png).
struct GalleryStatus: View {
    @State var toast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GalleryGrid(columns: 3, phone: 1) {
                GalleryItem("ป้ายสถานะ") {
                    FlowRow {
                        TCStatusChip("พร้อมใช้", kind: .ok, dot: true)
                        TCStatusChip("ใช้งานอยู่", kind: .active, dot: true)
                        TCStatusChip("เกินกำหนดคืน", kind: .overdue, dot: true)
                        TCStatusChip("ส่งซ่อม", kind: .pending, dot: true)
                        TCStatusChip("ครบ", kind: .done)
                        TCStatusChip("ขาด 3 ช่อง", kind: .pending)
                    }
                }
                GalleryItem("ป้ายข้อมูลตัวอย่าง / ทีม") {
                    FlowRow {
                        TCSampleChip()
                        TCTeamChip("TCR03")
                        TCSampleValue()
                    }
                }
                GalleryItem("จุดสถานะ + ข้อความ") {
                    VStack(alignment: .leading, spacing: 6) {
                        TCDotLine("พร้อมใช้", kind: .ok)
                        TCDotLine("เกินกำหนดคืน | เกิน 1 วัน", kind: .overdue)
                    }
                }
            }
            GalleryGrid(columns: 3, phone: 1) {
                GalleryItem("วงแหวน %", note: "ความคืบหน้า / วันที่เหลือก่อนครบสอบเทียบ") {
                    HStack(spacing: 12) {
                        TCProgressRing(.percent(0.72))
                        TCProgressRing(.percent(1))
                        TCProgressRing(.days(76, total: 365))
                        TCProgressRing(.days(-10, total: 365))
                    }
                }
                GalleryItem("แถบแบ่งช่อง") {
                    VStack(spacing: 8) {
                        TCSegmentedProgress(Array(repeating: .done, count: 10) + [.late, .current, .todo])
                        TCSegmentedProgress([.done, .done, .current, .todo, .todo], thin: false)
                    }
                }
                GalleryItem("แถบ \"ทำต่อ\"") {
                    TCResumeStrip(index: 12, count: 13, step: "D1 ถังน้ำใส") {}
                }
            }
            GalleryGrid(columns: 4, phone: 1) {
                GalleryItem("แถบเตือน") { TCWarningBanner("เสี่ยงปานกลาง", message: "ท่วม 7 ใน 14 ปี | สูงสุด 50 ซม.") }
                GalleryItem("กล่องผลสรุป") { TCResultBox("โหลดรวม 107 kW น้อยกว่า PV 120 kW → ต้องมีระบบกันย้อน (B4)") }
                GalleryItem("บรรทัดยังขาด") { TCMissingLine("ยังขาด — โรงกรอง: ภาพมุมกว้าง") }
                GalleryItem("Toast", note: "แตะปุ่มเพื่อแสดง | หายเองใน 2.5 วินาที") {
                    VStack(alignment: .leading, spacing: 8) {
                        TCToast("บันทึกร่างแล้ว | 10:24")
                        TCButton("แสดง toast", kind: .secondary, size: .card) { toast = "บันทึกร่างแล้ว | 10:24" }
                    }
                }
            }
        }
        .tcToast($toast)
    }
}

/// Chips that wrap onto new lines, 6 pt apart.
private struct FlowRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        WrapLayout(spacing: 6) { content }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }

    func arrange(width: CGFloat, subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var cur: [Int] = [], w: CGFloat = 0, h: CGFloat = 0
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if !cur.isEmpty && w + spacing + s.width > width {
                rows.append((cur, w, h)); cur = []; w = 0; h = 0
            }
            w += (cur.isEmpty ? 0 : spacing) + s.width
            h = max(h, s.height)
            cur.append(i)
        }
        if !cur.isEmpty { rows.append((cur, w, h)) }
        return rows
    }
}

#Preview("Status | iPad", traits: .landscapeLeft) {
    ScrollView { GallerySection(number: 4, title: "สถานะและข้อความแจ้ง", subtitle: "Status & feedback") { GalleryStatus() }.padding() }
}

#Preview("Status | iPhone") {
    ScrollView { GallerySection(number: 4, title: "สถานะและข้อความแจ้ง", subtitle: "Status & feedback") { GalleryStatus() }.padding() }
        .environment(\.horizontalSizeClass, .compact)
}
#endif
