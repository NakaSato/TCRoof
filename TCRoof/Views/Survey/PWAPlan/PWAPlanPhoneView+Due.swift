import SwiftUI
import TCRoofUI
import TCRoofCore

/// `กำหนดส่ง`: the handovers and submissions of this week (with everything overdue) and the next, and the filter
/// button at the end of the pill row with its menu.
extension PWAPlanPhoneView {
    /// The menu's choices: every kind, handovers, submissions.
    private static let dueFilters: [(kind: PWAPlan.DeadlineKind?, title: String)] =
        [(nil, "ทั้งหมด"), (.handover, "ส่งมอบ"), (.document, "ยื่นเอกสาร")]

    private func shown(_ list: [PWAPlan.Deadline], kind: PWAPlan.DeadlineKind?) -> [PWAPlan.Deadline] {
        list.filter { (kind == nil || $0.kind == kind) && $0.matches(search: search) }
    }

    @ViewBuilder func dueList(_ due: PWAPlan.DeadlineGroups) -> some View {
        let cal = PWAPlan.calendar
        let thisWeek = shown(due.thisWeek, kind: dueFilter), nextWeek = shown(due.nextWeek, kind: dueFilter)
        let sunday = cal.date(byAdding: .day, value: 6, to: due.thisStart) ?? due.thisStart
        let nextSunday = cal.date(byAdding: .day, value: 6, to: due.nextStart) ?? due.nextStart
        if !thisWeek.isEmpty {
            dueGroup("สัปดาห์นี้", PWAPlanFormat.range(due.thisStart, sunday) + " · รวมที่เลยกำหนด", thisWeek)
        }
        if !nextWeek.isEmpty {
            dueGroup("สัปดาห์หน้า", PWAPlanFormat.range(due.nextStart, nextSunday), nextWeek)
        }
        if thisWeek.isEmpty && nextWeek.isEmpty {
            Text(due.all.isEmpty ? "ไม่มีกำหนดส่งใน 2 สัปดาห์นี้" : "ไม่มีกำหนดส่งในตัวกรองนี้")
                .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12).padding(.vertical, 18)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    /// iPad: the framed `กำหนดส่ง` card, beside `รายสถานี`. It grows with its rows. No filter: the board has none.
    func padDueCard(_ due: PWAPlan.DeadlineGroups) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            padCardHeader("กำหนดส่ง", "งานส่งมอบและเอกสาร")
            dueList(due)
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func dueGroup(_ title: String, _ range: String, _ rows: [PWAPlan.Deadline]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                Text(range).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            .lineLimit(1)
            .padding(.horizontal, 2).padding(.top, 2)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(rows) { dueRow($0) }
        }
    }

    /// Date tile and chip colours by tone: an on-plan row has a navy-tinted tile and a green chip.
    private func tileColors(_ tone: PWAPlan.Tone) -> (fill: Color, ink: Color) {
        switch tone {
        case .late: (Theme.dangerSoft, Theme.dangerText)
        case .risk: (Theme.warningTint, Theme.warningText)
        case .ok: (Theme.progressBox, Theme.navy)
        }
    }

    private func chipColors(_ tone: PWAPlan.Tone) -> (fill: Color, ink: Color) {
        tone == .ok ? (Theme.successSoft, Theme.successText) : tileColors(tone)
    }

    private func dueRow(_ d: PWAPlan.Deadline) -> some View {
        let tile = tileColors(d.tone), chip = chipColors(d.tone)
        return Button { open(d.opens, station: d.station) } label: {
            HStack(spacing: 10) {
                VStack(spacing: 0) {
                    Text("\(PWAPlan.calendar.component(.day, from: d.date))").font(.sarabunFixed(16, .bold)).monospacedDigit().frame(height: 17)
                    Text(PWAPlanFormat.month.string(from: d.date)).font(.sarabunFixed(10)).frame(height: 13)
                }
                .foregroundStyle(tile.ink)
                .frame(width: 46).padding(.vertical, 4)
                .background(tile.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(d.title).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).frame(height: 18)
                    Text(d.subtitle).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).frame(height: 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(d.chip).font(.sarabunFixed(11, .bold)).foregroundStyle(chip.ink)
                    .padding(.horizontal, 8).frame(height: 18)
                    .background(chip.fill, in: Capsule())
                    .fixedSize()
            }
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .padRow(pad)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(PWAPlanFormat.dayMonth.string(from: d.date)) · \(d.title) · \(d.subtitle) · \(d.chip)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: filter

    func dueFilterButton(_ due: PWAPlan.DeadlineGroups) -> some View {
        let title = Self.dueFilters.first { $0.kind == dueFilter }?.title ?? ""
        return Button { showDueMenu.toggle() } label: { TCFilterCircle(open: showDueMenu, filtered: dueFilter != nil) }
            .buttonStyle(.plain)
            .accessibilityLabel("กรองกำหนดส่ง: \(title) \(shown(due.all, kind: dueFilter).count) รายการ")
    }

    /// 220 pt wide, right-aligned 8 pt under the filter button (the pill row is 12 + 44 pt), over a clear layer that
    /// closes it.
    func dueMenu(_ due: PWAPlan.DeadlineGroups) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { showDueMenu = false }
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(Self.dueFilters, id: \.title) { f in
                    let on = dueFilter == f.kind
                    Button {
                        dueFilter = f.kind
                        showDueMenu = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.primary)
                                .opacity(on ? 1 : 0).frame(width: 20)
                            Text(f.title).font(.sarabunFixed(14, on ? .bold : .regular)).foregroundStyle(Theme.navy)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(shown(due.all, kind: f.kind).count) รายการ").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).monospacedDigit()
                        }
                        .lineLimit(1)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(on ? Theme.primarySoft : Theme.surface)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            .frame(width: 220)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderOutdoor))
            .padding(.top, 64).padding(.trailing, 16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("กรองกำหนดส่ง")
        }
    }
}
