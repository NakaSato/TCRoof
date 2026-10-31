import SwiftUI
import TCRoofUI
import TCRoofCore
import ExcelExport

extension InstallTrackingPage {
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
            showWeeklyNote("ส่ง Weekly Report สัปดาห์ที่ \(reportContent?.weekNumber ?? 0) แล้ว")
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
