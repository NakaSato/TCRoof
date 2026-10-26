#if canImport(UIKit)
import SwiftUI

/// "ยังตรวจแบบไม่ครบ n จุด" on a layout built from a standard design whose check isn't finished
/// (docs/specs/standard-designs.md §4): D1's panel layout and C1's แผงบนหลังคา. A tap goes back to the check.
struct DesignCheckBanner: View {
    let open: Int
    /// จุด for the tank's points, รายการ for the roof's items.
    let unit: String
    let check: () -> Void

    var body: some View {
        Button(action: check) {
            HStack(spacing: 0) {
                TCWarningBanner("ยังตรวจแบบไม่ครบ \(open) \(unit)",
                                message: "แผงที่วางอาจเปลี่ยนเมื่อตรวจครบ | แตะเพื่อไปตรวจ")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("ไปตรวจแบบ")
    }
}
#endif
