#if canImport(UIKit) && DEBUG
import SwiftUI

/// Project feed of the iPhone home (docs/ui/tcroof-home-iphone-v3), shown with section 5's cards.
struct GalleryFeed: View {
    @State var filter = 0
    @State var acked: Set<Int> = [1]
    @State var fixed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GalleryItem("ตัวกรองฟีด", note: "สูง 40 pt · พื้นที่แตะ 44 pt") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array([("ทั้งหมด", 5), ("กปภ.", 4), ("งานบ้าน", 2), ("ทีมของฉัน", 3)].enumerated()), id: \.offset) { i, chip in
                            TCFeedChip(chip.0, count: chip.1, selected: filter == i) { filter = i }
                        }
                    }
                }
            }
            GalleryGrid(columns: 3, phone: 1, minItem: 340) {
                GalleryItem("โพสต์สรุป · ช่องตัวเลข") { summary }
                GalleryItem("โพสต์ปัญหา · กล่องผู้รับผิดชอบ", note: "แก้แล้ว / เปิดอีกครั้ง") { issue }
                GalleryItem("โพสต์รายงาน · รูปและป้าย") { progress }
            }
            GalleryGrid(columns: 3, phone: 1, minItem: 340) {
                GalleryItem("กล่องปัญหา") {
                    VStack(spacing: 8) {
                        TCIssueBox(owner: "ทีม B (ตัวอย่าง)", due: "13 ต.ค.", fixed: false) {}
                        TCIssueBox(owner: "ทีม B (ตัวอย่าง)", due: nil, fixed: true) {}
                    }
                }
            }
        }
    }

    private func ack(_ i: Int, _ base: Int) -> String {
        acked.contains(i) ? "คุณและอีก \(base) คนรับทราบ" : "\(base) คนรับทราบ"
    }

    private func toggle(_ i: Int) { acked.formSymmetricDifference([i]) }

    private var summary: some View {
        TCFeedPost(initials: "TC", avatar: Theme.heroSolid, who: "TCRoof", badge: "สรุปวันนี้", tone: .blue, detail: "ทุกโครงการ · 18:00",
                   text: "สรุปวันที่ 12 ต.ค. — ส่งรายงานแล้ว 8/12 สถานี กปภ. ความคืบหน้ารวม +2% ปัญหาค้าง 1 เรื่อง",
                   stats: [.init("8/12", "ส่งรายงาน", .blue), .init("+2%", "ความคืบหน้ารวม", .green), .init("1", "ปัญหาค้าง", .red)],
                   ackLine: ack(0, 5), acknowledged: acked.contains(0), link: "ดูสรุป",
                   menu: [.init("ซ่อนโพสต์นี้", symbol: "eye.slash") {}], onAck: { toggle(0) }, onOpen: {})
    }

    private var issue: some View {
        TCFeedPost(initials: "B", avatar: Theme.dangerText, who: "ทีม B · งานบ้าน", badge: "ปัญหา", tone: .red,
                   detail: "TC-0012 · ติดตั้ง Day 2/5 · 3 ชม.",
                   text: "พบรอยรั่วที่ครอบหลังคาจุด B3 หลังเจาะยึดราง ต้องอุดซิลิโคนและทดสอบน้ำก่อนวางแผงแถว B",
                   issue: .init(owner: "ทีม B (ตัวอย่าง)", due: "13 ต.ค.", fixed: fixed) { fixed.toggle() },
                   ackLine: ack(1, 1), acknowledged: acked.contains(1), link: "ดูงาน", onAck: { toggle(1) }, onOpen: {})
    }

    private var progress: some View {
        TCFeedPost(initials: "A", avatar: Theme.primary, who: "ทีม A · ผู้รับเหมา A", badge: "รายงานวันนี้", tone: .blue,
                   detail: "MP 189 ทุ่งน้อย · 2.3 ติดตั้งแผง · 25 นาที",
                   text: "วางแผงแถว C เสร็จ 48/120 แผง ขันทอร์กครบ เหลือแถว D พรุ่งนี้เช้า",
                   photoCount: 4, photoChips: [.init("+6% วันนี้", .green), .init("38% / แผน 50%", .red)],
                   ackLine: ack(2, 4), acknowledged: acked.contains(2), link: "ดูรายงาน", onAck: { toggle(2) }, onOpen: {}) { i in
            TCFeedExamplePhoto(i.isMultiple(of: 2) ? .roof : .inverters)
        }
    }
}

#Preview("Feed · iPhone") {
    ScrollView { GalleryFeed().padding() }.background(Theme.phonePage)
}
#endif
