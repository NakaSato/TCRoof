import SwiftUI
import TCRoofUI
import TCRoofCore

/// Which picker the new-customer sheet shows. One stable `id`, so switching between the grid and its custom entry
/// swaps the content of the same sheet instead of presenting a second one.
enum NewJobPicker: Identifiable, Equatable {
    case date, dateCustom, time, timeCustom, kWp, kWpCustom, team, install, province
    var id: String { "new-job-picker" }
}

/// The bottom sheet of the new-customer sheet: the board's grid picker for date, time, kWp, team and install timing,
/// the custom entries behind it, and the province sheet.
struct NewJobPickerSheet: View {
    let kind: NewJobPicker
    @Binding var current: NewJobPicker?
    let today: Date
    @Binding var day: Date
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var kWp: Double?
    @Binding var team: Team
    @Binding var installOffset: Int
    @Binding var installDays: Int
    @Binding var province: String

    @State private var contentHeight: CGFloat = 380
    @State private var kWpText = ""
    @FocusState private var kWpFocus: Bool

    private static let times = [(8, 30), (9, 0), (10, 30), (13, 0), (14, 0), (15, 30)]
    private static let kWps: [Double] = [3, 5, 7, 10, 15]
    private static let offsets = [7, 14, 21, 30]
    private static let durations = [1, 2, 3]

    var body: some View {
        Group {
            switch kind {
            case .province:
                NewJobProvinceSheet(province: $province, close: close)
            default:
                measured(content)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.groupedPage.ignoresSafeArea())
        .presentationDetents(kind == .province ? [.large] : [.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(16)
        .environment(\.locale, ThaiFormat.locale)
    }

    private func close() { current = nil }

    /// Sizes the sheet to its content (a bottom sheet, as on the board).
    private func measured(_ view: some View) -> some View {
        view
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { Color.clear.preference(key: SheetHeightKey.self, value: $0.size.height) })
            .onPreferenceChange(SheetHeightKey.self) { h in if h > 0 { contentHeight = h } }
            .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .date: dateGrid
        case .dateCustom: dateCustom
        case .time: timeGrid
        case .timeCustom: timeCustom
        case .kWp: kWpGrid
        case .kWpCustom: kWpCustom
        case .team: teamGrid
        case .install: installGrid
        case .province: EmptyView()
        }
    }

    // MARK: frame

    private func frame(_ title: String, doneAction: (() -> Void)? = nil, @ViewBuilder _ body: () -> some View) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(.sarabun(17, .bold)).foregroundStyle(.primary)
                Spacer()
                Button { (doneAction ?? close)() } label: {
                    Text("เสร็จ").font(.sarabun(16, .semibold)).foregroundStyle(Theme.iosBlue).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            body()
        }
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 28)
    }

    private func grid(_ columns: Int, _ options: [GridOption]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(options) { GridOptionButton(option: $0) }
        }
    }

    /// The full-width `เลือกวันอื่น` / `เวลาอื่น` / `กำหนดเอง` option under a grid.
    private func otherButton(_ title: String, sub: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        GridOptionButton(option: GridOption(id: "other", title: title, sub: sub, selected: selected, action: action))
    }

    // MARK: date, time

    private var dateGrid: some View {
        let days = (0...7).map { today.adding(days: $0) }
        let options = days.enumerated().map { i, d in
            GridOption(id: "d\(i)", title: i == 0 ? "วันนี้" : i == 1 ? "พรุ่งนี้" : NewJobFormat.weekday.string(from: d),
                       sub: ThaiFormat.dayMonthShort.string(from: d), selected: d == day) { day = d; close() }
        }
        let custom = !days.contains(day)
        return frame("วันนัดสำรวจ") {
            VStack(spacing: 8) {
                grid(4, options)
                otherButton(custom ? NewJobFormat.weekdayDayMonth.string(from: day) : "เลือกวันอื่น", sub: custom ? "เลือกวันอื่น" : nil,
                            selected: custom) { current = .dateCustom }
            }
        }
    }

    private var dateCustom: some View {
        frame("เลือกวันอื่น") {
            DatePicker("", selection: Binding(get: { day }, set: { day = $0.startOfDay }),
                       in: today..., displayedComponents: .date)
                .datePickerStyle(.graphical).labelsHidden()
                .environment(\.calendar, Calendar(identifier: .buddhist))
                .tint(Theme.iosBlue)
        }
    }

    private var timeGrid: some View {
        let options = Self.times.map { h, m in
            GridOption(id: "t\(h)\(m)", title: String(format: "%02d:%02d น.", h, m), sub: h < 12 ? "ช่วงเช้า" : "ช่วงบ่าย",
                       selected: h == hour && m == minute) { hour = h; minute = m; close() }
        }
        let custom = !Self.times.contains { $0.0 == hour && $0.1 == minute }
        return frame("เวลานัด") {
            VStack(spacing: 8) {
                grid(3, options)
                otherButton(custom ? String(format: "%02d:%02d น.", hour, minute) : "เวลาอื่น", sub: custom ? "เวลาอื่น" : nil,
                            selected: custom) { current = .timeCustom }
            }
        }
    }

    private var timeCustom: some View {
        frame("เวลาอื่น") {
            DatePicker("", selection: Binding(
                get: { NewJobRules.surveyDate(day: today, hour: hour, minute: minute) },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); hour = c.hour ?? hour; minute = c.minute ?? minute }
            ), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).labelsHidden()
        }
    }

    // MARK: kWp

    private var kWpGrid: some View {
        let options = Self.kWps.map { v in
            GridOption(id: "k\(v)", title: "\(Int(v)) kWp", sub: "~\(NewJobRules.panelCount(kWp: v)) แผง", selected: kWp == v) {
                kWp = kWp == v ? nil : v   // tapping the chosen size again clears it (ยังไม่ทราบ)
                close()
            }
        }
        let custom = kWp.map { !Self.kWps.contains($0) } ?? false
        return frame("ขนาดระบบโดยประมาณ") {
            VStack(spacing: 8) {
                grid(3, options)
                otherButton(custom ? "\(kWp!.formatted(.number.precision(.fractionLength(0...1)))) kWp" : "กำหนดเอง",
                            sub: custom ? "กำหนดเอง" : "แป้นตัวเลข", selected: custom) {
                    kWpText = kWp.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
                    current = .kWpCustom
                }
            }
        }
    }

    private var kWpCustom: some View {
        let check = NewJobRules.checkKWp(kWpText)
        var value: Double?
        if case let .ok(v) = check { value = v }
        return frame("ขนาดระบบ (kWp)") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("1 – 100", text: $kWpText)
                    .keyboardType(.decimalPad).focused($kWpFocus).font(.sarabun(22, .bold)).monospacedDigit()
                    .padding(.horizontal, 14).frame(minHeight: 52)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(NewJobRules.kWpMessage(check) ?? "1 – 100 kWp ทีละ 0.5").font(.sarabun(13))
                    .foregroundStyle(check == .tooHigh || check == .tooLow || check == .notStep ? Theme.dangerText : Theme.groupFooter)
                Button {
                    if let value { kWp = value; close() }
                } label: {
                    Text("ตกลง").font(.sarabun(17, .bold)).foregroundStyle(value == nil ? Theme.groupFooter : .white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(value == nil ? AnyShapeStyle(Theme.separatorLine) : AnyShapeStyle(Theme.actionGradient),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain).disabled(value == nil)
            }
        }
        .onAppear { kWpFocus = true }
    }

    // MARK: team, install

    private var teamGrid: some View {
        let options = Team.allCases.map { t in
            GridOption(id: t.rawValue, title: t.rawValue, dot: t.color, selected: t == team) { team = t; close() }
        }
        return frame("ทีม") { grid(2, options) }
    }

    private var installGrid: some View {
        let offsets = Self.offsets.map { n in
            GridOption(id: "o\(n)", title: "+\(n) วัน",
                       sub: NewJobFormat.weekdayDayMonth.string(from: NewJobRules.installRange(survey: day, offsetDays: n, days: 1).start),
                       selected: n == installOffset) { installOffset = n }
        }
        let durations = Self.durations.map { n in
            GridOption(id: "n\(n)", title: "\(n) วัน", sub: "ระยะติดตั้ง", selected: n == installDays) { installDays = n }
        }
        return frame("เริ่มติดตั้ง (หลังนัดสำรวจ)") { grid(3, offsets + durations) }
    }
}

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Grid option

struct GridOption: Identifiable {
    let id: String
    var title: String
    var sub: String?
    var dot: Color?
    var selected: Bool
    var action: () -> Void
}

/// One 56 pt option: selected has a 2 pt blue border and `optionSelected` fill.
private struct GridOptionButton: View {
    let option: GridOption

    var body: some View {
        Button(action: option.action) {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    if let dot = option.dot { Circle().fill(dot).frame(width: 10, height: 10) }
                    Text(option.title).font(.sarabun(16, .semibold)).foregroundStyle(.primary)
                }
                if let sub = option.sub { Text(sub).font(.sarabun(12)).foregroundStyle(.primary).opacity(0.75) }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(option.selected ? Theme.optionSelected : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(option.selected ? Theme.iosBlue : Theme.separatorLine, lineWidth: option.selected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(option.selected ? .isSelected : [])
    }
}
