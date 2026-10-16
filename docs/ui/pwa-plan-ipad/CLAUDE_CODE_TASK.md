# Claude Code task: PWA `แผนงาน` page on iPad: schedule | MP plan, with stations and deadlines side by side (board 14 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and paste `PROMPT.md`, or type
> `Follow docs/ui/pwa-plan-ipad/CLAUDE_CODE_TASK.md`

- **Board:** `iPad · แผนงาน PWA (ตารางงาน · แผน MP · กำหนดส่ง)` (`iPadPwaPlan.dc.html`, 1366 × 1024 pt, landscape).
- Thai strings in `backticks` are literal UI labels.
- Every name, number, date, MP, team and count in the previews is **example data**. Never hardcode any of it.

## What is built today, and what this task does
- **iPhone:** `PWAPlanPhoneView` (`TCRoof/Views/Survey/PWAPlan/`, from `docs/ui/pwa-plan-iphone`) is built.
  - It has its own header `แผนงาน PWA`.
  - `TCCountSegments` `ตารางงาน · แผน MP · กำหนดส่ง` switches between **one** pane at a time.
  - The data is `PWAPlanBoard` (`PWAPlanData.swift`).
- **iPad today:** the PWA home's nav `แผนงาน` (`PWARoot.openPlan`) pushes that same iPhone view, stretched to 1366 pt, with the dock hidden.
- **This task:** a regular-width layout of the plan page that shows **all three panes at once**, inside the PWA home's frame:
  - header `โครงการ PWA`
  - nav `โครงการ | แผนงาน | บำรุงรักษา` with `แผนงาน` selected
  - the dock with `โครงการ` selected

  **Reuse the iPhone pieces** (`schedule`, `calendarCard`, `curveCard`, `ganttCard`, `dueGroup`/`dueRow`, `open(_:station:)`, `PWAPlanBoard`). Do not write a second data path.

## Scope: change only this list
1. On iPad, `แผนงาน` shows the plan **in the PWA home's frame**: same header, same nav with `แผนงาน` selected, and the dock stays visible. It is not a pushed full-screen page with its own header.
2. The body is **two columns**:
   - left: a framed `ตารางงาน` card (calendar + agenda)
   - right: `แผน MP`, with the S-curve full width, then `รายสถานี | กำหนดส่ง` 50/50
3. Cards, frames and spacing as below. There is no bottom fade on this page.

**Do not touch:**
- the iPhone (`PWAPlanPhoneView` compact layout, its header and pills)
- `PWAPlanBoard` / `PWAPlanData` logic
- the PWA home's `โครงการ` and `บำรุงรักษา` views
- the screens a row opens (`JobDetailView`, `MPScheduleScreen`, `StationDocsScreen`, `DailyReportListView`, `SurveyReportEditor`)
- data models

**Before editing:** use code-review-graph (per `CLAUDE.md`). If the server is not available, use grep.
- Look at: `PWAPlanPhoneView` and its `+Schedule`, `+MP`, `+Due` extensions, `PWAPlanBoard`, `PWARoot` (`openPlan`, `showPlan`)
- Look at: `SurveyHomeView` `navRow` / `phoneHeader` (`TCPhoneSearchHeader`, `wide:`), `PWAOverviewHost.openPlan`, `PadTabs`
- Then run `tests_for` on what you touch: `PhoneSurveyUITests`, `HomeNavbarUITests`, and any `PWAPlan` test.

## Files in this folder
| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `preview.png` | The default state, the same as `states/01-plan.png` (@2x) |
| `states/01-plan.png` | Default: week calendar, today's agenda, S-curve, stations and deadlines, dock |
| `states/02-calendar-month.png` | `เดือน` selected: month grid with the type bars and legend; the agenda heading becomes `งานทั้งเดือน n รายการ` |
| `states/03-day-14.png` | Day 14 picked in the week strip; the agenda scrolls to it |
| `states/04-search-open.png` | Header search open, as on the PWA home |
| `states/05-right-column-scrolled.png` | The right column scrolled to its end: all of `สัปดาห์หน้า` |
| `states/06-schedule-card-crop.png` | The `ตารางงาน` card, close-up |
| `states/07-scurve-crop.png` | The full-width S-curve card |
| `states/08-stations-deadlines-crop.png` | `รายสถานี` and `กำหนดส่ง`, side by side |
| `states/09-header-nav-crop.png` | Header + nav with `แผนงาน` selected |
| `iPadPwaPlan.dc.html` + `grf.css` | The design source. Read it as text: the markup and `renderVals()` hold every size, colour and rule |
| `screenshots/` | Empty. Put your simulator screenshots here |

## 1. Frame: the plan lives in the PWA home (`states/09`, `01`)
- **Header:** the same as the PWA home on iPad: `โครงการ PWA` 30 pt, round search, bell, radius 20, padding 22/63.
  - The iPhone plan header `แผนงาน PWA` / `การประปาส่วนภูมิภาค` is **not** used on iPad.
  - There is no back button: `แผนงาน` is a place, not a push.
- **Nav row:**
  - `TCCountSegments` `โครงการ | แผนงาน | บำรุงรักษา`, with **`แผนงาน` selected** (white, bold, soft shadow).
  - 20 pt under the header, 63 pt side margins.
  - **No filter button** on this page: the nav takes the full width.
  - Tapping `โครงการ` or `บำรุงรักษา` goes back to those views in place.
- **Dock:** stays visible with `โครงการ` selected, as on the PWA home.
- **How to host it, your choice; report which:**
  - (a) Make `แผนงาน` a real segment on iPad. `SurveyHomeView` lives in `TCRoofKit` and the plan view is in the app, so the host gives it the plan body (e.g. a `planBody` closure on `PWAOverviewHost`) and `SurveyHomeView` shows it under the nav when `แผนงาน` is selected.
  - (b) `PWARoot` pushes a `PWAPlanPadView` that draws the same header and nav itself and keeps the dock.

  (a) keeps one header and nav. Either is fine as long as the result looks the same and the dock stays. On iPhone, `แผนงาน` keeps pushing `PWAPlanPhoneView`.
- **Search** in the header filters the plan the same way the iPhone plan's search does: agenda rows, stations and deadlines.

## 2. Left column: `ตารางงาน` card (`states/06`, `02`, `03`)
- **Column:** 440 pt wide.
- **Card frame:** white, 1 pt `#DDE4ED` border, radius 16, padding 10/12 (no bottom padding).
  - It ends **116 pt above the screen bottom** so it clears the dock.
  - The card header and the calendar stay put; **only the agenda scrolls inside the card**, with no scroll indicator.
- **Card header:** `ตารางงาน` 14 pt bold + `ทุกงานของโครงการ` 11 pt `#5B6B82`.
- **Calendar block:** the iPhone `calendarCard`, inside a soft panel: `#F8FAFC`, 1 pt `#E6ECF3`, radius 12, padding 8/6.
  - Title + `สัปดาห์ที่ n` (week), or the month name (month).
  - `‹ ›` arrows.
  - The `สัปดาห์ | เดือน` toggle: track `#E6ECF3`, selected white.
  - The day strip or month grid, with the type bars under each day.
  - The legend (month).
  - The selected day is the navy tile; weekends are grey.
- **Agenda:** the iPhone `listHeading` + day sections + `agendaRow`:
  - `งานสัปดาห์นี้ n รายการ · เลื่อนดูได้` (week) or `งานทั้งเดือน n รายการ` (month)
  - `● วันจันทร์ 12 ต.ค. · วันนี้ n รายการ`
  - **Rows:**
    - soft fill `#F8FAFC`, 1 pt `#E6ECF3` border, radius 12
    - start time 16 pt bold and end time 12 pt on the left
    - a 3 pt bar in the type colour
    - type chip + MP/NO + status on the right
    - title 15 pt bold, sub line 12.5 pt
  - The type colours are `PWAPlan.JobType.ink` / `.fill`.
- **Behaviour:**
  - Picking a day scrolls the agenda to it; scrolling the agenda selects the day (the iPhone `spyLock`/`jump` logic).
  - Taps open the same routes as on iPhone.
- The iPhone schedule's **filter button / popover is not on the iPad board.** Keep its state at "all" and do not show it (open question 2).

## 3. Right column: `แผน MP`, then `รายสถานี | กำหนดส่ง` (`states/07`, `08`, `05`)
- **Column:** the rest of the width, 20 pt from the left card. It **scrolls on its own**, with no indicator and 130 pt bottom padding for the dock.
- **Heading:** `แผน MP` 20 pt bold + `Master Plan · n สถานี` 13 pt `#5B6B82`.
- **S-curve card, full width** (`states/07`):
  - white, 1 pt `#DDE4ED` border, radius 16, padding 12/16
  - `ความก้าวหน้าทั้งโครงการ` 15 pt bold with `สัปดาห์ n/20` on the right
  - `จริง 47%` (20 pt, primary) · `แผน 48%` (20 pt, navy), and on the right the variance (`ช้ากว่าแผน n%` red / `ตามแผน`)
  - **Chart:** 170 pt tall, spanning the card width.
    - Plan dashed `#9FB3CC`, actual 2.6 pt primary, the red `วันนี้` line.
    - Y grid at 0/25/50/75/100 %, month labels under it.
    - Keep the text at its real size when the chart widens: no stretched glyphs. The iPhone `curveCard` scales into a fixed box, so check its labels at 760+ pt.
  - The legend row underneath.
- **Under it, two equal columns with a 14 pt gap, aligned to the top:**
  - **`รายสถานี` card** (the iPhone `ganttCard`):
    - white, 1 pt `#DDE4ED` border, radius 16, padding 10/12
    - header `รายสถานี` 14 pt bold + `เรียงตามวันส่งมอบ` 11 pt
    - month axis labels
    - rows: name 13 pt bold + `MP n · ผู้รับเหมา X` 11 pt, then the bar (track `#E3E9F1`, actual in the pace colour, a navy plan tick, the red today line), then the handover date (red when behind)
    - `อีก n สถานี · เลื่อนดู` at the end
    - Rows open the station, as on iPhone.
  - **`กำหนดส่ง` card:**
    - white, 1 pt `#DDE4ED` border, radius 16, padding 10/12/12, 8 pt between blocks
    - header `กำหนดส่ง` 14 pt bold + `งานส่งมอบและเอกสาร` 11 pt
    - then the iPhone groups `สัปดาห์นี้ 12–18 ต.ค. · รวมที่เลยกำหนด` and `สัปดาห์หน้า 19–25 ต.ค.` (14 pt bold + 12 pt range)
    - **Rows:**
      - soft fill `#F8FAFC`, 1 pt `#E6ECF3` border, radius 12, padding 8/12
      - a 46 pt date tile in the tone colour (day 16 pt bold over month 10 pt)
      - title 14 pt bold and sub 12 pt, each one line
      - the status chip 11 pt bold on the right (`เลยกำหนด n วัน`, `เสี่ยงช้า`, `วันนี้`, `ตามแผน`, `ช้ากว่าแผน`, `เอกสาร x/y`, `พร้อมยื่น`, `นัดแล้ว`)
    - The card grows with its rows; the column scrolls (`states/05`).
    - The iPhone due filter menu is **not** on the iPad board (open question 2).
- **No bottom gradient fade** on this page. The owner asked for it to be removed. The dock sits over the content as is.

## DEBUG
- `-surveyHomeTab plan` on iPad opens the plan page directly. No delayed push is needed, since it isn't pushed.
- Keep `-pwaPlanDemo YES`, `-pwaPlanToday 2026-10-12`, `-pwaPlanCalendar week|month`, `-pwaPlanDay 2026-10-14` and `-pwaPlanSearch YES` working on iPad.
- Update CLAUDE.md where it says the plan is iPhone-only.

## Check
- [ ] Build with your own `-derivedDataPath`. If you touched `TCRoofKit/`, run `swift build` + `swift test` there.
- [ ] Run on an iPad Pro 13" simulator, landscape, with `-surveyHomeTab plan -pwaPlanDemo YES -pwaPlanToday 2026-10-12`. Compare with `states/01`, `02` (`-pwaPlanCalendar month`), `03` (`-pwaPlanDay 2026-10-14`) and `05`. Note any difference larger than 4 pt.
- [ ] Header, nav (`แผนงาน` selected) and dock (`โครงการ` selected) look exactly like the PWA home's. Switching segments keeps them still.
- [ ] Only the agenda scrolls on the left; the right column scrolls as one.
- [ ] Rows open the same screens as on iPhone.
- [ ] The S-curve labels are not stretched.
- [ ] iPhone is unchanged. Run the `docs/ui/pwa-plan-iphone` state 01 and the PWA home iPhone state 01 again and compare them.
- [ ] Simulator screenshots of states 01, 02, 05 and 07 are in `docs/ui/pwa-plan-ipad/screenshots/`.

## Open questions (report, don't decide)
1. Which hosting did you choose (a in-page segment / b pushed page with the same frame), and why?
2. The iPhone plan has a schedule filter (type, team) and a deadline filter. The iPad board shows neither. Should iPad get them (e.g. in the nav row's filter button), or is "all" enough?
3. The iPhone's pill counts (`ตารางงาน n`, `แผน MP n`, `กำหนดส่ง n` with the late alert) have no place on the iPad board. Is the late-deadline alert needed somewhere, e.g. on the nav's `แผนงาน` segment?
