#if canImport(UIKit) && DEBUG
import SwiftUI

/// Section 7 of the board (sections/07-overlays.png): each overlay drawn in place, and a button that opens it live.
struct GalleryOverlays: View {
    @State var condition = 0
    @State var dialog = false
    @State var alert = false
    @State var panel = false
    @State var unread = true

    var body: some View {
        GalleryGrid(columns: 5, phone: 1, minItem: 300) {
            GalleryItem("Dialog กลางจอ") {
                dialogSample
                TCButton("เปิดจริง", kind: .text, size: .card) { dialog = true }
            }
            GalleryItem("Alert") {
                alertSample
                TCButton("เปิดจริง", kind: .text, size: .card) { alert = true }
            }
            GalleryItem("แผงรายละเอียดด้านขวา") {
                GeometryReader { g in
                    ZStack(alignment: .trailing) {
                        Theme.disabledFill
                        Theme.navy.opacity(0.35)
                        TCDetailPanel(title: "Mavic 3T", actionTitle: "คืนอุปกรณ์", actionSymbol: "arrow.left", onClose: {}) {
                            placeholderRow
                            placeholderRow.frame(height: 36)
                        }
                        .frame(width: max(200, g.size.width * 0.62))
                        .padding(10)
                    }
                }
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                TCButton("เปิดจริง", kind: .text, size: .card) { panel = true }
            }
            GalleryItem("แบนเนอร์ iOS + ปุ่มทำงานด่วน") {
                TCNotificationBannerSample(title: "ถึงคิวคุณ · DJI Mavic 3T", message: "รับได้ที่ห้องเก็บเครื่องมือ",
                                           actions: [.init("รับเครื่อง · ถ่ายภาพ", systemImage: "camera"),
                                                     .init("ดูคิว", systemImage: "list.bullet")])
            }
            GalleryItem("แผงการแจ้งเตือนในแอป") {
                TCNotificationPanel(items: [.init(id: "1", systemImage: "list.clipboard", title: "นัดสำรวจ 09:30",
                                                  detail: "NO.224 กปภ. สาขาตัวอย่าง", unread: unread)],
                                    onReadAll: { unread = false }, onOpen: { _ in unread = false })
            }
        }
        .tcDialog(isPresented: $dialog, title: "บันทึกการคืน", subtitle: "Fluke 376 FC · S/N 58720413", confirmTitle: "บันทึกการคืน",
                  confirmDisabledReason: condition == 1 ? "ใส่หมายเหตุสภาพก่อน" : nil, onConfirm: {}) {
            TCSmallSegmented(["ปกติ", "ชำรุด / ไม่ครบ"], selection: $condition)
        }
        .tcAlert(isPresented: $alert, title: "รายงานยังไม่มีลายเซ็น", message: "ส่งออกเป็นฉบับร่าง หรือไปลงนามก่อน",
                 actions: alertActions)
        .tcDetailPanel(isPresented: $panel, title: "Mavic 3T", actionTitle: "คืนอุปกรณ์", actionSymbol: "arrow.left") {
            placeholderRow
            placeholderRow
        }
    }

    var dialogSample: some View {
        TCDialog(title: "บันทึกการคืน", subtitle: "Fluke 376 FC · S/N 58720413", confirmTitle: "บันทึกการคืน",
                 confirmDisabledReason: nil, onCancel: {}, onConfirm: {}) {
            TCSmallSegmented(["ปกติ", "ชำรุด / ไม่ครบ"], selection: .constant(0))
        }
    }

    var alertSample: some View { TCAlertCard(title: "รายงานยังไม่มีลายเซ็น", message: "ส่งออกเป็นฉบับร่าง หรือไปลงนามก่อน", actions: alertActions) }

    var alertActions: [TCAlertCard.Action] {
        [.init("ไปลงนาม", kind: .primaryGradient) {},
         .init("ส่งออกเป็นฉบับร่าง", kind: .secondary) {},
         .init("ยกเลิก", kind: .text) {}]
    }

    var placeholderRow: some View {
        RoundedRectangle(cornerRadius: Radius.md).fill(Theme.background).frame(height: 56)
    }
}

#Preview("Overlays · iPad", traits: .landscapeLeft) {
    ScrollView { GallerySection(number: 7, title: "หน้าต่างซ้อน และการแจ้งเตือน", subtitle: "Overlays") { GalleryOverlays() }.padding() }
}

#Preview("Overlays · iPhone") {
    ScrollView { GallerySection(number: 7, title: "หน้าต่างซ้อน และการแจ้งเตือน", subtitle: "Overlays") { GalleryOverlays() }.padding() }
        .environment(\.horizontalSizeClass, .compact)
}
#endif
