import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore

// MARK: - Month grid

struct PlanDayInfo {
    let date: Date
    let inMonth: Bool
    let isSelected: Bool
    let installs: Int
    /// Appointments plus NO.224 reports that day.
    let surveys: Int
}

struct PlanBarItem: Identifiable {
    let bar: PlanLayout.Bar<PersistentIdentifier>
    let job: Job
    var id: PersistentIdentifier { bar.id }
}

/// One week of the month grid: seven tappable day cells with the install bars drawn over them.
/// Tracks top to bottom: date 32, three bar lanes of 20 with 2 pt gaps, then the survey pill.
struct PlanWeekRow: View {
    let days: [PlanDayInfo]
    let bars: [PlanBarItem]
    let select: (Date) -> Void

    private static let laneTop: CGFloat = 34
    private static let laneStep: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days.indices, id: \.self) { i in
                PlanDayCell(day: days[i]) { select(days[i].date) }
                    .overlay(alignment: .leading) {
                        if i > 0 { Rectangle().fill(Theme.borderSubtle).frame(width: 1) }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                let column = geo.size.width / 7
                ForEach(bars) { item in
                    PlanInstallBar(item: item, width: column * CGFloat(item.bar.span))
                        .offset(x: column * CGFloat(item.bar.startColumn), y: Self.laneTop + Self.laneStep * CGFloat(item.bar.lane))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct PlanDayCell: View {
    let day: PlanDayInfo
    let action: () -> Void

    private var number: String {
        let d = Calendar.current.component(.day, from: day.date)
        return d == 1 ? ThaiFormat.dayMonthShort.string(from: day.date) : "\(d)"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                dateLabel
                Spacer(minLength: 0)
                if day.surveys > 0 { PlanSurveyPill(count: day.surveys) }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background)
            .overlay {
                if day.isSelected { Rectangle().strokeBorder(Theme.primary, lineWidth: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.date.thaiLong), \(day.installs) งานติดตั้ง" + (day.surveys > 0 ? ", นัดสำรวจ \(day.surveys)" : ""))
        .accessibilityAddTraits(day.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var background: Color {
        if day.isSelected { return Theme.primarySoft }
        return day.date.isWeekend || !day.inMonth ? Theme.paperPage : .white
    }

    @ViewBuilder private var dateLabel: some View {
        if day.date.isToday {
            Text(number)
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 6).frame(minWidth: 26, minHeight: 24)
                .background(Theme.primary, in: Capsule())
        } else {
            Text(number)
                .font(.system(size: 15, weight: day.inMonth ? .bold : .regular))
                .foregroundStyle(day.inMonth ? Theme.navy : Theme.muted)
                .frame(minHeight: 24)
        }
    }
}

/// `นัดสำรวจ n`: white, dashed control border, capsule.
private struct PlanSurveyPill: View {
    let count: Int

    var body: some View {
        Text("นัดสำรวจ \(count)")
            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.navy)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 8).frame(height: 20)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
    }
}

/// An install job across the days it runs in one week. Edges carried over from or into another week are square.
private struct PlanInstallBar: View {
    let item: PlanBarItem
    let width: CGFloat

    private var bar: PlanLayout.Bar<PersistentIdentifier> { item.bar }
    private var job: Job { item.job }

    private var title: String {
        bar.span == 1 ? job.team.rawValue : "\(job.team.rawValue) · \(PlanLayout.shortName(job.customerName))"
    }

    private var detail: String {
        bar.span == 1 ? "" : "  " + (bar.continuesBefore ? "ต่อ · " : "") + "\(job.installDays) วัน · \(job.capacityKW.kw)"
    }

    var body: some View {
        let leading: CGFloat = bar.continuesBefore ? 0 : 4
        let trailing: CGFloat = bar.continuesAfter ? 0 : 4
        (Text(title).bold().foregroundColor(Theme.navy) + Text(detail).foregroundColor(Theme.inkMuted))
            .font(.system(size: 12))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(width: max(width - leading - trailing, 0), height: 20, alignment: .leading)
            .background(job.team.color.opacity(0.18),
                        in: UnevenRoundedRectangle(topLeadingRadius: leading, bottomLeadingRadius: leading,
                                                   bottomTrailingRadius: trailing, topTrailingRadius: trailing))
            .clipped()
            .padding(.leading, leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ติดตั้ง ทีม \(job.team.rawValue) \(job.code) \(job.customerName) \(job.installDays) วัน")
    }
}

// MARK: - Controls

/// `‹  วันนี้  ›` in one segmented group.
struct PlanMonthStepper: View {
    let previous: () -> Void
    let today: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: "เดือนก่อนหน้า", action: previous)
            Button(action: today) {
                Text("วันนี้")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.navy)
                    .padding(.horizontal, 12).frame(minWidth: 52, minHeight: 38)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .cardShadow()
            }
            .buttonStyle(.plain)
            arrow("chevron.right", label: "เดือนถัดไป", action: next)
        }
        .padding(3)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderSubtle))
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.navy)
                .frame(width: 44, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Team filter chip: dot, name and the team's installs this month.
struct PlanTeamChip: View {
    let title: String
    let color: Color
    let count: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                Text("\(count)").fontWeight(.regular).foregroundStyle(Theme.muted)
            }
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1).fixedSize()
            .foregroundStyle(isOn ? Theme.navy : Theme.inkMuted)
            .padding(.horizontal, 12).frame(height: 36)
            .background(isOn ? Theme.primarySoft : .white, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Theme.navy : Theme.borderSubtle))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(count) งาน")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Day panel rows

/// Small light-blue badge: `Day 2/4`, `แบบ กปภ.`.
struct PlanInfoBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.navy)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Theme.primarySoft, in: Capsule())
    }
}

/// A survey appointment or NO.224 report in the day panel.
struct PlanSurveyRow: View {
    let title: String
    let detail: String
    /// A NO.224 report, or an appointment with one behind it.
    let isReport: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.clipboard").font(.system(size: 17)).foregroundStyle(Theme.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Text(detail).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            Spacer(minLength: 0)
            if isReport { PlanInfoBadge(title: "แบบ กปภ.") }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderSubtle))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// An install job on the selected day: team stripe, code with `Day d/n`, customer, kW and province, team pill.
struct PlanDayJobRow: View {
    let job: Job
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.code).font(.system(size: 16, weight: .bold))
                Spacer(minLength: 8)
                if let day = job.installDay(on: date) { PlanInfoBadge(title: "Day \(day)/\(job.installDays)") }
            }
            Text(job.customerName).font(.system(size: 16)).lineLimit(1)
            HStack(spacing: 6) {
                Label(job.capacityKW.kw, systemImage: "bolt").fontWeight(.bold)
                Text("·")
                Label(job.province, systemImage: "mappin.and.ellipse").lineLimit(1)
            }
            .font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
            .labelStyle(TightIconLabel(spacing: 4))
            HStack(spacing: 6) {
                Circle().fill(job.team.color).frame(width: 8, height: 8)
                Text("ทีม \(job.team.rawValue)").font(.system(size: 12, weight: .bold))
            }
            .padding(.horizontal, 8).frame(height: 22)
            .overlay(Capsule().strokeBorder(Theme.borderControl))
        }
        .foregroundStyle(Theme.navy)
        .padding(14).padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) { Rectangle().fill(job.team.color).frame(width: 4) }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderSubtle))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
