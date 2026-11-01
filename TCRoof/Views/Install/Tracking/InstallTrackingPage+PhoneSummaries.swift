import SwiftUI
import TCRoofUI
import TCRoofCore
import ExcelExport

/// The iPhone page's in-page summaries (docs/ui/install-tracking-iphone §4.4–4.7) of the screens the iPad pushes:
/// next week's request (R1), the Weekly Report (R3), the IEC 62446 test and the station's permit papers. They read the
/// same records as those screens and change nothing themselves; their rows and buttons push the screens, which keep
/// every rule (who may edit, send, approve).
extension InstallTrackingPage {
    // MARK: คำขอรายสัปดาห์

    var requestWeekStart: Date {
        let cal = RoutineReport.calendar
        let next = MasterSchedule.weekStart(cal.date(byAdding: .day, value: 7, to: .now) ?? .now)
        return cal.date(byAdding: .day, value: 7 * requestWeek, to: next) ?? next
    }

    func phoneRequestTab() -> some View {
        let week = requestWeekStart, cal = RoutineReport.calendar
        let r = WeeklyRequestScreen.load(job, week), stored = job.weeklyRequest(for: week) != nil
        let left = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: week).day ?? 0
        let (chipText, tone): (String, InstallPageData.Tone) = switch r.status {
        case .approved: ("อนุมัติแล้ว", .ok)
        case .sent: ("รออนุมัติ", .info)
        case .draft: (stored ? "ร่าง | ยังไม่ส่ง" : "ร่างจากแผน MP", .warn)
        }
        return VStack(alignment: .leading, spacing: 14) {
            phoneCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("คำขอปฏิบัติงานรายสัปดาห์").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                            Text("ส่งก่อนเริ่มสัปดาห์").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer(minLength: 6)
                        toneChip(chipText, tone)
                    }
                    weekSwitcher(week) { requestWeek += $0 }
                    if r.status == .draft {
                        Label("ส่งก่อน " + RoutineReport.thaiDate(week) + (left > 0 ? " | อีก \(left) วัน" : left == 0 ? " | วันนี้" : " | เลยกำหนด"),
                              systemImage: "clock")
                            .font(.sarabunFixed(14)).foregroundStyle(left < 0 ? Theme.dangerText : Theme.warningInk)
                    }
                    stepLine(["ร่างคำขอ", "ส่งขออนุมัติ", "อนุมัติ"], current: r.status == .approved ? 3 : r.status == .sent ? 1 : 0)
                    HStack(spacing: 10) {
                        Button(r.isEditable(external: permissions.role == .external) && permissions.can(.weeklyRequest, on: job.access) ? "แก้ไขคำขอ" : "เปิดคำขอ") {
                            phoneRoute = .request(week)
                        }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                        Button("ดู PDF") {
                            if let url = try? RoutineReportFiles.temporaryURL(RoutineReportFiles.request(job, r)) { shared = Shared(url: url) }
                        }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                    }
                }
            }
            requestWorkCard(r, week: week)
            requestCountCard(2, "กำลังคน", r.crew, unit: "คน")
            requestCountCard(3, "เครื่องมือ", r.tools, unit: "รายการ", total: r.tools.filter { $0.count > 0 }.count)
            requestChecks(r, week: week)
        }
    }

    private func numbered(_ n: Int, _ title: String, trailing: String) -> some View {
        HStack(spacing: 8) {
            Text("\(n)").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                .frame(width: 24, height: 24).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            Text(trailing).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chevron)
        }
    }

    /// `1 แผนงาน`: each line with the days the MP plan gives its task this week.
    private func requestWorkCard(_ r: RoutineReport.WeeklyRequest, week: Date) -> some View {
        let cal = RoutineReport.calendar, settings = job.routineSettings
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week) }.filter { RoutineReport.isWorkingDay($0, settings: settings) }
        let plan = Dictionary((job.scheduleInput.map { MasterSchedule.plan($0) } ?? []).map { ($0.task, $0) }) { a, _ in a }
        return Button { phoneRoute = .request(week) } label: {
            phoneCard {
                VStack(alignment: .leading, spacing: 12) {
                    numbered(1, "แผนงาน", trailing: "\(r.work.count) งาน")
                    if r.work.isEmpty {
                        Text("ไม่มีงานตามแผนในสัปดาห์นี้").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(days, id: \.self) { d in
                                Text(Self.dayLabel(d).replacingOccurrences(of: "/\(cal.component(.month, from: d))", with: ""))
                                    .font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    ForEach(r.work) { line in requestLine(line, days: days, planned: line.task.flatMap { plan[$0] }, week: week) }
                    if !r.work.isEmpty {
                        HStack(spacing: 12) {
                            swatch(Theme.primary, "วันทำงาน")
                            swatch(Theme.danger, "ยกมา")
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func requestLine(_ line: RoutineReport.PlanLine, days: [Date], planned: MasterSchedule.PlannedTask?, week: Date) -> some View {
        let cal = RoutineReport.calendar
        let start = planned?.start.map(cal.startOfDay(for:)), end = planned?.end.map(cal.startOfDay(for:))
        let carried = end.map { $0 < week } ?? false
        let (tag, tone): (String, InstallPageData.Tone) = line.task == nil ? ("งานอื่น", .idle)
            : start == nil ? ("ยังไม่มีวัน", .warn) : carried ? ("ยกมา", .danger) : ("จากแผน MP", .info)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(line.task?.code ?? "–").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary).frame(width: 30, alignment: .leading)
                Text(line.description.isEmpty ? (line.task?.title ?? "งาน") : line.description).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
            }
            HStack(spacing: 6) {
                toneChip(tag, tone)
                if !line.location.isEmpty { Text(line.location).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
            }
            .padding(.leading, 40)
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { d in
                    let on = carried || (start.map { $0 <= d } ?? false) && (end.map { d <= $0 } ?? false)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(on ? (carried ? Theme.danger.opacity(0.75) : Theme.primary) : start == nil ? Theme.warningSoft : Theme.segmentTrack)
                        .overlay {
                            if start == nil && line.task != nil {
                                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.warning, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            }
                        }
                        .frame(height: 22).frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func requestCountCard(_ n: Int, _ title: String, _ counts: [RoutineReport.Count], unit: String, total: Int? = nil) -> some View {
        let sum = total ?? counts.reduce(0) { $0 + $1.count }
        return Button { phoneRoute = .request(requestWeekStart) } label: {
            phoneCard {
                VStack(alignment: .leading, spacing: 4) {
                    numbered(n, title, trailing: "รวม \(sum) \(unit)")
                    ForEach(counts.filter { $0.count > 0 }, id: \.name) { c in
                        HStack {
                            Text(c.name).font(.sarabunFixed(15)).foregroundStyle(Theme.navy).lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(c.count)").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                        }
                        .frame(minHeight: 36)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        .accessibilityElement(children: .combine)
                    }
                    if sum == 0 { Text("ยังไม่ได้ระบุ").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted) }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// `ตรวจก่อนส่ง`: what the request still lacks, from its own lines and the MP plan.
    private func requestChecks(_ r: RoutineReport.WeeklyRequest, week: Date) -> some View {
        let end = RoutineReport.calendar.date(byAdding: .day, value: 6, to: week) ?? week
        let planned = (job.scheduleInput.map { MasterSchedule.plan($0) } ?? []).filter { p in
            guard p.weight > 0, p.task.part != .permit, let s = p.start, let e = p.end else { return false }
            return s <= end && e >= week && job.scheduleActual.done(p.task, through: end) < p.weight - 1e-9
        }
        let missingTasks = planned.filter { p in !r.work.contains { $0.task == p.task } }.count
        let noPlace = r.work.filter { $0.location.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let crew = r.crew.reduce(0) { $0 + $1.count }
        let number = Calendar(identifier: .iso8601).component(.weekOfYear, from: end)
        let items: [(String, Bool, String)] = [
            ("แผนงานตรงกับแผน MP สัปดาห์ที่ \(number)", missingTasks == 0, missingTasks == 0 ? "" : "ขาด \(missingTasks) งานตามแผน"),
            ("ทุกงานมีตำแหน่ง", noPlace == 0, noPlace == 0 ? "" : "\(noPlace) งานยังไม่ระบุตำแหน่ง"),
            ("ประเมินความเสี่ยง", !r.risks.isEmpty, r.risks.isEmpty ? "ยังไม่มีรายการความเสี่ยง" : "\(r.risks.count) รายการ"),
            ("ระบุกำลังคน", crew > 0, crew > 0 ? "\(crew) คน" : "ยังไม่ได้ระบุ"),
            ("ส่งขออนุมัติแล้ว", r.status != .draft, r.status == .draft ? "ส่งจากหน้าคำขอ (ลงนามและ PDF)" : ""),
        ]
        return phoneCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("ตรวจก่อนส่ง").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                ForEach(items, id: \.0) { item in checkRow(item.0, ok: item.1, note: item.2) }
                Button(r.status == .draft ? "เปิดคำขอเพื่อลงนามและส่ง" : "เปิดคำขอ") { phoneRoute = .request(week) }
                    .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
                    .padding(.top, 4)
            }
        }
    }

    func checkRow(_ title: String, ok: Bool, note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark" : "exclamationmark").font(.system(size: 11, weight: .heavy))
                .foregroundStyle(ok ? Theme.successInk : Theme.warningInk)
                .frame(width: 24, height: 24).background(ok ? Theme.successSoft : Theme.warningSoft, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabunFixed(15)).foregroundStyle(Theme.navy)
                if !note.isEmpty { Text(note).font(.sarabunFixed(13)).foregroundStyle(ok ? Theme.inkMuted : Theme.warningInk) }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(ok ? "ครบ" : "ยังไม่ครบ")
    }

    // MARK: Weekly Report

    var reportWeekRange: ClosedRange<Date> {
        let cal = RoutineReport.calendar
        let anchor = cal.date(byAdding: .day, value: 7 * reportWeek, to: .now) ?? .now
        // Weekly Report weeks run Monday to Sunday, as the customer's deck
        return WeeklySlides.week(of: anchor)
    }

    func phoneWeeklyTab() -> some View {
        let cal = RoutineReport.calendar, w = reportWeekRange, today = cal.startOfDay(for: .now)
        let logs = job.dailyLogs.filter { w.contains(cal.startOfDay(for: $0.date)) }
        let reports = logs.compactMap(\.report)
        let checks = weeklyChecks(week: w)
        let ready = checks.filter(\.ok).count
        let filed = job.documents.contains { $0.name == RoutineReport.fileName(.weekly, date: MasterSchedule.weekStart(w.lowerBound), station: job.stationName) }
        let step = filed ? 3 : ready == checks.count ? 1 : 0
        return VStack(alignment: .leading, spacing: 14) {
            phoneCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary)
                            .frame(width: 44, height: 44).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Weekly Report").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                            Text("สรุปประจำสัปดาห์ (R3) | จากรายงานประจำวัน").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                        }
                    }
                    weekSwitcher(w.lowerBound) { reportWeek += $0 }
                    stepLine(["รอข้อมูล", "พร้อมส่ง", "ส่งแล้ว"], current: step)
                    if !filed {
                        Text("ครบสัปดาห์ " + RoutineReport.thaiDate(w.upperBound) + (today > w.upperBound ? " | ยังไม่ได้เก็บเข้าเอกสาร" : ""))
                            .font(.sarabunFixed(14)).foregroundStyle(Theme.warningInk)
                    }
                }
            }
            slidesCard(reports: reports.sorted { $0.date < $1.date }, logs: logs, week: w)
            phoneCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("ความพร้อมก่อนส่ง").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("\(ready)/\(checks.count)").font(.sarabunFixed(15, .bold)).foregroundStyle(ready == checks.count ? Theme.successInk : Theme.warningInk)
                    }
                    ForEach(checks, id: \.title) { c in
                        HStack(spacing: 8) {
                            checkRow(c.title, ok: c.ok, note: c.note)
                            if !c.ok && c.fixable {
                                Button("ไปแก้") { phoneTab = .daily }
                                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                            }
                        }
                        .padding(10)
                        .background(c.ok ? Theme.phonePage : Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    HStack(spacing: 10) {
                        Menu {
                            Button("PDF", systemImage: "doc") {
                                if let url = try? RoutineReportFiles.temporaryURL(RoutineReportFiles.weekly(job, week: w.lowerBound)) { shared = Shared(url: url) }
                            }
                            Button("PowerPoint", systemImage: "rectangle.on.rectangle") {
                                if let url = try? RoutineReportFiles.weeklySlides(job, week: w.lowerBound) { shared = Shared(url: url) }
                            }
                        } label: {
                            Image(systemName: "arrow.down.to.line").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.navy)
                                .frame(width: 52, height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderControl))
                        }
                        .accessibilityLabel("ดาวน์โหลด PDF หรือ PowerPoint")
                        Button("เปิด Weekly Report") { phoneRoute = .weekly(w.lowerBound) }
                            .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    /// The deck's slides as `WeeklySlides.outline` lists them (the template's 8, as the iPad rail). Green when its data
    /// is there, orange when it waits on something.
    private func slidesCard(reports: [RoutineReport.Daily], logs: [InstallLog], week: ClosedRange<Date>) -> some View {
        let slides = WeeklySlides.outline(RoutineReportFiles.outlineInput(job, week: week.lowerBound)).map { ($0.label, $0.ready) }
        return phoneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("สไลด์ \(slides.count) หน้า").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                    toneChip(slides.allSatisfy(\.1) ? "ข้อมูลครบ" : "รอข้อมูล \(slides.filter { !$0.1 }.count)", slides.allSatisfy(\.1) ? .ok : .warn)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(slides.enumerated()), id: \.offset) { i, s in
                            Button { phoneRoute = .weekly(week.lowerBound) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    RoundedRectangle(cornerRadius: 3).fill(Theme.primary).frame(height: 6)
                                    Spacer(minLength: 0)
                                    HStack(spacing: 4) {
                                        Text("\(i + 1) \(s.0)").font(.sarabunFixed(12)).foregroundStyle(Theme.navy).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Circle().fill(s.1 ? Theme.success : Theme.warning).frame(width: 7, height: 7)
                                    }
                                }
                                .padding(6)
                                .frame(width: 104, height: 64)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.borderSubtle))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("สไลด์ \(i + 1) \(s.0)")
                            .accessibilityValue(s.1 ? "ข้อมูลครบ" : "รอข้อมูล")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}
