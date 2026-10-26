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

    /// Sarabun at a fixed size, for the survey's wide pages: they are laid out to fit one screen, so their text
    /// does not grow with the text-size setting (as `.system(size:)` did not).
    static func sarabunFixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let bold = [Font.Weight.semibold, .bold, .heavy, .black].contains(weight)
        return .custom(bold ? "Sarabun-Bold" : "Sarabun-Regular", fixedSize: size)
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
    /// Selected filter pill and confirmed plan points: navy in both modes, under white text.
    public static let navySolid = Color(hex: 0x16325C)
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
    /// Behind plans, diagrams and the signature pad: white in both modes, since their ink is dark.
    public static let paper = Color.white
    /// Text and icons over the camera, photos and the full-screen viewer: white in both modes.
    public static let onMedia = Color.white
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
    /// Fill of the save button for 1.35 s after a save (`TCSaveButton`).
    public static let okFlash = Color(light: 0xF1F8EC, dark: 0x1E2A22)
    public static let pending = Color(light: 0xB45309, dark: 0xF5B35C)
    public static let pendingSoft = Color(light: 0xFFF4E5, dark: 0x2E2213)
    public static let danger = Color(light: 0xD9453B, dark: 0xFF8A7F)
    public static let dangerText = Color(light: 0xB42318, dark: 0xFF8A7F)
    /// Light red of a missing section in the editor sidebar.
    public static let dangerLine = Color(light: 0xF2A09A, dark: 0x7A3A35)
    public static let dangerSoft = Color(light: 0xFDECEA, dark: 0x3A1C1A)
    /// Work the plan has reached and the site hasn't: the overdue segments of an install bar.
    public static let dangerPale = Color(light: 0xF4B4AE, dark: 0x5A2A26)

    public static let unreadRow = Color(light: 0xF3F8FD, dark: 0x15212D)
    /// Survey job card progress box: fill while a draft is open, fill otherwise, finished-group bar,
    /// percent at 100 % and at 0 %.
    public static let progressBox = Color(light: 0xEEF4FB, dark: 0x16273A)
    public static let progressBoxIdle = Color(light: 0xF3F6FA, dark: 0x161E29)
    public static let stepDone = Color(hex: 0x70AD47)
    public static let progressFull = Color(light: 0x2E7D32, dark: 0x8FD16A)
    public static let progressZero = Color(hex: 0x9AA6B6)

    // iPhone home board (docs/ui/tcroof-home-iphone)
    public static let phonePage = Color(light: 0xF5F8FB, dark: 0x0E141C)
    /// Quiet fill of round icon buttons, and row separators.
    public static let hairline = Color(light: 0xEEF2F7, dark: 0x1C2734)
    public static let chevron = Color(light: 0xAAB6C5, dark: 0x5E6E83)
    public static let success = Color(hex: 0x2E9E5B)
    public static let successInk = Color(light: 0x3B7420, dark: 0x8FD16A)
    public static let warning = Color(hex: 0xF08C00)
    public static let warningSoft = Color(light: 0xFFF1DE, dark: 0x2E2213)
    // iPhone home v3 project feed (docs/ui/tcroof-home-iphone-v3): the green and orange badge pairs
    public static let successSoft = Color(light: 0xE8F5EE, dark: 0x16271D)
    public static let successText = Color(light: 0x1F6B43, dark: 0x8FD16A)
    public static let warningText = Color(light: 0x9A4A06, dark: 0xF5B35C)
    public static let ringDone = Color(hex: 0x8FD16A)
    // iPad install tracking (docs/ui/install-tracking-ipad)
    /// The page's tab bar track, and its tabs' resting text.
    public static let projectTabTrack = Color(light: 0xE9EEF5, dark: 0x1C2734)
    public static let projectTabInk = Color(light: 0x3B4A60, dark: 0x9DB0C7)
    // iPad install tracking v2 (docs/ui/install-tracking-ipad-v2)
    /// The outline of a critical-path bar that isn't done, and today's column tint (at 6 %).
    public static let installCritical = Color(light: 0xC0392B, dark: 0xF07468)
    /// A sub-task's dotted float tail.
    public static let installFloat = Color(light: 0x8FA3BC, dark: 0x6A7D95)
    /// Stripes of the days waiting on the utility, and of days off.
    public static let installWait = Color(light: 0x8FA3BC, dark: 0x5E6E83, opacity: 0.16)
    /// A Sunday's column.
    public static let installSunday = Color(light: 0xF8FAFC, dark: 0x18212C)
    /// A planned sub-task bar.
    public static let installPlanned = Color(light: 0xAFC0D4, dark: 0x4A5D74)
    /// A stage's baseline line under its bar.
    public static let installBaseline = Color(light: 0x6B7A8F, dark: 0x8A9AB0)
    // iPhone survey list (docs/ui/tcroof-survey-list-iphone)
    /// `TCSegmented(.filter)` track and the search field's ✕ circle.
    public static let segmentTrack = Color(light: 0xEEF2F7, dark: 0x1C2734)
    // iPhone survey home (docs/ui/tcroof-survey-home-iphone)
    /// The search field's resting border: navy at 50 %.
    public static let searchBorder = Color(light: 0x16325C, dark: 0xC9D8EE, opacity: 0.5)
    /// The dock's add-customer glyph, a darker `teal` for contrast on the glass.
    public static let dockTeal = Color(light: 0x1F8F83, dark: 0x4FC3B5)
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
    public static let headerLine = Color(light: 0xE6EBF2, dark: 0x243142)
    /// Light dim of the page behind the bell popover.
    public static let popoverDim = navy.opacity(0.12)
    // iPhone plan calendar (docs/ui/tcroof-plan-calendar-iphone)
    /// Survey appointment diamond and the survey row's leading rule.
    public static let survey = Color(light: 0xD6336C, dark: 0xF06595)
    /// Day numbers outside the shown month.
    public static let dayOutside = Color(light: 0xC3CBD6, dark: 0x3A4757)
    /// Selected row of a dropdown menu (the team filter).
    public static let rowSelected = Color(light: 0xEEF3F9, dark: 0x1C2734)

    // iPhone PWA plan page (docs/ui/pwa-plan-iphone): ink and fill of the job types that have no status pair
    public static let planSurvey = Color(light: 0x0E7C86, dark: 0x5CC8D1)
    public static let planSurveySoft = Color(light: 0xE0F4F5, dark: 0x12292B)
    public static let planInspect = Color(light: 0x6B4FBB, dark: 0xB09CF0)
    public static let planInspectSoft = Color(light: 0xEFEBFA, dark: 0x221C38)
    // iPad one-page daily report (docs/ui/daily-report-ipad): the work lines' pin colours, in order, and the picked `วันนี้` step
    public static let dailyTasks: [Color] = [Color(hex: 0x1F6FB5), Color(hex: 0x2E9E5B), Color(hex: 0xD9822B),
                                             Color(hex: 0x8E44AD), Color(hex: 0xC0392B)]
    public static let dailyPick = Color(light: 0xA8E6D4, dark: 0x2C6B5A)
    // iPad one-page weekly request (docs/ui/weekly-request-ipad-map): the request lines' colours by order, cycling, and
    // the 5 × 5 risk bands `ต่ำ | ปานกลาง | สูง | สูงมาก` (ink, and the grid cells' fill)
    public static let requestLines: [Color] = [Color(hex: 0x1F6FB5), Color(hex: 0xD9822B), Color(hex: 0x2E9E5B),
                                               Color(hex: 0x8E44AD), Color(hex: 0xC0392B)]
    public static let riskBands: [Color] = [success, warning, danger, Color(hex: 0x8E1B12)]
    public static let riskBandsSoft: [Color] = [Color(light: 0xE3F3EA, dark: 0x16271D), Color(light: 0xFFEBCC, dark: 0x2E2213),
                                                Color(light: 0xF9D3CF, dark: 0x3A1C1A), Color(light: 0xE8A29B, dark: 0x5A2A26)]
    // iPhone PWA documents page (docs/ui/pwa-docs-iphone-v2): papers waiting on an outside office, and the `บริษัท` badge
    public static let outside = planInspect
    public static let outsideSoft = planInspectSoft
    /// Fill of a document chip and of an at-risk deadline, under `warningText`.
    public static let warningTint = Color(light: 0xFFF3E6, dark: 0x2E2213)
    /// The contractor's duty card (`หน้าที่ต้องส่ง`, docs/ui/user-admin-iphone): its fill and border.
    public static let dutyFill = Color(light: 0xFFF8F0, dark: 0x2A1F12)
    public static let dutyLine = Color(light: 0xF3C99B, dark: 0x5A3D1E)
    /// Weekend days, the S-curve's plan line and axis labels, a filter chip with nothing to show.
    public static let inkFaint = Color(light: 0x9FB3CC, dark: 0x5E6E83)
    /// Track of a Gantt row.
    public static let ganttTrack = Color(light: 0xE3E9F1, dark: 0x243142)

    // iPad home v3 (docs/ui/tcroof-home-ipad-v3)
    // iPad PWA home v3, station rows (docs/ui/pwa-solar-survey-ipad-v3 FIX-01)
    /// Fill of a station row's `งานขออนุญาต` block.
    public static let permitFill = Color(light: 0xFAFBFD, dark: 0x161E29)
    /// Border of that block when a permit is overdue, on `photoEmptyFill`.
    public static let permitOverdueLine = Color(light: 0xF3C4BF, dark: 0x5A2B28)

    /// Fill of a feed post's summary strip.
    public static let stripFill = Color(light: 0xF8FAFC, dark: 0x161E29)

    // D1 จัดแผง (docs/ui/survey-d1-layout-iphone)
    /// A panel on the tank plan.
    public static let panelBlue = Color(light: 0x2B4FD8, dark: 0x6C8CFF)

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
    /// The iPad bar's off `‹ หัวข้อแรก`: grey text, its outline at 50 %.
    public static let navOff = Color(light: 0x8E8E93, dark: 0x6E6E73)
    /// Text on `sun` (the example-data chip): navy in both modes, since `sun` stays yellow.
    public static let onSun = Color(hex: 0x16325C)
    /// Empty required photo slot: dashed border #E7B3AE on #FFF8F7.
    public static let photoEmptyBorder = Color(light: 0xE7B3AE, dark: 0x6A3430)
    public static let photoEmptyFill = Color(light: 0xFFF8F7, dark: 0x22161A)
    /// Map placeholder land #E8EEF5.
    public static let mapLand = Color(light: 0xE8EEF5, dark: 0x1A2430)
    // Teams and job statuses (plan calendar, job chips): the same in both modes
    public static let teamPurple = Color(hex: 0x8B3FD9)
    public static let teamBlue = Color(hex: 0x2F6FDB)
    /// Team TCR04 and a job being installed.
    public static let jobOrange = Color(hex: 0xF08A24)
    /// A job at `สนใจ`.
    public static let statusInterested = Color(hex: 0x4DA3E0)
    /// Behind a full-screen picture, and the dim behind the signature pad at 55 %.
    public static let mediaBackdrop = Color(hex: 0x0E1A2B)
    /// Signature pad: near white in both modes, with its baseline and border.
    public static let padFill = Color(hex: 0xFCFDFE)
    public static let padLine = Color(hex: 0x5B6B82)
    // Over the camera (D1 compass): the aim mark, a locked heading and the read-out panel
    public static let hudYellow = Color(hex: 0xFFD43B)
    /// The selected DC input slot (IEC steps 2 and 4), as the dialog's DC box strip: ring, its outline, and the
    /// MPPT column's fill, border and number.
    public static let slotRing = Color(hex: 0xFFD400)
    public static let slotRingLine = Color(hex: 0x8A6D00)
    public static let slotColumnFill = Color(hex: 0xFFF6CC)
    public static let slotColumnLine = Color(hex: 0xE8B21A)
    public static let slotColumnInk = Color(hex: 0x7A5B00)
    /// The IEC sheet preview's `แสดงที่มา` (docs/ui/iec62446-sheet-before): each wizard step's cell tint and inner border.
    public static let sheetSource1Fill = Color(hex: 0xEEF2F7)
    public static let sheetSource1Line = Color(hex: 0x7D8FA8)
    public static let sheetSource2Fill = Color(hex: 0xFFF1DC)
    public static let sheetSource2Line = Color(hex: 0xF08C00)
    public static let sheetSource3Fill = Color(hex: 0xEFE8FB)
    public static let sheetSource3Line = Color(hex: 0x7B5CC4)
    public static let sheetSource4Fill = Color(hex: 0xE4F3E6)
    public static let sheetSource4Line = Color(hex: 0x2E9E5B)
    public static let sheetSource5Fill = Color(hex: 0xE1F2F5)
    public static let sheetSource5Line = Color(hex: 0x1B8A9E)
    public static let hudGreen = Color(hex: 0x2EC27E)
    public static let hudPanel = Color(hex: 0x1F2937, opacity: 0.92)
    // E1 automatic suggestions (docs/ui/survey-e1)
    public static let aiPurple = Color(hex: 0x5B4BC4)
    public static let aiPurpleText = Color(light: 0x6A5AE0, dark: 0xB3A8FF)
    public static let aiPurpleSoft = Color(light: 0xF1EEFF, dark: 0x241F3D)
    public static let aiPurpleFill = Color(light: 0xFBFAFF, dark: 0x1A1730)
    /// B3 selected card fill.
    public static let tealSoft = Color(light: 0xE8F7F3, dark: 0x163530)
    /// Amber text on a white or `warning`-tinted fill.
    public static let warningInk = Color(hex: 0xB26A00)
    /// A missing value on a dark card, among white text.
    public static let dangerOnDark = Color(hex: 0xFF8C80)
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
    /// The ring that lifts a badge off `headerGradient`.
    public static let headerBadgeRing = Color(hex: 0x2A84CF)
    public static let headerGradient = LinearGradient(colors: [Color(hex: 0x1F6FB5), primaryLight], startPoint: .leading, endPoint: .trailing)
    /// #27A99A → #4DB6E0: the survey module's call to action.
    public static let tealGradient = LinearGradient(colors: [teal, tealLight], startPoint: .leading, endPoint: .trailing)
    /// Sign-in page, top to bottom.
    public static let loginGradient = LinearGradient(colors: [Color(hex: 0x0E2344), navy, primary], startPoint: .top, endPoint: .bottom)
    public static let pageGradient = LinearGradient(colors: [Color(light: 0xDCE8F2, dark: 0x0E141C), background], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
    /// The developer key's lock screen and key sheet, 160° (จัดการผู้ใช้และสิทธิ์).
    public static let devLockGradient = LinearGradient(colors: [Color(hex: 0x0E1E38), Color(hex: 0x16325C), Color(hex: 0x1F4F86)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
    /// The Maintainer's pill and card, navy → purple.
    public static let maintainerGradient = LinearGradient(colors: [Color(hex: 0x16325C), Color(hex: 0x6B4FBB)], startPoint: .leading, endPoint: .trailing)
    /// A changed cell's ring and the unsaved bar's dot and save button.
    public static let pendingYellow = Color(hex: 0xFFD400)
    /// The wrong key's line on the dark lock screen.
    public static let keyError = Color(hex: 0xFFB4AB)
    /// The disabled matrix cell's stripes.
    public static let stripeLight = Color(light: 0xF1F4F8, dark: 0x1C2734)
    public static let stripeDark = Color(light: 0xE6ECF3, dark: 0x243142)
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
    /// Narrower padding for short fields in a row (times, quantities, units); still 44 pt tall.
    var dense: Bool
    public init(dense: Bool = false) { self.dense = dense }
    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, dense ? 10 : 14).padding(.vertical, dense ? 12 : 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Theme.navy.opacity(0.45)))
    }
}
#endif
