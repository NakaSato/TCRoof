import SwiftUI
import TCRoofUI
import TCRoofCore
import ExcelExport

/// iPad `Weekly Report` in the page (docs/ui/install-tracking-ipad-weekly-report): the week header with the step line
/// and the download menu, the 8-slide rail, the slide viewer, the readiness checks, the recipients and the send button,
/// and the .pptx sheet. The slides are `WeeklySlides`' content, the same the .pptx is written from.
extension InstallTrackingPage {
    /// The files to share and, when they are a send, its record (kept once the share sheet completes).
    struct WeeklyShare: Identifiable {
        let id = UUID()
        let urls: [URL]
        let record: RoutineReport.WeeklySent?
    }

    /// One row of `ความพร้อมก่อนส่ง`: both sizes show the same four.
    struct WeeklyCheck {
        let title: String
        let ok: Bool
        let note: String
        /// `ไปแก้` opens `รายงานประจำวัน` while it fails.
        let fixable: Bool
    }

    /// The week's four checks, from the job: the daily reports signed, the MP plan, the photos, the problems. With
    /// `weekNumber` the plan's row reads `แผน MP สัปดาห์ที่ n` (iPad).
    func weeklyChecks(week w: ClosedRange<Date>, weekNumber: Int? = nil) -> [WeeklyCheck] {
        let cal = RoutineReport.calendar, today = cal.startOfDay(for: .now), settings = job.routineSettings
        let logs = job.dailyLogs.filter { w.contains(cal.startOfDay(for: $0.date)) }
        let reports = logs.compactMap(\.report)
        let through = min(w.upperBound, today)
        let working = through >= w.lowerBound ? RoutineReport.workingDays(settings: settings, from: w.lowerBound, to: through).count : 0
        let signed = logs.filter { $0.engineerSignedAt != nil }.count
        let approved = logs.filter { $0.inspectorAckAt != nil }.count
        let photos = logs.reduce(0) { $0 + $1.sortedPhotos.count }
        let problems = reports.reduce(0) { $0 + $1.problems.filter { !$0.description.isEmpty }.count }
        let planned = job.scheduleInput.map { MasterSchedule.status(plan: MasterSchedule.plan($0), actual: job.scheduleActual, through: w.upperBound).planned }
        let unsigned = logs.filter { $0.engineerSignedAt == nil }.map { Self.dayLabel($0.date) }
        let unacked = logs.filter { $0.engineerSignedAt != nil && $0.inspectorAckAt == nil }.map { Self.dayLabel($0.date) }
        let pendingNotes = [
            unsigned.isEmpty ? nil : unsigned.joined(separator: ", ") + " รอเซ็น",
            unacked.isEmpty ? nil : unacked.joined(separator: ", ") + " รอรับทราบ"
        ].compactMap { $0 }
        return [
            WeeklyCheck(title: "รายงานประจำวันเซ็นครบ", ok: signed >= working && approved >= signed && working > 0,
                        note: "เซ็นแล้ว \(signed)/\(working) · รับทราบ \(approved)/\(signed) วัน"
                            + (pendingNotes.isEmpty ? "" : " | " + pendingNotes.joined(separator: " | ")), fixable: true),
            WeeklyCheck(title: "แผน MP" + (weekNumber.map { " สัปดาห์ที่ \($0)" } ?? ""), ok: planned != nil,
                        note: planned.map { "แผนสะสม \(Int($0.rounded()))%" } ?? "ยังไม่มีแผน MP", fixable: false),
            WeeklyCheck(title: "รูปหน้างาน", ok: photos > 0, note: "\(photos) รูปจากรายงานประจำวัน", fixable: true),
            WeeklyCheck(title: "ปัญหาและแนวทางแก้ไข", ok: true, note: "รวมจากรายงานประจำวัน \(problems) ข้อ", fixable: false),
        ]
    }

    // MARK: state

    var reportWeekStart: Date { MasterSchedule.weekStart(reportWeekRange.lowerBound) }
    var reportKey: String { RoutineReport.dayKey(reportWeekStart) }

    /// The page's send of the week, or `-installDemo YES`'s.
    var reportRecord: RoutineReport.WeeklySent? {
        #if DEBUG
        if Debug.demo { return reportDemoSent[reportKey] }
        #endif
        return job.weeklySent(for: reportWeekStart)
    }

    /// Sent from the page, or (older data) its PDF filed without a record.
    var reportSent: Bool {
        #if DEBUG
        if Debug.demo { return reportRecord != nil }
        #endif
        return reportRecord != nil || job.weeklyFiled(reportWeekStart)
    }

    var reportChecks: [WeeklyCheck] {
        #if DEBUG
        if Debug.demo, let c = reportContent { return Self.demoChecks(c) }
        #endif
        return weeklyChecks(week: reportWeekRange, weekNumber: reportContent?.weekNumber)
    }

    var reportRecipients: [String] {
        reportRecord?.recipients ?? reportTo ?? RoutineReport.WeeklySent.defaultRecipients
    }

    /// Works out the week's slides and decodes their photos; `-installReportState` opens its state on the first week.
    func loadReport() {
        reportTo = nil; reportDownload = false
        #if DEBUG
        if Debug.demo {
            let (input, images) = Self.demoReport(week: reportWeekRange.lowerBound, allSigned: Debug.reportState == "ready" || reportWeek < 0)
            reportContent = Self.demoContent(WeeklySlides.content(input, images: images))
            reportPhotos = images.compactMapValues(UIImage.init(data:))
            // the weeks before were sent; the current one only with `-installReportState sent`
            if reportWeek < 0, reportDemoSent[reportKey] == nil {
                let at = RoutineReport.calendar.date(byAdding: .hour, value: 24 + 10, to: reportWeekRange.upperBound) ?? .now
                reportDemoSent[reportKey] = .init(weekStart: reportWeekStart, sentAt: at, sentBy: permissions.email,
                                                  recipients: RoutineReport.WeeklySent.defaultRecipients)
            }
            if reportWeek == Debug.reportWeek {
                switch Debug.reportState {
                case "menu": reportDownload = true
                case "pptx": reportPptx = true
                case "sent":
                    reportDemoSent[reportKey] = .init(weekStart: reportWeekStart, sentAt: .now, sentBy: permissions.email,
                                                      recipients: RoutineReport.WeeklySent.defaultRecipients)
                default: break
                }
            }
            return
        }
        #endif
        let (input, images) = RoutineReportFiles.slidesInput(job, week: reportWeekRange.lowerBound)
        let content = WeeklySlides.content(input, images: images)
        reportContent = content
        var photos: [UUID: UIImage] = [:]
        for p in content.photos { photos[p.id] = images[p.id].flatMap(UIImage.init(data:)) }
        reportPhotos = photos
        #if DEBUG
        if reportWeek == Debug.reportWeek {
            if Debug.reportState == "menu" { reportDownload = true }
            if Debug.reportState == "pptx" { reportPptx = true }
        }
        #endif
    }

    // MARK: the tab

    @ViewBuilder func weeklyTab() -> some View {
        VStack(spacing: 12) {
            weeklyHeader.zIndex(1)
            weeklyContent
        }
        .padding(.horizontal, 24).padding(.top, 14)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { weeklyWidth = $0 }
        // `padDock` already reserves the dock's safe area; keep just a small gap here.
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { if let t = reportNote { weeklyToast(t).padding(.bottom, 100) } }
        .sheet(isPresented: $reportPptx) { weeklyPptxSheet }
        .sheet(item: $reportShare) { share in
            WeeklyShareSheet(urls: share.urls) { completed in
                reportShare = nil
                guard completed, let r = share.record else { return }
                job.recordWeeklySent(r)
                try? context.save()
                showWeeklyNote("ส่ง Weekly Report สัปดาห์ที่ \(reportContent?.weekNumber ?? 0) แล้ว")
            }
        }
    }

    /// The viewer, rail, and readiness panel each contain sizable SwiftUI trees. Type erase this branch boundary so
    /// opening the tab doesn't require the runtime to instantiate their combined generic type at once.
    private var weeklyContent: AnyView {
        guard let content = reportContent else {
            return AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity))
        }
        if weeklyNarrow {
            return AnyView(
                HStack(alignment: .top, spacing: 12) {
                    weeklyRail(content).frame(width: 206)
                    VStack(spacing: 12) {
                        weeklyViewer(content).layoutPriority(1)
                        weeklyPanel(split: true).frame(minHeight: 300)
                    }
                }
                .frame(maxHeight: .infinity)
            )
        }
        return AnyView(
            HStack(alignment: .top, spacing: 12) {
                weeklyRail(content).frame(width: 206)
                weeklyViewer(content)
                weeklyPanel(split: false).frame(width: 300)
            }
            .frame(maxHeight: .infinity)
        )
    }

    /// Use the portrait arrangement only when the content width is genuinely narrow. The 11-inch iPad Air's
    /// landscape content area is about 1130 pt after page margins, so a 1200 pt cutoff misclassified it.
    var weeklyNarrow: Bool { weeklyWidth > 0 && weeklyWidth < 1000 }

    func weeklyCard<Content: View>(padding: CGFloat = 14, @ViewBuilder _ content: () -> Content) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: frame)
            .overlay(frame.strokeBorder(Theme.borderSubtle))
            .cardShadow()
    }

    private func weeklyToast(_ text: String) -> some View {
        Text(text).font(.sarabunFixed(15, .semibold)).foregroundStyle(Theme.onPrimary)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Theme.toast, in: Capsule())
            .transition(.opacity)
            .accessibilityAddTraits(.isStaticText)
    }

    func showWeeklyNote(_ text: String) {
        reportNote = text
        Task { try? await Task.sleep(for: .seconds(2.5)); if reportNote == text { reportNote = nil } }
    }

    // MARK: header

    /// `Weekly Report`, the week switcher, the step line, the due day and `ดาวน์โหลด ▾`.
    var weeklyHeader: some View {
        let range = reportWeekRange
        return weeklyCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Weekly Report").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                        // nothing builds or reminds R3 on a schedule yet (§7 Q1)
                        Text("จากรายงานประจำวัน").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
                    }
                    .fixedSize()
                    weeklyWeekSwitcher(range)
                    // portrait: the step line takes a row of its own, so its words aren't cut
                    if weeklyNarrow { Spacer(minLength: 0) } else { weeklySteps.frame(maxWidth: .infinity) }
                    weeklyDue(range)
                    weeklyDownloadButton
                }
                if weeklyNarrow { weeklySteps.fixedSize() }
            }
        }
        .overlay(alignment: .topTrailing) { if reportDownload { weeklyDownloadMenu.offset(x: -12, y: 66) } }
    }

    private func weeklyWeekSwitcher(_ range: ClosedRange<Date>) -> some View {
        let frame = RoundedRectangle(cornerRadius: 14, style: .continuous), atNow = reportWeek >= 0
        return HStack(spacing: 0) {
            Button { reportWeek -= 1 } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Theme.primary)
            .accessibilityLabel("สัปดาห์ก่อน")
            VStack(spacing: 0) {
                Text("สัปดาห์ที่ \(reportContent?.weekNumber ?? 0)").font(.sarabunFixed(14.5, .bold)).foregroundStyle(Theme.navy)
                Text(Self.weekDates(range)).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .frame(minWidth: 178, minHeight: 48)
            .background(Theme.surface)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.borderSubtle).frame(width: 1) }
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSubtle).frame(width: 1) }
            .accessibilityElement(children: .combine)
            Button { reportWeek += 1 } label: {
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(atNow ? Theme.borderControl : Theme.primary)
            .disabled(atNow)
            .accessibilityLabel("สัปดาห์ถัดไป")
        }
        .background(Theme.phonePage, in: frame)
        .clipShape(frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
        .fixedSize()
    }

    /// `28 ก.ย. – 4 ต.ค. 2569`.
    static func weekDates(_ r: ClosedRange<Date>) -> String {
        let cal = RoutineReport.calendar
        let a = cal.dateComponents([.day, .month, .year], from: r.lowerBound), b = cal.dateComponents([.day, .month, .year], from: r.upperBound)
        let m = RoutineReport.thaiMonthsShort
        let left = a.month == b.month ? "\(a.day ?? 0)" : "\(a.day ?? 0) \(m[(a.month ?? 1) - 1])"
        return "\(left) – \(b.day ?? 0) \(m[(b.month ?? 1) - 1]) \((b.year ?? 0) + 543)"
    }

    /// 0 รอข้อมูล, 1 พร้อมส่ง, 2 ส่งแล้ว.
    private var reportStep: Int { reportSent ? 2 : reportChecks.allSatisfy(\.ok) ? 1 : 0 }

    /// `รอข้อมูล — พร้อมส่ง — ส่งแล้ว`.
    private var weeklySteps: some View {
        let step = reportStep, titles = ["รอข้อมูล", "พร้อมส่ง", "ส่งแล้ว"], sent = reportSent
        return HStack(spacing: 6) {
            ForEach(titles.indices, id: \.self) { i in
                if i > 0 {
                    Capsule().fill(i <= step ? Theme.primary : Theme.borderSubtle).frame(width: 22, height: 2)
                }
                let done = i < step || (i == 2 && sent), current = i == step
                let (fill, ink): (Color, Color) = !current ? (.clear, done ? Theme.inkMuted : Theme.borderControl)
                    : i == 0 ? (Theme.warningSoft, Theme.warningInk) : i == 1 ? (Theme.primarySoft, Theme.primary) : (Theme.successSoft, Theme.successInk)
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(done ? Theme.success : current ? ink : Color.clear)
                        if !done && !current { Circle().strokeBorder(Theme.borderControl, lineWidth: 1.5) }
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                        } else {
                            Text("\(i + 1)").font(.sarabunFixed(12, .bold)).foregroundStyle(current ? Theme.onPrimary : Theme.borderControl)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(titles[i]).font(.sarabunFixed(14, current ? .bold : .regular)).foregroundStyle(ink).lineLimit(1)
                }
                .padding(.horizontal, current ? 10 : 2).padding(.vertical, 5)
                .background(fill, in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("สถานะรายงาน " + titles[step])
    }

    /// The first working day after the week ends, and how many days are left; once sent, when.
    private func weeklyDue(_ range: ClosedRange<Date>) -> some View {
        let cal = RoutineReport.calendar
        var due = cal.date(byAdding: .day, value: 1, to: range.upperBound)!
        while !RoutineReport.isWorkingDay(due, settings: job.routineSettings) { due = cal.date(byAdding: .day, value: 1, to: due)! }
        let left = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: due).day ?? 0
        let sent = reportSent
        let value: String
        if sent {
            if let r = reportRecord, !cal.isDateInToday(r.sentAt) { value = "ส่ง " + Self.dayMonthNumber(r.sentAt) } else { value = "ส่งแล้ว" }
        } else {
            let when = left > 0 ? "อีก \(left) วัน" : left == 0 ? "วันนี้" : "เลย \(-left) วัน"
            value = Self.weekdayShort(due) + " \(cal.component(.day, from: due)) " + RoutineReport.thaiMonthsShort[cal.component(.month, from: due) - 1] + " · " + when
        }
        return VStack(alignment: .trailing, spacing: 0) {
            Text(sent ? "ส่งเจ้าของงานแล้ว" : "กำหนดส่งเจ้าของงาน").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabunFixed(15, .bold)).foregroundStyle(sent ? Theme.successInk : Theme.warningInk).lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    /// `จ.`
    static func weekdayShort(_ d: Date) -> String {
        ["อา.", "จ.", "อ.", "พ.", "พฤ.", "ศ.", "ส."][RoutineReport.calendar.component(.weekday, from: d) - 1]
    }

    /// `28/9`.
    static func dayMonthNumber(_ d: Date) -> String {
        let c = RoutineReport.calendar.dateComponents([.day, .month], from: d)
        return "\(c.day ?? 0)/\(c.month ?? 0)"
    }

    private var weeklyDownloadButton: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { reportDownload.toggle() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line").font(.system(size: 15, weight: .semibold))
                Text("ดาวน์โหลด").font(.sarabunFixed(15, .bold))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Theme.navy)
            .padding(.horizontal, 16).frame(height: 48)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderControl))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ดาวน์โหลด")
        .accessibilityValue(reportDownload ? "เปิดอยู่" : "")
    }

    /// `ดาวน์โหลด .pptx` (the sheet) and `ดาวน์โหลด PDF` (the R3 PDF through the share sheet).
    private var weeklyDownloadMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("ดาวน์โหลด .pptx", "rectangle.on.rectangle") { reportDownload = false; reportPptx = true }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            menuRow("ดาวน์โหลด PDF", "doc") {
                reportDownload = false
                if let url = try? RoutineReportFiles.temporaryURL(RoutineReportFiles.weekly(job, week: reportWeekRange.lowerBound)) {
                    reportShare = WeeklyShare(urls: [url], record: nil)
                }
            }
        }
        .frame(width: 230)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
        .shadow(color: Theme.navySolid.opacity(0.16), radius: 12, y: 6)
    }

    private func menuRow(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.sarabunFixed(15)).foregroundStyle(Theme.navy)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: rail

    /// `สไลด์ 8 หน้า`: a tile a slide, its thumbnail, number, label and status dot.
    func weeklyRail(_ c: WeeklySlides.Content) -> some View {
        weeklyCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("สไลด์ \(c.outline.count) หน้า").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    Text("แม่แบบ Weekly Report Template").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(c.outline, id: \.number) { o in railTile(o, c).id(o.number) }
                        }
                        .padding(.horizontal, 10).padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear { proxy.scrollTo(reportSlide + 1, anchor: .center) }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func railTile(_ o: WeeklySlides.Outline, _ c: WeeklySlides.Content) -> some View {
        let on = reportSlide == o.number - 1, frame = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button { reportSlide = o.number - 1 } label: {
            VStack(alignment: .leading, spacing: 5) {
                WeeklySlideView(slide: o, data: c, photos: reportPhotos)
                    .drawingGroup()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.borderSubtle))
                HStack(spacing: 6) {
                    Text("\(o.number)").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted).frame(width: 18, alignment: .leading)
                    Text(o.label).font(.sarabunFixed(12)).foregroundStyle(Theme.navy).lineLimit(1)
                    Spacer(minLength: 0)
                    statusDot(o.ready)
                }
            }
            .padding(6)
            .background(on ? Theme.primarySoft : Color.clear, in: frame)
            .overlay(frame.strokeBorder(on ? Theme.primary : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("สไลด์ \(o.number) \(o.label)")
        .accessibilityValue(o.ready ? "ข้อมูลครบ" : "รอข้อมูล")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func statusDot(_ ready: Bool) -> some View {
        Image(systemName: ready ? "checkmark" : "exclamationmark").font(.system(size: 9, weight: .heavy))
            .foregroundStyle(ready ? Theme.successInk : Theme.onPrimary)
            .frame(width: 18, height: 18)
            .background(ready ? Theme.successSoft : Theme.warning, in: Circle())
            .accessibilityHidden(true)
    }

    // MARK: viewer

    /// `สไลด์ n/8 · <label>`, its chip and arrows, the slide drawn to scale and a dot a slide.
    func weeklyViewer(_ c: WeeklySlides.Content) -> some View {
        let outline = c.outline, i = min(reportSlide, outline.count - 1), o = outline[i]
        return weeklyCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("สไลด์ \(o.number)/\(outline.count) · \(o.label)").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    toneChip(o.ready ? "ข้อมูลครบ" : "รอข้อมูล", o.ready ? .ok : .warn)
                        .accessibilityIdentifier("slideChip")
                    Spacer(minLength: 0)
                    arrowButton("chevron.left", "สไลด์ก่อน", enabled: i > 0) { reportSlide = i - 1 }
                    arrowButton("chevron.right", "สไลด์ถัดไป", enabled: i < outline.count - 1) { reportSlide = i + 1 }
                }
                .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 10)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                VStack(spacing: 18) {
                    Spacer(minLength: 0)
                    WeeklySlideView(slide: o, data: c, photos: reportPhotos)
                        .background(Theme.paper)
                        .shadow(color: Theme.navySolid.opacity(0.14), radius: 6, y: 2)
                    HStack(spacing: 8) {
                        ForEach(outline.indices, id: \.self) { n in
                            Capsule().fill(n == i ? Theme.primary : Theme.borderControl)
                                .frame(width: n == i ? 22 : 8, height: 8)
                                .frame(minWidth: 22, minHeight: 22).contentShape(Rectangle())
                                .onTapGesture { reportSlide = n }
                                .accessibilityHidden(true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.phonePage)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func arrowButton(_ symbol: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Theme.primary : Theme.borderControl)
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
