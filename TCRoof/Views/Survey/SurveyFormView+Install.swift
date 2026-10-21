import SwiftUI
import TCRoofUI
import TCRoofCore
import ModuleRules

/// The survey's installation checks from ZNSHINE's manual (docs/specs/module-install-rules.md §7.1): the site answers,
/// a live list of the rules they raise at the top (block red, warn with the engineer's reason, info blue) and the
/// photos the warranty needs. iPad: a card; iPhone: a section. The answers are one JSON field (`installCheckJSON`).
extension SurveyEditor {
    static let seaOptions: [(SeaDistance, String)] = [(.under100m, "< 100 ม."), (.to1km, "100 ม.–1 กม."), (.over1km, "> 1 กม.")]
    static let shadeSources = ["ต้นไม้", "อาคารข้างเคียง", "เสาไฟ / สายไฟ", "ถังน้ำ / เสาอากาศ", "ปล่องควัน", "อื่น ๆ"]

    var installCheck: SiteInstallCheck {
        get { SiteInstallCheck.decode(form.installCheckJSON) }
        nonmutating set { form.installCheckJSON = newValue.isEmpty ? "" : newValue.json }
    }

    var installValidation: Validation { installCheck.validation(latitude: form.latitude) }

    /// A field of the check as a binding.
    func check<T>(_ keyPath: WritableKeyPath<SiteInstallCheck, T>) -> Binding<T> {
        Binding(get: { installCheck[keyPath: keyPath] }, set: { var c = installCheck; c[keyPath: keyPath] = $0; installCheck = c })
    }

    /// Yes / no chips for an optional answer (no chip = not answered).
    func yesNo(_ keyPath: WritableKeyPath<SiteInstallCheck, Bool?>, yes: String = "มี", no: String = "ไม่มี") -> Binding<String?> {
        Binding(get: { installCheck[keyPath: keyPath].map { $0 ? yes : no } },
                set: { v in var c = installCheck; c[keyPath: keyPath] = v.map { $0 == yes }; installCheck = c })
    }

    var seaChoice: Binding<String?> {
        Binding(get: { installCheck.seaDistance.flatMap { d in Self.seaOptions.first { $0.0 == d }?.1 } },
                set: { v in var c = installCheck; c.seaDistance = Self.seaOptions.first { $0.1 == v }?.0; installCheck = c })
    }

    var flag: (WritableKeyPath<SiteInstallCheck, Bool?>) -> Binding<Bool> {
        { kp in Binding(get: { installCheck[keyPath: kp] ?? false }, set: { v in var c = installCheck; c[keyPath: kp] = v; installCheck = c }) }
    }

    var shadeChoice: Binding<Set<String>> {
        Binding(get: { Set(installCheck.shadingSources) },
                set: { v in var c = installCheck; c.shadingSources = Self.shadeSources.filter(v.contains); installCheck = c })
    }

    func reason(_ id: String) -> Binding<String> {
        Binding(get: { installCheck.reasons[id] ?? "" },
                set: { v in var c = installCheck; c.reasons[id] = v.isEmpty ? nil : v; installCheck = c })
    }

    /// Saving needs no block and a reason per warn; the alert lists what stops it.
    var installStops: [String] {
        let v = installValidation, reasons = installCheck.reasons
        return v.blocks.map { "\($0.id) \($0.messageTH)" }
            + v.warns.filter { (reasons[$0.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.map { "\($0.id) ใส่เหตุผลก่อนบันทึก" }
    }

    /// Stamps the rule set and catalog the survey is saved under.
    func stampInstallCheck() {
        guard !installCheck.isEmpty else { return }
        var c = installCheck
        c.ruleSetVersion = ModuleCatalog.ruleSetVersion; c.catalogVersion = ModuleCatalog.version
        installCheck = c
    }

    // MARK: rule list

    /// The rules the answers raise, most severe first; a warn carries the engineer's reason field.
    @ViewBuilder var installRules: some View {
        let v = installValidation
        if v.results.isEmpty {
            Label(installCheck.isEmpty ? "กรอกข้อมูลหน้างานเพื่อตรวจตามคู่มือติดตั้งแผง" : "ผ่านทุกข้อที่ตรวจได้",
                  systemImage: installCheck.isEmpty ? "info.circle" : "checkmark.seal")
                .font(.sarabun(14)).foregroundStyle(installCheck.isEmpty ? Theme.inkMuted : Theme.okText)
        }
        ForEach(v.results) { r in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: r.severity == .block ? "xmark.octagon.fill" : r.severity == .warn ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(color(r.severity))
                    Text(r.id).font(.sarabun(13, .bold)).foregroundStyle(color(r.severity))
                    Text(r.messageTH).font(.sarabun(14)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
                }
                if r.severity == .warn {
                    TCTextField("เหตุผลที่ยังติดตั้งได้ (จำเป็น)", text: reason(r.id))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color(r.severity).opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.md))
            .accessibilityElement(children: .contain)
        }
        ForEach(installCheck.notes, id: \.self) { n in
            Label(n, systemImage: "note.text").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
        }
    }

    func color(_ s: Severity) -> Color { s == .block ? Theme.dangerText : s == .warn ? Theme.pending : Theme.primary }

    /// Tilt that the manual recommends for the survey's latitude, or why there is none.
    var tiltHint: String {
        guard let lat = form.latitude else { return "บันทึกพิกัดเพื่อดูมุมเอียงที่แนะนำ" }
        return String(format: "แนะนำ %.0f° ที่ละติจูด %.1f° | ต่ำสุด 10°", ModuleRules.recommendedTilt(latitude: lat), lat)
    }

    func installPhotos(_ tag: String, _ title: String) -> some View {
        let photos = SurveyOptions.photos(form, tag)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            PhotoPickerSection(images: photos.map(\.data), onAdd: { addPhoto($0, tag: tag) },
                               onDelete: { index in deletePhoto(photos, at: index) })
        }
    }

    // MARK: iPad card

    var padInstallCard: some View {
        padCard("ตรวจตามคู่มือติดตั้งแผง", note: "ZNSHINE | กฎชุด \(ModuleCatalog.ruleSetVersion)") {
            installRules
            HStack(alignment: .top, spacing: 16) {
                padField("มุมเอียงแผงที่วางแผน") {
                    TCNumberField("มุมเอียงแผงที่วางแผน", value: check(\.plannedTiltDeg), range: 0...60, step: 1, unit: "°")
                    Text(tiltHint).font(.sarabun(12.5)).foregroundStyle(Theme.inkMuted)
                }
                padField("ความสูงจากระดับน้ำทะเล") {
                    TCNumberField("ความสูงจากระดับน้ำทะเล", value: check(\.altitudeM), range: 0...6000, unit: "ม.")
                }
            }
            padField("ระยะห่างทะเล / แหล่งกำมะถัน") {
                TCChoiceChips(Self.seaOptions.map(\.1), selection: seaChoice)
            }
            HStack(alignment: .top, spacing: 16) {
                padField("อุณหภูมิต่ำสุดเฉลี่ยรายเดือน") {
                    TCNumberField("อุณหภูมิต่ำสุดเฉลี่ยรายเดือน", value: check(\.monthlyMinC), range: -50...60, unit: "°C")
                }
                padField("อุณหภูมิสูงสุดเฉลี่ยรายเดือน") {
                    TCNumberField("อุณหภูมิสูงสุดเฉลี่ยรายเดือน", value: check(\.monthlyMaxC), range: -50...60, unit: "°C")
                }
                padField("T_min (ต่ำสุดของพื้นที่)") {
                    TCNumberField("อุณหภูมิต่ำสุดของพื้นที่", value: check(\.tMinC), range: -50...40, unit: "°C")
                }
            }
            HStack(alignment: .top, spacing: 16) {
                padField("ความชื้นสัมพัทธ์") {
                    TCNumberField("ความชื้นสัมพัทธ์", value: check(\.humidityPct), range: 0...100, unit: "%")
                }
                padField("ระยะใต้แผงถึงหลังคา") {
                    TCNumberField("ระยะใต้แผงถึงหลังคา", value: check(\.rearClearanceMm), range: 0...2000, unit: "มม.")
                }
                padField("ระยะขอบหลังคาถึงขอบแผง") {
                    TCNumberField("ระยะขอบหลังคาถึงขอบแผง", value: check(\.edgeSafeZoneM), range: 0...20, step: 0.1, unit: "ม.")
                }
            }
            padField("ชั้นกันไฟใต้แผง") { TCChoiceChips(["มี", "ไม่มี"], selection: yesNo(\.roofFireproof)) }
            HStack(alignment: .top, spacing: 16) {
                installPhotos("install.fireproof", "รูปชั้นกันไฟ")
                installPhotos("install.edge", "รูประยะขอบหลังคา")
            }
            TCSwitchRow("พื้นที่มีแอมโมเนีย (ฟาร์ม ทุ่งหญ้า)", isOn: flag(\.ammonia))
            TCSwitchRow("พื้นที่ลมแรง", isOn: flag(\.highWind))
            TCSwitchRow("พื้นที่ฟ้าผ่าบ่อย", isOn: flag(\.lightning))
            padField("แหล่งเงาบัง") { TCMultiChips(Self.shadeSources, selection: shadeChoice, columns: 3) }
            installPhotos("install.shade", "รูปแหล่งเงาบัง")
        }
    }

    // MARK: iPhone section

    var installSection: some View {
        PadSection("ตรวจตามคู่มือติดตั้งแผง (ZNSHINE)") {
            installRules
            LabeledContent("มุมเอียงแผงที่วางแผน (°)") {
                TextField("กรอก", value: check(\.plannedTiltDeg), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Text(tiltHint).font(.sarabun(12.5)).foregroundStyle(Theme.inkMuted)
            LabeledContent("ความสูงจากระดับน้ำทะเล (ม.)") {
                TextField("กรอก", value: check(\.altitudeM), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("ระยะห่างทะเล / แหล่งกำมะถัน").foregroundStyle(Theme.inkMuted)
                TCChoiceChips(Self.seaOptions.map(\.1), selection: seaChoice)
            }
            LabeledContent("อุณหภูมิต่ำสุดเฉลี่ยรายเดือน (°C)") {
                TextField("กรอก", value: check(\.monthlyMinC), format: .number).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
            }
            LabeledContent("อุณหภูมิสูงสุดเฉลี่ยรายเดือน (°C)") {
                TextField("กรอก", value: check(\.monthlyMaxC), format: .number).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
            }
            LabeledContent("T_min ต่ำสุดของพื้นที่ (°C)") {
                TextField("กรอก", value: check(\.tMinC), format: .number).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
            }
            LabeledContent("ความชื้นสัมพัทธ์ (%)") {
                TextField("กรอก", value: check(\.humidityPct), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("ระยะใต้แผงถึงหลังคา (มม.)") {
                TextField("กรอก", value: check(\.rearClearanceMm), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("ระยะขอบหลังคาถึงขอบแผง (ม.)") {
                TextField("กรอก", value: check(\.edgeSafeZoneM), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("ชั้นกันไฟใต้แผง").foregroundStyle(Theme.inkMuted)
                TCChoiceChips(["มี", "ไม่มี"], selection: yesNo(\.roofFireproof))
            }
            installPhotos("install.fireproof", "รูปชั้นกันไฟ")
            installPhotos("install.edge", "รูประยะขอบหลังคา")
            Toggle("พื้นที่มีแอมโมเนีย (ฟาร์ม ทุ่งหญ้า)", isOn: flag(\.ammonia))
            Toggle("พื้นที่ลมแรง", isOn: flag(\.highWind))
            Toggle("พื้นที่ฟ้าผ่าบ่อย", isOn: flag(\.lightning))
            VStack(alignment: .leading, spacing: 6) {
                Text("แหล่งเงาบัง").foregroundStyle(Theme.inkMuted)
                TCMultiChips(Self.shadeSources, selection: shadeChoice)
            }
            installPhotos("install.shade", "รูปแหล่งเงาบัง")
        }
    }
}
