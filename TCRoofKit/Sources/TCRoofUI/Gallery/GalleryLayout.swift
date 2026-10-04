#if canImport(UIKit) && DEBUG
import SwiftUI

/// Section 1 of the board (sections/01-layout.png).
struct GalleryLayout: View {
    @State var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GalleryGrid(columns: 2, minItem: 560) {
                GalleryItem("Header · แบบสำรวจ + แถบ 13 ขั้น", note: "g-head + g-prog / g-caps (ok · cur · ว่าง)") {
                    TCSurveyHeader(title: "B1 ตู้พิจารณาเชื่อมต่อ", subtitle: "แบบสำรวจ NO.224 · GRF2567-23407",
                                   step: 5, count: 13, stepName: "ตู้พิจารณาเชื่อมต่อ · 3 อาคาร")
                        .framed()
                }
                GalleryItem("Header · PWA", note: "ชื่อ 30 px · ช่องค้นหาในหัว · มุมล่างโค้ง 15") {
                    TCPWAHeader(title: "PWA Solar Survey", subtitle: "แบบสำรวจเพื่อออกแบบ (เบื้องต้น)", search: $search, onBack: {})
                }
            }
            GalleryGrid(columns: 2, minItem: 560) {
                GalleryItem("Nav bar สีขาว (pc-nav)", note: "หมวดสำรวจหน้างาน / แผนก่อสร้าง") {
                    TCNavBar(title: "สำรวจหน้างาน", trail: ["หน้าหลัก", "สำรวจหน้างาน"], current: "รายการงานสำรวจ", onBack: {}) {
                        TCButton("ประวัติการสำรวจ", kind: .secondary) {}
                    }
                    .framed()
                }
            }
            GalleryGrid(columns: 1) {
                GalleryItem("แถบล่าง (g-bar)", note: "ปุ่มสถานะ (แตะไปยังรายการที่ขาด) · บันทึกร่าง · ก่อนหน้า ติดกับ ถัดไป · สูง 53") {
                    TCStepBar(count: 13, previous: .init(index: 4, title: "A4 น้ำท่วม"), next: .init(index: 6, title: "B2 พื้นที่อินเวอร์เตอร์"),
                              missing: 7, missingDetail: "อาคารนี้: ภาพเบรกเกอร์", onSave: {}, onPrevious: {}, onNext: {})
                        .framed()
                }
            }
            GalleryGrid(columns: 3, minItem: 280) {
                GalleryItem("โครงจอ 2 คอลัมน์") {
                    TCFractionColumns(TCPageColumns<EmptyView>.twoColumn, spacing: 8) { slot("ฟอร์ม / ภาพ"); slot("การ์ดข้อมูล", soft: true) }
                }
                GalleryItem("โครงจอ 3 ช่อง") {
                    TCFractionColumns(TCPageColumns<EmptyView>.threePane, spacing: 8) { slot("ตัวกรอง"); slot("รายการ", soft: true); slot("รายละเอียด") }
                }
                GalleryItem("กริดการ์ด 3 คอลัมน์") {
                    TCFractionColumns([1, 1, 1], spacing: 8) { slot("การ์ด", soft: true); slot("การ์ด", soft: true); slot("การ์ด", soft: true) }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("iPhone · 390 × 844").font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                Text("โครงเดียวกัน ย่อให้พอดีจอเดียว · ด้านบนคือ iPad 1366 × 1024").font(.sarabun(12.5)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }

            GalleryGrid(columns: 3, minItem: 390) { phoneSamples }
        }
    }

    @ViewBuilder var phoneSamples: some View {
        GalleryItem("Header + แถบ 13 ขั้น", note: "ชื่อ 19 / รอง 13 · บรรทัดขั้น + ป้ายสถานะ · แถบสูง 6 (เขียว = ครบ · น้ำเงิน = ขั้นนี้)") {
            TCSurveyHeader(title: "B1 ตู้พิจารณาเชื่อมต่อ", subtitle: "แบบสำรวจ NO.224 · GRF2567-23407", step: 5, count: 13, stepName: "ตู้พิจารณาเชื่อมต่อ") {
                Text("ขาด 2 ช่อง").font(.sarabun(11.5, .bold)).foregroundStyle(Theme.pending)
                    .padding(.horizontal, 8).padding(.vertical, 1).background(Theme.pendingSoft, in: Capsule())
            }
            .environment(\.horizontalSizeClass, .compact)
            .framed()
        }
        .frame(maxWidth: 390, alignment: .leading)
        GalleryItem("แถบล่าง", note: "บันทึก ยืดเต็ม · ‹ › 72 × 53 ไอคอนอย่างเดียว · ไม่มีปุ่มสถานะ (ป้ายอยู่ที่บรรทัดขั้น)") {
            TCStepBar(count: 13, previous: .init(index: 4, title: "A4 น้ำท่วม"), next: .init(index: 6, title: "B2 พื้นที่อินเวอร์เตอร์"),
                      missing: 2, missingDetail: "", onSave: {}, onPrevious: {}, onNext: {})
                .environment(\.horizontalSizeClass, .compact)
                .framed()
        }
        .frame(maxWidth: 390, alignment: .leading)
        GalleryItem("โครงจอ 1 คอลัมน์", note: "ขอบ 16 · การ์ด r16 ห่าง 12 · เลื่อนในแนวตั้ง") {
            VStack(spacing: Space.m) {
                slot("การ์ด 1", soft: true, height: 100)
                slot("การ์ด 2", soft: true, height: 52)
                slot("การ์ด 3", soft: true, height: 52)
            }
            .padding(Space.l)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.borderSubtle))
        }
        .frame(maxWidth: 260, alignment: .leading)
    }

    func slot(_ title: String, soft: Bool = false, height: CGFloat = 120) -> some View {
        Text(title).font(.sarabun(12.5)).foregroundStyle(Theme.inkMuted)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(soft ? Theme.progressBox : Theme.background, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.chevron, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

private extension View {
    /// The board's sample frame: radius 12, subtle border, clipped.
    func framed() -> some View {
        clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.borderSubtle))
    }
}

#Preview("Layout · iPad", traits: .landscapeLeft) {
    ScrollView { GallerySection(number: 1, title: "โครงหน้า", subtitle: "Layout") { GalleryLayout() }.padding() }
}

#Preview("Layout · iPhone") {
    ScrollView { GallerySection(number: 1, title: "โครงหน้า", subtitle: "Layout") { GalleryLayout() }.padding() }
        .environment(\.horizontalSizeClass, .compact)
}
#endif
