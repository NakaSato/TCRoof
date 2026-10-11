# Claude Code task: iPad home navbar (board update 10 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/home-navbar-ipad/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels; keep them exactly.

**Example data:** the unread count `2`, the initials `WC`, and the notification / account contents shown when the panels are open (`assets/sample-data.json`). Bind them to the real notification store and signed-in user.

## Goal

Bring the top bar of the iPad home screen (`iPad · หน้าหลัก TCRoof (เมนู 6 หัวข้อ)`, board `iPadMenu.dc.html`, 1366 × 1024) in line with the board. The bar holds the brand, a search field and a capsule with the bell and the account button.

**This task covers the bar only.** The notification popover and the settings sheet it opens are shown for reference (`states/02`, `03`). If they already exist, wire the buttons to them and leave their layout alone.

**Before reading the source**, use code-review-graph (per `CLAUDE.md`). Look up these symbols:
- the iPad home / menu view, and its header or toolbar
- the search, notifications and settings views it presents
- any existing brand/logo view and the `tc-renewable-icon` asset
- `tests_for` on anything you touch

Then read the source. Don't change the iPhone home bar.

## Files in this folder

| File | Shows |
|---|---|
| `states/01-navbar-default.png` | The bar, @2x, crop |
| `states/01-full-page.png` / `.pdf` | Whole page in landscape; the PDF is **vector**, so measure there |
| `states/02-navbar-bell-open.png` + `02-full-page-notifications.png` | Bell pressed: highlighted button, popover below it |
| `states/03-navbar-account-open.png` + `03-full-page-settings.png` | Account pressed: settings sheet |
| `states/04-navbar-all-read.png` | No unread: badge hidden |
| `boards/iPadMenu.dc.html` | Board source. Find `<header`; the inline CSS gives exact values. The script holds `tNt` / `tSt`, `bellSt`, `badgeSt` and `unread`. |
| `assets/tc-renewable-icon.png` | App icon used in the bar. Use the existing asset if the app already has it. |
| `grf.css` | Shared board CSS |
| `assets/sample-data.json` | Labels and example values |

## Layout (landscape, 1366 wide)

- **Bar:**
  - white, height 91 including padding (**18 top / 32 sides / 16 bottom**)
  - bottom corners radius **22**, 1 pt bottom border `#E6EBF2`, soft shadow `0 2 8 rgba(22,50,92,0.05)`
  - horizontal stack, gap 16
- **Left: brand.**
  - icon 56 × 56, radius 14
  - then two lines in the SF Pro Rounded / system rounded font:
    - `TC` (27 pt heavy, navy) + `Roof` (27 pt bold, primary blue, 5 pt leading gap); line height 28, tracking −0.6
    - a 14 × 2 teal bar + `INTERNAL` (10.5 pt bold, uppercase, tracking 2.4, muted)
  - VoiceOver label `TC Roof Internal`
- **Flexible spacer**, then **search:**
  - fills the rest up to **max 600** wide, 52 high, radius 14
  - fill `#F5F8FB`, 1 pt `#E6EBF2` border, padding 16
  - magnifier (22 pt, `#5B6B82`) + placeholder `ค้นหาเลขที่ ชื่อโครงการ สถานี…` (16 pt muted, truncates)
  - Tap opens the existing job search. Keep today's search behaviour.
- **Right: action capsule.**
  - 56 high, radius 28, fill `#F5F8FB`, inner padding 2, two buttons side by side
  - **Bell:**
    - 52 × 52 circle with the bell icon (24 pt, navy, stroke 2.2)
    - badge: red `#D9453B` capsule, min 20 × 20, 12 pt bold white, 2 pt white ring, at top 4 / right 2
    - shows the unread count; hidden when 0 (`states/04`)
    - **Pressed / panel open** (`states/02`): fill `#E3EEF8` + 2 pt inner primary ring
    - Tap toggles the notifications popover and closes the settings sheet.
  - **Account:**
    - 52 × 52 hit area holding a 42 pt navy circle with the user's initials (15 pt heavy white)
    - Tap opens the settings / account sheet (`states/03`) and closes the notifications popover.
- **Portrait / narrow:** search shrinks first; the brand and capsule keep their size. Below about 900 wide, hide the `INTERNAL` line before truncating the search placeholder.

**VoiceOver:**
- bell: `การแจ้งเตือน`, plus the count, e.g. `การแจ้งเตือน · ใหม่ 2`
- account: `ตั้งค่าและบัญชี`

## Rules

- Thai text exactly as in the previews; all values are example data.
- Colours come from `Theme` / `Home`. If a colour above isn't in `Theme` yet (`#F5F8FB`, `#E6EBF2`), add a named token once; no hex literals in views.
- Touch targets ≥ 44 pt (bell and account are 52).
- **Layout only:** keep how search, notifications and settings work and where their data comes from.
- iPhone home must not change.
- Work on a new branch `feat/ipad-home-navbar`.

## Open questions

Choose the default unless it breaks something, and list your choice in the summary:

1. **Search on the board is a static field.** The default is a tappable field that presents the existing search screen (or `.searchable`). Don't build new search logic.
2. **Initials.** The default is the first letters of the signed-in user's first and last name (`WC`), falling back to the first two letters of the username.

## Done when

- `xcodebuild` builds the app and TCRoofKit, and `swift test` passes.
- On an iPad Pro 13" simulator in landscape, the bar matches `states/01` (measure in `01-full-page.pdf`).
- The bell's highlight and badge match `02` and `04`. Tapping the bell or the account button toggles its panel and closes the other.
- iPad portrait keeps one row without clipping.
- iPhone is unchanged.
- Write a summary of the files changed, the open-question choices and any remaining differences from the board.
