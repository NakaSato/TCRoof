#if canImport(UIKit) && DEBUG
import SwiftUI

/// Section 9 of the board (sections/09-number-pad.png): two pads drawn inline (normal, out of range), the rules,
/// and a live field that opens the real popover.
struct GalleryNumberPad: View {
    @State var normal = "1.2"
    @State var over = "7.5"
    @State var live: Double? = 1.2
    @State var current: Double? = 16
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let compact = sizeClass == .compact
        let columns = compact ? 1 : 3
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 24, alignment: .topLeading), count: columns),
                  alignment: .leading, spacing: 24) {
            GalleryItem("ปกติ · ใช้งานได้จริง") { InlinePad(text: $normal) }
            GalleryItem("ค่าเกินช่วง") { InlinePad(text: $over) }
            GalleryItem("การใช้งาน") {
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(Self.rules, id: \.self) { r in
                        Text("• " + r).font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("ใช้กับ: ระยะ (ม.) · กระแส (A) · โหลด (kW) · ความสูง (ซม.) · จำนวน")
                        .font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    Divider().padding(.vertical, Space.xs)
                    Text("ลองเปิดแป้นจริง").font(.sarabun(13, .bold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    TCFieldLabel("ระยะห่างจากขอบถัง")
                    TCNumberField("ระยะห่างจากขอบถัง", value: $live, range: 0.3...5.0, step: 0.1, unit: "ม.")
                    TCFieldLabel("กระแส", required: true)
                    TCNumberField("กระแส", value: $current, range: 0...630, step: 1, unit: "A", allowsDecimal: false, required: true)
                }
            }
        }
    }

    static let rules = [
        "แตะช่องตัวเลข → popover เปิดใต้ช่อง (ลูกศรชี้ช่อง) ช่องที่กำลังแก้ขอบน้ำเงิน 2 pt",
        "หัว: ชื่อช่อง + ช่วงที่รับได้ · จอแสดงค่า 30 pt ชิดขวา พร้อมหน่วย",
        "ปุ่ม − / + ปรับทีละขั้น (ขั้นตามชนิดค่า เช่น 0.1 ม., 1 A, 5 kW)",
        "แป้น 3 × 4 ปุ่มละ ≥ 52 pt · จุดทศนิยม (ซ่อนเมื่อเป็นจำนวนเต็ม) · ⌫ ลบทีละตัว · \"ล้าง\" ลบทั้งหมด",
        "ค่านอกช่วง: จอแดง + ข้อความบอกขีดจำกัด · ปุ่มตกลงกดไม่ได้",
        "ตกลง = บันทึกและปิด · ยกเลิก หรือแตะนอก popover = คืนค่าเดิม",
        "ไม่ใช้คีย์บอร์ดระบบ จึงไม่บังหน้าจอครึ่งล่าง",
    ]
}

/// The board's static sample: the field being edited, the arrow, and the pad card under it.
private struct InlinePad: View {
    @Binding var text: String
    let range = 0.3...5.0

    var out: Bool { Double(text).map { !range.contains($0) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ระยะห่างจากขอบถัง").font(.sarabun(13, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                .padding(.bottom, Space.xs)
            HStack(spacing: 2) {
                Text(text).font(.sarabun(16, .bold, relativeTo: .body)).foregroundStyle(Theme.navy)
                Rectangle().fill(Theme.primary).frame(width: 2, height: 20)
                Spacer(minLength: Space.xs)
                Text("ม.").font(.sarabun(13, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, Space.m)
            .frame(width: 220, height: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(out ? Theme.danger : Theme.primary, lineWidth: 2))
            Arrow().fill(Theme.surface)
                .overlay(Arrow().stroke(Theme.borderSubtle))
                .frame(width: 18, height: 9)
                .padding(.leading, 28).padding(.top, 6)
                .zIndex(1)
                .offset(y: 1)
            NumberPad(title: "ระยะห่างจากขอบถัง", range: range, step: 0.1, unit: "ม.", original: 1.2, text: $text,
                      onCancel: { text = "1.2" }, onConfirm: { _ in })
                .padding(14)
                .frame(maxWidth: 328)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Theme.borderSubtle))
                .shadow(color: Theme.navy.opacity(0.18), radius: 16, y: 12)
        }
    }
}

/// The popover's arrow, pointing up.
private struct Arrow: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
    }
}

#Preview("Number pad · iPad", traits: .landscapeLeft) {
    ScrollView { GallerySection(number: 9, title: "ป้อนตัวเลข", subtitle: "Number input popup") { GalleryNumberPad() }.padding() }
}

#Preview("Number pad · iPhone") {
    ScrollView { GallerySection(number: 9, title: "ป้อนตัวเลข", subtitle: "Number input popup") { GalleryNumberPad() }.padding() }
        .environment(\.horizontalSizeClass, .compact)
}
#endif
