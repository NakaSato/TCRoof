import SwiftUI
import Observation
import TCRoofCore
import TCRoofUI

/// `config/app.minSyncVersion` against this build (`AppCompat`): an outdated build shows `ต้องอัปเดตแอป` over everything
/// and `CloudSync` pushes nothing. The minimum is kept on the device, so an outdated build stays stopped offline.
@MainActor
@Observable
final class AppGate {
    static let shared = AppGate()
    private static let minimumKey = "appGate.minSyncVersion"
    private static let linkKey = "appGate.installLink"

    private(set) var minimum: Int?
    /// `config/app.installLink`: where to get the new build (TestFlight or the App Store).
    private(set) var installLink: URL?

    var outdated: Bool {
        #if DEBUG
        // `-appOutdated YES`: the screen without touching the console
        if UserDefaults.standard.bool(forKey: "appOutdated") { return true }
        #endif
        return AppCompat.isOutdated(minimum: minimum)
    }

    private init() {
        let d = UserDefaults.standard
        minimum = d.object(forKey: Self.minimumKey) as? Int
        installLink = d.string(forKey: Self.linkKey).flatMap(URL.init(string:))
    }

    /// From the `config/app` listener. Returns true when this build was stopped and no longer is.
    @discardableResult
    func update(minimum: Int?, installLink: String?) -> Bool {
        let was = outdated
        self.minimum = minimum
        self.installLink = installLink.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        let d = UserDefaults.standard
        d.set(minimum, forKey: Self.minimumKey)
        d.set(installLink, forKey: Self.linkKey)
        return was && !outdated
    }
}

/// Shown over the signed-in app while `AppGate.outdated`: nothing more is sent until the update, and what was edited on
/// this device stays for the new build to send.
struct UpdateRequiredView: View {
    @State private var gate = AppGate.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Space.l) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("ต้องอัปเดตแอป")
                        .font(.sarabun(24, .bold, relativeTo: .title2))
                        .foregroundStyle(Theme.navy)
                        .accessibilityAddTraits(.isHeader)
                    Text("แอปเวอร์ชันนี้ซิงก์กับทีมไม่ได้แล้ว ข้อมูลที่บันทึกในเครื่องนี้ยังอยู่ครบ และจะส่งขึ้นเมื่ออัปเดตเป็นเวอร์ชันใหม่")
                        .font(.sarabun(15, relativeTo: .subheadline))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let link = gate.installLink {
                    Button("อัปเดตแอป") { openURL(link) }
                        .buttonStyle(TCButtonStyle(.primary, size: .page, fullWidth: true))
                } else {
                    Text("ติดต่อผู้จัดการเพื่อรับลิงก์ติดตั้งเวอร์ชันใหม่")
                        .font(.sarabun(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.warningText)
                }
                Text("เวอร์ชันซิงก์ของเครื่องนี้ \(AppCompat.syncVersion) · ต้องการ \(gate.minimum ?? 0)")
                    .font(.sarabun(TypeScale.caption, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            .padding(24)
            .frame(maxWidth: 480)
        }
        .accessibilityIdentifier("updateRequired")
    }
}
