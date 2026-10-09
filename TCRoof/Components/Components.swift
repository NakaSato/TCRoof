import SwiftUI
import TCRoofUI

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
    /// Opened from a search field elsewhere (the iPad home bar): the keyboard comes up at once.
    var focusOnAppear = false
    @FocusState private var searching: Bool

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
                    .focused($searching)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                }
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.navy)
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.5)))
        }
        .task {
            // after the push animation, or the focus is dropped
            guard focusOnAppear else { return }
            try? await Task.sleep(for: .milliseconds(450))
            searching = true
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
