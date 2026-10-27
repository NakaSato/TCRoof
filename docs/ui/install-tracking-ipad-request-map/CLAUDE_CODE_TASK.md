# Task: iPad · Install tracking: the `คำขอรายสัปดาห์` tab becomes the one-page key-plan request (board 28 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/install-tracking-ipad-request-map`, then paste `PROMPT.md`, or type
> `Follow docs/ui/install-tracking-ipad-request-map/CLAUDE_CODE_TASK.md`

- **Board:** `iPadWeeklyMap.dc.html` (1366 × 1024, landscape). Open it in a browser with `grf.css` beside it. The key plan image is `/_blob/…` on the canvas; locally use `assets/keyplan-example.jpg`.
- Thai strings in `backticks` are literal UI labels.
- **Everything in the previews is example data** (สถานีผลิตน้ำโชคชัย, สัปดาห์ที่ 32, 4–10 ส.ค. 2568, lines, crew, names). It is listed in `assets/sample-data.json`. Never hard-code it.

## Where this sits

Both halves are already built:

| Built | Where | What |
|---|---|---|
| the one-page request | `WeeklyRequestOnePage` (+`Lines`, `Plan`, `Right`, `Risk`), hosted by `WeeklyRequestScreen.onePage`; `docs/ui/weekly-request-ipad-map` | key plan with pins, day chips per line, team / tools, signature, bottom bar; opened as its own pushed screen |
| the install page's tab | `InstallTrackingPage+Request.swift` / `+RequestPanel.swift`; `docs/ui/install-tracking-ipad-weekly-request` | the R1 **form** (crew × day, tools, work × day, risks) with an approval panel |

**The board puts the one-page request inside the install tracking page**, under its tab bar, with `คำขอรายสัปดาห์` selected (`states/04`). That is the whole change: on iPad regular width the tab shows the one-page request instead of the R1 form. The one-page's own content, logic and states don't change.

## Previews

| File | State |
|---|---|
| `states/01-default.png` (= `preview.png`) | the tab, line 1 selected, unsigned (`ส่งขออนุมัติ` off) |
| `states/02-line2-selected.png` | pin / line 2 selected |
| `states/03-signed-ready.png` | signed: bottom bar `ครบทุกส่วนแล้ว` and `ส่งขออนุมัติ` on |
| `states/04-header-tabs.png` | the header and the tab bar, `คำขอรายสัปดาห์` selected |

## Scope: only this

- **In scope:** the iPad install tracking page (`InstallTrackingPage.swift` `padBody`, `InstallTrackingPage+Request.swift`) and the small changes `WeeklyRequestOnePage` / `WeeklyRequestScreen` need to be hosted there (change list 1–5).
- **Do not touch:**
  - the one-page request's content: the plan, pins, lines, day chips, risk sheet, team card, signature card, bottom bar's states (`WeeklyRequestOnePage+*.swift` beyond item 1)
  - saving, signing, the PDF, sending, approving (`WeeklyRequestStore`, `RequestSignSheet`, `RequestPDFSheet`, `RoutineReport.WeeklyRequest`)
  - the R1 form (`requestTab`, `+RequestPanel`): keep it for compact width (< 1000 pt); don't delete it
  - the iPhone (`phoneRequestTab`), the other tabs, the dock's own code
  - stored model fields, `firestore.rules`

**Before editing:** use code-review-graph (per `CLAUDE.md`), else grep. Read:
- `TCRoof/Views/Install/Tracking/InstallTrackingPage.swift`: `padBody` (the `.request` branch, `.task(id: requestWeek)`), `Debug` (`-installTab`, `-installRequestWeek`, `-installRequestState`), `destination(.request)`
- `TCRoof/Views/Install/Tracking/InstallTrackingPage+Request.swift`: `requestTab`, `loadRequest`, `reqChange`
- `TCRoof/Views/Job/RoutineReports/WeeklyRequestScreen.swift`: `onePage`, `forceOnePage`, `prepare`, `weekChoices`, `sendFromPage`, the demo (`-requestDemo` / `-installDemo`)
- `TCRoof/Views/Job/RoutineReports/WeeklyRequestOnePage.swift`: `body`, `header`, `bottomBar`, its 63 pt margins and `GeometryReader` sizing
- `TCRoof/Views/Home/PadTabs.swift`: `padDock`
- `TCRoofUITests/WeeklyRequestOnePageUITests.swift`, `InstallTrackingUITests.swift`

## Change list

1. **Hostable one-page.** Give `WeeklyRequestOnePage` an `embedded: Bool = false`. When true: no `header` (the install page's header and tab bar stand in for it), no `.toolbar(.hidden…)`, no page gradient background (the install page's `Theme.phonePage` shows), and 24 pt side margins in place of 63, so it lines up with the other tabs. The left / right columns, their sizes (right 384 pt) and the bottom bar stay. Nothing else in the view changes.
2. **One path for the request.** Host it through `WeeklyRequestScreen` so saving, signing, the PDF, sending and the week list stay in one place: add `embedded` (and the week to open) to `WeeklyRequestScreen`, which then always takes the one-page layout and passes `embedded` on. Don't copy its logic into `InstallTrackingPage`.
3. **The tab.** In `padBody`, when `tab == .request` and the width is ≥ 1000 pt, show `WeeklyRequestScreen(job:, week:, embedded: true)` (its week from the page's `requestWeek`); below 1000 pt keep `requestTab()` as now. The `‹ / ›` week buttons and the week menu move the request's own week; keep the page's `requestWeek` in step if other code reads it.
4. **Bottom bar and dock.** The board shows the request's bottom bar (`บันทึกร่างตอนนี้ | ดูตัวอย่างคำขอ | ส่งขออนุมัติ`) at the bottom of the screen and no dock. Hide the dock on this tab only (as a pushed screen covers it), so the bar sits where the board puts it; every other tab keeps the dock. If the dock can't be hidden per tab without changing `PadTabs`, put the bar directly above the dock instead and say so in the report.
5. **DEBUG + test.** `-installTab request` with `-installDemo YES` (landscape, `-homeBoard YES`) opens the board's example in memory, nothing saved; `-requestState …` keeps working inside the tab. Add to `InstallTrackingUITests`: open the `คำขอรายสัปดาห์` tab → the key plan (`KEY PLAN`) and `ส่งขออนุมัติ` are there and the tab bar stays; tap pin 2 → its line is selected; `ภาพรวม` returns to the overview. `WeeklyRequestOnePageUITests` must still pass on the standalone screen.

## Checks when done

- The app builds with `xcodebuild … -derivedDataPath <your scratch>` (in the background).
- `InstallTrackingUITests` and `WeeklyRequestOnePageUITests` on an iPad simulator.
- Screenshots with `-screen home -homeTab pwa -homeBoard YES -installOpen YES -installDemo YES -installTab request` (and `-requestState signed`), saved to `screenshots/` under the names in `states/`, compared with the board.
- The standalone `-screen request -routineRequest onepage` looks unchanged; the portrait iPad still shows the R1 form.

## Open questions (answer in your report)

1. Header: the board's header reads the request's title (`คำขอปฏิบัติงานสัปดาห์ที่ 32 (4 – 10 ส.ค. 2568)`, station under it) because it was the standalone page. This brief keeps the install page's header (the station, as on every tab); the week is in the right column. Should the tab change the header title instead?
2. Dock: hidden on this tab (board), or the bar above the dock?
3. The R1 form tab (`+Request`, `+RequestPanel`): keep it for portrait, or retire it once the one-page also fits portrait?
4. The approval (`บันทึกอนุมัติแล้ว`, the team's) lives on the R1 form's panel; on the one-page it's in `WeeklyRequestScreen`'s flow. Is that reachable enough from the tab?
