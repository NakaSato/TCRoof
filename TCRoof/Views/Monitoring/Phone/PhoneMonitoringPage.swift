import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// `Monitoring ทุกสถานี` on iPhone (CHA-34, docs/ui/iphone-monitor-entry §5): the iPhone dock's `Monitor` tab. The same
/// `MonitoringStore.shared.fleet` as the iPad's `MonitoringPage`, in one column: the header, the failure strip, the
/// summary card, `ต้องดำเนินการ` (the costliest five) and the stations. Read only; no chart and no ตั้งค่า Monitoring
/// (managers use the iPad). A station opens `PWAMaintenanceStationView`. `PhoneTabs`' `MonitoringPoller` reads Growatt while this tab is shown.
struct PhoneMonitoringPage: View {
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State var store = MonitoringStore.shared
    /// The filter picked; nil until one is, when `มีปัญหา` shows, or `ทั้งหมด` when nothing has a problem.
    @State var picked: Monitoring.Filter?
    @State var sort: Monitoring.Sort = .loss
    @State var opened: Monitoring.Station?
    @State var allActions = false

    /// Lines of `ต้องดำเนินการ` before `ดูทั้งหมด`.
    static let actionsShown = 5

    var body: some View {
        let fleet = store.fleet
        ScrollView {
            VStack(spacing: 10) {
                if store.awaitingFirstRead {
                    loadingContent
                } else if fleet.rows.isEmpty {
                    emptyCard
                } else {
                    content(fleet)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { header(fleet) }
        .background(Theme.phonePage.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: jobs.map(\.persistentModelID)) { store.refresh(jobs: jobs) }
        .navigationDestination(item: $opened) { s in Self.station(s, fleet: fleet, store: store) }
        .navigationDestination(isPresented: $allActions) { PhoneMonitoringActionsPage() }
    }

    @ViewBuilder private func content(_ f: Monitoring.Fleet) -> some View {
        if let failure = store.feedFailure { failureStrip(failure) }
        summaryCard(f)
        if !f.rows.contains(where: \.station.paired), !MonitoringStore.demo { notPairedCard }
        actionsCard(f)
        stationsCard(f)
    }

    /// The station's maintenance page, until a compact `Monitoring สถานี` is designed (§6).
    static func station(_ s: Monitoring.Station, fleet: Monitoring.Fleet, store: MonitoringStore) -> some View {
        let health = fleet.rows.first { $0.id == s.id }?.health ?? s.health(now: fleet.now, offlineAfter: store.settings.loggerOfflineMinutes)
        return PWAMaintenanceStationView(station: MonitoringPage.summary(s, health: health))
    }

    // MARK: header

    private func header(_ f: Monitoring.Fleet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Monitoring ทุกสถานี").font(.sarabun(22, .bold)).foregroundStyle(Theme.onPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(headerLine(f)).font(.sarabun(13)).foregroundStyle(Theme.onPrimary.opacity(0.85)).lineLimit(1)
                .accessibilityIdentifier("monitoring.phone.updated")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous)
                .fill(Theme.headerGradient).ignoresSafeArea(edges: .top)
        }
    }

    /// `อัปเดต 14:55 · จับคู่แล้ว 6/8 สถานี`, or the source's note in place of the counts.
    private func headerLine(_ f: Monitoring.Fleet) -> String {
        let read = f.stations.compactMap(\.lastReading).max() ?? store.refreshedAt
        let second = store.sourceNote ?? "จับคู่แล้ว \(f.stations.filter(\.paired).count)/\(f.stations.count) สถานี"
        return "อัปเดต " + MonFormat.time(read) + " · " + second
    }

    // MARK: notes

    private func failureStrip(_ failure: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 16)).foregroundStyle(Theme.warningInk)
            VStack(alignment: .leading, spacing: 2) {
                Text(failure).font(.sarabun(14, .semibold)).foregroundStyle(Theme.warningInk).lineLimit(2)
                Text("แสดงข้อมูลล่าสุดที่อ่านได้").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("monitoring.feedFailure")
    }

    private var notPairedCard: some View {
        MonCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("ยังไม่ได้จับคู่สถานีกับ Plant ใน Growatt").font(.sarabun(15, .bold)).foregroundStyle(Theme.navy)
                Text("ผู้จัดการจับคู่ได้ที่ ตั้งค่า Monitoring บน iPad").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyCard: some View {
        MonCard {
            VStack(spacing: 6) {
                Image(systemName: "sun.max").font(.system(size: 28)).foregroundStyle(Theme.inkMuted)
                Text("ยังไม่มีสถานีที่ส่งมอบ").font(.sarabun(16, .bold)).foregroundStyle(Theme.navy)
                Text("สถานีจะขึ้นที่นี่เมื่อส่งมอบงานแล้ว").font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("monitoring.phone.empty")
    }

    // MARK: loading

    /// The first read since launch (CHA-74): skeletons in the page's shape, never a spinner.
    private var loadingContent: some View {
        VStack(spacing: 10) {
            TCSkeletonCard(lines: 3, block: 64)
            skeletonList(rows: 3)
            skeletonList(rows: 4)
        }
        .tcShimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("กำลังโหลดข้อมูล Monitoring")
    }

    private func skeletonList(rows: Int) -> some View {
        MonCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TCSkeletonBlock(width: 120, height: 16).padding(16)
                ForEach(0..<rows, id: \.self) { _ in
                    Divider()
                    TCSkeletonRow(avatar: false).padding(.horizontal, 16)
                }
            }
        }
    }
}
