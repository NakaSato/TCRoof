#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// Station page for a handed-over maintenance station (reference/PhonePwaStation.dc.html): its overview only, with no
/// tabs: the issue banner, today's hourly generation, the KPIs and the inverters. Repairs, PM and the equipment list
/// are not on this page.
public struct PWAMaintenanceStationView: View {
    public let station: MaintenanceStationSummary
    @State public var detail: MaintenanceStationDetail
    /// A Growatt example plant's figures are still being fetched: the overview shows skeletons.
    @State private var loadingDetail: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    public init(station: MaintenanceStationSummary, detail: MaintenanceStationDetail? = nil) {
        self.station = station
        // a Growatt example plant shows its row until its own figures load (`GrowattDemoFeed.detail`)
        self._detail = State(initialValue: detail ?? (GrowattDemoFeed.isGrowatt(station) ? .growatt(summary: station) : .mock(for: station)))
        self._loadingDetail = State(initialValue: detail == nil && GrowattDemoFeed.enabled && GrowattDemoFeed.isGrowatt(station))
    }


    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                overviewView
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    // room for the floating call button when there is one
                    .padding(.bottom, detail.contractorPhone.isEmpty ? 24 : 104)
            }
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if !detail.contractorPhone.isEmpty { bottomBar }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard loadingDetail else { return }
            if let d = await GrowattDemoFeed.detail(for: station) { detail = d }
            // a cancelled fetch (the page left) keeps the skeleton for the next appearance
            if !Task.isCancelled { loadingDetail = false }
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text("บำรุงรักษา")
                            .font(.sarabunFixed(15, .semibold))
                    }
                    .foregroundStyle(Theme.onPrimary)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("กลับไปบำรุงรักษา")
                .accessibilityIdentifier("stationDetail.back")

                Spacer()

                Menu {
                    Button("แชร์ข้อมูลสถานี") {}
                    Button("รีเฟรชข้อมูล") {}
                } label: {
                    Text("…")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(width: 44, height: 44)
                        .background(Theme.onPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("เพิ่มเติม")
                .accessibilityIdentifier("stationDetail.more")
            }
            .frame(height: 44)

            Text(station.name)
                .font(.sarabunFixed(22, .bold))
                .foregroundStyle(Theme.onPrimary)
                .lineLimit(1)
                .accessibilityIdentifier("stationDetail.title")

            Text("\(station.kWp.formatted(.number.precision(.fractionLength(0...1)))) kWp | ส่งมอบ \(detail.handoverDate) | \(detail.contractor)")
                .font(.sarabunFixed(13))
                .foregroundStyle(Theme.onPrimary.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background {
            Theme.headerGradient
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15, style: .continuous))
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Overview ("Live dashboard")

    /// The issue banner, the live card (power now, a gauge of the plant's size in use, today's curve against
    /// expected), the 2 × 2 figures (today, month, total, PR) and the inverters with their own power bars.
    private var overviewView: some View {
        VStack(spacing: 10) {
            if loadingDetail {
                overviewSkeleton
            } else {
                if detail.hasIssue { issueAlertBanner }
                liveCard
                statsGrid
                invertersCard
            }
        }
    }

    /// The overview's cards in outline while the plant's figures load.
    private var overviewSkeleton: some View {
        VStack(spacing: 10) {
            TCSkeletonCard(lines: 1, block: 110)
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        TCSkeletonBlock(width: 52)
                        TCSkeletonBlock(width: 96, height: 20, radius: 5)
                        TCSkeletonBlock(width: 70)
                    }
                    .tcShimmer()
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
                }
            }
            .tcLoadingLabel()
            TCSkeletonCard(lines: 3)
        }
    }

    private var tint: Color {
        switch station.status {
        case .normal: Theme.success
        case .alarm: Theme.danger
        case .offline: Theme.chevron
        }
    }

    @ViewBuilder
    private var issueAlertBanner: some View {
        if let issue = detail.issueTitle, let issueSub = detail.issueSubtitle {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(issue).font(.sarabunFixed(14, .bold))
                    Text(issueSub).font(.sarabunFixed(12)).opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.dangerText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: live card

    /// Power now: the feed's, else the last hour with a reading; nil when there is none (offline).
    private var livePower: Double? {
        guard station.status != .offline else { return nil }
        return detail.summary.powerNow ?? detail.actualHourly.last(where: { $0 > 0 })
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            liveHead
            TCDayCurve(actual: detail.actualHourly, expected: detail.expectedHourly, tint: tint)
                .frame(height: 104)
            HStack {
                ForEach(["06", "09", "12", "15", "18"], id: \.self) { h in
                    Text(h)
                    if h != "18" { Spacer() }
                }
            }
            .font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            curveLegend
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private var liveHead: some View {
        let kWp = max(detail.summary.kWp, station.kWp)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let p = livePower {
                        Text(p.formatted(.number.precision(.fractionLength(1)))).font(.sarabunFixed(32, .bold))
                            + Text(" kW").font(.sarabunFixed(16, .bold))
                    } else {
                        Text("—").font(.sarabunFixed(32, .bold))
                    }
                }
                .foregroundStyle(Theme.navy).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(station.status == .offline ? "ออฟไลน์ ไม่มีข้อมูลการผลิต" : "กำลังผลิตตอนนี้")
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                Text("อัปเดต \(detail.lastUpdated)").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).monospacedDigit()
            }
            Spacer(minLength: 8)
            if let p = livePower, kWp > 0 {
                VStack(spacing: 4) {
                    TCPlanRing(actual: p / kWp, tint: tint)
                    Text("ของกำลังติดตั้ง").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(livePower.map { p in
            "กำลังผลิตตอนนี้ \(p.formatted(.number.precision(.fractionLength(1)))) กิโลวัตต์" + (kWp > 0 ? " \(Int((p / kWp * 100).rounded()))% ของกำลังติดตั้ง" : "")
        } ?? "ออฟไลน์ ไม่มีข้อมูลการผลิต")
    }

    private var curveLegend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 14, height: 4)
                Text("ผลิตจริง")
            }
            if detail.expectedHourly.contains(where: { $0 > 0 }) {
                HStack(spacing: 5) {
                    Path { p in p.move(to: CGPoint(x: 0, y: 2)); p.addLine(to: CGPoint(x: 14, y: 2)) }
                        .stroke(Theme.inkFaint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(width: 14, height: 4)
                    Text("คาดการณ์")
                }
            }
            Spacer()
        }
        .font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
        .accessibilityHidden(true)
    }

    // MARK: figures

    private var gridColumns: [GridItem] { [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)] }

    private var statsGrid: some View {
        let s = detail.summary
        let pct = s.expected > 0 ? "\(Int((s.yield * 100).rounded()))% ของที่คาด" : "ไม่มีค่าคาดการณ์"
        return LazyVGrid(columns: gridColumns, spacing: 8) {
            statTile("วันนี้", value: "\(detail.energyTodayFormatted) kWh", sub: pct,
                     subTint: s.expected > 0 && s.yield < 0.8 ? Theme.warning : Theme.inkMuted)
            statTile("เดือนนี้", value: detail.energyThisMonth, sub: "ลด CO₂ \(detail.co2SavedThisMonth)")
            statTile("ทั้งหมด", value: detail.energyTotal.isEmpty ? "—" : detail.energyTotal,
                     sub: detail.handoverDate == "—" ? "ตั้งแต่เริ่มระบบ" : "ตั้งแต่ \(detail.handoverDate)")
            statTile("PR วันนี้", value: detail.prToday > 0 ? "\(Int(detail.prToday))%" : "—",
                     sub: "เป้า \(Int(detail.prTarget))%",
                     valueTint: detail.prToday > 0 && detail.prToday < detail.prTarget ? Theme.dangerText : Theme.navy)
        }
    }

    private func statTile(_ title: String, value: String, sub: String, valueTint: Color = Theme.navy,
                          subTint: Color = Theme.inkMuted) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabunFixed(20, .bold)).foregroundStyle(valueTint).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.sarabunFixed(11)).foregroundStyle(subTint).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
        .accessibilityElement(children: .combine)
    }

    // MARK: inverters

    private var invertersCard: some View {
        let online = detail.inverters.filter { !$0.isError }.count
        return VStack(alignment: .leading, spacing: 0) {
            Text("อินเวอร์เตอร์ \(online)/\(detail.inverters.count) ออนไลน์")
                .font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                .frame(height: 30)
            ForEach(Array(detail.inverters.enumerated()), id: \.element.id) { index, inv in
                if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                inverterRow(inv)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func inverterRow(_ inv: InverterItem) -> some View {
        let ink = inv.isError ? Theme.dangerText : Theme.navy
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(inv.isError ? Theme.danger : Theme.success).frame(width: 9, height: 9)
                Text(inv.name).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                Text(inv.model).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Spacer(minLength: 6)
                Text(inv.power).font(.sarabunFixed(14, .bold)).foregroundStyle(ink).monospacedDigit()
            }
            HStack(spacing: 8) {
                if let share = inv.share {
                    // the inverter's own state, not the station's: a healthy inverter is green beside a faulty one
                    TCPlanBar(actual: share, tint: inv.isError ? Theme.danger : Theme.success).padding(.vertical, -3)
                    Text("\(Int((share * 100).rounded()))%").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
                        .monospacedDigit().frame(width: 34, alignment: .trailing)
                } else {
                    Spacer()
                }
                Text(inv.statusText).font(.sarabunFixed(11, .bold)).foregroundStyle(inv.isError ? Theme.dangerText : Theme.inkMuted)
            }
            .padding(.leading, 17)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Bottom Floating Action Bar
    /// The contractor's call button, only when there is a number (`body` leaves the bar out otherwise). The repair
    /// button went with the repairs tab.
    private var bottomBar: some View {
        HStack(spacing: 8) {
            callButton
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .background {
            LinearGradient(colors: [
                Theme.phonePage.opacity(0),
                Theme.phonePage.opacity(0.9),
                Theme.phonePage
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: 120)
            .allowsHitTesting(false)
        }
    }

    private var callButton: some View {
        Button {
            if let url = URL(string: "tel://\(detail.contractorPhone)") {
                openURL(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 15))
                Text(detail.contractorShort)
                    .font(.sarabunFixed(15, .bold))
            }
            .foregroundStyle(Theme.navy)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderOutdoor))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stationDetail.call")
    }
}
#endif
