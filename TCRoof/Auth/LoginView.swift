import SwiftUI
import TCRoofUI

/// Logo and a single Google sign-in button on the brand gradient.
struct LoginView: View {
    @Environment(GoogleSession.self) private var session
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0E2344), Theme.navy, Theme.primary],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "house.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 84, height: 84)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                Text("TCRoof")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.top, 18)
                Spacer()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }

                Button(action: signIn) {
                    HStack(spacing: 12) {
                        if isLoading { ProgressView().tint(Theme.navy) } else { GoogleMark() }
                        Text("เข้าสู่ระบบด้วย Google")
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(isLoading || !session.hasValidClientID)
                .opacity(session.hasValidClientID ? 1 : 0.55)
            }
            .frame(maxWidth: 380)
            .padding(.horizontal, 28)
            .padding(.bottom, isPhone ? 24 : 64)
        }
        // the app runs dark here only for a white status bar; the brand colours stay light
        .environment(\.colorScheme, .light)
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
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
