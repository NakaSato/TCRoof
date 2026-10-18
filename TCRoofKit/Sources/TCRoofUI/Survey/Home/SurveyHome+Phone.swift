#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// The PWA project home (docs/ui/pwa-solar-survey-iphone-v3, and on iPad docs/ui/pwa-solar-survey-ipad-v3): a header
/// whose search button grows into the field, with a bell; the nav `โครงการ | แผนงาน | บำรุงรักษา` with a filter button; the
/// project cards, and the install and maintenance overviews. The iPad has the same parts at 63 pt margins, in three
/// columns (two in portrait). The host's floating dock is the bottom safe-area inset, so the page scrolls behind it.
extension SurveyHomeView {
    /// The page's side margin.
    var margin: CGFloat { compact ? 16 : 63 }

    /// iPad (docs/ui/pwa-plan-ipad): the host's plan page under the nav, in place of the scrolling page.
    var showsPlan: Bool { !compact && planOpen && page == .project && host.planBody != nil }

    var homePage: some View {
        Group {
            if showsPlan, let plan = host.planBody {
                VStack(spacing: 0) {
                    navRow.padding(.horizontal, margin).padding(.top, 20)
                    plan(search)
                }
            } else {
                homeScroll
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { phoneHeader }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .background(Theme.phonePage.ignoresSafeArea())
        // iPad: the filter list hangs under its button, in the page
        .overlayPreferenceValue(FilterAnchorKey.self) { anchor in
            GeometryReader { g in
                if !compact, showFilter, !showsPlan, let anchor { padFilterPanel(under: g[anchor], in: g.size) }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // iPad: 116 pt above the screen's edge, over the dock's 98
            if page == .project && tab == .survey && !showsPlan { addButton.padding(.trailing, compact ? 20 : margin).padding(.bottom, compact ? 4 : 18) }
        }
    }

    private var homeScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                if let message { Label(message, systemImage: "checkmark.circle").font(.sarabunFixed(13)).foregroundStyle(Paper.tick) }
                if page == .settings {
                    settingsGroups
                } else {
                    navRow
                    switch tab {
                    case .survey: surveyList
                    case .install: installOverview
                    case .maintenance: maintenanceOverview
                    }
                }
            }
            .padding(.horizontal, margin).padding(.top, compact ? 12 : 20)
            // 20 pt clear of the dock; the survey cards also clear the add button over it
            .padding(.bottom, page == .project && tab == .survey ? (compact ? 82 : 98) : 20)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: header

    /// The project page has the growing search and the host's bell; the settings page only its title. Pushed, it has
    /// a back button.
    @ViewBuilder var phoneHeader: some View {
        if page == .settings {
            TCPhoneSearchHeader(title: "PWA Setting", subtitle: nil, search: $search, isOpen: $searchOpen, showsSearch: false,
                                onBack: isPushed ? { dismiss() } : nil)
        } else {
            TCPhoneSearchHeader(title: title, subtitle: nil, search: $search, isOpen: $searchOpen, large: true, wide: !compact,
                                bell: host.openNotifications.map { .init(unread: host.unread, action: $0) },
                                settings: host.openSettings,
                                onBack: isPushed ? { dismiss() } : nil)
        }
    }

    // MARK: nav and the filter

    private enum NavItem { case project, plan, maintenance }

    /// `โครงการ` is the project list or, picked in the filter, the install overview. `แผนงาน` on iPhone is a link to
    /// the host's plan page and never the selected segment; on iPad it is the plan page under this nav, which has no
    /// filter button.
    var navRow: some View {
        let items: [(NavItem, String)] = [(.project, "โครงการ")] + (host.openPlan == nil ? [] : [(.plan, "แผนงาน")]) + [(.maintenance, "บำรุงรักษา")]
        let current: NavItem = showsPlan ? .plan : tab == .maintenance ? .maintenance : .project
        let selected = items.firstIndex { $0.0 == current } ?? 0
        return HStack(spacing: 8) {
            TCCountSegments(items.map { .init($0.1) }, selection: Binding(get: { selected }, set: { i in
                switch items[i].0 {
                case .project: if tab == .maintenance || showsPlan { select(tab == .maintenance ? .survey : tab) }
                case .plan:
                    if !compact, host.planBody != nil {
                        showFilter = false
                        withAnimation(reduceMotion ? nil : .snappy) { planOpen = true }
                    } else {
                        host.openPlan?()
                    }
                case .maintenance: select(.maintenance)
                }
            }), fontSize: 14)
            if !showsPlan { filterButton }
        }
    }

    /// `ประเภทงาน`: the project list, the install overview or the maintenance overview.
    private func select(_ stage: JobStage) {
        withAnimation(reduceMotion ? nil : .snappy) { tab = stage; planOpen = false }
    }

    /// A type other than `ทั้งหมด`, a status other than all, or a sort other than `แก้ไขล่าสุด`.
    var isFiltered: Bool { tab != .survey || filter != .all || sort != .updated || mineOn }

    private var filterLabel: String {
        switch tab {
        case .survey: "กรองและเรียงงาน: \(mineOn ? "งานของฉัน · " : "")\(filter.heading) \(shown.count) งาน · เรียง \(sort.title)"
        case .install: "กรองงาน: ติดตั้ง \(installStations.count) สถานี"
        case .maintenance: "กรองงาน: บำรุงรักษา \(maintenanceStations.count) สถานี"
        }
    }

    private var filterButton: some View {
        let fill = showFilter ? Theme.primarySoft : isFiltered ? Theme.navySolid : Theme.surface
        return Button { showFilter.toggle() } label: {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 17, weight: .bold))
                .foregroundStyle(isFiltered && !showFilter ? Theme.onPrimary : Theme.navySolid)
                .frame(width: 44, height: 44)
                .background(fill, in: Circle())
                .overlay {
                    if showFilter { Circle().strokeBorder(Theme.primary) } else if !isFiltered { Circle().strokeBorder(Theme.borderSubtle) }
                }
                .overlay(alignment: .topTrailing) {
                    if isFiltered {
                        Circle().fill(Theme.warning).frame(width: 8, height: 8)
                            .background(Circle().fill(fill).padding(-2))
                            .padding(.top, 6).padding(.trailing, 7)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filterLabel)
        .anchorPreference(key: FilterAnchorKey.self, value: .bounds) { $0 }
        // iPhone: a system popover. iPad: `padFilterPanel`, drawn in the page at the board's size
        .popover(isPresented: Binding(get: { compact && showFilter }, set: { showFilter = $0 }), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            filterPanel.presentationCompactAdaptation(.popover).presentationBackground(Theme.surface)
        }
    }

    /// iPad (docs/ui/pwa-solar-survey-ipad-v3 FIX-01 §3): the 248 pt list under the filter button, radius 16 with a
    /// 1 pt border and an arrow on the button, its right edge on the button's. A tap outside closes it.
    private func padFilterPanel(under button: CGRect, in area: CGSize) -> some View {
        let width: CGFloat = 248
        let left = min(max(button.maxX - width, 8), area.width - width - 8)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { showFilter = false }
                .accessibilityLabel("ปิดตัวกรอง").accessibilityAddTraits(.isButton)
            VStack(alignment: .leading, spacing: -1) {
                FilterArrow(closed: true).fill(Theme.surface)
                    .overlay(FilterArrow(closed: false).stroke(Theme.borderOutdoor, lineWidth: 1))
                    .frame(width: 18, height: 9)
                    .offset(x: button.midX - left - 9)
                    .zIndex(1)
                filterList
                    .background(Theme.surface, in: shape)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Theme.borderOutdoor))
            }
            .compositingGroup()
            .shadow(color: Theme.navy.opacity(0.16), radius: 14, y: 8)
            .offset(x: left, y: button.maxY + 2)
        }
        .transition(.opacity)
    }

    private var clearButton: some View {
        Button("ล้าง") { filter = .all; sort = .updated; onlyMine = false; select(.survey) }
            .font(.sarabunFixed(13, .bold)).foregroundStyle(isFiltered ? Theme.primary : Theme.chevron)
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(!isFiltered)
            .accessibilityLabel("ล้างตัวกรองและการเรียง")
    }

    /// iPhone: tiles and segments, closed by `แสดง n งาน`.
    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("กรองและเรียง").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                clearButton
            }
            .frame(height: 32)
            popoverSection("ประเภทงาน") { typeRows }
            // the overviews have their own row filters
            if tab == .survey {
                if host.mine != nil { popoverSection("ผู้รับผิดชอบ") { mineRow } }
                popoverSection("สถานะงาน") { statusTiles }
                popoverSection("เรียงตาม") { sortSegments }
                Button { showFilter = false } label: {
                    Text("แสดง \(shown.count) งาน").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if let openSettings = host.openSettings {
                Button {
                    showFilter = false
                    openSettings()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape").font(.system(size: 14, weight: .semibold))
                        Text("ตั้งค่าโครงการ PWA").font(.sarabunFixed(13, .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    }
                    .foregroundStyle(Theme.navy)
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pwaHome.filterSettings")
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    /// iPad (docs/ui/pwa-solar-survey-ipad-v3 §5): a 248 pt list of 44 pt rows; a row applies at once.
    private var filterList: some View {
        VStack(alignment: .leading, spacing: 0) {
            listTitle("ประเภทงาน").padding(.top, 10).padding(.bottom, 2)
            typeRows
            // the overviews have their own row filters
            if tab == .survey {
                if host.mine != nil {
                    listDivider
                    listTitle("ผู้รับผิดชอบ").padding(.top, 6).padding(.bottom, 2)
                    mineRow
                }
                listDivider
                HStack(spacing: 0) {
                    listTitle("สถานะงาน")
                    Spacer(minLength: 0)
                    clearButton.padding(.trailing, 4)
                }
                statusRows
                listDivider
                listTitle("เรียงตาม").padding(.top, 6).padding(.bottom, 2)
                sortRows
            }
        }
        .padding(.top, 4).padding(.bottom, 6)
        .frame(width: 248)
    }

    private func listTitle(_ title: String) -> some View {
        Text(title).font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 14)
    }

    private var listDivider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 14).padding(.vertical, 4)
    }

    /// A radio row of the filter: a status dot, the title, a count and a tick on the selected one. Rounded inside the
    /// iPhone panel, edge to edge in the iPad list.
    private func filterRow(_ title: String, count: Int? = nil, countInk: Color = Theme.inkMuted, dot: Color? = nil, on: Bool,
                           label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(title).font(.sarabunFixed(14, on ? .bold : .medium)).foregroundStyle(Theme.navy)
                Spacer(minLength: 6)
                if let count { Text("\(count)").font(.sarabunFixed(13, .bold)).foregroundStyle(countInk).monospacedDigit() }
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
                    .frame(width: 18).opacity(on ? 1 : 0)
            }
            .padding(.horizontal, compact ? 10 : 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background { if on { RoundedRectangle(cornerRadius: compact ? 10 : 0, style: .continuous).fill(Theme.rowSelected) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// Radio rows with a count and a tick on the selected one; picking a row closes the popover.
    private var typeRows: some View {
        let rows: [(JobStage, String, Int, String)] = [
            (.survey, "ทั้งหมด", model.jobs(in: .survey).count, "งาน"), (.install, "ติดตั้ง", installStations.count, "สถานี"),
            (.maintenance, "บำรุงรักษา", maintenanceStations.count, "สถานี")]
        return VStack(spacing: 0) {
            ForEach(rows, id: \.0) { stage, title, count, unit in
                filterRow(title, count: count, on: tab == stage, label: "\(title) \(count) \(unit)") { select(stage); showFilter = false }
            }
        }
    }

    /// `งานของฉัน`: a row that turns the filter on and off, with how many of the surveys are mine.
    private var mineRow: some View {
        let n = model.jobs(in: .survey).filter(isMine).count
        return filterRow("งานของฉัน", count: n, on: onlyMine, label: onlyMine ? "งานของฉัน \(n) งาน · เปิดอยู่" : "งานของฉัน \(n) งาน") {
            onlyMine.toggle()
        }
        .accessibilityIdentifier("pwaHome.mine")
    }

    /// iPad: the statuses as rows.
    private var statusRows: some View {
        let jobs = searched
        return VStack(spacing: 0) {
            ForEach(Filter.allCases, id: \.self) { f in
                let n = jobs.filter { matches($0, f) }.count
                filterRow(f.heading, count: n, countInk: f == .unsynced && n > 0 ? Theme.pending : Theme.inkMuted, dot: statusDot(f),
                          on: filter == f, label: "\(f.heading) \(n) งาน") { filter = f }
            }
        }
    }

    /// iPad: the sorts as rows.
    private var sortRows: some View {
        VStack(spacing: 0) {
            ForEach(Sort.allCases, id: \.self) { s in filterRow(s.title, on: sort == s, label: s.title) { sort = s } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("เรียงตาม")
    }

    private func popoverSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.sarabunFixed(11, .bold)).foregroundStyle(Theme.inkMuted)
            content()
        }
    }

    private func statusDot(_ f: Filter) -> Color {
        switch f {
        case .all: Theme.primary
        case .active: Theme.primaryLight
        case .draft: Theme.chevron
        case .unsynced: Theme.warning
        }
    }

    private var statusTiles: some View {
        let jobs = searched
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible())], spacing: 6) {
            ForEach(Filter.allCases, id: \.self) { f in
                let on = filter == f, n = jobs.filter { matches($0, f) }.count
                Button { filter = f } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(on ? Theme.onPrimary : statusDot(f)).frame(width: 8, height: 8)
                            Text(f.heading).font(.sarabunFixed(13, .bold)).lineLimit(1)
                        }
                        Text("\(n)").font(.sarabunFixed(20, .bold)).monospacedDigit()
                    }
                    .foregroundStyle(on ? Theme.onPrimary : f == .unsynced && n > 0 ? Theme.pending : Theme.navySolid)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(on ? Theme.navySolid : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { if !on { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(f.heading) \(n) งาน")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private var sortSegments: some View {
        HStack(spacing: 0) {
            ForEach(Sort.allCases, id: \.self) { s in
                let on = sort == s
                Button { sort = s } label: {
                    Text(s.title).font(.sarabunFixed(12.5, on ? .bold : .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(on ? Theme.navySolid : Theme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background { if on { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.surface) } }
                        .overlay { if on { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.borderSubtle) } }
                        // the track's 3 pt padding is part of the 44 pt hit area
                        .padding(.vertical, 3).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 3)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("เรียงตาม")
    }

    // MARK: survey list

    @ViewBuilder var surveyList: some View {
        // the heading names the status once the list is narrowed
        if filter != .all || !search.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(spacing: 8) {
                Text(filter.heading).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Text("\(shown.count) งาน").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            }
            .padding(.top, 2)
            .accessibilityElement(children: .combine)
        }
        if shown.isEmpty { empty } else { grid }
    }

    /// 60 pt (iPad 64), the board's gradient, no shadow.
    private var addButton: some View {
        Button { showNew = true } label: {
            Image(systemName: "plus").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.onPrimary)
                .frame(width: compact ? 60 : 64, height: compact ? 60 : 64)
                .background(Theme.actionGradient, in: Circle())
        }
        .accessibilityLabel("งานสำรวจใหม่")
    }

    // MARK: DEBUG

    /// `-surveyHomeTab projects|plan|maintenance` (on iPhone `plan` is the host's push), `-surveyHomeType all|install|maintenance`,
    /// `-surveyHomeSearch YES`, `-surveyHomeFilter YES|draft`, `-pwaMaintenanceFilter issue|pmSoon|all`.
    func applyDebugHome() {
        #if DEBUG
        let d = UserDefaults.standard
        guard page == .project else { return }
        // `-surveyCompleteJob YES` (UI tests): a new survey filled to 100% (docNo `UITEST-MOVE`), replacing the last one;
        // `partial` leaves it unfinished
        let seed = d.string(forKey: "surveyCompleteJob")
        if seed == "partial" || d.bool(forKey: "surveyCompleteJob") {
            for j in model.jobs where j.docNo == "UITEST-MOVE" { model.delete(j.id) }
            let t = JobTemplate.all[2]
            var j = model.create(t, engineer: "สมชาย")
            if seed != "partial" { for g in Schema.jobGroups { for f in g.fields where f.isRequired(j.values) { j.values[f.id] = .text("1") } } }
            j.values["docNo"] = .text("UITEST-MOVE"); j.values["projectName"] = .text("ทดสอบย้ายติดตั้ง")
            // `-surveyCompleteJobLink <syncID>`: linked to that TCRoof job, whose status the move then changes
            j.jobSyncID = d.string(forKey: "surveyCompleteJobLink")
            model.update(j)
        }
        switch d.string(forKey: "surveyHomeTab") {
        case "projects": tab = .survey
        case "maintenance": tab = .maintenance
        // iPad: the plan page under the nav, with the plan's own search flag
        case "plan":
            planOpen = true
            if !compact, d.bool(forKey: "pwaPlanSearch") { searchOpen = true }
        default: break
        }
        switch d.string(forKey: "surveyHomeType") {
        case "all": tab = .survey
        case "install": tab = .install
        case "maintenance": tab = .maintenance
        default: break
        }
        if let f = d.string(forKey: "pwaMaintenanceFilter").flatMap(MaintenanceOverview.RowFilter.init) { maintenanceFilter = f }
        if d.bool(forKey: "surveyHomeSearch") { searchOpen = true }
        switch d.string(forKey: "surveyHomeFilter") {
        case "draft": tab = .survey; filter = .draft; sort = .progress
        // the popover opens on the type the other flags picked
        case .some(let v) where (v as NSString).boolValue: showFilter = true
        default: break
        }
        #endif
    }
}
/// Where the filter button is, for the iPad's filter list under it.
private struct FilterAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

/// The filter list's arrow, pointing up at the button: the triangle, or with `closed` off only its two sides.
private struct FilterArrow: Shape {
    let closed: Bool

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        if closed { p.closeSubpath() }
        return p
    }
}
#endif
