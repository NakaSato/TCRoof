import SwiftUI

/// Home header drawn like a drawing's title block: brand, user, date, time and buttons on top,
/// today's figures and the next appointment below. Narrow widths (iPhone, iPad mini portrait) stack it.
struct HomeHeader<Panel: View>: View {
    struct Stat: Identifiable {
        let label: String
        let value: Int
        let color: Color
        var id: String { label }
    }

    let userName: String
    let stats: [Stat]
    let next: String
    let unread: Int
    @Binding var showNotifications: Bool
    let openSettings: () -> Void
    @ViewBuilder let panel: Panel

    /// Starts at the device's likely layout so the first frame doesn't flip between the two.
    @State private var width: CGFloat = isPhone ? 390 : 1000
    private var wide: Bool { width >= 900 }
    private let brandWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            topRow
            hairline(Theme.borderControl, horizontal: true)
            bottomRow
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.borderControl))
        .cardShadow()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    // MARK: top row

    @ViewBuilder var topRow: some View {
        if wide {
            HStack(spacing: 0) {
                brand.frame(width: brandWidth, alignment: .leading)
                divider
                cell("ผู้ใช้งาน", userName.isEmpty ? "—" : userName, "วิศวกรสำรวจ").frame(maxWidth: .infinity, alignment: .leading)
                divider
                TimelineView(.everyMinute) { t in
                    HStack(spacing: 0) {
                        cell("วันที่", ThaiFormat.numericDate.string(from: t.date), ThaiFormat.weekday.string(from: t.date)).frame(width: 160, alignment: .leading)
                        divider
                        cell("เวลา", t.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)), "น.").frame(width: 110, alignment: .leading)
                    }
                }
                divider
                buttons.padding(.horizontal, 16)
            }
            .frame(height: 92)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack { brand; Spacer(); buttons }
                TimelineView(.everyMinute) { t in
                    Text([userName.isEmpty ? nil : userName, "วิศวกรสำรวจ",
                          ThaiFormat.weekday.string(from: t.date) + " " + ThaiFormat.numericDate.string(from: t.date),
                          t.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) + " น."]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Theme.inkMuted).monospacedDigit()
                }
            }
            .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 12)
        }
    }

    var brand: some View {
        HStack(spacing: 12) {
            Image("AppLogo").resizable().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("TCRoof").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.navy)
                Text("ระบบงานติดตั้งโซลาร์รูฟ").font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.horizontal, wide ? 24 : 0)
        .accessibilityElement(children: .combine)
    }

    func cell(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.system(size: 19, weight: .bold)).monospacedDigit().foregroundStyle(Theme.navy)
            Text(sub).font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
        }
        .lineLimit(1).minimumScaleFactor(0.8)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    var buttons: some View {
        HStack(spacing: 10) {
            Button { showNotifications.toggle() } label: {
                squareIcon("bell", active: showNotifications)
                    .overlay(alignment: .topTrailing) {
                        if unread > 0 {
                            Text("\(unread)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).monospacedDigit()
                                .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                                .background(Theme.danger, in: Capsule())
                                .offset(x: 8, y: -8)
                        }
                    }
            }
            .accessibilityLabel("การแจ้งเตือน")
            .accessibilityValue(unread > 0 ? "ยังไม่อ่าน \(unread)" : "")
            .popover(isPresented: $showNotifications, arrowEdge: .top) {
                panel.frame(width: isPhone ? nil : 440).presentationCompactAdaptation(.sheet)
            }
            Button(action: openSettings) { squareIcon("gearshape", active: false) }
                .accessibilityLabel("ตั้งค่า")
        }
    }

    func squareIcon(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol).font(.title3).foregroundStyle(active ? Theme.primary : Theme.navy)
            .frame(width: 44, height: 44)
            .background(active ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Theme.primary : Theme.borderControl, lineWidth: active ? 2 : 1))
    }

    // MARK: bottom row

    @ViewBuilder var bottomRow: some View {
        if wide {
            HStack(spacing: 0) {
                Text("สถานะวันนี้").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.paperInk)
                    .padding(.horizontal, 24).frame(width: brandWidth, alignment: .leading).frame(maxHeight: .infinity)
                    .background(Theme.paperBand)
                divider
                statCells
                divider
                VStack(alignment: .leading, spacing: 2) {
                    Text("งานถัดไป").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkMuted)
                    Text(next).font(.system(size: 15)).foregroundStyle(Theme.navy).lineLimit(1).monospacedDigit()
                }
                .padding(.horizontal, 20).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            .frame(height: 56)
        } else {
            VStack(spacing: 0) {
                statCells.fixedSize(horizontal: false, vertical: true)
                hairline(Theme.borderSubtle, horizontal: true)
                HStack(spacing: 6) {
                    Text("งานถัดไป").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkMuted)
                    Text(next).font(.system(size: 15)).foregroundStyle(Theme.navy).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
    }

    var statCells: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { i, s in
                if i > 0 { hairline(Theme.borderSubtle, horizontal: false) }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(s.value)").font(.system(size: 26, weight: .bold)).monospacedDigit().foregroundStyle(s.color)
                    Text(s.label).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, wide ? 20 : 12).padding(.vertical, 8)
                .frame(maxWidth: wide ? nil : .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(s.label) \(s.value)")
            }
        }
    }

    // MARK: lines

    var divider: some View { hairline(Theme.borderControl, horizontal: false) }

    func hairline(_ color: Color, horizontal: Bool) -> some View {
        Rectangle().fill(color).frame(width: horizontal ? nil : 1, height: horizontal ? 1 : nil)
    }
}
