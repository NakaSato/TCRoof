import SwiftUI
import TCRoofUI
import TCRoofCore

/// iPad `ตั้งค่าโครงการ` (docs/ui/install-tracking-ipad-settings): the in-page tab with the iPadOS Settings layout, the
/// station card and the categories on the left, the chosen one on the right. It shows and edits what this station
/// keeps, from the same job data, editors and permissions as the iPhone's gear (`settingsPage`). Picker and text edits
/// wait in `settingsDraft` until `บันทึก`.
enum PadSettingsCategory: String, CaseIterable, Identifiable {
    case team, header, drawings, routine, connection, reference
    var id: String { rawValue }

    var title: String {
        switch self {
        case .team: "ทีมและสิทธิ์"
        case .header: "หัวเอกสาร"
        case .drawings: "แบบก่อสร้าง"
        case .routine: "รอบรายงาน"
        case .connection: "การเชื่อมต่อและ IEC"
        case .reference: "ข้อมูลอ้างอิง"
        }
    }

    var note: String {
        switch self {
        case .team: "ใครทำงานนี้ | ใครลงนาม | ผู้รับเหมาที่เห็นงานนี้"
        case .header: "ใช้ใน DAILY REPORT | คำขอรายสัปดาห์ | Weekly Report"
        case .drawings: "อัปโหลดแบบ | ทุกครั้งที่แก้เป็น Revision ใหม่"
        case .routine: "วันทำงานและผู้ลงนามรายงานประจำ"
        case .connection: "ชุดเอกสาร กปภ. / กกพ. และการทดสอบ IEC"
        case .reference: "แก้ที่ต้นทาง | หน้านี้แสดงอย่างเดียว"
        }
    }

    var symbol: String {
        switch self {
        case .team: "person.2"
        case .header: "doc.text"
        case .drawings: "rectangle.split.2x1"
        case .routine: "calendar.badge.checkmark"
        case .connection: "bolt"
        case .reference: "building.2"
        }
    }

    var tint: Color {
        switch self {
        case .team: PadSettingsTint.team
        case .header: PadSettingsTint.header
        case .drawings: PadSettingsTint.drawings
        case .routine: PadSettingsTint.routine
        case .connection: PadSettingsTint.connection
        case .reference: PadSettingsTint.reference
        }
    }
}

/// The tab's icon tints, in one place.
enum PadSettingsTint {
    static let team = Theme.aiPurple
    static let header = Theme.aiPurple
    static let drawings = Theme.teal
    static let routine = Theme.primary
    static let connection = Theme.warning
    static let reference = Theme.navy
    /// File-type tiles of the drawings.
    static let pdf = Theme.danger
    static let dwg = Theme.teal
    static let image = Theme.primary
}

/// The edits not saved yet: only the fields changed, so a save merges them into what the job holds then (an edit made
/// meanwhile in `RoutineSettingsSheet` stays).
struct SettingsDraft: Equatable {
    var contractName: String?
    var contractor: String?
    var employer: String?
    var inspector: String?
    var workStart: Int?
    var workEnd: Int?
    var weekdays: Set<Int>?
    var sellsPower: Bool?

    /// One per row the bar counts.
    enum Field: String, CaseIterable, Identifiable {
        case contractName, contractor, employer, workTime, inspector, weekdays, sellsPower
        var id: String { rawValue }

        var category: PadSettingsCategory {
            switch self {
            case .contractName, .contractor, .employer, .workTime: .header
            case .inspector, .weekdays: .routine
            case .sellsPower: .connection
            }
        }

        var title: String {
            switch self {
            case .contractName: "สัญญา / โครงการ"
            case .contractor: "จาก (ผู้รับจ้าง)"
            case .employer: "ถึง (ผู้ว่าจ้าง)"
            case .workTime: "เวลาทำงาน"
            case .inspector: "ผู้รับรายงาน"
            case .weekdays: "วันทำงาน"
            case .sellsPower: "การเชื่อมต่อ"
            }
        }
    }

    /// The settings with the draft's fields written in.
    func merged(_ s: RoutineReport.Settings) -> RoutineReport.Settings {
        var s = s
        if let v = contractName { s.contractName = v }
        if let v = contractor { s.contractor = v }
        if let v = employer { s.employer = v }
        if let v = inspector { s.inspector = v }
        if let v = workStart { s.workStart = v }
        if let v = workEnd { s.workEnd = v }
        if let v = weekdays { s.workingWeekdays = v }
        return s
    }

    /// The fields that differ from what is kept.
    func changes(from s: RoutineReport.Settings, sellsPower kept: Bool) -> [Field] {
        let m = merged(s)
        return Field.allCases.filter { f in
            switch f {
            case .contractName: m.contractName != s.contractName
            case .contractor: m.contractor != s.contractor
            case .employer: m.employer != s.employer
            case .workTime: m.workStart != s.workStart || m.workEnd != s.workEnd
            case .inspector: m.inspector != s.inspector
            case .weekdays: m.workingWeekdays != s.workingWeekdays
            case .sellsPower: (sellsPower ?? kept) != kept
            }
        }
    }
}

/// The tab's sheets.
enum PadSettingsSheet: Identifiable {
    case text(SettingsDraft.Field)
    case workTime
    case person(String, PadPersonRole)
    case access
    case routine
    case station
    case history(String)
    case upload(String?)

    var id: String {
        switch self {
        case .text(let f): "text." + f.rawValue
        case .workTime: "workTime"
        case .person(let e, let r): "person.\(r.rawValue).\(e)"
        case .access: "access"
        case .routine: "routine"
        case .station: "station"
        case .history(let d): "history." + d
        case .upload(let d): "upload." + (d ?? "new")
        }
    }
}

/// Where a person sits on the job (`JobAccessCard`'s parts), and who may take them off it.
enum PadPersonRole: String {
    case supervisor, team, external

    var section: String {
        switch self {
        case .supervisor: "วิศวกรผู้ควบคุมงาน"
        case .team: "ทีมงานของเรา"
        case .external: "ผู้รับเหมา"
        }
    }

    var chip: String {
        switch self {
        case .supervisor: "ผู้ควบคุมงาน"
        case .team: "ทีมงาน"
        case .external: "ภายนอก"
        }
    }

    var tone: InstallPageData.Tone { self == .external ? .warn : .info }

    /// The capability `JobAccessCard` checks for this part (the supervisor sits in its external part).
    var capability: Capability { self == .team ? .assignTeam : .assignExternal }
}

/// `-installDemo YES`: the board's station in memory, so nothing is saved (empty in release builds).
struct PadSettingsDemo {
    var settings = RoutineReport.Settings()
    var sellsPower = false
    var branch = ""
    var supervisor: String?
    var team: [String] = []
    var externals: [String] = []
    var names: [String: String] = [:]
    var drawings: [StationDrawing] = []

    static var initial: PadSettingsDemo {
        #if DEBUG
        if InstallTrackingPage.Debug.demo { return board() }
        #endif
        return PadSettingsDemo()
    }
}

extension InstallTrackingPage {
    // MARK: data (the job's, or the demo's)

    var padDemoOn: Bool { Debug.demo }

    var settingsKept: RoutineReport.Settings { padDemoOn ? padDemo.settings : job.routineSettings }
    var sellsPowerKept: Bool { padDemoOn ? padDemo.sellsPower : job.stationDocs.sellsPower }
    var settingsShown: RoutineReport.Settings { settingsDraft.merged(settingsKept) }
    var sellsPowerShown: Bool { settingsDraft.sellsPower ?? sellsPowerKept }
    var settingsChanges: [SettingsDraft.Field] { settingsDraft.changes(from: settingsKept, sellsPower: sellsPowerKept) }

    var padSupervisor: String? {
        let s = ((padDemoOn ? padDemo.supervisor : job.supervisorEmail) ?? "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }
    var padTeam: [String] { padDemoOn ? padDemo.team : job.teamMembers }
    var padExternals: [String] { padDemoOn ? padDemo.externals : job.externals }
    var padPeopleCount: Int { Set(padTeam + padExternals + [padSupervisor].compactMap { $0 }).count }

    func personName(_ email: String) -> String {
        if padDemoOn, let n = padDemo.names[email] { return n }
        return TeamDirectory.shared.person(email)?.name ?? ""
    }

    /// Header and routine rows: the job's routine settings, which only the team writes (firestore.rules).
    var editsRoutine: Bool { permissions.can(.jobEdit, on: job.access) }
    /// The station's facts and its drawings, as the iPhone's `แก้ข้อมูลสถานี` (`stationdocs.drafts`).
    var editsStation: Bool { permissions.can(.stationDocsDrafts, on: job.access) }

    func trailing(_ c: PadSettingsCategory) -> String {
        switch c {
        case .team: "\(padPeopleCount) คน"
        case .drawings: padDrawings.isEmpty ? "" : "\(padDrawings.count) แบบ"
        case .routine: Self.weekdaysSummary(settingsShown.workingWeekdays)
        case .connection: sellsPowerShown ? "ขนานไฟ" : "Zero Export"
        case .header, .reference: ""
        }
    }

    // MARK: layout

    func padSettingsTab(_ data: InstallPageData) -> some View {
        let frame = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return HStack(alignment: .top, spacing: 18) {
            ScrollView { padSettingsLeft(data).padding(.vertical, 2) }
                .scrollIndicators(.hidden)
                .frame(width: 330)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    padHeadCard
                    // Keep the selected category's large editor tree out of this tab's concrete view type.
                    AnyView(padCategoryBody(data))
                }
                .padding(.vertical, 2)
                .padding(.bottom, settingsChanges.isEmpty ? 0 : 96)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.groupedPage, in: frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
        .overlay(alignment: .bottom) { if !settingsChanges.isEmpty { unsavedBar.padding(.bottom, 14) } }
        // the panel ends above the dock
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 16)
        .animation(.snappy, value: settingsChanges.isEmpty)
        .sheet(item: $padSheet) { padSheetView($0) }
        #if DEBUG
        .task { applySettingsState() }
        #endif
    }

    private func padSettingsLeft(_ data: InstallPageData) -> some View {
        VStack(spacing: 16) {
            padStationCard(data)
            padCategoryList
        }
    }

    func syncChip(_ dirty: Bool) -> some View {
        Label(dirty ? "ยังไม่บันทึก" : "ซิงก์แล้ว", systemImage: dirty ? "pencil" : "checkmark")
            .labelStyle(.titleAndIcon)
            .font(.sarabunFixed(13, .bold))
            .foregroundStyle(dirty ? Theme.warningInk : Theme.successInk)
            .padding(.horizontal, 9).frame(height: 26)
            .background(dirty ? Theme.warningSoft : Theme.successSoft, in: Capsule())
            .fixedSize()
            .accessibilityIdentifier("settings.syncChip")
    }

    private func padStationCard(_ data: InstallPageData) -> some View {
        let name = padDemoOn ? data.title : job.stationName
        return phoneCard(padding: 14) {
            HStack(spacing: 12) {
                Text(String(name.prefix(2))).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 48, height: 48).background(Theme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).lineLimit(2).minimumScaleFactor(0.85)
                    Text("ตั้งค่าเฉพาะโครงการนี้").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                syncChip(!settingsChanges.isEmpty)
            }
        }
    }

    func padIconTile(_ symbol: String, _ tint: Color, size: CGFloat = 40) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Image(systemName: symbol).font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.08), in: shape)
            .overlay(shape.strokeBorder(tint.opacity(0.35)))
            .accessibilityHidden(true)
    }

    private var padCategoryList: some View {
        let touched = Set(settingsChanges.map(\.category))
        return padListCard {
            ForEach(Array(PadSettingsCategory.allCases.enumerated()), id: \.element) { i, c in
                Button { padCategory = c } label: { padCategoryRow(c, on: c == padCategory, dirty: touched.contains(c)) }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) } }
                    .accessibilityAddTraits(c == padCategory ? .isSelected : [])
                    .accessibilityIdentifier("padSettings.\(c.rawValue)")
            }
        }
    }

    private func padCategoryRow(_ c: PadSettingsCategory, on: Bool, dirty: Bool) -> some View {
        HStack(spacing: 12) {
            padIconTile(c.symbol, c.tint, size: 34)
            Text(c.title).font(.sarabunFixed(16, on ? .bold : .regular)).foregroundStyle(Theme.navy).lineLimit(1).fixedSize()
                .layoutPriority(1)
            Spacer(minLength: 4)
            let t = trailing(c)
            if !t.isEmpty { Text(t).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary).lineLimit(1).minimumScaleFactor(0.75) }
            if dirty { Circle().fill(Theme.warning).frame(width: 8, height: 8).accessibilityLabel("ยังไม่บันทึก") }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chevron)
        }
        .padding(.horizontal, 16).frame(minHeight: 60)
        .background(on ? Theme.primarySoft : .clear)
        .overlay(alignment: .leading) { if on { Rectangle().fill(Theme.primary).frame(width: 3) } }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var padHeadCard: some View {
        let c = padCategory
        return phoneCard(padding: 14) {
            HStack(spacing: 14) {
                padIconTile(c.symbol, c.tint, size: 46)
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.title).font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Text(c.note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 4)
                syncChip(!settingsChanges.isEmpty)
            }
        }
    }

    @ViewBuilder private func padCategoryBody(_ data: InstallPageData) -> some View {
        switch padCategory {
        case .team: padTeamPage
        case .header: padHeaderPage
        case .drawings: padDrawingsPage
        case .routine: padRoutinePage
        case .connection: padConnectionPage
        case .reference: padReferencePage(data)
        }
    }

    // MARK: rows

    func padListCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(spacing: 0) { content() }
            .background(Theme.surface, in: frame)
            .clipShape(frame)
            .overlay(frame.strokeBorder(Theme.borderSubtle))
            .cardShadow()
    }

    /// An inset grouped list: its title inside the card, the footer under it.
    func padSection<C: View>(_ title: String?, footer: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            padListCard {
                if let title {
                    Text(title).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).padding(.horizontal, 20)
                }
                content()
            }
            if let footer { Text(footer).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).padding(.leading, 4) }
        }
    }

    private func rowLabel(_ title: String, _ hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.sarabunFixed(17)).foregroundStyle(Theme.navy)
            if let hint { Text(hint).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func rowDivider(_ first: Bool) -> some View {
        Rectangle().fill(first ? .clear : Theme.hairline).frame(height: 1)
    }

    /// Label and hint left, the value right in primary bold; a chevron when it opens something, a lock when read only.
    func padValueRow(_ title: String, hint: String? = nil, value: String, first: Bool = false, locked: Bool = false,
                     id: String? = nil, action: (() -> Void)? = nil) -> some View {
        let content = HStack(spacing: 10) {
            rowLabel(title, hint)
            HStack(spacing: 6) {
                if locked { Image(systemName: "lock").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted) }
                Text(value.isEmpty ? "–" : value).font(.sarabunFixed(17, .bold))
                    .foregroundStyle(value.isEmpty ? Theme.inkFaint : Theme.navy).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if action != nil {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chevron)
            }
        }
        .padding(.horizontal, 20).frame(minHeight: 62)
        .contentShape(Rectangle())
        return VStack(spacing: 0) {
            rowDivider(first)
            if let action {
                Button(action: action) { content }.buttonStyle(.plain).accessibilityIdentifier(id ?? title)
            } else {
                content.accessibilityElement(children: .combine)
            }
        }
    }

    /// Label and hint left, 2–3 outlined segments right; a role that can't save it sees the value only.
    func padPickerRow(_ title: String, hint: String? = nil, options: [String], selected: Int?, first: Bool = false,
                      editable: Bool, pick: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 0) {
            rowDivider(first)
            HStack(spacing: 10) {
                rowLabel(title, hint)
                HStack(spacing: 12) {
                    if editable {
                        ForEach(Array(options.enumerated()), id: \.offset) { i, o in segment(o, on: i == selected) { pick(i) } }
                    } else {
                        Text(selected.map { options[$0] } ?? "–").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20).frame(minHeight: 66)
        }
    }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button(action: action) {
            Text(title).font(.sarabunFixed(17, on ? .bold : .regular)).foregroundStyle(on ? Theme.navy : Theme.inkStrong)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 16).frame(minWidth: 96, minHeight: 46)
                .background(on ? Theme.optionSelected : Theme.surface, in: shape)
                .overlay(shape.strokeBorder(on ? Theme.primary : Theme.borderControl, lineWidth: on ? 2 : 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Avatar initial, name, email, role chip; tapped, the person sheet.
    func padPersonRow(_ email: String, role: PadPersonRole, first: Bool) -> some View {
        let name = personName(email)
        return VStack(spacing: 0) {
            rowDivider(first)
            Button { padSheet = .person(email, role) } label: {
                HStack(spacing: 14) {
                    Text(Self.avatarLetters(name.isEmpty ? email : name, count: 1)).font(.sarabunFixed(18, .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(width: 44, height: 44).background(Self.ink(role.tone), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name.isEmpty ? email : name).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                        if !name.isEmpty { Text(email).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    toneChip(role.chip, role.tone)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chevron)
                }
                .padding(.horizontal, 20).frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("padSettings.person.\(email)")
        }
    }

    /// The avatar's letters: the name's first `count` words without a title (นาย, น.ส. …), as `UserAdminStyle.initials`.
    static func avatarLetters(_ name: String, count: Int) -> String {
        var n = name.trimmingCharacters(in: .whitespaces)
        for title in ["นางสาว", "น.ส.", "นาง", "นาย", "ดร.", "คุณ"] where n.hasPrefix(title) {
            n = String(n.dropFirst(title.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        let letters = UserAdminStyle.initials(n.isEmpty ? name : n)
        return String(letters.prefix(count))
    }

    /// An outlined `+ …` button.
    func padActionRow(_ title: String, first: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            rowDivider(first)
            HStack {
                Button(action: action) { Label(title, systemImage: "plus").font(.sarabunFixed(16, .bold)) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    func padNoteRow(_ text: String, first: Bool) -> some View {
        VStack(spacing: 0) {
            rowDivider(first)
            Text(text).font(.sarabunFixed(16)).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).padding(.horizontal, 20)
        }
    }

    // MARK: ทีมและสิทธิ์

    private var padTeamPage: some View {
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

    private var padHeaderPage: some View {
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

    private var padRoutinePage: some View {
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

    private var padConnectionPage: some View {
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

    private func padReferencePage(_ data: InstallPageData) -> some View {
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

    private var unsavedBar: some View {
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
