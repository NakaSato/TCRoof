#if canImport(UIKit) && DEBUG
import SwiftUI

/// Section 5 of the board (sections/05-cards.png).
struct GalleryCards: View {
    @State var tile = 0
    @State var filter = "all"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GalleryGrid(columns: 3, phone: 1, minItem: 400) {
                GalleryItem("การ์ดเมนูหลัก") {
                    TCMenuCard(title: "เครื่องมือวัด", subtitle: "โดรน กล้องความร้อน", symbol: "briefcase.fill") {}
                }
                GalleryItem("การ์ดงาน · PWA") {
                    TCPWAJobCard(number: "NO.224", missing: 3, name: "กปภ. สาขาตัวอย่าง", place: "ต.หนองบัว · 120 kWp",
                                 progress: 0.72, steps: Array(repeating: .done, count: 10) + [.late, .current, .todo],
                                 resume: .init(index: 12, count: 13, step: "D1 ถังน้ำใส"),
                                 sections: ["B ระบบไฟฟ้า ×5", "C หลังคา ×2"],
                                 date: "29/9/2569 · 23:05", sync: .pending, onOpen: {}, onResume: {})
                }
                GalleryItem("การ์ดงานสำรวจ") {
                    TCSurveyJobCard(customer: "คุณนพพร วีระโชติ", team: "TCR03", code: "TCR2569-23403", tag: "ลูกค้าสนใจติดตั้ง",
                                    capacity: "5.5 kW", when: "วันนี้ 09:30 น.", date: "30 ก.ย. 69",
                                    progress: (3, 5, "ระบบไฟฟ้า", 0.4), onOpen: {}, onAction: {})
                }
            }
            GalleryGrid(columns: 3, phone: 1, minItem: 400) {
                GalleryItem("แถวรายการ (แนวนอน)") {
                    VStack(spacing: 10) {
                        TCListRow(symbol: "lock.fill", title: "Fluke 376 FC", code: "TCR-MT-01",
                                  subtitle: "ใช้โดย วิชัย · NO.098 · ถึง 29/9 · เกิน 1 วัน",
                                  status: ("เกินกำหนดคืน", .overdue), trailing: "คิว 1 · ถัดไป สมชาย", overdue: true) {}
                        TCListRow(symbol: "camera.fill", title: "DJI Mavic 3T", code: "TCR-DR-02",
                                  subtitle: "อยู่ห้องเก็บเครื่องมือ", status: ("พร้อมใช้", .ok)) {}
                    }
                }
                GalleryItem("ช่องตัวเลขเป็นตัวกรอง") {
                    HStack(alignment: .top, spacing: 10) {
                        TCNumberTile(value: 7, title: "ทั้งหมด", caption: "งานในเครื่องนี้", selected: tile == 0) { tile = 0 }
                        TCNumberTile(value: 1, title: "เกินกำหนดคืน", caption: "ต้องตามคืน", tint: Theme.dangerText, selected: tile == 1) { tile = 1 }
                    }
                }
                GalleryItem("แถบตัวกรองด้านข้าง") {
                    TCSideFilterList(title: "สถานะ", rows: [
                        .init(id: "all", title: "ทั้งหมด", count: 10, color: Theme.inkMuted),
                        .init(id: "active", title: "ใช้งานอยู่", count: 2, color: Theme.primary),
                        .init(id: "overdue", title: "เกินกำหนดคืน", count: 1, color: Theme.danger, alert: true),
                    ], selection: $filter)
                }
            }
        }
    }
}

#Preview("Cards · iPad", traits: .landscapeLeft) {
    ScrollView { GallerySection(number: 5, title: "การ์ดและรายการ", subtitle: "Cards & lists") { GalleryCards() }.padding() }
}

#Preview("Cards · iPhone") {
    ScrollView { GallerySection(number: 5, title: "การ์ดและรายการ", subtitle: "Cards & lists") { GalleryCards() }.padding() }
        .environment(\.horizontalSizeClass, .compact)
}
#endif
