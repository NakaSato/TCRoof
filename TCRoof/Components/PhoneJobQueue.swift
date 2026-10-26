import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore

/// The iPhone install-date queues (`ติดตั้ง` tab, `สแกนอุปกรณ์`), in the style of the survey list
/// (docs/ui/tcroof-survey-list-iphone): gradient header with the count and a history button, any extra filter,
/// the 7 วัน / 30 วัน / ทั้งหมด filter over the install dates, the search field, one card per job and the FAB.
/// As on the survey list, an active query searches every job and ignores the date window.
struct PhoneJobQueue<Extra: View, History: View, Card: View>: View {
    let title: String
    /// `งานติดตั้ง` in `งานติดตั้ง 4 งาน`.
    let noun: String
    let historyLabel: String
    let fabSymbol: String
    let fabLabel: String
    let fab: () -> Void
    @ViewBuilder let extraControls: () -> Extra
    @ViewBuilder let history: () -> History
    @ViewBuilder let card: (Job) -> Card

    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var window: DateWindow = .week
    @State private var search = ""
    @FocusState private var searching: Bool

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private var filtered: [Job] {
        jobs.filter { query.isEmpty ? window.overlaps($0.installInterval) : $0.matches(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if filtered.isEmpty {
                    Text("ไม่พบ\(noun)").font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 16)
                }
                ForEach(filtered) { card($0) }
            }
            // the last card clears the FAB (60 + 16); the tab bar is already a safe-area inset
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 76)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                TCGradientHeader(title: title,
                                 subtitle: query.isEmpty ? "\(noun) \(filtered.count) งาน" : "ผลการค้นหา \(filtered.count) งาน") {
                    NavigationLink(destination: history) { TCHeaderIcon("clock") }
                        .buttonStyle(.plain)
                        .accessibilityLabel(historyLabel)
                }
                controls
            }
            .background(Theme.background)
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            TCFab(fabSymbol, accessibilityLabel: fabLabel, gradient: Theme.tealGradient, action: fab)
                .tcFabPlacement(compact: true)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            extraControls()
            TCSegmented(DateWindow.allCases.map(\.shortLabel),
                        selection: Binding(get: { window.shortLabel },
                                           set: { t in window = DateWindow.allCases.first { $0.shortLabel == t } ?? .week }),
                        fontSize: 14, style: .filter)
            PhoneSearchField(text: $search, focused: $searching)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
    }
}

/// An iPhone install-queue card: project and team, code and kW, the install dates (`InstallWhen`), then `status`.
/// The whole card opens `destination`. A job installing today has a primary border.
struct CompactJobCard<Destination: View, Status: View>: View {
    let job: Job
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let status: () -> Status

    private var today: Int? { job.installDay(on: .now) }
    private var when: String {
        InstallWhen.label(daysToStart: RelativeDay.days(from: .now, to: job.installStart), day: today, total: job.installDays,
                          start: job.installStart.thaiShort, end: job.installEnd.thaiShort)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 8) {
                titleRow
                codeRow.padding(.top, -4)
                whenRow
                status()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(today != nil ? Theme.primary : Theme.borderSubtle))
            .shadow(color: Theme.navy.opacity(0.08), radius: 4, y: 3)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(job.projectName).font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(job.team.rawValue).font(.sarabun(11.5, .bold, relativeTo: .caption)).foregroundStyle(job.team.color)
                .padding(.horizontal, 8).padding(.vertical, 1)
                .background(job.team.color.opacity(0.1), in: Capsule())
                .fixedSize()
        }
    }

    private var codeRow: some View {
        HStack(spacing: 6) {
            Text(job.code)
            Text(verbatim: "|")
            Image(systemName: "bolt").font(.system(size: 11, weight: .medium))
            Text(job.capacityKW.kw)
        }
        .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
        .lineLimit(1)
    }

    private var whenRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.primary)
            Text(when).font(.sarabun(14, .bold, relativeTo: .subheadline))
                .foregroundStyle(today != nil ? Theme.primary : Theme.navy).lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Image(systemName: "mappin").font(.system(size: 12, weight: .medium))
                Text(job.province).lineLimit(1)
            }
            .font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// The card's grey status box: a muted key, a bold value, optional trailing content and a chevron; at least 44 high.
struct CompactStatusBox<Trailing: View>: View {
    let key: String
    let value: String
    var valueColor: Color = Theme.navy
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(key).font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabun(13.5, .bold, relativeTo: .subheadline)).foregroundStyle(valueColor).lineLimit(1)
            Spacer(minLength: 6)
            trailing()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.primary)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.progressBoxIdle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension CompactStatusBox where Trailing == EmptyView {
    init(key: String, value: String, valueColor: Color = Theme.navy) {
        self.init(key: key, value: value, valueColor: valueColor) { EmptyView() }
    }
}
