import SwiftUI
import TCRoofUI
import TCRoofCore

/// หนังสือมอบอำนาจ (แบบฟอร์ม กฟภ.) of one job. The printout is the original PEA page with the answers on it.
struct PowerOfAttorneyView: View {
    let job: Job

    @State private var poa = PowerOfAttorney()
    @State private var loaded = false
    private let map = PermitFormMap.load(PermitFormMap.powerOfAttorney)
    static let file = "poa"

    var body: some View {
        if let map {
            PermitFormScaffold(title: "หนังสือมอบอำนาจ", job: job, map: map, issues: poa.issues,
                               fileName: "หนังสือมอบอำนาจ-\(job.code).pdf", version: AnyHashable(poaVersion),
                               content: { PermitRenderer.Content(values: poa.values, marks: poa.marks) }) {
                documentCard
                personCard("ผู้มอบอำนาจ", subtitle: "เจ้าของมิเตอร์ ชื่อตรงกับบิลค่าไฟ", person: $poa.grantor)
                personCard("ผู้รับมอบอำนาจ", subtitle: nil, person: $poa.grantee)
                powersCard
                witnessCard
                beforeSendingCard
            }
            .task { load() }
            .onChange(of: poa) { _, new in if loaded { PermitStore(job: job).save(new, Self.file) } }
        } else {
            TCEmptyState("ไม่พบแบบฟอร์ม", systemImage: "doc.questionmark")
        }
    }

    /// `PowerOfAttorney` is Equatable; its JSON is a cheap hashable stand-in for the preview's redraw key.
    private var poaVersion: Data { (try? JSONEncoder().encode(poa)) ?? Data() }

    private func load() {
        guard !loaded else { return }
        if let saved = PermitStore(job: job).load(PowerOfAttorney.self, Self.file) {
            poa = saved
        } else {
            poa.grantor.name = job.customerName
            poa.grantor.phone = job.phone
            poa.grantor.province = job.province
        }
        loaded = true
    }

    // MARK: Cards

    private var documentCard: some View {
        PermitSection(title: "ข้อมูลเอกสาร") {
            PermitField("เขียนที่", text: $poa.writtenAt, required: true)
            VStack(alignment: .leading, spacing: 6) {
                TCFieldLabel("วันที่", required: true)
                TCDateField(date: $poa.date, accessibilityTitle: "วันที่")
            }
        }
    }

    private func personCard(_ title: String, subtitle: String?, person: Binding<PowerOfAttorney.Person>) -> some View {
        PermitSection(title: title, subtitle: subtitle) {
            PermitRow {
                PermitField("ชื่อ-นามสกุล", text: person.name, required: true)
                PermitField("อายุ", text: person.age, required: true, keyboard: .numberPad, unit: "ปี").frame(maxWidth: isPhone ? .infinity : 130)
            }
            PermitField("เลขบัตรประชาชน", text: idBinding(person.nationalID), required: true, keyboard: .numberPad,
                        error: idError(person.wrappedValue.nationalID))
            PermitRow {
                PermitField("เชื้อชาติ", text: person.ethnicity, required: true)
                PermitField("สัญชาติ", text: person.nationality, required: true)
            }
            PermitRow {
                PermitField("บ้านเลขที่", text: person.houseNo, required: true)
                PermitField("หมู่", text: person.moo)
            }
            PermitRow {
                PermitField("แขวง/ตำบล", text: person.subdistrict, required: true)
                PermitField("เขต/อำเภอ", text: person.district, required: true)
            }
            PermitField("จังหวัด", text: person.province, required: true)
            PermitRow {
                PermitField("เบอร์โทรศัพท์", text: person.phone, required: true, keyboard: .phonePad)
                PermitField("Email (ถ้ามี)", text: person.email, keyboard: .emailAddress)
            }
        }
    }

    /// Shows `x-xxxx-xxxxx-xx-x` while typing and stores digits only.
    private func idBinding(_ id: Binding<String>) -> Binding<String> {
        Binding(get: { ThaiID.formatted(id.wrappedValue) }, set: { id.wrappedValue = ThaiID.digits($0) })
    }

    private func idError(_ id: String) -> String? {
        let n = ThaiID.digits(id).count
        if n == 13 && !ThaiID.isValid(id) { return "เลขตรวจสอบไม่ถูกต้อง ตรวจเลขบัตรอีกครั้ง" }
        if n > 0 && n < 13 { return "\(n)/13 หลัก" }
        return nil
    }

    private var powersCard: some View {
        PermitSection(title: "อำนาจที่มอบ", subtitle: "✓ ให้ดำเนินการ | – ไม่ให้ดำเนินการ (หมายเหตุข้อ 3 ของแบบฟอร์ม)") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) { presetButtons }
                VStack(alignment: .leading, spacing: Space.s) { presetButtons }
            }
            ForEach(0..<7, id: \.self) { i in powerRow(i) }
            if poa.powers[5] == .yes {
                PermitField("ข้อ 6: แก้ไข ตกเติม และรับรองเอกสารในข้อ", text: $poa.item6Ref, required: true)
            }
            if poa.powers[6] == .yes {
                PermitField("ข้อ 7: อื่นๆ (ระบุ)", text: $poa.item7Other, required: true)
            }
        }
    }

    @ViewBuilder private var presetButtons: some View {
        TCButton("✓ ข้อ 1–5 (ขายไฟ)", kind: .secondary, size: .card) { poa.apply(.sellAll) }
        TCButton("เฉพาะขอเชื่อมต่อ (3, 5)", kind: .secondary, size: .card) { poa.apply(.connectOnly) }
        TCButton("ล้าง", kind: .text, size: .card) { poa.apply(.clear) }
    }

    private func powerRow(_ i: Int) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            HStack(spacing: 0) {
                markButton(i, .yes, "checkmark")
                markButton(i, .no, "minus")
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Theme.borderControl))
            Text("\(i + 1). \(PowerOfAttorney.powers[i])")
                .font(.sarabun(15, relativeTo: .body)).foregroundStyle(Theme.navy)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private func markButton(_ i: Int, _ mark: PermitMark, _ symbol: String) -> some View {
        let on = poa.powers[i] == mark
        return Button { poa.powers[i] = on ? nil : mark } label: {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold))
                .foregroundStyle(on ? Theme.onPrimary : Theme.inkMuted)
                .frame(width: touchMin, height: touchMin)
                .background(on ? (mark == .yes ? Theme.okTick : Theme.inkMuted) : Color.clear,
                            in: RoundedRectangle(cornerRadius: Radius.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ข้อ \(i + 1) " + (mark == .yes ? "ให้ดำเนินการ" : "ไม่ให้ดำเนินการ"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var witnessCard: some View {
        PermitSection(title: "พยาน", subtitle: "ชื่อในวงเล็บใต้ช่องลงชื่อ ผู้มอบและผู้รับมอบใช้ชื่อจากด้านบน") {
            PermitField("พยานคนที่ 1", text: $poa.witness1, required: true)
            PermitField("พยานคนที่ 2", text: $poa.witness2, required: true)
        }
    }

    private var beforeSendingCard: some View {
        PermitSection(title: "ก่อนส่ง") {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(["พิมพ์แล้วเซ็นสดครบ 4 ช่อง (ผู้มอบ ผู้รับมอบ พยาน 2 คน)",
                         "ติดอากรแสตมป์ 30 บาท และขีดฆ่า",
                         "แนบสำเนาบัตร ปชช. ผู้มอบและผู้รับมอบ ลงนามรับรองสำเนาถูกต้อง",
                         "แก้ข้อความบนกระดาษ: ขีดเส้นทับและเซ็นกำกับทุกแห่ง"], id: \.self) { line in
                    Label(line, systemImage: "checklist").font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.inkStrong)
                }
            }
        }
    }
}
