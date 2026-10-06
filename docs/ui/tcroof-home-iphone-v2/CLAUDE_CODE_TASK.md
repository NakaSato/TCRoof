# Claude Code task: TCRoof home on iPhone, design update v2 (outdoor contrast, minimal header, bottom tab bar)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/tcroof-home-iphone-v2/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels. Names, numbers, times and job data in the previews are **example data**.

## Context
The first iPhone home hand-off (`docs/ui/tcroof-home-iphone/`) is already built. See commit `c677022`:
- `TCRoof/Views/Home/PhoneHome.swift`
- `HomeParts.swift`: `HomeBrandHeader`, `ModuleRow`, `AppointmentHero`, `ProgressRing`
- `PhoneNotifications.swift`, `PhoneSettings.swift`, `HomeGreeting.swift`

The board `iPhone · หน้าหลัก TCRoof (เมนู 6 หัวข้อ)` has changed since then. **This task applies only the differences listed below.**
- Everything not listed stays as built: the greeting logic, pager, notifications behaviour, settings content, call sheet and module destinations.
- `docs/ui/tcroof-home-iphone/CLAUDE_CODE_TASK.md` remains the reference for those parts.

The design goal of v2: **readable outdoors in direct sun.** Field engineers use the phone on rooftops, so it needs higher contrast, solid fills instead of gradients, darker secondary text and stronger borders.

**Compact width only.** `HomeBrandHeader` and `AppointmentHero` are shared with the iPad home through `HomeSize` (`size: .phone` / `.pad`). Every change here must apply only to `.phone`. The iPad home must look exactly as before.

Use code-review-graph first (per `CLAUDE.md`):
- callers of `HomeBrandHeader`, `AppointmentHero`, `ModuleRow`, `HomeSize`, `PhoneHome`, `Theme.heroGradient`
- `tests_for` on anything you touch

Then read the source.

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` = `states/01-home.png` | Home, appointment 1/2, @2x (780 × 1688) |
| `states/02-next-appointment.png` | Pager on appointment 2/2 |
| `states/01a-header-crop.png`, `01b-tabbar-crop.png` | Header and tab bar close-ups (@2x) |
| `states/03-notifications.png`, `04-notifications-todo.png` | Full-screen notifications (only the colour changes below apply) |
| `states/05-settings.png`, `06-logout-confirm.png`, `07-call-sheet.png` | Unchanged behaviour; for colour reference |
| `states/01-home.pdf`, `03-notifications.pdf` | **Vector** 390 × 844 renders. Measure here. |
| `PhoneMenu.dc.html` | Design source. Read as text; every style value is inline. `renderVals()` holds the state logic and sample data. |
| `preview.html` + `grf.css` | Static render of the home state |
| `icons/tab-*.svg` | New tab bar glyphs (see `icons/README.md`) |
| `icons/*.svg` (others), `assets/` | Same as v1, copied here so the folder is complete |

## Changes

### 1. Brand header (compact): minimal
Compare `states/01a-header-crop.png` with v1's header.
- **The greeting is removed from the compact header.** There is no text in the header at all.
  - Keep `HomeGreeting` and its Settings toggle for the iPad; just don't show it on `.phone`.
  - If the toggle only affects the phone, hide it on compact too.
- **Bar**:
  - white, **no border**
  - bottom corners **2** (nearly square)
  - shadow `0 2 10 rgba(22,50,92,0.06)`
  - padding 0 / 16 / 12 under the status bar
- **Row**: the logo at the leading edge and the bell + avatar capsule at the trailing edge, with a spacer between.
- **Logo**: `AppLogo` **44 × 44**, radius **12**, no ring or border.
- **Bell + avatar capsule**, replacing the two separate circles:
  - height 48, radius 24, fill `#F5F8FB` (`Theme.phonePage`), **no border, no divider**, inner padding 0 / 2
  - **Bell**: 44 × 44 tap target, no fill, glyph 22 pt, stroke 2.2, navy.
    - Unread badge: top 2, right 0; min 20 × 20; red `#D9453B` with a 2 pt white ring.
    - When the notifications are open, the bell gets fill `#E3EEF8` and a 2 pt inset `#1F6FB5` ring (board `bellSt`).
  - **Avatar**: 44 × 44 tap target holding a **36 pt navy (`#16325C`) circle** with white initials, 13.5 pt, weight 800. It opens Settings, as now.

### 2. `นัดวันนี้` hero card (compact)
- Background: **solid `#0E2747`** instead of `Theme.heroGradient`. Add `Theme.heroSolid` (light `#0E2747`; dark: keep the current dark look).
- Shadow `0 8 18 rgba(14,39,71,0.28)`.
- Secondary text opacity:
  - top row (`นัดวันนี้`, the date) and `นัดสำรวจ · อีก n นาที`: **95 %** (was 85 %)
  - place line: **92 %** (was 80 %)
- **Progress ring**: track white **28 %** (was 22 %), progress **`#9BE26E`** (was `#8FD16A`), stroke 5. Add `Theme.ringOutdoor` or update `ringDone` for the phone card only.
- **Primary button** (`ทำต่อ … ›` / `เริ่มสำรวจ A1 ›`):
  - white
  - text **`#0E2747`, weight 800** (was navy bold)
  - height 46, radius 12
- **Navigate / call buttons**:
  - 44 × 44, radius 12
  - fill white **20 %** (was 16 %) plus a **1 pt white 35 % border**
  - glyph white, stroke 2

### 3. Module rows (compact)
- Row border **`#C9D3E0`** (was `#DDE4ED`), shadow `0 2 6 rgba(22,50,92,0.05)`.
- Subtitle colour **`#44546A`** (was `#5B6B82`).
- Chevron **`#7A8BA3`** (was `#AAB6C5`).
- Everything else as v1: icon tile 42, title 15, subtitle 12, chips, 6 rows filling the remaining height.
- The rows now end **above the tab bar**: page padding is 12 / 16 / **86** bottom (bar height ≈ 75 incl. the home-indicator inset).

### 4. New: bottom tab bar (compact), minimal and as short as possible
See `states/01b-tabbar-crop.png`.
- **Docked**: full width, flush with the bottom edge, extending under the home indicator.
- **Bar**:
  - solid white
  - **1 pt top border `#C9D3E0`**, no shadow, no corner radius
  - padding 4 top / 6 sides / bottom = the safe-area inset (22 on the board)
  - total ≈ 75 pt on a 390 × 844 phone
- **Five tabs**, equal width, each **min 48 pt** tall, the whole column tappable. A glyph **22 pt** sits in a 52 × 28 slot over a label **10.5 pt** (line height 13), gap 2.
  1. `หน้าหลัก` (`house`): home. Selected on this screen.
  2. `สำรวจ` (`list.clipboard`): survey list (`AppModule.survey` destination). Badge with today's survey appointment count; hide it when 0.
  3. `แผนงาน` (`calendar`): plan calendar (`AppModule.plan` destination).
  4. `ติดตั้ง` (`hammer`, or the SVG): install log (`AppModule.install` destination).
  5. `ตั้งค่า` (`gearshape`): Settings.
- **Selected tab**: a **52 × 28 capsule, radius 14, fill `#E3EEF8`** behind the glyph only. Glyph stroke 2.3; glyph and label `#1F6FB5`; label weight 800.
- **Unselected tab**: glyph stroke 2, glyph and label `#3E4C60`, label weight 600, no capsule.
- **Badge**:
  - on the glyph capsule's top-trailing corner (top −4, trailing 4)
  - min 16 × 16, radius 8, `#D9453B` (`Theme.danger`)
  - text 10 pt bold white
  - 2 pt white ring
- Accessibility labels:
  - `เมนูหลัก` on the bar
  - each tab its label; the badge tab reads `สำรวจ · นัดวันนี้ 2`
  - the selected tab has the selected trait
- Build it as a reusable component in `TCRoofUI`, for example `TCTabBar(items:selection:)` in `Layout.swift`. Add it to `ComponentGallery` section 1.
- **The same bar is on the survey list board** (`PhoneSurveyList`, with `สำรวจ` selected). Its FAB sits 16 pt above the bar: bottom 92 on the board.
- **Navigation model**: see open question 1. Default, unless the code suggests a better fit: the tabs switch between root `NavigationStack`s, using `TabView` with the system tab bar hidden and this bar as a `safeAreaInset(edge: .bottom)`.
  - The bar is visible on the tab root screens only. Hide it when a pushed screen (for example a survey page with its own bottom bar) is on top.
  - `ตั้งค่า` presents the existing Settings sheet instead of switching tab. The avatar does the same.
  - You may use the system `TabView` tab bar instead if it can be styled to match closely (selected capsule, colours, badge). Say which you chose.

### 5. Notifications and settings colours (compact)
Same contrast pass as the home:
- muted text `#5B6B82` → `#44546A`
- secondary icon/label grey `#56657A` → `#3E4C60`
- chevrons `#AAB6C5` → `#7A8BA3`
- 1 pt card borders `#DDE4ED` → `#C9D3E0`

Layout and behaviour are unchanged.

## Tokens
Add these to `TCRoofUI/Theme.swift` (light values; give each a sensible dark value) and use them, never hex in views:

| Token | Light | Use |
|---|---|---|
| `heroSolid` | `#0E2747` | hero card fill (the board keeps this exact colour) |
| `ringOutdoor` | `#9BE26E` | hero ring progress |
| `inkStrong` | `#44546A` | outdoor secondary text (compact home, notifications, settings) |
| `inkTab` | `#3E4C60` | unselected tab, secondary labels |
| `borderOutdoor` | `#C9D3E0` | tab bar top border, module row and card borders |
| `chevronStrong` | `#7A8BA3` | chevrons (equals `muted`; reuse it if you prefer) |

Existing tokens stay; the iPad keeps using `inkMuted`, `borderSubtle`, `chevron` and `heroGradient`.

## Rules
- Compact width only; iPad unchanged. Thai UI text exactly as in the previews. Touch targets ≥ 44 pt.
- No model, sync or greeting-logic changes.
- Keep `-homeNotifications YES` working.
- Add a DEBUG launch argument `-homeTab survey|plan|install` that opens with that tab selected, for checks.

## Acceptance
1. An iPhone 15/16 simulator (390 × 844) matches `states/01-home.png`: minimal header (logo + capsule, no greeting), solid hero card, six rows and the docked tab bar on one screen with no scrolling, with the last row clear of the bar.
2. The tab bar switches tabs and also appears on the survey list root. The `สำรวจ` badge equals today's survey appointments. `ตั้งค่า` opens Settings. The bar hides on pushed screens.
3. Header capsule: the bell opens notifications and shows the open state; the avatar opens Settings.
4. Notifications and settings show the darker colours (states 04–06).
5. The iPad home is pixel-identical to before. Check `PadHome` with a screenshot before and after.
6. `swift build`, `swift test` and the `CLAUDE.md` xcodebuild (with your own `-derivedDataPath`) pass without new warnings.
7. Finish with a summary: the files changed, the new tokens and component, the navigation model you chose for the tab bar, and any remaining differences from the board.

## Open questions (report back; don't block on them)
1. **Tab bar vs module rows.** `สำรวจ`, `แผนงาน` and `ติดตั้ง` duplicate three module rows. Is the bar meant as app-wide root navigation, which needs the tab model above, or only as shortcuts on the home screen? Implement the default and say which you chose.
2. **`ตั้งค่า` tab.** Should it be a real tab (a Settings root screen) instead of opening the sheet?
3. **Dark mode.** The board is light only. Propose dark values for the new tokens.
4. **AI greeting on iPhone.** The board removed it from the compact header. Should the Foundation Models greeting move somewhere else on the phone (for example the hero card when there is no appointment), or stay iPad-only?
