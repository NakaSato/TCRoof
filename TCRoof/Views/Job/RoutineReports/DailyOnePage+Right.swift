import SwiftUI
import TCRoofUI
import TCRoofCore

// The one-page report's right column, top and bottom (docs/ui/daily-report-ipad-v3): the day bar with its date and
// working-time popovers, and the reporter's sign card.

extension DailyOnePage {
    /// Which of the day bar's popovers is open; one at a time.
    enum Pop: Hashable { case date, time }

    func popBinding(_ p: Pop) -> Binding<Bool> {
        Binding(get: { pop == p }, set: { open in
            if open { pop = p } else if pop == p { pop = nil }
        })
    }

    /// The reporter's signature time on screen: an edited report reads as unsigned until it is saved and signed again.
    var signedAt: Date? {
        #if DEBUG
        if let demoSign { return demoSign.at }
        #endif
        return dirty ? nil : log?.engineerSignedAt
    }

    var drawnSignature: Data? {
        #if DEBUG
        if let demoSign { return demoSign.drawn }
        #endif
        return log?.signature(InstallLog.engineerSignatureTag)?.data
    }

    /// Day key → whether that day's report is signed, for the calendar's dots.
    var reportStates: [String: Bool] {
        Dictionary(job.dailyLogs.map { (RoutineReport.dayKey($0.date), $0.engineerSignedAt != nil) }, uniquingKeysWith: { $0 || $1 })
    }

    // MARK: day bar

    var daySwitcher: some View {
        HStack(spacing: 6) {
            dayStep(-1, icon: "chevron.left", label: "วันก่อน")
            dateButton
            dayStep(1, icon: "chevron.right", label: "วันถัดไป")
                .disabled(RoutineReport.reportDay(from: date, by: 1, settings: settings, limit: .now) == nil)
            timeChip
        }
        .padding(4)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .popover(isPresented: popBinding(.date), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            DailyDatePopover(selected: date, earliest: min(job.installStart, job.dailyLogs.map(\.date).min() ?? date, date),
                             states: reportStates, settings: settings, installStart: job.installStart,
                             pick: pickDay, close: { pop = nil })
                .presentationCompactAdaptation(.popover)
        }
        .background {
            Color.clear.popover(isPresented: popBinding(.time), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                DailyWorkTimePopover(report: $report, date: date, close: { pop = nil }, weather: openWeather)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func dayStep(_ step: Int, icon: String, label: String) -> some View {
        Button { actions.day(step) } label: {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary)
                .frame(width: 44, height: 48)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var dateButton: some View {
        let open = pop == .date
        return Button { pop = open ? nil : .date } label: {
            HStack(spacing: 6) {
                Text(RoutineReport.thaiWeekdayDate(date)).font(.sarabunFixed(16, .bold)).lineLimit(1).minimumScaleFactor(0.75)
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 8))
            }
            .foregroundStyle(open ? Theme.onPrimary : Theme.navy)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(open ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RoutineReport.thaiWeekdayDate(date))
        .accessibilityHint("เลือกวันรายงาน")
        .accessibilityIdentifier("dailyDate")
    }

    private var timeChip: some View {
        let open = pop == .time
        let time = Self.timeText(report.workStart) + "–" + Self.timeText(report.workEnd)
        return Button { pop = open ? nil : .time } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text("เวลาทำงาน").font(.sarabunFixed(11))
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 6))
                    if report.rainHours > 0 { Image(systemName: "cloud.rain").font(.system(size: 10)) }
                }
                .foregroundStyle(open ? Theme.onPrimary.opacity(0.85) : Theme.inkMuted)
                Text(time).font(.sarabunFixed(15, .bold)).monospacedDigit()
                    .foregroundStyle(open ? Theme.onPrimary : Theme.navy)
            }
            .padding(.horizontal, 12).frame(height: 48)
            .background(open ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เวลาทำงาน")
        .accessibilityValue(time)
        .accessibilityIdentifier("dailyWorkTime")
    }

    /// `08.00` → `08:00`.
    static func timeText(_ s: String) -> String {
        RoutineReport.hour(s).map { String(format: "%02d:00", $0) } ?? s.replacingOccurrences(of: ".", with: ":")
    }

    /// Closes the popover, then opens the day through the editor (which keeps or asks about unsaved edits).
    private func pickDay(_ d: Date) {
        pop = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { actions.open(d) }
    }

    private func openWeather() {
        pop = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showWeather = true }
    }

    // MARK: sign

    var signCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 4) {
                Text("ลงนามผู้รายงาน").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                Text("*").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.danger)
                Spacer(minLength: 8)
                Text("SITE ENGINEER").font(.sarabunFixed(11.5, .bold)).tracking(0.8).foregroundStyle(Theme.primary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.primarySoft, in: Capsule())
            }
            Group {
                if let at = signedAt { signedBox(at) } else { idleBox }
            }
            .frame(height: 180)
            VStack(alignment: .leading, spacing: 4) {
                Text("ชื่อผู้ลงนาม").font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
                TextField("ชื่อ Site Engineer ผู้รับเหมา", text: siteEngineerName)
                    .font(.sarabunFixed(17)).multilineTextAlignment(.center)
                    .textFieldStyle(OutlinedFieldStyle(dense: true))
                    .frame(minHeight: 48)
            }
        }
        .padding(16)
        .dailyCard()
    }

    private var siteEngineerName: Binding<String> {
        Binding(get: { job.routineSettings.siteEngineer }, set: { v in
            var s = job.routineSettings
            s.siteEngineer = v
            job.routineSettings = s
        })
    }

    /// The hairline the reporter signs on, 40 pt above the box's bottom, with a small × at its left end.
    private func signLine(_ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                .padding(.leading, 2)
            Rectangle().fill(color).frame(height: 1)
        }
        .padding(.horizontal, 18).padding(.bottom, 40)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var idleBox: some View {
        Button(action: actions.sign) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.borderOutdoor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                signLine(Theme.borderOutdoor)
                VStack(spacing: 2) {
                    Image(systemName: "signature").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary)
                    Text("แตะเพื่อเซ็น").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary)
                    Text("เซ็นบนเส้นด้านล่าง").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                }
                .padding(.bottom, 36)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ผู้รายงาน แตะเพื่อเซ็น")
        .accessibilityIdentifier("dailySign")
    }

    private func signedBox(_ at: Date) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.successSoft)
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.success, lineWidth: 1)
            signLine(Theme.success.opacity(0.45))
            signature
                .padding(.bottom, 44)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .overlay(alignment: .topLeading) {
            Label("ลงนามแล้ว " + ThaiFormat.time.string(from: at), systemImage: "checkmark")
                .font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.successText)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Theme.success.opacity(0.14), in: Capsule())
                .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: actions.clearSignature) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ล้างลายเซ็นผู้รายงาน")
        }
    }

    /// The drawn signature when there is one, else the name in italics.
    @ViewBuilder private var signature: some View {
        let name = settings.siteEngineer
        if let drawn = drawnSignature, let image = UIImage(data: drawn) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 90)
                .accessibilityLabel("ลายเซ็น " + name)
        } else {
            Text(name.isEmpty ? "ลงนามแล้ว" : name)
                .font(.sarabunFixed(22, .bold)).italic().foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 24)
        }
    }
}

// MARK: - Date popover

/// The month calendar under the date button: a dot per day for sent / draft / missing reports, days up to today.
struct DailyDatePopover: View {
    let selected: Date
    /// The earliest month it pages back to.
    let earliest: Date
    /// Day key → signed.
    let states: [String: Bool]
    let settings: RoutineReport.Settings
    let installStart: Date
    let pick: (Date) -> Void
    let close: () -> Void
    @State private var month: Date

    init(selected: Date, earliest: Date, states: [String: Bool], settings: RoutineReport.Settings, installStart: Date,
         pick: @escaping (Date) -> Void, close: @escaping () -> Void) {
        self.selected = selected; self.earliest = earliest; self.states = states; self.settings = settings
        self.installStart = installStart; self.pick = pick; self.close = close
        _month = State(initialValue: selected)
    }

    private var cal: Calendar { RoutineReport.calendar }
    private var today: Date { cal.startOfDay(for: .now) }
    private static let weekdays = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            weekdayRow
            grid
            Rectangle().fill(Theme.hairline).frame(height: 1)
            legend
        }
        .padding(16)
        .frame(width: 384)
        .background(Theme.surface)
    }

    private func shifted(_ n: Int) -> Date? { cal.date(byAdding: .month, value: n, to: month) }
    private func monthIndex(_ d: Date) -> Int { cal.component(.year, from: d) * 12 + cal.component(.month, from: d) }

    private var header: some View {
        let short = RoutineReport.thaiMonthsShort[cal.component(.month, from: today) - 1]
        return HStack(spacing: 4) {
            pageButton(-1, icon: "chevron.left", label: "เดือนก่อน").disabled(monthIndex(month) <= monthIndex(earliest))
            Text(RoutineReport.thaiMonth(month)).font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
            pageButton(1, icon: "chevron.right", label: "เดือนถัดไป").disabled(monthIndex(month) >= monthIndex(today))
            Text("วันนี้ \(cal.component(.day, from: today)) \(short)").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                .lineLimit(1).padding(.leading, 4)
            Spacer(minLength: 4)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 44, height: 44).background(Theme.segmentTrack, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปิด")
        }
    }

    private func pageButton(_ n: Int, icon: String, label: String) -> some View {
        Button { if let m = shifted(n) { month = m } } label: {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primary)
                .frame(width: 32, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Self.weekdays.indices, id: \.self) { i in
                Text(Self.weekdays[i]).font(.sarabunFixed(12, .bold))
                    .foregroundStyle(i == 0 ? Theme.dangerText : Theme.inkMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let g = RoutineReport.monthGrid(month)
        let cells: [Date?] = Array(repeating: nil, count: g.leading) + g.days.map(Optional.some)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(cells.indices, id: \.self) { i in
                if let d = cells[i] { cell(d) } else { Color.clear.frame(height: 44) }
            }
        }
    }

    private func status(_ d: Date) -> RoutineReport.DayStatus {
        RoutineReport.dayStatus(d, signed: states[RoutineReport.dayKey(d)], settings: settings, today: today, from: installStart)
    }

    private func dotColor(_ s: RoutineReport.DayStatus) -> Color {
        switch s {
        case .sent: Theme.success
        case .draft: Theme.warningInk
        case .missing: Theme.danger
        case .none: .clear
        }
    }

    private func statusText(_ s: RoutineReport.DayStatus) -> String {
        switch s {
        case .sent: "ส่งแล้ว"
        case .draft: "ร่าง"
        case .missing: "ยังไม่มีรายงาน"
        case .none: ""
        }
    }

    private func cell(_ d: Date) -> some View {
        let isSelected = cal.isDate(d, inSameDayAs: selected), isToday = cal.isDate(d, inSameDayAs: today)
        let future = d > today, s = status(d)
        return Button { if !isSelected { pick(d) } } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: d))").font(.sarabunFixed(17, isToday || isSelected ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(isSelected ? Theme.onPrimary : future ? Theme.inkFaint : Theme.navy)
                Circle().fill(s == .none ? Color.clear : isSelected ? Theme.onPrimary : dotColor(s)).frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(isSelected ? Theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.primary, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(RoutineReport.thaiWeekdayDate(d) + (s == .none ? "" : " " + statusText(s)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("dailyDay-" + RoutineReport.dayKey(d))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([RoutineReport.DayStatus.sent, .draft, .missing], id: \.self) { s in
                HStack(spacing: 5) {
                    Circle().fill(dotColor(s)).frame(width: 6, height: 6)
                    Text(statusText(s)).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 4)
            Text("เลือกได้ถึงวันนี้").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        }
    }
}

// MARK: - Working-time popover

/// เวลาทำงาน: three presets and start / end steppers of one hour, writing `workStart` / `workEnd` as `08.00`.
struct DailyWorkTimePopover: View {
    @Binding var report: RoutineReport.Daily
    let date: Date
    let close: () -> Void
    /// Opens the weather editor (the 15-hour strip has no room here).
    let weather: () -> Void

    private typealias W = RoutineReport.WorkHours
    private var start: Int { RoutineReport.hour(report.workStart) ?? 8 }
    private var end: Int { RoutineReport.hour(report.workEnd) ?? 17 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("เวลาทำงาน | " + RoutineReport.thaiWeekdayDate(date)).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                        .frame(width: 44, height: 44).background(Theme.segmentTrack, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ปิด")
            }
            presets
            stepper("เริ่มงาน", hour: start, moveEnd: false, id: "workStart")
            stepper("เลิกงาน", hour: end, moveEnd: true, id: "workEnd")
            weatherRow
            HStack(spacing: 12) {
                Text("ทำงาน \(max(end - start, 0)) ชม. | ใช้คำนวณ คน·ชม. และชั่วโมงฝนในเวลางาน")
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: close) { Text("เสร็จ").font(.sarabunFixed(16, .bold)).frame(width: 76, height: 44) }
                    .buttonStyle(TCButtonStyle(.primary, size: .card))
            }
        }
        .padding(16)
        .frame(width: 384)
        .background(Theme.surface)
    }

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(W.presets.indices, id: \.self) { i in
                let p = W.presets[i]
                let on = RoutineReport.hour(p.start) == start && RoutineReport.hour(p.end) == end
                Button { report.workStart = p.start; report.workEnd = p.end } label: {
                    Text(DailyOnePage.timeText(p.start) + "–" + DailyOnePage.timeText(p.end))
                        .font(.sarabunFixed(14, .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(on ? Theme.onPrimary : Theme.navy)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(on ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            if !on { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.borderOutdoor) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func stepper(_ title: String, hour: Int, moveEnd: Bool, id: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.sarabunFixed(16)).foregroundStyle(Theme.navy)
            Spacer(minLength: 8)
            stepButton(moveEnd: moveEnd, by: -1, icon: "minus", label: title + " ลด", id: id + "-")
            Text(String(format: "%02d:00", hour)).font(.sarabunFixed(24, .bold)).monospacedDigit().foregroundStyle(Theme.navy)
                .frame(width: 84)
                .accessibilityLabel(title).accessibilityValue(String(format: "%02d:00", hour))
            stepButton(moveEnd: moveEnd, by: 1, icon: "plus", label: title + " เพิ่ม", id: id + "+")
        }
        .padding(.leading, 14).padding(.trailing, 4)
        .frame(height: 52)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stepButton(moveEnd: Bool, by step: Int, icon: String, label: String, id: String) -> some View {
        let next = W.step(start: start, end: end, moveEnd: moveEnd, by: step)
        return Button {
            guard let next else { return }
            report.workStart = W.text(next.start); report.workEnd = W.text(next.end)
        } label: {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.primary)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderOutdoor))
        }
        .buttonStyle(.plain)
        .opacity(next == nil ? 0.35 : 1)
        .disabled(next == nil)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var weatherRow: some View {
        Button(action: weather) {
            HStack(spacing: 8) {
                Image(systemName: report.rainHours > 0 ? "cloud.rain" : "sun.max").font(.system(size: 15)).foregroundStyle(Theme.primary)
                Text("สภาพอากาศ").font(.sarabunFixed(15)).foregroundStyle(Theme.navy)
                Spacer(minLength: 8)
                Text(report.rainHours > 0 ? "ฝน \(report.rainHours) ชม." : "ไม่มีฝน").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, 14).frame(height: 44)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dailyWeather")
    }
}

/// The day's weather, from the working-time popover's `สภาพอากาศ` row.
struct DailyWeatherSheet: View {
    @Binding var report: RoutineReport.Daily
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 760) {
                PadSection { WeatherCard(weather: $report.weather) }
            }
            .navigationTitle("สภาพอากาศ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() }.bold() } }
        }
    }
}
