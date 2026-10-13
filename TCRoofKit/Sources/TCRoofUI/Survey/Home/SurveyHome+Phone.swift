#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// iPhone survey home (docs/ui/pwa-solar-survey-iphone-v3): a header whose search button grows into the field, with a
/// bell; the nav `โครงการ | แผนงาน | บำรุงรักษา` with a filter button; the project cards, and the install and maintenance
/// overviews. The host's floating dock is the bottom safe-area inset, so the page scrolls behind it.
extension SurveyHomeView {
    var phonePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
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
            .padding(.horizontal, 16).padding(.top, 12)
            // 20 pt clear of the dock; the survey cards also clear the add button over it
            .padding(.bottom, page == .project && tab == .survey ? 82 : 20)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) { phoneHeader }
        .background(Theme.phonePage.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            if page == .project && tab == .survey { addButton.padding(.trailing, 20).padding(.bottom, 4) }
        }
    }

    // MARK: header

    /// The project page has the growing search and the host's bell; the settings page only its title. Pushed, it has
    /// a back button.
    @ViewBuilder var phoneHeader: some View {
        if page == .settings {
            TCPhoneSearchHeader(title: "PWA Setting", subtitle: nil, search: $search, isOpen: $searchOpen, showsSearch: false,
                                onBack: isPushed ? { dismiss() } : nil)
        } else {
            TCPhoneSearchHeader(title: title, subtitle: nil, search: $search, isOpen: $searchOpen, large: true,
                                bell: host.openNotifications.map { .init(unread: host.unread, action: $0) },
                                onBack: isPushed ? { dismiss() } : nil)
        }
    }

    // MARK: nav and the filter

    private enum NavItem { case project, plan, maintenance }

    /// `โครงการ` is the project list or, picked in the filter, the install overview; `แผนงาน` is a link to the host's
    /// plan page and never the selected segment.
    var navRow: some View {
        let items: [(NavItem, String)] = [(.project, "โครงการ")] + (host.openPlan == nil ? [] : [(.plan, "แผนงาน")]) + [(.maintenance, "บำรุงรักษา")]
        let selected = items.firstIndex { $0.0 == (tab == .maintenance ? .maintenance : .project) } ?? 0
        return HStack(spacing: 8) {
            TCCountSegments(items.map { .init($0.1) }, selection: Binding(get: { selected }, set: { i in
                switch items[i].0 {
                case .project: if tab == .maintenance { select(.survey) }
                case .plan: host.openPlan?()
                case .maintenance: select(.maintenance)
                }
            }), fontSize: 14)
            filterButton
        }
    }

    /// `ประเภทงาน`: the project list, the install overview or the maintenance overview.
    private func select(_ stage: JobStage) {
        withAnimation(reduceMotion ? nil : .snappy) { tab = stage }
    }

    /// A type other than `ทั้งหมด`, a status other than all, or a sort other than `แก้ไขล่าสุด`.
    var isFiltered: Bool { tab != .survey || filter != .all || sort != .updated }

    private var filterLabel: String {
        switch tab {
        case .survey: "กรองและเรียงงาน: \(filter.heading) \(shown.count) งาน · เรียง \(sort.title)"
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
        .popover(isPresented: $showFilter, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            filterPopover.presentationCompactAdaptation(.popover).presentationBackground(Theme.surface)
        }
    }

    private var filterPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("กรองและเรียง").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Button("ล้าง") { filter = .all; sort = .updated; select(.survey) }
                    .font(.sarabunFixed(13, .bold)).foregroundStyle(isFiltered ? Theme.primary : Theme.chevron)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .disabled(!isFiltered)
                    .accessibilityLabel("ล้างตัวกรองและการเรียง")
            }
            .frame(height: 32)
            popoverSection("ประเภทงาน") { typeRows }
            // the overviews have their own row filters
            if tab == .survey {
                popoverSection("สถานะงาน") { statusTiles }
                popoverSection("เรียงตาม") { sortSegments }
                Button { showFilter = false } label: {
                    Text("แสดง \(shown.count) งาน").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    /// Radio rows with a count and a tick on the selected one; picking a row closes the popover.
    private var typeRows: some View {
        let rows: [(JobStage, String, Int, String)] = [
            (.survey, "ทั้งหมด", model.jobs(in: .survey).count, "งาน"), (.install, "ติดตั้ง", installStations.count, "สถานี"),
            (.maintenance, "บำรุงรักษา", maintenanceStations.count, "สถานี")]
        return VStack(spacing: 0) {
            ForEach(rows, id: \.0) { stage, title, count, unit in
                let on = tab == stage
                Button { select(stage); showFilter = false } label: {
                    HStack(spacing: 10) {
                        Text(title).font(.sarabunFixed(14, on ? .bold : .medium)).foregroundStyle(Theme.navy)
                        Spacer(minLength: 6)
                        Text("\(count)").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted).monospacedDigit()
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
                            .frame(width: 18).opacity(on ? 1 : 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background { if on { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.rowSelected) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title) \(count) \(unit)")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
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

    /// 60 pt, the board's gradient, no shadow.
    private var addButton: some View {
        Button { showNew = true } label: {
            Image(systemName: "plus").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.onPrimary)
                .frame(width: 60, height: 60)
                .background(Theme.actionGradient, in: Circle())
        }
        .accessibilityLabel("งานสำรวจใหม่")
    }

    // MARK: DEBUG

    /// `-surveyHomeTab projects|maintenance` (`plan` is the host's), `-surveyHomeType all|install|maintenance`,
    /// `-surveyHomeSearch YES`, `-surveyHomeFilter YES|draft`, `-pwaMaintenanceFilter issue|pmSoon|all`.
    func applyDebugHome() {
        #if DEBUG
        let d = UserDefaults.standard
        guard compact, page == .project else { return }
        switch d.string(forKey: "surveyHomeTab") {
        case "projects": tab = .survey
        case "maintenance": tab = .maintenance
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
#endif
