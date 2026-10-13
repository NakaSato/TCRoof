# Claude Code task: iPhone PWA `แผนงาน` page (ตารางงาน · แผน MP · กำหนดส่ง)

> **How to use:** open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/pwa-plan-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels: keep them exactly.

**Example data.** Every station, time, team, date and percentage on the board is example data
(`assets/sample-data.json`). "Today" on the board is จันทร์ 12 ต.ค. 2569 (2026-10-12), week 42.
In the app, use the real `Job` records, `MasterSchedule` plans and today's date.

## Context

This is **phase 2** of `docs/ui/pwa-solar-survey-iphone-v2` (§8 "`แผนงาน` page: phase 2, reference only", and open
question 5). That task built the PWA dock (`TCRoof/Views/Survey/PWAPhoneTabs.swift`). Its `แผนงาน` tab still opens
`MPOverviewView` (`TCRoof/Views/Job/MPOverviewView.swift`) as a stop-gap:

```swift
case .plan: MPOverviewView().toolbar(.visible, for: .navigationBar)
```

The owner has now finished the board `iPhone · แผนงาน PWA` (`PhonePwaPlan.dc.html`). It **replaces the `แผนงาน` tab's
content on iPhone** with one page that has three views under capsule pills, like the PWA home:

1. `ตารางงาน`: a week strip and the selected day's agenda for PWA work, with a filter popover.
2. `แผน MP`: the project S-curve (plan vs actual) and a Gantt row per station.
3. `กำหนดส่ง`: deadlines (handovers and document submissions) grouped by week, with a filter menu.

The board in v2's folder (`docs/ui/pwa-solar-survey-iphone-v2/PhonePwaPlan.dc.html`) is an older draft: **this folder's copy
is the final one.** Differences from that draft are listed in §6.

**Scope: compact width (iPhone) only.** `MPOverviewView` stays as it is for iPad and for every other place that opens it.
Do not change the PWA home, `เอกสาร`, `ตั้งค่า`, the dock, or the main app's plan calendar (`PlanCalendarView`).

**Before you start.** Use code-review-graph first (per `CLAUDE.md`):
- callers of `PWAPhoneTabs.root`, `MPOverviewView`, `MPOverviewRow`, `MPScheduleScreen`, `TCPWAHeader`, `TCCapsuleTabs`,
  `TCTabBar`, `TCDockFade`, the `filterButton` / `filterPopover` in `TCRoofKit/Sources/SurveyUI/SurveyHome+Phone.swift`
- `MasterSchedule.plan`, `MasterSchedule.status`, `MasterSchedule.plannedPoints`, `Job.scheduleInput`, `Job.scheduleActual`
- `tests_for` on anything you touch

Then read the source and the board.

## Files in this folder

| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `preview.png` = `states/01-schedule-today.png` | Default: `ตารางงาน`, week view, today selected, list at today. @2x (780 × 1688) |
| `states/02-schedule-filter-open.png` | Agenda filter popover open (`กรองตารางงาน`) |
| `states/03-schedule-filtered-install-A.png` | Type `ติดตั้ง` + team `A`: navy filter button with orange dot, removable chips, counts `N จาก M` |
| `states/04-schedule-scrolled-to-15.png` | The list scrolled to พฤ. 15: the calendar highlight followed the scroll |
| `states/05-schedule-month.png`, `15-month-grid-crop.png` | Month view: whole October, colour bars, legend |
| `states/06-schedule-month-day-20.png` | Month view after tapping 20: the list jumped to 20 |
| `states/07-schedule-month-empty-day.png` | Month view, ส. 17 selected: that day's group shows `ไม่มีงาน` |
| `states/14-week-strip-crop.png` | Week strip close-up: title, `สัปดาห์ที่ 42`, `สัปดาห์ / เดือน` switch, bars |
| `states/08-mp.png` | `แผน MP`: S-curve card and `รายสถานี` Gantt |
| `states/09-due.png` | `กำหนดส่ง`: `สัปดาห์นี้` / `สัปดาห์หน้า` groups; the filter button sits at the end of the pill row |
| `states/10-due-filter-open.png` | Deadline filter menu open (right-aligned under the button) |
| `states/11-due-filtered-docs.png` | `ยื่นเอกสาร` only: button navy with orange dot |
| `states/12-search-open.png` | Header search expanded (same component as the PWA home) |
| `states/13-header-tabs-crop.png`, `16-dock-crop.png` | Close-ups |
| `states/01-schedule-today.pdf`, `05-schedule-month.pdf`, `08-mp.pdf`, `09-due.pdf` | **Vector** 390 × 844 renders. Measure here. |
| `PhonePwaPlan.dc.html` + `grf.css` | Design source. Read it as text: every size and colour is inline; `renderVals()` holds the logic and the rules. Fonts there point at `/_blob/…`: they are Sarabun 400/700, already in the app. |
| `icons/` | Glyphs and the SF Symbol to prefer (`icons/README.md`) |
| `assets/sample-data.json` | The board's stations, agenda, deadlines and type colours as JSON, for the demo flag, previews and tests |

## Build

### 1. New screen and where it goes
- Add `PWAPlanPhoneView` (suggested path `TCRoof/Views/Survey/PWAPlan/`, split into `+Schedule`, `+MP`, `+Due` files
  like `PlanCalendar+Phone.swift`).
- In `PWAPhoneTabs.root`: `case .plan:` shows `PWAPlanPhoneView()` when `horizontalSizeClass == .compact`, otherwise
  `MPOverviewView()` as today.
- The page owns its header (no navigation bar), sits on `Theme.phonePage`, and leaves room for the dock exactly like the
  PWA home (content bottom padding 108, the dock and `TCDockFade` come from `PWAPhoneTabs`).
- Rows open the existing screens; the board's `href`s map to:
  - install / check rows and Gantt rows → the station (`JobDetailView` via the same `station` destination the home uses,
    or `MPScheduleScreen(job:)` for Gantt rows — say which you used)
  - document rows → `StationDocsScreen(job:)`
  - survey rows → the survey job
  - test rows (`3.1 Pre-Commissioning`) → the IEC 62446 test screen if it exists, otherwise the station
  - the daily-report reminder → `DailyReportListView` (first station without today's report, like `openDailyReports`)

### 2. Header and pills (all views)
- Header: reuse the PWA home header (`TCPWAHeader` + the growing search button). Title `แผนงาน PWA`, subtitle
  `การประปาส่วนภูมิภาค`. Search filters the current view by MP number or station name.
- View switch (segmented, same as the PWA home's stage switch): one track `#E6ECF3`, radius 22, padding 3, height 44,
  12 pt top / 16 pt sides. Three equal segments 38 high, radius 19, label 13 + count 12 bold as plain text after it:
  - `ตารางงาน` + today's item count · `แผน MP` + stations with a plan · `กำหนดส่ง` + open deadlines in the next 2 weeks
    (this count is `dangerText` when any is late).
  - Selected: white segment with a 1 pt soft shadow (`0 1 3 navy 16 %`), `navy` 700, count `primary`. Unselected: no
    fill, `inkMuted` 600. Build it once as a `TCSegmented` variant with counts and use it on the home, plan and docs pages.
- **Only on `กำหนดส่ง`** a 44 × 44 round filter button sits at the end of the same row (§5). The pills shrink to make room.

### 3. `ตารางงาน`
The page is a fixed calendar card on top and **one scrolling list of days** under it. Only the list scrolls.

**Calendar card** (surface, 1 pt `borderSubtle`, radius 16, padding 8/6):
- Top row: `‹` · title · `›` on the left (arrows 40 × 44, `primary`), a `สัปดาห์ | เดือน` segmented switch on the right
  (same look as §2, segments 38 high, label 13).
  - Week: title `12–18 ต.ค. 2569` (15 bold) with `สัปดาห์ที่ 42` under it (11.5 600 `primary`) — the ISO week number.
  - Month: title `ตุลาคม 2569` only. Buddhist-era years.
- **Week view**: 7 cells Mon–Sun, min height 62, radius 12: weekday 11, number 17 bold, then the colour bars.
- **Month view**: weekday header row (11, weekend muted), then a Mon-first grid of the month (blank cells before the 1st),
  cells min height 46, radius 10, number 15 bold, then the colour bars. A legend under the grid: a 12 × 4 bar + label
  per job type.
- Cell states (both views): selected `navySolid` fill, white text, white bars · today (not selected) `primarySoft` fill,
  `primary` text · Sat/Sun muted `#9FB3CC`.
- **Colour bars** (`states/14`, `15`) replace dots. Bars are 4 pt high, 2 pt apart, in the job type's ink colour:
  - Lane 1 is always `ติดตั้ง`. Lanes 2–3 hold the other types of that day.
  - A type that runs on consecutive days is **one continuous line** across those cells within the same week row:
    square ends where it continues, 2 pt rounded ends where it starts and stops. Keep a run in the same lane for its
    whole length (pack runs per week row, earliest first, into lanes 2–3).
  - The selected day breaks runs (its bars are white inside the navy cell).
  - Draw it as one overlay per week row (`Canvas` or a `Path` per run) rather than per-cell pieces, so the joins are clean.
- Tapping a day selects it **and scrolls the list to that day** (smooth). Switching week → month keeps the day; month →
  week jumps back to today if the day is outside the shown week.

**List heading row** (fixed, above the list): `งานสัปดาห์นี้` / `งานทั้งเดือน` (16 bold) + total
(`15 รายการ · เลื่อนดูได้`, or `N จาก M รายการ` when filtered) and the 44 round filter button at the right.
- Filter button states — normal: surface + `borderSubtle`; open: `primarySoft` + 1 pt `primary`; filtered: `navySolid`
  with white glyph and an 8 pt orange (`Theme.warning`, `#F08C00`) dot top-right with a 2 pt ring. Same as the PWA home.
- **Filter popover** `กรองตารางงาน` (300 wide, radius 18, 1 pt `borderOutdoor`, no shadow, arrow under the button):
  `ล้าง`; `ประเภทงาน` 3-column grid of 44-high chips with colour dot and count; `ทีม` segmented
  `ทุกทีม · A · B · C · TC`; primary button `แสดง N รายการ`. The filter applies to every day in the list.
  Reuse the PWA home's popover presentation (`presentationCompactAdaptation(.popover)`).
- When filtered, removable chips (`ติดตั้ง ✕`, `ผู้รับเหมา A ✕`; 30 high, `primarySoft`, `primary` 12 bold) sit under the row.

**Day list** (`ScrollViewReader` + `LazyVStack`, bottom inset so the last day can reach the top):
- Every day of the range (week: 7 days, month: the whole month), in order. Each day = a header + its rows.
- Day header: `วันพฤหัสบดี 15 ต.ค.` (13 bold) + count (12 muted); `· วันนี้` after today. The header of the selected
  day is `primary` with a 6 pt `primary` dot before it.
- Rows sorted by start time. A day with nothing: dashed 12-radius row `ไม่มีงาน` (`ไม่มีงานในตัวกรองนี้` when the
  filter hid its rows).
- **Scroll-spy:** the day whose header is at (or just above) the top of the list is the selected day, so the calendar
  highlight follows the scroll (`states/04`). Ignore scroll events while a tap-triggered smooth scroll is running.
- On first appear the list is at today.

**Agenda rows** (surface card, radius 16, padding 10/12, gap 10):
- left 44 pt column: start `08:00` (14 bold), end `–17:00` (11 muted)
- 3 pt bar in the type colour
- line 1: type chip (11 bold, type fill/ink) · ref (`MP 189` / `NO.224` / `รายงาน`, 12 bold muted) · status at the right
  (11 bold; colours from `STT` in the board: `กำลังทำ` primary, `นัดแล้ว`/`ตามแผน` success, `รอ` muted, `ต้องยื่น` warning text,
  `เตือน` danger text)
- line 2: title 14 bold, one line · line 3: subtitle 12 muted, one line

**Job types** (board `TY`, also in `sample-data.json`). Add them as `Theme` tokens if missing, never hex in views:

| key | Label | Ink | Fill | Source in the app |
|---|---|---|---|---|
| `ins` | `ติดตั้ง` | `#1F6FB5` | `#E3EEF8` | MP tasks 2.x planned that day (`MasterSchedule.plan`), one row per station |
| `srv` | `สำรวจ` | `#0E7C86` | `#E0F4F5` | PWA survey appointments (`Job.surveyDate`) |
| `chk` | `ตรวจรับ` | `#6B4FBB` | `#EFEBFA` | Inspections by the PWA representative, if stored; otherwise leave out and ask |
| `doc` | `เอกสาร` | `#9A4A06` | `#FFF3E6` | Document due dates (same source as §5) |
| `tst` | `ทดสอบ` | `#1F6B43` | `#E8F5EE` | MP task 3.1 Pre-Commissioning / IEC 62446 test date |
| `ntf` | `เตือน` | `#B42318` | `#FDECEA` | Today only: stations without today's daily report (`sentDailyReportToday`), at 16:00, one row listing them |

Team filter: `A`–`D` = contractor (where v2 found it), `TC` = our own teams (`TCRxx`).

### 4. `แผน MP`
**S-curve card** (radius 16, padding 12/14):
- `ความก้าวหน้าทั้งโครงการ` (15 bold) + `สัปดาห์ 11/20` at the right (project week / total weeks).
- `จริง 47%` (20 bold primary) · `แผน 48%` (20 bold navy) · at the right `ช้ากว่าแผน 1%` (danger text) or `ตามแผน`
  (success). Both are **kWp-weighted** averages, the same maths as `MPOverviewView.totals`.
- Chart 120 high: gridlines 0/25/50/75/100 % (`#EEF2F7`, labels 9 pt `#9FB3CC`), month labels under it, plan = dashed
  2 pt `#9FB3CC`, actual = 2.6 pt `primary` up to today, today = 1.5 pt red line labelled `วันนี้`. Legend under it.
  - Plan curve: weekly kWp-weighted planned % from `MasterSchedule.plannedPoints` over all stations. Actual: the same from
    `scheduleActual`. The board's logistic curve is only a stand-in.
  - Use Swift Charts (`LineMark` + `RuleMark`) or a `Path`; keep the look.

**`รายสถานี` card** (`เรียงตามวันส่งมอบ`): month header (`ก.ย. ต.ค. พ.ย. ธ.ค.`) over a shared time axis, then one row per
station sorted by due date, min height 30:
- left 90 pt: short name (12 bold) / `MP 189 · ผู้รับเหมา A` (10 muted)
- bar (`icons/gantt-row.svg`): track `#E3E9F1` from start to due, actual fill (`danger` when behind by ≥ 2 %, else
  `primary`), navy 2 × 14 plan tick, 1.5 pt red today line across every row
- right 40 pt: due `15/10` (11 bold, danger text when behind)
- Show 8, then `อีก N สถานี · เลื่อนดู` — on device just let the list scroll and drop that line.
- Tapping a row opens `MPScheduleScreen(job:)`.

### 5. `กำหนดส่ง`
- Groups `สัปดาห์นี้` (`12–18 ต.ค. · รวมที่เลยกำหนด`: this week plus anything overdue) and `สัปดาห์หน้า` (`19–25 ต.ค.`).
  Group heading 14 bold + range 12 muted.
- Row card (radius 16, padding 8/12): date tile 46 wide (day 16 bold over month 10, tinted by tone) · title 14 bold /
  subtitle 12 muted, one line each · status chip at the right.
- Tones (board `CS` / `DS`): `late` danger, `risk` warning, `ok` success chip on a navy-tinted date tile.
- Sources: station due dates (handover = MP end / `InstallInfo.dueDate`; `late` if past, `risk` if actual < plan) and
  document deadlines from the PWA documents (`StationDocs…`: แจ้งเทศบาล, พค.2, ขนานไฟ). If a deadline has no stored date,
  leave it out and list it in your report.
- **Filter**: 44 round button at the end of the pill row (only on this view). It opens a 220-wide menu right-aligned
  under it (radius 12, 1 pt `borderOutdoor`): `ทั้งหมด` / `ส่งมอบ` / `ยื่นเอกสาร`, each 44 high with a check and
  `N รายการ`. Picking closes it. Filtered = navy button + orange dot (state 09). `TCDropdownList` may fit.

### 6. What changed since the v2 draft
- View pills → one segmented switch with plain counts (§2).
- `ตารางงาน`: week/month switch, week number, colour bars with continuous runs (instead of dots), one scrolling list of
  days with scroll-spy (instead of one day's agenda), agenda filter popover + chips.
- `กำหนดส่ง`: the full-width `แสดง ทั้งหมด 9 ▾` row is gone; its filter is the round button at the end of the switch row.
- `แผน MP`: unchanged apart from spacing.

### 7. Debug launch arguments (add to `CLAUDE.md` next to `-surveyHomeTab`)
- `-pwaPlanView schedule|mp|due` picks the pill (with `-screen pwa -surveyHomeTab plan`).
- `-pwaPlanCalendar week|month`, `-pwaPlanDay 2026-10-15` (selects and scrolls to it), `-pwaPlanFilter open|ins-A`,
  `-pwaPlanDueFilter open|doc`, `-pwaPlanDemo YES` (seed `assets/sample-data.json` dated from today; `monthTypesByDay`
  drives the bars). These reproduce states 01–12.

## Rules (from `CLAUDE.md`)
- Build from `TCRoofUI` components and `Theme` tokens; no hex literals, no `Color.white` in views.
- Sarabun via `Font.sarabun`; touch targets ≥ 44; light mode only.
- VoiceOver: day cells read `วันจันทร์ 12 ต.ค. · 3 ประเภทงาน`; Gantt rows read `สถานี… · จริง 38% แผน 50% · ส่งมอบ 15/10`
  (see the board's `aria-label`s).
- Build with your own `-derivedDataPath` (CLAUDE.md). Add unit tests for the weighted S-curve and the deadline grouping
  (overdue goes into `สัปดาห์นี้`).

## Check list
- [ ] iPhone `แผนงาน` tab opens `PWAPlanPhoneView`; iPad still opens `MPOverviewView`
- [ ] Segmented view switch with counts; filter button at its end only on `กำหนดส่ง`
- [ ] Week strip with `สัปดาห์ที่ N`; `สัปดาห์ / เดือน` switch; month grid with legend
- [ ] Colour bars: continuous runs per type within a week row, lane-stable, broken by the selected day
- [ ] Day list scrolls; scroll-spy moves the highlight; tapping a day scrolls the list
- [ ] Agenda filter popover, chips, `ล้าง`, per-day empty rows
- [ ] S-curve from real plans, kWp-weighted; today line; variance text
- [ ] Gantt rows sorted by due date with plan tick and behind colour
- [ ] Deadline groups with overdue in `สัปดาห์นี้`; filter menu and filtered state
- [ ] Screenshots of states 01–12 on an iPhone simulator match the PNGs (put yours in `screenshots/`)

## Report back
1. Which data you found for each job type and deadline kind, and which you left out.
2. Where rows navigate.
3. Anything on the board you could not match, with a screenshot.
