import SwiftUI
import TCRoofUI
import TCRoofCore

/// The iPhone (compact width) install tracking page (docs/ui/install-tracking-iphone): the blue header with the
/// assistant and the project settings' gear, a scrolling strip of seven tabs that all change the page in place, and
/// the main dock kept under it. The iPad layout is `padBody`.
extension InstallTrackingPage {
    enum PhoneTab: String, CaseIterable { case overview, daily, request, weekly, iec, docs, plan }

    /// Screens the phone page pushes that the iPad's `Route` has no case for.
    enum PhoneRoute: Hashable {
        case request(Date), weekly(Date), docs(StationDocs.Package?, String?), access
    }

    /// A stage's edited start (days moved) and length, in `แผนก่อสร้าง`'s edit mode.
    struct PlanDraft: Equatable {
        var shift = 0
        var days: Int
    }

    @ViewBuilder func phoneDestination(_ r: PhoneRoute) -> some View {
        switch r {
        case .request(let week): WeeklyRequestScreen(job: job, week: week)
        case .weekly(let week): RoutineSummaryScreen(job: job, period: .week, anchor: week)
        case .docs(let package, let paper):
            if canOpen(.docs) { StationDocsScreen(job: job, package: package, paper: paper.flatMap(StationDocs.kind)) }
        case .access: PhoneAccessScreen(job: job)
        }
    }

    func phoneBody(_ data: InstallPageData) -> some View {
        VStack(spacing: 0) {
            phoneHeader(data)
            if !phoneSettings { phoneTabStrip(data) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if phoneSettings { settingsPage(data) } else { phoneContent(data) }
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
                    Color.clear.frame(height: 1).id("end")
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                #if DEBUG
                .task {
                    guard Debug.scrollEnd else { return }
                    try? await Task.sleep(for: .milliseconds(500))
                    proxy.scrollTo("end", anchor: .bottom)
                }
                #endif
            }
        }
        .background(Theme.phonePage.ignoresSafeArea())
        // the main dock stays on this page, as on iPad (docs/ui/install-tracking-iphone §4.1)
        .phoneDock(fade: Theme.phonePage, spacing: 0)
        .sheet(item: $phoneSheet) { s in
            switch s {
            case .routine: RoutineSettingsSheet(job: job)
            case .station: StationFactsSheet(job: job)
            }
        }
    }

    @ViewBuilder private func phoneContent(_ data: InstallPageData) -> some View {
        switch phoneTab {
        case .overview:
            phoneKPIs(data)
            if let g = data.gantt { phoneProgressCard(data, g) }
            if permissions.role != .external, !data.docs.isEmpty { phoneDocsCard(data.docs) }
            if let s = data.site { phoneSitePanel(s) }
        case .daily: phoneDailyTab(dailyData)
        case .request: phoneRequestTab()
        case .weekly: phoneWeeklyTab()
        case .iec: phoneIECTab()
        case .docs: if canOpen(.docs) { phoneDocsTab() }
        case .plan: phonePlanTab(data)
        }
    }

    // MARK: header

    /// `209.76 kWp | ทีม TCR04 | ผู้รับเหมา C`: the size, the team and the contractor the station settings name.
    private func phoneSubtitle(_ data: InstallPageData) -> String {
        #if DEBUG
        if Debug.demo { return data.subtitle }
        #endif
        let kWp = job.capacityKW.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
        let contractor = job.routineSettings.subcontractor.trimmingCharacters(in: .whitespaces)
        return [job.capacityKW > 0 ? kWp + " kWp" : nil, "ทีม " + job.team.rawValue, contractor.isEmpty ? nil : contractor]
            .compactMap { $0 }.joined(separator: " | ")
    }

    private func phoneHeader(_ data: InstallPageData) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(data.title).font(.sarabun(19, .bold)).lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
                Text(phoneSubtitle(data)).font(.sarabun(13)).opacity(0.92).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if permissions.can(.assistantUse), job.scheduleInput != nil {
                roundButton("ผู้ช่วย", "sparkles", on: false) { assistant = true }
            }
            if permissions.role != .external {
                roundButton("ตั้งค่าเฉพาะโครงการ", "gearshape", on: phoneSettings) {
                    withAnimation(.snappy) {
                        phoneSettings.toggle()
                        settingsCategory = nil
                    }
                }
            }
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15, style: .continuous)
                .fill(Theme.headerGradient).ignoresSafeArea(edges: .top)
        }
    }

    /// A round 44 pt button on the blue header; white with a blue icon while its page is open.
    private func roundButton(_ label: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? Theme.primary : Theme.onPrimary)
                .frame(width: 44, height: 44)
                .background(on ? Theme.surface : Theme.onPrimary.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(Theme.onPrimary.opacity(on ? 0 : 0.4)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: tab strip

    private static func phoneItem(_ t: PhoneTab) -> (title: String, symbol: String) {
        switch t {
        case .overview: ("ภาพรวม", "chart.line.uptrend.xyaxis")
        case .daily: ("รายงานประจำวัน", "list.clipboard")
        case .request: ("คำขอรายสัปดาห์", "calendar")
        case .weekly: ("Weekly Report", "doc.text")
        case .iec: ("ทดสอบ IEC 62446", "bolt")
        case .docs: ("เอกสาร", "doc")
        case .plan: ("แผนก่อสร้าง", "slider.horizontal.3")
        }
    }

    private func phoneTabStrip(_ data: InstallPageData) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(PhoneTab.allCases.filter { t in
                        permissions.role != .external || ![.weekly, .docs, .plan].contains(t)
                    }, id: \.self) { t in
                        let on = t == phoneTab, item = Self.phoneItem(t)
                        Button {
                            guard permissions.role != .external || ![.weekly, .docs, .plan].contains(t) else { return }
                            phoneTab = t
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: item.symbol).font(.system(size: 15, weight: .semibold))
                                Text(item.title).font(.sarabun(15, .bold)).lineLimit(1)
                                if t == .daily, data.dailyUnsent {
                                    Circle().fill(Theme.warning).frame(width: 8, height: 8).accessibilityLabel("วันนี้ยังไม่ส่ง")
                                }
                            }
                            .foregroundStyle(on ? Theme.navy : Theme.projectTabInk)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background {
                                if on {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.surface)
                                        .shadow(color: Theme.navySolid.opacity(0.15), radius: 1.5, y: 1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(t)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("installTab.\(t.rawValue)")
                    }
                }
                .padding(4)
                .background(Theme.projectTabTrack, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("installTabs")
            .padding(.top, 12)
            // after the first layout: on appear the strip has no width yet
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                proxy.scrollTo(phoneTab, anchor: .center)
            }
            .onChange(of: phoneTab) { _, t in withAnimation(.snappy) { proxy.scrollTo(t, anchor: .center) } }
        }
    }

    // MARK: shared parts

    static func phoneCard<C: View>(padding: CGFloat = 16, @ViewBuilder _ content: () -> C) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: frame)
            .overlay(frame.strokeBorder(Theme.borderSubtle))
            .cardShadow()
    }

    func phoneCard<C: View>(padding: CGFloat = 16, @ViewBuilder _ content: () -> C) -> some View {
        Self.phoneCard(padding: padding, content)
    }

    static func cardHeading(_ title: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.sarabun(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            if let note { Text(note).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
        }
    }

    func cardHeading(_ title: String, note: String? = nil) -> some View {
        Self.cardHeading(title, note: note)
    }

    /// A tile of a 2 × 2 summary: label, value, note.
    static func statCell(_ label: String, _ value: String, ink: Color, note: String, valueSize: CGFloat = 26) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            Text(value).font(.sarabun(valueSize, .bold)).foregroundStyle(ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(note).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    func statCell(_ label: String, _ value: String, ink: Color, note: String, valueSize: CGFloat = 26) -> some View {
        Self.statCell(label, value, ink: ink, note: note, valueSize: valueSize)
    }

    /// Cells two by two inside one card, with hairlines between them.
    static func statGrid(_ cells: [AnyView]) -> some View {
        let rows = stride(from: 0, to: cells.count, by: 2).map { Array(cells[$0..<min($0 + 2, cells.count)]) }
        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        rows[r][c]
                            .overlay(alignment: .leading) { if c > 0 { Rectangle().fill(Theme.hairline).frame(width: 1) } }
                    }
                    if rows[r].count == 1 { Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .top) { if r > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) } }
            }
        }
    }

    func statGrid(_ cells: [AnyView]) -> some View {
        Self.statGrid(cells)
    }

    /// A small tile on the page's tint: label over a bold value.
    static func factTile(_ label: String, _ value: String, ink: Color = Theme.navy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.75)
            Text(value).font(.sarabun(17, .bold)).foregroundStyle(ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    func factTile(_ label: String, _ value: String, ink: Color = Theme.navy) -> some View {
        Self.factTile(label, value, ink: ink)
    }

    /// `‹ สัปดาห์ที่ n ›` over the week's dates.
    static func weekSwitcher(_ week: Date, shift: @escaping (Int) -> Void) -> some View {
        let end = RoutineReport.calendar.date(byAdding: .day, value: 6, to: week) ?? week
        let number = Calendar(identifier: .iso8601).component(.weekOfYear, from: end)
        return HStack(spacing: 0) {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary)
                    .frame(width: 48, height: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("สัปดาห์ก่อน")
            Rectangle().fill(Theme.borderSubtle).frame(width: 1)
            VStack(spacing: 0) {
                Text("สัปดาห์ที่ \(number)").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                Text(RoutineReport.thaiDate(week) + " – " + RoutineReport.thaiDate(end)).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            Rectangle().fill(Theme.borderSubtle).frame(width: 1)
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary)
                    .frame(width: 48, height: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("สัปดาห์ถัดไป")
        }
        .frame(height: 52)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    func weekSwitcher(_ week: Date, shift: @escaping (Int) -> Void) -> some View {
        Self.weekSwitcher(week, shift: shift)
    }

    /// `① ร่าง —— ② ส่ง —— ③ อนุมัติ`: steps before `current` done, `current` orange.
    static func stepLine(_ titles: [String], current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(titles.indices, id: \.self) { i in
                if i > 0 { Rectangle().fill(Theme.borderSubtle).frame(height: 1).frame(minWidth: 8) }
                HStack(spacing: 5) {
                    ZStack {
                        Circle().fill(i < current ? Theme.success : i == current ? Theme.warning : Theme.surface)
                        Circle().strokeBorder(i <= current ? .clear : Theme.borderSubtle)
                        if i < current {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                        } else {
                            Text("\(i + 1)").font(.sarabun(12, .bold)).foregroundStyle(i == current ? Theme.onPrimary : Theme.inkMuted)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(titles[i]).font(.sarabun(14, i == current ? .bold : .regular))
                        .foregroundStyle(i == current ? Theme.warningInk : i < current ? Theme.successInk : Theme.inkMuted).lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ขั้น \(min(current + 1, titles.count)) จาก \(titles.count) | " + (titles.indices.contains(current) ? titles[current] : "ครบ"))
    }

    func stepLine(_ titles: [String], current: Int) -> some View {
        Self.stepLine(titles, current: current)
    }

    static func toneChip(_ text: String, _ tone: InstallPageData.Tone) -> some View {
        chip(text, tone).fixedSize()
    }

    func toneChip(_ text: String, _ tone: InstallPageData.Tone) -> some View {
        Self.toneChip(text, tone)
    }
}

/// `ทีมและสิทธิ์`'s editor on iPhone: the job's own `JobAccessCard`, pushed from `ตั้งค่าเฉพาะโครงการ`.
struct PhoneAccessScreen: View {
    @Bindable var job: Job

    var body: some View {
        ScrollView {
            JobAccessCard(job: job).padding(16)
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .navigationTitle("ทีมและสิทธิ์")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
