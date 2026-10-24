import SwiftUI
import TCRoofUI
import TCRoofCore

/// The end of `ภาพรวม` (docs/ui/install-tracking-ipad §C, `states/08`–`10`): `เอกสารโครงการ` beside the site panel,
/// and the two sheets of the page, `ต้องดำเนินการ` (`states/04`) and a tile's list (`states/07`).
extension InstallTrackingPage {
    /// A sheet over the page: the open items, or a document tile's list.
    enum Sheet: Equatable { case actions, doc(String) }

    enum SiteTab: String { case info, risk, labour }

    func go(_ target: InstallPageData.Target) {
        sheet = nil
        // the iPad's เอกสาร is a tab of the page; the iPhone pushes the station's papers
        if target == .docs, sizeClass != .compact { tab = .docs; return }
        let today = RoutineReport.calendar.startOfDay(for: .now)
        route = switch target {
        case .daily: .day(today)
        case .day(let d): .day(d)
        case .request: .request
        case .weekly: .weekly
        case .docs: .docs
        case .plan: .plan
        case .iec: .iec
        case .devices: .devices
        }
    }

    func siteRow(_ data: InstallPageData) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !data.docs.isEmpty { docsCard(data.docs) }
            if let s = data.site { sitePanel(s) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content()
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: frame)
            .overlay(frame.strokeBorder(Theme.borderSubtle))
            .cardShadow()
    }

    // MARK: เอกสารโครงการ

    private func docsCard(_ tiles: [InstallPageData.DocTile]) -> some View {
        let open = tiles.filter(\.needsAction).count
        return card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("เอกสารโครงการ").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Text("แตะเพื่อดูรายละเอียด").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 8)
                    if open > 0 { chip("ต้องดำเนินการ \(open)", .warn) }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(tiles) { docTile($0) }
                }
            }
        }
    }

    private func docTile(_ t: InstallPageData.DocTile) -> some View {
        Button { sheet = .doc(t.id) } label: {
            HStack(spacing: 10) {
                Circle().fill(Self.ink(t.tone)).frame(width: 9, height: 9)
                Text(t.title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                chip(t.chip, t.tone).layoutPriority(1)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("เปิดรายการ")
    }

    func chip(_ text: String, _ tone: InstallPageData.Tone) -> some View {
        Text(text).font(.sarabunFixed(13, .bold)).foregroundStyle(Self.ink(tone)).lineLimit(1)
            .padding(.horizontal, 9).frame(height: 24)
            .background(Self.fill(tone), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    static func ink(_ tone: InstallPageData.Tone) -> Color {
        switch tone {
        case .ok: Theme.successInk
        case .warn: Theme.warningInk
        case .danger: Theme.dangerText
        case .info: Theme.primary
        case .waiting: Theme.planInspect
        case .idle: Theme.inkMuted
        }
    }

    static func fill(_ tone: InstallPageData.Tone) -> Color {
        switch tone {
        case .ok: Theme.successSoft
        case .warn: Theme.warningSoft
        case .danger: Theme.dangerSoft
        case .info: Theme.primarySoft
        case .waiting: Theme.planInspectSoft
        case .idle: Theme.hairline
        }
    }

    // MARK: site panel

    private func siteTabs(_ s: InstallPageData.Site) -> [SiteTab] {
        [.info] + (s.risks.isEmpty ? [] : [.risk]) + (s.labour.isEmpty ? [] : [.labour])
    }

    private func sitePanel(_ s: InstallPageData.Site) -> some View {
        let tabs = siteTabs(s), current = tabs.contains(siteTab) ? siteTab : .info
        return card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    if tabs.count > 1 {
                        TCCountSegments(tabs.map { t in
                            switch t {
                            case .info: .init("ข้อมูลหน้างาน")
                            case .risk: .init("ความเสี่ยง", count: s.risks.count)
                            case .labour: .init("แรงงาน")
                            }
                        }, selection: Binding(get: { tabs.firstIndex(of: current) ?? 0 }, set: { siteTab = tabs[$0] }),
                           equalWidths: false, fontSize: 15)
                        .fixedSize()
                    } else {
                        Text("ข้อมูลหน้างาน").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 8)
                    Text("ณ " + ThaiFormat.numericDate.string(from: s.asOf)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                switch current {
                case .info: siteInfo(s)
                case .risk: siteRisks(s)
                case .labour: siteLabour(s)
                }
            }
        }
    }

    /// The MP tasks' % (the board's installed quantities have no model) beside the four tiles.
    private func siteInfo(_ s: InstallPageData.Site) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if !s.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ความคืบหน้าตามงาน MP").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    ForEach(Array(s.tasks.enumerated()), id: \.offset) { _, t in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(t.title).font(.sarabunFixed(14)).foregroundStyle(Theme.navy).lineLimit(1)
                                Spacer(minLength: 6)
                                Text("\(Int(t.percent.rounded()))%").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                if s.hasReports {
                    kpiTile("แรงงานวันนี้", value: s.peopleToday.map { "\($0) คน" } ?? "ยังไม่บันทึก", ink: s.peopleToday == nil ? Theme.inkMuted : Theme.navy,
                            note: "สะสม \(s.manDays) man-day")
                }
                kpiTile("รายงานส่งแล้ว", value: "\(s.reportsSent)/\(s.workingDaysSoFar) วัน",
                        ink: s.reportsSent >= s.workingDaysSoFar ? Theme.successInk : Theme.warningInk, note: "วันทำงานถึงวันนี้")
                if s.hasReports {
                    kpiTile("ปัญหาที่เปิดอยู่", value: s.issues.isEmpty ? "ไม่มี" : "\(s.issues.count) เรื่อง",
                            ink: s.issues.isEmpty ? Theme.successInk : Theme.warningInk, note: s.issues.first?.description ?? "จากรายงานล่าสุด")
                    kpiTile("ฝนตก", value: "\(s.rainHours) ชม.", ink: Theme.navy, note: "รวมจากรายงานประจำวัน")
                }
            }
            .frame(maxWidth: s.tasks.isEmpty ? .infinity : 400)
        }
    }

    private func kpiTile(_ label: String, value: String, ink: Color, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabunFixed(22, .bold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// This week's request's risks: the level, the risk and how it is handled.
    private func siteRisks(_ s: InstallPageData.Site) -> some View {
        VStack(spacing: 10) {
            ForEach(s.risks) { r in
                HStack(spacing: 14) {
                    priorityChip(r.level == .high ? .danger : r.level == .medium ? .warn : .idle, r.level.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
                        if !r.prevention.isEmpty {
                            Text("รับมือ: " + r.prevention).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            Text("จากคำขอรายสัปดาห์นี้").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func priorityChip(_ tone: InstallPageData.Tone, _ text: String) -> some View {
        Text(text).font(.sarabunFixed(14, .bold)).foregroundStyle(Self.ink(tone))
            .frame(width: 48, height: 32)
            .background(Self.fill(tone), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The working days' crew: the week's request in grey, the daily report in blue.
    private func siteLabour(_ s: InstallPageData.Site) -> some View {
        let top = max(s.labour.map { max($0.plan ?? 0, $0.actual ?? 0) }.max() ?? 1, 1)
        let chartHeight: CGFloat = 170
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                if s.plannedManDays != nil { legendSwatch(Theme.track, "แผน") }
                legendSwatch(Theme.primary, "จริง")
                Spacer(minLength: 8)
                Text("สะสม \(s.manDays) man-day" + (s.plannedManDays.map { " | แผนทั้งโครงการ \($0)" } ?? ""))
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(s.labour) { d in
                    VStack(spacing: 4) {
                        let shown = d.actual ?? d.plan
                        Text(shown.map(String.init) ?? "").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.navy).frame(height: 16)
                        ZStack(alignment: .bottom) {
                            if let p = d.plan {
                                RoundedRectangle(cornerRadius: 4).fill(Theme.track).frame(height: chartHeight * CGFloat(p) / CGFloat(top))
                            }
                            if let a = d.actual {
                                RoundedRectangle(cornerRadius: 4).fill(Theme.primary).frame(height: chartHeight * CGFloat(a) / CGFloat(top))
                                    .padding(.horizontal, d.plan == nil ? 0 : 6)
                            }
                        }
                        .frame(height: chartHeight, alignment: .bottom)
                        Text(ThaiFormat.dayMonth.string(from: d.date)).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ThaiFormat.dayMonth.string(from: d.date))
                    .accessibilityValue([d.plan.map { "แผน \($0) คน" }, d.actual.map { "จริง \($0) คน" }].compactMap { $0 }.joined(separator: " | "))
                }
            }
        }
    }

    private func legendSwatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 12)
            Text(title).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        }
    }

    // MARK: sheets

    func pageSheet(_ s: Sheet, _ data: InstallPageData) -> some View {
        ZStack {
            Theme.navySolid.opacity(0.35).ignoresSafeArea()
                .onTapGesture { sheet = nil }
                .accessibilityHidden(true)
            switch s {
            case .actions: actionsSheet(data.actions)
            case .doc(let id): if let t = data.docs.first(where: { $0.id == id }) { docSheet(t) }
            }
        }
        .transition(.opacity)
    }

    private func sheetFrame<Content: View>(width: CGFloat, title: String, about: String, chip: (String, InstallPageData.Tone)?,
                                           @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.sarabunFixed(26, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    // up to two lines (the 4.2 sheet's state)
                    Text(about).font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let chip { self.chip(chip.0, chip.1).padding(.top, 10) }
                Button { sheet = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.navy)
                        .frame(width: 48, height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ปิด")
            }
            .padding(.horizontal, 26).padding(.vertical, 22)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                VStack(spacing: 0) { content() }.padding(.horizontal, 26).padding(.bottom, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 640)
            .fixedSize(horizontal: false, vertical: true)
        }
        // as wide as the board's sheet, or the phone's width less its margins
        .frame(maxWidth: width)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.navySolid.opacity(0.18), radius: 24, y: 8)
        .padding(.horizontal, 12)
    }

    private func actionsSheet(_ actions: [InstallPageData.Action]) -> some View {
        sheetFrame(width: 730, title: "ต้องดำเนินการ", about: "รายการที่ค้างจากแผน รายงาน และเอกสาร | แตะเพื่อเปิดรายการ", chip: nil) {
            if actions.isEmpty {
                Text("ไม่มีรายการค้าง").font(.sarabunFixed(16)).foregroundStyle(Theme.inkMuted).padding(.vertical, 24)
            }
            ForEach(actions) { a in
                Button { go(a.target) } label: {
                    HStack(spacing: 16) {
                        priorityChip(a.priority == .high ? .danger : .warn, a.priority == .high ? "สูง" : "กลาง")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                            Text(a.detail).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primary)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
        }
    }

    private func docSheet(_ t: InstallPageData.DocTile) -> some View {
        sheetFrame(width: 810, title: t.title, about: t.about, chip: (t.chip, t.tone)) {
            if t.items.isEmpty {
                Text("ยังไม่มีรายการ").font(.sarabunFixed(16)).foregroundStyle(Theme.inkMuted).padding(.vertical, 24)
            }
            ForEach(t.items) { item in
                docRow(item).overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
        }
    }

    /// A line of a tile's sheet: the whole row opens its target, or its own button does (`เปิดบันทึก ›`).
    @ViewBuilder private func docRow(_ item: InstallPageData.DocItem) -> some View {
        if let title = item.button, let target = item.target {
            HStack(alignment: .center, spacing: 16) {
                docRowLabel(item)
                Button(title) { go(target) }
                    .buttonStyle(TCButtonStyle(.primary, size: .card))
                    .fixedSize()
            }
            .padding(.vertical, 14)
            .accessibilityElement(children: .contain)
        } else {
            Button { if let target = item.target { go(target) } } label: {
                docRowLabel(item)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.target == nil)
        }
    }

    private func docRowLabel(_ item: InstallPageData.DocItem) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if !item.code.isEmpty {
                Text(item.code).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary).frame(width: 96, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                Text(item.detail).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 8)
            chip(item.chip, item.tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
