# Component: iPhone docked tab bar (`TCTabBar`)

Board: `iPhone · หน้าหลัก TCRoof (เมนู 6 หัวข้อ)` (`PhoneMenu.dc.html`, the `<nav aria-label="เมนูหลัก">` at the bottom).
Code: `TCRoofKit/Sources/TCRoofUI/Layout.swift` (`TCTabItem`, `TCTabBar`), used by `TCRoof/Views/Home/PhoneTabs.swift`
and shown in `ComponentGallery` (`GalleryLayout.swift`).

**The component already exists and matches this spec.** This sheet is the reference to check against;
the only change in this hand-off is the 4th item (see `CLAUDE_CODE_TASK.md`).

## Items (left → right)
| # | Label | VoiceOver | Glyph | Opens |
|---|---|---|---|---|
| 1 | `หน้าหลัก` | `หน้าหลัก` | SF `house` (board: `icons/tab-home.svg`) | home stack |
| 2 | `สำรวจ` | `สำรวจ · นัดวันนี้ 2` *(example count)* | SF `list.clipboard` (`icons/tab-survey.svg`) + red badge | survey list |
| 3 | `แผนงาน` | `แผนงาน` | SF `calendar` (`icons/tab-plan.svg`) | plan calendar |
| 4 | **`เครื่องมือ`** | **`เครื่องมือวัด`** | **asset `tab-tools`** (`icons/tab-tools.svg`, multimeter) | **`AppModule.tools`** |
| 5 | `ตั้งค่า` | `ตั้งค่า` | SF `gearshape` (`icons/tab-settings.svg`) | settings sheet (action, never selected) |

Items 1–3 and 5 keep their SF Symbols; the SVGs are there only so the glyphs can be compared.

## Metrics (board px = pt)
| Part | Value | Token in `TCTabBar` |
|---|---|---|
| Bar | white, top line 1 pt, padding top 4, sides 6; white runs under the home indicator (board: bottom 22) | `Theme.surface`, `Theme.borderOutdoor` |
| Item | equal width, min height **48** (hit area ≥ 44), glyph slot over label, gap 2 | `.frame(maxWidth: .infinity, minHeight: 48)` |
| Glyph slot | 52 × 28, capsule radius 14; selected fill `#E3EEF8` | `Theme.primarySoft` |
| Glyph | 22 pt, stroke 2 (selected 2.3 on the board), round caps/joins | asset 22 × 22 template; SF 18 pt |
| Label | 10.5 / 13, Sarabun 600; selected 800 | `.sarabun(10.5, .semibold / .heavy)` |
| Colour | selected `#1F6FB5`, others `#3E4C60` | `Theme.primary`, `Theme.inkTab` |
| Badge | 16 high, min 16 wide, radius 8, `#D9453B`, white 10 pt heavy, 2 pt white ring, top −4 / right 4 of the slot | `Theme.danger` |

Hex values are the board's; in Swift use the `Theme` tokens in the right column, never hex literals.

## States
`states/01-selected-home.png` … `05-selected-settings.png` (390 pt wide, @2x) show each tab selected.
Settings is an action tab in the app (opens a sheet), so state 05 is reference only.
