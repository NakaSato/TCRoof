import SwiftUI
import TCRoofCore
import SurveyUI

/// One entry of the bell panel. `id` stays the same while the event does, so "read" survives relaunches.
struct AppNotification: Identifiable {
    enum Kind { case survey, install, syncPending, saved }
    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let date: Date
    /// "อีก 9 ชม." for an appointment still ahead; otherwise the time (today) or date and time (earlier).
    var timeText: String {
        if kind == .survey, date > .now {
            let mins = Int(date.timeIntervalSinceNow / 60)
            return mins >= 60 ? "อีก \(mins / 60) ชม." : "อีก \(max(mins, 1)) นาที"
        }
        return date.isToday ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            : ThaiFormat.dayMonthTime.string(from: date)
    }
    var isToday: Bool { date.isToday || kind == .survey || kind == .install || kind == .syncPending }

    var symbol: String {
        switch kind {
        case .survey: "list.clipboard"
        case .install: "calendar"
        case .syncPending: "icloud.and.arrow.up"
        case .saved: "checkmark.circle"
        }
    }
    var tint: Color {
        switch kind {
        case .survey: Theme.primary
        case .install: Theme.navy
        case .syncPending: Theme.pending
        case .saved: Theme.paperTickStrong
        }
    }
    var tintBackground: Color {
        switch kind {
        case .survey, .install: Theme.primarySoft
        case .syncPending: Theme.pendingSoft
        case .saved: Theme.paperBand
        }
    }

    /// Today's survey appointments and install days, survey reports still waiting to sync,
    /// and Drive saves of the last 7 days.
    @MainActor static func list(jobs: [Job], survey: SurveyModel) -> [AppNotification] {
        let day = ISODate.string(.now)
        var out: [AppNotification] = []
        for job in jobs {
            let key = job.syncID ?? job.code
            if job.surveyDate.isToday {
                out.append(.init(id: "survey-\(key)-\(day)", kind: .survey,
                                 title: "นัดสำรวจ " + job.surveyDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)),
                                 detail: [job.code, job.projectName, job.address].filter { !$0.isEmpty }.joined(separator: " · "),
                                 date: job.surveyDate))
            }
            if let d = job.installDay(on: .now) {
                out.append(.init(id: "install-\(key)-\(day)", kind: .install, title: "ติดตั้ง Day \(d)/\(job.installDays)",
                                 detail: "\(job.code) · ทีม \(job.team.rawValue) · \(job.capacityKW.plain) kWp · จ.\(job.province)",
                                 date: Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: job.installStart),
                                                             minute: Calendar.current.component(.minute, from: job.installStart), second: 0, of: .now) ?? .now))
            }
        }
        let pending = survey.jobsToSync
        if let latest = pending.map(\.updated).max() {
            // a new id whenever the count changes, so a fresh backlog shows as unread again
            out.append(.init(id: "sync-\(day)-\(pending.count)", kind: .syncPending, title: "รอซิงก์ \(pending.count) งาน",
                             detail: "ยังไม่ได้บันทึกขึ้นคลาวด์ · แตะเพื่อซิงก์ตอนมีสัญญาณ", date: latest))
        }
        let weekAgo = Date.now.adding(days: -7)
        for j in survey.jobs {
            guard let saved = j.drive?.lastSaved, saved > weekAgo else { continue }
            let name = [j.docNo.isEmpty ? "" : "NO.\(j.docNo)", j.projectName].filter { !$0.isEmpty }.joined(separator: " ")
            out.append(.init(id: "saved-\(j.id.uuidString)-\(saved.millis)", kind: .saved, title: "บันทึกขึ้น Drive แล้ว",
                             detail: "\(name.isEmpty ? "งานสำรวจ" : name) · \(j.photoCount) ภาพ", date: saved))
        }
        return out.sorted { a, b in a.isToday != b.isToday ? a.isToday : a.date > b.date }
    }
}

/// The bell's panel: unread count, "mark all read", today / earlier groups, link to the full list.
struct NotificationPanel: View {
    let items: [AppNotification]
    let read: Set<String>
    let markRead: ([AppNotification]) -> Void
    let sync: () -> Void
    let close: () -> Void
    let showAll: () -> Void

    var body: some View {
        let unread = items.filter { !read.contains($0.id) }.count
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("การแจ้งเตือน").font(.sarabun(18, .bold)).foregroundStyle(Theme.navy)
                Text(unread > 0 ? "ยังไม่อ่าน \(unread)" : "อ่านครบแล้ว").font(.sarabun(12, .bold, relativeTo: .caption))
                    .foregroundStyle(unread > 0 ? Theme.primary : Theme.paperTickStrong)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(unread > 0 ? Theme.primarySoft : Theme.paperBand, in: Capsule())
                Spacer()
                if unread > 0 {
                    Button("อ่านทั้งหมด") { markRead(items) }.font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.primary)
                        .frame(minHeight: 44)
                }
                Button(action: close) {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(Theme.navy)
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))
                }
                .accessibilityLabel("ปิด")
            }
            .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 56)
            Rectangle().fill(Theme.borderControl).frame(height: 1)
            ScrollView { NotificationList(items: items, read: read, markRead: markRead, sync: sync) }
                .frame(maxHeight: 460)
            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
            Button(action: showAll) {
                Text("ดูการแจ้งเตือนทั้งหมด").font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        .background(Theme.surface)
        .font(.sarabun(17))
    }
}

/// Rows grouped "วันนี้ · d/M/พ.ศ." and "ก่อนหน้า"; tapping a row marks it read (the sync row also sends now).
struct NotificationList: View {
    let items: [AppNotification]
    let read: Set<String>
    let markRead: ([AppNotification]) -> Void
    let sync: () -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            let today = items.filter(\.isToday), earlier = items.filter { !$0.isToday }
            if items.isEmpty {
                Text("ไม่มีการแจ้งเตือน").foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity).padding(24)
            }
            if !today.isEmpty { group("วันนี้ · " + ThaiFormat.numericDate.string(from: .now), today) }
            if !earlier.isEmpty { group("ก่อนหน้า", earlier) }
        }
    }

    func group(_ title: String, _ list: [AppNotification]) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.sarabun(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.background)
                .accessibilityAddTraits(.isHeader)
            ForEach(list) { n in
                Button {
                    markRead([n])
                    if n.kind == .syncPending { sync() }
                } label: { row(n, unread: !read.contains(n.id)) }
                .buttonStyle(.plain)
            }
        }
    }

    func row(_ n: AppNotification, unread: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: n.symbol).font(.body.weight(.semibold)).foregroundStyle(n.tint)
                .frame(width: 40, height: 40).background(n.tintBackground, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(n.title).font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                    Spacer(minLength: 8)
                    Text(n.timeText).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).monospacedDigit()
                }
                Text(n.detail).font(.sarabun(14)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            if unread { Circle().fill(Theme.primary).frame(width: 10, height: 10).padding(.top, 6).accessibilityLabel("ยังไม่อ่าน") }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(unread ? Theme.unreadRow : Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Every notification, full screen ("ดูการแจ้งเตือนทั้งหมด").
struct NotificationsView: View {
    let items: [AppNotification]
    let read: Set<String>
    let markRead: ([AppNotification]) -> Void
    let sync: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView { NotificationList(items: items, read: read, markRead: markRead, sync: sync) }
                .background(Theme.surface)
                .font(.sarabun(17))
                .navigationTitle("การแจ้งเตือน")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("อ่านทั้งหมด") { markRead(items) } }
                    ToolbarItem(placement: .confirmationAction) { Button("ปิด") { dismiss() } }
                }
        }
    }
}
