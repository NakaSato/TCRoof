#if canImport(UIKit)
import SwiftUI

/// The single line diagram's zoom steps, shared by the SLD page and A3's diagram card.
enum ZoomStep {
    /// The next level up (`by` > 0) or down from `scale`, staying at the ends.
    static func next(_ scale: CGFloat, levels: [CGFloat], by d: Int) -> CGFloat {
        d > 0 ? levels.first { $0 > scale + 0.005 } ?? levels.last! : levels.last { $0 < scale - 0.005 } ?? levels.first!
    }
}

/// A 44 pt `−` / `+` zoom button.
struct ZoomStepButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    init(_ symbol: String, _ label: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.primary).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}
#endif
