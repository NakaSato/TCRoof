#if canImport(UIKit) && DEBUG
import SwiftUI

/// Section 2 of the board (sections/02-buttons.png).
struct GalleryButtons: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GalleryGrid(phone: 2) {
                GalleryItem("Primary") { TCButton("คืนอุปกรณ์", systemImage: "arrow.left", fullWidth: true) {} }
                GalleryItem("Primary ไล่เฉด") { TCButton("กล้อง", systemImage: "camera", kind: .primaryGradient, fullWidth: true) {} }
                GalleryItem("ไล่เฉดเขียวอมฟ้า (หมวดสำรวจ)") { TCButton("เพิ่มแบบสำรวจ", systemImage: "list.clipboard", kind: .tealGradient, fullWidth: true) {} }
                GalleryItem("Secondary") { TCButton("อัปโหลด", systemImage: "photo", kind: .secondary, fullWidth: true) {} }
                GalleryItem("Destructive") { TCButton("ลบอาคาร", kind: .destructive, fullWidth: true) {} }
                GalleryItem("Disabled") { TCButton("บันทึกการยืม", fullWidth: true, disabledReason: "ยังไม่ได้เลือกอุปกรณ์") {} }
                GalleryItem("Text") { TCButton("อ่านทั้งหมด", kind: .text, fullWidth: true) {} }
                GalleryItem("ปุ่ม + เพิ่ม (เส้นประ)") { TCButton("+ เพิ่มอาคาร", kind: .dashedAdd, fullWidth: true) {} }
            }
            GalleryGrid(columns: 4, phone: 1) {
                GalleryItem("ปุ่มลอย · วงกลม") { TCFab(accessibilityLabel: "เพิ่ม") {} }
                GalleryItem("ปุ่มลอย · แคปซูล") { TCFab(title: "เพิ่มอุปกรณ์", accessibilityLabel: "เพิ่มอุปกรณ์") {} }
                GalleryItem("ปุ่มไอคอน 44 pt") {
                    HStack(spacing: 12) {
                        TCIconButton("chevron.left", accessibilityLabel: "กลับ") {}
                        TCIconButton("bell", accessibilityLabel: "การแจ้งเตือน", badge: 1) {}
                        TCIconButton("gearshape", accessibilityLabel: "ตั้งค่า") {}
                        TCIconButton("xmark", accessibilityLabel: "ปิด") {}
                    }
                }
            }

            GallerySubhead(title: "สถานะของปุ่ม")
            GalleryGrid(phone: 2) {
                GalleryItem("ปกติ") { TCButton("บันทึก", fullWidth: true) {} }
                GalleryItem("กดค้าง", note: "เข้มขึ้น + ย่อ 2%") { PressedSample() }
                GalleryItem("ปิดใช้งาน", note: "บอกเหตุผลข้างปุ่มเสมอ") {
                    Button("บันทึก") {}.buttonStyle(TCButtonStyle(fullWidth: true)).disabled(true)
                }
                GalleryItem("กำลังทำงาน", note: "กดซ้ำไม่ได้จนเสร็จ") {
                    TCButton("กำลังบันทึก…", fullWidth: true, working: true) {}
                }
            }

            GallerySubhead(title: "ขนาด · ลิงก์ · ปุ่มอันตราย")
            GalleryGrid(phone: 2) {
                GalleryItem("ขนาด · แถบล่าง 53", note: "ทุกปุ่มในแถบล่าง") { TCButton("บันทึกร่างตอนนี้", kind: .secondary, size: .bar, fullWidth: true) {} }
                GalleryItem("ขนาด · มาตรฐาน 44", note: "ในการ์ด · หัวส่วน") { TCButton("ลบอาคาร", kind: .destructive, size: .card, fullWidth: true) {} }
                GalleryItem("ลิงก์ในการ์ด", note: "ข้อความสีน้ำเงิน · เป้ากดสูง 44") {
                    HStack(spacing: 16) {
                        TCLinkButton("เปิด A2", trailingSymbol: "arrow.right") {}
                        TCLinkButton("แก้", trailingSymbol: "arrowtriangle.down.fill") {}
                    }
                }
                GalleryItem("อันตรายแบบทึบ", note: "ใช้ในหน้าต่างยืนยันเท่านั้น") { TCButton("ลบถาวร", kind: .danger, fullWidth: true) {} }
            }

            GallerySubhead(title: "ปุ่มในแถบล่างของขั้น")
            GalleryGrid(columns: 2, phone: 1) {
                GalleryItem("ปุ่มนำทางขั้น (แถบล่าง)", note: "ก่อนหน้าติดกับถัดไปเสมอ · บอกเลขขั้นและชื่อขั้น") {
                    HStack(spacing: 12) {
                        TCStepNavButton(direction: .previous, index: 4, count: 13, title: "A4 น้ำท่วม") {}
                        TCStepNavButton(direction: .next, index: 6, count: 13, title: "B2 อินเวอร์เตอร์") {}
                    }
                }
                GalleryItem("ปุ่มสถานะ (แถบล่าง)", note: "แตะแล้วไปยังรายการที่ขาด · เขียว = ครบช่องบังคับ · ส้ม = ยังขาด") {
                    VStack(spacing: 10) {
                        TCStatusButton(missing: 0, detail: "ยังไม่มี (ไม่บังคับ): บันได") {}
                        TCStatusButton(missing: 7, detail: "ถัดไป โรงกรอง: ภาพมุมกว้าง…") {}
                    }
                }
            }

            GallerySubhead(title: "ขนาดปุ่ม iPad เทียบ iPhone")
            SizeTable()
        }
    }
}

/// The board's "กดค้าง" sample: the pressed look, held.
private struct PressedSample: View {
    var body: some View {
        Text("บันทึก")
            .font(.sarabun(16, .bold)).foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.black.opacity(0.18)))
            .scaleEffect(0.98)
            .accessibilityHidden(true)
    }
}

/// iPad and iPhone sizes side by side; the iPhone column forces the compact size class.
private struct SizeTable: View {
    var body: some View {
        VStack(spacing: 0) {
            row("ชนิด", pad: Text("IPAD · 1366 × 1024"), phone: Text("IPHONE · 390 × 844"), header: true)
            row("ปุ่มหลักในหน้า",
                pad: sample("52 · r12 · 16 pt · ตามเนื้อหา") { TCButton("คืนอุปกรณ์") {} },
                phone: sample("48 · r10 · 15 pt · เต็มความกว้าง") { TCButton("คืนอุปกรณ์") {} })
            row("แถบล่าง · บันทึก",
                pad: sample("53 · กว้าง 170 · 16 pt") { TCButton("บันทึกร่างตอนนี้", kind: .secondary, size: .bar) {}.frame(width: 170) },
                phone: sample("53 · ยืดเต็มช่อง · 16 pt") { TCButton("บันทึก", kind: .secondary, size: .bar, fullWidth: true) {} })
            row("แถบล่าง · ก่อนหน้า / ถัดไป",
                pad: sample("53 · กว้าง 210–250 · มีเลขขั้น + ชื่อ") {
                    HStack(spacing: 10) {
                        TCStepNavButton(direction: .previous, index: 4, count: 13, title: "A4 น้ำท่วม") {}
                        TCStepNavButton(direction: .next, index: 6, count: 13, title: "B2") {}
                    }
                },
                phone: sample("53 × 72 · ไอคอนอย่างเดียว · ชื่อใน VoiceOver") {
                    HStack(spacing: 10) {
                        TCStepNavButton(direction: .previous, index: 4, count: 13, title: "A4 น้ำท่วม") {}
                        TCStepNavButton(direction: .next, index: 6, count: 13, title: "B2 อินเวอร์เตอร์") {}
                    }
                })
            row("ปุ่มในการ์ด",
                pad: sample("44 · r10 · 14 pt") { TCButton("ลบอาคาร", kind: .destructive, size: .card) {} },
                phone: sample("44 · r10 · 14 pt · ข้อความสั้นลง") { TCButton("ลบ", kind: .destructive, size: .card, fullWidth: false) {} })
            row("ปุ่มไอคอน",
                pad: sample("44 × 44 · r8") { TCIconButton("chevron.left", accessibilityLabel: "กลับ") {} },
                phone: sample("44 × 44 · ไม่มีกรอบ (ในหัวหน้า)") { TCIconButton("chevron.left", accessibilityLabel: "กลับ", bordered: false) {} })
            row("ปุ่มลอย (FAB)",
                pad: sample("68 · ห่างขอบ 24") { TCFab(accessibilityLabel: "เพิ่ม") {} },
                phone: sample("60 · ห่างขวา 20 · ล่าง 12") { TCFab(accessibilityLabel: "เพิ่ม") {} })
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.borderSubtle))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPad: name · iPad sample · iPhone sample in columns. iPhone: the three stacked.
    func row(_ name: String, pad: some View, phone: some View, header: Bool = false) -> some View {
        let compact = sizeClass == .compact
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 0))
        return layout {
            Text(name).font(header ? .system(size: 11.5, weight: .semibold, design: .monospaced) : .sarabun(15, .bold))
                .foregroundStyle(header ? Theme.muted : Theme.navy)
                .frame(width: compact ? nil : 150, alignment: .leading).padding(.horizontal, 14).padding(.top, compact ? 10 : 0)
            pad.environment(\.horizontalSizeClass, .regular)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            if !compact { Rectangle().fill(Theme.borderSubtle).frame(width: 1) }
            phone.environment(\.horizontalSizeClass, .compact)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
        .font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.muted)
        .background(header ? Theme.background : Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }

    func sample(_ note: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            Text(note).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.inkMuted)
        }
    }
}

#Preview("Buttons · iPad", traits: .landscapeLeft) {
    ScrollView { GallerySection(number: 2, title: "ปุ่ม", subtitle: "Buttons") { GalleryButtons() }.padding() }
}

#Preview("Buttons · iPhone") {
    ScrollView { GallerySection(number: 2, title: "ปุ่ม", subtitle: "Buttons") { GalleryButtons() }.padding() }
        .environment(\.horizontalSizeClass, .compact)
}
#endif
