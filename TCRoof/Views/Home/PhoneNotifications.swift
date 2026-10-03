import SwiftUI

/// Notifications: full screen on iPhone, the bell's popover on iPad (`large`). Filter chips, today / yesterday / earlier
/// groups, compact rows. Rows have no buttons; tapping one does its action and marks it read.
struct PhoneNotificationsView: View {
    let items: [AppNotification]
    let read: Set<String>
    let markRead: ([AppNotification]) -> Void
    let sync: () -> Void
    /// "แตะเพื่อทำต่อ D1 ถังน้ำใส" for an appointment row; nil when it has no report step to name.
    let surveyHint: (AppNotification) -> String
    /// Opens the appointment's report (after the cover closes).
    let openSurvey: (AppNotification) -> Void
    /// iPad popover: 440 wide, at most 640 high, 21 pt title.
    var large = false

    @Environment(\.dismiss) private var dismiss
    @State private var todoOnly = false
    /// Set when the sync row is tapped; once nothing waits, the row shows as "ซิงก์ครบแล้ว".
    @State private var syncedAt: Date?
    @State private var listHeight: CGFloat = 0
    @State private var topHeight: CGFloat = 0

    private func isTodo(_ n: AppNotification) -> Bool {
        switch n.kind {
        case .survey: n.date > .now && n.job != nil
        case .syncPending: true
        case .install, .saved: false
        }
    }

    var body: some View {
        let unread = items.filter { !read.contains($0.id) }.count
        let todo = items.filter(isTodo).count
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header(unread: unread)
                filters(todo: todo)
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
            ScrollView { list.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 } }
                // the popover hugs its rows up to 640 pt
                .frame(height: large ? max(min(listHeight, 640 - topHeight), 120) : nil)
        }
        .frame(width: large ? 440 : nil)
        .background(Theme.surface)
        .font(.sarabun(17))
    }

    private func header(unread: Int) -> some View {
        HStack(spacing: 6) {
            Text("การแจ้งเตือน").font(.sarabun(large ? 21 : 24, .bold, relativeTo: .title)).foregroundStyle(Theme.navy).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Text(unread > 0 ? "ใหม่ \(unread)" : "อ่านครบแล้ว").font(.sarabun(12.5, .bold, relativeTo: .caption))
                .foregroundStyle(unread > 0 ? Theme.primary : Theme.successInk)
                .padding(.horizontal, 10).padding(.vertical, 2)
                .background(unread > 0 ? Theme.primarySoft : Theme.paperBand, in: Capsule())
                .fixedSize()
            Spacer(minLength: 4)
            if unread > 0 {
                Button("อ่านทั้งหมด") { markRead(items) }
                    .font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.primary)
                    .padding(.horizontal, 6).frame(minHeight: 44)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.navy)
                    .frame(width: 44, height: 44).background(Theme.hairline, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปิด")
        }
        .padding(.leading, large ? 20 : 16).padding(.trailing, 6).padding(.top, large ? 10 : 4).padding(.bottom, 6)
    }

    private func filters(todo: Int) -> some View {
        HStack(spacing: 8) {
            chip("ทั้งหมด", count: nil, on: !todoOnly) { todoOnly = false }
            chip("ต้องทำ", count: todo, on: todoOnly) { todoOnly = true }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    private func chip(_ title: String, count: Int?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.sarabun(13.5, .bold, relativeTo: .footnote))
                if let count {
                    Text("\(count)").font(.sarabun(12, .bold, relativeTo: .caption)).monospacedDigit()
                        .foregroundStyle(on ? .white : Theme.pending)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(on ? Color.white.opacity(0.2) : Theme.warningSoft, in: Circle())
                }
            }
            .foregroundStyle(on ? .white : Theme.navy)
            .padding(.horizontal, 14).frame(minHeight: 36)
            .background(on ? Theme.navy : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(on ? .clear : Theme.borderSubtle))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: list

    @ViewBuilder private var list: some View {
        let shown = todoOnly ? items.filter(isTodo) : items
        let today = shown.filter(\.isToday)
        let yesterday = shown.filter { !$0.isToday && Calendar.current.isDateInYesterday($0.date) }
        let earlier = shown.filter { !$0.isToday && !Calendar.current.isDateInYesterday($0.date) }
        let showSynced = syncedAt != nil && !items.contains { $0.kind == .syncPending }
        LazyVStack(spacing: 0) {
            if shown.isEmpty && !showSynced {
                Text(todoOnly ? "ไม่มีงานที่ต้องทำ" : "ไม่มีการแจ้งเตือน").foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity).padding(24)
            }
            if !today.isEmpty || showSynced {
                groupHeader("วันนี้")
                ForEach(today) { row($0) }
                if showSynced, let at = syncedAt { syncedRow(at) }
            }
            if !yesterday.isEmpty {
                groupHeader("เมื่อวาน · " + ThaiFormat.dayMonth.string(from: .now.adding(days: -1)))
                ForEach(yesterday) { row($0) }
            }
            if !earlier.isEmpty {
                groupHeader("ก่อนหน้า")
                ForEach(earlier) { row($0) }
            }
        }
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title).font(.sarabun(11.5, .bold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Theme.phonePage)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ n: AppNotification) -> some View {
        let unread = !read.contains(n.id)
        let hint = hint(n)
        return Button {
            markRead([n])
            switch n.kind {
            case .syncPending: syncedAt = .now; sync()
            case .survey where n.job != nil: dismiss(); openSurvey(n)
            default: break
            }
        } label: {
            NotificationRowLabel(title: n.title, detail: phoneDetail(n), time: n.timeText, symbol: symbol(n), tile: tile(n),
                                 hint: hint?.text, hintColor: hint?.color ?? Theme.primary, unread: unread, actionable: hint != nil)
        }
        .buttonStyle(.plain)
    }

    private func syncedRow(_ at: Date) -> some View {
        NotificationRowLabel(title: "ซิงก์ครบแล้ว", detail: "บันทึกขึ้นคลาวด์แล้ว", time: ThaiFormat.time.string(from: at),
                             symbol: "checkmark", tile: Theme.success, hint: nil, hintColor: .clear, unread: false, actionable: false)
    }

    private func hint(_ n: AppNotification) -> (text: String, color: Color)? {
        switch n.kind {
        case .survey where n.job != nil: (surveyHint(n), Theme.primary)
        case .syncPending: ("แตะเพื่อซิงก์ตอนนี้", Theme.pending)
        default: nil
        }
    }

    /// The shared list's detail without its own "tap to sync" note, which the hint line replaces here.
    private func phoneDetail(_ n: AppNotification) -> String {
        n.kind == .syncPending ? "เก็บไว้ในเครื่องแล้ว · ยังไม่ขึ้นคลาวด์" : n.detail
    }

    private func symbol(_ n: AppNotification) -> String {
        switch n.kind {
        case .survey: "calendar"
        case .install: "folder"
        case .syncPending: "icloud.and.arrow.up"
        case .saved: "checkmark"
        }
    }

    private func tile(_ n: AppNotification) -> Color {
        switch n.kind {
        case .survey: Theme.primary
        case .install: n.isToday ? Theme.success : Theme.muted
        case .syncPending: Theme.warning
        case .saved: Theme.muted
        }
    }
}

private struct NotificationRowLabel: View {
    let title: String
    let detail: String
    let time: String
    let symbol: String
    let tile: Color
    let hint: String?
    let hintColor: Color
    let unread: Bool
    let actionable: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(tile, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(.sarabun(14, unread ? .heavy : .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(time).font(.sarabun(11.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).monospacedDigit()
                }
                Text(detail).font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                if let hint {
                    Text(hint).font(.sarabun(12.5, .bold, relativeTo: .caption)).foregroundStyle(hintColor).lineLimit(1)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chevron)
                .opacity(actionable ? 1 : 0)
        }
        .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(unread ? Theme.unreadRow : Theme.surface)
        .overlay(alignment: .leading) {
            if unread { Circle().fill(Theme.primary).frame(width: 7, height: 7).padding(.leading, 7) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(unread ? "ยังไม่อ่าน" : "")
    }
}
