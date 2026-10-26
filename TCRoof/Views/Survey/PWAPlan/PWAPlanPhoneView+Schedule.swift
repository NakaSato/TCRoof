import SwiftUI
import TCRoofUI
import TCRoofCore

/// Where the day list stands: how far its content has moved, and the top of each listed day in the list's space.
private struct DayListPosition: Equatable {
    var offset: CGFloat = 0
    var tops: [Date: CGFloat] = [:]
}

private struct DayTops: PreferenceKey {
    static let defaultValue = DayListPosition()
    static func reduce(value: inout DayListPosition, nextValue: () -> DayListPosition) {
        let next = nextValue()
        value.offset += next.offset
        value.tops.merge(next.tops) { $1 }
    }
}

/// `ตารางงาน`: the calendar card (a week or a month, with the colour bars of each day's job types), the list heading
/// with its filter, and one scrolling list of every day shown. The day at the top of the list is the selected day.
extension PWAPlanPhoneView {
    /// The calendar's rows of seven cells, Monday first: the week, or the month with blank cells around it.
    private var calendarRows: [[Date?]] {
        calendarMode == .week ? [PWAPlan.week(from: weekStart).map(Optional.some)] : PWAPlan.monthRows(containing: day)
    }

    /// A type or a team is picked.
    var isFiltered: Bool { type != nil || team != nil }

    private var searching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private func passes(_ item: PWAPlan.AgendaItem) -> Bool {
        (type == nil || item.type == type) && PWAPlan.matches(item, team: team) && item.matches(search: search)
    }

    func schedule(_ board: PWAPlanBoard) -> some View {
        let rows = calendarRows, days = rows.flatMap { $0 }.compactMap { $0 }
        let items = board.agenda(days), shown = items.filter(passes)
        return VStack(alignment: .leading, spacing: 10) {
            Group {
                calendarCard(rows, types: board.typesByDay ?? PWAPlan.types(items), today: board.today)
                listHeading(items, shown: shown.count, teams: PWAPlan.teamKeys(items), today: board.today)
                if isFiltered { filterChips }
            }
            .padding(.horizontal, 16)
            dayList(days, all: Dictionary(grouping: items, by: \.day), shown: Dictionary(grouping: shown, by: \.day), today: board.today)
        }
        .padding(.top, 10)
        // rows come and go above the selected day: keep it at the top
        .onChange(of: type) { scrollToDay(animated: false) }
        .onChange(of: team) { scrollToDay(animated: false) }
        .onChange(of: search) { scrollToDay(animated: false) }
        .onChange(of: items.count) { scrollToDay(animated: false) }
    }

    /// iPad: the framed `ตารางงาน` card. The calendar stays and only the day list scrolls, inside the card. No filter
    /// button: the board has none.
    func padSchedule(_ board: PWAPlanBoard) -> some View {
        let rows = calendarRows, days = rows.flatMap { $0 }.compactMap { $0 }
        let items = board.agenda(days), shown = items.filter(passes)
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            padCardHeader("ตารางงาน", "ทุกงานของโครงการ")
            calendarCard(rows, types: board.typesByDay ?? PWAPlan.types(items), today: board.today)
            listHeading(items, shown: shown.count, teams: PWAPlan.teamKeys(items), today: board.today)
            dayList(days, all: Dictionary(grouping: items, by: \.day), shown: Dictionary(grouping: shown, by: \.day), today: board.today)
        }
        .padding(.horizontal, 12).padding(.top, 10)
        .background(Theme.surface, in: frame)
        .clipShape(frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
        .onChange(of: search) { scrollToDay(animated: false) }
        .onChange(of: items.count) { scrollToDay(animated: false) }
    }

    /// Scrolls the day list to the selected day. Until it is there the list's position selects nothing.
    private func scrollToDay(animated: Bool) {
        spyLock = .distantFuture
        jumpAnimated = animated
        jump += 1
    }

    // MARK: calendar card

    private func calendarCard(_ rows: [[Date?]], types: [Date: Set<PWAPlan.JobType>], today: Date) -> some View {
        let week = calendarMode == .week
        return VStack(spacing: 6) {
            HStack(spacing: 2) {
                arrow("chevron.left", week ? "สัปดาห์ก่อน" : "เดือนก่อน", by: -1)
                calendarTitle
                arrow("chevron.right", week ? "สัปดาห์ถัดไป" : "เดือนถัดไป", by: 1)
                Spacer(minLength: 4)
                TCCountSegments([.init("สัปดาห์"), .init("เดือน")],
                                selection: Binding(get: { week ? 0 : 1 }, set: { setCalendar($0 == 0 ? .week : .month) }), equalWidths: false)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("มุมมองปฏิทิน")
            }
            .padding(.trailing, 4)
            if !week { weekdayHeader }
            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in calendarRow(cells, types: types, today: today) }
            }
            if !week { legend }
        }
        .padding(.horizontal, 6).padding(.vertical, 8)
        // iPad: a soft panel inside the `ตารางงาน` card
        .background(pad ? Theme.stripFill : Theme.surface, in: RoundedRectangle(cornerRadius: pad ? 12 : 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: pad ? 12 : 16, style: .continuous).strokeBorder(pad ? Theme.track : Theme.borderSubtle))
    }

    /// `12–18 ต.ค. 2569` over the ISO week number, or `ตุลาคม 2569`.
    private var calendarTitle: some View {
        let week = calendarMode == .week
        let sunday = PWAPlan.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return VStack(alignment: .leading, spacing: 0) {
            Text(week ? "\(PWAPlanFormat.range(weekStart, sunday)) \(PWAPlanFormat.year.string(from: sunday))" : PWAPlanFormat.monthYear.string(from: day))
                .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).frame(height: 18)
                .accessibilityAddTraits(.isHeader)
            if week {
                Text("สัปดาห์ที่ \(PWAPlan.calendar.component(.weekOfYear, from: weekStart))")
                    .font(.sarabunFixed(11.5, .semibold)).foregroundStyle(Theme.primary).frame(height: 15)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.75)
    }

    private func arrow(_ symbol: String, _ label: String, by step: Int) -> some View {
        Button {
            let cal = PWAPlan.calendar
            if calendarMode == .week {
                weekStart = cal.date(byAdding: .day, value: 7 * step, to: weekStart) ?? weekStart
                day = cal.date(byAdding: .day, value: 7 * step, to: day) ?? day
            } else if let first = cal.dateInterval(of: .month, for: day)?.start, let month = cal.date(byAdding: .month, value: step, to: first) {
                // today in its own month, else the 1st
                let today = cal.startOfDay(for: Self.today)
                day = cal.isDate(today, equalTo: month, toGranularity: .month) ? today : month
            }
            scrollToDay(animated: false)
        } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.primary)
                .frame(width: 40, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The month keeps the day. The week view shows its own week: a day picked outside it gives way to today.
    private func setCalendar(_ mode: CalendarMode) {
        guard mode != calendarMode else { return }
        let cal = PWAPlan.calendar
        if mode == .week, !PWAPlan.week(from: weekStart).contains(day) {
            day = cal.startOfDay(for: Self.today)
            weekStart = Self.monday(of: day)
        }
        calendarMode = mode
        scrollToDay(animated: false)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(Array(PWAPlanFormat.weekdayLetters.enumerated()), id: \.offset) { i, letter in
                Text(letter).font(.sarabunFixed(11, .semibold)).foregroundStyle(i >= 5 ? Theme.inkFaint : Theme.inkMuted)
                    .frame(maxWidth: .infinity).frame(height: 16)
            }
        }
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        FlowLayout(spacing: 12, lineSpacing: 4) {
            ForEach(PWAPlan.JobType.allCases, id: \.self) { t in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(t.ink).frame(width: 12, height: 4)
                    Text(t.title).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 2)
        .accessibilityHidden(true)
    }

    /// One row of seven cells with its bars drawn over it in one piece, so a type's run of days is one line.
    private func calendarRow(_ cells: [Date?], types: [Date: Set<PWAPlan.JobType>], today: Date) -> some View {
        let week = calendarMode == .week
        let height: CGFloat = week ? 62 : 46
        // where the cell's centred text leaves the bars: 4 pt high, 2 pt apart
        let barTop: CGFloat = week ? 42 : 26
        let runs = PWAPlan.barRuns(cells, types: types, selected: day)
        return HStack(spacing: 2) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, d in
                if let d {
                    dayCell(d, column: i, height: height, types: types[d]?.count ?? 0, isToday: PWAPlan.calendar.isDate(d, inSameDayAs: today))
                } else {
                    Color.clear.frame(maxWidth: .infinity).frame(height: height)
                }
            }
        }
        .overlay {
            GeometryReader { g in
                let cell = (g.size.width - 12) / 7
                ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                    // 6 pt in from the ends of the run; across the 2 pt between cells where it goes on
                    let x = CGFloat(run.from) * (cell + 2) + 6, end = CGFloat(run.to) * (cell + 2) + cell - 6
                    let selected = cells[run.from] == day
                    RoundedRectangle(cornerRadius: 2)
                        .fill(selected ? Theme.onPrimary.opacity(run.lane == 0 ? 1 : 0.85) : run.type.ink)
                        .frame(width: max(end - x, 4), height: 4)
                        .offset(x: x, y: barTop + CGFloat(run.lane) * 6)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func dayCell(_ d: Date, column: Int, height: CGFloat, types: Int, isToday: Bool) -> some View {
        let on = d == day, week = calendarMode == .week
        let ink = on ? Theme.onPrimary : isToday ? Theme.primary : column >= 5 ? Theme.inkFaint : Theme.navy
        let number = Text("\(PWAPlan.calendar.component(.day, from: d))").monospacedDigit()
        return Button {
            day = d
            scrollToDay(animated: true)
        } label: {
            VStack(spacing: week ? 1 : 3) {
                if week {
                    Text(PWAPlanFormat.weekdayLetters[column]).font(.sarabunFixed(11)).frame(height: 14)
                    number.font(.sarabunFixed(17, .bold)).frame(height: 22)
                } else {
                    number.font(.sarabunFixed(15, .bold)).frame(height: 19)
                }
                // the bars: `calendarRow` draws them
                Color.clear.frame(height: 16)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(on ? Theme.navySolid : isToday ? Theme.primarySoft : .clear, in: RoundedRectangle(cornerRadius: week ? 12 : 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PWAPlanFormat.weekday.string(from: d)) \(PWAPlanFormat.dayMonth.string(from: d))" + (isToday ? " | วันนี้" : "")
                            + (types > 0 ? " | \(types) ประเภทงาน" : " | ไม่มีงาน"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: heading and filter

    /// `งานสัปดาห์นี้ 15 รายการ | เลื่อนดูได้`, counting every day in the list, and the filter button.
    private func listHeading(_ items: [PWAPlan.AgendaItem], shown: Int, teams: [String], today: Date) -> some View {
        let title = calendarMode == .month ? "งานทั้งเดือน"
            : weekStart == Self.monday(of: today) ? "งานสัปดาห์นี้" : "งานสัปดาห์ที่ \(PWAPlan.calendar.component(.weekOfYear, from: weekStart))"
        return HStack(spacing: 8) {
            Text(title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                .accessibilityAddTraits(.isHeader)
            Text(isFiltered || searching ? "\(shown) จาก \(items.count) รายการ" : "\(items.count) รายการ | เลื่อนดูได้")
                .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).monospacedDigit().minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if !pad {
                Button { showFilter.toggle() } label: { TCFilterCircle(open: showFilter, filtered: isFiltered) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("กรองตารางงาน: \(type?.title ?? "ทุกประเภท") | \(team.map(teamTitle) ?? "ทุกทีม") | \(shown) รายการ")
                    .popover(isPresented: $showFilter, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                        filterPopover(items, shown: shown, teams: teams)
                            .presentationCompactAdaptation(.popover).presentationBackground(Theme.surface)
                    }
            }
        }
        .lineLimit(1)
    }

    // MARK: day list

    private func dayList(_ days: [Date], all: [Date: [PWAPlan.AgendaItem]], shown: [Date: [PWAPlan.AgendaItem]], today: Date) -> some View {
        GeometryReader { g in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(days, id: \.self) { d in
                            daySection(d, all: all[d]?.count ?? 0, rows: shown[d] ?? [], isToday: PWAPlan.calendar.isDate(d, inSameDayAs: today))
                                .background {
                                    GeometryReader { p in
                                        Color.clear.preference(key: DayTops.self, value: .init(tops: [d: p.frame(in: .named("days")).minY]))
                                    }
                                }
                                .id(d)
                        }
                    }
                    // room under the last day for it to reach the top
                    .padding(.horizontal, pad ? 0 : 16).padding(.top, 2).padding(.bottom, max(g.size.height - 60, 20))
                    .background {
                        GeometryReader { p in Color.clear.preference(key: DayTops.self, value: .init(offset: p.frame(in: .named("days")).minY)) }
                    }
                }
                .coordinateSpace(name: "days")
                .scrollIndicators(pad ? .hidden : .automatic)
                .scrollDismissesKeyboard(.immediately)
                .onPreferenceChange(DayTops.self) { at in
                    // only a list that moved selects a day, not rows that came or went
                    let moved = abs(at.offset - spyOffset) > 0.5
                    spyOffset = at.offset
                    // the last day whose heading has reached the top
                    guard moved, Date() >= spyLock, let top = at.tops.filter({ $0.value <= 24 }).max(by: { $0.value < $1.value })?.key,
                          top != day else { return }
                    day = top
                }
                .task(id: jump) {
                    let animated = jumpAnimated && !reduceMotion
                    jumpAnimated = false
                    withAnimation(animated ? .easeInOut(duration: 0.35) : nil) { proxy.scrollTo(day, anchor: .top) }
                    spyLock = Date().addingTimeInterval(animated ? 0.7 : 0.25)
                }
                .onDisappear { spyLock = .distantFuture }
            }
        }
    }

    /// A day's heading (`วันพฤหัสบดี 15 ต.ค. 3 รายการ`, blue with a dot when selected) over its rows, or a dashed row
    /// when it has none.
    private func daySection(_ d: Date, all: Int, rows: [PWAPlan.AgendaItem], isToday: Bool) -> some View {
        let on = d == day
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(on ? Theme.primary : .clear).frame(width: 6, height: 6)
                Text("\(PWAPlanFormat.weekday.string(from: d)) \(PWAPlanFormat.dayMonth.string(from: d))" + (isToday ? " | วันนี้" : ""))
                    .font(.sarabunFixed(13, .bold)).foregroundStyle(on ? Theme.primary : Theme.navy)
                    .accessibilityAddTraits(.isHeader)
                if all > 0 {
                    Text(rows.count == all ? "\(all) รายการ" : "\(rows.count) จาก \(all)")
                        .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).monospacedDigit()
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 2).padding(.top, 2)
            ForEach(rows) { agendaRow($0) }
            if rows.isEmpty {
                Text(all == 0 ? "ไม่มีงาน" : isFiltered ? "ไม่มีงานในตัวกรองนี้" : "ไม่พบงานที่ค้นหา")
                    .font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }

    private func teamTitle(_ key: String) -> String {
        key == PWAPlan.ownTeams ? "ทีม TC" : PWAPlan.contractorTitle(key)
    }

    private func resetFilter() {
        type = nil
        team = nil
    }

    private func filterPopover(_ items: [PWAPlan.AgendaItem], shown: Int, teams: [String]) -> some View {
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
            popoverSection("ประเภทงาน") { typeChips(items) }
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

    /// `ทั้งหมด` and one chip per type, with the count of the days shown under the team filter. A type with nothing is
    /// grey, and can still be picked.
    private func typeChips(_ items: [PWAPlan.AgendaItem]) -> some View {
        let inTeam = items.filter { PWAPlan.matches($0, team: team) }
        let options: [PWAPlan.JobType?] = [nil] + PWAPlan.JobType.allCases
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(options, id: \.self) { t in
                let on = type == t, n = inTeam.filter { t == nil || $0.type == t }.count
                Button { type = t } label: {
                    HStack(spacing: 5) {
                        Circle().fill(on ? Theme.onPrimary : t?.ink ?? Theme.navySolid).frame(width: 8, height: 8)
                        Text(t?.title ?? "ทั้งหมด").font(.sarabunFixed(12.5, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
            .padRow(pad)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.start.map(PWAPlan.clock) ?? "ทั้งวัน", item.type.title, item.ref, item.title, item.subtitle, item.status.title]
            .filter { !$0.isEmpty }.joined(separator: " | "))
        .accessibilityAddTraits(.isButton)
    }
}
