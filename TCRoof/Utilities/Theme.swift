import SwiftUI
import CoreText

/// Sarabun 400/700 (Resources/Fonts, SIL OFL), registered at launch so no Info.plist entry is needed.
enum AppFont {
    static func register() {
        for name in ["Sarabun-Regular", "Sarabun-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Sarabun at `size`, scaling with Dynamic Type like `style`; semibold and heavier use the bold face.
    static func sarabun(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let bold = [Font.Weight.semibold, .bold, .heavy, .black].contains(weight)
        return .custom(bold ? "Sarabun-Bold" : "Sarabun-Regular", size: size, relativeTo: style)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    static let navy = Color(hex: 0x16325C)
    static let primary = Color(hex: 0x1F6FB5)
    static let primaryLight = Color(hex: 0x2E8FDB)
    static let teal = Color(hex: 0x27A99A)
    static let mint = Color(hex: 0x9EE6D6)
    static let danger = Color(hex: 0xD9453B)
    static let background = Color(hex: 0xF3F6FA)
    static let muted = Color(hex: 0x7A8BA3)
    static let chip = Color(hex: 0x5E9BD0)

    // design system "TCRoof Survey" (docs/ui/tcroof-home)
    static let surface = Color.white
    static let inkMuted = Color(hex: 0x5B6B82)
    static let borderControl = Color(hex: 0x77889E)
    static let borderSubtle = Color(hex: 0xDDE4ED)
    static let primarySoft = Color(hex: 0xE3EEF8)
    static let paperBand = Color(hex: 0xE2EFDA)
    static let paperInk = Color(hex: 0x1F2E24)
    static let paperTickStrong = Color(hex: 0x4E7F2E)
    static let pending = Color(hex: 0xB45309)
    static let pendingSoft = Color(hex: 0xFDF1E4)
    static let unreadRow = Color(hex: 0xF3F8FD)
    /// Survey job card progress box: fill while a draft is open, fill otherwise, finished-group bar,
    /// percent at 100 % and at 0 %.
    static let progressBox = Color(hex: 0xEEF4FB)
    static let progressBoxIdle = Color(hex: 0xF3F6FA)
    static let stepDone = Color(hex: 0x70AD47)
    static let progressFull = Color(hex: 0x2E7D32)
    static let progressZero = Color(hex: 0x9AA6B6)

    // iPhone home board (docs/ui/tcroof-home-iphone)
    static let phonePage = Color(hex: 0xF5F8FB)
    /// Quiet fill of round icon buttons, and row separators.
    static let hairline = Color(hex: 0xEEF2F7)
    static let chevron = Color(hex: 0xAAB6C5)
    static let success = Color(hex: 0x2E9E5B)
    static let successInk = Color(hex: 0x3B7420)
    static let warning = Color(hex: 0xF08C00)
    static let warningSoft = Color(hex: 0xFFF1DE)
    static let ringDone = Color(hex: 0x8FD16A)
    // iPad home board (docs/ui/tcroof-home-ipad)
    /// Hairline under the white header #E6EBF2.
    static let headerLine = Color(hex: 0xE6EBF2)
    /// Light dim of the page behind the bell popover.
    static let popoverDim = navy.opacity(0.12)
    /// Expanded timeline row's action button, 135°.
    static let actionGradient = LinearGradient(colors: [primary, primaryLight], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let heroGradient = LinearGradient(colors: [primary, navy], startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1))

    static let headerGradient = LinearGradient(colors: [primary, primaryLight], startPoint: .leading, endPoint: .trailing)
    static let tealGradient = LinearGradient(colors: [teal, Color(hex: 0x4DB6E0)], startPoint: .leading, endPoint: .trailing)
    static let pageGradient = LinearGradient(colors: [Color(hex: 0xDCE8F2), background], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.navy.opacity(0.08), radius: 8, y: 3)
    }
    /// `shadow-card`: y 3, blur 8, navy 8%.
    func cardShadow() -> some View { shadow(color: Theme.navy.opacity(0.08), radius: 8, y: 3) }
}

struct OutlinedFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.navy.opacity(0.45)))
    }
}
