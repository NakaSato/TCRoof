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
        let photos = logs.reduce(0) { $0 + $1.sortedPhotos.count }
        let problems = reports.reduce(0) { $0 + $1.problems.filter { !$0.description.isEmpty }.count }
        let planned = job.scheduleInput.map { MasterSchedule.status(plan: MasterSchedule.plan($0), actual: job.scheduleActual, through: w.upperBound).planned }
        let unsigned = logs.filter { $0.engineerSignedAt == nil }.map { Self.dayLabel($0.date) }
        return [
            WeeklyCheck(title: "รายงานประจำวันเซ็นครบ", ok: signed >= working && working > 0,
                        note: "เซ็นแล้ว \(signed)/\(working) วันทำงาน" + (unsigned.isEmpty ? "" : " | " + unsigned.joined(separator: ", ") + " รอเซ็น"), fixable: true),
            WeeklyCheck(title: "แผน MP" + (weekNumber.map { " สัปดาห์ที่ \($0)" } ?? ""), ok: planned != nil,
                        note: planned.map { "แผนสะสม \(Int($0.rounded()))%" } ?? "ยังไม่มีแผน MP", fixable: false),
            WeeklyCheck(title: "รูปหน้างาน", ok: photos > 0, note: "\(photos) รูปจากรายงานประจำวัน", fixable: true),
            WeeklyCheck(title: "ปัญหาและแนวทางแก้ไข", ok: true, note: "รวมจากรายงานประจำวัน \(problems) ข้อ", fixable: false),
        ]
    }

    // MARK: state

    private var reportWeekStart: Date { MasterSchedule.weekStart(reportWeekRange.lowerBound) }
    private var reportKey: String { RoutineReport.dayKey(reportWeekStart) }

    /// The page's send of the week, or `-installDemo YES`'s.
    private var reportRecord: RoutineReport.WeeklySent? {
        #if DEBUG
        if Debug.demo { return reportDemoSent[reportKey] }
        #endif
        return job.weeklySent(for: reportWeekStart)
    }

    /// Sent from the page, or (older data) its PDF filed without a record.
    private var reportSent: Bool {
        #if DEBUG
        if Debug.demo { return reportRecord != nil }
        #endif
        return reportRecord != nil || job.weeklyFiled(reportWeekStart)
    }

    private var reportChecks: [WeeklyCheck] {
        #if DEBUG
        if Debug.demo, let c = reportContent { return Self.demoChecks(c) }
        #endif
        return weeklyChecks(week: reportWeekRange, weekNumber: reportContent?.weekNumber)
    }

    private var reportRecipients: [String] {
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
                note("ส่ง Weekly Report สัปดาห์ที่ \(reportContent?.weekNumber ?? 0) แล้ว")
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

    private func weeklyCard<Content: View>(padding: CGFloat = 14, @ViewBuilder _ content: () -> Content) -> some View {
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

    private func note(_ text: String) {
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

    // MARK: panel

    /// `ความพร้อมก่อนส่ง`, `ส่งถึง` and the send button or the sent line.
    /// `split` (portrait): the checks on the left, the recipients and the send button on the right.
    func weeklyPanel(split: Bool) -> some View {
        weeklyCard(padding: 14) {
            if split {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        panelTitle
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) { ForEach(reportChecks, id: \.title) { c in panelCheck(c) } }
                        }
                        .scrollIndicators(.hidden)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ส่งถึง").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                        recipientChips
                        Spacer(minLength: 0)
                        sendArea
                    }
                    .frame(width: 280)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            } else {
                columnPanel
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var panelTitle: some View {
        let checks = reportChecks, ready = checks.filter(\.ok).count
        return HStack {
            Text("ความพร้อมก่อนส่ง").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
            Spacer()
            Text("\(ready)/\(checks.count)").font(.sarabunFixed(15, .bold)).foregroundStyle(ready == checks.count ? Theme.successInk : Theme.warningInk)
        }
    }

    private var columnPanel: some View {
        let checks = reportChecks
        return VStack(alignment: .leading, spacing: 10) {
                panelTitle
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(checks, id: \.title) { c in panelCheck(c) }
                        Text("ส่งถึง").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).padding(.top, 10)
                            .accessibilityAddTraits(.isHeader)
                        recipientChips
                    }
                }
                .scrollIndicators(.hidden)
                Spacer(minLength: 0)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                sendArea
        }
    }

    /// A check as on the iPhone (`checkRow`'s icon and words), tighter to fit the 300 pt panel.
    private func panelCheck(_ c: WeeklyCheck) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: c.ok ? "checkmark" : "exclamationmark").font(.system(size: 10, weight: .heavy))
                .foregroundStyle(c.ok ? Theme.successInk : Theme.onPrimary)
                .frame(width: 22, height: 22).background(c.ok ? Theme.successSoft : Theme.warning, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(c.title).font(.sarabunFixed(14, .semibold)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.85)
                Text(c.note).font(.sarabunFixed(12.5)).foregroundStyle(c.ok ? Theme.inkMuted : Theme.warningInk).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !c.ok && c.fixable {
                Button { tab = .daily } label: {
                    Text("ไปแก้").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.warningInk)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.warning.opacity(0.6)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(c.ok ? Theme.phonePage : Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if !c.ok { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.warning.opacity(0.45)) }
        }
        .accessibilityElement(children: .contain)
    }

    /// `เจ้าของงาน กปภ.`, `ผู้ตรวจ กฟภ.`, `ทีมภายใน`: picked ✓ on `primarySoft`, else + dashed; fixed once sent.
    private var recipientChips: some View {
        let picked = reportRecipients, locked = reportSent
        return FlowRow(spacing: 8) {
            ForEach(RoutineReport.WeeklySent.groups, id: \.self) { g in
                let on = picked.contains(g)
                Button {
                    var list = picked
                    if on { list.removeAll { $0 == g } } else { list.append(g) }
                    reportTo = RoutineReport.WeeklySent.groups.filter(list.contains)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: on ? "checkmark" : "plus").font(.system(size: 11, weight: .bold))
                        Text(g).font(.sarabunFixed(14, on ? .bold : .regular))
                    }
                    .foregroundStyle(on ? Theme.primary : Theme.inkMuted)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(on ? Theme.primarySoft : Color.clear, in: Capsule())
                    .overlay { if !on { Capsule().strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(locked)
                .accessibilityLabel(g)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var sendArea: some View {
        let n = reportRecipients.count
        if reportSent {
            VStack(alignment: .leading, spacing: 6) {
                Label(sentLine, systemImage: "checkmark").font(.sarabunFixed(14)).foregroundStyle(Theme.successInk)
                Text("ส่งแล้ว · อ่านอย่างเดียว").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                Label("ส่งแล้ว", systemImage: "checkmark").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.successInk)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("ส่งแล้ว")
            }
        } else {
            let ready = reportChecks.allSatisfy(\.ok) && n > 0
            VStack(alignment: .leading, spacing: 6) {
                Text(ready ? "ส่ง .pptx และ .pdf ให้ผู้รับที่เลือก" : "ส่งได้เมื่อเช็กลิสต์ครบ").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                Button("ส่งให้ \(n) ผู้รับ") { sendReport() }
                    .buttonStyle(TCButtonStyle(.primary, size: .page, fullWidth: true))
                    .disabled(!ready)
                    .accessibilityIdentifier("weeklySend")
            }
        }
    }

    /// `ส่ง วันนี้ 11:05 · ถึง 2 ผู้รับ`; `ส่งแล้ว` for a week filed before the record.
    private var sentLine: String {
        guard let r = reportRecord else { return "ส่งแล้ว" }
        let cal = RoutineReport.calendar
        let day = cal.isDateInToday(r.sentAt) ? "วันนี้" : cal.isDateInYesterday(r.sentAt) ? "เมื่อวาน" : Self.dayMonthNumber(r.sentAt)
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = cal.timeZone
        return "ส่ง \(day) \(f.string(from: r.sentAt)) · ถึง \(r.recipients.count) ผู้รับ"
    }

    /// Builds the PDF and the .pptx, files both into the job's documents (so the Drive upload carries them) and opens the
    /// share sheet; the send is recorded once the sheet completes.
    private func sendReport() {
        let record = RoutineReport.WeeklySent(weekStart: reportWeekStart, sentAt: .now, sentBy: permissions.email, recipients: reportRecipients)
        #if DEBUG
        if Debug.demo {
            reportDemoSent[reportKey] = record
            note("ส่ง Weekly Report สัปดาห์ที่ \(reportContent?.weekNumber ?? 0) แล้ว")
            return
        }
        #endif
        let week = reportWeekRange.lowerBound
        let built = RoutineReportFiles.weekly(job, week: week)
        let pdf = RoutineReportFiles.file(built, job: job, context: context)
        let (input, images) = RoutineReportFiles.slidesInput(job, week: week)
        var urls: [URL] = []
        if let url = try? RoutineReportFiles.temporaryURL(built, data: pdf) { urls.append(url) }
        if let deck = try? WeeklySlides.export(input, images: images) {
            let name = WeeklySlides.fileName(week: week, station: job.stationName)
            RoutineReportFiles.file(RoutineReportFiles.Ready(name: name, folder: RoutineReport.folder(.weekly, date: reportWeekStart), data: deck),
                                    job: job, context: context)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            if (try? deck.write(to: url, options: .atomic)) != nil { urls.append(url) }
        }
        try? context.save()
        reportShare = WeeklyShare(urls: urls, record: record)
    }

    // MARK: .pptx sheet

    /// Every slide in two columns, `แชร์` / `✕` and `ปิด` / `ดาวน์โหลด .pptx`.
    var weeklyPptxSheet: some View {
        let c = reportContent, no = c?.weekNumber ?? 0
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("P").font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 46, height: 46).background(Theme.danger, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Weekly Report สัปดาห์ที่ \(no).pptx").font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy)
                    Text("\(c?.outline.count ?? 0) สไลด์ · 16:9 · ใช้แม่แบบ \"Weekly Report Template\" · ข้อมูลจากรายงานประจำวัน แผน MP และรูปที่เลือก")
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Button("แชร์") { shareDeck() }.buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                Button { reportPptx = false } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.navy)
                        .frame(width: 44, height: 44).background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ปิด")
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                if let c {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 26), GridItem(.flexible(), spacing: 26)], spacing: 20) {
                        ForEach(c.outline, id: \.number) { o in
                            VStack(alignment: .leading, spacing: 8) {
                                WeeklySlideView(slide: o, data: c, photos: reportPhotos)
                                    .background(Theme.paper)
                                    .shadow(color: Theme.navySolid.opacity(0.12), radius: 4, y: 1)
                                (Text("\(o.number)").bold() + Text(" · " + o.label)).font(.sarabunFixed(14)).foregroundStyle(Theme.navy)
                            }
                        }
                    }
                    .padding(26)
                }
            }
            .background(Theme.phonePage)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 12) {
                Text("สร้างอัตโนมัติจากงานที่ส่งในสัปดาห์ · ลงแม่แบบต้นฉบับ").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 8)
                Button("ปิด") { reportPptx = false }.buttonStyle(TCButtonStyle(.secondary, size: .page)).fixedSize()
                Button("ดาวน์โหลด .pptx") { shareDeck() }.buttonStyle(TCButtonStyle(.primary, size: .page)).fixedSize()
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .background(Theme.surface)
        .modifier(PageSheetSizing())
        .sheet(item: $reportDeckShare) { share in
            WeeklyShareSheet(urls: share.urls) { _ in reportDeckShare = nil }
        }
    }

    /// The week's .pptx through the share sheet (`-installDemo YES`: the board's example deck).
    private func shareDeck() {
        #if DEBUG
        if Debug.demo {
            let (input, images) = Self.demoReport(week: reportWeekRange.lowerBound, allSigned: reportWeek < 0)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(WeeklySlides.fileName(week: input.week, station: input.stationName))
            if let deck = try? WeeklySlides.export(input, images: images), (try? deck.write(to: url, options: .atomic)) != nil {
                reportDeckShare = WeeklyShare(urls: [url], record: nil)
            }
            return
        }
        #endif
        if let url = try? RoutineReportFiles.weeklySlides(job, week: reportWeekRange.lowerBound) {
            reportDeckShare = WeeklyShare(urls: [url], record: nil)
        }
    }
}

/// The system share sheet for the week's files, telling whether it completed (a send is recorded only then).
struct WeeklyShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    let done: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in done(completed) }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// The .pptx sheet as large as the page allows (iOS 18), else the system's large sheet.
private struct PageSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) { content.presentationSizing(.page) } else { content.presentationDetents([.large]) }
    }
}

/// Chips that wrap onto the next line.
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing; row = max(row, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

#if DEBUG
// MARK: - -installDemo YES

extension InstallTrackingPage {
    /// The board's example week (docs/ui/install-tracking-ipad-weekly-report/assets/sample-data.json) around today:
    /// Monday to Saturday reported (the week runs Monday to Sunday), Friday not signed unless `allSigned`, six drawn
    /// photos; nothing is saved.
    static func demoReport(week: Date, allSigned: Bool) -> (input: WeeklySlides.Input, images: [UUID: Data]) {
        let cal = RoutineReport.calendar, start = WeeklySlides.week(of: week).lowerBound
        let work = [["ติดตั้งแผงหลังคา A–B"], ["เดินสายสตริง 1–6", "เข้าหัว MC4"], ["ติดตั้งตู้ DC combiner", "เดินสายสตริง 7–12"],
                    ["ติดป้ายเตือน"], ["เทฐานอินเวอร์เตอร์"], ["ติดตั้ง Walkway"]]
        let sky: [RoutineReport.Weather] = [.fine, .fine, .cloudy, .cloudy, .rain, .rain]
        let pictures = [("แผงหลังคา A", 0), ("สายสตริง 1–6", 1), ("ตู้ DC", 2), ("สายสตริง 7–12", 2), ("ฐานอินเวอร์เตอร์", 4), ("ภาพรวมหลังคา", 5)]
        var images: [UUID: Data] = [:], days: [WeeklySlides.Day] = [], all: [RoutineReport.Daily] = []
        for i in 0..<6 {
            let date = cal.date(byAdding: .day, value: i, to: start)!
            var r = RoutineReport.Daily(date: date)
            r.progress = work[i].enumerated().map { k, t in .init(task: .structure, description: t, location: "", percent: Double(10 * (i + 1) + k)) }
            for h in r.weather.indices { r.weather[h] = sky[i] }
            if i == 4 { r.problems = [.init(description: "ตู้ AC รออนุมัติ MA-05 (เสี่ยงสูง)", solution: "วัด Voc/Isc และยื่น RFI-03", since: date),
                                      .init(description: "ฝนตกช่วงบ่าย", solution: "ติดตั้งอินเวอร์เตอร์ · ตู้ AC", since: date),
                                      .init(description: "รอการไฟฟ้านัดวันตรวจ", solution: "ทดสอบระบบ · ส่งมอบ", since: date)] }
            var photos: [WeeklySlides.DayPhoto] = []
            for (n, p) in pictures.enumerated() where p.1 == i {
                let id = UUID()
                images[id] = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 520)).jpegData(withCompressionQuality: 0.8) { c in
                    let colors = [UIColor(hue: CGFloat(n) / 6 + 0.45, saturation: 0.32, brightness: 0.9, alpha: 1).cgColor,
                                  UIColor(hue: CGFloat(n) / 6 + 0.55, saturation: 0.55, brightness: 0.75, alpha: 1).cgColor]
                    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
                    c.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 600, y: 520), options: [])
                }
                photos.append(.init(id: id, width: 600, height: 520, caption: p.0))
            }
            days.append(.init(report: r, photos: photos, signed: allSigned || i != 4))
            all.append(r)
        }
        let input = WeeklySlides.Input(stationName: "การประปาบ้านโป่ง", mpNumber: nil, capacityKWp: 90, settings: RoutineReport.Settings(),
                                       week: start, days: days, all: all, schedule: nil, nextRequest: nil, installStart: nil,
                                       asOf: cal.date(byAdding: .day, value: 6, to: start)!)
        return (input, images)
    }

    /// The board's six weeks of plan and actual on slide 3.
    static func demoContent(_ c: WeeklySlides.Content) -> WeeklySlides.Content {
        var c = c
        let plan: [Double] = [6, 14, 24, 33, 41, 52], actual: [Double] = [5, 12, 22, 30, 36, 50]
        let first = c.weekNumber - 5
        var bars: [WeeklySlides.Bar] = []
        for k in 0..<6 {
            bars.append(WeeklySlides.Bar(label: "W" + String(first + k), planned: plan[k], actual: actual[k], current: k == 5))
        }
        c.bars = bars
        c.planned = plan.last; c.actual = actual.last
        return c
    }

    /// The four checks from the example's content.
    static func demoChecks(_ c: WeeklySlides.Content) -> [WeeklyCheck] {
        let working = c.rows.filter { $0.state == .done || $0.state == .waiting }.count
        let signed = c.rows.filter { $0.state == .done }.count
        return [
            WeeklyCheck(title: "รายงานประจำวันเซ็นครบ", ok: c.waiting.isEmpty,
                        note: "เซ็นแล้ว \(signed)/\(working) วันทำงาน" + (c.waiting.isEmpty ? "" : " | " + c.waiting.joined(separator: ", ") + " รอเซ็น"), fixable: true),
            WeeklyCheck(title: "แผน MP สัปดาห์ที่ \(c.weekNumber)", ok: c.planned != nil, note: "แผนสะสม \(Int((c.planned ?? 0).rounded()))%", fixable: false),
            WeeklyCheck(title: "รูปหน้างาน", ok: c.photoCount > 0, note: "\(c.photoCount) รูปจากรายงานประจำวัน", fixable: true),
            WeeklyCheck(title: "ปัญหาและแนวทางแก้ไข", ok: true, note: "รวมจากรายงานประจำวัน \(c.problems.count) ข้อ", fixable: false),
        ]
    }
}
#endif
