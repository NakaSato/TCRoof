import SwiftUI
import TCRoofUI
import TCRoofCore
import SurveyUI

/// Sizes of the pieces the iPhone and iPad homes share (docs/ui/tcroof-home-iphone-v2, docs/ui/tcroof-home-ipad).
/// The iPhone follows the v2 outdoor-contrast board; every v2 change is phone only, so the iPad looks as before.
struct HomeSize {
    // header
    var logo: CGFloat
    var logoRadius: CGFloat
    var headerRadius: CGFloat
    var isPad: Bool
    var roundButton: CGFloat
    var bellGlyph: CGFloat
    // hero
    var heroRadius: CGFloat
    var heroPadding: EdgeInsets
    var heroGap: CGFloat
    var heroLabel: CGFloat
    var ring: CGFloat
    var ringStroke: CGFloat
    var ringText: CGFloat
    var time: CGFloat
    var kind: CGFloat
    var name: CGFloat
    var place: CGFloat
    var action: CGFloat
    var actionRadius: CGFloat
    var actionText: CGFloat
    // module row
    var rowRadius: CGFloat
    var rowGap: CGFloat
    var rowPadding: (leading: CGFloat, trailing: CGFloat)
    var tile: CGFloat
    var tileRadius: CGFloat
    var tileGlyph: CGFloat
    var title: CGFloat
    var subtitle: CGFloat
    var chip: CGFloat
    var chevron: CGFloat

    static let phone = HomeSize(
        logo: 44, logoRadius: 12, headerRadius: 2, isPad: false, roundButton: 44, bellGlyph: 20,
        heroRadius: 20, heroPadding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), heroGap: 11, heroLabel: 12.5,
        ring: 56, ringStroke: 5, ringText: 13, time: 24, kind: 12.5, name: 15, place: 12.5, action: 46, actionRadius: 12, actionText: 15,
        rowRadius: 16, rowGap: 12, rowPadding: (12, 10), tile: 42, tileRadius: 12, tileGlyph: 19, title: 15, subtitle: 12, chip: 11, chevron: 14)

    static let pad = HomeSize(
        logo: 56, logoRadius: 14, headerRadius: 22, isPad: true, roundButton: 52, bellGlyph: 22,
        heroRadius: 22, heroPadding: EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20), heroGap: 16, heroLabel: 14,
        ring: 88, ringStroke: 8, ringText: 20, time: 38, kind: 14, name: 19, place: 14, action: 56, actionRadius: 14, actionText: 17,
        rowRadius: 18, rowGap: 16, rowPadding: (18, 18), tile: 56, tileRadius: 15, tileGlyph: 26, title: 19, subtitle: 14, chip: 13, chevron: 18)
}

/// How the home's notifications and settings look: v2 outdoor contrast on iPhone,
/// v1 everywhere else (the iPad popover and form sheet).
struct HomeInk {
    /// Details, times, group titles, settings labels.
    var muted: Color
    var chevron: Color
    /// 1 pt card and chip borders.
    var border: Color

    static let standard = HomeInk(muted: Theme.inkMuted, chevron: Theme.chevron, border: Theme.borderSubtle)
    static let outdoor = HomeInk(muted: Theme.inkStrong, chevron: Theme.muted, border: Theme.borderOutdoor)
}

extension EnvironmentValues {
    @Entry var homeInk: HomeInk = .standard
}

/// "WC" from "wit.chanthawat", or the first letters of the first two words of the name.
func userInitials(_ name: String, email: String?) -> String {
    let source = name.trimmingCharacters(in: .whitespaces).isEmpty ? (email?.split(separator: "@").first.map(String.init) ?? "") : name
    let words = source.split(whereSeparator: { " ._-".contains($0) })
    let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    return letters.isEmpty ? "?" : letters
}

// MARK: - Header

/// iPad (docs/ui/home-navbar-ipad): brand, search field, and the bell + account capsule.
/// iPhone (docs/ui/tcroof-home-iphone-v2): the logo and the bell; settings are the tab bar's `ตั้งค่า`.
/// The caller shows the notifications: under the bell on iPad (`BellAnchorKey`), full screen on iPhone.
struct HomeBrandHeader: View {
    let size: HomeSize
    let initials: String
    let unread: Int
    @Binding var notificationsShown: Bool
    let openSettings: () -> Void
    /// iPad: the search field opens the job search.
    var openSearch: () -> Void = {}

    /// iPad bar width; under ~900 pt the `INTERNAL` line goes before the search placeholder truncates.
    @State private var width: CGFloat = 1366

    var body: some View {
        if size.isPad { padRow } else { phoneRow }
    }

    private var padRow: some View {
        HStack(spacing: 16) {
            Image("AppLogo").resizable().frame(width: size.logo, height: size.logo)
                .clipShape(RoundedRectangle(cornerRadius: size.logoRadius, style: .continuous))
                .accessibilityHidden(true)
            brand
            // the spacer and the search share the free width evenly, the search capped at 600 (the board's flex: 1 pair)
            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            searchField.frame(maxWidth: .infinity, alignment: .trailing)
            HStack(spacing: 0) {
                bell
                Button {
                    notificationsShown = false
                    openSettings()
                } label: {
                    Text(initials).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 42, height: 42).background(Theme.navy, in: Circle())
                        .frame(width: size.roundButton, height: size.roundButton).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ตั้งค่าและบัญชี")
            }
            .padding(.horizontal, 2)
            .frame(height: 56)
            .background(Theme.phonePage, in: Capsule())
        }
        .padding(.horizontal, 32)
        .padding(.top, 18).padding(.bottom, 16)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background {
            let shape = UnevenRoundedRectangle(bottomLeadingRadius: size.headerRadius, bottomTrailingRadius: size.headerRadius, style: .continuous)
            shape.fill(Theme.surface)
                .overlay { shape.stroke(Theme.headerLine) }
                .shadow(color: Theme.navy.opacity(0.05), radius: 4, y: 2)
                .ignoresSafeArea(edges: .top)
        }
    }

    /// `TC Roof` in the rounded face, a teal dash and `INTERNAL` under it.
    private var brand: some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text(verbatim: "TC").font(.system(size: 27, weight: .heavy, design: .rounded)).foregroundStyle(Theme.navy)
             + Text(verbatim: " Roof").font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(Theme.primary))
                .tracking(-0.6)
                .frame(height: 28)
            if width >= 900 {
                HStack(spacing: 6) {
                    Capsule().fill(Theme.teal).frame(width: 14, height: 2)
                    Text(verbatim: "INTERNAL").font(.system(size: 10.5, weight: .bold, design: .rounded)).tracking(2.4)
                        .foregroundStyle(Theme.muted)
                }
                .frame(height: 13)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "TC Roof Internal"))
    }

    /// Looks like a field; tapping opens the job search.
    private var searchField: some View {
        Button(action: openSearch) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 22, height: 22)
                Text("ค้นหาเลขที่ ชื่อโครงการ สถานี…").font(.system(size: 16)).foregroundStyle(Theme.muted)
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 600, minHeight: 52, maxHeight: 52, alignment: .leading)
            .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.headerLine))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isSearchField)
    }

    /// v2: no text, just the logo and the bell in a capsule; nearly square, borderless bar.
    private var phoneRow: some View {
        HStack(spacing: 10) {
            Image("AppLogo").resizable().frame(width: size.logo, height: size.logo)
                .clipShape(RoundedRectangle(cornerRadius: size.logoRadius, style: .continuous))
                .accessibilityLabel(Text(verbatim: "TC Renewable"))
            Spacer(minLength: 0)
            bell
                .padding(.horizontal, 2)
                .frame(height: 48)
                .background(Theme.phonePage, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 2).padding(.bottom, 12)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: size.headerRadius, bottomTrailingRadius: size.headerRadius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.navy.opacity(0.06), radius: 5, y: 2)
                .ignoresSafeArea(edges: .top)
        }
    }

    /// A 52 / 44 pt target in the capsule, light blue with a blue ring while the notifications are open.
    private var bell: some View {
        let active = notificationsShown
        return Button { notificationsShown.toggle() } label: {
            Group {
                if size.isPad {
                    Image(systemName: "bell").font(.system(size: size.bellGlyph, weight: .medium)).foregroundStyle(Theme.navy)
                        .frame(width: size.roundButton, height: size.roundButton)
                        .background { if active { Circle().fill(Theme.primarySoft) } }
                        .overlay { if active { Circle().strokeBorder(Theme.primary, lineWidth: 2) } }
                        .contentShape(Circle())
                } else {
                    Image(systemName: "bell").font(.system(size: size.bellGlyph, weight: .semibold)).foregroundStyle(Theme.navy)
                        .frame(width: size.roundButton, height: size.roundButton)
                        .background { if active { Circle().fill(Theme.primarySoft) } }
                        .overlay { if active { Circle().strokeBorder(Theme.primary, lineWidth: 2) } }
                        .contentShape(Circle())
                }
            }
            .overlay(alignment: .topTrailing) {
                if unread > 0 {
                    Text("\(unread)").font(.sarabun(12, .bold)).monospacedDigit().foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                        .background(Theme.danger, in: Capsule())
                        .overlay(Capsule().stroke(.white, lineWidth: 2))
                        .padding(.top, size.isPad ? 4 : 0).padding(.trailing, size.isPad ? 2 : 0)
                        .offset(y: size.isPad ? 0 : 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(size.isPad && unread > 0 ? "การแจ้งเตือน · ใหม่ \(unread)" : "การแจ้งเตือน")
        .accessibilityValue(size.isPad || unread == 0 ? "" : "ยังไม่อ่าน \(unread)")
        .anchorPreference(key: BellAnchorKey.self, value: .bounds) { size.isPad ? $0 : nil }
    }

}

/// Where the iPad bell is, so the home can hang the notifications panel under it.
struct BellAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

// MARK: - Module row

struct ModuleRow: View {
    let size: HomeSize
    let module: AppModule
    let chip: String?

    var body: some View {
        HStack(spacing: size.rowGap) {
            Image(systemName: module.symbol).font(.system(size: size.tileGlyph, weight: .semibold)).foregroundStyle(Theme.onPrimary)
                .frame(width: size.tile, height: size.tile)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: size.tileRadius, style: .continuous))
            VStack(alignment: .leading, spacing: size.isPad ? 2 : 1) {
                let oneLine = module.title.replacingOccurrences(of: "\n", with: "")
                Group {
                    if size.isPad {
                        Text(oneLine).lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        // one line when it fits, else broken where the title has its line break
                        ViewThatFits(in: .horizontal) {
                            Text(oneLine).lineLimit(1).fixedSize()
                            Text(module.title).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.sarabun(size.title, .bold, relativeTo: size.isPad ? .title3 : .subheadline)).foregroundStyle(Theme.navy)
                Text(module.shortSubtitle).font(.sarabun(size.subtitle, relativeTo: .caption)).foregroundStyle(size.isPad ? Theme.inkMuted : Theme.inkStrong)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let chip {
                Text(chip).font(.sarabun(size.chip, .bold, relativeTo: .caption2)).foregroundStyle(Theme.primary).lineLimit(1)
                    .padding(.horizontal, size.isPad ? 12 : 8).padding(.vertical, size.isPad ? 3 : 1)
                    .background(Theme.primarySoft, in: Capsule())
                    .fixedSize()
            }
            Image(systemName: "chevron.right").font(.system(size: size.chevron, weight: .semibold)).foregroundStyle(size.isPad ? Theme.chevron : Theme.muted)
        }
        .padding(.leading, size.rowPadding.leading).padding(.trailing, size.rowPadding.trailing).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: size.isPad ? 72 : 60, maxHeight: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: size.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size.rowRadius, style: .continuous).stroke(size.isPad ? Theme.borderSubtle : Theme.borderOutdoor))
        .shadow(color: Theme.navy.opacity(0.05), radius: 3, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: size.rowRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hero

/// `นัดวันนี้`: today's survey appointments as a pager, with ring, primary action, navigate and call.
struct AppointmentHero: View {
    let size: HomeSize
    let appointments: [TodayAppointment]
    @Binding var page: Int
    let open: (TodayAppointment, MissingGroup.Target?) -> Void
    let newSurvey: () -> Void

    @State private var calling: TodayAppointment?
    @Environment(\.openURL) private var openURL

    private var current: TodayAppointment? { appointments.indices.contains(page) ? appointments[page] : appointments.first }

    var body: some View {
        VStack(alignment: .leading, spacing: size.heroGap) {
            topRow
            if let a = current {
                AppointmentBody(size: size, appointment: a)
                    .id(a.id)
                    .transition(.opacity)
                actions(a)
            } else {
                Text("ไม่มีนัดวันนี้").font(.sarabun(size.isPad ? 21 : 17, .bold, relativeTo: .headline))
                Button(action: newSurvey) { primaryLabel("งานสำรวจใหม่ ›") }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(size.heroPadding)
        .background { heroFill }
        .shadow(color: size.isPad ? Theme.navy.opacity(0.25) : Theme.heroSolid.opacity(0.28), radius: size.isPad ? 11 : 9, y: size.isPad ? 10 : 8)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) else { return }
            go(v.translation.width < 0 ? 1 : -1)
        })
        .onChange(of: appointments.count) { page = min(page, max(appointments.count - 1, 0)) }
        .callDialog($calling, open: open)
    }

    /// iPad: the blue gradient. iPhone v2: solid navy, readable in sun.
    @ViewBuilder private var heroFill: some View {
        let shape = RoundedRectangle(cornerRadius: size.heroRadius, style: .continuous)
        if size.isPad { shape.fill(Theme.heroGradient) } else { shape.fill(Theme.heroSolid) }
    }

    /// Secondary text on the card: 85 % on iPad, 95 % on iPhone v2.
    private var labelOpacity: Double { size.isPad ? 0.85 : 0.95 }

    private var topRow: some View {
        HStack(spacing: size.isPad ? 8 : 6) {
            Text("นัดวันนี้").font(.sarabun(size.heroLabel, .bold, relativeTo: .caption)).opacity(labelOpacity)
            if appointments.count > 1 {
                HStack(spacing: 4) {
                    ForEach(appointments.indices, id: \.self) { i in
                        Capsule().fill(.white.opacity(i == page ? 1 : 0.4)).frame(width: i == page ? 16 : 6, height: 6)
                    }
                }
                .padding(.leading, size.isPad ? 4 : 2)
                .accessibilityHidden(true)
            }
            Spacer(minLength: 4)
            Text(ThaiFormat.weekdayShort.string(from: .now) + (appointments.isEmpty ? "" : " · \(page + 1)/\(appointments.count)"))
                .font(.sarabun(size.heroLabel, relativeTo: .caption)).opacity(labelOpacity).lineLimit(1)
            if appointments.count > 1 {
                pagerButton("chevron.left", label: "นัดก่อนหน้า", enabled: page > 0) { go(-1) }
                pagerButton("chevron.right", label: "นัดถัดไป", enabled: page < appointments.count - 1) { go(1) }
            }
        }
        .frame(minHeight: 32)
        .padding(.trailing, size.isPad ? -10 : -8).padding(.vertical, -6)
    }

    private func pagerButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size.isPad ? 18 : 16, weight: .bold)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func go(_ step: Int) {
        let next = page + step
        guard appointments.indices.contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { page = next }
    }

    private func actions(_ a: TodayAppointment) -> some View {
        HStack(spacing: size.isPad ? 10 : 8) {
            Button { open(a, a.nextStep?.page) } label: { primaryLabel(a.actionTitle) }
                .buttonStyle(.plain)
            if let c = a.coordinate {
                iconButton("location", label: "นำทาง") { openURL(mapsURL(c)) }
            }
            if !a.phone.isEmpty {
                iconButton("phone", label: "โทรหาผู้ประสานงาน") { calling = a }
            }
        }
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title).font(.sarabun(size.actionText, size.isPad ? .bold : .heavy, relativeTo: .subheadline))
            .foregroundStyle(size.isPad ? Theme.navy : Theme.heroSolid)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: size.action)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: size.actionRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: size.actionRadius, style: .continuous))
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            let shape = RoundedRectangle(cornerRadius: size.actionRadius, style: .continuous)
            if size.isPad {
                Image(systemName: symbol).font(.system(size: 21, weight: .semibold))
                    .frame(width: 56, height: size.action)
                    .background(.white.opacity(0.16), in: shape)
            } else {
                // v2: 44 × 44, white 20 % with a white 35 % border
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.2), in: shape)
                    .overlay(shape.strokeBorder(.white.opacity(0.35)))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Apple Maps driving directions to a point.
func mapsURL(_ c: (lat: Double, lon: Double)) -> URL {
    URL(string: "http://maps.apple.com/?daddr=\(c.lat),\(c.lon)&dirflg=d")!
}

extension View {
    /// `โทร <number>` · `ส่งข้อความ` · `ดูรายละเอียดผู้ประสานงานใน A1` · `ยกเลิก` for the appointment being called.
    func callDialog(_ calling: Binding<TodayAppointment?>, open: @escaping (TodayAppointment, MissingGroup.Target?) -> Void) -> some View {
        modifier(CallDialog(calling: calling, open: open))
    }
}

private struct CallDialog: ViewModifier {
    @Binding var calling: TodayAppointment?
    let open: (TodayAppointment, MissingGroup.Target?) -> Void
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.confirmationDialog(calling?.contactName ?? "", isPresented: Binding(get: { calling != nil }, set: { if !$0 { calling = nil } }),
                                   titleVisibility: .visible, presenting: calling) { a in
            let digits = a.phone.filter { $0.isNumber || $0 == "+" }
            Button("โทร \(a.phone)") { if let url = URL(string: "tel:\(digits)") { openURL(url) } }
            Button("ส่งข้อความ") { if let url = URL(string: "sms:\(digits)") { openURL(url) } }
            if a.report != nil {
                Button("ดูรายละเอียดผู้ประสานงานใน A1") { open(a, .info) }
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: { a in
            Text("ผู้ประสานงาน · \(a.name)")
        }
    }
}

/// Ring, time, countdown, job name and place of one appointment.
private struct AppointmentBody: View {
    let size: HomeSize
    let appointment: TodayAppointment

    var body: some View {
        HStack(spacing: size.isPad ? 18 : 12) {
            ProgressRing(size: size, fraction: appointment.fraction, percent: appointment.percent)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: size.isPad ? 10 : 8) {
                    Text(appointment.time).font(.sarabun(size.time, .bold, relativeTo: .title2)).monospacedDigit()
                    Text("นัดสำรวจ · \(appointment.countdown)").font(.sarabun(size.kind, relativeTo: .caption)).opacity(size.isPad ? 0.9 : 0.95).lineLimit(1)
                }
                Text(appointment.name).font(.sarabun(size.name, .bold, relativeTo: .subheadline)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !appointment.place.isEmpty {
                    Text(appointment.place).font(.sarabun(size.place, relativeTo: .caption)).opacity(size.isPad ? 0.8 : 0.92).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressRing: View {
    let size: HomeSize
    let fraction: Double
    let percent: Int

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(size.isPad ? 0.22 : 0.28), lineWidth: size.ringStroke)
            Circle().trim(from: 0, to: fraction)
                .stroke(size.isPad ? Theme.ringDone : Theme.ringOutdoor, style: StrokeStyle(lineWidth: size.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%").font(.sarabun(size.ringText, .bold, relativeTo: .caption)).monospacedDigit()
        }
        .padding(size.ringStroke / 2)
        .frame(width: size.ring, height: size.ring)
        .accessibilityLabel("กรอกแล้ว \(percent)%")
    }
}
