import SwiftUI
import TCRoofUI
import TCRoofCore

/// `ตารางงาน`: the week strip, the selected day's heading with its filter, and the day's rows.
extension PWAPlanPhoneView {
    /// The seven days of the shown week, Monday first.
    private var week: [Date] { (0..<7).map { PWAPlan.calendar.date(byAdding: .day, value: $0, to: weekStart) ?? weekStart } }

    /// A type or a team is picked.
    var isFiltered: Bool { type != nil || team != nil }

    private var searching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    @ViewBuilder func schedule(_ board: PWAPlanBoard) -> some View {
        let items = board.agenda(week)
        let ofDay = items.filter { $0.day == day }
        let shown = ofDay.filter { (type == nil || $0.type == type) && PWAPlan.matches($0, team: team) && $0.matches(search: search) }
        weekStrip(items, today: board.today)
        dayHeading(ofDay, shown: shown.count, teams: PWAPlan.teamKeys(items), today: board.today)
        if isFiltered { filterChips }
        ForEach(shown) { agendaRow($0) }
        if shown.isEmpty { emptyCard(dayIsEmpty: ofDay.isEmpty) }
    }

    // MARK: week strip

    private func weekStrip(_ items: [PWAPlan.AgendaItem], today: Date) -> some View {
        let number = PWAPlan.calendar.component(.weekOfYear, from: weekStart)
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                weekArrow("chevron.left", "สัปดาห์ก่อน", by: -7)
                Text("\(PWAPlanFormat.monthYear.string(from: day)) · สัปดาห์ที่ \(number)")
                    .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                weekArrow("chevron.right", "สัปดาห์ถัดไป", by: 7)
            }
            .padding(.horizontal, 4)
            HStack(spacing: 2) {
                ForEach(Array(week.enumerated()), id: \.offset) { i, d in
                    dayCell(d, letter: PWAPlanFormat.weekdayLetters[i], weekend: i >= 5, types: dotTypes(items.filter { $0.day == d }),
                            isToday: PWAPlan.calendar.isDate(d, inSameDayAs: today))
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func weekArrow(_ symbol: String, _ label: String, by days: Int) -> some View {
        Button {
            let cal = PWAPlan.calendar
            weekStart = cal.date(byAdding: .day, value: days, to: weekStart) ?? weekStart
            day = cal.date(byAdding: .day, value: days, to: day) ?? day
        } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.primary)
                // 36 pt tall on the board; the hit area takes the card's padding to reach 44
                .frame(width: 44, height: 36).padding(.vertical, 4).contentShape(Rectangle()).padding(.vertical, -4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Up to three types for a day's dots. The types that fill a day (install, survey, papers) win a place first;
    /// the dots then stand in the types' own order.
    private func dotTypes(_ items: [PWAPlan.AgendaItem]) -> [PWAPlan.JobType] {
        let priority: [PWAPlan.JobType] = [.install, .survey, .document, .test, .inspection, .notice]
        let order: [PWAPlan.JobType] = [.install, .survey, .inspection, .test, .document, .notice]
        let present = Set(items.map(\.type)), picked = Set(priority.filter(present.contains).prefix(3))
        return order.filter(picked.contains)
    }

    private func dayCell(_ d: Date, letter: String, weekend: Bool, types: [PWAPlan.JobType], isToday: Bool) -> some View {
        let on = d == day
        let ink = on ? Theme.onPrimary : isToday ? Theme.primary : weekend ? Theme.inkFaint : Theme.navy
        let count = types.count
        return Button { day = d } label: {
            VStack(spacing: 1) {
                Text(letter).font(.sarabunFixed(11)).frame(height: 14)
                Text("\(PWAPlan.calendar.component(.day, from: d))").font(.sarabunFixed(17, .bold)).monospacedDigit().frame(height: 22)
                HStack(spacing: 2) {
                    ForEach(types, id: \.self) { t in Circle().fill(on ? Theme.onPrimary : t.ink).frame(width: 5, height: 5) }
                }
                .frame(height: 6)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(on ? Theme.navySolid : isToday ? Theme.primarySoft : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PWAPlanFormat.weekday.string(from: d)) \(PWAPlanFormat.dayMonth.string(from: d))" + (isToday ? " · วันนี้" : "")
                            + " · \(count) ประเภทงาน")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: heading and filter

    private func dayHeading(_ ofDay: [PWAPlan.AgendaItem], shown: Int, teams: [String], today: Date) -> some View {
        let isToday = PWAPlan.calendar.isDate(day, inSameDayAs: today)
        let narrowed = isFiltered || searching
        return HStack(spacing: 8) {
            Text("\(PWAPlanFormat.weekday.string(from: day)) \(PWAPlanFormat.dayMonth.string(from: day))" + (isToday ? " · วันนี้" : ""))
                .font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                .accessibilityAddTraits(.isHeader)
            Text(narrowed ? "\(shown) จาก \(ofDay.count) รายการ" : "\(ofDay.count) รายการ")
                .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            Spacer(minLength: 0)
            Button { showFilter.toggle() } label: { TCFilterCircle(open: showFilter, filtered: isFiltered) }
                .buttonStyle(.plain)
                .accessibilityLabel("กรองตารางงาน: \(type?.title ?? "ทุกประเภท") · \(team.map(teamTitle) ?? "ทุกทีม") · \(shown) รายการ")
                .popover(isPresented: $showFilter, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    filterPopover(ofDay, shown: shown, teams: teams)
                        .presentationCompactAdaptation(.popover).presentationBackground(Theme.surface)
                }
        }
        .lineLimit(1)
    }

    private func teamTitle(_ key: String) -> String {
        key == PWAPlan.ownTeams ? "ทีม TC" : PWAPlan.contractorTitle(key)
    }

    private func resetFilter() {
        type = nil
        team = nil
    }

    private func filterPopover(_ ofDay: [PWAPlan.AgendaItem], shown: Int, teams: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("กรองตารางงาน").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Button("ล้าง", action: resetFilter)
                    .font(.sarabunFixed(13, .bold)).foregroundStyle(isFiltered ? Theme.primary : Theme.inkFaint)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .disabled(!isFiltered)
                    .accessibilityLabel("ล้างตัวกรองตารางงาน")
            }
            .frame(height: 32)
            popoverSection("ประเภทงาน") { typeChips(ofDay) }
            if !teams.isEmpty { popoverSection("ทีม") { teamSegments(teams) } }
            Button { showFilter = false } label: {
                Text("แสดง \(shown) รายการ").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 300)
    }

    private func popoverSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.inkMuted)
            content()
        }
    }

    /// `ทั้งหมด` and one chip per type, with the day's count under the team filter. A type with nothing is grey, and
    /// can still be picked.
    private func typeChips(_ ofDay: [PWAPlan.AgendaItem]) -> some View {
        let inTeam = ofDay.filter { PWAPlan.matches($0, team: team) }
        let options: [PWAPlan.JobType?] = [nil] + PWAPlan.JobType.allCases
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(options, id: \.self) { t in
                let on = type == t, n = inTeam.filter { t == nil || $0.type == t }.count
                Button { type = t } label: {
                    HStack(spacing: 5) {
                        Circle().fill(on ? Theme.onPrimary : t?.ink ?? Theme.navySolid).frame(width: 8, height: 8)
                        Text(t?.title ?? "ทั้งหมด").font(.sarabunFixed(12.5, .bold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(n)").font(.sarabunFixed(14, .bold)).monospacedDigit()
                    }
                    .foregroundStyle(on ? Theme.onPrimary : n > 0 ? Theme.navySolid : Theme.inkFaint)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(on ? Theme.navySolid : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        if !on { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(n > 0 ? Theme.borderSubtle : Theme.hairline) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(t?.title ?? "ทั้งหมด") \(n) รายการ")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func teamSegments(_ teams: [String]) -> some View {
        let options: [String?] = [nil] + teams
        return HStack(spacing: 0) {
            ForEach(options, id: \.self) { k in
                let on = team == k
                Button { team = k } label: {
                    Text(k ?? "ทุกทีม").font(.sarabunFixed(13, .bold)).lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(on ? Theme.navySolid : Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background { if on { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface) } }
                        .overlay { if on { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(k.map(teamTitle) ?? "ทุกทีม")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ทีม")
    }

    /// `ติดตั้ง ✕`, `ผู้รับเหมา A ✕`: 30 pt chips in 44 pt hit areas.
    private var filterChips: some View {
        HStack(spacing: 2) {
            if let type { filterChip(type.title) { self.type = nil } }
            if let team { filterChip(teamTitle(team)) { self.team = nil } }
        }
        .padding(.leading, -4).padding(.top, -8).padding(.bottom, -6)
    }

    private func filterChip(_ title: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Text(title).font(.sarabunFixed(12, .bold))
                Image(systemName: "xmark").font(.system(size: 10, weight: .heavy))
            }
            .foregroundStyle(Theme.primary)
            .padding(.leading, 10).padding(.trailing, 8).frame(height: 30)
            .background(Theme.primarySoft, in: Capsule())
            .padding(.horizontal, 4).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ล้างตัวกรอง \(title)")
    }

    // MARK: rows

    private func statusColor(_ s: PWAPlan.AgendaStatus) -> Color {
        switch s {
        case .doing: Theme.primary
        case .booked, .onPlan: Theme.successText
        case .waiting: Theme.inkMuted
        case .mustSubmit: Theme.warningText
        case .alert: Theme.dangerText
        }
    }

    private func agendaRow(_ item: PWAPlan.AgendaItem) -> some View {
        Button { open(item.opens, station: item.station) } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.start.map(PWAPlan.clock) ?? "ทั้งวัน").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                        .minimumScaleFactor(0.8).frame(height: 18)
                    if let end = item.end {
                        Text("–" + PWAPlan.clock(end)).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).frame(height: 18)
                    }
                }
                .monospacedDigit().lineLimit(1)
                .frame(width: 44, alignment: .leading)
                RoundedRectangle(cornerRadius: 2).fill(item.type.ink).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.type.title).font(.sarabunFixed(11, .bold)).foregroundStyle(item.type.ink)
                            .padding(.horizontal, 8).frame(height: 18)
                            .background(item.type.fill, in: Capsule())
                        Text(item.ref).font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted)
                        Spacer(minLength: 4)
                        Text(item.status.title).font(.sarabunFixed(11, .bold)).foregroundStyle(statusColor(item.status))
                    }
                    Text(item.title).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).frame(height: 18)
                    Text(item.subtitle).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).frame(height: 18)
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.start.map(PWAPlan.clock) ?? "ทั้งวัน", item.type.title, item.ref, item.title, item.subtitle, item.status.title]
            .filter { !$0.isEmpty }.joined(separator: " · "))
        .accessibilityAddTraits(.isButton)
    }

    /// A day with no rows, a filter that matches none (with `ล้างตัวกรอง`), or a search that finds none.
    private func emptyCard(dayIsEmpty: Bool) -> some View {
        HStack(spacing: 4) {
            if dayIsEmpty {
                Text("ไม่มีงานในวันนี้")
            } else if isFiltered {
                Text("ไม่มีงานในตัวกรองนี้ ·")
                Button("ล้างตัวกรอง", action: resetFilter)
                    .font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                    .frame(minHeight: 44).contentShape(Rectangle())
                    .buttonStyle(.plain)
            } else {
                Text("ไม่พบงานที่ค้นหาในวันนี้")
            }
        }
        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 12).padding(.vertical, 18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
