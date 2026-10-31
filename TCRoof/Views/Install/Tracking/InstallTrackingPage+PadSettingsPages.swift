import SwiftUI
import TCRoofUI
import TCRoofCore

extension InstallTrackingPage {
    // MARK: ทีมและสิทธิ์

    var padTeamPage: some View {
        let team = permissions.can(.assignTeam, on: job.access), externals = permissions.can(.assignExternal, on: job.access)
        return VStack(alignment: .leading, spacing: 18) {
            padSection("วิศวกรผู้ควบคุมงาน", footer: "ลงนามรายงานประจำวันและปิดการทดสอบ IEC") {
                if let s = padSupervisor { padPersonRow(s, role: .supervisor, first: true) } else { padNoteRow("ยังไม่ระบุ", first: true) }
                if externals { padActionRow("เปลี่ยนวิศวกรผู้ควบคุมงาน") { padSheet = .access } }
            }
            padSection("ทีมงานของเรา", footer: "งานนี้อยู่ใน งานของฉัน ของคนเหล่านี้") {
                if padTeam.isEmpty { padNoteRow("ยังไม่ระบุ (ทุกคนในทีม)", first: true) }
                ForEach(Array(padTeam.enumerated()), id: \.offset) { i, e in padPersonRow(e, role: .team, first: i == 0) }
                if team { padActionRow("เพิ่มคนจากรายชื่อทีม") { padSheet = .access } }
            }
            padSection("ผู้รับเหมา", footer: "เห็นเฉพาะงานนี้ | ส่งคำขอและผล IEC") {
                if padExternals.isEmpty { padNoteRow("ยังไม่มีผู้รับเหมา", first: true) }
                ForEach(Array(padExternals.enumerated()), id: \.offset) { i, e in padPersonRow(e, role: .external, first: i == 0) }
                if externals { padActionRow("เพิ่มผู้รับเหมา") { padSheet = .access } }
            }
        }
    }

    /// Takes the person off the job, as `JobAccessCard` does (`externals`, `teamMembers`, `supervisorEmail`).
    func removePerson(_ email: String, _ role: PadPersonRole) {
        guard permissions.can(role.capability, on: job.access) else { return }
        if padDemoOn {
            switch role {
            case .supervisor: padDemo.supervisor = nil
            case .team: padDemo.team.removeAll { $0 == email }
            case .external: padDemo.externals.removeAll { $0 == email }
            }
            return
        }
        switch role {
        case .supervisor: job.supervisorEmail = nil
        case .team: job.teamMembers.removeAll { $0 == email }
        case .external: job.externals.removeAll { $0 == email }
        }
        try? context.save()
    }

    // MARK: หัวเอกสาร

    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    private var padBranch: String {
        let st = job.stationDocs
        let branch = padDemoOn ? padDemo.branch : [st.branch, st.region].filter { !$0.isEmpty }.joined(separator: " | ")
        return branch
    }

    private func textAction(_ f: SettingsDraft.Field) -> (() -> Void)? {
        editsRoutine ? { padSheet = .text(f) } : nil
    }

    var padHeaderPage: some View {
        let s = settingsShown
        return VStack(alignment: .leading, spacing: 18) {
            padSection(nil) {
                padValueRow("หน่วยงาน กปภ.", hint: "สาขาและเขตของสถานี | แก้ที่ข้อมูลสถานี", value: padBranch, first: true,
                            locked: !editsStation, id: "padSettings.branch", action: editsStation ? { padSheet = .station } : nil)
                padValueRow(SettingsDraft.Field.contractName.title, hint: "ชื่อโครงการในหัวรายงาน", value: s.contractName,
                            id: "padSettings.contractName", action: textAction(.contractName))
                padValueRow(SettingsDraft.Field.contractor.title, value: s.contractor, id: "padSettings.contractor", action: textAction(.contractor))
                padValueRow(SettingsDraft.Field.employer.title, value: s.employer, id: "padSettings.employer", action: textAction(.employer))
                padValueRow(SettingsDraft.Field.workTime.title, hint: "ใช้เป็นค่าเริ่มของรายงานแต่ละวัน",
                            value: Self.clock(s.workStart) + " – " + Self.clock(s.workEnd), id: "padSettings.workTime",
                            action: editsRoutine ? { padSheet = .workTime } : nil)
            }
            if editsRoutine { padEditAllCard }
        }
    }

    private var padEditAllCard: some View {
        padSection(nil, footer: "วันหยุด ผู้ลงนาม ตำแหน่ง เครื่องมือ และพื้นที่ทำงาน | " + RoutineSettingsSheet.publicHolidaysNote) {
            padValueRow("แก้ไขทั้งหมด", value: "", first: true, id: "padSettings.editAll") { padSheet = .routine }
        }
    }

    // MARK: รอบรายงาน

    /// `จ – ศ | จ – ส | ทุกวัน`.
    static let weekdayOptions: [(title: String, days: Set<Int>)] = [("จ – ศ", [2, 3, 4, 5, 6]), ("จ – ส", [2, 3, 4, 5, 6, 7]),
                                                                    ("ทุกวัน", [1, 2, 3, 4, 5, 6, 7])]

    var padRoutinePage: some View {
        let s = settingsShown
        let picked = Self.weekdayOptions.firstIndex { $0.days == s.workingWeekdays }
        return VStack(alignment: .leading, spacing: 18) {
            padSection(nil, footer: picked == nil ? "วันทำงานตอนนี้: " + Self.weekdaysSummary(s.workingWeekdays) : nil) {
                padPickerRow(SettingsDraft.Field.weekdays.title, hint: "วันหยุดราชการไม่นับ", options: Self.weekdayOptions.map(\.title),
                             selected: picked, first: true, editable: editsRoutine) { i in
                    settingsDraft.weekdays = Self.weekdayOptions[i].days
                }
                padValueRow(SettingsDraft.Field.inspector.title, hint: "ผู้ตรวจ กปภ. ที่รับทราบรายงานประจำวัน", value: s.inspector,
                            id: "padSettings.inspector", action: textAction(.inspector))
                padValueRow("วิศวกรหน้างาน", value: s.siteEngineer)
                padValueRow("วันหยุดเพิ่ม", value: s.holidays.isEmpty ? "ไม่มี" : "\(s.holidays.count) วัน")
            }
            if editsRoutine { padEditAllCard }
        }
    }

    // MARK: การเชื่อมต่อและ IEC

    private var instrumentsSummary: String {
        guard let r = job.iecReport else { return "" }
        let i = r.instruments
        return [i.multimeterClamp, i.insulationTester, i.irradianceMeter, i.thermalCamera]
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " | ")
    }

    var padConnectionPage: some View {
        let ctx = job.stationContext
        let instruments = instrumentsSummary
        return VStack(alignment: .leading, spacing: 18) {
            padSection(nil, footer: "ขนาดสถานีกำหนดว่าต้องยื่น พค.2 (กกพ.) หรือไม่") {
                padPickerRow(SettingsDraft.Field.sellsPower.title, hint: "มีผลต่อเอกสาร กปภ. และ กกพ.", options: ["Zero Export", "ขนานไฟ (ขายคืน)"],
                             selected: sellsPowerShown ? 1 : 0, first: true, editable: editsStation) { i in
                    settingsDraft.sellsPower = i == 1
                }
                padValueRow("ขอยกเว้นใบอนุญาต กกพ.",
                            value: ctx.over200kVA ? "200 kVA ขึ้นไป | ต้องยื่น พค.2" : "ต่ำกว่า 200 kVA | ไม่ต้องยื่นขอยกเว้น",
                            id: "padSettings.erc", action: editsStation ? { padSheet = .station } : nil)
                padValueRow("ชุดที่ยื่น", value: StationDocs.packages(ctx).map(\.title).joined(separator: ", "))
            }
            padSection("การทดสอบ IEC 62446") {
                padValueRow("เครื่องมือวัด", value: instruments.isEmpty ? "ยังไม่ได้ตั้งค่า" : instruments, first: true,
                            id: "padSettings.instruments") { leave(to: .tab(.iec)) }
                padValueRow("อินเวอร์เตอร์", value: job.iecReport.map { "\($0.inverters.count) เครื่อง | \($0.stringCount) สตริง" } ?? "ยังไม่ได้ตั้งค่า")
            }
        }
    }

    // MARK: ข้อมูลอ้างอิง

    /// The linked survey's number and its last issued REV.
    private func surveyLine(_ id: UUID) -> String {
        guard let s = SurveyModel.shared.jobs.first(where: { $0.id == id }) else { return "" }
        let doc = s.docNo.isEmpty ? "ไม่มีเลขที่" : s.docNo
        return doc + " | " + (s.lastRevision.map { "ออก REV \($0.rev)" } ?? "ยังไม่ออก REV")
    }

    func padReferencePage(_ data: InstallPageData) -> some View {
        let survey = data.surveyReport
        return VStack(alignment: .leading, spacing: 18) {
            padSection(nil, footer: "แก้ที่หน้ารายละเอียดงาน") {
                padValueRow("ประเภทงาน", hint: "มีแผน MP | รายงานประจำ | เอกสาร กปภ.", value: job.kind.title, first: true, locked: true)
                padValueRow("รายงานสำรวจ", hint: "ดูอย่างเดียว", value: survey.map(surveyLine) ?? "ไม่มีรายงานที่เชื่อมไว้",
                            id: "padSettings.survey", action: survey.map { id in { leave(to: .route(.survey(id))) } })
                padValueRow("ผังตำแหน่งงาน (Key Plan)", hint: "ใช้ในหน้า 2 ของ DAILY REPORT",
                            value: job.uploadedKeyPlan != nil ? "อัปโหลดแล้ว" : (survey == nil ? "ยังไม่มี" : "ภาพ A2 จากรายงานสำรวจ"))
            }
            padSection("ข้อมูลสถานี") {
                padValueRow("สถานี", value: data.title, first: true)
                padValueRow("เลขที่ MP", value: job.mpNumber.map { "MP \($0)" } ?? "")
                padValueRow("ขนาด", value: job.capacityKW > 0 ? job.capacityKW.formatted(.number.precision(.fractionLength(0...2))) + " kWp" : "")
                padValueRow("ทีม", value: job.team.rawValue)
                padValueRow("ช่วงติดตั้ง", value: ThaiFormat.numericDate.string(from: job.installStart) + " – " + ThaiFormat.numericDate.string(from: job.installEnd))
                padValueRow("สาขา กปภ.", value: job.stationDocs.branch)
                padValueRow("รายละเอียดงาน", value: "", id: "padSettings.detail") { leave(to: .route(.detail)) }
            }
        }
    }

    // MARK: unsaved bar

    var unsavedBar: some View {
        let changes = settingsChanges
        let cats = PadSettingsCategory.allCases.filter { c in changes.contains { $0.category == c } }.map(\.title)
        let frame = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return HStack(spacing: 14) {
            padIconTile("pencil", Theme.warning, size: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text("แก้ไข \(changes.count) รายการ | ยังไม่บันทึก").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Text("หมวด " + cats.joined(separator: ", ") + " | บันทึกแล้วซิงก์ให้ทีมของงานนี้")
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("ยกเลิกการแก้") { settingsDraft = SettingsDraft() }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
            Button { saveSettingsDraft() } label: { Label("บันทึก", systemImage: "checkmark") }
                .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
                .accessibilityIdentifier("padSettings.save")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 940)
        .background(Theme.surface, in: frame)
        .overlay(frame.strokeBorder(Theme.warning.opacity(0.35)))
        .shadow(color: Theme.navySolid.opacity(0.16), radius: 14, y: 6)
        .padding(.horizontal, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("padSettings.unsavedBar")
    }

    /// Writes the draft once: the routine settings, and `sellsPower` through `Job.stationDocs`'s setter so its links
    /// run. The demo keeps it in memory.
    func saveSettingsDraft() {
        let draft = settingsDraft
        settingsDraft = SettingsDraft()
        if padDemoOn {
            padDemo.settings = draft.merged(padDemo.settings)
            if let v = draft.sellsPower { padDemo.sellsPower = v }
            return
        }
        let s = draft.merged(job.routineSettings)
        if s != job.routineSettings { job.routineSettings = s }
        if let v = draft.sellsPower, v != job.stationDocs.sellsPower {
            var station = job.stationDocs
            station.sellsPower = v
            job.stationDocs = station
        }
        try? context.save()
    }
}
