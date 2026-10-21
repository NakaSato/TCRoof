import SwiftUI
import TCRoofUI
import TCRoofCore
import ModuleRules

/// The daily report's module installation checklist from ZNSHINE's manual (docs/specs/module-install-rules.md §7.3):
/// a card with today's status that opens the checklist. It is kept on the report (`Daily.moduleCheck`) on days with
/// module work; our engineer signs only once it has no block and every warn has a reason.
struct DailyModuleCard: View {
    @Binding var report: RoutineReport.Daily
    /// The day's photos: the checklist's evidence is among them (`ModuleEvidence`).
    @Binding var photos: [DraftPhoto]
    var compact = false
    @State private var open = false

    static func check(_ r: RoutineReport.Daily) -> InstallDailyCheck? { r.moduleCheck.flatMap(InstallDailyCheck.decode) }

    /// Why the report can't be signed yet, Thai; empty when it can (or there is no module work today).
    static func stops(_ r: RoutineReport.Daily) -> [String] {
        guard let c = check(r) else { return [] }
        let v = c.validation(crew: r.crewTotal)
        return v.blocks.map { "\($0.id) \($0.messageTH)" }
            + v.warns.filter { (c.reasons[$0.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.map { "\($0.id) ใส่เหตุผล" }
    }

    var body: some View {
        let c = Self.check(report)
        Button { open = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "checklist").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ตรวจติดตั้งแผงตามคู่มือ").font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                    Text(status(c)).font(.sarabun(12.5)).foregroundStyle(color(c)).lineLimit(2)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.inkMuted)
            }
            .padding(compact ? 12 : 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dailyModuleCheck")
        .sheet(isPresented: $open) { DailyModuleSheet(report: $report, photos: $photos) }
        #if DEBUG
        .task { if Self.openOnAppear { Self.openOnAppear = false; open = true } }
        #endif
    }

    #if DEBUG
    /// `-dailyModuleDemo open`: the sheet opens once.
    nonisolated(unsafe) static var openOnAppear = false
    #endif

    func status(_ c: InstallDailyCheck?) -> String {
        guard let c else { return "วันนี้ไม่มีงานติดตั้งแผง | แตะเพื่อเปิดรายการตรวจ" }
        let v = c.validation(crew: report.crewTotal)
        let reasonless = v.warns.filter { (c.reasons[$0.id] ?? "").isEmpty }.count
        if v.blocks.isEmpty && reasonless == 0 && c.openTicks.isEmpty { return "ผ่าน | ลงนามได้" }
        var parts: [String] = []
        if !v.blocks.isEmpty { parts.append("ห้าม \(v.blocks.count)") }
        if reasonless > 0 { parts.append("เตือนรอเหตุผล \(reasonless)") }
        if !c.openTicks.isEmpty { parts.append("ยังไม่ติ๊ก \(c.openTicks.count)") }
        let shot = Set(photos.compactMap { ModuleEvidence.kind($0.tag) })
        if shot.count < ModuleEvidence.allCases.count { parts.append("รูปหลักฐาน \(shot.count)/\(ModuleEvidence.allCases.count)") }
        return parts.joined(separator: " | ")
    }

    func color(_ c: InstallDailyCheck?) -> Color {
        guard let c else { return Theme.inkMuted }
        return Self.stops(report).isEmpty ? (c.openTicks.isEmpty ? Theme.okText : Theme.pending) : Theme.dangerText
    }
}

private struct ScanTarget: Identifiable {
    let rejected: Bool
    var id: Bool { rejected }
}

/// The checklist itself (§7.3): safety, mounting readings, cable, grounding and serials, with the rules live at the top.
struct DailyModuleSheet: View {
    @Binding var report: RoutineReport.Daily
    @Binding var photos: [DraftPhoto]
    /// `สแกน` opened for the installed (false) or the rejected (true) list.
    @State private var scanning: Bool?
    @Environment(\.dismiss) private var dismiss
    @State private var torques = ""
    @State private var groundTorques = ""
    @State private var serials = ""
    @State private var rejected = ""

    var check: InstallDailyCheck? { DailyModuleCard.check(report) }

    func edit(_ f: (inout InstallDailyCheck) -> Void) {
        var c = check ?? InstallDailyCheck()
        f(&c)
        report.moduleCheck = c.json
    }

    func tick(_ kp: WritableKeyPath<InstallDailyCheck, Bool?>) -> Binding<Bool> {
        Binding(get: { check?[keyPath: kp] == true }, set: { v in edit { $0[keyPath: kp] = v ? true : nil } })
    }
    func number(_ kp: WritableKeyPath<InstallDailyCheck, Double?>) -> Binding<Double?> {
        Binding(get: { check?[keyPath: kp] }, set: { v in edit { $0[keyPath: kp] = v } })
    }
    func count(_ kp: WritableKeyPath<InstallDailyCheck, Int?>) -> Binding<Double?> {
        Binding(get: { check?[keyPath: kp].map(Double.init) }, set: { v in edit { $0[keyPath: kp] = v.map { Int($0.rounded()) } } })
    }
    func reason(_ id: String) -> Binding<String> {
        Binding(get: { check?.reasons[id] ?? "" }, set: { v in edit { $0.reasons[id] = v.isEmpty ? nil : v } })
    }

    var active: Binding<Bool> {
        Binding(get: { report.moduleCheck != nil }, set: { on in report.moduleCheck = on ? (check ?? InstallDailyCheck()).json : nil })
    }

    var frame: Binding<Int> {
        Binding(get: { check?.frameModified.map { $0 ? 2 : 1 } ?? 0 }, set: { v in edit { $0.frameModified = v == 0 ? nil : v == 2 } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("วันนี้มีงานติดตั้งแผง", isOn: active)
                } footer: {
                    Text("ตามคู่มือติดตั้งแผง ZNSHINE | กฎชุด \(ModuleCatalog.ruleSetVersion) | ลงนามได้เมื่อไม่มีข้อห้าม และข้อเตือนมีเหตุผล")
                }
                if let c = check {
                    Section("ผลตรวจ") {
                        ModuleRulesList(c.validation(crew: report.crewTotal), empty: "ไม่มีข้อห้ามหรือข้อเตือน", reason: reason)
                        ForEach(c.openTicks, id: \.self) { Label($0, systemImage: "circle").font(.sarabun(13)).foregroundStyle(Theme.pending) }
                    }
                    safety
                    mounting
                    cable
                    grounding
                    serialSection
                }
            }
            .navigationTitle("ตรวจติดตั้งแผงตามคู่มือ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } }
            .sheet(item: Binding(get: { scanning.map { ScanTarget(rejected: $0) } }, set: { if $0 == nil { scanning = nil } })) { t in
                ModuleSerialScanSheet(title: t.rejected ? "สแกนแผงที่คัดออก" : "สแกนแผงที่ติดตั้ง") { addScanned($0, rejectedList: t.rejected) }
            }
            .onAppear {
                torques = InstallDailyCheck.text(check?.boltTorquesNm ?? [])
                groundTorques = InstallDailyCheck.text(check?.groundTorquesNm ?? [])
                serials = (check?.installedSerials ?? []).joined(separator: "\n")
                rejected = (check?.rejectedSerials ?? []).joined(separator: "\n")
            }
        }
    }

    var safety: some View {
        Section("ความปลอดภัย") {
            LabeledContent("ช่างวันนี้ (คน)") {
                TextField("\(report.crewTotal) จากกำลังคน", value: count(\.crewCount), format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            Toggle("อุปกรณ์ป้องกันครบ (ถุงมือ หมวก เข็มขัดนิรภัย รองเท้ายาง)", isOn: tick(\.ppe))
            Toggle("ไม่สวมเครื่องประดับ", isOn: tick(\.noJewelry))
            Toggle("อากาศแห้ง ไม่มีฝน ลมไม่แรง", isOn: tick(\.weatherDry))
            Toggle("แผงและขั้วต่อแห้ง", isOn: tick(\.modulesDry))
        }
    }

    var mounting: some View {
        Section {
            Picker("วิธียึด", selection: Binding(get: { check?.method ?? .clamp }, set: { v in edit { $0.method = v } })) {
                Text("ตัวจับ (clamp)").tag(MountingMethod.clamp)
                Text("ยึดน็อตผ่านรู").tag(MountingMethod.bolt)
                Text("แทรคเกอร์ 1 แกน").tag(MountingMethod.tracker1P)
                Text("แทรคเกอร์ 2V").tag(MountingMethod.tracker2V)
            }
            LabeledContent("แรงขันน็อตที่สุ่มวัด (N·m)") {
                TextField("เช่น 18, 19, 20", text: $torques).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                    .onChange(of: torques) { _, t in edit { $0.boltTorquesNm = InstallDailyCheck.readings(t) } }
            }
            LabeledContent("แหวนรอง หนา (มม.)") {
                TextField("กรอก", value: number(\.washerThicknessMm), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("แหวนรอง เส้นผ่านศูนย์กลางนอก (มม.)") {
                TextField("กรอก", value: number(\.washerOdMm), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("ตัวจับต่อแผง (ตัว)") {
                TextField("กรอก", value: count(\.clampsPerModule), format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("ตัวจับทับขอบแผง (มม.)") {
                TextField("7–10", value: number(\.clampOverlapMm), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("ช่องว่างระหว่างแผง (มม.)") {
                TextField("≥ 10", value: number(\.gapMm), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("ระยะใต้แผงถึงหลังคา (มม.)") {
                TextField("≥ 115", value: number(\.rearClearanceMm), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Toggle("รูระบายน้ำที่เฟรมไม่อุดตัน", isOn: tick(\.drainHolesClear))
            Picker("เจาะหรือดัดแปลงเฟรม", selection: frame) {
                Text("ยังไม่ตรวจ").tag(0); Text("ไม่มี").tag(1); Text("พบ").tag(2)
            }
            .pickerStyle(.segmented)
            Toggle("แผงสีเซลล์เดียวกันติดตั้งด้วยกัน", isOn: tick(\.sameColour))
            ModuleEvidenceRow(kind: .torque, photos: $photos)
        } header: {
            Text("การยึดแผง")
        } footer: {
            Text("ขันน็อตให้ได้ 16–20 N·m คลายออก 90–180° แล้วขันใหม่ให้ได้ค่าเดิม เพื่อลดการคลายตัว")
        }
    }

    var cable: some View {
        Section("สายไฟ") {
            Toggle("สายไม่วนเป็นห่วง", isOn: tick(\.noLoops))
            LabeledContent("รัศมีดัดสายที่แคบที่สุด (มม.)") {
                TextField("≥ 43", value: number(\.bendRadiusMm), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Toggle("สายไม่โดนแดดโดยตรง", isOn: tick(\.outOfSun))
            Toggle("สายเดินในท่อ ไม่แช่น้ำ", isOn: tick(\.inConduit))
            ModuleEvidenceRow(kind: .cable, photos: $photos)
        }
    }

    var grounding: some View {
        Section("สายดิน") {
            LabeledContent("ขนาดสายดิน (ตร.มม.)") {
                TextField("4–14", value: number(\.groundWireMm2), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Toggle("น็อต M4 + แหวนจักร + แหวนรอง", isOn: tick(\.m4StarWasher))
            LabeledContent("แรงขันน็อตสายดิน (N·m)") {
                TextField("เช่น 5, 6", text: $groundTorques).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                    .onChange(of: groundTorques) { _, t in edit { $0.groundTorquesNm = InstallDailyCheck.readings(t) } }
            }
            ModuleEvidenceRow(kind: .ground, photos: $photos)
        }
    }

    var serialSection: some View {
        Section {
            TextField("เลขซีเรียลแผงที่ติดตั้ง บรรทัดละเลข", text: $serials, axis: .vertical).lineLimit(2...6)
                .onChange(of: serials) { _, t in edit { $0.installedSerials = Self.lines(t) } }
                .accessibilityIdentifier("moduleSerials.installed")
            Button { scanning = false } label: { Label("สแกนบาร์โค้ดแผงที่ติดตั้ง", systemImage: "barcode.viewfinder") }
                .accessibilityIdentifier("moduleSerials.scanInstalled")
            TextField("เลขซีเรียลแผงที่คัดออก (แตก สนิม)", text: $rejected, axis: .vertical).lineLimit(1...4)
                .onChange(of: rejected) { _, t in edit { $0.rejectedSerials = Self.lines(t) } }
            Button { scanning = true } label: { Label("สแกนบาร์โค้ดแผงที่คัดออก", systemImage: "barcode.viewfinder") }
            ModuleEvidenceRow(kind: .rejected, photos: $photos)
        } header: {
            Text("เลขซีเรียล")
        } footer: {
            Text("ติดตั้ง \(check?.installedSerials.count ?? 0) แผง | คัดออก \(check?.rejectedSerials.count ?? 0) แผง")
        }
    }

    /// Adds scanned serials to a list, once each.
    func addScanned(_ codes: [String], rejectedList: Bool) {
        let text = rejectedList ? rejected : serials
        var list = Self.lines(text)
        for c in codes where !list.contains(c) { list.append(c) }
        if rejectedList { rejected = list.joined(separator: "\n") } else { serials = list.joined(separator: "\n") }
    }

    static func lines(_ t: String) -> [String] {
        t.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
