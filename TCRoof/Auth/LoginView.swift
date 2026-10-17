import SwiftUI
import TCRoofUI

/// Sign-in on a photo of a solar roof (`LoginBackground`, Pexels) and one frosted-glass card at the bottom: the company
/// logo with TCRoof, then the Google button (`TCButtonStyle` secondary), the error as a `TCWarningBanner`, who may sign
/// in and the version.
struct LoginView: View {
    @Environment(GoogleSession.self) private var session
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.xl)
            card
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, isPhone ? Space.l : 32)
        .padding(.bottom, isPhone ? Space.l : 64)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { backdrop }
        .environment(\.colorScheme, .light)
        .animation(.snappy, value: notice)
    }

    /// The photo, filling the screen; the sky under the status bar is lightened a little so it reads.
    private var backdrop: some View {
        GeometryReader { geo in
            Image("LoginBackground")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Theme.surface.opacity(0.55), Theme.surface.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 140)
                }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// The logo and the app's name, at the top of the card.
    private var brand: some View {
        HStack(spacing: Space.m) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .cardShadow()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("TCRoof")
                    .font(.sarabun(24, .bold, relativeTo: .title2))
                    .foregroundStyle(Theme.navy)
                    .accessibilityAddTraits(.isHeader)
                Text("TC Renewable")
                    .font(.sarabun(TypeScale.caption, relativeTo: .caption))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            brand
            Rectangle().fill(Theme.navy.opacity(0.1)).frame(height: 1)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("เข้าสู่ระบบ")
                    .font(.sarabun(20, .bold, relativeTo: .title3))
                    .foregroundStyle(Theme.navy)
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
            footer
        }
        .padding(isPhone ? 20 : 24)
        // frosted glass: the photo shows blurred through it
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.surface.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
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
