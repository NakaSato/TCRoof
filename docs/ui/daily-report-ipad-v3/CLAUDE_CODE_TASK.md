# Task: iPad · รายงานประจำวัน v3: date calendar, working-time picker, reporter-only sign card (board 21 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/daily-report-ipad-v3`, then paste `PROMPT.md`, or type
> `Follow docs/ui/daily-report-ipad-v3/CLAUDE_CODE_TASK.md`

- **Board:** `iPadDaily.dc.html` (1366 × 1024, landscape, one-page layout).
- Thai strings in `backticks` are literal UI labels.
- **Everything in the previews is example data** (สถานีผลิตน้ำโชคชัย, ก.ค. 2568, names, times). It is listed in `assets/sample-data.json`. Never hard-code it.

## Where this sits

| Hand-off | Branch | Covers | State |
|---|---|---|---|
| v1 | `docs/ui/daily-report-ipad` | the one-page layout | **built** (`DailyOnePage`, `+Plan`, `+Work`) |
| v2 | `design/daily-report-ipad-v2` | the **left card**: plan + task list in one scroll, grouped rows, upload plan, save animation, team header line | its own branch (`feat/daily-report-ipad-v2`) |
| **v3 (this)** | `design/daily-report-ipad-v3` | the **right column only**: date picker, working-time picker, sign card | this task |

v2 and v3 are **separate** and can be built in parallel:
- v2 changes `DailyOnePage+Plan.swift`, `DailyOnePage+Work.swift` and the left card.
- v3 changes only `daySwitcher`, the time sheet and `signCard` in `DailyOnePage.swift`.

The board's left card already shows v2. **Ignore it here.** Don't build v2's items in this branch, and don't change v1's left card.

## Scope: only this

- **In scope:** the iPad one-page daily report (`DailyOnePage`, regular width ≥ 1000 pt): the right column's top bar and the sign card (change list 1–4).
- **Do not touch:**
  - the left card (v1 / v2)
  - the team card
  - the bottom bar
  - the iPhone daily report and `DailyReportScreen`'s non-iPad paths
  - the PDF (`RoutineReportPages.dailyForm`): page 3 keeps both signature boxes
  - `InstallLog` / `RoutineReport` stored fields
  - `firestore.rules`

**Before editing:** use code-review-graph (per `CLAUDE.md`), else grep. Read:
- `DailyOnePage.swift`: `daySwitcher`, `showTime`, `DailyTimeSheet`, `signCard`, `signColumn`, `Actions`
- `DailyReportScreen.swift`: `actions`, `requestSign`, `requestAck`, `changeDay`
- `RoutineReport` (`reportDay(from:by:settings:limit:)`, `isWorkingDay`, `workStart` / `workEnd`, `rainHours`, `labour`)
- `InstallTrackingUITests`, `RoleUITests` (`dailySign`)

Then run `tests_for` on what you touch.

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` | = `states/01` (@2x) |
| `states/01-default.png` | The page; the right column's top bar now has `พ. 2 ก.ค. 2568 ▾` and `เวลาทำงาน ▾`; sign card reporter only |
| `states/02-date-picker.png` | Date button tapped: month calendar popover with report-status dots |
| `states/03-day-before.png` | 1 ก.ค. picked: the page moves to that report day |
| `states/04-working-time.png` | `เวลาทำงาน` tapped: presets and start / end steppers |
| `states/05-working-time-custom.png` | 07:00–17:00 set with the steppers (no preset highlighted) |
| `states/06-signed.png` | Reporter signed: `ส่งรายงาน` enabled |
| `states/07-sign-card.png` · `08-sign-card-signed.png` | The sign card, cropped, idle and signed |
| `iPadDaily.dc.html` + `grf.css` | Design source. Read it as text: search for `dpCells`, `wtRows`, `wtPre`, `ลงนามผู้รายงาน` |
| `assets/sample-data.json` | The example values |
| `screenshots/` | Empty. Put your simulator screenshots here, named like `states/` |

## Change list

Work in order. After each item, build and take its screenshot.

### 1. Date button opens a calendar (`states/02`, `03`)
- Keep `‹` and `›` (they still step one *report day*; `›` stops at today).
- The date between them becomes a button: `<weekday d MMM yyyy> ▾`, 48 pt high, radius 11.
  - It is filled `Theme.primary` with `Theme.onPrimary` text while its popover is open, and white (`Theme.surface`) otherwise.
- **Popover** (anchored under the top bar, the column's width, radius 16, shadow):
  - **Header:** the month (`กรกฎาคม 2568`, Thai month + BE year), then `วันนี้ <d MMM>`, then a 44 pt `✕`.
  - **Weekday row:** `อา จ อ พ พฤ ศ ส`, with Sunday in `Theme.dangerText`.
  - **Day grid:** 7 columns, 44 pt cells, radius 12, with leading blanks before the 1st.
    - Each cell shows the day number and a 6 pt status dot under it:
      - `Theme.success`: sent (`engineerSignedAt` set)
      - `Theme.warningInk`: a draft exists
      - `Theme.danger`: a working day up to today with no report
      - none: a non-working day per `settings`
    - **Selected day:** filled `Theme.primary`, white number and dot.
    - **Today:** 1.5 pt `Theme.primary` ring and bold.
    - **Future days:** `Theme.inkFaint`, disabled.
  - **Legend line:** `ส่งแล้ว · ร่าง · ยังไม่มีรายงาน`, then `เลือกได้ถึงวันนี้` on the right.
- **Month paging:** add `‹ ›` beside the month (the board shows one month). Allow paging back to `job.installStart`'s month.
- **Selecting a day** closes the popover and opens that day's report. Use the same path as `‹ ›` (`DailyReportScreen.changeDay`), so unsaved edits are handled exactly as today.
- Only one popover is open at a time (date or working time).
- **Data:** report status per day comes from the job's `dailyLogs` / reports. Put the per-day status function in `TCRoofCore` (`RoutineReport`), with a test.

### 2. Working-time picker replaces the cycling chip / sheet (`states/04`, `05`)
- The chip reads `เวลาทำงาน ▾` over `HH:mm–HH:mm`, filled `Theme.primary` while open.
- **Popover:**
  - **Title:** `เวลาทำงาน · <weekday d MMM yyyy>` and `✕`.
  - **Three presets:** `08:00–17:00`, `08:00–18:00`, `07:00–16:00`, 44 pt, equal width. The one matching the current times is filled `Theme.primary`.
    - Take the presets from the station's routine settings if it has them. Otherwise use these three, and report which.
  - **Two stepper rows**, 52 pt, on `Theme.segmentTrack`: `เริ่มงาน − 08:00 +` and `เลิกงาน − 18:00 +`.
    - Steps are 1 hour.
    - Start is 06–10, end is 15–20, and end − start ≥ 4.
    - A stepper at its limit is dimmed and does nothing.
  - **Summary line:** `ทำงาน n ชม. ใช้คำนวณ คน·ชม. และชั่วโมงฝนในเวลางาน`, then a `เสร็จ` button (primary, 44 pt).
- **It writes `report.workStart` / `workEnd`** in their existing format (`"08.00"`). The team card's `แรงงานวันนี้` / `ทำงานได้จริง` update live, through the existing `RoutineReport.labour`.
- **Weather:** today `DailyTimeSheet` also holds the 15-hour weather strip. The board's popover has none. Keep it reachable:
  - add a last row `สภาพอากาศ ›` (44 pt) in the popover, showing the rain hours (`ฝน n ชม.`)
  - it opens the existing weather editor (the weather part of `DailyTimeSheet`)
  - keep the small rain glyph on the chip as today
  - report it
- Delete the parts of `DailyTimeSheet` the popover replaces. Do not keep two time editors.

### 3. Sign card: reporter only (`states/07`, `08`, `06`)
The **site engineer of the contractor (ผรม.)** signs this page. The inspector (**TC team**) does not sign here.
- **Header row:**
  - `ลงนามผู้รายงาน` (18 pt bold) with a red `*`
  - right-aligned pill `SITE ENGINEER`: 11.5 pt bold, letter-spaced, `Theme.primary` on `Theme.primarySoft`
  - **Remove** `ลงใน DAILY REPORT หน้า 3` and the two-column layout
- **Signature box:** full card width, **180 pt** high, radius 12.
  - **Idle:**
    - dashed 1.5 pt `Theme.borderOutdoor` border
    - the signature glyph and `แตะเพื่อเซ็น` (15 pt bold, `Theme.primary`), then `เซ็นบนเส้นด้านล่าง` (12 pt, `Theme.inkMuted`)
    - a hairline signing line 40 pt above the bottom, inset 18 pt, with a small `×` at its left end
  - **Signed:**
    - `Theme.successSoft` fill, 1 pt `Theme.success` border
    - the drawn signature (`InstallLog.engineerSignatureTag`) sitting on the line, scaled to fit ~240 × 90
    - a pill `✓ ลงนามแล้ว HH:mm` at the top left
    - a 44 pt clear button at the top right (`actions.clearSignature`, as today)
    - when there is no drawn image, show the name in italics on the line, as today's fallback
- **Name:** a label `ชื่อผู้ลงนาม` (12.5 pt, `Theme.inkMuted`), then the field, centred text, 48 pt, placeholder `ชื่อ Site Engineer ผู้รับเหมา`. It binds `routineSettings.siteEngineer`, as today.
- **Remove the `ผู้ตรวจงาน / INSPECTOR` column** from this page.
  - The inspector's acknowledgement stays where it already works: the home feed's `รับทราบ` (`HomeFeed.acknowledge`) and `-routineDemo ack`'s `InspectorAckSheet`.
  - Keep `requestAck` / `inspectorAckAt` / the PDF's inspector box unchanged.
  - Report any other screen that relied on this column.
- **Permissions:** the tap still goes through `requestSign` and `Permissions.signsDaily`. `RoleUITests`' `dailySign` cases must keep passing.

### 4. DEBUG and docs
- Extend `-routineDailyState` with `datepicker`, `worktime` and `worktimecustom` (07:00–17:00, not saved).
- `-routineDailyState signed` already opens the sign sheet. Add `signedcard` for a signed card with a drawn example signature, not saved.
- Add one sentence to `CLAUDE.md`'s `-routineDaily` item.
- **UI test** in `InstallTrackingUITests` or a new `DailyOnePageUITests` (iPad), with `-screen daily -routineDaily onepage`:
  - open the calendar, pick the previous sent day, and the title changes
  - open the working time, tap `+` on `เลิกงาน`, and the chip reads the new time
  - the sign card has no `ผู้ตรวจงาน`

## Rules
- Colours from `Theme` (`primary`, `onPrimary`, `primarySoft`, `success`, `successSoft`, `warningInk`, `danger`, `dangerText`, `inkMuted`, `inkFaint`, `segmentTrack`, `borderOutdoor`, `surface`). No hex in views, no `Color.white`.
- Hit areas ≥ 44 pt. Buttons use `TCButtonStyle`.
- Split each popover and the sign card into its own view or computed property (Debug type-check limits).
- Popovers: use `.popover` with `presentationCompactAdaptation(.popover)`, or an overlay anchored to the bar. Report which, and make sure it doesn't cover the bottom bar.
- Old job data must still decode. Nothing stored changes shape.

## Check list
- [ ] `swift test` in `TCRoofKit` passes (with the new day-status test).
- [ ] The xcodebuild app build passes, with your own `-derivedDataPath`, run in the background.
- [ ] `RoleUITests` (`dailySign`) and the new UI test pass on an iPad simulator.
- [ ] iPad Pro 13" landscape screenshots `01`–`08` in `screenshots/`, taken with:
  ```
  -screen daily -routineDaily onepage -routineKeyPlan YES -routineDailyState …
  ```
- [ ] The PDF of `-routineDemo pdf` is unchanged.
- [ ] The iPhone daily report is unchanged.

## Open questions (report, don't decide)
1. Inspector acknowledgement now lives only in the home feed (and the ack sheet). Should the daily list (`DailyReportListView`) get a `รับทราบ` action for the TC team too?
2. Should the working-time presets be per station (routine settings) or fixed for the company?
3. Should the calendar show a status for non-working days, for example a day with a report although it's a Sunday?
4. Is a minimum of 4 working hours right for the end − start rule?
