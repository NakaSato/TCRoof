# Claude Code task: iPhone install-team calendar (แผนก่อสร้าง · ปฏิทินทีมติดตั้ง), v10

> **How to use:** open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/tcroof-plan-calendar-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels; keep them exactly.

**Example data.** Every name, code, team, time and date in the previews is example data:
- the board's `SEEDS` and `TIMES`, also in `assets/sample-data.json`
- "today" is fixed at 30 กันยายน 2569 (2026-09-30)

In the app, use the real `Job` records (`surveyDate`, `installStart`, `installEnd`, `installDays`, `team`) and the real date.

## Context

`PlanCalendarView` (`TCRoof/Views/Plan/PlanCalendarView.swift`, parts in `PlanCalendar+Parts.swift`) already switches on `horizontalSizeClass`:
- `padBody` is the iPad wall planner (`docs/ui/plan-calendar`).
- `phoneBody` is a first compact layout:
  - `TCGradientHeader` with counts
  - `phoneMonthCard`, using `PlanMonthStepper` and `PlanPhoneDayCell`, with a dot per team and a ring for surveys
  - horizontally scrolling `PlanTeamChip`s
  - the shared `dayPanel`

The board `iPhone · แผนก่อสร้าง · ปฏิทินทีมติดตั้ง` replaces that compact layout. Its changes:
- a **เดือน / สัปดาห์** segmented switch
- a **team dropdown** instead of the chip row
- **team-coloured range lines** under each calendar week, one lane per install job, instead of dots
- a **pink diamond** for survey appointments
- a **week view** with labelled bars
- a quieter **agenda** list for the selected day

**Compact width only.** Change only `phoneBody` and add phone-only parts. `padBody`, `calendarCard`, `monthGrid`, `PlanWeekRow`, `PlanDayCell`, `PlanSurveyRow`, `PlanDayJobRow` and the iPad `dayPanel` must render exactly as before. If a part is shared, add a compact variant instead of editing it.

**Before you start.** Use code-review-graph first (per `CLAUDE.md`):
- callers of `PlanCalendarView`, `phoneBody`, `PlanPhoneDayCell`, `PlanMonthStepper`, `PlanTeamChip`, `dayPanel`, `TCGradientHeader`, `TCHeaderIcon`, `PhoneTabs`
- `tests_for` on anything you touch

Then read the source.

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` = `states/01-month-today.png` | Default: month view, today (30 ก.ย.) selected, every team. @2x (780 × 1688) |
| `states/01a-header-controls-crop.png` | Header, month title row, segmented switch and team button |
| `states/01b-month-grid-crop.png` | Month grid: day numbers, survey diamonds, range lines in lanes, legend |
| `states/01d-agenda-crop.png` | Agenda heading and the two row kinds (survey, install with day progress) |
| `states/01c-month-today-full.png` | Whole scroll content (@1x) |
| `states/02-month-day-installs.png` | 1 ต.ค. selected: one survey and two installs (`วัน 3/4`, `วัน 1/5`); today shows as blue text only |
| `states/03-team-menu-open.png`, `03a-team-menu-crop.png` | Team dropdown open (`ทุกทีม` selected, with a check) |
| `states/04-team-filter-TCR01.png` | `ทีม 01` filter. The button shows a green dot, the legend shows only `01`, and lines, diamonds and agenda are filtered |
| `states/05-week.png`, `05a-week-strip-crop.png` | Week view for the week containing the selected day: title `27 ก.ย. – 3 ต.ค.`, labelled bars |
| `states/06-week-day-installs.png` | Week view, 1 ต.ค. selected |
| `states/07-next-month.png` | `›` once (ตุลาคม 2569), 16 ต.ค. selected. Up to 3 lanes; lines continue across weeks |
| `states/08-empty-day.png` | A day with nothing: `ไม่มีนัดในวันนี้` |
| `states/01-month-today.pdf`, `05-week.pdf` | **Vector** 390 × 844 renders. Measure here. |
| `PhonePlanCal.dc.html` | Design source. Read it as text; every style value is inline. `renderVals()` holds all the logic. Later `// vN` blocks override earlier ones, and **v10 at the bottom is the final state**. |
| `preview.html` + `grf.css` | Static render of the default state |
| `icons/` | SVG glyphs with the SF Symbol to prefer (`icons/README.md`) |
| `assets/sample-data.json` | The example jobs as JSON, for previews and tests |

## Layout (compact), top to bottom

Page background `Theme.background` (`#F3F6FA`). Content is one `ScrollView`:
- padding 0 / 16 / 20 (top / sides / bottom)
- vertical gap 10
- the bottom clears the tab bar

### 1. Header (`TCGradientHeader`)

- **Title** `ปฏิทินทีมติดตั้ง`.
- **Subtitle** `แผนก่อสร้างและเอกสาร`. This is static on the board; the counts move out of the header. See open question 1.
- **Back chevron**: as `TCGradientHeader` already does (shown only when pushed). On the board it goes to the home screen.
- **Trailing button**: `TCHeaderIcon("list.bullet")` → `PlanListView()`, accessibility label `รายการแผนก่อสร้าง`. This is the same link as today.

### 2. Month title row

Row with gap 2 and 12 pt top padding.

- **Title**:
  - month view: `กันยายน` 22 bold `Theme.navy` with a space and `2569` in weight 500 `Theme.inkStrong` (`#44546A`)
  - week view: the range only, with no year:
    - same month: `1–7 ต.ค.`
    - otherwise: `27 ก.ย. – 3 ต.ค.`, using Thai short months
  - one line, truncates
- **`วันนี้`** text button:
  - 44 high, horizontal padding 10
  - 14 bold `Theme.primary`
  - dimmed to 40 % opacity when today is already selected and the current month is shown (still tappable)
  - action: go to the current month and select today
- **`‹` and `›`** buttons:
  - 44 × 44 circles with no fill
  - glyph 20 pt, `Theme.navy`, stroke 2.4
  - labels `ก่อนหน้า` / `ถัดไป`
  - in month view they step one month; the selection stays
  - in week view they step the selection by 7 days and keep the month in sync with it
- This replaces `PlanMonthStepper` on compact. Keep the existing horizontal swipe on the grid to change month (or week in week view).

### 3. Controls row: segmented switch + team button

HStack with gap 8.

**View switch** (`role=tablist`), flexible width:
- **Track**: height 44, padding 2, gap 2, radius 12, fill `#EBEFF5`. Use `Theme.segmentTrack` (`#EEF2F7`) unless you want an exact match; the difference is negligible.
- **Columns**: 2 equal columns, `เดือน` and `สัปดาห์`.
- **Selected segment**: white, radius 10, shadow `0 1 3 rgba(22,50,92,0.25)`, 14 pt weight 800 `Theme.navy`.
- **Unselected segment**: transparent, 14 pt weight 700 `Theme.inkStrong`.
- **Accessibility**: `.isSelected` on the active segment.
- If the segmented control from the survey-list task exists (`TCSegmented`), reuse it with a 2-item variant.

**Team button**:
- height 44, padding 0 10 0 12, radius 12, white, 1 pt `#D5DDE7` border (≈ `Theme.borderSubtle`)
- 14 bold `Theme.navy`
- content: a 10 pt team dot (hidden for all teams), the label `ทุกทีม` or `ทีม 01` … `ทีม 04`, and `chevron.down` 16 pt `Theme.inkStrong`
- accessibility label `กรองทีม <label>`; expanded state

**Team menu** (popover or overlay):
- anchored under the button's right edge (top + 50), width 170, padding 6, radius 14
- white, 1 pt `#D5DDE7` border, shadow `0 10 28 rgba(22,50,92,0.18)`
- **5 rows**: `ทุกทีม`, `ทีม 01`, `ทีม 02`, `ทีม 03`, `ทีม 04`
- **Each row**: height 44, padding 0 10, radius 10, gap 10, 14.5 pt weight 600 `Theme.navy`
  - a 10 pt dot: `team.color`, or for `ทุกทีม` a 4-colour split dot (`AngularGradient`)
  - the label
  - `checkmark` 18 pt `Theme.primary` on the selected row
- **Selected row fill**: `#EEF3F9`. Use `Theme.unreadRow` (`#F3F8FD`) or add a `rowSelected` token.
- Picking a row sets the filter and closes the menu. Tapping outside closes it.
- A SwiftUI `Menu` is acceptable if it shows the dot, label and checkmark. A custom overlay is closer to the board.
- **Remove** the horizontal `PlanTeamChip` row on compact.

### 4. Calendar card

White (`Theme.surface`), radius 20, padding 10 / 8.

#### 4a. Month view

- **Weekday header** `อา จ อ พ พฤ ศ ส`: 7 equal columns, 11.5 pt weight 600 `#8A97AA` (≈ `Theme.muted`), 6 pt bottom padding. **No red Sunday** in v10.
- **Week rows**: one per calendar week, with 6 pt between rows. Each row is a VStack (spacing 2) of a day strip and a lines block.
- **Day strip**: 7 equal buttons, each 44 high. In each button, a VStack (spacing 3, centred) of:
  - **Number**: in a 34 pt circle, 15.5 pt weight 500.
    - selected: `Theme.navy` fill, white, weight 700
    - today (not selected): `Theme.primary` text, weight 700, no fill or ring
    - in month: `Theme.navy`
    - outside the month: `#C3CBD6`
  - **Survey mark**: a 6 pt high row holding only the **survey diamond** when the day has at least one survey appointment (team-filtered, in-month days only). The diamond is 6 × 6, radius 1, rotated 45°, scale 0.9, colour `#D6336C` (new token `Theme.survey`, see Tokens).
  - **No install dots** in the month view (v10). Installs are the lines below.
- **Lines block**: a 7-column grid. Each lane is a 5 pt row, with 3 pt between lanes and min height 5.
  - Each install job overlapping that week draws one **range line**:
    - spans from its first to its last day within the week
    - 5 pt high, radius 3, solid `team.color`
    - 5 pt inset at the ends where the job starts or ends
  - Where the job continues from the previous week or into the next, that end is square and has no inset, so the line reads as continuous across rows (see `states/07-next-month.png`).
  - **Lanes**: sort the visible jobs by `installStart` and give each the first lane whose last job ended before this one starts (greedy interval packing over the visible range). The lane stays the same for a job across weeks.
  - Out-of-month days still draw their lines.
  - Accessibility: each line `ทีม 01 · <nickname> · ช่วงติดตั้ง`.
- **Day accessibility**: `<d> <เดือน>` plus `วันนี้` for today. Better: also say install / survey counts, as `PlanPhoneDayCell` does today.
- Tapping any day selects it. Out-of-month days do not change the month on the board; see open question 3.

#### 4b. Week view (the week containing the selected day, Sunday first)

- **Day strip**: 7 buttons, 66 high. In each, a VStack (spacing 4) of:
  - **Weekday** 11.5 / 600 `#8A97AA`
  - **Number**: 36 pt circle, same styling as the month view
  - **Marks**: a 6 pt row, gap 3:
    - up to 2 team dots (6 pt, `team.color`) for installs running that day
    - the survey diamond if any
- **Bars**: a VStack (spacing 2, top padding 2), one row per install job overlapping the week. Each row is a 7-column grid with one bar spanning the job's days in that week.
  - **Bar shape**: height 20, radius 5, horizontal margin 3, padding 0 8.
  - **Text**: 11 pt weight 800, one line, truncates.
  - **Colours**: fill `team.color` at 20 % (`33`), text `team.color`, a 4 pt solid `team.color` leading edge (inset).
  - **Label**:
    - `TCR01 · <project>` when the bar spans 3 or more days
    - just `01` when it spans 1–2 days

#### 4c. Legend (both views)

- Centred, gap 10, 8 pt top padding, 11.5 pt weight 700 `#6B7A90` (≈ `Theme.inkMuted`).
- For each visible team (all, or only the filtered team): a 14 × 5 radius-3 swatch in `team.color`, then `01` … `04`.
- Then the diamond + `สำรวจ`.

### 5. Agenda for the selected day

Section with gap 8 and padding 8 / 0 / 4.

- **Heading row** (baseline aligned):
  - left: `30 กันยายน 2569` (`thaiLong`), 18 bold `Theme.navy`
  - right: 13 pt `Theme.inkStrong`. Parts are joined with ` · ` and each is shown only when non-zero:
    - `สำรวจ n`
    - `ติดตั้ง n`
    - `n ทีม` (distinct teams installing)
- **Rows**: survey appointments first (sorted by time), then installs running that day.
- **Row container** (both kinds):
  - min height 64, padding 10 / 12, radius 14
  - white, 1 pt `#D5DDE7` border, HStack gap 12
  - a 4 pt wide leading rule, radius 2, full height
- **Survey row**:
  - rule `#D6336C`
  - title: project 15.5 bold `Theme.navy`
  - subtitle `นัดสำรวจ · ทีม TCR03`, 13 `Theme.inkStrong`
  - right: `09:30 น.` 15 bold, tabular digits
  - tap → `SurveyFormView` for that job (as `PlanSurveyRow` does on iPad)
  - label `นัดสำรวจ <project> <time>`
- **Install row**:
  - rule `team.color`
  - title: project
  - subtitle `งานติดตั้ง · ทีม TCR01`
  - progress: 5 pt top margin, one 4 pt segment per install day, gap 3, radius 2
    - days up to and including the selected day: `team.color`
    - later days: `#E6EBF2` (`Theme.headerLine`)
  - right column (trailing aligned):
    - `วัน 2/4`, 15 bold
    - `เหลือ 2 วัน`, 12 `Theme.inkStrong`
    - use `job.installDay(on:)` and `installDays`
  - tap → the plan job detail (`JobDetailView` / the same destination as `PlanDayJobRow` today)
  - label `งานติดตั้ง <project> วันที่ n จาก N`
- **Empty**: a 1.5 pt dashed `#D5DDE7` rounded rectangle (radius 14), padding 20 / 16, centred `ไม่มีนัดในวันนี้` 14 `Theme.inkStrong`.
- On compact this replaces the shared `dayPanel(scrolls:)`. Keep the iPad panel unchanged.

## Behaviour summary (`renderVals()`)

**State**:
- `vm`: `month` | `week`, default `month`
- `sel`: the selected day, default today
- `mo`: month offset
- `tf`: team filter, `all` or a team
- `tOpen`: menu open

**The team filter applies to everything**: lines, bars, diamonds, legend and agenda.

**Model**:
- An install job runs from `installStart` through `installEnd` (= start + days − 1).
- A survey is on `surveyDate`'s day.
- Keep the data helpers (`jobs(on:)`, `surveys(on:)`, `gridData`) and add what the lanes need in a small testable type, for example `PlanLanes.assign(_ jobs:) -> [Job.ID: Int]`, rather than inside the view.

## Tokens

No hex in views. Add missing tokens to `TCRoofKit/Sources/TCRoofUI/Theme.swift` with dark values:

| Use | Light | Token |
|---|---|---|
| survey diamond, survey rule | `#D6336C` | **new** `survey` (dark e.g. `#F06595`) |
| card / menu / row border | `#D5DDE7` | `borderSubtle` (`#DDE4ED`), close enough, or add `borderCard` |
| weekday labels | `#8A97AA` | `muted` (`#7A8BA3`) |
| secondary text | `#44546A` | `inkStrong` (exists) |
| legend text | `#6B7A90` | `inkMuted` (exists) |
| out-of-month day number | `#C3CBD6` | **new** `dayOutside` (dark `#3A4757`) or `chevron` (`#AAB6C5`) |
| segmented track | `#EBEFF5` | `segmentTrack` (exists) |
| selected menu row | `#EEF3F9` | `hairline` (`#EEF2F7`) or new `rowSelected` |
| future progress segment | `#E6EBF2` | `headerLine` / `track` (exist) |

Team colours come from `Team.color` (`#2E9E5B`, `#8B3FD9`, `#2F6FDB`, `#F08A24`). The `ทุกทีม` split dot on the board uses slightly different purple and orange values; use `Team.color` for all four.

## Fonts

The board uses system fonts. The app uses `.sarabun(size, weight, relativeTo:)`; keep using it at the sizes above, as the existing phone views do.

## Rules

- Compact width only; iPad `PlanCalendarView` is pixel-identical to before.
- Thai UI text exactly as in the previews.
- Touch targets ≥ 44 pt.
- No model or sync changes.
- Keep `-homeTab plan` (`PhoneTabs`) working; use it to open this screen in the simulator.

## Acceptance

1. **Matches the board.** On an iPhone 16 simulator (390 × 844) launched with `-homeTab plan`, with the clock set to or seeded for the sample data, the screen matches `states/01-month-today.png`. Then:
   - selecting 1 ต.ค. matches state 02
   - the team menu matches 03
   - `ทีม 01` matches 04
   - `สัปดาห์` matches 05 and 06
   - `›` matches 07
   - an empty day matches 08
2. **Lanes.**
   - Overlapping installs get separate lanes.
   - A job keeps its lane across weeks.
   - Lines are continuous across week rows.
   - Unit tests for `PlanLanes` cover: no overlap → 1 lane; 3 overlapping → 3 lanes; a lane reused after a job ends.
3. **Navigation.**
   - Survey rows open `SurveyFormView`; install rows open the job detail.
   - `วันนี้` / `‹` / `›` behave as described in both views.
   - Both kinds of row are single VoiceOver elements with the labels above.
4. **iPad unchanged.** Compare iPad screenshots of `PlanCalendarView` before and after.
5. **Builds and tests pass.** `swift build`, `swift test` and the `CLAUDE.md` xcodebuild (with your own `-derivedDataPath`) pass with no new warnings.
6. **Summary.** Finish with:
   - the files changed
   - new tokens and components
   - remaining differences from the board
   - answers to the open questions

## Open questions (report back; don't block on them)

1. **Header counts.** The old phone header showed `n งานติดตั้ง · n นัดสำรวจ`; the board uses a static subtitle. Default: follow the board. The board's logic still computes `ติดตั้ง n งาน · สำรวจ n นัด`, so propose where it could go if wanted.
2. **NO.224 survey reports.** The current `dayPanel` also lists survey reports (`แบบ กปภ.`). The board shows only appointments. Default: keep reports as survey rows with the `แบบ กปภ.` badge on the right instead of the time.
3. **Out-of-month taps.** Should tapping a grey day also switch to that month? Default: select it and stay (as on the board).
4. **Dark mode.** The board is light only. Propose dark values for the new tokens.
