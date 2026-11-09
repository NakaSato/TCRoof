import SwiftUI
import TCRoofUI

/// ผู้ช่วยโครงการ on the iPad page (CHA-68, board "iPad · ติดตามงานติดตั้ง"): a panel over the page on the right, 16 pt
/// in from the top, right and bottom, about 70 % of the page wide, over a dimmed page whose tap closes it. It opens
/// from the header on every tab. The iPhone keeps the sheet.
extension InstallTrackingPage {
    /// The iPhone's sheet: only in compact width, so the iPad's panel never shows a sheet too.
    var phoneAssistant: Binding<Bool> {
        Binding(get: { assistant && sizeClass == .compact }, set: { assistant = $0 })
    }

    func assistantPanel() -> some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                Theme.navySolid.opacity(0.38).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { assistant = false }
                    .accessibilityHidden(true)
                AssistantChatView(focus: job, style: .panel, onClose: { assistant = false },
                                  openPlan: canOpen(.plan) ? { assistant = false; tab = .plan } : nil)
                    .frame(width: min(geo.size.width - 32, max(560, geo.size.width * 0.7)))
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Theme.navySolid.opacity(0.18), radius: 24, y: 8)
                    .padding(16)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .transition(.opacity)
    }
}
