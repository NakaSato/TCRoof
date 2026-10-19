# Claude Code task: D1 sub-step tab bar as a stepper (iPad)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-d1-stepper-ipad/CLAUDE_CODE_TASK.md`

## Goal
D1's four sub-steps (`ขนาดถัง`, `สิ่งกีดขวาง · เงาบัง`, `จัดแผง`, `ภาพถ่าย`) sit in `TankPageWide.tabBar`: a grey track with four equal segments, where the current one is a raised white segment. Replace it with a **stepper**:
- a white card holding the four steps
- each step with its numbered circle, title and status
- lines connecting the steps
- the current step as a light-blue pill with a blue outline

**Do only this.** Change only the tab bar's look in `tabBar`, `tabSegment` and `stepCircle`.
- `steps` (titles, statuses, done) and the `tab` switching stay as they are.
- The sub-step pages don't change. Sub-step 4's new page is a separate hand-off on branch `design/survey-d1-photo-ipad`.
- The iPhone step line (`TankPageWide+Phone.swift`) doesn't change.

## Files in this folder
| File | Shows |
|---|---|
| `iPadD1.dc.html`, `iPadD1Obs.dc.html`, `iPadD1Layout.dc.html`, `iPadD1Photo.dc.html` | The four sub-step boards, 1366 × 1024. Read them as text. The stepper is the `<nav aria-label="ขั้นย่อยของ D1">` markup. In `renderVals()`, read `tabOn`, `tabOff`, `nOn`, `nOff`, `nDone` and `ln1–ln3`. The rest of each board is unchanged context. |
| `grf.css` | The boards' shared styles |
| `preview.png` | The top of the four boards, one under another |
| `states/01-size.png` | Step 1 current, nothing done |
| `states/02-obstacles.png` | Step 1 done, step 2 current |
| `states/03-layout.png` | Steps 1–2 done, step 3 current |
| `states/04-photos.png` | Steps 1–3 done, step 4 current with "บังคับ 3/5" |
| `screenshots/` | Where your screenshots go |

Values in the boards are examples. Never hardcode them.

## Design
- **Card.**
  - `Theme.surface`, radius 14, a 1 pt `Theme.borderSubtle` border.
  - Padding 6 / 8, with 10 pt between items.
  - It replaces the grey `Self.track` background.
- **Order.** One row: step 1, line, step 2, line, step 3, line, step 4.
- **Steps.**
  - Each step hugs its content and doesn't stretch.
  - The lines take the free width: `frame(maxWidth: .infinity)`, at least 16 pt, 2 pt high, rounded.
- **Each step** is a button with at least 48 pt hit height, padding 0 / 12 (16 trailing when current), radius 12.
  - Circle, 26 pt:
    - done: the existing `d1-step-done` icon in `Theme.success`
    - current: `Theme.primary` fill, number in `Theme.onPrimary`
    - other: `Theme.surface` with a 1 pt `Theme.navy.opacity(0.25)` ring, number in `Theme.inkMuted`
  - Title: 15 bold, one line, no wrap. `Theme.navy` when current, else `Theme.inkMuted`.
  - Status: 12 semibold. `Theme.success` when `statusOK`, else `Theme.pending`. Step 4's red "บังคับ n/m" stays as `steps` already gives it.
  - Current step: `Theme.primary.opacity(0.1)`-like light blue fill (use the closest `Theme` token, such as `Theme.primarySoft` if it exists; otherwise add a token rather than a hex) and an inset 1.5 pt `Theme.primary` stroke. No shadow.
- **Lines.** `Theme.success` when the step before is `done`, else `Theme.hairline`.
- **Undo buttons:** the tab bar shares its row with `undoButtons()` (`↶ เลิกทำ` / `ทำซ้ำ`, TankPageWide+Undo). The stepper takes the remaining width (`frame(maxWidth: .infinity)`, as `feat/tank-photo-details` already does), and the lines shrink first so the undo buttons are never squeezed.
- **Narrow widths** (`narrow`, under 600 pt): keep today's 2 × 2 grid, since a row of four doesn't fit. The stepper is for regular width only.
- **Accessibility:** keep the label "ขั้นที่ n ชื่อ สถานะ" and the `.isSelected` trait on the current step. Hide the lines from VoiceOver.

## Change list
1. `TankPageWide.swift`:
   - `tabBar` becomes the stepper row in regular width, and stays the 2 × 2 grid when `narrow`.
   - `tabSegment` gets its new padding, fill and stroke.
   - `stepCircle` is 26 pt.
   - Add `stepLine(after:)`.
   - Keep each piece a small function or computed property (the Debug SIGSEGV note in CLAUDE.md).
2. If a light-blue selection token is missing from `Theme`, add one (light and dark values) in the design-system files, and mention it in the report.
3. No new DEBUG flag. The existing `-surveyD1 default|tab2|obst|layout` states open steps 1–3. Open step 4 by tapping it, or with the photo branch's flag once that branch is merged.

## Rules
- Theme tokens only, no hex. 44 pt hit areas. `Font.sarabun`.
- Nothing in `steps`, `Tank.*`, `Progress` or the schema changes.

## Check list
- [ ] xcodebuild with your own `-derivedDataPath`
- [ ] iPad simulator, `-screen pwa -surveyDemo YES -surveyDemoSection YES -surveyWideA1 YES -surveyPage tank -surveyD1 default`, then `tab2`, then `layout`, then a tap on step 4. Save the screenshots as `screenshots/01–04` and compare them with `states/`.
- [ ] `-surveyStacked YES` (portrait) and a narrow width still work. Long statuses don't push step 4 off the row (titles keep one line; statuses may shrink with `minimumScaleFactor`).
- [ ] The existing D1 UI tests still pass (`TankUndoUITests`, and any test that taps the tabs by their accessibility labels).

## Merge note
`feat/tank-photo-details` (not merged yet) changes the same `HStack` line (`tabBar.frame(maxWidth: .infinity)`). Keep that modifier when you merge.
`design/survey-d1-photo-ipad` also edits `TankPageWide.swift`, in the `tab == 4` switch and a new `+Photos` file. The two changes touch different parts of the file, so either branch can merge first.
