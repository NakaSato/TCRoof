import SwiftUI
import TCRoofUI
import TCRoofCore

extension InstallTrackingPage {
    // MARK: ภาพรวม

    func phoneKPIs(_ data: InstallPageData) -> some View {
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

    func phoneDocsCard(_ tiles: [InstallPageData.DocTile]) -> some View {
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

    func phoneSitePanel(_ s: InstallPageData.Site) -> some View {
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
