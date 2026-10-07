import SwiftUI
import TCRoofUI
import TCRoofCore

/// Roof load per m² for กฎกระทรวง ฉบับที่ 72 (พ.ศ. 2568): over 20 kg/m² needs ข.1 → อ.1 before installing.
struct RoofWeightSheet: View {
    @Binding var result: Double?
    @Environment(\.dismiss) private var dismiss

    @State private var panelKg = ""
    @State private var panelLength = ""
    @State private var panelWidth = ""
    @State private var panelCount = ""
    @State private var mountingKg = ""
    @State private var otherKg = "0"

    private func n(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: "")) }

    private var value: Double? {
        guard let kg = n(panelKg), let l = n(panelLength), let w = n(panelWidth), let c = Int(panelCount) else { return nil }
        // datasheets give mm; 2,000+ means millimetres
        let lm = l > 50 ? l / 1000 : l, wm = w > 50 ? w / 1000 : w
        return RoofWeight.kgPerM2(panelKg: kg, panelAreaM2: lm * wm, panelCount: c, mountingKg: n(mountingKg) ?? 0, otherKg: n(otherKg) ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    PermitSection(title: "แผง", subtitle: "จาก datasheet") {
                        PermitRow {
                            PermitField("น้ำหนักต่อแผง", text: $panelKg, required: true, keyboard: .decimalPad, unit: "กก.")
                            PermitField("จำนวนแผง", text: $panelCount, required: true, keyboard: .numberPad, unit: "แผง")
                        }
                        PermitRow {
                            PermitField("ยาว", text: $panelLength, required: true, keyboard: .decimalPad, unit: "มม.")
                            PermitField("กว้าง", text: $panelWidth, required: true, keyboard: .decimalPad, unit: "มม.")
                        }
                    }
                    PermitSection(title: "อื่นบนหลังคา") {
                        PermitField("ราง ขายึด clamp น็อต รวม", text: $mountingKg, keyboard: .decimalPad, unit: "กก.")
                        PermitField("อุปกรณ์อื่น (optimizer กล่อง DC ทางเดิน)", text: $otherKg, keyboard: .decimalPad, unit: "กก.")
                    }
                    resultCard
                }
                .padding(Space.l)
            }
            .background(Theme.background)
            .navigationTitle("น้ำหนักบนหลังคา")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ใช้ค่านี้") { result = value.map { ($0 * 10).rounded() / 10 }; dismiss() }.disabled(value == nil)
                }
            }
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let v = value {
                Text(String(format: "%.1f กก./ตร.ม.", v)).font(.sarabun(TypeScale.pageTitle, .bold, relativeTo: .title2))
                    .foregroundStyle(v > 20 ? Theme.pending : Theme.okText)
                Text(v > 20 ? "เกิน 20 กก./ตร.ม. ต้องยื่น ข.1 ขออนุญาตดัดแปลงอาคาร พร้อมแบบและรายการคำนวณโยธา และได้ อ.1 ก่อนติดตั้ง"
                            : "ไม่เกิน 20 กก./ตร.ม. ไม่ถือเป็นการดัดแปลงอาคาร เก็บใบคำนวณนี้ไว้ในแฟ้มงาน")
                    .font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.navy)
                Text("หลายกลุ่มแผงให้คิดกลุ่มที่หนักที่สุด · หลังคาเก่าหรือโครงไม้ควรให้วิศวกรโยธาตรวจแม้ไม่ถึงเกณฑ์")
                    .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            } else {
                Text("กรอกน้ำหนัก ขนาด และจำนวนแผง").font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Space.l)
    }
}
