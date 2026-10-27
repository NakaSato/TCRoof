import SwiftUI
import TCRoofUI
import TCRoofCore

/// `ตั้งค่าเฉพาะโครงการ` (docs/ui/install-tracking-iphone §4.9), the header gear on iPhone: grouped lists of what this
/// station keeps, each row leading to the editor that already exists (`JobAccessCard`, `RoutineSettingsSheet`,
/// `StationFactsSheet`, the IEC set-up), with the same permissions as those editors. The board's `หัวเอกสาร`,
/// `แบบก่อสร้าง`, `ผู้ติดต่อหน้างาน` and `ขั้นสูง` rows have no stored source and are left out.
extension InstallTrackingPage {
    enum SettingsCategory: String, CaseIterable { case team, routine, connection, reference }

    enum PhoneSheet: String, Identifiable {
        case routine, station
        var id: String { rawValue }
    }

    private struct SettingsRow {
        let category: SettingsCategory
        let title: String
        let note: String
        let symbol: String
        let tint: Color
        let trailing: String
    }

    private var editsAccess: Bool { permissions.can(.assignTeam, on: job.access) || permissions.can(.assignExternal, on: job.access) }

    private var people: Int { Set(job.teamMembers + job.externals + [job.supervisorEmail].compactMap { $0 }.filter { !$0.isEmpty }).count }

    /// `จ – ส`: the site's working weekdays, as a range when they run on.
    private var weekdaysSummary: String { Self.weekdaysSummary(job.routineSettings.workingWeekdays) }

    /// `จ – ส`: `Calendar` weekdays (1 = Sunday) as a range when they run on, else listed (the iPad tab shares it).
    static func weekdaysSummary(_ set: Set<Int>) -> String {
        let names = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]
        let days = set.sorted()
        guard let first = days.first, let last = days.last else { return "–" }
        if days.count > 2, last - first + 1 == days.count { return names[first - 1] + " – " + names[last - 1] }
        return days.map { names[$0 - 1] }.joined(separator: " ")
    }

    private func row(_ c: SettingsCategory) -> SettingsRow {
        switch c {
        case .team: .init(category: c, title: "ทีมและสิทธิ์", note: "ใครทำงานนี้ | ใครลงนาม | ผู้รับเหมาที่เห็นงานนี้", symbol: "person.2",
                          tint: Theme.aiPurple, trailing: "\(people) คน")
        case .routine: .init(category: c, title: "รอบรายงาน", note: "วันทำงานและผู้ลงนามรายงานประจำ", symbol: "calendar",
                             tint: Theme.primary, trailing: weekdaysSummary)
        case .connection: .init(category: c, title: "การเชื่อมต่อและ IEC", note: "ชุดเอกสาร กปภ. / กกพ. และการทดสอบ IEC", symbol: "bolt",
                                tint: Theme.warning, trailing: job.stationContext.over200kVA ? "≥ 200 kVA" : "< 200 kVA")
        case .reference: .init(category: c, title: "ข้อมูลอ้างอิง", note: "แก้ที่ต้นทาง | หน้านี้แสดงอย่างเดียว", symbol: "doc.plaintext",
                               tint: Theme.navy, trailing: "")
        }
    }

    func settingsPage(_ data: InstallPageData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let c = settingsCategory {
                Button { withAnimation(.snappy) { settingsCategory = nil } } label: {
                    Label("หมวดทั้งหมด", systemImage: "chevron.left").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.primary)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.back")
                categoryHead(row(c))
                switch c {
                case .team: teamPage
                case .routine: routinePage
                case .connection: connectionPage
                case .reference: referencePage(data)
                }
            } else {
                stationCard(data)
                group("โครงการ", editsAccess ? [.team] : [])
                group("การทำงาน", [.routine, .connection])
                group(nil, [.reference])
            }
        }
    }

    private func stationCard(_ data: InstallPageData) -> some View {
        phoneCard {
            HStack(spacing: 14) {
                Text(String(job.stationName.prefix(2))).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 48, height: 48).background(Theme.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(data.title).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text("ตั้งค่าเฉพาะโครงการนี้").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private func group(_ title: String?, _ cats: [SettingsCategory]) -> some View {
        if !cats.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let title { Text(title).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.inkMuted).padding(.leading, 4) }
                listCard {
                    ForEach(Array(cats.enumerated()), id: \.offset) { i, c in
                        let r = row(c)
                        Button { withAnimation(.snappy) { settingsCategory = c } } label: { settingsRow(r) }
                            .buttonStyle(.plain)
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 66) } }
                            .accessibilityIdentifier("settings.\(c.rawValue)")
                    }
                }
            }
        }
    }

    private func listCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
            .cardShadow()
    }

    private func iconTile(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.onPrimary)
            .frame(width: 40, height: 40).background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }

    private func settingsRow(_ r: SettingsRow) -> some View {
        HStack(spacing: 12) {
            iconTile(r.symbol, r.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(r.title).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Text(r.note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !r.trailing.isEmpty { Text(r.trailing).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.inkMuted).lineLimit(1).fixedSize() }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chevron)
        }
        .padding(.horizontal, 14).frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func categoryHead(_ r: SettingsRow) -> some View {
        phoneCard {
            HStack(spacing: 14) {
                iconTile(r.symbol, r.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(r.title).font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Text(r.note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func section<C: View>(_ title: String, footer: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.inkMuted).padding(.leading, 4)
            listCard(content)
            if let footer { Text(footer).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).padding(.leading, 4) }
        }
    }

    private func valueRow(_ title: String, _ value: String, first: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.sarabunFixed(16)).foregroundStyle(Theme.navy)
            Spacer(minLength: 8)
            Text(value.isEmpty ? "–" : value).font(.sarabunFixed(16, .bold)).foregroundStyle(value.isEmpty ? Theme.inkFaint : Theme.inkMuted)
                .multilineTextAlignment(.trailing).lineLimit(2)
        }
        .padding(.horizontal, 14).frame(minHeight: 52)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 14) } }
        .accessibilityElement(children: .combine)
    }

    private func actionRow(_ title: String, first: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chevron)
            }
            .padding(.horizontal, 14).frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 14) } }
    }

    // MARK: categories

    private func personRow(_ email: String, role: String, tone: InstallPageData.Tone, first: Bool) -> some View {
        let name = TeamDirectory.shared.person(email)?.name ?? ""
        return HStack(spacing: 12) {
            Text(String((name.isEmpty ? email : name).prefix(1)).uppercased()).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.onPrimary)
                .frame(width: 40, height: 40).background(Self.ink(tone), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(name.isEmpty ? email : name).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                if !name.isEmpty { Text(email).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
            }
            Spacer(minLength: 4)
            toneChip(role, tone)
        }
        .padding(.horizontal, 14).frame(minHeight: 60)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 66) } }
        .accessibilityElement(children: .combine)
    }

    private var teamPage: some View {
        let supervisor = (job.supervisorEmail ?? "").trimmingCharacters(in: .whitespaces)
        let team = permissions.can(.assignTeam, on: job.access), externals = permissions.can(.assignExternal, on: job.access)
        return VStack(alignment: .leading, spacing: 14) {
            section("วิศวกรผู้ควบคุมงาน", footer: "ลงนามรายงานประจำวันและปิดการทดสอบ IEC") {
                if supervisor.isEmpty { valueRow("ยังไม่ระบุ", "", first: true) } else { personRow(supervisor, role: "ผู้ควบคุมงาน", tone: .info, first: true) }
                if externals { actionRow("+ เปลี่ยนวิศวกรผู้ควบคุมงาน") { phoneRoute = .access } }
            }
            section("ทีมงานของเรา", footer: "งานนี้อยู่ใน งานของฉัน ของคนเหล่านี้") {
                if job.teamMembers.isEmpty { valueRow("ยังไม่ระบุ (ทุกคนในทีม)", "", first: true) }
                ForEach(Array(job.teamMembers.enumerated()), id: \.offset) { i, e in personRow(e, role: "ทีมงาน", tone: .info, first: i == 0) }
                if team { actionRow("+ เพิ่มคนจากรายชื่อทีม") { phoneRoute = .access } }
            }
            section("ผู้รับเหมา", footer: "เห็นเฉพาะงานนี้ | ส่งคำขอและผล IEC") {
                if job.externals.isEmpty { valueRow("ยังไม่มีผู้รับเหมา", "", first: true) }
                ForEach(Array(job.externals.enumerated()), id: \.offset) { i, e in personRow(e, role: "ภายนอก", tone: .warn, first: i == 0) }
                if externals { actionRow("+ เพิ่มผู้รับเหมา") { phoneRoute = .access } }
            }
        }
    }

    private var routinePage: some View {
        let s = job.routineSettings
        func clock(_ m: Int) -> String { String(format: "%02d.%02d", m / 60, m % 60) }
        return VStack(alignment: .leading, spacing: 14) {
            section("รอบรายงาน", footer: "รายงานประจำวันส่งก่อนเลิกงาน | คำขอรายสัปดาห์ส่งก่อนเริ่มสัปดาห์ | " + RoutineSettingsSheet.publicHolidaysNote) {
                valueRow("วันทำงาน", weekdaysSummary, first: true)
                valueRow("เวลาทำงาน", clock(s.workStart) + " – " + clock(s.workEnd))
                valueRow("วันหยุดเพิ่ม", s.holidays.isEmpty ? "ไม่มี" : "\(s.holidays.count) วัน")
            }
            section("ผู้ลงนาม") {
                valueRow("วิศวกรหน้างาน", s.siteEngineer, first: true)
                valueRow("ผู้ตรวจ (กปภ.)", s.inspector)
                valueRow("ผู้รับเหมาช่วง", s.subcontractor)
            }
            listCard { actionRow("แก้ไขรอบรายงานและข้อมูลสถานี", first: true) { phoneSheet = .routine } }
        }
    }

    private var connectionPage: some View {
        let ctx = job.stationContext, station = job.stationDocs
        let canEdit = permissions.can(.stationDocsDrafts, on: job.access)
        return VStack(alignment: .leading, spacing: 14) {
            section("ชุดเอกสาร", footer: "ขนาดสถานีกำหนดว่าต้องยื่น พค.2 (กกพ.) หรือไม่") {
                valueRow("พค.2", ctx.over200kVA ? "ต้องยื่น (200 kVA ขึ้นไป)" : "ไม่ต้องยื่น", first: true)
                valueRow("เทศบาลให้", station.buildingRoute.title)
                valueRow("คำขอ พค.2", station.requestType.title)
                valueRow("ชุดที่ยื่น", StationDocs.packages(ctx).map(\.title).joined(separator: ", "))
            }
            if canEdit { listCard { actionRow("แก้ข้อมูลสถานี", first: true) { phoneSheet = .station } } }
            section("การทดสอบ IEC 62446") {
                valueRow("อินเวอร์เตอร์", job.iecReport.map { "\($0.inverters.count) เครื่อง | \($0.stringCount) สตริง" } ?? "ยังไม่ได้ตั้งค่า", first: true)
                actionRow("ตั้งค่าการทดสอบ IEC") { route = .iec }
            }
        }
    }

    private func referencePage(_ data: InstallPageData) -> some View {
        section("ข้อมูลสถานี", footer: "แก้ที่หน้ารายละเอียดงาน") {
            valueRow("สถานี", data.title, first: true)
            valueRow("เลขที่ MP", job.mpNumber.map { "MP \($0)" } ?? "")
            valueRow("ขนาด", job.capacityKW > 0 ? job.capacityKW.formatted(.number.precision(.fractionLength(0...2))) + " kWp" : "")
            valueRow("ทีม", job.team.rawValue)
            valueRow("ช่วงติดตั้ง", ThaiFormat.numericDate.string(from: job.installStart) + " – " + ThaiFormat.numericDate.string(from: job.installEnd))
            valueRow("สาขา กปภ.", job.stationDocs.branch)
            actionRow("รายละเอียดงาน") { route = .detail }
        }
    }
}
