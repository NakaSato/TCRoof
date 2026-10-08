#if canImport(UIKit)
import SwiftUI
import UIKit
import CoreText

/// Sarabun 400/700 (the app's Resources/Fonts, SIL OFL), registered at launch so no Info.plist entry is needed.
public enum AppFont {
    public static func register() {
        for name in ["Sarabun-Regular", "Sarabun-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

public extension Font {
    /// Sarabun at `size`, scaling with Dynamic Type like `style`; semibold and heavier use the bold face.
    static func sarabun(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let bold = [Font.Weight.semibold, .bold, .heavy, .black].contains(weight)
        return .custom(bold ? "Sarabun-Bold" : "Sarabun-Regular", size: size, relativeTo: style)
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A token with a light and a dark value (docs/ui/components/tokens.css).
    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: opacity)
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

/// Design system "TCRoof Survey": colours of docs/ui/components/tokens.css, light and dark.
public enum Theme {
    public static let navy = Color(light: 0x16325C, dark: 0xC9D8EE)
    public static let primary = Color(light: 0x1F6FB5, dark: 0x5BB0F0)
    /// Text and icons on `primary` and the blue gradients.
    public static let onPrimary = Color(light: 0xFFFFFF, dark: 0x0B1A2E)
    public static let primaryLight = Color(hex: 0x2E8FDB)
    public static let primarySoft = Color(light: 0xE3EEF8, dark: 0x16273A)
    public static let teal = Color(hex: 0x27A99A)
    /// End of `tealGradient`.
    public static let tealLight = Color(hex: 0x4DB6E0)
    /// Calculated values, selected chips.
    public static let mint = Color(light: 0x9EE6D6, dark: 0x1E5A52)
    public static let chip = Color(hex: 0x5E9BD0)
    /// "ข้อมูลตัวอย่าง" chip.
    public static let sun = Color(hex: 0xFFC53D)
    public static let background = Color(light: 0xF3F6FA, dark: 0x0E141C)
    public static let surface = Color(light: 0xFFFFFF, dark: 0x121A24)
    public static let muted = Color(hex: 0x7A8BA3)
    public static let inkMuted = Color(light: 0x5B6B82, dark: 0x9DB0C7)
    public static let borderControl = Color(light: 0x77889E, dark: 0x6B7D93)
    public static let borderSubtle = Color(light: 0xDDE4ED, dark: 0x243142)

    // paper form (green bands of the NO.224 workbook)
    public static let paperBand = Color(light: 0xE2EFDA, dark: 0x1E2A22)
    /// `paper-page`: weekend and other-month days on the plan calendar, info notes.
    public static let paperPage = Color(light: 0xF2F2F7, dark: 0x1C1C1E)
    public static let paperInk = Color(light: 0x1F2E24, dark: 0xDCEBD2)
    public static let paperValue = Color(light: 0x1F4F78, dark: 0x7CC4F5)
    public static let paperRule = Color(light: 0x000000, dark: 0xFFFFFF, opacity: 0.75)
    public static let paperTick = Color(light: 0x70AD47, dark: 0x8FD16A)
    public static let paperTickStrong = okTick

    // status pairs (section 4)
    /// Checkbox fill, "ครบ" chip text.
    public static let okTick = Color(light: 0x3B7420, dark: 0x8FD16A)
    /// Background of the ok chip (same as `paperBand`).
    public static let okSoft = Color(light: 0xE2EFDA, dark: 0x1E2A22)
    /// Text of the ok chip "พร้อมใช้".
    public static let okText = Color(light: 0x2E7D32, dark: 0x8FD16A)
    public static let pending = Color(light: 0xB45309, dark: 0xF5B35C)
    public static let pendingSoft = Color(light: 0xFFF4E5, dark: 0x2E2213)
    public static let danger = Color(light: 0xD9453B, dark: 0xFF8A7F)
    public static let dangerText = Color(light: 0xB42318, dark: 0xFF8A7F)
    public static let dangerSoft = Color(light: 0xFDECEA, dark: 0x3A1C1A)

    public static let unreadRow = Color(hex: 0xF3F8FD)
    /// Survey job card progress box: fill while a draft is open, fill otherwise, finished-group bar,
    /// percent at 100 % and at 0 %.
    public static let progressBox = Color(hex: 0xEEF4FB)
    public static let progressBoxIdle = Color(hex: 0xF3F6FA)
    public static let stepDone = Color(hex: 0x70AD47)
    public static let progressFull = Color(hex: 0x2E7D32)
    public static let progressZero = Color(hex: 0x9AA6B6)

    // iPhone home board (docs/ui/tcroof-home-iphone)
    public static let phonePage = Color(hex: 0xF5F8FB)
    /// Quiet fill of round icon buttons, and row separators.
    public static let hairline = Color(hex: 0xEEF2F7)
    public static let chevron = Color(hex: 0xAAB6C5)
    public static let success = Color(hex: 0x2E9E5B)
    public static let successInk = Color(hex: 0x3B7420)
    public static let warning = Color(hex: 0xF08C00)
    public static let warningSoft = Color(hex: 0xFFF1DE)
    public static let ringDone = Color(hex: 0x8FD16A)
    // iPhone survey list (docs/ui/tcroof-survey-list-iphone)
    /// `TCSegmented(.filter)` track and the search field's ✕ circle.
    public static let segmentTrack = Color(light: 0xEEF2F7, dark: 0x1C2734)
    // iPhone home v2, outdoor contrast (docs/ui/tcroof-home-iphone-v2); the iPad keeps the tokens above
    /// `นัดวันนี้` card fill and the text of its white button.
    public static let heroSolid = Color(light: 0x0E2747, dark: 0x123A66)
    /// Progress of the hero card's ring.
    public static let ringOutdoor = Color(hex: 0x9BE26E)
    /// Secondary text in sun: module subtitles, notification details, settings labels.
    public static let inkStrong = Color(light: 0x44546A, dark: 0xB4C3D6)
    /// Unselected tab of `TCTabBar`, secondary icons and labels.
    public static let inkTab = Color(light: 0x3E4C60, dark: 0xC2CFDF)
    /// `TCTabBar`'s top line, module rows and card borders.
    public static let borderOutdoor = Color(light: 0xC9D3E0, dark: 0x34465C)
    // iPad home board (docs/ui/tcroof-home-ipad)
    /// Hairline under the white header #E6EBF2.
    public static let headerLine = Color(hex: 0xE6EBF2)
    /// Light dim of the page behind the bell popover.
    public static let popoverDim = navy.opacity(0.12)
    // iPhone plan calendar (docs/ui/tcroof-plan-calendar-iphone)
    /// Survey appointment diamond and the survey row's leading rule.
    public static let survey = Color(light: 0xD6336C, dark: 0xF06595)
    /// Day numbers outside the shown month.
    public static let dayOutside = Color(light: 0xC3CBD6, dark: 0x3A4757)
    /// Selected row of a dropdown menu (the team filter).
    public static let rowSelected = Color(light: 0xEEF3F9, dark: 0x1C2734)

    // component board (docs/ui/components)
    /// Progress ring track, empty segments of a segmented bar.
    public static let track = Color(light: 0xE6ECF3, dark: 0x243142)
    /// Disabled button fill and text.
    public static let disabledFill = Color(light: 0xE6EBF2, dark: 0x1E2733)
    public static let disabledText = Color(light: 0x9AA6B6, dark: 0x5E6E83)
    /// Number pad keys, the `ทำต่อ` strip.
    public static let keyFill = Color(light: 0xEEF4FB, dark: 0x16273A)
    /// Dark toast.
    public static let toast = Color(hex: 0x3A3A3C, opacity: 0.94)
    /// FAB shadow: primary at 35 %.
    public static let fabShadow = Color(hex: 0x1F6FB5, opacity: 0.35)
    /// Grey todo capsule and the off ‹ › of the bottom bar, rgba(142,142,147,.25).
    public static let capsuleTodo = Color(hex: 0x8E8E93, opacity: 0.25)
    // Grouped iOS lists and bottom sheets (docs/ui/tcroof-new-job-iphone).
    /// Page and sheet background behind white group cards (≈ systemGroupedBackground).
    public static let groupedPage = Color(light: 0xF7F7FA, dark: 0x000000)
    /// Group header text.
    public static let groupHeader = Color(light: 0x6D6D72, dark: 0x98989D)
    /// Group footer text.
    public static let groupFooter = Color(light: 0x8E8E93, dark: 0x8E8E93)
    /// Placeholder text and disclosure chevrons.
    public static let placeholder = Color(light: 0xC4C4C7, dark: 0x5A5A5E)
    /// Row separators and unselected option borders.
    public static let separatorLine = Color(light: 0xE5E5EA, dark: 0x38383A)
    /// Tappable values, `เสร็จ`, `แสดง`.
    public static let iosBlue = Color(light: 0x007AFF, dark: 0x0A84FF)
    /// Selected option in a grid picker.
    public static let optionSelected = Color(light: 0xEAF3FF, dark: 0x0F2540)
    /// Search field fill.
    public static let searchFill = Color(light: 0xEEEEF0, dark: 0x1C1C1E)
    /// Saved banner: navy in both modes, since its text is white.
    public static let bannerFill = Color(hex: 0x16325C)
    /// Sheet grabber.
    public static let grabber = Color(light: 0xC7C7CC, dark: 0x48484A)
    /// Text on `sun` (the example-data chip): navy in both modes, since `sun` stays yellow.
    public static let onSun = Color(hex: 0x16325C)
    /// Empty required photo slot: dashed border #E7B3AE on #FFF8F7.
    public static let photoEmptyBorder = Color(light: 0xE7B3AE, dark: 0x6A3430)
    public static let photoEmptyFill = Color(light: 0xFFF8F7, dark: 0x22161A)
    /// Map placeholder land #E8EEF5.
    public static let mapLand = Color(light: 0xE8EEF5, dark: 0x1A2430)
    /// Grey stand-in for a photo, 160°.
    public static let photoPlaceholder = LinearGradient(colors: [Color(hex: 0x8E959B), Color(hex: 0x5C6773)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Lock-screen wallpaper behind the sample iOS banner, 170°.
    public static let wallpaperGradient = LinearGradient(colors: [Color(hex: 0x0A2458), Color(hex: 0x1257C9), teal],
                                                         startPoint: .top, endPoint: .bottom)

    /// Expanded timeline row's action button, 135°.
    public static let actionGradient = LinearGradient(colors: [primary, primaryLight], startPoint: .topLeading, endPoint: .bottomTrailing)
    public static let heroGradient = LinearGradient(colors: [primary, navy], startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1))
    /// #1F6FB5 → #2E8FDB: headers, primary gradient buttons, "ถัดไป".
    public static let headerGradient = LinearGradient(colors: [Color(hex: 0x1F6FB5), primaryLight], startPoint: .leading, endPoint: .trailing)
    /// #27A99A → #4DB6E0: the survey module's call to action.
    public static let tealGradient = LinearGradient(colors: [teal, tealLight], startPoint: .leading, endPoint: .trailing)
    public static let pageGradient = LinearGradient(colors: [Color(light: 0xDCE8F2, dark: 0x0E141C), background], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
}

/// Spacing scale 4 / 8 / 12 / 16 / 24.
public enum Space {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
}

/// Corner radii 3 / 8 / 10 / 12 / 16.
public enum Radius {
    /// Checkbox.
    public static let box: CGFloat = 3
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 12
    public static let xl: CGFloat = 16
}

/// Type scale: header 30, page title 24, field label 17, caption 13.
public enum TypeScale {
    public static let header: CGFloat = 30
    public static let pageTitle: CGFloat = 24
    public static let label: CGFloat = 17
    public static let caption: CGFloat = 13
}

/// Smallest hit area, 44 pt.
public let touchMin: CGFloat = 44

public extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .cardShadow()
    }
    /// `shadow-card`: y 3, blur 8, navy 8%.
    func cardShadow() -> some View { shadow(color: Color(hex: 0x16325C, opacity: 0.08), radius: 8, y: 3) }
}

public struct OutlinedFieldStyle: TextFieldStyle {
    public init() {}
    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Theme.navy.opacity(0.45)))
    }
}
#endif
