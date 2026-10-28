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
        case .docs(let package, let paper): StationDocsScreen(job: job, package: package, paper: paper.flatMap(StationDocs.kind))
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
            if !data.docs.isEmpty { phoneDocsCard(data.docs) }
            if let s = data.site { phoneSitePanel(s) }
        case .daily: phoneDailyTab(dailyData)
        case .request: phoneRequestTab()
        case .weekly: phoneWeeklyTab()
        case .iec: phoneIECTab()
        case .docs: phoneDocsTab()
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
                Text(data.title).font(.sarabunFixed(19, .bold)).lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
                Text(phoneSubtitle(data)).font(.sarabunFixed(13)).opacity(0.92).lineLimit(1)
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
                            if t != .plan { planEditing = false }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: item.symbol).font(.system(size: 15, weight: .semibold))
                                Text(item.title).font(.sarabunFixed(15, .bold)).lineLimit(1)
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

    func phoneCard<C: View>(padding: CGFloat = 16, @ViewBuilder _ content: () -> C) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: frame)
            .overlay(frame.strokeBorder(Theme.borderSubtle))
            .cardShadow()
    }

    func cardHeading(_ title: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            if let note { Text(note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
        }
    }

    /// A tile of a 2 × 2 summary: label, value, note.
    func statCell(_ label: String, _ value: String, ink: Color, note: String, valueSize: CGFloat = 26) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            Text(value).font(.sarabunFixed(valueSize, .bold)).foregroundStyle(ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    /// Cells two by two inside one card, with hairlines between them.
    func statGrid(_ cells: [AnyView]) -> some View {
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

    /// A small tile on the page's tint: label over a bold value.
    func factTile(_ label: String, _ value: String, ink: Color = Theme.navy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.75)
            Text(value).font(.sarabunFixed(17, .bold)).foregroundStyle(ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// `‹ สัปดาห์ที่ n ›` over the week's dates.
    func weekSwitcher(_ week: Date, shift: @escaping (Int) -> Void) -> some View {
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
                Text("สัปดาห์ที่ \(number)").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Text(RoutineReport.thaiDate(week) + " – " + RoutineReport.thaiDate(end)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
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

    /// `① ร่าง —— ② ส่ง —— ③ อนุมัติ`: steps before `current` done, `current` orange.
    func stepLine(_ titles: [String], current: Int) -> some View {
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
                            Text("\(i + 1)").font(.sarabunFixed(12, .bold)).foregroundStyle(i == current ? Theme.onPrimary : Theme.inkMuted)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(titles[i]).font(.sarabunFixed(14, i == current ? .bold : .regular))
                        .foregroundStyle(i == current ? Theme.warningInk : i < current ? Theme.successInk : Theme.inkMuted).lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ขั้น \(min(current + 1, titles.count)) จาก \(titles.count) | " + (titles.indices.contains(current) ? titles[current] : "ครบ"))
    }

    func toneChip(_ text: String, _ tone: InstallPageData.Tone) -> some View {
        chip(text, tone).fixedSize()
    }

    // MARK: ภาพรวม

    private func phoneKPIs(_ data: InstallPageData) -> some View {
        let all = cells(data), kpis = all.filter { $0.label != "ต้องดำเนินการ" }
        let open = data.actions
        return VStack(spacing: 0) {
            if !kpis.isEmpty {
                statGrid(kpis.map { AnyView(statCell($0.label, $0.value, ink: $0.ink, note: $0.note)) })
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            Button { if !open.isEmpty { sheet = .actions } } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ต้องดำเนินการ").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(open.isEmpty ? "ไม่มี" : "\(open.count) เรื่อง").font(.sarabunFixed(22, .bold))
                                .foregroundStyle(open.isEmpty ? Theme.successInk : Theme.pending).fixedSize()
                            Text(open.prefix(3).map(\.title).joined(separator: " | ")).font(.sarabunFixed(13))
                                .foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if !open.isEmpty {
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.pending)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(open.isEmpty)
            .accessibilityIdentifier("install.actions")
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        .cardShadow()
    }

    /// The tiles that are one of this page's tabs switch to it; the others list their items, as on iPad.
    private func openTile(_ t: InstallPageData.DocTile) {
        switch t.id {
        case "daily": phoneTab = .daily
        case "weekly": phoneTab = .weekly
        case "commissioning": phoneTab = .iec
        case "grid", "handover": phoneTab = .docs
        default: sheet = .doc(t.id)
        }
    }

    private func phoneDocsCard(_ tiles: [InstallPageData.DocTile]) -> some View {
        phoneCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeading("เอกสารโครงการ", note: "แตะเพื่อดูรายละเอียด")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(tiles) { t in
                        Button { openTile(t) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Circle().fill(Self.ink(t.tone)).frame(width: 8, height: 8)
                                    Text(t.title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.75)
                                }
                                chip(t.chip, t.tone).padding(.leading, 16)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("installDoc.\(t.id)")
                    }
                }
            }
        }
    }

    // MARK: site panel

    private func phoneSitePanel(_ s: InstallPageData.Site) -> some View {
        let tabs: [SiteTab] = [.info] + (s.risks.isEmpty ? [] : [.risk]) + (s.labour.isEmpty ? [] : [.labour])
        let current = tabs.contains(siteTab) ? siteTab : .info
        return phoneCard {
            VStack(alignment: .leading, spacing: 12) {
                if tabs.count > 1 {
                    TCCountSegments(tabs.map { t in
                        switch t {
                        case .info: .init("ข้อมูลหน้างาน")
                        case .risk: .init("ความเสี่ยง", count: s.risks.count)
                        case .labour: .init("แรงงาน")
                        }
                    }, selection: Binding(get: { tabs.firstIndex(of: current) ?? 0 }, set: { siteTab = tabs[$0] }), fontSize: 15)
                } else {
                    cardHeading("ข้อมูลหน้างาน")
                }
                Text("ณ " + ThaiFormat.numericDate.string(from: s.asOf)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                switch current {
                case .info: phoneSiteInfo(s)
                case .risk: phoneSiteRisks(s)
                case .labour: phoneSiteLabour(s)
                }
            }
        }
    }

    private func phoneSiteInfo(_ s: InstallPageData.Site) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !s.tasks.isEmpty {
                Text("ความคืบหน้าตามงาน MP").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                ForEach(Array(s.tasks.enumerated()), id: \.offset) { _, t in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(t.title).font(.sarabunFixed(15)).foregroundStyle(Theme.navy).lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(Int(t.percent.rounded()))%").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                        }
                        Capsule().fill(Theme.track).frame(height: 6)
                            .overlay(alignment: .leading) {
                                GeometryReader { g in
                                    Capsule().fill(t.percent >= 99.95 ? Theme.success : Theme.primary)
                                        .frame(width: g.size.width * min(max(t.percent, 0), 100) / 100)
                                }
                            }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                if s.hasReports {
                    siteTile("แรงงานวันนี้", s.peopleToday.map { "\($0) คน" } ?? "ยังไม่บันทึก", s.peopleToday == nil ? Theme.inkMuted : Theme.navy,
                             "สะสม \(s.manDays) man-day")
                }
                siteTile("รายงานส่งแล้ว", "\(s.reportsSent)/\(s.workingDaysSoFar) วัน",
                         s.reportsSent >= s.workingDaysSoFar ? Theme.successInk : Theme.warningInk, "วันทำงานถึงวันนี้")
                if s.hasReports {
                    siteTile("ปัญหาที่เปิดอยู่", s.issues.isEmpty ? "ไม่มี" : "\(s.issues.count) เรื่อง",
                             s.issues.isEmpty ? Theme.successInk : Theme.warningInk, s.issues.first?.description ?? "จากรายงานล่าสุด")
                    siteTile("ฝนตก", "\(s.rainHours) ชม.", Theme.navy, "รวมจากรายงานประจำวัน")
                }
            }
        }
    }

    private func siteTile(_ label: String, _ value: String, _ ink: Color, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabunFixed(20, .bold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func phoneSiteRisks(_ s: InstallPageData.Site) -> some View {
        VStack(spacing: 10) {
            ForEach(s.risks) { r in
                HStack(alignment: .top, spacing: 12) {
                    priorityChip(r.level == .high ? .danger : r.level == .medium ? .warn : .idle, r.level.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                        if !r.prevention.isEmpty {
                            Text("รับมือ: " + r.prevention).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            Text("จากคำขอรายสัปดาห์นี้").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func phoneSiteLabour(_ s: InstallPageData.Site) -> some View {
        let top = max(s.labour.map { max($0.plan ?? 0, $0.actual ?? 0) }.max() ?? 1, 1)
        let chart: CGFloat = 130
        let today = RoutineReport.calendar.startOfDay(for: s.asOf)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if s.plannedManDays != nil { swatch(Theme.track, "แผน") }
                swatch(Theme.primary, "จริง")
                Spacer(minLength: 6)
                Text("สะสม \(s.manDays) man-day" + (s.plannedManDays.map { " | แผน \($0)" } ?? ""))
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(s.labour) { d in
                    VStack(spacing: 3) {
                        Text((d.actual ?? d.plan).map(String.init) ?? "").font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.navy).frame(height: 14)
                        ZStack(alignment: .bottom) {
                            if let p = d.plan { RoundedRectangle(cornerRadius: 3).fill(Theme.track).frame(height: chart * CGFloat(p) / CGFloat(top)) }
                            if let a = d.actual {
                                RoundedRectangle(cornerRadius: 3).fill(Theme.primary).frame(height: chart * CGFloat(a) / CGFloat(top))
                                    .padding(.horizontal, d.plan == nil ? 0 : 3)
                            }
                        }
                        .frame(height: chart, alignment: .bottom)
                        Text("\(RoutineReport.calendar.component(.day, from: d.date))").font(.sarabunFixed(11))
                            .foregroundStyle(d.date == today ? Theme.dangerText : InstallPlan.isSunday(d.date) ? Theme.survey : Theme.inkMuted)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ThaiFormat.dayMonth.string(from: d.date))
                    .accessibilityValue([d.plan.map { "แผน \($0) คน" }, d.actual.map { "จริง \($0) คน" }].compactMap { $0 }.joined(separator: " | "))
                }
            }
        }
    }

    func swatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 12)
            Text(title).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        }
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
