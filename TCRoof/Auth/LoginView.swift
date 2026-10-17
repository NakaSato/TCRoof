import SwiftUI
import TCRoofUI

/// The company logo on the brand gradient, and one card with the Google sign-in button: who may sign in, what went
/// wrong when it fails, and the app version.
struct LoginView: View {
    @Environment(GoogleSession.self) private var session
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.loginGradient.ignoresSafeArea()
            glow

            // the phone keeps the card at the thumb; the iPad centres logo and card as one group
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                brand
                if isPhone { Spacer(minLength: 24) } else { Spacer().frame(height: 56) }
                card
                if !isPhone { Spacer(minLength: 24) }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, isPhone ? Space.m + 4 : 32)
            .padding(.bottom, isPhone ? Space.m : 56)
        }
        // the app runs dark here only for a white status bar; the brand colours stay light
        .environment(\.colorScheme, .light)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }

    /// A soft light behind the logo, so the gradient isn't flat.
    private var glow: some View {
        RadialGradient(colors: [Theme.onPrimary.opacity(0.18), .clear], center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: 320)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var logoSide: CGFloat { isPhone ? 104 : 128 }

    private var brand: some View {
        VStack(spacing: Space.m) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: logoSide, height: logoSide)
                .clipShape(RoundedRectangle(cornerRadius: logoSide / 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: logoSide / 4, style: .continuous).stroke(Theme.onPrimary.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
                .accessibilityHidden(true)
            Text("TCRoof")
                .font(.system(size: isPhone ? 34 : 40, weight: .heavy))
                .foregroundStyle(Theme.onPrimary)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .accessibilityElement(children: .combine)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("เข้าสู่ระบบ")
                    .font(.sarabun(22, .bold, relativeTo: .title2))
                    .foregroundStyle(Theme.navy)
                Text("ใช้บัญชี Google ที่ได้รับเชิญเข้าทีม")
                    .font(.sarabun(15, relativeTo: .subheadline))
                    .foregroundStyle(Theme.inkMuted)
            }

            if let notice {
                Label(notice, systemImage: "exclamationmark.circle.fill")
                    .font(.sarabun(14, relativeTo: .footnote))
                    .foregroundStyle(Theme.dangerText)
                    .padding(.horizontal, Space.m - 4).padding(.vertical, Space.s + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            googleButton

            HStack(spacing: Space.xs + 2) {
                Image(systemName: "lock.fill").font(.system(size: 11))
                Text("เฉพาะสมาชิกทีม TC Renewable")
                Spacer(minLength: Space.s)
                if let version { Text(version).monospacedDigit() }
            }
            .font(.sarabun(12, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
        }
        .padding(isPhone ? 20 : 28)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
        .animation(.snappy, value: notice)
    }

    private var googleButton: some View {
        Button(action: signIn) {
            HStack(spacing: Space.m - 4) {
                if isLoading { ProgressView().tint(Theme.navy) } else { GoogleMark() }
                Text(isLoading ? "กำลังเข้าสู่ระบบ…" : "เข้าสู่ระบบด้วย Google")
            }
            .font(.sarabun(17, .semibold, relativeTo: .headline))
            .foregroundStyle(Theme.navy)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.lg + 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg + 2, style: .continuous).stroke(Theme.borderSubtle, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(isLoading || !session.hasValidClientID)
        .opacity(session.hasValidClientID ? 1 : 0.55)
    }

    /// The last sign-in failure, or why the button can't be used yet.
    private var notice: String? {
        errorMessage ?? (session.hasValidClientID ? nil : "ยังไม่ได้ตั้งค่า Google Client ID ของแอป")
    }

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
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(AngularGradient(
                colors: [Color(hex: 0xEA4335), Color(hex: 0xFBBC05), Color(hex: 0x34A853), Color(hex: 0x4285F4), Color(hex: 0xEA4335)],
                center: .center, startAngle: .degrees(-40), endAngle: .degrees(320)))
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
