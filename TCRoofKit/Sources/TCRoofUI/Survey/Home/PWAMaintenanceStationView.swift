#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// Station Detail page for handed-over maintenance stations (reference/PhonePwaStation.dc.html).
/// Shows hourly generation chart, KPIs, inverters, repair tickets, PM schedule & history, and equipment catalog.
public struct PWAMaintenanceStationView: View {
    public enum Tab: String, CaseIterable, Identifiable {
        case overview = "ภาพรวม"
        case repairs = "งานซ่อม"
        case pm = "PM"
        case equipment = "อุปกรณ์"

        public var id: String { rawValue }
    }

    public let station: MaintenanceStationSummary
    @State public var detail: MaintenanceStationDetail
    @State public var selectedTab: Tab
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    public init(station: MaintenanceStationSummary,
                initialTab: Tab = .overview,
                detail: MaintenanceStationDetail? = nil) {
        self.station = station
        self._selectedTab = State(initialValue: initialTab)
        self._detail = State(initialValue: detail ?? .mock(for: station))
    }

    private var statusColor: Color {
        switch station.status {
        case .normal: return Color(hex: 0x2E9E5B)
        case .alarm: return Color(hex: 0xD9453B)
        case .offline: return Color(hex: 0x9FB3CC)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            tabRow
            ScrollView {
                VStack(spacing: 10) {
                    switch selectedTab {
                    case .overview:
                        overviewView
                    case .repairs:
                        repairsView
                    case .pm:
                        pmView
                    case .equipment:
                        equipmentView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 104) // Space for floating bottom action bar
            }
        }
        .background(Color(hex: 0xF5F8FB).ignoresSafeArea())
        .overlay(alignment: .bottom) {
            bottomBar
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Tab Row
    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(tab.rawValue)
                        if tab == .repairs, detail.tickets.count > 0 {
                            Text(" \(detail.tickets.count)")
                                .foregroundStyle(Color(hex: 0xB45309))
                        }
                    }
                    .font(.sarabunFixed(14, selectedTab == tab ? .bold : .semibold))
                    .foregroundStyle(selectedTab == tab ? Theme.navy : Theme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 19, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: Theme.navy.opacity(0.16), radius: 3, y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stationDetail.tab.\(tab == .overview ? "overview" : tab == .repairs ? "repairs" : tab == .pm ? "pm" : "equipment")")
            }
        }
        .padding(3)
        .background(Color(hex: 0xE6ECF3), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Tab 1: Overview
    private var overviewView: some View {
        VStack(spacing: 10) {
            if detail.hasIssue {
                issueAlertBanner
            }
            dailyGenerationCard
            kpiGrid
            invertersCard
        }
    }

    @ViewBuilder
    private var issueAlertBanner: some View {
        if let issue = detail.issueTitle, let issueSub = detail.issueSubtitle {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xB42318))

                VStack(alignment: .leading, spacing: 1) {
                    Text(issue)
                        .font(.sarabunFixed(14, .bold))
                        .foregroundStyle(Color(hex: 0xB42318))
                    Text(issueSub)
                        .font(.sarabunFixed(12))
                        .foregroundStyle(Color(hex: 0xB42318).opacity(0.85))
                }

                Spacer(minLength: 4)

                Button("ดูงานซ่อม") {
                    withAnimation { selectedTab = .repairs }
                }
                .font(.sarabunFixed(13, .bold))
                .foregroundStyle(Color(hex: 0xB42318))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Color.white.opacity(0.85), in: Capsule())
                .accessibilityIdentifier("stationDetail.viewRepairs")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: 0xFDECEA), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var dailyGenerationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("วันนี้ผลิต")
                    .font(.sarabunFixed(13))
                    .foregroundStyle(Theme.inkMuted)
                Text(detail.energyTodayFormatted)
                    .font(.sarabunFixed(26, .bold))
                    .foregroundStyle(Theme.navy)
                Text("/ คาด \(detail.energyExpectedFormatted) kWh")
                    .font(.sarabunFixed(13))
                    .foregroundStyle(Theme.inkMuted)
                Spacer()
                Text("\(detail.generationPct)%")
                    .font(.sarabunFixed(16, .bold))
                    .foregroundStyle(statusColor)
            }

            hourlyBarChart

            HStack {
                Text("06")
                Spacer()
                Text("09")
                Spacer()
                Text("12")
                Spacer()
                Text("15")
                Spacer()
                Text("18")
            }
            .font(.sarabunFixed(11))
            .foregroundStyle(Color(hex: 0x9FB3CC))
            .padding(.top, -2)

            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text("ผลิตจริง")
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: 0xE6ECF3))
                        .frame(width: 10, height: 10)
                    Text("คาดการณ์")
                }
                Spacer()
                Text("อัปเดต \(detail.lastUpdated)")
            }
            .font(.sarabunFixed(11))
            .foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private var hourlyBarChart: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<13, id: \.self) { idx in
                let expected = idx < detail.expectedHourly.count ? detail.expectedHourly[idx] : 0
                let actual = idx < detail.actualHourly.count ? detail.actualHourly[idx] : 0
                let maxVal = max(detail.hourlyMax, 1)
                let expRatio = min(max(expected / maxVal, 0), 1)
                let actRatio = min(max(actual / maxVal, 0), 1)

                GeometryReader { geo in
                    let h = geo.size.height
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: 0xE6ECF3))
                            .frame(height: max(h * expRatio, 2))

                        if actual > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(statusColor)
                                .frame(height: max(h * actRatio, 2))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(height: 84)
        .padding(.top, 4)
    }

    private var kpiGrid: some View {
        HStack(spacing: 6) {
            kpiCard(title: "PR วันนี้",
                    value: "\(Int(detail.prToday))%",
                    sub: "เป้า \(Int(detail.prTarget))%",
                    valueColor: detail.prToday < detail.prTarget ? Color(hex: 0xB42318) : Theme.navy)
            kpiCard(title: "ผลิตเดือนนี้",
                    value: detail.energyThisMonth,
                    sub: detail.energyExpectedThisMonth,
                    valueColor: Theme.navy)
            kpiCard(title: "ลด CO₂",
                    value: detail.co2SavedThisMonth,
                    sub: "เดือนนี้",
                    valueColor: Theme.navy)
        }
    }

    private func kpiCard(title: String, value: String, sub: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabunFixed(16, .bold)).foregroundStyle(valueColor)
            Text(sub).font(.sarabunFixed(11)).foregroundStyle(Color(hex: 0x9FB3CC))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private var invertersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("อินเวอร์เตอร์")
                    .font(.sarabunFixed(14, .bold))
                    .foregroundStyle(Theme.navy)
                Spacer()
                Button {
                    withAnimation { selectedTab = .equipment }
                } label: {
                    Text("ทั้งหมด ›")
                        .font(.sarabunFixed(13, .bold))
                        .foregroundStyle(Theme.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stationDetail.allInverters")
            }
            .frame(height: 28)

            ForEach(Array(detail.inverters.enumerated()), id: \.element.id) { index, inv in
                if index > 0 {
                    Divider().overlay(Color(hex: 0xEEF1F5))
                }
                HStack(spacing: 10) {
                    Circle()
                        .fill(inv.isError ? Color(hex: 0xD9453B) : Color(hex: 0x2E9E5B))
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(inv.name).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                        Text(inv.model).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(inv.power).font(.sarabunFixed(14, .bold))
                            .foregroundStyle(inv.isError ? Color(hex: 0xB42318) : Theme.navy)
                        Text(inv.statusText).font(.sarabunFixed(11))
                            .foregroundStyle(inv.isError ? Color(hex: 0xB42318) : Theme.inkMuted)
                    }
                }
                .frame(minHeight: 46)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    // MARK: - Tab 2: Repairs
    private var repairsView: some View {
        VStack(spacing: 10) {
            ForEach(detail.tickets) { tk in
                ticketCard(tk)
            }
        }
    }

    private func ticketCard(_ tk: MaintenanceTicket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(tk.id)
                    .font(.sarabunFixed(12, .bold))
                    .foregroundStyle(Theme.inkMuted)

                Text(tk.status)
                    .font(.sarabunFixed(11, .bold))
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(tk.isClosed ? Color(hex: 0xE8F5EE) : Color(hex: 0xFFF3E6), in: Capsule())
                    .foregroundStyle(tk.isClosed ? Color(hex: 0x1F6B43) : Color(hex: 0x9A4A06))

                Spacer()

                Text(tk.dateText)
                    .font(.sarabunFixed(12))
                    .foregroundStyle(Theme.inkMuted)
            }

            Text(tk.title)
                .font(.sarabunFixed(15, .bold))
                .foregroundStyle(Theme.navy)

            Text(tk.subtitle)
                .font(.sarabunFixed(13))
                .foregroundStyle(Theme.inkMuted)

            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { step in
                    let isDone = step <= tk.currentStep
                    let label = ["แจ้ง", "รับงาน", "เข้าหน้างาน", "ปิดงาน"][step - 1]
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isDone ? Theme.primary : Color(hex: 0xE3E9F1))
                            .frame(height: 4)
                        Text(label)
                            .font(.sarabunFixed(11, isDone ? .bold : .regular))
                            .foregroundStyle(isDone ? Theme.navy : Color(hex: 0x9FB3CC))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        .accessibilityIdentifier("stationDetail.ticket.\(tk.id)")
    }

    // MARK: - Tab 3: PM
    private var pmView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let next = detail.nextPM {
                HStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Text(next.dayText)
                            .font(.sarabunFixed(20, .bold))
                        Text(next.monthText)
                            .font(.sarabunFixed(11))
                    }
                    .foregroundStyle(Theme.primary)
                    .frame(width: 56, height: 56)
                    .background(Color(hex: 0xE8F1FB), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(next.countdownText)
                            .font(.sarabunFixed(12))
                            .foregroundStyle(Theme.inkMuted)
                        Text(next.title)
                            .font(.sarabunFixed(15, .bold))
                            .foregroundStyle(Theme.navy)
                        Text(next.subtitle)
                            .font(.sarabunFixed(13))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
            }

            Text("ประวัติ")
                .font(.sarabunFixed(13, .bold))
                .foregroundStyle(Theme.navy)
                .padding(.top, 4)

            ForEach(detail.pmHistory) { item in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0x2E9E5B))
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.sarabunFixed(14, .bold))
                            .foregroundStyle(Theme.navy)
                        Text(item.detail)
                            .font(.sarabunFixed(12))
                            .foregroundStyle(Theme.inkMuted)
                    }

                    Spacer()

                    Text(item.dateText)
                        .font(.sarabunFixed(12))
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
            }
        }
    }

    // MARK: - Tab 4: Equipment
    private var equipmentView: some View {
        VStack(spacing: 10) {
            ForEach(detail.equipmentGroups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.title)
                        .font(.sarabunFixed(13, .bold))
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.vertical, 6)

                    ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                        Divider().overlay(Color(hex: 0xEEF1F5))
                        HStack {
                            Text(row.key)
                                .font(.sarabunFixed(14))
                                .foregroundStyle(Theme.navy)
                                .lineLimit(1)
                            Spacer()
                            Text(row.value)
                                .font(.sarabunFixed(14, .bold))
                                .foregroundStyle(Theme.navy)
                        }
                        .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
            }
        }
    }

    // MARK: - Bottom Floating Action Bar
    private var bottomBar: some View {
        HStack(spacing: 8) {
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
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(hex: 0xC9D3E0)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stationDetail.call")

            Button {
                withAnimation { selectedTab = .repairs }
            } label: {
                Text(detail.ctaText)
                    .font(.sarabunFixed(16, .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stationDetail.cta")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .background {
            LinearGradient(colors: [
                Color(hex: 0xF5F8FB).opacity(0),
                Color(hex: 0xF5F8FB).opacity(0.9),
                Color(hex: 0xF5F8FB)
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: 120)
            .allowsHitTesting(false)
        }
    }
}
#endif
