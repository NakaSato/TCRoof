import SwiftUI
import TCRoofUI
import TCRoofCore

/// `รายงานประจำวัน` (docs/ui/install-tracking-ipad §D, `states/05`): the KPI row, `ทุกรายงาน` with its filter and one row a
/// working day, and under it the crew, the cumulative progress against the MP plan, the photos by MP task and tomorrow.
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

    func dailyTab(_ d: InstallDailyData, site: InstallPageData.Site?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            dailyKPIs(d)
            reportsCard(d)
            dailyCards(d, site: site)
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

    private struct DailyKPI: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let ink: Color
        let note: String
    }

    private func kpis(_ d: InstallDailyData) -> [DailyKPI] {
        var out: [DailyKPI] = []
        let n = d.workingThroughYesterday, x = d.sentThroughYesterday
        out.append(DailyKPI(label: "ส่งแล้ว", value: "\(x) / \(n) วัน", ink: x >= n ? Theme.successInk : Theme.warningInk, note: "นับถึงเมื่อวาน"))
        let dates = { (ds: [Date]) in ds.sorted().map(ThaiFormat.dayMonth.string(from:)).joined(separator: ", ") }
        let waitNote = [d.drafts.isEmpty ? nil : "ร่าง " + dates(d.drafts),
                        d.unacknowledged.isEmpty ? nil : "ผู้ตรวจยังไม่รับทราบ " + dates(d.unacknowledged)].compactMap { $0 }
        out.append(DailyKPI(label: "รอลงนาม · รับทราบ", value: "\(d.drafts.count) · \(d.unacknowledged.count)",
                            ink: d.drafts.isEmpty && d.unacknowledged.isEmpty ? Theme.successInk : Theme.warningInk,
                            note: waitNote.isEmpty ? "ครบทุกฉบับ" : waitNote.joined(separator: " · ")))
        let today = d.rows.first { $0.date == d.today }
        let (value, ink, note): (String, Color, String) = switch today?.state {
        case .signed?, .stopped?: ("ส่งแล้ว", Theme.successInk, today?.ackAt == nil ? "รอผู้ตรวจรับทราบ" : "ผู้ตรวจรับทราบแล้ว")
        case .draft?: ("ร่างไว้", Theme.warningInk, "ยังไม่ลงนาม · ส่งก่อน \(d.workEnd)")
        case .today?, .missing?: ("ยังไม่ส่ง", Theme.dangerText, "ส่งก่อน \(d.workEnd)")
        case nil: ("ไม่ต้องส่ง", Theme.inkMuted, d.inWindow ? "วันหยุดของหน้างาน" : "นอกช่วงติดตั้ง")
        }
        out.append(DailyKPI(label: "วันนี้ " + ThaiFormat.dayMonth.string(from: d.today), value: value, ink: ink, note: note))
        if d.hasReports {
            let avg = d.workedDays > 0 ? Double(d.manDays) / Double(d.workedDays) : 0
            out.append(DailyKPI(label: "คน·วันรวม", value: "\(d.manDays)", ink: Theme.navy,
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.label).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    Text(c.value).font(.sarabunFixed(26, .bold)).foregroundStyle(c.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text(c.note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).truncationMode(.tail)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Theme.hairline).frame(width: 1) } }
                .accessibilityElement(children: .combine)
            }
        }
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

    /// The columns' widths; `งานที่ทำ` takes the rest.
    private enum Col {
        static let date: CGFloat = 80, status: CGFloat = 88, weather: CGFloat = 56, crew: CGFloat = 32
        static let progress: CGFloat = 150, photos: CGFloat = 36, sign: CGFloat = 190, problem: CGFloat = 170, action: CGFloat = 140
    }

    private func reportsCard(_ d: InstallDailyData) -> some View {
        panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text("ทุกรายงาน").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    TCCountSegments([.init("ทั้งหมด", count: d.rows.count), .init("ต้องทำ", count: d.rows.filter(\.needsWork).count),
                                     .init("มีปัญหา", count: d.rows.filter(\.hasProblem).count)],
                                    selection: $dailyFilter, equalWidths: false, fontSize: 15)
                        .fixedSize()
                    Spacer(minLength: 8)
                    if let w = d.week {
                        Button { route = .weekly } label: {
                            Label("สร้าง Weekly Report W\(w.number) จาก \(w.reports) รายงาน", systemImage: "doc.text")
                        }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                    }
                    if d.hasReports {
                        Button { shareAllDailies() } label: { Label("PDF รวม", systemImage: "arrow.down.to.line") }
                            .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                    }
                }
                VStack(spacing: 0) {
                    tableHeader
                    let rows = filtered(d)
                    if rows.isEmpty {
                        Text(d.rows.isEmpty ? "ยังไม่ถึงช่วงติดตั้ง" : "ไม่มีรายงานในหมวดนี้").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    ForEach(rows) { reportRow($0, today: d.today) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
            }
            .padding(18)
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Text("วันที่").frame(width: Col.date, alignment: .leading)
            Text("สถานะ").frame(width: Col.status, alignment: .leading)
            Text("อากาศ").frame(width: Col.weather, alignment: .leading)
            Text("คน").frame(width: Col.crew, alignment: .leading)
            Text("งานที่ทำ").frame(maxWidth: .infinity, alignment: .leading)
            Text("สะสม (แผน MP)").frame(width: Col.progress, alignment: .leading)
            Text("รูป").frame(width: Col.photos, alignment: .leading)
            Text("ลงนาม · รับทราบ").frame(width: Col.sign, alignment: .leading)
            Text("ปัญหา").frame(width: Col.problem, alignment: .leading)
            Color.clear.frame(width: Col.action, height: 1)
        }
        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 14).frame(height: 40)
        .background(Theme.phonePage)
        .accessibilityHidden(true)
    }

    private func reportRow(_ r: InstallDailyData.Row, today: Date) -> some View {
        let urgent = r.state == .today
        return HStack(spacing: 10) {
            Text(Self.dayLabel(r.date)).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                .frame(width: Col.date, alignment: .leading)
            stateChip(r.state).frame(width: Col.status, alignment: .leading)
            weatherCell(r).frame(width: Col.weather, alignment: .leading)
            Text(r.crew.map(String.init) ?? "—").font(.sarabunFixed(15)).foregroundStyle(Theme.navy).monospacedDigit()
                .frame(width: Col.crew, alignment: .leading)
            Text(r.work).font(.sarabunFixed(15)).foregroundStyle(r.state == .missing ? Theme.dangerText : Theme.navy).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            progressCell(r).frame(width: Col.progress, alignment: .leading)
            Text("\(r.photos)").font(.sarabunFixed(15)).foregroundStyle(r.photos > 0 ? Theme.navy : Theme.inkMuted).monospacedDigit()
                .frame(width: Col.photos, alignment: .leading)
            signCell(r, today: today).frame(width: Col.sign, alignment: .leading)
            Text(r.problem.isEmpty ? "—" : r.problem).font(.sarabunFixed(14)).foregroundStyle(r.problem.isEmpty ? Theme.inkMuted : Theme.warningInk)
                .lineLimit(1).frame(width: Col.problem, alignment: .leading)
            actionButton(r).frame(width: Col.action)
        }
        .padding(.horizontal, 14).frame(minHeight: 64)
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

    @ViewBuilder private func progressCell(_ r: InstallDailyData.Row) -> some View {
        if let p = r.planned {
            HStack(spacing: 8) {
                Capsule().fill(Theme.track).frame(width: 54, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.primary).frame(width: 54 * min(max((r.actual ?? 0) / 100, 0), 1), height: 6)
                    }
                Text("\(r.actual.map { "\(Int($0.rounded()))%" } ?? "—") / \(Int(p.rounded()))%")
                    .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).monospacedDigit().lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("สะสม \(r.actual.map { "\(Int($0.rounded()))" } ?? "ไม่มี") เปอร์เซ็นต์ แผน \(Int(p.rounded())) เปอร์เซ็นต์")
        } else {
            Text("—").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
        }
    }

    private func signCell(_ r: InstallDailyData.Row, today: Date) -> some View {
        let ack: (String, InstallPageData.Tone) = if let a = r.ackAt {
            ("ผู้ตรวจ ✓ " + ThaiFormat.dayMonth.string(from: a), .ok)
        } else if let s = r.signedAt {
            ("ผู้ตรวจ รอ \(max(RoutineReport.calendar.dateComponents([.day], from: RoutineReport.calendar.startOfDay(for: s), to: today).day ?? 0, 0)) วัน", .danger)
        } else {
            ("ผู้ตรวจ —", .idle)
        }
        return HStack(spacing: 6) {
            chip(r.signedAt != nil ? "วิศวกร ✓" : "วิศวกร —", r.signedAt != nil ? .ok : .idle)
            chip(ack.0, ack.1)
        }
    }

    private func actionButton(_ r: InstallDailyData.Row) -> some View {
        let (title, prominent): (String, Bool) = switch r.state {
        case .today: ("ทำรายงานวันนี้", true)
        case .draft: ("ทำต่อ · ส่ง", true)
        case .missing: ("ทำรายงาน", false)
        case .signed, .stopped: ("เปิดรายงาน", false)
        }
        return Button { route = .day(r.date) } label: { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(TCButtonStyle(prominent ? .primary : .secondary, size: .card))
            .accessibilityLabel(title + " " + Self.dayLabel(r.date))
    }

    /// `PDF รวม`: every daily report's R2 pages in one file, to the share sheet.
    private func shareAllDailies() {
        let built = job.dailyLogs.compactMap { RoutineReportFiles.daily(job, log: $0) }
        guard !built.isEmpty else { return }
        let all = RoutineReportFiles.Built(pages: built.flatMap(\.pages), images: built.reduce(into: [:]) { $0.merge($1.images) { a, _ in a } },
                                           name: "รายงานประจำวันรวม-\(job.stationName).pdf", folder: [], title: RoutineReport.Kind.daily.title)
        if let url = try? RoutineReportFiles.temporaryURL(all) { shared = Shared(url: url) }
    }

    // MARK: the four cards

    @ViewBuilder private func dailyCards(_ d: InstallDailyData, site: InstallPageData.Site?) -> some View {
        let labour = site?.labour ?? []
        HStack(alignment: .top, spacing: 14) {
            if !labour.isEmpty { crewCard(labour) }
            if d.points.contains(where: { $0.actual != nil }) { progressLineCard(d) }
            if !d.photosByTask.isEmpty { photosCard(d) }
            if let t = d.nextDay, !d.next.isEmpty { tomorrowCard(t, d.next) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cardTitle(_ title: String, _ note: String, trailing: String? = nil, ink: Color = Theme.inkMuted) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).lineLimit(1).accessibilityAddTraits(.isHeader)
            Text(note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            Spacer(minLength: 4)
            if let trailing { Text(trailing).font(.sarabunFixed(13, .bold)).foregroundStyle(ink).lineLimit(1) }
        }
    }

    private func crewCard(_ days: [InstallPageData.LabourDay]) -> some View {
        let top = max(days.map { max($0.plan ?? 0, $0.actual ?? 0) }.max() ?? 1, 1), h: CGFloat = 150
        return panel {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("กำลังคนรายวัน", days.contains { $0.plan != nil } ? "เส้นประ = แผน" : "จากรายงาน")
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(days) { day in
                        VStack(spacing: 3) {
                            Text((day.actual ?? day.plan).map(String.init) ?? "").font(.sarabunFixed(11, .bold))
                                .foregroundStyle(day.actual == nil ? Theme.inkMuted : Theme.navy).frame(height: 14)
                            ZStack(alignment: .bottom) {
                                if let a = day.actual {
                                    RoundedRectangle(cornerRadius: 3).fill(Theme.primary).frame(height: h * CGFloat(a) / CGFloat(top))
                                } else if let p = day.plan {
                                    RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.inkMuted.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                                        .frame(height: h * CGFloat(p) / CGFloat(top))
                                }
                            }
                            .frame(height: h, alignment: .bottom)
                            Text(ThaiFormat.dayMonth.string(from: day.date).split(separator: "/").first.map(String.init) ?? "")
                                .font(.sarabunFixed(10)).foregroundStyle(Theme.inkMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(ThaiFormat.dayMonth.string(from: day.date))
                        .accessibilityValue([day.plan.map { "แผน \($0) คน" }, day.actual.map { "จริง \($0) คน" }].compactMap { $0 }.joined(separator: " · "))
                    }
                }
            }
            .padding(16)
        }
    }

    private func progressLineCard(_ d: InstallDailyData) -> some View {
        let last = d.points.last { $0.actual != nil }
        let gap = last.map { ($0.actual ?? 0) - $0.planned } ?? 0
        return panel {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("ความก้าวหน้าสะสม", "เทียบแผน MP", trailing: abs(gap) < 0.5 ? "ตามแผน" : gap > 0 ? "เร็วกว่า \(Int(gap.rounded()))%" : "ช้ากว่า \(Int((-gap).rounded()))%",
                          ink: gap >= -0.5 ? Theme.successInk : Theme.dangerText)
                Canvas { ctx, size in
                    let n = max(d.points.count - 1, 1)
                    func pt(_ i: Int, _ v: Double) -> CGPoint { CGPoint(x: size.width * CGFloat(i) / CGFloat(n), y: size.height * (1 - CGFloat(v) / 100)) }
                    for f in [0.25, 0.5, 0.75] {
                        var g = Path(); g.move(to: CGPoint(x: 0, y: size.height * f)); g.addLine(to: CGPoint(x: size.width, y: size.height * f))
                        ctx.stroke(g, with: .color(Theme.hairline), lineWidth: 1)
                    }
                    var plan = Path(), act = Path()
                    for (i, p) in d.points.enumerated() { i == 0 ? plan.move(to: pt(i, p.planned)) : plan.addLine(to: pt(i, p.planned)) }
                    ctx.stroke(plan, with: .color(Theme.inkMuted.opacity(0.7)), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    let done = d.points.enumerated().filter { $0.element.actual != nil }
                    for (k, e) in done.enumerated() { k == 0 ? act.move(to: pt(e.offset, e.element.actual!)) : act.addLine(to: pt(e.offset, e.element.actual!)) }
                    ctx.stroke(act, with: .color(Theme.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    if let t = done.last?.offset {
                        var line = Path(); line.move(to: CGPoint(x: pt(t, 0).x, y: 0)); line.addLine(to: CGPoint(x: pt(t, 0).x, y: size.height))
                        ctx.stroke(line, with: .color(Theme.danger), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    }
                }
                .frame(height: 168)
                .accessibilityElement()
                .accessibilityLabel("ความก้าวหน้าสะสม")
                .accessibilityValue(last.map { "จริง \(Int(($0.actual ?? 0).rounded()))% แผน \(Int($0.planned.rounded()))%" } ?? "")
            }
            .padding(16)
        }
    }

    private func photosCard(_ d: InstallDailyData) -> some View {
        let top = max(d.photosByTask.map(\.count).max() ?? 1, 1)
        return panel {
            VStack(alignment: .leading, spacing: 10) {
                cardTitle("รูปตามงาน MP", "", trailing: "\(d.photosByTask.reduce(0) { $0 + $1.count }) รูป", ink: Theme.navy)
                ForEach(d.photosByTask, id: \.code) { t in
                    HStack(spacing: 10) {
                        Text(t.code).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary).frame(width: 30, alignment: .leading)
                        Text(t.title).font(.sarabunFixed(14)).foregroundStyle(Theme.navy).lineLimit(1)
                        Spacer(minLength: 6)
                        Capsule().fill(Theme.track).frame(width: 70, height: 6)
                            .overlay(alignment: .leading) { Capsule().fill(Theme.success).frame(width: 70 * CGFloat(t.count) / CGFloat(top), height: 6) }
                        Text("\(t.count)").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.successInk).monospacedDigit().frame(width: 26, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
        }
    }

    private func tomorrowCard(_ day: Date, _ items: [InstallDailyData.Next]) -> some View {
        panel {
            VStack(alignment: .leading, spacing: 10) {
                cardTitle("พรุ่งนี้ " + Self.dayLabel(day), "งานตามแผน MP")
                ForEach(items) { n in
                    HStack(spacing: 10) {
                        Text(n.code).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                        Text(n.title).font(.sarabunFixed(14)).foregroundStyle(Theme.navy).lineLimit(1)
                        Spacer(minLength: 6)
                        Text("ตอนนี้ \(Int(n.percent.rounded()))%").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).monospacedDigit()
                    }
                    .padding(.horizontal, 12).frame(minHeight: 40)
                    .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
                Button { route = .day(day) } label: { Text("สร้างร่างรายงาน " + ThaiFormat.dayMonth.string(from: day)).frame(maxWidth: .infinity) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
            }
            .padding(16)
        }
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous).fill(Theme.primary).frame(height: 4)
        }
    }
}
