import SwiftUI
import TCRoofUI

/// Sign-in. The solar roof photo (`LoginBackground`, Pexels) carries the brand: the logo, TCRoof, one line on what the
/// app does and its three areas, on a navy shade so the white text reads. The sign-in itself sits on a plain surface
/// panel: on a wide screen (iPad) a column on the right, on iPhone a sheet at the bottom. A cancelled Google sheet is no
/// error; a failure shows as a `TCWarningBanner` above the button, and `เข้าสู่ระบบไม่ได้?` explains who may sign in.
struct LoginView: View {
    @Environment(GoogleSession.self) private var session
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsHelp = false

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700
            Group {
                if wide {
                    HStack(spacing: 0) {
                        hero(wide: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        panel(wide: true)
                            .frame(width: min(480, geo.size.width * 0.42))
                    }
                } else {
                    VStack(spacing: 0) {
                        hero(wide: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        panel(wide: false)
                    }
                }
            }
            .background { backdrop }
        }
        .environment(\.colorScheme, .light)
        .animation(.snappy, value: notice)
        .animation(.snappy, value: showsHelp)
    }

    // MARK: Photo and brand

    /// The photo, filling the screen behind both halves, shaded navy where the brand text sits.
    private var backdrop: some View {
        GeometryReader { geo in
            Image("LoginBackground")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: Theme.navySolid.opacity(0.15), location: 0),
                            .init(color: Theme.navySolid.opacity(0.35), location: 0.35),
                            .init(color: Theme.navySolid.opacity(0.85), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)
                }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func hero(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: wide ? Space.xl : Space.l) {
            Spacer(minLength: 0)
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: wide ? 72 : 60, height: wide ? 72 : 60)
                .clipShape(RoundedRectangle(cornerRadius: wide ? 16 : 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: wide ? 16 : 14, style: .continuous).stroke(Theme.onMedia.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s) {
                Text("TCRoof")
                    .font(.sarabun(wide ? 48 : 36, .bold, relativeTo: .largeTitle))
                    .accessibilityAddTraits(.isHeader)
                Text("สำรวจ ติดตั้ง และส่งมอบงานโซลาร์\nครบในแอปเดียวของทีม TC Renewable")
                    .font(.sarabun(wide ? 20 : 16, relativeTo: .title3))
                    .foregroundStyle(Theme.onMedia.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if wide {
                VStack(alignment: .leading, spacing: Space.m) {
                    feature("ruler", "สำรวจหน้างาน", "รายงาน PDF และ Excel จากหน้างาน")
                    feature("hammer", "ติดตามงานติดตั้ง", "แผน MP รายงานประจำวัน และ IEC 62446")
                    feature("folder", "เอกสาร กปภ. และส่งมอบ", "จัดเก็บขึ้น Google Drive ให้อัตโนมัติ")
                }
                .padding(.top, Space.s)
            }
        }
        .foregroundStyle(Theme.onMedia)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .frame(maxWidth: wide ? 520 : .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, wide ? 64 : 24)
        .padding(.bottom, wide ? 72 : 28)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Theme.onMedia.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(Theme.onMedia.opacity(0.25), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarabun(17, .semibold, relativeTo: .headline))
                Text(detail)
                    .font(.sarabun(14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.onMedia.opacity(0.8))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Sign-in panel

    private func panel(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if wide { Spacer(minLength: Space.xl) }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("เข้าสู่ระบบ")
                    .font(.sarabun(wide ? 28 : 22, .bold, relativeTo: .title2))
                    .foregroundStyle(Theme.navy)
                    .accessibilityAddTraits(.isHeader)
                Text("ใช้บัญชี Google ที่ได้รับเชิญเข้าทีม")
                    .font(.sarabun(15, relativeTo: .subheadline))
                    .foregroundStyle(Theme.inkMuted)
            }
            if let notice {
                TCWarningBanner(notice.title, message: notice.message)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Button(action: signIn) {
                HStack(spacing: Space.m - 2) {
                    if !isLoading { GoogleMark() }
                    Text(isLoading ? "กำลังเข้าสู่ระบบ…" : "เข้าสู่ระบบด้วย Google")
                }
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .page, fullWidth: true, working: isLoading))
            .disabled(isLoading || !session.hasValidClientID)
            help
            if wide { Spacer(minLength: Space.xl) }
            footer
        }
        .padding(.horizontal, wide ? 48 : 24)
        .padding(.top, wide ? 0 : 28)
        .padding(.bottom, wide ? 32 : Space.l)
        .frame(maxWidth: .infinity, maxHeight: wide ? .infinity : nil, alignment: .leading)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 28, bottomLeadingRadius: wide ? 28 : 0,
                bottomTrailingRadius: 0, topTrailingRadius: wide ? 0 : 28, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.18), radius: 24, x: wide ? -6 : 0, y: wide ? 0 : -6)
                .ignoresSafeArea(edges: wide ? [.vertical, .trailing] : .bottom)
        }
    }

    /// `เข้าสู่ระบบไม่ได้?`: who may sign in, opened in place under the button.
    private var help: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button {
                showsHelp.toggle()
            } label: {
                HStack(spacing: Space.xs + 2) {
                    Image(systemName: "questionmark.circle")
                    Text("เข้าสู่ระบบไม่ได้?")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(showsHelp ? 180 : 0))
                }
                .font(.sarabun(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(Theme.primary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsHelp ? "เปิดอยู่" : "ปิดอยู่")
            if showsHelp {
                VStack(alignment: .leading, spacing: Space.s) {
                    helpLine("person.badge.plus", "ผู้จัดการต้องเพิ่มอีเมล Google ของคุณเป็นสมาชิกทีมก่อน")
                    helpLine("envelope", "ใช้บัญชีเดียวกับที่ได้รับเชิญ เช่น Gmail ส่วนตัวหรืออีเมลบริษัท")
                    helpLine("wifi", "ต้องต่ออินเทอร์เน็ตตอนเข้าสู่ระบบ")
                }
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func helpLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.primary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.sarabun(14, relativeTo: .footnote))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: Space.xs + 2) {
            Image(systemName: "lock.fill").font(.system(size: 11))
            Text("เฉพาะสมาชิกทีม TC Renewable")
            if let version {
                Text("·")
                Text(version).monospacedDigit()
            }
        }
        .font(.sarabun(TypeScale.caption, relativeTo: .caption))
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity)
    }

    // MARK: State

    /// The last sign-in failure, or why the button can't be used yet.
    private var notice: Notice? {
        if let errorMessage { return Notice(title: "เข้าสู่ระบบไม่สำเร็จ", message: errorMessage) }
        return session.hasValidClientID ? nil : Notice(title: "ยังเข้าสู่ระบบไม่ได้", message: "ยังไม่ได้ตั้งค่า Google Client ID ของแอป")
    }

    private struct Notice: Equatable { let title: String; let message: String }

    private var version: String? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { "v" + $0 }
    }

    private func signIn() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await session.signIn()
            } catch GoogleAuth.Failure.cancelled {
                // closing Google's sheet is a choice, not a failure
            } catch {
                withAnimation { errorMessage = error.localizedDescription }
            }
            isLoading = false
        }
    }
}

/// Four-colour "G" for the Google button.
private struct GoogleMark: View {
    var body: some View {
        Text("G")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(AngularGradient(
                colors: [Color(hex: 0xEA4335), Color(hex: 0xFBBC05), Color(hex: 0x34A853), Color(hex: 0x4285F4), Color(hex: 0xEA4335)],
                center: .center, startAngle: .degrees(-40), endAngle: .degrees(320)))
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}
