#if canImport(UIKit) && DEBUG
import SwiftUI

/// Section 3 of the board (sections/03-inputs.png).
struct GalleryInputs: View {
    @State var name = "สมชาย"
    @State var kwp = "120"
    @State var at = "400"
    @State var kw = "85"
    @State var breaker = "MDP-1 · CB1"
    @State var date = Self.sampleDate(hour: 10, minute: 30)
    @State var height = 48.0
    @State var search = ""
    @State var calendarView = "เดือน"
    @State var model = ""
    @State var type = "ทุกประเภท"
    @State var has: String? = "มี"
    @State var pass: String? = "ไม่ผ่าน"
    @State var slot = "10:00"
    @State var window = "7 วัน"
    @State var battery = true
    @State var complete = false
    @State var meter = "NO.224"
    @State var note = "โหลดหลักคือปั๊มน้ำ 3 ตัว เดินพร้อมกัน 06:00–18:00"
    @State var strokes: [[CGPoint]] = Self.sampleSignature
    @State var missing = ""
    @State var kv = "22"
    @State var defaultHeight = ""
    @State var plate = "4.14"
    @State var rating = "400 AT"
    @State var distance: Double? = 1.2
    @State var la = true
    @State var spd = false
    @State var protections: Set<String> = ["SPD", "หน้าตู้ ≥ 1 ม."]
    @State var brand = "Schneider"
    @State var from = "06:00"
    @State var to = "18:00"
    @State var remark = "บัสบาร์มีคราบออกไซด์"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GalleryGrid {
                GalleryItem("ช่องข้อความ") { TCTextField("ชื่อ", text: $name) }
                GalleryItem("ตัวเลข + หน่วย") { TCTextField("กำลังติดตั้ง", text: $kwp, unit: "kWp", keyboard: .decimalPad) }
                GalleryItem("ค่าคำนวณ / ดึงอัตโนมัติ", note: "พื้นเขียวอ่อน = ระบบเติมให้") {
                    TCTextField("เบรกเกอร์", text: $at, unit: "AT", calculated: true)
                }
                GalleryItem("กำลังพิมพ์ (focus)") { TCTextField("โหลด", text: $kw, unit: "kW", focused: true) }
            }
            GalleryGrid {
                GalleryItem("Dropdown") {
                    TCDropdown(["MDP-1 · CB1", "MDP-1 · CB2", "MDP-2 · CB1"], selection: $breaker, accessibilityTitle: "เบรกเกอร์")
                }
                GalleryItem("วันที่") { TCDateField(date: $date, accessibilityTitle: "วันที่") }
                GalleryItem("Stepper ±") { TCStepperField(value: $height, range: 0...200, unit: "ม.", title: "ความสูง") }
                GalleryItem("ปุ่มถ่าย / ตำแหน่ง") { TCLocationButton {} }
            }
            GalleryGrid(columns: 2, phone: 1) {
                GalleryItem("ช่องค้นหา") { TCSearchField("ค้นหาด้วยชื่อลูกค้าหรือรหัสโครงการ", text: $search) }
                GalleryItem("ค้นหา + ตัวเลือกประเภท") {
                    TCSearchField("ค้นหารุ่น S/N", text: $model) {
                        TCSearchTypePicker(["ทุกประเภท", "อินเวอร์เตอร์", "มิเตอร์", "โดรน"], selection: $type, count: 10)
                    }
                }
            }
            GalleryGrid {
                GalleryItem("Chip เลือกอันเดียว") { TCChoiceChips(["มี", "ไม่มี"], selection: $has) }
                GalleryItem("Chip ตอบ \"ไม่ผ่าน\"") { TCChoiceChips(["ผ่าน", "ไม่ผ่าน"], selection: $pass, negative: ["ไม่ผ่าน"]) }
                GalleryItem("Segmented") { TCSegmented(["10:00", "12:00", "14:00"], selection: $slot) }
                GalleryItem("แท็บแคปซูล") { TCCapsuleTabs(["7 วัน", "30 วัน", "ทั้งหมด"], selection: $window) }
                GalleryItem("Segmented · ตัวกรอง iPhone", note: "สูง 44 · ราง r10 · ช่องเลือก r8") {
                    TCSegmented(["7 วัน", "30 วัน", "ทั้งหมด"], selection: $window, fontSize: 14, style: .filter)
                }
                GalleryItem("Segmented · สลับมุมมอง iPhone", note: "สูง 44 · ราง r12 · ช่องเลือก r10") {
                    TCSegmented(["เดือน", "สัปดาห์"], selection: $calendarView, fontSize: 14, style: .view)
                }
            }
            GalleryGrid {
                GalleryItem("เช็กบ็อกซ์") {
                    VStack(alignment: .leading, spacing: 0) {
                        TCCheckbox("แบตเตอรี่ชาร์จเต็ม", isOn: $battery)
                        TCCheckbox("อุปกรณ์ครบ", isOn: $complete)
                    }
                }
                GalleryItem("Radio card") {
                    VStack(spacing: Space.s) {
                        TCRadioCard("NO.224", subtitle: "กปภ. สาขาตัวอย่าง", selected: meter == "NO.224") { meter = "NO.224" }
                        TCRadioCard("NO.230", subtitle: "โรงสูบน้ำ", selected: meter == "NO.230") { meter = "NO.230" }
                    }
                }
                GalleryItem("ช่องข้อความยาว") { TCLongText("หมายเหตุ", text: $note) }
                GalleryItem("ช่องลายเซ็น") { TCSignatureBox(strokes: $strokes) }
            }
            GalleryGrid {
                GalleryItem("ป้ายชื่อช่อง", note: "* = บังคับ · ไม่บังคับ = ป้ายเทาท้ายชื่อ") {
                    VStack(alignment: .leading, spacing: Space.s) {
                        TCFieldLabel("ความสูงปุ่ม", required: true)
                        TCFieldLabel("ยี่ห้อ / รุ่น", optional: true)
                    }
                }
                GalleryItem("ช่องบังคับยังว่าง", note: "ขอบแดง + พื้นชมพู · นับใน \"ยังขาด n ช่อง\"") {
                    TCTextField("กระแส", text: $missing, unit: "A", required: true)
                }
                GalleryItem("อ่านอย่างเดียว / ปิด", note: "มาจากขั้นอื่น แก้ที่ต้นทาง") {
                    TCTextField("แรงดัน", text: $kv, unit: "kV", readOnly: true)
                }
                GalleryItem("ค่าตั้งต้น / จากป้าย", note: "ตัวเทา = ค่าตั้งต้น พิมพ์ทับได้") {
                    VStack(spacing: 6) {
                        TCTextField("ระยะ", text: $defaultHeight, source: .defaultValue("4"), keyboard: .decimalPad)
                        TCTextField("ระยะ", text: $plate, source: .nameplate, keyboard: .decimalPad)
                    }
                }
            }
            GalleryGrid {
                GalleryItem("Dropdown · เปิดรายการ", note: "เปิดทีละรายการ · เลือกแล้วปิดเอง") {
                    VStack(spacing: 6) {
                        TCDropdownLabel(title: rating, open: true)
                        TCDropdownList(["250 AT", "300 AT", "400 AT", "500 AT"], selection: rating) { rating = $0 }
                    }
                }
                GalleryItem("ป้อนตัวเลข", note: "แตะแล้วเปิดแป้นตัวเลข → หมวด 9") {
                    TCNumberField("ระยะห่างจากขอบถัง", value: $distance, range: 0.3...5.0, step: 0.1, unit: "ม.")
                }
                GalleryItem("สวิตช์ เปิด/ปิด", note: "ใช้กับค่า มี/ไม่มี ที่ไม่ต้องระบุเพิ่ม") {
                    VStack(spacing: Space.xs) {
                        TCSwitchRow("มี LA", isOn: $la)
                        TCSwitchRow("มี SPD", isOn: $spd)
                    }
                }
                GalleryItem("เลือกหลายรายการ", note: "แตะสลับ · เลือกได้หลายข้อ") {
                    TCMultiChips(["SPD", "RCD", "หน้าตู้ ≥ 1 ม."], selection: $protections)
                }
            }
            GalleryGrid {
                GalleryItem("เวลา", note: "ใช้กับเวลาที่วัดค่า") { TCDateField(date: $date, kind: .time, accessibilityTitle: "เวลา") }
                GalleryItem("ช่องพร้อมปุ่มล้าง", note: "× แสดงเมื่อมีค่า · เป้ากด 44 pt") { ClearableSample(text: $brand) }
                GalleryItem("ช่วงค่า จาก–ถึง", note: "เช่น ช่วงเวลาโหลด · ระยะ min–max") { TCRangeField(from: $from, to: $to) }
                GalleryItem("ข้อความยาว + ตัวนับ", note: "จำกัดความยาวหมายเหตุ") { TCLongText("หมายเหตุ", text: $remark, limit: 200) }
            }
        }
    }

    static func sampleDate(hour: Int, minute: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 29, hour: hour, minute: minute)) ?? .now
    }

    /// A wavy stroke like the board's sample.
    static let sampleSignature: [[CGPoint]] = [
        (0...40).map { i in
            let x = Double(i) * 4.2
            return CGPoint(x: 24 + x, y: 46 + sin(x / 14) * 12 - (x > 90 ? 6 : 0))
        }
    ]
}

/// `ช่องพร้อมปุ่มล้าง`: a text field with the ✕ clear button.
private struct ClearableSample: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 0) {
            TextField("ยี่ห้อ", text: $text).font(.sarabun(TypeScale.label, relativeTo: .body)).foregroundStyle(Theme.navy)
            if !text.isEmpty { TCClearButton { text = "" }.padding(.trailing, -10) }
        }
        .tcFieldFrame(.normal)
    }
}

#Preview("Inputs · iPad", traits: .landscapeLeft) {
    ScrollView { GallerySection(number: 3, title: "ช่องกรอกข้อมูล", subtitle: "Inputs") { GalleryInputs() }.padding() }
}

#Preview("Inputs · iPhone") {
    ScrollView { GallerySection(number: 3, title: "ช่องกรอกข้อมูล", subtitle: "Inputs") { GalleryInputs() }.padding() }
        .environment(\.horizontalSizeClass, .compact)
}
#endif
