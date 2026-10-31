import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore

// MARK: - Parts

/// A day number in its circle: selected navy with light text, today primary text, other months faded.
struct PlanPhoneDayNumber: View {
    let date: Date
    let size: CGFloat
    let isSelected: Bool
    let isToday: Bool
    let inMonth: Bool

    var body: some View {
        Text("\(Calendar.current.component(.day, from: date))")
            .font(.sarabun(15.5, isSelected || isToday ? .bold : .regular, relativeTo: .body)).monospacedDigit()
            .foregroundStyle(isSelected ? Theme.onPrimary : isToday ? Theme.primary : inMonth ? Theme.navy : Theme.dayOutside)
            .frame(width: size, height: size)
            .background { if isSelected { Circle().fill(Theme.navy) } }
    }
}

/// The survey appointment mark: a 6 pt pink square turned 45°.
struct PlanSurveyDiamond: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1).fill(Theme.survey)
            .frame(width: 6, height: 6)
            .rotationEffect(.degrees(45)).scaleEffect(0.9)
    }
}

/// Under a month row: one 5 pt line per install job on its lane, inset 5 pt where the job starts or ends and
/// square where it carries over from or into another week.
struct PlanRangeLines: View {
    let segments: [PlanLayout.Bar<PersistentIdentifier>]
    let jobs: [PersistentIdentifier: Job]

    private static let lane: CGFloat = 5
    private static let gap: CGFloat = 3

    var body: some View {
        let lanes = (segments.map(\.lane).max() ?? -1) + 1
        GeometryReader { geo in
            let column = geo.size.width / 7
            ForEach(segments, id: \.id) { bar in
                if let job = jobs[bar.id] { line(bar, job, column: column) }
            }
        }
        .frame(height: max(CGFloat(lanes) * Self.lane + CGFloat(max(lanes - 1, 0)) * Self.gap, Self.lane))
    }

    private func line(_ bar: PlanLayout.Bar<PersistentIdentifier>, _ job: Job, column: CGFloat) -> some View {
        let leading: CGFloat = bar.continuesBefore ? 0 : 5
        let trailing: CGFloat = bar.continuesAfter ? 0 : 5
        let r: (CGFloat, CGFloat) = (bar.continuesBefore ? 0 : 3, bar.continuesAfter ? 0 : 3)
        return UnevenRoundedRectangle(topLeadingRadius: r.0, bottomLeadingRadius: r.0, bottomTrailingRadius: r.1, topTrailingRadius: r.1)
            .fill(job.team.color)
            .frame(width: max(column * CGFloat(bar.span) - leading - trailing, 0), height: Self.lane)
            .offset(x: column * CGFloat(bar.startColumn) + leading, y: CGFloat(bar.lane) * (Self.lane + Self.gap))
            .accessibilityElement()
            .accessibilityLabel("ทีม \(job.team.rawValue.suffix(2)) | \(planPhoneNickname(job)) | ช่วงติดตั้ง")
    }
}

/// The project without `คุณ` / `บริษัท`, first word only: `ดารา`.
func planPhoneNickname(_ job: Job) -> String {
    let name = PlanLayout.shortName(job.projectName)
    return name.split(separator: " ").first.map(String.init) ?? name
}

/// A job's days in the week view: team tint at 20 %, a 4 pt solid leading edge, `TCR01 | <project>` or just `01`.
struct PlanWeekBar: View {
    let bar: PlanLayout.Bar<PersistentIdentifier>
    let job: Job

    var body: some View {
        let color = job.team.color
        let label = bar.span >= 3 ? "\(job.team.rawValue) | \(job.projectName)" : String(job.team.rawValue.suffix(2))
        GeometryReader { geo in
            let column = geo.size.width / 7
            Text(label)
                .font(.sarabun(11, .bold, relativeTo: .caption)).foregroundStyle(color)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(width: max(column * CGFloat(bar.span) - 6, 0), height: 20, alignment: .leading)
                .background(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        color.opacity(0.2)
                        color.frame(width: 4)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .offset(x: column * CGFloat(bar.startColumn) + 3)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ติดตั้ง ทีม \(job.team.rawValue) \(job.projectName) \(bar.span) วันในสัปดาห์นี้")
    }
}

/// The team filter's dropdown: `ทุกทีม` (a four-colour dot), then each team, the selected row tinted with a check.
struct PlanTeamMenu: View {
    static let width: CGFloat = 170
    let selection: Team?
    let pick: (Team?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            row(nil)
            ForEach(Team.allCases) { row($0) }
        }
        .padding(6)
        .frame(width: Self.width)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
        .compositingGroup()
        .shadow(color: Theme.navy.opacity(0.18), radius: 14, y: 10)
    }

    private func row(_ t: Team?) -> some View {
        let on = t == selection
        let label = t.map { "ทีม \($0.rawValue.suffix(2))" } ?? "ทุกทีม"
        return Button { pick(t) } label: {
            HStack(spacing: 10) {
                dot(t)
                Text(label).font(.sarabun(14.5, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: 0)
                if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.primary) }
            }
            .padding(.horizontal, 10)
            .frame(height: touchMin)
            .background(on ? Theme.rowSelected : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func dot(_ t: Team?) -> some View {
        if let t {
            Circle().fill(t.color).frame(width: 10, height: 10)
        } else {
            let colors = Team.allCases.map(\.color)
            let stops = colors.enumerated().flatMap { i, c in
                [Gradient.Stop(color: c, location: Double(i) / 4), Gradient.Stop(color: c, location: Double(i + 1) / 4)]
            }
            Circle().fill(AngularGradient(stops: stops, center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
                .frame(width: 10, height: 10)
        }
    }
}

/// An agenda row: white, bordered, a 4 pt leading rule, title and subtitle, an optional day-by-day progress,
/// and the trailing time or day count.
struct PlanAgendaRow<Trailing: View>: View {
    let rule: Color
    let title: String
    let subtitle: String
    var progress: (done: Int, total: Int, color: Color)?
    @ViewBuilder var trailing: Trailing

    init(rule: Color, title: String, subtitle: String, progress: (done: Int, total: Int, color: Color)? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.rule = rule; self.title = title; self.subtitle = subtitle; self.progress = progress; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabun(15.5, .bold, relativeTo: .body)).foregroundStyle(Theme.navy).lineLimit(1)
                Text(subtitle).font(.sarabun(13, relativeTo: .subheadline)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                if let progress {
                    HStack(spacing: 3) {
                        ForEach(0..<progress.total, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(i < progress.done ? progress.color : Theme.headerLine).frame(height: 4)
                        }
                    }
                    .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 10).padding(.trailing, 12).padding(.leading, 12 + 4 + 12)
        .frame(minHeight: 64)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(rule).frame(width: 4).padding(.vertical, 10).padding(.leading, 12)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
