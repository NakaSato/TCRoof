# Claude Code task: iPad install tracking, `Weekly Report` tab in the page

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/install-tracking-ipad-weekly-report` and type
> `Follow docs/ui/install-tracking-ipad-weekly-report/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels: keep them exactly.

**Do only what this task lists.** Do not refactor, rename or restyle anything outside the change list in §5. Do not
touch:

- the other tabs of the page (`ภาพรวม`, `รายงานประจำวัน`, `คำขอรายสัปดาห์`, `เอกสาร`, `แผนก่อสร้าง`, …)
- the R3 PDF layout (`RoutineReportPages.weekly`)
- the iPhone page, except the one shared slide list of §5 item 3
- Firestore rules, `CloudSync` or `firestore.rules` (see §5 item 2 for the one stored field)

**Example data.** The board's station, weeks, days, percentages, photos, problems and recipients are examples
(`assets/sample-data.json`). The app reads:

- the week's daily reports (`job.dailyLogs`, `RoutineReport.Daily`, `engineerSignedAt`, `sortedPhotos`)
- the MP plan (`job.scheduleInput`, `job.scheduleActual`, `MasterSchedule.status`)
- next week's request (`job.weeklyRequest(for:)`)
- the station's routine settings (`job.routineSettings`: working weekdays, holidays)

Never hard-code a board value.

## 1. Context

- `InstallTrackingPage` (`TCRoof/Views/Install/Tracking/`) is the iPad page of a PWA station being installed. Its
  `Weekly Report` item is `Item(id: "weekly", … route: .weekly)` and pushes `RoutineSummaryScreen(job:, period: .week)`
  (`TCRoof/Views/Job/RoutineReports/RoutineSummaryScreen.swift`): a PDF view with `เก็บในเอกสาร`, `PDF` and
  `PowerPoint`.
- The iPhone already has a weekly tab in the page (`InstallTrackingPage+PhoneSummaries.swift`, `phoneWeeklyTab`): the
  step line `รอข้อมูล | พร้อมส่ง | ส่งแล้ว`, a slide strip, the `ความพร้อมก่อนส่ง` checks and the download menu. Its
  checks are the logic to reuse on iPad.
- The board **`iPad · ติดตามงานติดตั้ง · แท็บWeekly Report`** (`iPadInstallWeeklyReport.dc.html`, 1366 × 1024, menu
  `wr`) draws `Weekly Report` **in the page**: the week's deck as the customer's 8-slide `Weekly Report Template`, a
  slide viewer, the readiness checks, the recipients and `ส่งให้ n ผู้รับ`. This task builds that tab.
- `คำขอรายสัปดาห์` (`Tab.request`) and `เอกสาร` (`Tab.docs`) were moved into the page the same way. Follow their
  pattern (`InstallTrackingPage+Request.swift`, `+RequestPanel.swift`), and keep your change to `Tab` to one new case so
  it merges cleanly with other branches.
- `WeeklySlides` (`TCRoofKit/Sources/ExcelExport/WeeklySlides.swift`) builds R3 as .pptx today with its own slide
  order (cover, plan, a slide per daily report, weather, labour, problems, next week). The board's deck is the
  template's 8 slides (§4.3). §5 item 1 moves `WeeklySlides` to that order; the screen preview and the file must show
  the same slides.

## 2. Before you start

Start with code-review-graph, as `CLAUDE.md` says:

- `InstallTrackingPage`: `Tab`, `Route`, `items`, `go(_:)`, the `request` tab (`requestTab`, `requestWeek`,
  `loadRequest`), the DEBUG flags block (`-installTab`, `-installDemo`)
- `InstallTrackingPage+PhoneSummaries`: `phoneWeeklyTab`, `reportWeekRange`, `slidesCard`
- `RoutineSummaryScreen`: `fileIt`, `exportPDF`, `exportSlides`
- `RoutineReportFiles.weekly`, `RoutineReportFiles.weeklySlides`, `RoutineReport.fileName(.weekly, …)`,
  `RoutineReport.folder(.weekly, …)`
- `WeeklySlides` (`Input`, `Deck.slides()`, `weather()`, `package`) and `WeeklySlidesTests`
- `tests_for` on anything you touch, plus `InstallTrackingUITests` and `PhoneInstallTrackingUITests`

Then read the source and open `iPadInstallWeeklyReport.dc.html` as text. The tab's logic is the block after
`v.isWr` in `renderVals()` (its v3 part, "no editing and no signature", is the one that counts), and its markup is the
`{{isWr}}` section and the `{{wrPptOpen}}` sheet.

## 3. Files in this folder

| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `iPadInstallWeeklyReport.dc.html`, `grf.css` | The board (the whole install page; this task is its `Weekly Report` tab) |
| `preview.png` = `states/01-default-cover.png` | Week 40, one daily report unsigned, slide 1. @2x (2732 × 2048) |
| `states/02-progress-slide.png` | Slide 3 `ความก้าวหน้า` selected: plan / actual bars per week and the % box |
| `states/03-daily-slide-unsigned.png` | Slide 4 `งานรายวัน`: the unsigned day's row is a dashed orange placeholder, its rail tile has `!` |
| `states/04-photos-slide.png` | Slide 5 `ภาพหน้างาน 1/2`: three photos with captions |
| `states/05-ready.png` | Every daily report signed: checks 4/4, step `พร้อมส่ง`, `ส่งให้ 2 ผู้รับ` enabled |
| `states/06-download-menu.png` | `ดาวน์โหลด ▾` open: `.pptx` and `PDF` |
| `states/07-pptx-sheet.png` | The .pptx preview sheet: every slide in two columns, `แชร์`, `ปิด`, `ดาวน์โหลด .pptx` |
| `states/08-sent.png` | Sent: steps all done, `✓ ส่ง วันนี้ 11:05 · ถึง 2 ผู้รับ`, `ส่งแล้ว · อ่านอย่างเดียว`, recipients locked |
| `states/09-previous-week.png` | Week 39 after `‹`: sent earlier, read only |
| `assets/sample-data.json` | The board's example values |
| `assets/*.png` | The template's pictures: PEA seal (slide header), AGENDA markers 1–3, weather icons |
| `screenshots/` | Put your simulator screenshots here, named like `states/` |

## 4. The tab

The page header, tab bar and dock stay as they are. Under the tab bar there is a header card, then three columns: the
slide rail (about 206 pt), the slide viewer (fills), and a right panel (about 300 pt). The page does not scroll; the
rail and the right panel's list scroll inside themselves. The last row ends above the dock (`dockClearance`).

### 4.1 Header card (full width)

- **Left:** `Weekly Report` and the sub-line `สร้างอัตโนมัติทุกอาทิตย์ 18:00 · จากรายงานประจำวัน`. See §7 Q1 for the
  time: if nothing schedules the weekly report today, write `จากรายงานประจำวัน` alone.
- **Week switcher:** `‹` / `›` (44 pt), `สัปดาห์ที่ n` and the dates. It opens on the current week (the one being
  reported, `RoutineReport.week(of:)`, as `reportWeekRange` does on iPhone). `›` is off on the current week.
- **Step line** `รอข้อมูล — พร้อมส่ง — ส่งแล้ว`, numbered circles 1–3:
  - `รอข้อมูล` (orange) while a check of §4.4 fails,
  - `พร้อมส่ง` (blue) when every check passes,
  - `ส่งแล้ว` (green) once sent (§5 item 2). Done steps get a green `✓`.
- **Right:** the due line, `กำหนดส่งเจ้าของงาน` over the day and how many days are left (`จ. 5 ต.ค. · อีก 1 วัน`,
  orange): the first working day after the week ends. Once sent: `ส่งเจ้าของงานแล้ว` over `ส่งแล้ว` or the sent date
  (green).
- **`ดาวน์โหลด ▾`** (44 pt high): a menu with `ดาวน์โหลด .pptx` (opens §4.6) and `ดาวน์โหลด PDF` (the R3 PDF from
  `RoutineReportFiles.weekly`, through the share sheet as `RoutineSummaryScreen.exportPDF` does).

### 4.2 Left: the slide rail

- Title `สไลด์ 8 หน้า`, sub-line `แม่แบบ Weekly Report Template`.
- One tile per slide: a thumbnail of the slide (the same view as the viewer, scaled), the number, the label, and a
  status dot: green `✓` when its data is there, orange `!` when it waits on something (an unsigned daily report for
  slides 4, 7 and 8).
- The selected tile has a 2 pt `Theme.primary` border on `Theme.primarySoft`. A tap selects it.

### 4.3 Centre: the slide viewer

- Header: `สไลด์ n/8 · <label>`, a chip `ข้อมูลครบ` (green) or `รอข้อมูล` (orange), and `‹` / `›` (44 pt) on the right.
- The slide, 16:9, on `Theme.paper`, drawn to scale from the same values `WeeklySlides` writes (one SwiftUI view per
  slide kind, drawn at 1920 × 1080 points and scaled to fit). Under it a dot per slide; the current one is a 22 pt bar.
- The 8 slides of the template (header band `#4472C4`-style blue band at the top and the PEA seal top right on every
  slide; these are the customer's template colours, so put them in the slide drawing as named constants, not in
  `Theme`):

  | # | Label | Content | Data |
  |---|---|---|---|
  | 1 | `ปก` | `Weekly Report`, the project line, `สถานีผลิตน้ำ<station>`, `ประจำวันที่ … ถึงวันที่ …` | station, week |
  | 2 | `AGENDA` | three items with the hexagon markers 1–3: `CONSTRUCTION PROGRESS`, `Weather Report`, `ปัญหาและอุปสรรค` | fixed |
  | 3 | `ความก้าวหน้า` | `1.Construction Progress`, `ความก้าวหน้าของงาน`: plan and actual bars for the last six weeks (current week dark), a grey box `% WORK PROGRESS / PLAN / ACTUAL / STATUS`, `ข้อมูล ณ วันที่ …` | MP plan, cumulative % per week |
  | 4 | `งานรายวัน` | `1.Construction Progress`, a table `ลำดับ · สัปดาห์ที่ · วันที่ · การดำเนินงาน`, one row per day of the week | daily reports' work lines; a holiday reads `วันหยุด` |
  | 5 | `ภาพหน้างาน 1/2` | `Construction Progress`, `PROGRESS FOR THIS WEEK`, photos 1–3 with captions | the week's photos |
  | 6 | `ภาพหน้างาน 2/2` | the same, photos 4–6 | |
  | 7 | `Weather Report` | seven columns: the day name in the template's day colour, the date, the weather icon and its text | daily reports' weather |
  | 8 | `ปัญหาและอุปสรรค` | two boxes: `ปัญหาและอุปสรรคระหว่างปฏิบัติงาน` and `แนวทางแก้ไข`, bullets | daily reports' problems and their fixes |

- **A day that waits** (a working day whose daily report is not signed): its row on slide 4 shows
  `รอเซ็นรายงานประจำวัน <day>` in italic orange in a dashed orange box (state 03), and slides 4, 7, 8 are `รอข้อมูล`.
- **Photos:** the six photos are picked from the week's daily-report photos automatically (spread over the days, first
  photo of each day first). There is no picker on this board. Fewer than six photos leaves empty frames.
- **Weather icons:** map the daily report's weather to the three icons (`weather-sunny`, `weather-partly-cloudy`,
  `weather-thunderstorm` in `assets/`); a value with no icon shows its text only.
- **Sources under the viewer** (`v.wrChips`): skip them unless they fit without crowding; see §7 Q4.

### 4.4 Right: readiness, recipients, send

- **`ความพร้อมก่อนส่ง`** and `n/4` (green at 4/4, else orange). Four rows, the same checks as the iPhone's
  `phoneWeeklyTab`:
  1. `รายงานประจำวันเซ็นครบ`: `เซ็นแล้ว n/m วันทำงาน · <days> รอเซ็น`, with `ไปแก้` (44 pt) when it fails, which opens
     the `รายงานประจำวัน` tab (`tab = .daily`);
  2. `แผน MP สัปดาห์ที่ n`: `แผนสะสม n%`, or `ยังไม่มีแผน MP` (failing);
  3. `รูปหน้างาน`: `n รูปจากรายงานประจำวัน`, with `ไปแก้` when there are none;
  4. `ปัญหาและแนวทางแก้ไข`: `รวมจากรายงานประจำวัน n ข้อ` (always passes).
  A passing row is on `Theme.phonePage` (as on iPhone) with a green `✓`; a failing one on `Theme.warningSoft` with an
  orange `!`.
- **`ส่งถึง`**: three chips, `เจ้าของงาน กปภ.`, `ผู้ตรวจ กฟภ.`, `ทีมภายใน`. Picked: `✓` on `Theme.primarySoft`;
  not picked: `+` with a dashed border. Default: `เจ้าของงาน กปภ.` and `ทีมภายใน`. Read only once sent.
- **Bottom of the panel:**
  - before sending: the note `ส่งได้เมื่อเช็กลิสต์ครบ` and the button `ส่งให้ n ผู้รับ` (full width, 52 pt),
    disabled until every check passes and at least one recipient is picked;
  - after: `✓ ส่ง <day> hh:mm · ถึง n ผู้รับ`, `ส่งแล้ว · อ่านอย่างเดียว`, and a green, disabled `✓ ส่งแล้ว`.

### 4.5 Sending

`ส่งให้ n ผู้รับ`:

1. builds the PDF and the .pptx,
2. files them into the job's documents as `fileIt` does today (`RoutineReport.fileName(.weekly, …)`, the weekly
   folder), so the existing Drive upload carries them,
3. opens the share sheet with both files, so the person sends them by mail or LINE,
4. records the send (§5 item 2) when the share sheet completes (not when it is cancelled).

There is no in-app mail. Who the chips stand for (addresses) is §7 Q2.

### 4.6 The .pptx sheet (state 07)

A sheet over the page (about 1080 × 940): the PowerPoint badge, `Weekly Report สัปดาห์ที่ n.pptx`, the sub-line
`8 สไลด์ · 16:9 · ใช้แม่แบบ "Weekly Report Template" · ข้อมูลจากรายงานประจำวัน แผน MP และรูปที่เลือก`, `แชร์` and
`✕` in the header; every slide in two columns with `n · <label>` under it (scrolls); a footer note
`สร้างอัตโนมัติจากงานที่ส่งในสัปดาห์ · ลงแม่แบบต้นฉบับ`, `ปิด` and `ดาวน์โหลด .pptx` (opens the share sheet with the file
from `RoutineReportFiles.weeklySlides`).

### 4.7 Previous weeks (state 09)

`‹` goes back. A week that was sent is read only (no chips to change, the sent line in place of the button). A past
week that was never sent still offers `ส่งให้ n ผู้รับ`.

## 5. Change list

Do these in order, and nothing else.

1. **`WeeklySlides` follows the template's 8 slides** (ExcelExport). Change `Deck.slides()` to the 8 slides of §4.3, in
   that order, keeping `Input` and `export(_:images:)` as they are (add optional inputs only if a slide needs one). Add
   the template's pictures from `assets/` to the package's resources (`ExcelExport/Resources/WeeklyTemplate/`) and
   place them as §4.3 says. Add `WeeklySlides.outline(_ input:) -> [Outline]` (label, source, `ready: Bool`), the one
   list the screen's rail, viewer chips and the .pptx sheet read. Update `WeeklySlidesTests`: 8 slides, their order,
   a waiting day marked, the pictures present in the package, photos 1–6 split 3 + 3.
2. **The send record.** Add `RoutineReport.WeeklySent` (`weekStart`, `sentAt`, `sentBy`, `recipients: [String]`),
   Codable with `decodeIfPresent` defaults, kept on the job as an optional JSON field (`weeklySentJSON`, nil by
   default) with `job.weeklySent(for:)` and `job.recordWeeklySent(_:)`. The step line, the due line and read-only mode
   read it; a week with no record but a filed weekly document counts as `ส่งแล้ว` without a time (older data). Check
   how `CloudRecords` carries job fields: if the job document carries a new field without a rule change, let it sync;
   otherwise keep it on the device and say so in your report.
3. **The iPhone strip reads the same list.** Change only `slidesCard` in `InstallTrackingPage+PhoneSummaries.swift` to
   take its labels and dots from `WeeklySlides.outline`. Nothing else on the iPhone.
4. **`Tab.weekly` on iPad.** Add one case to `InstallTrackingPage.Tab`, point the `Weekly Report` item at it in place of
   `route: .weekly` (keep `Route.weekly` for the iPhone and other callers), and add the tab's body in a new file
   `InstallTrackingPage+WeeklyReport.swift`, laid out like `requestTab()` (no outer scroll). Split it into computed
   properties: `weeklyHeader`, `weeklyRail`, `weeklyViewer`, `weeklyPanel`, `weeklyPptxSheet`. Move the readiness
   checks out of `phoneWeeklyTab` into a shared helper (`weeklyChecks(week:)`) both sizes call, without changing their
   wording or results.
5. **Slide views.** `WeeklySlideView(kind:, data:)` in its own file, one small view per slide kind, drawn at
   1920 × 1080 and scaled; used by the rail, the viewer and the .pptx sheet.
6. **Send flow** of §4.5 and the .pptx sheet of §4.6.
7. **DEBUG flags**, documented in `CLAUDE.md` next to `-installTab`:
   - `-installTab weekly` opens the tab on iPad;
   - `-installReportWeek 0|1|2`: the current week or one of the two before;
   - `-installReportSlide 1…8`: the selected slide;
   - `-installReportState ready|menu|pptx|sent`: states 05–08 (in memory with `-installDemo YES`, nothing saved);
   - with `-installDemo YES` the tab shows the board's example (one unsigned day, six drawn photos), nothing saved.
8. **UI test** `InstallWeeklyReportUITests` (iPad, `-installDemo YES -installTab weekly`): the rail selects slide 4 and
   its chip reads `รอข้อมูล`; `ไปแก้` opens `รายงานประจำวัน`; `ดาวน์โหลด` shows both items; `ดาวน์โหลด .pptx` opens the
   sheet and `ปิด` closes it; with `-installReportState ready` the send button is enabled; `‹` moves to the week
   before. Add it to the UI test list in `CLAUDE.md`.

## 6. Rules and check list

- Colours from `Theme` for the app's chrome; the slides use the template's own colours as named constants in the slide
  views (they are a document, like the PDF). No hex literals elsewhere, no `Color.white` (use `Theme.surface` /
  `Theme.paper`).
- Buttons use `TCButtonStyle`; hit areas ≥ 44 pt; `accessibilityLabel` on icon buttons, the rail tiles
  (`สไลด์ n <label>`, value `ข้อมูลครบ` / `รอข้อมูล`) and the step line.
- Old job JSON and old jobs decode unchanged; the PDF is unchanged.
- [ ] `swift test` in `TCRoofKit` passes (with the updated `WeeklySlidesTests`).
- [ ] The xcodebuild app build passes with your own `-derivedDataPath` (in the background).
- [ ] An exported .pptx opens in Keynote / PowerPoint with 8 slides and the pictures (check one by unzipping).
- [ ] Simulator screenshots at 1366 × 1024 (`-homeBoard YES`) for states 01–09, saved to `screenshots/` with the same
      names, compared side by side with `states/`.
- [ ] `InstallWeeklyReportUITests`, `InstallTrackingUITests` and `PhoneInstallTrackingUITests` pass.
- [ ] Every item of §5 ticked in your report.

## 7. Open questions (answer in your report; do not block on them)

1. **`สร้างอัตโนมัติทุกอาทิตย์ 18:00`.** Is there a reminder or build at Sunday 18:00 for R3 today
   (`NotificationPlan`)? If not, use the sub-line without the time and say whether one should be added.
2. **Recipients.** The chips are categories. Should they map to addresses (the job's PWA owner, the PEA inspector from
   `routineSettings.inspector`, the team directory) for a mail draft, or stay a record of who it went to?
3. **The customer's template file.** The slides here are drawn from the board. If the real
   `Weekly Report Template.pptx` is in the repo or Drive, say so and list any difference.
4. **Sources under the viewer.** The board has chips naming each slide's sources (daily reports, MP plan, the request
   W41). Were they kept? If not, should they come back?
5. **Photo choice.** The board picks six photos automatically. Should the person be able to swap them?
