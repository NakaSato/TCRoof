import SwiftUI
import TCRoofUI
import TCRoofCore

/// iPad survey form from the components board (docs/ui/components): white cards on the page gradient, the fields
/// on the left (2 : 1) and what is still missing on the right. Same fields and record as the iPhone form.
extension SurveyEditor {
    var padForm: some View {
        ScrollView {
            TCFractionColumns([2, 1], spacing: 20) {
                VStack(spacing: 16) {
                    padJobCard
                    padRoofCard
                    padElectricalCard
                    padPhotoCard
                    padNotesCard
                }
                VStack(spacing: 16) {
                    padStatusCard
                    padSizingCard
                }
            }
            .padding(24)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        #if DEBUG
        // `-surveyScrollEnd YES`: open scrolled to the end (the simulator can't be swiped here)
        .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "surveyScrollEnd") ? .bottom : .top)
        #endif
    }

    // MARK: Cards

    func padCard<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.sarabun(19, .bold, relativeTo: .title3)).foregroundStyle(Theme.navy)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let note { Text(note).font(.sarabun(13)).foregroundStyle(Theme.inkMuted) }
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tcCard()
    }

    func padField<Content: View>(_ title: String, required: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TCFieldLabel(title, required: required)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var padJobCard: some View {
        padCard("โครงการ · ตำแหน่งหน้างาน", note: form.isDraft ? "ร่าง · บันทึกอัตโนมัติทุกครั้งที่แก้ไข" : nil) {
            if let job = form.job {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.customerName).font(.sarabun(18, .bold)).foregroundStyle(Theme.navy)
                    Text("\(job.code) · \(job.address) \(job.province)").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("พิกัด").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                    if let lat = form.latitude, let lon = form.longitude {
                        Text(String(format: "%.6f, %.6f", lat, lon)).font(.sarabun(16, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                    } else {
                        Text("ยังไม่บันทึก").font(.sarabun(16, .bold)).foregroundStyle(Theme.pending)
                    }
                }
                Spacer(minLength: 8)
                if let lat = form.latitude, let lon = form.longitude,
                   let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(form.job?.code ?? "หน้างาน")") {
                    Link(destination: url) { Label("เปิดในแผนที่", systemImage: "map").labelStyle(TCIconTitleLabel()) }
                        .buttonStyle(TCButtonStyle(.secondary, fullWidth: false))
                }
                TCLocationButton(working: locating, action: locate)
            }
            if let locationError { TCMissingLine(locationError) }
        }
    }

    var padRoofCard: some View {
        padCard("ข้อมูลหลังคา") {
            HStack(alignment: .top, spacing: 16) {
                padField("ประเภทหลังคา", required: true) {
                    TCDropdown(SurveyOptions.roofTypes, selection: $form.roofType, accessibilityTitle: "ประเภทหลังคา")
                }
                padField("พื้นที่หลังคาที่ใช้ได้", required: true) {
                    TCNumberField("พื้นที่หลังคาที่ใช้ได้", value: optional(\.roofAreaSqm), range: 0...100_000, unit: "ตร.ม.")
                }
            }
            HStack(alignment: .top, spacing: 16) {
                padField("ทิศทางหลังคา", required: true) {
                    TCDropdown(SurveyOptions.orientations, selection: $form.orientation, accessibilityTitle: "ทิศทางหลังคา")
                }
                padField("ความลาดชัน") {
                    TCStepperField(value: tilt, range: 0...60, unit: "°", title: "ความลาดชัน")
                }
            }
            padField("เงาบัง", required: true) {
                TCChoiceChips(SurveyOptions.shadings, selection: choice(\.shading))
            }
            TCSwitchRow("โครงสร้างหลังคารับน้ำหนักได้", isOn: $form.structureOK)
        }
    }

    var padElectricalCard: some View {
        padCard("ระบบไฟฟ้า") {
            HStack(alignment: .top, spacing: 16) {
                padField("การไฟฟ้า", required: true) { TCSegmented(SurveyOptions.utilities, selection: $form.utility) }
                padField("ระบบมิเตอร์", required: true) { TCSegmented(["1 เฟส", "3 เฟส"], selection: $form.meterPhase) }
            }
            HStack(alignment: .top, spacing: 16) {
                padField("เลขผู้ใช้ไฟฟ้า (CA)") { TCTextField("ดูจากบิลค่าไฟ", text: $form.caNumber, keyboard: .numberPad) }
                padField("ขนาดมิเตอร์") { TCTextField("เช่น 15(45) A", text: $form.meterSize) }
            }
            HStack(alignment: .top, spacing: 16) {
                padField("เมนเบรกเกอร์", required: true) {
                    TCDropdown(breakerOptions.map { "\($0) A" }, selection: breaker, accessibilityTitle: "เมนเบรกเกอร์")
                }
                padField("อัตราค่าไฟ") { TCChoiceChips(SurveyOptions.tariffs, selection: choice(\.tariff)) }
            }
            HStack(alignment: .top, spacing: 16) {
                padField("หน่วยไฟเฉลี่ยต่อเดือน") {
                    TCNumberField("หน่วยไฟเฉลี่ยต่อเดือน", value: optional(\.monthlyKWh), range: 0...10_000_000, unit: "kWh")
                }
                padField("ค่าไฟเฉลี่ยต่อเดือน") {
                    TCNumberField("ค่าไฟเฉลี่ยต่อเดือน", value: optional(\.monthlyBill), range: 0...100_000_000, unit: "บาท")
                }
            }
            padField("สายดินเดิม") { TCChoiceChips(SurveyOptions.groundings, selection: choice(\.grounding)) }
        }
    }

    var padPhotoCard: some View {
        padCard("รูปถ่าย", note: "รูปที่มี * จำเป็น") {
            ForEach(SurveyOptions.photoTags) { tag in
                let photos = SurveyOptions.photos(form, tag.id)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TCFieldLabel("รูป\(tag.title)", required: tag.required)
                        if tag.required {
                            TCStatusChip(photos.isEmpty ? "จำเป็น" : "ครบ", kind: photos.isEmpty ? .pending : .done)
                        }
                    }
                    PhotoPickerSection(images: photos.map(\.data),
                                       onAdd: { addPhoto($0, tag: tag.id) },
                                       onDelete: { index in deletePhoto(photos, at: index) })
                }
                if tag.id != SurveyOptions.photoTags.last?.id { Divider() }
            }
        }
    }

    var padNotesCard: some View {
        padCard("หมายเหตุ") {
            TCLongText("รายละเอียดเพิ่มเติม", text: $form.notes, minHeight: 96)
        }
    }

    /// What is still missing, in form order, or a green line when complete.
    var padStatusCard: some View {
        let list = SurveyOptions.checklist(form)
        let done = list.filter(\.filled).count
        return padCard(missing.isEmpty ? "กรอกครบแล้ว" : "ยังขาด \(missing.count) รายการ", note: "\(done)/\(list.count)") {
            TCSegmentedProgress(list.map { $0.filled ? .done : .todo })
            if missing.isEmpty {
                Text("กดบันทึกเพื่อปิดแบบสำรวจ").font(.sarabun(14)).foregroundStyle(Theme.okText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(missing, id: \.self) { TCMissingLine($0) }
                }
            }
        }
    }

    var padSizingCard: some View {
        padCard("ขนาดระบบที่เสนอ") {
            VStack(alignment: .leading, spacing: 8) {
                sizingRow("ขนาดแนะนำจากการใช้ไฟ", SurveyOptions.suggestedKW(form).kw)
                sizingRow("ขนาดสูงสุดตามพื้นที่หลังคา", SurveyOptions.maxKWByRoof(form).kw)
            }
            padField("ขนาดที่เสนอ") {
                TCNumberField("ขนาดที่เสนอ", value: optional(\.recommendedKW), range: 0...100_000, step: 0.01, unit: "kWp")
            }
            Text("เว้นว่างเพื่อใช้ค่าที่คำนวณ (\(SurveyOptions.autoKW(form).kw)) · ใช้หน่วย kWh ถ้ากรอก ไม่เช่นนั้นคิดจากค่าไฟ 4.5 บาท/หน่วย · ใช้ไฟกลางวัน 60% · แดดเฉลี่ย 4 ชม./วัน")
                .font(.sarabun(13)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    func sizingRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.sarabun(15)).foregroundStyle(Theme.inkMuted)
            Spacer(minLength: 8)
            Text(value).font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
        }
    }

    // MARK: Bindings

    /// A chip row's answer: `""` stored is no chip selected.
    func choice(_ keyPath: ReferenceWritableKeyPath<SurveyForm, String>) -> Binding<String?> {
        Binding(get: { form[keyPath: keyPath].isEmpty ? nil : form[keyPath: keyPath] }, set: { form[keyPath: keyPath] = $0 ?? "" })
    }

    var tilt: Binding<Double> {
        Binding(get: { Double(form.tiltDegree) }, set: { form.tiltDegree = Int($0.rounded()) })
    }

    /// `"63 A"` in the menu, the amperes in the record (0 = none).
    var breaker: Binding<String> {
        Binding(get: { form.mainBreakerAmp > 0 ? "\(form.mainBreakerAmp) A" : "" },
                set: { form.mainBreakerAmp = Int($0.split(separator: " ").first ?? "") ?? 0 })
    }
}
