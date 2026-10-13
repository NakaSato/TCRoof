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
| `preview.png` = `states/01-schedule-today.png` | Default: `ตารางงาน`, today selected, every type and team. @2x (780 × 1688) |
| `states/02-schedule-filter-open.png` | Agenda filter popover open (`กรองตารางงาน`) |
| `states/03-schedule-filtered-install-A.png` | Type `ติดตั้ง` + team `A`: navy filter button with orange dot, removable chips under the heading, count `1 จาก 7 รายการ` |
| `states/04-schedule-day-13.png` | อ. 13 selected (today keeps a blue tint) |
| `states/05-schedule-filter-empty.png` | A filter with no match: dashed empty card with `ล้างตัวกรอง` |
| `states/06-mp.png`, `12-mp-crop.png` | `แผน MP`: S-curve card and `รายสถานี` Gantt |
| `states/07-due.png` | `กำหนดส่ง`: `สัปดาห์นี้` / `สัปดาห์หน้า` groups; the filter button sits at the end of the pill row |
| `states/08-due-filter-open.png` | Deadline filter menu open (right-aligned under the button) |
| `states/09-due-filtered-docs.png` | `ยื่นเอกสาร` only: button navy with orange dot |
| `states/10-search-open.png` | Header search expanded (same component as the PWA home) |
| `states/11-header-tabs-crop.png`, `13-dock-crop.png` | Close-ups |
| `states/01-schedule-today.pdf`, `06-mp.pdf`, `07-due.pdf` | **Vector** 390 × 844 renders. Measure here. |
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
- Pill row: 12 pt top, 16 pt sides, gap 6. Three equal pills, height 44, radius 22, label 13 bold (selected) / 600,
  count badge 20 high radius 10:
  - `ตารางงาน` + today's item count · `แผน MP` + stations with a plan · `กำหนดส่ง` + open deadlines in the next 2 weeks
    (this badge is red-tinted, `Theme.dangerSoft` / `dangerText`, when any is late).
  - Selected: `Theme.navySolid` fill, white text, badge white 22 %. Unselected: `Theme.surface`, 1 pt `borderSubtle`.
  Use `TCCapsuleTabs` if it can show counts; otherwise extend it, don't fork it.
- **Only on `กำหนดส่ง`** a 44 × 44 round filter button sits at the end of the same row (§5). The pills shrink to make room.

### 3. `ตารางงาน`
**Week strip card** (surface, 1 pt `borderSubtle`, radius 16, padding 8/6):
- Row: `‹` · `ตุลาคม 2569 · สัปดาห์ที่ 42` (15 bold, centred) · `›`; arrows 44 × 36, `Theme.primary`. Buddhist-era year.
- 7 day cells (Mon–Sun), min height 62, radius 12: weekday 11, number 17 bold, up to 3 dots (5 pt) — one per job type on
  that day, in the type's colour.
  - selected: `navySolid` fill, white text, white dots · today (not selected): `primarySoft` fill, `primary` text ·
    Sat/Sun: muted `#9FB3CC` text.

**Day heading row**: `วันจันทร์ 12 ต.ค. · วันนี้` (16 bold) + count (`7 รายการ`, or `1 จาก 7 รายการ` when filtered), filter
button at the right (44 × 44 round, `icons/filter.svg`).
- Filter button states — normal: surface + `borderSubtle`; open: `primarySoft` + 1 pt `primary`; filtered: `navySolid`
  with white glyph and an 8 pt orange (`Theme.warning`, `#F08C00`) dot top-right with a 2 pt ring. Same as the PWA home.
- **Filter popover** `กรองตารางงาน` (300 wide, radius 18, 1 pt `borderOutdoor`, no shadow, arrow under the button):
  - header `กรองตารางงาน` + `ล้าง` (disabled grey when nothing is set)
  - `ประเภทงาน`: 3-column grid of 44-high chips: `ทั้งหมด` + one per type, each with a colour dot and its count for the day
    (counts respect the team filter; zero-count chips are greyed but tappable)
  - `ทีม`: segmented `ทุกทีม · A · B · C · TC` (track `segmentTrack`, selected white)
  - primary button `แสดง N รายการ` closes it.
  - Reuse the PWA home's popover presentation (`presentationCompactAdaptation(.popover)`).
- When filtered, removable chips (`ติดตั้ง ✕`, `ผู้รับเหมา A ✕`; 30 high, `primarySoft`, `primary` 12 bold) sit under the heading.

**Agenda rows** (surface card, radius 16, padding 10/12, gap 10):
- left 44 pt column: start `08:00` (14 bold), end `–17:00` (11 muted)
- 3 pt bar in the type colour
- line 1: type chip (11 bold, type fill/ink) · ref (`MP 189` / `NO.224` / `รายงาน`, 12 bold muted) · status at the right
  (11 bold; colours from `STT` in the board: `กำลังทำ` primary, `นัดแล้ว`/`ตามแผน` success, `รอ` muted, `ต้องยื่น` warning text,
  `เตือน` danger text)
- line 2: title 14 bold, one line · line 3: subtitle 12 muted, one line
- Empty / no match: dashed card `ไม่มีงานในตัวกรองนี้ · ล้างตัวกรอง` (state 05); a day with nothing at all: `ไม่มีงานในวันนี้`.

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
- `ตารางงาน`: the agenda filter (round button + `กรองตารางงาน` popover + removable chips + empty state) is new; the draft had none.
- `กำหนดส่ง`: the full-width `แสดง ทั้งหมด 9 ▾` dropdown row is gone; its filter is the round button at the end of the
  pill row.
- `แผน MP`: unchanged apart from spacing.

### 7. Debug launch arguments (add to `CLAUDE.md` next to `-surveyHomeTab`)
- `-pwaPlanView schedule|mp|due` picks the pill (with `-screen pwa -surveyHomeTab plan`).
- `-pwaPlanDay 2026-10-13`, `-pwaPlanFilter open|ins-A|empty`, `-pwaPlanDueFilter open|doc`, `-pwaPlanDemo YES` (seed
  `assets/sample-data.json` dated from today). These reproduce states 01–10.

## Rules (from `CLAUDE.md`)
- Build from `TCRoofUI` components and `Theme` tokens; no hex literals, no `Color.white` in views.
- Sarabun via `Font.sarabun`; touch targets ≥ 44; light mode only.
- VoiceOver: day cells read `วันจันทร์ 12 ต.ค. · 3 ประเภทงาน`; Gantt rows read `สถานี… · จริง 38% แผน 50% · ส่งมอบ 15/10`
  (see the board's `aria-label`s).
- Build with your own `-derivedDataPath` (CLAUDE.md). Add unit tests for the weighted S-curve and the deadline grouping
  (overdue goes into `สัปดาห์นี้`).

## Check list
- [ ] iPhone `แผนงาน` tab opens `PWAPlanPhoneView`; iPad still opens `MPOverviewView`
- [ ] Pills with counts; filter button appears only on `กำหนดส่ง`
- [ ] Week strip: selected / today / weekend styles, type dots
- [ ] Agenda filter popover, chips, `ล้าง`, empty state
- [ ] S-curve from real plans, kWp-weighted; today line; variance text
- [ ] Gantt rows sorted by due date with plan tick and behind colour
- [ ] Deadline groups with overdue in `สัปดาห์นี้`; filter menu and filtered state
- [ ] Screenshots of states 01–10 on an iPhone simulator match the PNGs (put yours in `screenshots/`)

## Report back
1. Which data you found for each job type and deadline kind, and which you left out.
2. Where rows navigate.
3. Anything on the board you could not match, with a screenshot.
