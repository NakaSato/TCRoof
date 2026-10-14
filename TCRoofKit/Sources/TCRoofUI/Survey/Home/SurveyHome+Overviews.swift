#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// The survey home's `งานติดตั้ง` and `บำรุงรักษา` overviews (docs/ui/pwa-solar-survey-iphone-v2 §4–5): a summary card, row
/// filters and one row per station. On iPad (docs/ui/pwa-solar-survey-ipad-v3 §7) the summary's parts stand side by
/// side and the rows are in three columns. No shadows.
extension SurveyHomeView {
    // MARK: data

    /// The host's stations, then the installation jobs here that it didn't cover, from their `InstallInfo` (no plan).
    var installStations: [InstallStationSummary] {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "surveyHomeDemo") == "install" { return PWAOverviewDemo.install }
        #endif
        let given = host.installStations ?? []
        // a station the host has handed over is no installation here either
        let ids = Set(given.map(\.id) + host.maintenanceStations.map(\.id))
        let local = model.jobs(in: .install).filter { j in !(j.jobSyncID.map(ids.contains) ?? false) }.map { j in
            let info = j.install ?? InstallInfo(movedAt: j.updated)
            return InstallStationSummary(id: j.id.uuidString, name: j.projectName.isEmpty ? "ยังไม่ได้ตั้งชื่อโครงการ" : j.projectName,
                                         kWp: Double(j.values.text("capacity").trimmingCharacters(in: .whitespaces)) ?? 0,
                                         actual: Double(info.percent), currentTask: info.currentStep ?? "ส่งมอบแล้ว",
                                         contractor: info.team, dueDate: info.dueDate)
        }
        return given + local
    }

    var maintenanceStations: [MaintenanceStationSummary] {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "surveyHomeDemo") == "maintenance" { return PWAOverviewDemo.maintenance }
        #endif
        let given = host.maintenanceStations
        let ids = Set(given.map(\.id))
        // no monitoring feed yet: a job handed over here has no energy or PR to show
        let local = model.jobs(in: .maintenance).filter { j in !(j.jobSyncID.map(ids.contains) ?? false) }.map { j in
            MaintenanceStationSummary(id: j.id.uuidString, name: j.projectName.isEmpty ? "ยังไม่ได้ตั้งชื่อโครงการ" : j.projectName,
                                      kWp: Double(j.values.text("capacity").trimmingCharacters(in: .whitespaces)) ?? 0,
                                      status: .normal, note: "ยังไม่มีข้อมูลการผลิต")
        }
        return given + local
    }

    /// Hands a station of the install overview over: its jobs here, and the host's station.
    func addToMaintenance(_ s: InstallStationSummary) {
        for j in model.jobs(in: .install) where j.id.uuidString == s.id || j.jobSyncID == s.id { model.moveToMaintenance(j.id) }
        host.handOver?(s.id)
    }

    private func returnToInstall(_ s: MaintenanceStationSummary) {
        for j in model.jobs(in: .maintenance) where j.id.uuidString == s.id || j.jobSyncID == s.id { model.moveBackToInstall(j.id) }
        host.returnToInstall?(s.id)
    }

    private var maintenanceTasks: [MaintenanceTask] {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "surveyHomeDemo") == "maintenance" { return PWAOverviewDemo.tasks }
        #endif
        return host.maintenanceTasks
    }

    var threshold: Double { model.settings.behindThreshold }

    func number(_ v: Double, digits: Int = 2) -> String {
        v.formatted(.number.precision(.fractionLength(0...digits)).locale(Locale(identifier: "en_US")))
    }

    func dayMonth(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: d)
        return "\(c.day ?? 0)/\(c.month ?? 0)"
    }

    private func card(_ content: some View, padding: EdgeInsets) -> some View {
        content.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private var summaryPadding: EdgeInsets {
        compact ? EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14) : EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    }
    private var rowPadding: EdgeInsets {
        compact ? EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12) : EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)
    }

    /// The summary's three parts: one under another on iPhone; on iPad the board's columns 330 | 300 | the rest.
    @ViewBuilder private func summaryParts(_ head: some View, tiles: some View, hasTiles: Bool = true, rest: some View) -> some View {
        if compact {
            head
            tiles
            rest
        } else {
            HStack(alignment: .top, spacing: 20) {
                head.frame(width: 330, alignment: .leading)
                if hasTiles { tiles.frame(width: 300) }
                rest.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// iPad: the number of rows shown stands right of the row filters.
    @ViewBuilder private func rowFilters(_ pills: some View, count: Int, note: String? = nil) -> some View {
        if compact {
            pills
        } else {
            HStack(spacing: 12) {
                pills
                Text(["\(count) สถานี", note ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).monospacedDigit().fixedSize()
            }
        }
    }

    /// The station rows: one under another on iPhone, three columns on iPad.
    @ViewBuilder private func stationRows(@ViewBuilder _ rows: () -> some View) -> some View {
        if compact {
            rows()
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3), spacing: 16) { rows() }
        }
    }

    private func noRows(_ text: String) -> some View {
        Text(text).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity).padding(.vertical, 12)
    }

    /// Installation or maintenance overview with nothing in it yet.
    var stageEmpty: some View {
        VStack(spacing: 8) {
            Text(tab == .install ? "ยังไม่มีงานติดตั้งในเครื่องนี้" : "ยังไม่มีงานบำรุงรักษา").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            Text(tab == .install ? "กด \"เพิ่มโครงการ\" เพื่อดึงงานสำรวจที่ครบ 100% มาเป็นงานติดตั้ง"
                 : "กด \"เพิ่มโครงการบำรุงรักษา\" เพื่อย้ายงานติดตั้งที่ส่งมอบแล้วมาที่นี่")
                .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: compact ? 280 : 520)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderControl.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    // MARK: งานติดตั้ง

    @ViewBuilder var installOverview: some View {
        let stations = installStations
        if stations.isEmpty {
            stageEmpty
        } else {
            let totals = InstallOverview.totals(stations, threshold: threshold)
            // with no MP plan anywhere nothing is behind, so start on every station
            let rowFilter = installFilter ?? (totals.plan == nil ? .all : .behind)
            let rows = InstallOverview.rows(stations, filter: rowFilter, contractor: contractor, threshold: threshold)
            card(installSummary(stations, totals), padding: summaryPadding)
            rowFilters(installFilters(stations, selected: rowFilter), count: rows.count, note: contractor)
            stationRows {
                ForEach(rows) { s in
                    Button { openStation(s) } label: {
                        if compact { card(installRow(s), padding: rowPadding) } else { card(padInstallRow(s), padding: rowPadding) }
                    }
                    .buttonStyle(.plain)
                }
            }
            if rows.isEmpty { noRows("ไม่มีสถานีในตัวกรองนี้") }
        }
        addInstallButton
    }

    /// The add button is over the survey list only, so adding an installation project is a row under the stations.
    private var addInstallButton: some View {
        Button { showInstallPicker = true } label: {
            Label("เพิ่มโครงการติดตั้ง", systemImage: "plus").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func openStation(_ s: InstallStationSummary) {
        // iPad: a host station opens the host's install tracking page, even when a survey job here is linked to it
        if !compact, let open = host.openStation, host.installStations?.contains(where: { $0.id == s.id }) == true {
            open(s)
            return
        }
        if let j = model.jobs(in: .install).first(where: { $0.id.uuidString == s.id || $0.jobSyncID == s.id }) {
            lastOpened = j.id.uuidString
            tracking = j.id
        } else {
            host.openStation?(s)
        }
    }

    private func installSummary(_ stations: [InstallStationSummary], _ t: InstallOverview.Totals) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            summaryParts(installHead(t), tiles: installTiles(t), hasTiles: t.plan != nil,
                         rest: contractorGrid(InstallOverview.contractors(stations, threshold: threshold)))
            if t.reporting > 0 { dailyStrip(t) }
        }
    }

    private func installHead(_ t: InstallOverview.Totals) -> some View {
        HStack(spacing: 12) {
            TCPlanRing(actual: Double(t.actual) / 100, plan: t.plan.map { Double($0) / 100 })
            VStack(alignment: .leading, spacing: 0) {
                Text("กำลังติดตั้ง \(t.count) สถานี").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Text("\(number(t.kWp, digits: 1)) kWp · เฉลี่ย \(t.actual)%" + (t.plan.map { " / แผน \($0)%" } ?? ""))
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                if let plan = t.plan {
                    Text(t.actual >= plan ? "ภาพรวมตามแผน" : "ภาพรวมช้ากว่าแผน \(plan - t.actual)%")
                        .font(.sarabunFixed(13, .bold)).foregroundStyle(t.actual >= plan ? Theme.successText : Theme.dangerText)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func installTiles(_ t: InstallOverview.Totals) -> some View {
        if t.plan != nil {
            HStack(spacing: 6) {
                TCStatTile("\(t.behind)", "ช้ากว่าแผน", tone: .red, large: !compact)
                TCStatTile("\(t.onPlan)", "ตามแผน", tone: .blue, large: !compact)
                TCStatTile("\(t.ahead)", "เร็วกว่าแผน", tone: .green, large: !compact)
            }
        }
    }

    @ViewBuilder private func contractorGrid(_ teams: [InstallOverview.Contractor]) -> some View {
        if !teams.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("ผู้รับเหมา \(teams.count) ทีม").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                    Text("แตะเพื่อดูเฉพาะทีม").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                }
                // iPad: every team in one row
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: compact ? min(max(teams.count, 2), 4) : max(teams.count, 4)), spacing: 5) {
                    ForEach(teams) { team in contractorButton(team) }
                }
            }
        }
    }

    private func contractorButton(_ team: InstallOverview.Contractor) -> some View {
        let on = contractor == team.name
        return Button { contractor = on ? nil : team.name } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(team.name).font(.sarabunFixed(12, .bold))
                (Text("\(team.stations) สถานี")
                 + Text(team.behind > 0 ? " · ช้า \(team.behind)" : "").foregroundStyle(on ? Theme.dangerLine : Theme.dangerText))
                    .font(.sarabunFixed(11))
            }
            .lineLimit(1).minimumScaleFactor(0.75)
            .foregroundStyle(on ? Theme.onPrimary : Theme.navySolid)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(on ? Theme.navySolid : Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { if !on { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(team.name) \(team.stations) สถานี" + (team.behind > 0 ? " ช้ากว่าแผน \(team.behind)" : ""))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func dailyStrip(_ t: InstallOverview.Totals) -> some View {
        Button { host.openDailyReports?() } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.clipboard").font(.system(size: 15, weight: .semibold))
                (Text("รายงานประจำวันวันนี้ ") + Text("\(t.sent)/\(t.reporting)").bold() + Text(" ส่งแล้ว · ยังไม่ส่ง \(t.unsent) สถานี"))
                    .font(.sarabunFixed(13)).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if host.openDailyReports != nil { Text("›").font(.sarabunFixed(17)) }
            }
            .foregroundStyle(Theme.warningText)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(host.openDailyReports == nil)
    }

    private func installFilters(_ stations: [InstallStationSummary], selected: InstallOverview.RowFilter) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // the permit block is on the iPad rows only, and so is its filter
                ForEach(InstallOverview.RowFilter.allCases.filter { !compact || $0 != .permit }, id: \.self) { f in
                    let title = [.behind: "ช้ากว่าแผน", .noReport: "ยังไม่ส่งรายงาน", .permit: "ขออนุญาตค้าง", .all: "ทั้งหมด"][f] ?? ""
                    TCCountPill(title, count: stations.filter { InstallOverview.matches($0, f, threshold: threshold) }.count,
                                selected: selected == f) { installFilter = f }
                }
            }
        }
    }

    func paceChip(_ s: InstallStationSummary) -> (String, TCFeedTone)? {
        guard let pace = InstallOverview.pace(s, threshold: threshold), let v = s.variance else { return nil }
        switch pace {
        case .behind: return ("ช้ากว่า \(-v)%", .red)
        case .onPlan: return ("ตามแผน", .blue)
        case .ahead: return ("เร็วกว่า \(v)%", .green)
        }
    }

    private func installRow(_ s: InstallStationSummary) -> some View {
        let behind = InstallOverview.pace(s, threshold: threshold) == .behind
        let who = [s.contractor, s.dueDate.map { "ส่งมอบ " + dayMonth($0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let mp = s.mpNumber { Text("MP \(mp)").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted) }
                if let chip = paceChip(s) { TCToneChip(chip.0, tone: chip.1) }
                Spacer(minLength: 6)
                if let sent = s.reportSentToday { TCToneChip(sent ? "รายงานวันนี้ ✓" : "ยังไม่ส่งรายงาน", tone: sent ? .green : .orange) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(s.name).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: 6)
                if s.kWp > 0 { Text("\(number(s.kWp)) kWp").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize() }
            }
            TCPlanBar(actual: s.actual / 100, plan: s.plan.map { $0 / 100 }, tint: behind ? Theme.danger : Theme.primary)
            HStack(spacing: 6) {
                Text("\(Int(s.actual.rounded()))%").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.navy).fixedSize()
                if let plan = s.plan { Text("/ แผน \(Int(plan.rounded()))%").fixedSize() }
                if !s.currentTask.isEmpty { Text("· " + s.currentTask).foregroundStyle(Theme.navy).lineLimit(1) }
                Spacer(minLength: 6)
                Text(who).lineLimit(1).layoutPriority(1)
            }
            .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: บำรุงรักษา

    @ViewBuilder var maintenanceOverview: some View {
        let stations = maintenanceStations
        if stations.isEmpty {
            stageEmpty
        } else {
            // with no station in trouble `มีปัญหา` would be empty, so start on every station
            let rowFilter = maintenanceFilter ?? (stations.contains { MaintenanceOverview.matches($0, .issue) } ? .issue : .all)
            let rows = stations.filter { MaintenanceOverview.matches($0, rowFilter) }
            card(maintenanceSummary(MaintenanceOverview.totals(stations)), padding: summaryPadding)
            rowFilters(maintenanceFilters(stations, selected: rowFilter), count: rows.count)
            stationRows {
                ForEach(rows) { s in
                    Button { openMaintenanceStation(s) } label: {
                        if compact { maintenanceRow(s).padding(rowPadding) } else { padMaintenanceRow(s).padding(rowPadding) }
                    }
                        .buttonStyle(TCStationRowStyle())
                        .accessibilityLabel(maintenanceLabel(s))
                        .contextMenu {
                            Button { returnToInstall(s) } label: { Label("ย้ายกลับเป็นงานติดตั้ง", systemImage: "arrow.uturn.backward") }
                        }
                }
            }
            if rows.isEmpty { noRows("ไม่มีสถานีในตัวกรองนี้") }
        }
        addMaintenanceButton
    }

    /// As `addInstallButton`: a row under the stations.
    private var addMaintenanceButton: some View {
        Button { showMaintenancePicker = true } label: {
            Label("เพิ่มโครงการบำรุงรักษา", systemImage: "plus").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The station's job here when it has one, else the host's screen for it.
    private func openMaintenanceStation(_ s: MaintenanceStationSummary) {
        if let j = model.jobs(in: .maintenance).first(where: { $0.id.uuidString == s.id || $0.jobSyncID == s.id }) {
            lastOpened = j.id.uuidString
            tracking = j.id
        } else {
            host.openMaintenanceStation?(s)
        }
    }

    private func maintenanceLabel(_ s: MaintenanceStationSummary) -> String {
        let status = [.normal: "ปกติ", .alarm: "แจ้งเตือน", .offline: "ออฟไลน์"][s.status] ?? ""
        return [s.mpNumber.map { "MP \($0)" } ?? "", s.name, status, "เปิดหน้าสถานี"].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func maintenanceSummary(_ t: MaintenanceOverview.Totals) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            summaryParts(maintenanceHead(t), tiles: maintenanceTiles(t), rest: dueList(Array(MaintenanceOverview.due(maintenanceTasks).prefix(3))))
        }
    }

    private func maintenanceHead(_ t: MaintenanceOverview.Totals) -> some View {
        HStack(spacing: 12) {
            TCPlanRing(actual: Double(t.yield) / 100, tint: Theme.success)
            VStack(alignment: .leading, spacing: 0) {
                Text("ส่งมอบแล้ว \(t.count) สถานี").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Text("\(number(t.kWp, digits: 1)) kWp · PR เฉลี่ย \(t.pr.map { "\($0)" } ?? "—")%")
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                (Text("วันนี้ผลิต ") + Text(number(t.energy, digits: 0)).bold() + Text(" / คาด \(number(t.expected, digits: 0)) kWh"))
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.navy)
            }
            .lineLimit(1).minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
        // the ring
        .accessibilityValue("ผลิตวันนี้ \(t.yield)% ของที่คาด")
    }

    private func maintenanceTiles(_ t: MaintenanceOverview.Totals) -> some View {
        HStack(spacing: 6) {
            TCStatTile("\(t.normal)", "ปกติ", tone: .green, large: !compact)
            TCStatTile("\(t.alarm)", "แจ้งเตือน", tone: .red, large: !compact)
            TCStatTile("\(t.offline)", "ออฟไลน์", tone: nil, large: !compact)
        }
    }

    @ViewBuilder private func dueList(_ due: [MaintenanceTask]) -> some View {
        if !due.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("งานที่ถึงกำหนดใน \(MaintenanceOverview.soonDays) วัน").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                ForEach(due) { task in dueRow(task) }
            }
        }
    }

    private func dueRow(_ task: MaintenanceTask) -> some View {
        HStack(spacing: 8) {
            Text(dayMonth(task.date)).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary).frame(width: 44, alignment: .leading)
            Text(task.title).font(.sarabunFixed(13)).foregroundStyle(Theme.navy).lineLimit(1)
            Spacer(minLength: 6)
            Text(task.assignee).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func maintenanceFilters(_ stations: [MaintenanceStationSummary], selected: MaintenanceOverview.RowFilter) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MaintenanceOverview.RowFilter.allCases, id: \.self) { f in
                    let title = [.issue: "มีปัญหา", .pmSoon: "ใกล้ถึง PM", .all: "ทั้งหมด"][f] ?? ""
                    TCCountPill(title, count: stations.filter { MaintenanceOverview.matches($0, f) }.count,
                                selected: selected == f) { maintenanceFilter = f }
                }
            }
        }
    }

    private func maintenanceRow(_ s: MaintenanceStationSummary) -> some View {
        let status: (String, TCFeedTone?, Color) = switch s.status {
        case .normal: ("ปกติ", .green, Theme.success)
        case .alarm: ("แจ้งเตือน", .red, Theme.danger)
        case .offline: ("ออฟไลน์", nil, Theme.chevron)
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let mp = s.mpNumber { Text("MP \(mp)").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted) }
                TCToneChip(status.0, tone: status.1)
                Spacer(minLength: 6)
                if s.openRepairs > 0 {
                    TCToneChip("แจ้งซ่อม \(s.openRepairs) งาน", tone: .orange)
                } else {
                    // fainter than the grey `ออฟไลน์` chip
                    Text("ไม่มีงานซ่อม").font(.sarabunFixed(11, .bold)).lineLimit(1).fixedSize()
                        .foregroundStyle(Theme.inkFaint)
                        .padding(.horizontal, 8).frame(height: 18)
                        .background(Theme.hairline, in: Capsule())
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(s.name).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: 6)
                if s.kWp > 0 { Text("\(number(s.kWp)) kWp").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize() }
            }
            // no plan tick here: the bar gives back the 3 pt it keeps for one on each side
            TCPlanBar(actual: s.yield, tint: status.2).padding(.vertical, -3)
            HStack(spacing: 6) {
                Text(number(s.energy, digits: 0)).font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.navy).fixedSize()
                Text("/ คาด \(number(s.expected, digits: 0)) kWh").fixedSize()
                Text("· PR \(s.reportsPR ? number(s.pr, digits: 0) : "—")%").foregroundStyle(Theme.navy).fixedSize()
                Spacer(minLength: 6)
                Text(s.note).lineLimit(1)
                Text("›").font(.sarabunFixed(17)).foregroundStyle(Theme.inkFaint).frame(height: 12).accessibilityHidden(true)
            }
            .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// A station row that is a button: the overview's white card, `Theme.background` while pressed.
private struct TCStationRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? Theme.background : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#if DEBUG
/// `-surveyHomeDemo install|maintenance`: the stations of docs/ui/pwa-solar-survey-iphone-v2's board, dated from today
/// as the board is from 13 ต.ค.
enum PWAOverviewDemo {
    private static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    static let install: [InstallStationSummary] = {
        // the last column is the iPad board's permits, อปท. กกพ. กฟภ. กว.: o got, w handed in, t not handed in, l overdue
        let rows: [(Int, String, Double, Double, Double, String, String, Int, Bool, String)] = [
            (189, "สถานีผลิตน้ำทุ่งน้อย · สาขาเมืองพล", 92.34, 38, 50, "2.3 ติดตั้งแผง", "A", 2, true, "twoo"),
            (120, "การประปาวัดชัย", 250, 22, 28, "2.1 โครงสร้าง", "B", 17, false, "owwo"),
            (98, "การประปาบ้านโป่ง", 90, 50, 52, "2.2 สาย DC", "A", -7, false, "oooo"),
            (154, "สถานีจ่ายน้ำแพรกหนามแดง", 209.76, 71, 68, "2.5 อินเวอร์เตอร์", "C", -1, true, "oowo"),
            (77, "สถานีผลิตน้ำโชคชัย", 171, 94, 92, "3.1 ทดสอบระบบ", "B", -5, true, "oooo"),
            (61, "สถานีผลิตน้ำแม่ข่ายชนบท", 145.2, 12, 10, "2.1 โครงสร้าง", "D", 27, true, "owto"),
            (133, "สถานีผลิตน้ำบางปะกง", 120.5, 55, 54, "2.3 ติดตั้งแผง", "A", 7, true, "oowo"),
            (142, "สถานีผลิตน้ำหนองแค", 180, 30, 36, "2.2 สาย DC", "C", 15, false, "lwoo"),
            (88, "สถานีผลิตน้ำพนัสนิคม", 160.4, 64, 62, "2.5 อินเวอร์เตอร์", "B", 1, true, "oooo"),
            (171, "สถานีผลิตน้ำสามโคก", 98.2, 8, 8, "1.3 ส่งมอบพื้นที่", "D", 43, true, "ttwt"),
            (66, "สถานีผลิตน้ำบ้านบึง", 210, 42, 40, "2.3 ติดตั้งแผง", "C", 20, false, "owoo"),
            (109, "สถานีผลิตน้ำศรีราชา", 115, 80, 78, "2.6 ระบบ AC", "A", -3, true, "oooo"),
        ]
        let states: [Character: InstallPermit.State] = ["o": .done, "w": .submitted, "t": .pending, "l": .overdue]
        return rows.map { r in
            InstallStationSummary(id: "demo-\(r.0)", mpNumber: r.0, name: r.1, kWp: r.2, actual: r.3, plan: r.4, currentTask: r.5,
                                  contractor: "ผู้รับเหมา " + r.6, dueDate: day(r.7), reportSentToday: r.8,
                                  permits: zip(InstallPermit.Authority.allCases, r.9).map { InstallPermit($0, states[$1] ?? .pending) })
        }
    }()

    static let maintenance: [MaintenanceStationSummary] = [
        .init(id: "demo-12", mpNumber: 12, name: "สถานีผลิตน้ำบางเลน", kWp: 180, energy: 612, expected: 650, pr: 81, nextPM: day(7), note: "PM " + short(7)),
        .init(id: "demo-25", mpNumber: 25, name: "สถานีผลิตน้ำนครชัยศรี", kWp: 220, energy: 410, expected: 790, pr: 63, status: .alarm, openRepairs: 1,
              nextPM: day(21), note: "INV 2 fault · 2 วัน"),
        .init(id: "demo-31", mpNumber: 31, name: "สถานีผลิตน้ำพุทธมณฑล", kWp: 150, energy: 530, expected: 540, pr: 84, nextPM: day(27), note: "PM " + short(27)),
        .init(id: "demo-44", mpNumber: 44, name: "สถานีผลิตน้ำสามพราน", kWp: 120, energy: 0, expected: 430, pr: 0, status: .offline, openRepairs: 1,
              nextPM: day(15), note: "ไม่มีข้อมูล 6 ชม."),
        .init(id: "demo-52", mpNumber: 52, name: "สถานีผลิตน้ำกำแพงแสน", kWp: 200, energy: 690, expected: 720, pr: 82, nextPM: day(2), note: "ล้างแผง " + short(2)),
        .init(id: "demo-7", mpNumber: 7, name: "สถานีผลิตน้ำดอนตูม", kWp: 95, energy: 330, expected: 345, pr: 83, nextPM: day(11), note: "PM " + short(11)),
    ]

    static let tasks: [MaintenanceTask] = [
        .init(id: "t1", date: day(2), title: "ล้างแผง · กำแพงแสน (MP 52)", assignee: "ผู้รับเหมา B"),
        .init(id: "t2", date: day(7), title: "PM รอบ 6 เดือน · บางเลน (MP 12)", assignee: "ทีม TC"),
        .init(id: "t3", date: day(11), title: "PM รอบ 6 เดือน · ดอนตูม (MP 7)", assignee: "ทีม TC"),
    ]

    private static func short(_ offset: Int) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: day(offset))
        return "\(c.day ?? 0)/\(c.month ?? 0)"
    }
}
#endif
#endif
