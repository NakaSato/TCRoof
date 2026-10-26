# Claude Code task: iPad `คำขอรายสัปดาห์`, one page on the station's key plan

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/weekly-request-ipad-map-v2` and type
> `Follow docs/ui/weekly-request-ipad-map/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels: keep them exactly.

**Do only what this task lists.** Do not refactor, rename or restyle anything outside the change list in §5. Do not
touch:

- the iPhone (`WeeklyRequestScreen` keeps its current form on compact width; `InstallTrackingPage+Phone*.swift`)
- the daily report (`DailyOnePage*`, `DailyReportScreen`): reuse its pieces, don't change them
- the R1 PDF layout (`RoutineReportPages.request`), except the working-time value of §5 item 1
- Firestore rules, `CloudSync`, `WeeklyRequest.trusting`, and the send / send back / approve / reopen rules
- the other tabs of the install tracking page

**Example data.** The board's station, weeks, MP lines, crew, tools, days, risk scores, names and times are examples
(`assets/sample-data.json`; the key plan picture is `assets/keyplan-example.jpg`). The app reads:

- the request (`RoutineReport.WeeklyRequest`, `job.weeklyRequest(for:)`, `WeeklyRequestStore`, `requestDraft`)
- the MP plan's tasks for the week and their locations (`PlanLine.task`, `.location`, `.days`)
- the station's routine settings (working weekdays, roles, tools, `keyPoints`, work hours)
- the station's key plan (`job.reportKeyPlan()`, `KeyPlanViews.swift`: the uploaded plan, else the survey's A2 picture)

Never hard-code a board value.

## 1. Context

- `WeeklyRequestScreen` (`TCRoof/Views/Job/RoutineReports/WeeklyRequestScreen.swift`) is R1, next week's request: a
  plain form of cards. It is pushed from the job's `RoutineReportCard`, the home's notification link and the install
  page's `Route.request`. On iPad the install tracking page also has an in-page `คำขอรายสัปดาห์` tab
  (`Tab.request`, `InstallTrackingPage+Request.swift`, `+RequestPanel.swift`, docs/ui/install-tracking-ipad-weekly-request).
- The daily report already has an iPad one-page layout: `DailyReportScreen` shows `DailyOnePage` at width ≥ 1000
  (docs/ui/daily-report-ipad, -v2, -v3, -v4): the key plan with pins on the left over the lines grouped by location,
  the day / team / signature on the right, and a bottom bar.
- The board **`iPad · คำขอรายสัปดาห์`** (`iPadWeeklyMap.dc.html`, 1366 × 1024) gives R1 the same one-page layout:
  the week's lines as pins on the key plan, each line's days as six day chips, the crew and tools as the daily report's
  dropdown rows, a 5 × 5 risk assessment per hazard, the engineer's signature in the page, and the bottom bar
  `บันทึกร่างตอนนี้ | ดูตัวอย่างคำขอ | ส่งขออนุมัติ`. This task builds that page.

## 2. Before you start

Start with code-review-graph, as `CLAUDE.md` says:

- `WeeklyRequestScreen` (`load`, `save`, `bottomBar`, `exportPDF`) and `WeeklyRequestStore`
- `RoutineReport.WeeklyRequest` (`Status`, `send`, `sendBack`, `approve`, `reopen`, `isEditable(external:)`,
  `workingDays`), `PlanLine`, `Risk`, `RiskLevel`, `Count`, `requestDraft`, `commonRisks`
- `DailyReportScreen` (how it picks `DailyOnePage` at ≥ 1000 pt and `forceOnePage`), `DailyOnePage`,
  `DailyOnePage+Plan` (`planCanvas`, `markers`, `pin`, `ghostPin`, the full-screen plan), `DailyOnePage+Right`
  (the team card's dropdown rows, `DailyWorkTimePopover`, the sign card), `KeyPlanViews.swift`
- `InstallTrackingPage` (`items`, `Tab.request`, `Route.request`, the `-installTab` flag)
- `RoutineReportPages.request` (only where it prints the working time)
- `tests_for` on anything you touch, plus `WeeklyRequestTests`, `WeeklyRequestDaysTests`, `DailyOnePageUITests`

Then read the source and open `iPadWeeklyMap.dc.html` as text: its constants (`MPW`, `RISKS`, `LV`, `lvOf`) are at the
top of the script, the logic is `renderVals()`.

## 3. Files in this folder

| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `iPadWeeklyMap.dc.html`, `grf.css` | The board |
| `preview.png` = `states/01-draft.png` | Week 32, a draft: three lines, line 1 selected, nothing signed. @2x (2732 × 2048) |
| `states/02-line2-selected.png` | Line 2 selected (from its card or its pin): its card outlined, its zone and pin enlarged |
| `states/03-week-picker.png` | `สัปดาห์ที่ 32 ▾`: the week list with each week's state chip |
| `states/04-work-time.png` | `เวลาทำงาน ▾`: presets, start / end steppers, `ทำงาน n ชม. ต่อวัน` |
| `states/05-tools-dropdown.png` | The team card's `เครื่องมือ` tab with a count dropdown open (`ลบออก`, 1–12) |
| `states/06-risk-sheet.png` | A hazard chip opened the risk sheet: 5 × 5 matrix, the level, the controls |
| `states/07-line-no-days.png` | Line 2 with no day: `0 วัน`, the footer `ยังส่งไม่ได้: งาน 2 ยังไม่เลือกวัน` |
| `states/08-signed-ready.png` | Signed: footer `ครบทุกส่วนแล้ว พร้อมส่งขออนุมัติ`, `ส่งขออนุมัติ` enabled |
| `states/09-sent.png` | Sent: read only, `ส่งขออนุมัติแล้ว รอทีมภายในตรวจ …`, `ถอนกลับมาแก้` |
| `states/10-approved.png` | Week 31, approved: read only, the green `อนุมัติแล้ว` |
| `states/11-empty-week.png` | Week 33 with no line: `ยังไม่มีงานในคำขอสัปดาห์นี้` and `เพิ่มงานทั้งหมดตามแผน MP` |
| `states/12-map-full.png` | The key plan full screen with its title line |
| `states/13-pdf-preview.png` | `ดูตัวอย่างคำขอ`: the R1 form filled from the page (the existing PDF, unchanged) |
| `assets/sample-data.json` | The board's example values, the risk matrix and the hazard list |
| `assets/keyplan-example.jpg` | The board's example station picture |
| `screenshots/` | Put your simulator screenshots here, named like `states/` |

## 4. The page

A pushed screen, the page does not scroll; its cards do. A header bar, a left column (fills) and a right column
(about 384 pt), then a bottom bar. Follow `DailyOnePage`'s structure and sizes wherever the two boards match.

### 4.1 Header bar

The back button (44 pt), the title `คำขอปฏิบัติงานสัปดาห์ที่ n (<dates>)` and the station line under it.

### 4.2 Left: the key plan

- The station's key plan, drawn as `DailyOnePage`'s plan: `KEY PLAN` and `คำขอ หน้า 1` top left, `อัปโหลดผัง` and the
  full-screen button top right, the legend at the bottom (`ทำสัปดาห์นี้`, `เสร็จแล้ว`, `ยังไม่เริ่ม`,
  `+ คืองานในแผน MP ที่ยังไม่ได้ขอ`).
- **Places:** each location of `settings.keyPoints` gets its label. A place with a request line takes that line's
  colour (`sample-data.json` `lineColours`, cycling by line order); the selected line's place is drawn stronger.
  The board draws rectangles for the places; the app stores points only, so draw the daily report's labels and
  markers, not rectangles (§7 Q2).
- **Pins:** one numbered pin per request line at its place, offset when several share a place. The selected one is
  40 pt with a ring and `<place> (<days>)`; the others 32 pt, dimmed, with `n วัน`. A tap selects the line.
- **`+` ghosts:** one per MP task planned in that week at a place that is not in the request yet (draft only). A tap
  adds it as a line with the plan's days and selects it.
- **Full screen** (state 12): `ผังสถานีและงานสัปดาห์นี้` with the week and the hint, as the daily report's.
- **No key plan:** the daily report's fallback text, the places as a list.

### 4.3 Left: the lines, grouped by place

Under the plan, scrolling: a group header per place (`<place>`, `n งาน รวม n วัน`), then one card per line:

- the number in the line's colour, the task's name, `MP <code> แผนทำวัน <days>`;
- six day chips `จ 4 … ส 9` (the week's working days from settings, with the date): filled in the line's colour
  when picked; a tap toggles it (draft only). They write `PlanLine.days`;
- on the right `n วัน` and a tag: `ตาม MP` (the days equal the plan's) or `แก้วัน` (orange);
- the selected card only: the line's hazards as chips (§4.5), `ยังไม่ประเมิน` dashed orange until assessed, and
  `เอาออก` (draft only), which removes the line with a toast.
- **No line** (state 11): `ยังไม่มีงานในคำขอสัปดาห์นี้`, `แผน MP มี n งาน …`, and `เพิ่มงานทั้งหมดตามแผน MP`, which
  adds every MP line of the week with its days.

### 4.4 Right column

- **Week row:** `‹`, `สัปดาห์ที่ n ▾` (opens the week list, state 03: next week and the two before, each with
  `อนุมัติแล้ว` / `ส่งแล้ว รออนุมัติ` / `ร่าง` / `ยังไม่เริ่ม`), `›`, and `เวลาทำงาน ▾ hh:mm–hh:mm`, which opens
  `DailyWorkTimePopover` (state 04) and writes the request's working time (§5 item 1).
- **`ทีมงานสัปดาห์นี้`**: `n คน เครื่องมือ n รายการ` on the right; two tiles, `แรงงานทั้งสัปดาห์` (`n คน·วัน`,
  `n คน × n วัน`) and `วันที่มีงาน` (`n วัน`, the days); a segment `คน n | เครื่องมือ n`; the rows as the daily
  report's team card (name, a count dropdown 1–12 with `ลบออก`, one open at a time) and `+ เพิ่มตำแหน่ง ▾` /
  `+ เพิ่มเครื่องมือ ▾` from `settings.roles` / `settings.tools`. They write `crew` and `tools`. `crewOff` is not shown
  and is kept as it is.
- **`ลงนามผู้รายงาน *`** with the chip `SITE ENGINEER`: the daily report's sign card (tap to sign, the drawn
  signature, `เซ็นแล้ว hh:mm`, clear), and `ชื่อผู้ลงนาม` under it (the engineer's name from settings).

### 4.5 Risks

- Each line's hazards come from a hazard list (§5 item 2) by its rules (a roof or tank place, cable / cabinet /
  inverter work, modules or trays on a roof). A hazard is assessed once per week (`WeeklyRequest.risks`, keyed by its
  name) and shows on every line it applies to, coloured by its band: `ต่ำ` green, `ปานกลาง` orange, `สูง` red,
  `สูงมาก` dark red.
- A tap on a chip (draft only) opens the risk sheet (state 06): the hazard and the line, a 5 × 5 grid (severity rows
  `5 เสียชีวิต` … `1 เล็กน้อย`, likelihood columns `1 แทบไม่เกิด` … `5 เกิดแน่นอน`, each cell its score on its band's
  colour, the picked one outlined), `ระดับความเสี่ยง` with `โอกาส L × ความรุนแรง S = n` and the band, the band key,
  and the controls under `มาตรการควบคุม (Hierarchy of Controls)`. Buttons: `ไม่ใช้กับงานนี้` (removes the
  assessment, only when one exists), `ยกเลิก`, `บันทึกระดับ`.
- A new draft starts with every hazard that applies to its lines assessed at the list's default L and S.

### 4.6 Bottom bar

- **Left:** a status icon and line:
  - draft, blocked: `ยังส่งไม่ได้: <first reason>`, in this order: `ยังไม่มีงาน แตะ + บนผังเพื่อเพิ่มงานตามแผน MP`,
    `งาน n ยังไม่เลือกวัน`, `ยังไม่มีทีมงาน`, `งาน n ยังไม่ประเมินความเสี่ยง`, `ผู้รายงานยังไม่ได้เซ็น`;
  - draft, ready: `ครบทุกส่วนแล้ว พร้อมส่งขออนุมัติ` (green);
  - sent: `ส่งขออนุมัติแล้ว รอทีมภายในตรวจ แก้ไขได้เมื่อถูกส่งกลับ`;
  - approved: `อนุมัติแล้ว <date> โดย <name> (ดูอย่างเดียว)` (green).
- **Buttons:** `บันทึกร่างตอนนี้` (saves, the daily report's saving / saved states), `ดูตัวอย่างคำขอ` with
  `PDF 1 หน้า` above it (opens the existing `RequestPDFSheet` on the R1 PDF), and the main button:
  - draft: `ส่งขออนุมัติ`, with the blocking reason as its small top line while blocked; a tap while blocked selects
    the line at fault (no day, or no assessment) and shows the reason as a toast;
  - sent: `ถอนกลับมาแก้` only for the team (`sendBack`); hidden for a contractor (§7 Q1);
  - approved: a green, disabled `อนุมัติแล้ว`.
- Sending uses the existing path (`send(by:signs:)`, filing the PDF as the tab does today). Approve / reopen for the
  team stay where they are today (§7 Q4).

## 5. Change list

Do these in order, and nothing else.

1. **Working time on the request.** Add optional `workStart` / `workEnd` (minutes after midnight, `Int?`) to
   `WeeklyRequest`, decoded with `decodeIfPresent`, encoded only when set. `requestDraft` leaves them nil; the page shows
   the settings' hours when nil. In `RoutineReportPages.request` only the printed working-time value reads them first.
   Add a test: an old request JSON decodes with nil, a set value round-trips.
2. **Risk scores and the hazard list.** Add optional `likelihood` / `severity` (`Int?`, 1–5) to `RoutineReport.Risk`,
   decoded with `decodeIfPresent`; when both are set, `level` is written from the score (≤ 4 `.low`, ≤ 9 `.medium`,
   else `.high`) so the PDF and older devices keep working. Add `RiskBand` (`ต่ำ`, `ปานกลาง`, `สูง`, `สูงมาก`, from the
   score) for the screen. Add `RoutineReport.Hazard` (name, controls, default L / S, `applies(to: PlanLine) -> Bool`) and
   `RoutineReport.hazards`, the five entries of `sample-data.json` `hazards` (text as written there). Tests: the bands
   at 4/5, 9/10, 16/20; each hazard's rule on a matching and a non-matching line; old risk JSON decodes.
3. **`WeeklyRequestOnePage`** (new, `TCRoof/Views/Job/RoutineReports/WeeklyRequestOnePage*.swift`), split like
   `DailyOnePage`: `+Plan` (key plan, pins, ghosts, full screen), `+Lines` (groups and cards), `+Right` (week row,
   team card, sign card), `+Risk` (the sheet), and the bottom bar in the main file. It takes the request as a binding
   and an `Actions` struct (save, sign, clear, preview, send, withdraw, week, toast), as `DailyOnePage` does. Reuse the
   daily report's views (`KeyPlanImage` / the plan canvas pieces, `DailyWorkTimePopover`, the dropdown rows, the sign
   card) by calling them; if one needs a small parameter to fit, add it with a default so the daily report is
   unchanged. Each card in its own computed property.
4. **`WeeklyRequestScreen` picks it** on iPad at width ≥ 1000 (and with `forceOnePage`), as `DailyReportScreen` does,
   keeping its store, saving, signing, PDF and send code; compact width keeps the current form.
5. **The install page's item.** On iPad, point `คำขอรายสัปดาห์` at `route: .request` (pushes this page) in place of
   `tab: .request`. Leave `Tab.request` and its files in place, unused by the item; list them in your report for
   removal later (§7 Q5). Nothing else in the install page.
6. **DEBUG flags**, documented in `CLAUDE.md` next to `-screen request`:
   - `-screen request -routineRequest onepage` forces this layout;
   - `-requestWeek 0|-1|-2` picks next week or one of the two before;
   - `-requestState line2|weeks|worktime|tools|risk|nodays|signed|sent|approved|empty|map|pdf` opens states 02–13
     (with `-installDemo YES` or `-requestDemo YES`, the board's example in memory, nothing saved; the example key plan
     is a drawn picture, as `-routineKeyPlan YES` does).
7. **UI test** `WeeklyRequestOnePageUITests` (iPad, `-requestDemo YES`): a day chip toggles and the tag becomes
   `แก้วัน`; a pin selects its line; a `+` ghost adds a line; a hazard chip opens the sheet, a cell changes the level
   and `บันทึกระดับ` keeps it; `ส่งขออนุมัติ` stays off until signed; `ดูตัวอย่างคำขอ` opens the PDF sheet; `‹` moves a
   week back. Add it to the UI test list in `CLAUDE.md`.

## 6. Rules and check list

- Colours from `Theme`; the line colours and risk bands as named constants in one place (they carry meaning), not
  hex literals in views. No `Color.white`. Buttons use `TCButtonStyle`. Hit areas ≥ 44 pt, `accessibilityLabel` on the
  pins (`งาน n <task> ที่ <place>`), the ghosts, the day chips (`<day> <date>`, selected or not) and the grid cells
  (`โอกาส L ความรุนแรง S คะแนน n`).
- Old job JSON and old requests decode unchanged; the R1 PDF looks the same except the working-time value.
- A contractor edits only a draft (`isEditable(external:)`), as today; nothing here changes who can send or approve.
- [ ] `swift test` in `TCRoofKit` passes, with the new tests of items 1 and 2.
- [ ] The xcodebuild app build passes with your own `-derivedDataPath` (in the background).
- [ ] Simulator screenshots at 1366 × 1024 for states 01–13, saved to `screenshots/` with the same names, compared
      side by side with `states/`.
- [ ] `WeeklyRequestOnePageUITests`, `DailyOnePageUITests` and `InstallTrackingUITests` pass.
- [ ] Every item of §5 ticked in your report.

## 7. Open questions (answer in your report; do not block on them)

1. **Withdraw.** The board's `ถอนกลับมาแก้` lets the sender take a sent request back. Team devices drop a contractor's
   change to a sent week (`WeeklyRequest.trusting`), so this task offers it to the team only. Should a contractor be able
   to withdraw (a rules and `trusting` change)?
2. **Places as areas.** The board draws each place as a rectangle on the plan. The station stores points
   (`keyPoints`). Should places get areas (and an editor), for the daily report too?
3. **Hazard text.** The hazards' controls and default scores come from the board. Who reviews them (the team's safety
   officer), and should the list live in settings per station or team-wide in `config/`?
4. **Approve on this page.** The board shows the contractor's side. Should the team's `อนุมัติ` / `ส่งกลับ` also be in
   this page's bottom bar, as they are in the tab's panel?
5. **The in-page tab.** Once this page is in use, can `Tab.request` and its files (`InstallTrackingPage+Request*.swift`)
   be removed?
