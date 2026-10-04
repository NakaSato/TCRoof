import SwiftUI

// MARK: - Page chrome

struct ModuleIllustration: View {
    let symbol: String
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.primarySoft)
                .frame(width: size * 0.62, height: size * 0.75)
                .rotationEffect(.degrees(-14))
                .offset(x: -size * 0.12)
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.primary)
                .frame(width: size * 0.62, height: size * 0.75)
                .rotationEffect(.degrees(6))
            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(6))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PageHeader<Accessory: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.navy)
                accessory
            }
            Spacer()
            ModuleIllustration(symbol: symbol, size: isPhone ? 72 : 120)
        }
    }
}

struct HeaderLink<Destination: View>: View {
    let title: String
    var systemImage = "clock.arrow.circlepath"
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .underline()
                .foregroundStyle(Theme.navy)
        }
    }
}

/// Back, page title over the breadcrumb, and `trailing` (usually a `TopBarLink`), on a white bar.
/// Pages using it hide the navigation bar.
struct PageTopBar<Trailing: View>: View {
    let title: String
    /// Pages before this one, e.g. `["หน้าหลัก", "สำรวจหน้างาน"]`.
    let trail: [String]
    let current: String
    var backLabel = "กลับหน้าหลัก"
    @ViewBuilder var trailing: Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .secondaryButtonFrame()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backLabel)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.navy)
                (Text(trail.map { "\($0) › " }.joined()) + Text(current).bold().foregroundColor(Theme.navy))
                    .font(.system(size: 14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing
        }
        .foregroundStyle(Theme.navy)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(minHeight: 72)
        .background(.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }
}

/// The secondary button on the right of a `PageTopBar`.
struct TopBarLink<Destination: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .bold))
                .padding(.horizontal, 16).frame(minHeight: 44)
                .secondaryButtonFrame()
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Design system `tc-btn secondary`: white, 1 pt control border, radius 8.
    func secondaryButtonFrame() -> some View {
        background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderControl))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FloatingButton: View {
    let systemImage: String
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(Theme.tealGradient, in: Circle())
                .shadow(color: Theme.teal.opacity(0.4), radius: 10, y: 4)
        }
        .accessibilityLabel(accessibilityLabel)
        .padding(28)
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

struct StatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
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
            footer()
        }
        .cardStyle()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if showTeam {
                    Label("งานติดตั้งระบบโซลาร์", systemImage: "square.grid.3x3.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.navy)
                    TeamTag(team: job.team)
                }
                Spacer()
                Image(systemName: "arrow.right.square.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
            }
            Text("\(dateLabel) : \(date.thaiLong)")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Divider().padding(.vertical, 4)
            HStack(spacing: 4) {
                Text(job.code).fontWeight(.bold).foregroundStyle(Theme.navy)
                Text(": \(job.status.title)").foregroundStyle(job.status.color)
            }
            .font(.subheadline)
            Text("ชื่อโครงการ : \(job.projectName)")
                .font(.subheadline)
                .foregroundStyle(Theme.navy)
            HStack(spacing: 16) {
                Label(job.customerName, systemImage: "person")
                Label(job.capacityKW.kw, systemImage: "bolt.fill")
            }
            .font(.footnote)
            .foregroundStyle(Theme.navy.opacity(0.85))
            Label(job.province, systemImage: "mappin.and.ellipse")
                .font(.footnote)
                .foregroundStyle(Theme.navy.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension JobCard where Footer == EmptyView {
    init(job: Job, dateLabel: String, date: Date, showTeam: Bool = true,
         @ViewBuilder destination: @escaping () -> Destination) {
        self.init(job: job, dateLabel: dateLabel, date: date, showTeam: showTeam,
                  destination: destination, footer: { EmptyView() })
    }
}

/// Tinted capsule, optionally led by a dot (team and status on the job card).
struct DotPill: View {
    let title: String
    let color: Color
    var dot = false

    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(color).frame(width: 7, height: 7) }
            Text(title)
        }
        .font(.system(size: 12.5, weight: .bold)).foregroundStyle(color).lineLimit(1).fixedSize()
        .padding(.horizontal, 10).frame(height: 24)
        .background(color.opacity(dot ? 0.1 : 0.12), in: Capsule())
    }
}

struct TightIconLabel: LabelStyle {
    var spacing: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) { configuration.icon; configuration.title }
    }
}

struct GradientButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.tealGradient, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// True on iPhone, where screens are narrow and layouts collapse to a single column.
let isPhone = UIDevice.current.userInterfaceIdiom == .phone

let cardColumns = [GridItem(.adaptive(minimum: isPhone ? 280 : 380), spacing: 16)]

// MARK: - Form helpers

struct FieldLabel: View {
    let title: String
    var required = false

    var body: some View {
        (Text(title).foregroundStyle(Theme.navy) + Text(required ? " *" : "").foregroundStyle(Theme.danger))
            .font(.headline)
    }
}

struct ChoiceButton: View {
    let title: String
    let selected: Bool
    var tint: Color = Theme.mint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.navy)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(selected ? tint : .white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(selected ? 0.2 : 0.5)))
        }
        .buttonStyle(.plain)
    }
}

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
