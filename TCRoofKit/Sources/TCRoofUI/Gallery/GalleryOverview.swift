#if canImport(UIKit) && DEBUG
import SwiftUI

/// Parts of the PWA project home on iPhone (docs/ui/pwa-solar-survey-iphone-v2), shown with section 5's cards.
struct GalleryOverview: View {
    @State var stage = 0
    @State var calendar = 0
    @State var filter = 0
    @State var remind = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GalleryItem("สวิตช์มุมมอง + ตัวกรองแถว", note: "ราง 44 ช่อง 38 กว้างเท่ากัน ตัวเลขแดงเมื่อเตือน | ตัวกรองแถวสูง 40 พื้นที่แตะ 44") {
                VStack(alignment: .leading, spacing: 8) {
                    TCCountSegments([.init("ตารางงาน", count: 7), .init("แผน MP", count: 12), .init("กำหนดส่ง", count: 9, alert: true)],
                                    selection: $stage)
                    TCCountSegments([.init("สัปดาห์"), .init("เดือน")], selection: $calendar, equalWidths: false)
                    HStack(spacing: 6) {
                        ForEach(Array([("ช้ากว่าแผน", 4), ("ยังไม่ส่งรายงาน", 4), ("ทั้งหมด", 12)].enumerated()), id: \.offset) { i, p in
                            TCCountPill(p.0, count: p.1, selected: filter == i) { filter = i }
                        }
                    }
                }
            }
            .frame(maxWidth: 390, alignment: .leading)
            GalleryGrid(columns: 3, phone: 1, minItem: 340) {
                GalleryItem("วงแหวน 64 + ขีดแผน", note: "ส่วนโค้ง = ทำได้ | ขีดกรมท่า = แผน") {
                    HStack(spacing: 16) {
                        TCPlanRing(actual: 0.47, plan: 0.48)
                        TCPlanRing(actual: 0.84, tint: Theme.success)
                    }
                }
                GalleryItem("แถบ 8 + ขีดแผน 2 × 14", note: "แดง = ช้ากว่าแผน") {
                    VStack(spacing: 10) {
                        TCPlanBar(actual: 0.38, plan: 0.5, tint: Theme.danger)
                        TCPlanBar(actual: 0.71, plan: 0.68)
                        TCPlanBar(actual: 0.52, tint: Theme.success)
                    }
                }
                GalleryItem("ช่องตัวเลข + ป้ายสถานะ") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            TCStatTile("4", "ช้ากว่าแผน", tone: .red)
                            TCStatTile("2", "ตามแผน", tone: .blue)
                            TCStatTile("6", "เร็วกว่าแผน", tone: .green)
                            TCStatTile("1", "ออฟไลน์", tone: nil)
                        }
                        HStack(spacing: 6) {
                            TCToneChip("ช้ากว่า 12%", tone: .red)
                            TCToneChip("ตามแผน", tone: .blue)
                            TCToneChip("รายงานวันนี้ ✓", tone: .green)
                            TCToneChip("ยังไม่ส่งรายงาน", tone: .orange)
                        }
                    }
                }
            }
            GalleryItem("กลุ่มตั้งค่า", note: "การ์ด r16 ขอบ 1 | แถว ≥ 50 | หัวกลุ่ม 12 หนา") {
                TCSettingsGroup("รายงานประจำวัน") {
                    TCSettingsRow("แจ้งเตือนก่อนหมดเวลาส่ง", detail: "ส่งภายใน 18:00") { Toggle("", isOn: $remind).labelsHidden().tint(Theme.success) }
                    TCSettingsRow("ผู้ตรวจงานเริ่มต้น", detail: "ของแต่ละสถานี")
                    TCSettingsRow("ซิงก์ทั้งหมดตอนนี้") { TCToneChip("ซิงก์ 2", tone: .blue) }
                }
            }
            .frame(maxWidth: 390, alignment: .leading)
        }
    }
}
#endif
