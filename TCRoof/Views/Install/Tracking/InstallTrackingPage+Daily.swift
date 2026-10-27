import SwiftUI
import TCRoofUI
import TCRoofCore

/// `รายงานประจำวัน` (docs/ui/install-tracking-ipad-daily): the KPI strip, then `ทุกรายงาน` with its filter and one row a
/// working day, running down to the dock. Each row's cumulative progress is set against the MP plan.
extension InstallTrackingPage {
    /// A file to hand to the share sheet.
    struct Shared: Identifiable {
        let url: URL
        var id: URL { url }
    }

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
    static let dailyKPIHeight: CGFloat = 52

    func dailyTab(_ d: InstallDailyData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            dailyKPIs(d)
            // the reports card takes the rest of the height, down to the dock
            reportsCard(d).frame(height: max(viewport - 14 - Self.dailyKPIHeight - 14 - Self.dockClearance, 300))
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

    // MARK: KPI row

    struct DailyKPI: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let ink: Color
        let note: String
    }

    func kpis(_ d: InstallDailyData) -> [DailyKPI] {
        var out: [DailyKPI] = []
        let n = d.workingThroughYesterday, x = d.sentThroughYesterday
        out.append(DailyKPI(label: "ส่งแล้ว", value: "\(x) / \(n) วัน", ink: x >= n ? Theme.successInk : Theme.warningInk, note: "นับถึงเมื่อวาน"))
        let dates = { (ds: [Date]) in ds.sorted().map(ThaiFormat.dayMonth.string(from:)).joined(separator: ", ") }
        let waitNote = [d.drafts.isEmpty ? nil : "ร่าง " + dates(d.drafts),
                        d.unacknowledged.isEmpty ? nil : "ผู้ตรวจยังไม่รับทราบ " + dates(d.unacknowledged)].compactMap { $0 }
        out.append(DailyKPI(label: "รอลงนาม | รับทราบ", value: "\(d.drafts.count) | \(d.unacknowledged.count)",
                            ink: d.drafts.isEmpty && d.unacknowledged.isEmpty ? Theme.successInk : Theme.warningInk,
                            note: waitNote.isEmpty ? "ครบทุกฉบับ" : waitNote.joined(separator: " | ")))
        let today = d.rows.first { $0.date == d.today }
        let (value, ink, note): (String, Color, String) = switch today?.state {
        case .signed?, .stopped?: ("ส่งแล้ว", Theme.successInk, today?.ackAt == nil ? "รอผู้ตรวจรับทราบ" : "ผู้ตรวจรับทราบแล้ว")
        case .draft?: ("ร่างไว้", Theme.warningInk, "ยังไม่ลงนาม | ส่งก่อน \(d.workEnd)")
        case .today?, .missing?: ("ยังไม่ส่ง", Theme.dangerText, "ส่งก่อน \(d.workEnd)")
        case nil: ("ไม่ต้องส่ง", Theme.inkMuted, d.inWindow ? "วันหยุดของหน้างาน" : "นอกช่วงติดตั้ง")
        }
        out.append(DailyKPI(label: "วันนี้ " + ThaiFormat.dayMonth.string(from: d.today), value: value, ink: ink, note: note))
        if d.hasReports {
            let avg = d.workedDays > 0 ? Double(d.manDays) / Double(d.workedDays) : 0
            out.append(DailyKPI(label: "คน-วันรวม", value: "\(d.manDays)", ink: Theme.navy,
                                note: "เฉลี่ย \(avg.formatted(.number.precision(.fractionLength(0...1)))) คน/วันที่ทำงาน"))
            out.append(DailyKPI(label: "หยุดเพราะฝน", value: "\(d.rainStops) วัน", ink: Theme.navy, note: "ฝนรวม \(d.rainHours) ชม. จากรายงาน"))
        }
        return out
    }

    private func dailyKPIs(_ d: InstallDailyData) -> some View {
        let cells = kpis(d)
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { i, c in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(c.label).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(c.value).font(.sarabunFixed(20, .bold)).foregroundStyle(c.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            .layoutPriority(1)
                    }
                    Text(c.note).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).truncationMode(.tail)
                }
                .padding(.horizontal, 14)
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

    private func filtered(_ d: InstallDailyData) -> [InstallDailyData.Row] {
        switch dailyFilter {
        case 1: d.rows.filter(\.needsWork)
        case 2: d.rows.filter(\.hasProblem)
        default: d.rows
        }
    }

    /// The columns' widths; `งานที่ทำ` takes the rest. `compact` is the portrait iPad's: no `งานที่ทำ`, the two sign chips
    /// stacked, narrower columns (the table picks it when the full one doesn't fit, `ViewThatFits`).
    private struct Col {
        let compact: Bool
        let date: CGFloat = 80, status: CGFloat = 88, weather: CGFloat = 56, crew: CGFloat = 32, photos: CGFloat = 36
        let progress: CGFloat = 170
        var sign: CGFloat { compact ? 110 : 190 }
        var problem: CGFloat { compact ? 130 : 170 }
        var action: CGFloat { compact ? 120 : 140 }
        /// `งานที่ทำ`'s ideal width, so every row asks the same width of `ViewThatFits`.
        static let work: CGFloat = 120
    }

    private func reportsCard(_ d: InstallDailyData) -> some View {
        panel {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    reportsBar(d, short: false)
                    reportsBar(d, short: true)
                }
                VStack(spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        tableHeader(Col(compact: false))
                        tableHeader(Col(compact: true))
                    }
                    let rows = filtered(d)
                    // the rows scroll under the header inside the card's fixed height
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if rows.isEmpty {
                                Text(d.rows.isEmpty ? "ยังไม่ถึงช่วงติดตั้ง" : "ไม่มีรายงานในหมวดนี้").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
                                    .frame(maxWidth: .infinity, minHeight: 64)
                            }
                            ForEach(rows) { r in
                                ViewThatFits(in: .horizontal) {
                                    reportRow(r, today: d.today, col: Col(compact: false))
                                    reportRow(r, today: d.today, col: Col(compact: true))
                                }
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
            }
            .padding(18)
        }
    }

    /// `ทุกรายงาน`, its filter and buttons; `short` names the Weekly Report button without its count of reports.
    private func reportsBar(_ d: InstallDailyData, short: Bool) -> some View {
        HStack(spacing: 14) {
            Text("ทุกรายงาน").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            TCCountSegments([.init("ทั้งหมด", count: d.rows.count), .init("ต้องทำ", count: d.rows.filter(\.needsWork).count),
                             .init("มีปัญหา", count: d.rows.filter(\.hasProblem).count)],
                            selection: $dailyFilter, equalWidths: false, fontSize: 15)
                .fixedSize()
            Spacer(minLength: 8)
            if let w = d.week {
                Button { go(.weekly) } label: {
                    Label(short ? "Weekly Report W\(w.number)" : "สร้าง Weekly Report W\(w.number) จาก \(w.reports) รายงาน", systemImage: "doc.text")
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
        HStack(spacing: 10) {
            Text("วันที่").frame(width: col.date, alignment: .leading)
            Text("สถานะ").frame(width: col.status, alignment: .leading)
            Text("อากาศ").frame(width: col.weather, alignment: .leading)
            Text("คน").frame(width: col.crew, alignment: .leading)
            if !col.compact { Text("งานที่ทำ").frame(minWidth: 0, idealWidth: Col.work, maxWidth: .infinity, alignment: .leading) }
            Text("สะสม | เทียบแผน MP").frame(width: col.progress, alignment: .leading)
            Text("รูป").frame(width: col.photos, alignment: .leading)
            Text("ลงนาม | รับทราบ").frame(width: col.sign, alignment: .leading)
            Text("ปัญหา").frame(width: col.problem, alignment: .leading)
            if col.compact { Spacer(minLength: 0) }
            Color.clear.frame(width: col.action, height: 1)
        }
        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 14).frame(height: 40)
        .background(Theme.phonePage)
        .accessibilityHidden(true)
    }

    private func reportRow(_ r: InstallDailyData.Row, today: Date, col: Col) -> some View {
        let urgent = r.state == .today
        return HStack(spacing: 10) {
            Text(Self.dayLabel(r.date)).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                .frame(width: col.date, alignment: .leading)
            stateChip(r.state).frame(width: col.status, alignment: .leading)
            weatherCell(r).frame(width: col.weather, alignment: .leading)
            Text(r.crew.map(String.init) ?? "—").font(.sarabunFixed(15)).foregroundStyle(Theme.navy).monospacedDigit()
                .frame(width: col.crew, alignment: .leading)
            if !col.compact {
                Text(r.work).font(.sarabunFixed(15)).foregroundStyle(r.state == .missing ? Theme.dangerText : Theme.navy).lineLimit(1)
                    .frame(minWidth: 0, idealWidth: Col.work, maxWidth: .infinity, alignment: .leading)
            }
            progressCell(r).frame(width: col.progress, alignment: .leading)
            Text("\(r.photos)").font(.sarabunFixed(15)).foregroundStyle(r.photos > 0 ? Theme.navy : Theme.inkMuted).monospacedDigit()
                .frame(width: col.photos, alignment: .leading)
            signCell(r, today: today, stacked: col.compact).frame(width: col.sign, alignment: .leading)
            Text(r.problem.isEmpty ? "—" : r.problem).font(.sarabunFixed(14)).foregroundStyle(r.problem.isEmpty ? Theme.inkMuted : Theme.warningInk)
                .lineLimit(col.compact ? 2 : 1).frame(width: col.problem, alignment: .leading)
            if col.compact { Spacer(minLength: 0) }
            actionButton(r).frame(width: col.action)
        }
        .padding(.horizontal, 14).frame(minHeight: 56)
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
                if r.rainHours > 0 { Text("ฝน").font(.sarabunFixed(14)).foregroundStyle(Theme.navy) }
            }
            .font(.system(size: 16))
            .accessibilityLabel(w.title)
        } else {
            Text("—").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
        }
    }

    /// `47%` with `+3 เร็วกว่า` / `ตามแผน` / `-6 ช้ากว่า`, over a bar green when on or ahead of plan, orange when behind,
    /// with a tick at the plan; `—` and `แผน 52%` before there is an actual.
    @ViewBuilder private func progressCell(_ r: InstallDailyData.Row) -> some View {
        if let p = r.planned {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(r.actual.map { "\(Int($0.rounded()))%" } ?? "—").font(.sarabunFixed(15, .bold))
                        .foregroundStyle(r.actual == nil ? Theme.inkMuted : Theme.navy).monospacedDigit().lineLimit(1)
                    if let d = r.delta {
                        chip(d > 0 ? "+\(d) เร็วกว่า" : d == 0 ? "ตามแผน" : "\(d) ช้ากว่า", d >= 0 ? .ok : .danger)
                    } else {
                        chip("แผน \(Int(p.rounded()))%", .idle)
                    }
                }
                progressBar(actual: r.actual, planned: p, behind: (r.delta ?? 0) < 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("สะสม \(r.actual.map { "\(Int($0.rounded()))" } ?? "ไม่มี") เปอร์เซ็นต์ แผน \(Int(p.rounded())) เปอร์เซ็นต์"
                                + (r.delta.map { $0 > 0 ? " | เร็วกว่าแผน \($0)" : $0 < 0 ? " | ช้ากว่าแผน \(-$0)" : " | ตามแผน" } ?? ""))
        } else {
            Text("—").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
        }
    }

    /// A 6 pt bar the column's width: the actual filled, a navy tick at the plan.
    private func progressBar(actual: Double?, planned: Double, behind: Bool) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if let a = actual {
                    Capsule().fill(behind ? Theme.warning : Theme.success).frame(width: g.size.width * min(max(a / 100, 0), 1))
                }
                Rectangle().fill(Theme.navy).frame(width: 2, height: 10)
                    .offset(x: min(max(g.size.width * planned / 100 - 1, 0), g.size.width - 2))
            }
        }
        .frame(height: 6)
        .padding(.trailing, 8)
    }

    private func signCell(_ r: InstallDailyData.Row, today: Date, stacked: Bool) -> some View {
        let ack: (String, InstallPageData.Tone) = if let a = r.ackAt {
            ("ผู้ตรวจ ✓ " + ThaiFormat.dayMonth.string(from: a), .ok)
        } else if let s = r.signedAt {
            ("ผู้ตรวจ รอ \(max(RoutineReport.calendar.dateComponents([.day], from: RoutineReport.calendar.startOfDay(for: s), to: today).day ?? 0, 0)) วัน", .danger)
        } else {
            ("ผู้ตรวจ —", .idle)
        }
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            chip(r.signedAt != nil ? "วิศวกร ✓" : "วิศวกร —", r.signedAt != nil ? .ok : .idle)
            chip(ack.0, ack.1)
        }
    }

    private func actionButton(_ r: InstallDailyData.Row) -> some View {
        let (title, prominent): (String, Bool) = switch r.state {
        case .today: ("ทำรายงานวันนี้", true)
        case .draft: ("ทำต่อ | ส่ง", true)
        case .missing: ("ทำรายงาน", false)
        case .signed, .stopped: ("เปิดรายงาน", false)
        }
        return Button { route = .day(r.date) } label: { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(TCButtonStyle(prominent ? .primary : .secondary, size: .card))
            .accessibilityLabel(title + " " + Self.dayLabel(r.date))
    }

    /// `PDF รวม`: every daily report's R2 pages in one file, to the share sheet.
    func shareAllDailies() {
        let built = job.dailyLogs.compactMap { RoutineReportFiles.daily(job, log: $0) }
        guard !built.isEmpty else { return }
        let all = RoutineReportFiles.Built(pages: built.flatMap(\.pages), images: built.reduce(into: [:]) { $0.merge($1.images) { a, _ in a } },
                                           name: "รายงานประจำวันรวม-\(job.stationName).pdf", folder: [], title: RoutineReport.Kind.daily.title)
        if let url = try? RoutineReportFiles.temporaryURL(all) { shared = Shared(url: url) }
    }
}
