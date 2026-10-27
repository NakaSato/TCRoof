# Task: iPad · Install tracking: `รายงานประจำวัน` tab, table-only layout (board 27 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/install-tracking-ipad-daily`, then paste `PROMPT.md`, or type
> `Follow docs/ui/install-tracking-ipad-daily/CLAUDE_CODE_TASK.md`

- **Board:** `iPadInstallDaily.dc.html` (1366 × 1024, landscape). Open it in a browser with `grf.css` beside it; the filter is live.
- Thai strings in `backticks` are literal UI labels.
- **Everything in the previews is example data** (การประปาบ้านโป่ง, 24–30/9/2569, crews, percentages, problems). It is listed in `assets/sample-data.json`. Never hard-code it.

## Where this sits

The tab is already built (`InstallTrackingPage+Daily.swift`, from `docs/ui/install-tracking-ipad-v2` §5): KPI row, `ทุกรายงาน` table, and three cards under it. This hand-off is the **difference** between that build and the board now:

| # | Built today | Board now |
|---|---|---|
| A | KPI cells 96 pt tall, label over a 26 pt value over a note | one 52 pt strip: label left and value right on one line, note under them |
| B | three cards under the table (`กำลังคนรายวัน`, `รูปตามงาน MP`, `พรุ่งนี้`) | **gone**: the reports card runs down to the dock |
| C | `สะสม (แผน MP)`: bar + `47% / 52%` | `สะสม · เทียบแผน MP`: `47%` bold + a delta chip (`+3 เร็วกว่า` / `ตามแผน` / `-6 ช้ากว่า`), the bar coloured by ahead/behind with a tick at the plan |
| D | `ลงนาม \| รับทราบ` header | same chips, header `ลงนาม · รับทราบ` (keep the app's `\|` separator if that's the house rule; see open question 3) |

Nothing else changes.

## Previews

| File | State |
|---|---|
| `states/01-default.png` (= `preview.png`) | `ทั้งหมด`, today not sent, one draft |
| `states/02-filter-todo.png` | filter `ต้องทำ` |
| `states/03-filter-problem.png` | filter `มีปัญหา` |
| `states/04-kpi-row.png` | the KPI strip alone, for measuring (2×) |
| `states/05-rows-crop.png` | the rows alone: progress column, chips, buttons (2×) |

## Scope: only this

- **In scope:** the iPad `รายงานประจำวัน` tab of the install tracking page, `InstallTrackingPage+Daily.swift` (change list 1–5).
- **Do not touch:**
  - `InstallDailyData` (its rows, KPIs and filters are right as they are) beyond what item 3 needs
  - the other tabs, the header, the tab bar, the dock
  - the iPhone daily tab (`InstallTrackingPage+PhoneDaily.swift`)
  - the daily report itself (`DailyOnePage`, `DailyReportScreen`) and the PDF
  - stored model fields, `firestore.rules`
- **Out of scope:** the board's `x/4` photo quota (there is no quota anywhere in the data; `InstallDailyData` already says so). Keep the photo count as it is.

**Before editing:** use code-review-graph (per `CLAUDE.md`), else grep. Read:
- `TCRoof/Views/Install/Tracking/InstallTrackingPage+Daily.swift`: `dailyTab`, `dailyKPIs`, `kpis`, `reportsCard`, `Col`, `tableHeader`, `reportRow`, `progressCell`, `dailyCards` and the three cards
- `TCRoof/Views/Install/Tracking/InstallDailyData.swift`: `Row.actual` / `planned`
- `TCRoof/Views/Install/Tracking/InstallTrackingPage+Progress.swift`: `dockClearance`, `fittedHeight`
- `TCRoofUITests/InstallTrackingUITests.swift` (the `รายงานประจำวัน` part: `ต้องทำ` filter, row button, `PDF รวม`)

## Change list

1. **KPI strip (A).** `dailyKPIHeight` → 52. Each cell: first line `label` (13 pt, muted) left and `value` (20 pt bold, its ink) right-aligned in an `HStack` with a `Spacer`; second line `note` (12–13 pt, muted, one line, tail truncation). Same cells, same values, same dividers, padding 14 pt horizontal. Keep `.accessibilityElement(children: .combine)`.
2. **No cards under the table (B).** `dailyTab` becomes KPI strip + `reportsCard`, and the reports card takes the rest of the height down to the dock: `viewport − 14 − dailyKPIHeight − 14 − dockClearance` (min 300), in place of the fixed `reportsHeight`. Remove `dailyCards`, `crewCard`, `photosCard`, `tomorrowCard`, `cardTitle` (and the `site` parameter if nothing else needs it) from this file. Leave `InstallDailyData.photosByTask` / `next` / `nextDay` in place (other code may read them later; note any compiler "unused" result in the report rather than deleting data code).
3. **Progress cell (C).** Header `สะสม · เทียบแผน MP`. With a plan:
   - with an actual: `47%` (15 pt bold, navy) then a small chip with the delta `d = round(actual) − round(planned)`: `d > 0` → `+d เร็วกว่า` (success tone), `d == 0` → `ตามแผน` (success), `d < 0` → `d ช้ากว่า` (danger tone, the sign already in d). Under them a 6 pt bar the column's width: fill = actual, green (`Theme.success`) when d ≥ 0, orange (`Theme.warning` / the warn tone) when d < 0; a 2 × 10 pt navy tick at the planned %.
   - without an actual (today, missing): `—` muted and an idle chip `แผน 52%`, the grey track with the tick.
   - Without a plan: `—` as now.
   - Use the existing `chip(_:_:)` tones; no hex. The VoiceOver label stays `สะสม … แผน …` and adds `เร็วกว่าแผน n` / `ช้ากว่าแผน n`. Put the delta and its tone in a small pure helper (e.g. on `InstallDailyData.Row`) so a unit test can pin it, if the target allows; else keep it in the view.
4. **Row height.** Rows `minHeight` 56 (board 49; the buttons stay ≥ 44 pt), the action column as now. Check the portrait (`compact`) fallback still fits with the taller progress cell.
5. **Test.** Extend the `รายงานประจำวัน` part of `InstallTrackingUITests` (`-installDemo YES -installTab daily`): the tab shows no `กำลังคนรายวัน`, a row's progress reads `เร็วกว่า` or `ช้ากว่า`, and the `ต้องทำ` filter and row button still work.

## Checks when done

- The app builds with `xcodebuild … -derivedDataPath <your scratch>` (in the background); `swift test` in `TCRoofKit` if you touched the package.
- `InstallTrackingUITests` on an iPad simulator.
- Screenshots with `-screen home -homeTab pwa -homeBoard YES -installOpen YES -installDemo YES -installTab daily` (and `-installDailyFilter todo|problem` if it applies on iPad; otherwise tap), saved to `screenshots/` under the names in `states/`, compared with the board.
- The other tabs look unchanged.

## Open questions (answer in your report)

1. The board's `x/4` photo quota: should a daily report have a minimum photo count (per report, per MP task)? Not built.
2. The cards removed in B (crew, photos by MP task, tomorrow): drop them, or move them elsewhere (the overview's site panel already has `labour`)?
3. Separator in chips and headers: the board writes `·`, the app uses `|`. Keep the app's?
4. Should the delta use a margin (e.g. within ±5 % reads `ตามแผน`), as the overview's `กำหนดการ` KPI does?
