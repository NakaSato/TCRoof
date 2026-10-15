import SwiftUI
import TCRoofUI
import TCRoofCore

/// `ผลการผลิตหลังเชื่อมต่อ` (docs/ui/iec62446-test screen 4): the 7-day energy, Yr, array temperature and module area
/// typed in, Yf, PR, kWh a day and efficiency worked out, and the after checks. The board's `ฟอร์มเดิม` comparison is
/// left out: the app keeps no hand-typed Yf / PR to compare with.
struct IECPerformancePage: View {
    @Bindable var job: Job
    let inverter: Int
    @Environment(\.modelContext) private var context

    var body: some View {
        let r = job.iecReport ?? job.newIECReport
        let inv = r.inverters[inverter]
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 14) {
                inputs(r, inv)
                checks(r, inv)
            }
            .frame(maxWidth: .infinity)
            results(r, inv).frame(maxWidth: .infinity)
        }
    }

    private func save(_ change: @escaping (inout IECReport) -> Void) { job.updateIEC(context, change) }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func inputs(_ r: IECReport, _ inv: IECReport.Inverter) -> some View {
        let i = inverter
        return card("ข้อมูลที่กรอก") {
            HStack(spacing: 12) {
                IECNumberField(title: "พลังงานที่ผลิตได้ 7 วัน", unit: "kWh", value: inv.energy7dKWh) { v in save { $0.inverters[i].energy7dKWh = v } }
                IECNumberField(title: "Solar irradiance เฉลี่ย (Yr)", unit: "kWh/m²/วัน", value: r.yrKWhM2Day) { v in save { $0.yrKWhM2Day = v } }
            }
            HStack(spacing: 12) {
                IECNumberField(title: "Array Temperature", unit: "°C", value: r.arrayTempC) { v in save { $0.arrayTempC = v } }
                IECNumberField(title: "พื้นที่แผงต่อแผ่น", unit: "m²", value: r.module.areaM2, placeholder: "จาก datasheet") { v in save { $0.module.areaM2 = v } }
            }
            IECTextField(title: "หมายเหตุ", text: inv.remark) { t in save { $0.inverters[i].remark = t } }
        }
    }

    private func checks(_ r: IECReport, _ inv: IECReport.Inverter) -> some View {
        let i = inverter, t = r.tally(inv, .vmpAndImp)
        return card("ตรวจการทำงาน") {
            VStack(spacing: 0) {
                Button {
                    save { $0.inverters[i].functionalAfter = inv.functionalAfter == .normal ? .abnormal : inv.functionalAfter == .abnormal ? nil : .normal }
                } label: {
                    checkLine(inv.functionalAfter == .normal, "Inverter testing", inv.functionalAfter.map { $0 == .normal ? "Normal" : "Abnormal" } ?? "ยังไม่ได้ตรวจ",
                              bad: inv.functionalAfter == .abnormal)
                }
                .buttonStyle(.plain)
                .accessibilityHint("แตะเพื่อสลับ Normal / Abnormal")
                Divider()
                checkLine(!r.thermalPhotos.isEmpty, "ภาพถ่ายความร้อนแผงเซลล์", r.thermalPhotos.isEmpty ? "ยังไม่มีรูป" : "เอกสารแนบ \(r.thermalPhotos.count) รูป")
                Divider()
                checkLine(t.isComplete, "Vmp / Imp ทุกสตริง", "\(t.done)/\(t.total)")
            }
        }
    }

    private func checkLine(_ ok: Bool, _ title: String, _ value: String, bad: Bool = false) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ok ? Theme.success : bad ? Theme.danger : Theme.pendingSoft)
                if ok || bad { Image(systemName: ok ? "checkmark" : "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.onPrimary) }
                else { Circle().fill(Theme.pending).frame(width: 7, height: 7) }
            }
            .frame(width: 24, height: 24)
            Text(title).font(.sarabunFixed(15)).foregroundStyle(Theme.navy)
            Spacer()
            Text(value).font(.sarabunFixed(15, .bold)).foregroundStyle(ok ? Theme.navy : bad ? Theme.dangerText : Theme.warningInk)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func results(_ r: IECReport, _ inv: IECReport.Inverter) -> some View {
        VStack(spacing: 14) {
            card("คำนวณให้") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 16) {
                    result("Final Yield (Yf)", r.yf(inv).map { IECFormat.number($0) }, "kWh/kWp/วัน", missing: "รอพลังงาน 7 วัน")
                    result("Performance Ratio", r.pr(inv).map { IECFormat.number($0) }, "= Yf ÷ Yr", missing: "รอ Yr")
                    result("พลังงานเฉลี่ยต่อวัน", r.dailyKWh(inv).map { IECFormat.number($0, grouping: true) }, "kWh", missing: "รอพลังงาน 7 วัน")
                    result("System Efficiency", r.efficiency(inv).map { "\(Int(($0 * 100).rounded()))%" }, "ของแสงที่ตกบนแผง", missing: "รอพื้นที่แผง")
                }
            }
            passBanner(r, inv)
        }
    }

    private func result(_ title: String, _ value: String?, _ note: String, missing: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            Text(value ?? "—").font(.sarabunFixed(30, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
            Text(value == nil ? missing : note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    /// Whether the after test passes: the inverter check and PR ≥ 0.70 (no PWA threshold yet; the board's assumption).
    private func passBanner(_ r: IECReport, _ inv: IECReport.Inverter) -> some View {
        let pass = r.passes(inv, .after)
        let (title, ink, fill): (String, Color, Color) = switch pass {
        case true?: ("ผ่าน", Theme.successInk, Theme.successSoft)
        case false?: ("ไม่ผ่าน", Theme.dangerText, Theme.dangerSoft)
        case nil: ("ยังไม่ครบ", Theme.warningInk, Theme.pendingSoft)
        }
        return HStack(spacing: 12) {
            Text(title).font(.sarabunFixed(15, .bold)).foregroundStyle(ink).padding(.horizontal, 12).frame(height: 30)
                .background(fill, in: Capsule())
            VStack(alignment: .leading, spacing: 0) {
                Text("ผลหลังเชื่อมต่อ").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Text("PR ≥ \(IECFormat.number(IECReport.defaultPRThreshold)) และ Inverter testing ปกติ").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }
}

/// `สภาพการทดสอบและเครื่องมือ`: the weather of each phase (rows 29–30), the test date, tester and instruments.
struct IECConditionsPage: View {
    @Bindable var job: Job
    @Environment(\.modelContext) private var context

    var body: some View {
        let r = job.iecReport ?? job.newIECReport
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                phase("ก่อนการเชื่อมต่อระบบ", r.before) { c in job.updateIEC(context) { $0.before = c } }
                phase("หลังการเชื่อมต่อระบบ", r.after) { c in job.updateIEC(context) { $0.after = c } }
            }
            record(r)
        }
    }

    private func phase(_ title: String, _ c: IECReport.Conditions, set: @escaping (IECReport.Conditions) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(Theme.paperBand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            IECNumberField(title: "อุณหภูมิอากาศ", unit: "°C", value: c.ambientC) { v in var n = c; n.ambientC = v; set(n) }
            IECNumberField(title: "ความเข้มแสง", unit: "W/m²", value: c.irradianceWm2) { v in var n = c; n.irradianceWm2 = v; set(n) }
            IECTextField(title: "เวลาทดสอบ", text: c.time ?? "", placeholder: "13:00") { t in var n = c; n.time = t.isEmpty ? nil : t; set(n) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func record(_ r: IECReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ผู้ทดสอบและเครื่องมือ").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
            HStack(spacing: 12) {
                IECTextField(title: "ผู้ทดสอบ", text: r.tester) { t in job.updateIEC(context) { $0.tester = t } }
                VStack(alignment: .leading, spacing: 6) {
                    Text("วันที่ทดสอบ").font(.sarabunFixed(14)).foregroundStyle(Theme.navy)
                    // no date shown until one is set, so today is never mistaken for a kept date
                    if r.testDate == nil {
                        Button { job.updateIEC(context) { $0.testDate = .now } } label: { Label("ระบุวันที่", systemImage: "calendar") }
                            .buttonStyle(TCButtonStyle(.secondary, size: .card)).frame(minHeight: 50)
                    } else {
                        DatePicker("วันที่ทดสอบ", selection: Binding(get: { r.testDate ?? .now }, set: { d in job.updateIEC(context) { $0.testDate = d } }),
                                   displayedComponents: .date)
                            .labelsHidden().environment(\.locale, Locale(identifier: "th_TH"))
                            .frame(minHeight: 50)
                    }
                }
            }
            HStack(spacing: 12) {
                IECTextField(title: "S/N แคลมป์มิเตอร์", text: r.instruments.multimeterClamp) { t in job.updateIEC(context) { $0.instruments.multimeterClamp = t } }
                IECTextField(title: "S/N เครื่องวัด IR", text: r.instruments.insulationTester) { t in job.updateIEC(context) { $0.instruments.insulationTester = t } }
            }
            HStack(spacing: 12) {
                IECTextField(title: "S/N เครื่องวัดแสง", text: r.instruments.irradianceMeter) { t in job.updateIEC(context) { $0.instruments.irradianceMeter = t } }
                IECTextField(title: "S/N กล้องภาพความร้อน", text: r.instruments.thermalCamera) { t in job.updateIEC(context) { $0.instruments.thermalCamera = t } }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }
}

/// `ความเข้มแสงและภาพความร้อน`: the irradiance meter's screen and the thermal images (the sheet's `เอกสารแนบ`).
struct IECStationPhotosPage: View {
    @Bindable var job: Job
    @Environment(\.modelContext) private var context

    var body: some View {
        let r = job.iecReport ?? job.newIECReport
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ความเข้มแสงอาทิตย์ (W/m²)").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                IECPhotoTile(caption: "เครื่องวัดแสง", asset: job.iecPhoto(r.irradiancePhoto), height: 220, stubReading: "1022") { data in
                    let id = job.storeIECPhoto(data, replacing: r.irradiancePhoto, context: context)
                    job.updateIEC(context) { $0.irradiancePhoto = id }
                } remove: {
                    job.removeIECPhoto(r.irradiancePhoto, context: context)
                    job.updateIEC(context) { $0.irradiancePhoto = nil }
                }
                .frame(width: 320)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 12) {
                Text("ภาพถ่ายความร้อน · \(r.thermalPhotos.count) รูป").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(r.thermalPhotos, id: \.self) { id in
                        IECPhotoTile(caption: "ความร้อน", asset: job.iecPhoto(id), height: 150, stubReading: "59.4") { data in
                            let new = job.storeIECPhoto(data, replacing: id, context: context)
                            job.updateIEC(context) { r in if let k = r.thermalPhotos.firstIndex(of: id) { r.thermalPhotos[k] = new } }
                        } remove: {
                            job.removeIECPhoto(id, context: context)
                            job.updateIEC(context) { $0.thermalPhotos.removeAll { $0 == id } }
                        }
                    }
                    IECPhotoTile(caption: "ภาพความร้อนเพิ่ม", asset: nil, height: 150, stubReading: "59.4") { data in
                        let id = job.storeIECPhoto(data, replacing: nil, context: context)
                        job.updateIEC(context) { $0.thermalPhotos.append(id) }
                    } remove: {}
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// A number in a box, saved when typing ends.
struct IECNumberField: View {
    let title: String
    let unit: String
    let value: Double?
    var placeholder = "—"
    let set: (Double?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.sarabunFixed(14)).foregroundStyle(Theme.navy)
                if value == nil {
                    Text("● ยังขาด").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.warningInk)
                }
            }
            HStack {
                TextField(placeholder, text: $text).keyboardType(.decimalPad).focused($focused)
                    .font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                Text(unit).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 14).frame(minHeight: 50)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? Theme.primary : Theme.borderControl, lineWidth: focused ? 2 : 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { text = value.map { IECFormat.number($0, digits: 3) } ?? "" }
        .onChange(of: value) { _, v in if !focused { text = v.map { IECFormat.number($0, digits: 3) } ?? "" } }
        .onChange(of: focused) { _, on in if !on { commit() } }
        .onSubmit(commit)
        .onDisappear(perform: commit)
        .accessibilityElement(children: .contain)
    }

    private func commit() {
        let v = Double(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
        if v != value { set(v) }
    }
}

/// Text in a box, saved when typing ends.
struct IECTextField: View {
    let title: String
    let text: String
    var placeholder = ""
    let set: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.sarabunFixed(14)).foregroundStyle(Theme.navy)
            TextField(placeholder, text: $draft).focused($focused).font(.sarabunFixed(17)).foregroundStyle(Theme.navy)
                .padding(.horizontal, 14).frame(minHeight: 50)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? Theme.primary : Theme.borderControl, lineWidth: focused ? 2 : 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { draft = text }
        .onChange(of: text) { _, t in if !focused { draft = t } }
        .onChange(of: focused) { _, on in if !on, draft != text { set(draft) } }
        .onSubmit { if draft != text { set(draft) } }
        .onDisappear { if draft != text { set(draft) } }
    }
}
