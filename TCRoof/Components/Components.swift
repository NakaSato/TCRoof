import SwiftUI
import TCRoofUI

// MARK: - Page chrome

/// The secondary button on the right of a `TCNavBar`.
struct TopBarLink<Destination: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            Label(title, systemImage: systemImage).labelStyle(TCIconTitleLabel())
        }
        .buttonStyle(TCButtonStyle(.secondary, fullWidth: false))
    }
}

// MARK: - Tags

struct TeamTag: View {
    let team: Team

    var body: some View {
        Text(team.rawValue)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(team.color, in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Filter + search

struct QueueFilterBar: View {
    let listTitle: String
    let prefix: String
    @Binding var window: DateWindow
    @Binding var search: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(listTitle).font(.headline).foregroundStyle(Theme.navy)
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Theme.navy, in: Circle())
            }
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DateWindow.allCases) { option in
                    Button {
                        window = option
                    } label: {
                        Text(option.label(prefix))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(window == option ? Theme.primary : Theme.chip.opacity(0.75), in: Capsule())
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            HStack {
                TextField("ค้นหาด้วยชื่อลูกค้าหรือรหัสโครงการ", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                }
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.navy)
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.5)))
        }
    }
}

// MARK: - Job card

/// iPad install-queue card (scan, install), in the survey list's card style (docs/ui/survey-list):
/// project and team, code and status, customer and kW, then the install dates; `footer` below (`JobCardStrip`).
struct JobCard<Destination: View, Footer: View>: View {
    let job: Job
    let dateLabel: String
    let date: Date
    var showTeam = true
    @ViewBuilder var destination: () -> Destination
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(destination: destination) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            footer()
        }
        .cardStyle()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(job.projectName).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.navy)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if showTeam {
                    TCStatusChip("ทีม \(job.team.rawValue)", fill: job.team.color.opacity(0.1), text: job.team.color, dot: true)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                Text(job.code).font(.caption.bold()).foregroundStyle(Theme.inkMuted)
                TCStatusChip(job.status.title, fill: job.status.color.opacity(0.12), text: job.status.color)
            }
            HStack(spacing: 16) {
                if job.customerName != job.projectName { Label(job.customerName, systemImage: "person").lineLimit(1) }
                Label(job.capacityKW.kw, systemImage: "bolt.fill")
            }
            .font(.footnote)
            .foregroundStyle(Theme.navy.opacity(0.85))
            Divider().padding(.vertical, 4)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(date.thaiLong, systemImage: "calendar").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.navy)
                Text(dateLabel).font(.caption).foregroundStyle(Theme.muted)
            }
            Label(job.province, systemImage: "mappin.and.ellipse").font(.footnote).foregroundStyle(Theme.navy.opacity(0.85))
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The box under a `JobCard`, like the survey card's progress box: `แผง` · `12/26` · 46 %, an optional bar.
struct JobCardStrip: View {
    let key: String
    let value: String
    var valueColor: Color = Theme.navy
    /// 0…1; nil hides the percent and the bar.
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(key).font(.caption).foregroundStyle(Theme.inkMuted)
                Text(value).font(.subheadline.bold()).foregroundStyle(valueColor).lineLimit(1)
                Spacer(minLength: 0)
                if let progress {
                    Text("\(Int((progress * 100).rounded()))%").font(.subheadline.bold()).monospacedDigit()
                        .foregroundStyle(progress <= 0 ? Theme.progressZero : progress >= 1 ? Theme.progressFull : Theme.primary)
                }
            }
            if let progress {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(progress >= 1 ? Theme.progressFull : Theme.primary).frame(width: g.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.progressBoxIdle, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

extension JobCard where Footer == EmptyView {
    init(job: Job, dateLabel: String, date: Date, showTeam: Bool = true,
         @ViewBuilder destination: @escaping () -> Destination) {
        self.init(job: job, dateLabel: dateLabel, date: date, showTeam: showTeam,
                  destination: destination, footer: { EmptyView() })
    }
}

struct TightIconLabel: LabelStyle {
    var spacing: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) { configuration.icon; configuration.title }
    }
}

/// True on iPhone, where screens are narrow and layouts collapse to a single column.
let isPhone = UIDevice.current.userInterfaceIdiom == .phone

let cardColumns = [GridItem(.adaptive(minimum: isPhone ? 280 : 380), spacing: 16)]

// MARK: - Form helpers

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Theme.muted)
            Spacer(minLength: 16)
            Text(value).foregroundStyle(Theme.navy).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
