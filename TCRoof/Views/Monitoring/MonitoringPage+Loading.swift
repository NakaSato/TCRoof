import SwiftUI
import TCRoofUI
import TCRoofCore

// The page while the first Growatt read since launch is under way (CHA-74, `MonitoringStore.awaitingFirstRead`):
// skeletons in the shape of each card, in the same `MonCard`s and sizes, so nothing reads `—` or 0 before the figures
// come. Later polls keep the last figures instead. DEBUG `-monitoringLoading YES` holds it on.

extension MonitoringPage {
    var loadingContent: some View {
        VStack(spacing: 14) {
            loadingStrip
            loadingKPIRow
            HStack(alignment: .top, spacing: 14) {
                loadingChartCard.frame(maxWidth: .infinity)
                loadingActionsCard.frame(width: 398)
            }
            loadingStationsCard
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("กำลังโหลดข้อมูลจาก Growatt")
        .accessibilityIdentifier("monitoring.loading")
    }

    // MARK: since installed

    private var loadingStrip: some View {
        MonCard(padding: 0) {
            HStack(spacing: 0) {
                Text("ตั้งแต่ติดตั้ง").font(.sarabun(13, .bold)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 16)
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 8) {
                        TCSkeletonBlock(width: 80, height: 11)
                        TCSkeletonBlock(width: 64, height: 18, radius: 5)
                    }
                    .tcShimmer()
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1, height: 26) }
                }
            }
            .frame(height: 52)
        }
    }

    // MARK: the six cards

    private var loadingKPIRow: some View {
        HStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in loadingKPI }
        }
    }

    /// `MonitoringKPI`'s shape: icon, title and spark; the figure; the chip and its caption.
    private var loadingKPI: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TCSkeletonBlock(width: 26, height: 26, radius: 7)
                TCSkeletonBlock(width: 70, height: 13)
                Spacer(minLength: 2)
                TCSkeletonBlock(width: 44, height: 22, radius: 4)
            }
            TCSkeletonBlock(width: 96, height: 28, radius: 6).padding(.vertical, 4)
            HStack(spacing: 6) {
                TCSkeletonBlock(width: 44, height: 22, radius: 6)
                TCSkeletonBlock(width: 60, height: 11)
            }
        }
        .tcShimmer()
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    // MARK: chart

    /// The chart card's title and switches (off until the figures come), the plot and the summary column in outline.
    private var loadingChartCard: some View {
        MonCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("กำลังผลิตรวม (\(range == .today ? "kW" : "kWh")) " + Self.rangeTitle(range))
                        .font(.sarabun(17, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    Spacer(minLength: 8)
                    MonSwitch(options: Monitoring.ChartRange.allCases.map { ($0, Self.rangeLabel($0)) }, selection: $range, disabled: true)
                    MonSwitch(options: [(false, "รวม"), (true, "แยกสถานี")], selection: $split, disabled: true)
                }
                TCSkeletonBlock(width: 220, height: 12).tcShimmer().frame(height: 18)
                HStack(alignment: .top, spacing: 14) {
                    TCSkeletonBlock(height: 190, radius: 10)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(0..<4, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                TCSkeletonBlock(width: 90, height: 10)
                                TCSkeletonBlock(width: 120, height: 16, radius: 5)
                            }
                        }
                    }
                    .frame(width: 150, alignment: .leading)
                }
                .tcShimmer()
            }
        }
    }

    // MARK: ต้องดำเนินการ

    private var loadingActionsCard: some View {
        MonCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("ต้องดำเนินการ").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                    Spacer()
                    Text("เรียงตามพลังงานที่เสีย").font(.sarabun(12)).foregroundStyle(Theme.inkMuted)
                }
                .padding(16)
                ForEach(0..<4, id: \.self) { _ in
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        TCSkeletonBlock(width: 220, height: 13)
                        TCSkeletonBlock(width: 150, height: 10)
                    }
                    .tcShimmer()
                    .padding(.horizontal, 16).frame(minHeight: 58)
                }
            }
        }
    }

    // MARK: stations

    /// The stations card's title, the table's header and five rows in outline, a block per column.
    private var loadingStationsCard: some View {
        MonCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("สถานี").font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
                    TCSkeletonBlock(width: 280, height: 30, radius: 10).tcShimmer()
                    Spacer(minLength: 8)
                }
                .frame(minHeight: 48)
                .padding(16)
                tableHeader
                ForEach(0..<5, id: \.self) { _ in
                    Divider()
                    loadingTableRow
                }
            }
        }
    }

    private var loadingTableRow: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                TCSkeletonBlock(width: 160, height: 13)
                TCSkeletonBlock(width: 100, height: 10)
            }
            .frame(width: Col.station, alignment: .leading)
            TCSkeletonBlock(width: 56, height: 22, radius: 6).frame(width: Col.status, alignment: .leading)
            loadingBarCell.frame(width: Col.power, alignment: .leading).padding(.trailing, 14)
            loadingBarCell.frame(width: Col.energy, alignment: .leading).padding(.trailing, 12)
            TCSkeletonBlock(width: 50, height: 13).frame(width: Col.yield, alignment: .trailing).padding(.trailing, 12)
            TCSkeletonBlock(width: 56, height: 13).frame(width: Col.loss, alignment: .trailing).padding(.trailing, 12)
            TCSkeletonBlock(width: 68, height: 14, radius: 3).frame(width: Col.inverters, alignment: .leading)
            TCSkeletonBlock(width: 50, height: 11).frame(width: Col.data, alignment: .leading)
            TCSkeletonBlock(width: 24, height: 24, radius: 12).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .tcShimmer()
        .padding(.horizontal, 16).frame(minHeight: 48)
    }

    /// A figure over its thin bar, as the power and energy cells.
    private var loadingBarCell: some View {
        VStack(alignment: .leading, spacing: 5) {
            TCSkeletonBlock(width: 70, height: 13)
            TCSkeletonBlock(height: 5, radius: 2.5)
        }
    }
}
