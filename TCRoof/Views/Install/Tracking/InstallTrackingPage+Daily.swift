import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// `รายงานประจำวัน` (docs/ui/install-tracking-ipad-daily): the KPI strip, then `ทุกรายงาน` with its filter and one row a
/// working day, running down to the dock. Each row's cumulative progress is set against the MP plan.
struct InstallDailyTabView: View {
    let job: Job
    let data: InstallDailyData
    let viewport: CGFloat
    /// The scroll view's bottom inset: the dock's height.
    let viewportInset: CGFloat
    @Binding var route: InstallTrackingPage.Route?
    var onGoWeekly: (() -> Void)?

    @State private var dailyFilter: Int = InstallTrackingPage.Debug.dailyFilter
    @State private var ackingAllDailies = false
    @State private var shared: InstallTrackingPage.Shared?

    @Environment(\.permissions) private var permissions
    @Environment(\.modelContext) private var context

    static let dailyKPIHeight: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            dailyKPIs(data)
            // the reports card takes the rest of the height, down to the dock
            reportsCard(data).frame(height: max(viewport - 14 - Self.dailyKPIHeight - 14 - viewportInset - InstallTrackingPage.dockClearance, 300))
        }
        .sheet(item: $shared) { ActivitySheet(items: [$0.url]) }
        .sheet(isPresented: $ackingAllDailies) {
            InspectorAckSheet(title: "รับทราบทั้งหมด (\(job.pendingAckLogs.count) วัน)", name: job.routineSettings.inspector, date: .now, signs: true) { name, when, drawn in
                job.recordInspectorAckAll(job.pendingAckLogs, name: name, at: when, signature: drawn, context: context)
            }
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: frame)
            .overlay(frame.strokeBorder(Theme.borderSubtle))
            .cardShadow()
    }

    private func chip(_ text: String, _ tone: InstallPageData.Tone) -> some View {
        Text(text).font(.sarabun(13, .bold)).foregroundStyle(InstallTrackingPage.ink(tone)).lineLimit(1)
            .padding(.horizontal, 9).frame(height: 24)
            .background(InstallTrackingPage.fill(tone), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: KPI row

    private func dailyKPIs(_ d: InstallDailyData) -> some View {
        let cells = d.kpis()
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { i, c in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(c.label).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 4)
                        Text(c.value).font(.sarabun(20, .bold)).foregroundStyle(c.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            .layoutPriority(1)
                    }
                    Text(c.note).font(.sarabun(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).truncationMode(.tail)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Theme.hairline).frame(width: 1) } }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(height: Self.dailyKPIHeight)
        .background(Theme.surface, in: frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
        .cardShadow()
    }

    // MARK: ทุกรายงาน

    func rowNeedsWork(_ r: InstallDailyData.Row) -> Bool {
        r.needsWork || (r.isPendingAck && permissions.can(.dailySign, on: job.access))
    }

    private func filtered(_ d: InstallDailyData) -> [InstallDailyData.Row] {
        switch dailyFilter {
        case 1: d.rows.filter(rowNeedsWork)
        case 2: d.rows.filter(\.hasProblem)
        default: d.rows
        }
    }

    /// The columns' widths. All columns are preserved across iPad portrait and landscape;
    /// on narrower screens, the table scrolls horizontally without dropping columns or misaligning.
    private struct Col {
        let date: CGFloat = 76
        let status: CGFloat = 80
        let weather: CGFloat = 50
        let crew: CGFloat = 30
        let work: CGFloat = 140
        let progress: CGFloat = 155
        let photos: CGFloat = 30
        let sign: CGFloat = 170
        let problem: CGFloat = 130
        let action: CGFloat = 120
        let spacing: CGFloat = 8

        var totalWidth: CGFloat {
            date + status + weather + crew + work + progress + photos + sign + problem + action + (spacing * 9) + 24
        }
    }

    private func reportsCard(_ d: InstallDailyData) -> some View {
        panel {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    reportsBar(d, short: false)
                    reportsBar(d, short: true)
                    reportsBar(d, short: true, compact: true)
                }
                let col = Col()
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        tableHeader(col)
                        let rows = filtered(d)
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                if rows.isEmpty {
                                    Text(d.rows.isEmpty ? "ยังไม่ถึงช่วงติดตั้ง" : "ไม่มีรายงานในหมวดนี้")
                                        .font(.sarabun(15)).foregroundStyle(Theme.inkMuted)
                                        .frame(maxWidth: .infinity, minHeight: 64)
                                }
                                ForEach(rows) { r in
                                    reportRow(r, today: d.today, col: col)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                        .scrollIndicators(.automatic)
                    }
                    .frame(minWidth: col.totalWidth, maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
            }
            .padding(18)
        }
    }

    /// `ทุกรายงาน`, its filter and buttons; `short` names the Weekly Report button without its count of reports;
    /// `compact` adapts for narrower screen widths like iPad portrait.
    private func reportsBar(_ d: InstallDailyData, short: Bool, compact: Bool = false) -> some View {
        HStack(spacing: compact ? 8 : 14) {
            Text("ทุกรายงาน").font(.sarabun(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            TCCountSegments([.init("ทั้งหมด", count: d.rows.count), .init("ต้องทำ", count: d.rows.filter(rowNeedsWork).count),
                             .init("มีปัญหา", count: d.rows.filter(\.hasProblem).count)],
                            selection: $dailyFilter, equalWidths: false, fontSize: compact ? 13.5 : 15)
                .fixedSize()
            Spacer(minLength: 6)
            if !d.unacknowledged.isEmpty, permissions.can(.dailySign, on: job.access) {
                Button { ackingAllDailies = true } label: {
                    Label(compact ? "รับทราบ (\(d.unacknowledged.count))" : "รับทราบทั้งหมด (\(d.unacknowledged.count))",
                          systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
                .accessibilityIdentifier("dailyAckAll")
            }
            if let w = d.week {
                Button { onGoWeekly?() } label: {
                    Label(compact ? "Weekly W\(w.number)" : short ? "Weekly Report W\(w.number)" : "สร้าง Weekly Report W\(w.number) จาก \(w.reports) รายงาน",
                          systemImage: "doc.text")
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                .accessibilityLabel("สร้าง Weekly Report W\(w.number) จาก \(w.reports) รายงาน")
            }
            if d.hasReports {
                Button { shareAllDailies() } label: { Label("PDF รวม", systemImage: "arrow.down.to.line") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
            }
        }
    }

    private func tableHeader(_ col: Col) -> some View {
        HStack(spacing: col.spacing) {
            Text("วันที่").frame(width: col.date, alignment: .leading)
            Text("สถานะ").frame(width: col.status, alignment: .leading)
            Text("อากาศ").frame(width: col.weather, alignment: .leading)
            Text("คน").frame(width: col.crew, alignment: .leading)
            Text("งานที่ทำ").frame(width: col.work, alignment: .leading)
            Text("สะสม | เทียบแผน MP").frame(width: col.progress, alignment: .leading)
            Text("รูป").frame(width: col.photos, alignment: .leading)
            Text("ลงนาม | รับทราบ").frame(width: col.sign, alignment: .leading)
            Text("ปัญหา").frame(width: col.problem, alignment: .leading)
            Color.clear.frame(width: col.action, height: 1)
        }
        .font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 12).frame(height: 40)
        .background(Theme.phonePage)
        .accessibilityHidden(true)
    }

    private func reportRow(_ r: InstallDailyData.Row, today: Date, col: Col) -> some View {
        let urgent = r.state == .today
        return HStack(spacing: col.spacing) {
            Text(InstallTrackingPage.dayLabel(r.date)).font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
                .frame(width: col.date, alignment: .leading)
            stateChip(r.state).frame(width: col.status, alignment: .leading)
            weatherCell(r).frame(width: col.weather, alignment: .leading)
            Text(r.crew.map(String.init) ?? "—").font(.sarabun(15)).foregroundStyle(Theme.navy).monospacedDigit()
                .frame(width: col.crew, alignment: .leading)
            Text(r.work.isEmpty ? "—" : r.work).font(.sarabun(14.5)).foregroundStyle(r.state == .missing ? Theme.dangerText : Theme.navy)
                .lineLimit(2)
                .frame(width: col.work, alignment: .leading)
            progressCell(r).frame(width: col.progress, alignment: .leading)
            Text("\(r.photos)").font(.sarabun(15)).foregroundStyle(r.photos > 0 ? Theme.navy : Theme.inkMuted).monospacedDigit()
                .frame(width: col.photos, alignment: .leading)
            signCell(r, today: today).frame(width: col.sign, alignment: .leading)
            Text(r.problem.isEmpty ? "—" : r.problem).font(.sarabun(14)).foregroundStyle(r.problem.isEmpty ? Theme.inkMuted : Theme.warningInk)
                .lineLimit(2).frame(width: col.problem, alignment: .leading)
            actionButton(r).frame(width: col.action)
        }
        .padding(.horizontal, 12).frame(minHeight: 56)
        .background(urgent ? Theme.dangerSoft.opacity(0.45) : Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    private func stateChip(_ s: InstallDailyData.State) -> some View {
        let (title, tone): (String, InstallPageData.Tone) = switch s {
        case .today: ("ยังไม่ส่ง", .danger)
        case .missing: ("ไม่มีรายงาน", .danger)
        case .draft: ("ร่าง", .warn)
        case .signed: ("ส่งแล้ว", .ok)
        case .stopped: ("หยุดงาน", .idle)
        }
        return chip(title, tone)
    }

    @ViewBuilder private func weatherCell(_ r: InstallDailyData.Row) -> some View {
        if let w = r.weather {
            HStack(spacing: 4) {
                Image(systemName: w == .fine ? "sun.max" : w == .cloudy ? "cloud.sun" : "cloud.rain")
                    .foregroundStyle(w == .rain ? Theme.primary : Theme.pending)
                if r.rainHours > 0 { Text("ฝน").font(.sarabun(14)).foregroundStyle(Theme.navy) }
            }
            .font(.system(size: 16))
            .accessibilityLabel(w.title)
        } else {
            Text("—").font(.sarabun(15)).foregroundStyle(Theme.inkMuted)
        }
    }

    /// `47%` with `+3 เร็วกว่า` / `ตามแผน` / `-6 ช้ากว่า`, over a bar green when on or ahead of plan, orange when behind,
    /// with a tick at the plan; `—` and `แผน 52%` before there is an actual.
    @ViewBuilder private func progressCell(_ r: InstallDailyData.Row) -> some View {
        if let p = r.planned {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(r.actual.map { "\(Int($0.rounded()))%" } ?? "—").font(.sarabun(15, .bold))
                        .foregroundStyle(r.actual == nil ? Theme.inkMuted : Theme.navy).monospacedDigit().lineLimit(1)
                    if let d = r.delta {
                        chip(d > 0 ? "+\(d) เร็วกว่า" : d == 0 ? "ตามแผน" : "\(d) ช้ากว่า", d >= 0 ? .ok : .danger)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    } else {
                        chip("แผน \(Int(p.rounded()))%", .idle)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
                progressBar(actual: r.actual, planned: p, behind: (r.delta ?? 0) < 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("สะสม \(r.actual.map { "\(Int($0.rounded()))" } ?? "ไม่มี") เปอร์เซ็นต์ แผน \(Int(p.rounded())) เปอร์เซ็นต์"
                                + (r.delta.map { $0 > 0 ? " | เร็วกว่าแผน \($0)" : $0 < 0 ? " | ช้ากว่าแผน \(-$0)" : " | ตามแผน" } ?? ""))
        } else {
            Text("—").font(.sarabun(15)).foregroundStyle(Theme.inkMuted)
        }
    }

    /// A 6 pt bar the column's width: the actual filled, a navy tick at the plan.
    private func progressBar(actual: Double?, planned: Double, behind: Bool) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                    .overlay(Capsule().strokeBorder(Theme.borderSubtle, lineWidth: 0.5))
                if let a = actual, a > 0 {
                    Capsule().fill(behind ? Theme.warning : Theme.success).frame(width: g.size.width * min(max(a / 100, 0), 1))
                }
                RoundedRectangle(cornerRadius: 1).fill(Theme.navy).frame(width: 2, height: 6)
                    .offset(x: min(max(g.size.width * planned / 100 - 1, 0), g.size.width - 2))
            }
        }
        .frame(height: 6)
        .padding(.trailing, 8)
    }

    private func signCell(_ r: InstallDailyData.Row, today: Date) -> some View {
        let ack: (String, InstallPageData.Tone) = if let a = r.ackAt {
            ("ผู้ตรวจ ✓ " + ThaiFormat.dayMonth.string(from: a), .ok)
        } else if let s = r.signedAt {
            ("ผู้ตรวจ รอ \(max(RoutineReport.calendar.dateComponents([.day], from: RoutineReport.calendar.startOfDay(for: s), to: today).day ?? 0, 0)) วัน", .danger)
        } else {
            ("ผู้ตรวจ —", .idle)
        }
        return HStack(spacing: 4) {
            chip(r.signedAt != nil ? "วิศวกร ✓" : "วิศวกร —", r.signedAt != nil ? .ok : .idle)
                .lineLimit(1).minimumScaleFactor(0.8)
            chip(ack.0, ack.1)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func actionButton(_ r: InstallDailyData.Row) -> some View {
        let canApprove = r.isPendingAck && permissions.can(.dailySign, on: job.access)
        let (title, prominent): (String, Bool) = switch r.state {
        case .today: ("ทำรายงานวันนี้", true)
        case .draft: ("ทำต่อ | ส่ง", true)
        case .missing: ("ทำรายงาน", false)
        case .signed, .stopped: canApprove ? ("ตรวจ & รับทราบ", true) : ("เปิดรายงาน", false)
        }
        return Button { route = .day(r.date) } label: { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(TCButtonStyle(prominent ? .primary : .secondary, size: .card))
            .accessibilityLabel(title + " " + InstallTrackingPage.dayLabel(r.date))
    }

    /// `PDF รวม`: every daily report's R2 pages in one file, to the share sheet.
    func shareAllDailies() {
        if let url = InstallDailyData.shareAllDailies(job: job) {
            shared = InstallTrackingPage.Shared(url: url)
        }
    }
}

// MARK: - Compatibility Extension

extension InstallTrackingPage {
    /// A file to hand to the share sheet.
    struct Shared: Identifiable {
        let url: URL
        var id: URL { url }
    }

    typealias DailyKPI = InstallDailyData.KPI

    /// `พ. 30/9`, as on the board (the Thai `EEE` spells the day out).
    static func dayLabel(_ d: Date) -> String {
        let short = ["อา.", "จ.", "อ.", "พ.", "พฤ.", "ศ.", "ส."][(RoutineReport.calendar.component(.weekday, from: d) + 6) % 7]
        return short + " " + ThaiFormat.dayMonth.string(from: d)
    }

    var dailyData: InstallDailyData {
        #if DEBUG
        if Debug.demo { return .demo() }
        #endif
        return InstallDailyData(job: job)
    }

    /// The KPI strip's height.
    static let dailyKPIHeight: CGFloat = InstallDailyTabView.dailyKPIHeight

    func dailyTab(_ d: InstallDailyData) -> some View {
        InstallDailyTabView(
            job: job,
            data: d,
            viewport: viewport,
            viewportInset: viewportInset,
            route: $route,
            onGoWeekly: { go(.weekly) }
        )
    }

    func kpis(_ d: InstallDailyData) -> [DailyKPI] {
        d.kpis()
    }

    func rowNeedsWork(_ r: InstallDailyData.Row) -> Bool {
        r.needsWork || (r.isPendingAck && permissions.can(.dailySign, on: job.access))
    }

    func shareAllDailies() {
        if let url = InstallDailyData.shareAllDailies(job: job) {
            shared = Shared(url: url)
        }
    }
}
