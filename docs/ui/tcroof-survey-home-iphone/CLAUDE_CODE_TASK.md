# Claude Code task: iPhone survey home (สำรวจหน้างาน · หน้าแรก · รายการงาน)

> How to use: open Claude Code in `~/Developments/TCRoof` and type
> `Follow docs/ui/tcroof-survey-home-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels; keep them exactly.

**Example data.** Names, codes, times, kW, distances, ETAs, the greeting and the draft progress in the previews are example data from the board's `SEEDS`, `TIMES` and `DRAFT`, and "today" is fixed at 30 Sep 2026. In the app, use the real `Job`, `surveyDate`, `surveyDraft` and the current date.

## Context
The root of the `สำรวจ` tab on iPhone is `PhoneSurveyList` (`TCRoof/Views/Survey/PhoneSurveyList.swift`). It was built from `docs/ui/tcroof-survey-list-iphone` and has:
- a gradient header with a count and a history button
- a `7 วัน / 30 วัน / ทั้งหมด` segmented filter
- a search field
- one `SurveyJobCompactCard` per job
- a teal `TCFab`

`SurveyListView` (`SurveyViews.swift:35`) shows it when `sizeClass == .compact`.

The board `iPhone · งานบ้าน · 1 หน้าแรก · รายการงาน` (`PhoneSurveyHome.dc.html`) redesigns this screen as a **home for the survey day**. From top to bottom:
1. A greeting header.
2. A **week strip** with the next appointment and the selected day's agenda.
3. A **compact list** of every job, with search and status chips.
4. A floating **glass dock** whose main button follows the next thing to do.

**Compact width only.** The iPad survey list (`padList`, `docs/ui/survey-list`) must stay pixel-identical.

**Use code-review-graph first** (per `CLAUDE.md`), then read the source:
- callers of `PhoneSurveyList`, `SurveyJobCompactCard`, `PhoneSearchField`, `TCGradientHeader`, `TCFab`, `tcFabPlacement`, `PhoneTabs`, `RecentSearches`, `RelativeDay`, `SurveyCardProgress`
- `tests_for` on anything you touch

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` = `states/01-default.png` | Default: today selected, `นัดถัดไป` card, status `ทั้งหมด`, a draft in progress, the dock. @2x (780 × 1688) |
| `states/01c-full-list.png` | The whole page scrolled out (@2x): the last row must clear the dock and the tab bar |
| `states/02-tomorrow.png` | Tomorrow selected. No `นัดถัดไป` block, because the next appointment is today; one agenda row |
| `states/03-day-empty.png` | A day with no appointments: `ไม่มีนัดสำรวจในวันนี้` |
| `states/04-search-open.png` | Search focused: 2 pt primary border and `ค้นหาล่าสุด` chips |
| `states/05-search-result.png` | Query `นพพร`: the count reads `1 งาน` and a clear button appears |
| `states/06-filter-confirmed.png` | Status chip `ยืนยันแล้ว` selected |
| `states/07-no-result.png` | No match: `ไม่พบงานที่ตรงกับ "สมหญิง"` |
| `states/08-sun-mode.png` | Outdoor high-contrast mode. It is in the board CSS but has **no toggle on the board**, so it is out of scope (see open question 5) |
| `states/01-default.pdf`, `states/04-search-open.pdf` | **Vector** renders at 390 × 844. Measure here. |
| `PhoneSurveyHome.dc.html` | Design source. Read it as text: every style value is inline, and `renderVals()` holds the logic for the week strip, next appointment, agenda, chips, search and dock. |
| `preview.html` + `grf.css` | Static render of the default state (text falls back to a system font without Sarabun) |
| `icons/` | SVGs for every glyph, with the SF Symbol to prefer (`icons/README.md`) |

## What to build (compact only)
Rebuild `PhoneSurveyList` to this design. You may rename it to `PhoneSurveyHome` if you update every caller. Keep the parts that already work:
- the recent-searches storage (`RecentSearches`, `@AppStorage("surveyList.recentSearches")`)
- `PhoneSearchField` (add parameters; do not fork it)
- the `NewJobView` sheet
- `JobDetailView` / `SurveyFormView` navigation

Page: background `Theme.background` (`#F3F6FA`). Scroll content padding 12 top / 16 sides, section gap 18.

### 1. Header (`TCGradientHeader`)
- `Theme.headerGradient`, white text, bottom corners 15. Padding 10 top / 10 trailing / 14 bottom / 18 leading. The gradient extends under the status bar.
- **Title**: `สำรวจหน้างาน`, 22 / 28 bold.
- **Subtitle**: `<greeting> · <date>`, 13 / 18 at 92 % opacity, one line, tail truncation.
  - Greeting by the local hour: `สวัสดีตอนเช้า` before 12:00, `สวัสดีตอนบ่าย` from 12:00 to 16:59, `สวัสดีตอนเย็น` from 17:00.
  - Date: weekday name without `วัน`, day, short month and Buddhist year, for example `พุธ 30 ก.ย. 2569`. Use `ThaiFormat` if it has this format; otherwise add one.
- **No trailing button** on the board. The current history button is removed. See open question 1 before you drop the history entry point.
- **Back chevron**: only when the screen is pushed; hidden on the tab root (as now).
- If `TCGradientHeader` cannot take a 22 pt title or these paddings, add parameters with the current values as defaults, so the other callers do not change.

### 2. Week card
**Section label** (shared style, reused in section 3):
- one row, 13 pt `Theme.inkMuted`, padding 0 / 4, gap 6 to the card
- leading `สัปดาห์นี้`
- trailing: the range `30 ก.ย. – 6 ต.ค.` (today to today + 6)

**Card**: `Theme.surface`, radius 16, no shadow, padding 8 top / 6 sides / 4 bottom, clipped.

**Week strip.** Seven equal columns, **rolling from today** (not Monday to Sunday). Each day is a button, min height 64, vertical stack with gap 3:
- **Weekday label**, 11.5 pt `Theme.inkMuted`: `วันนี้` for today; otherwise `อา จ อ พ พฤ ศ ส`.
- **Day number**, 16 pt tabular, in a 34 pt circle:
  - selected: `Theme.navy` fill, white, bold
  - today but not selected: `Theme.primary`, bold, no fill
  - other days: `Theme.navy`
- **Dot**, 6 pt, shown when the day has survey appointments: `Theme.survey` (`#D6336C`), or `Theme.primary` on the selected day. Keep the space when there is no dot.
- Tapping a day selects it. Today is selected by default.
- Accessibility: a tab group labelled `เลือกวัน`, with `.isSelected` on the selected day. Day label: `วันนี้ 30 ก.ย. นัด 1`, or `… ไม่มีนัด` when the day has no appointments.

After the strip: a 1 pt `Theme.borderSubtle` divider, margin 4 top / 10 sides.

**`นัดถัดไป` block.** The next appointment is the earliest job whose `surveyDate` is still ahead (`>= now`); on a tie, take the earlier time. Show the block **only when the selected day is that job's day** (compare `states/01` with `states/02`).
- **Label**: `นัดถัดไป`, 12.5 pt semibold `Theme.primary`, padding 10 / 10 / 2.
- **Row**: padding 2 top / 6 trailing / 8 bottom / 10 leading, gap 8.
  - **Text** (flex; tapping it opens `JobDetailView`; accessibility `รายละเอียดงาน <project>`):
    - `job.projectName`, 18 / 24 bold navy, one line
    - then a 14 / 20 line: `<RelativeDay label> HH:mm น.` bold `Theme.primary`, followed by ` · <province>` in `Theme.inkMuted`, for example `วันนี้ 09:30 น. · นนทบุรี`
  - **Call** button: 44 pt circle, `Theme.background` fill, `phone` glyph 20 pt `Theme.primary`. It opens `tel:`. Accessibility `โทรหาลูกค้า`.
  - **Navigate** button: the same style with the navigate glyph. It opens Apple Maps the same way `JobViews.swift` `mapsURL` does (reuse that code; don't copy it). Accessibility `นำทางไปหน้างาน`.
- **Meta line**: 13.5 pt `Theme.inkTab`, gap 14, margin 0 / 10, padding-bottom 12, one line.
  - `clock` 15 pt `Theme.inkMuted`, then the time until the appointment, bold navy:
    - `อีก 1 ชม. 20 นาที` when it is today
    - `อีก n วัน` when it is another day
    - the hour part is dropped when it is under an hour
  - `car` 15 pt `Theme.inkMuted`, then `12 กม. - ขับ 25 นาที` (distance and drive time). See open question 2. Default: compute it with `MKDirections` from the current location when location access is already granted and the job has coordinates. Otherwise **hide this item**; never show placeholder numbers.
- A divider follows (as above, margin 0 / 10) when agenda rows follow.

**Agenda rows.** The other appointments on the selected day, excluding the next appointment, sorted by time. Each row opens `JobDetailView`. Row: min height 56, padding 8 / 10, gap 12.
- **Time**: 48 pt wide, 15 pt bold navy, tabular.
- **Team bar**: 4 pt wide, full row height, radius 2, `job.team.color`.
- **Text**:
  - `job.projectName`, 15.5 pt bold navy, one line
  - `ทีม <team> · <province> · <kW>`, 12.5 pt `Theme.inkMuted`, one line
- **Chevron**: `chevron.right`, 8 × 13 visual, `Theme.muted`.
- **Accessibility**: `นัดสำรวจ <project> HH:mm น.`

**Empty day.** When the day has neither the next appointment nor agenda rows: `ไม่มีนัดสำรวจในวันนี้`, 14 pt `Theme.inkMuted`, centred, min height 56.

### 3. All jobs
**Section label**:
- leading `งานสำรวจทั้งหมด`
- trailing `<n> งาน`, where n is the count after search and status filtering

**Search field.** Reuse `PhoneSearchField` and add size parameters. This screen differs from the old list (44 / r12 / 14 pt):
- min height **50**, radius **10**, white
- 1 pt border `Theme.navy` at 50 % opacity; 2 pt `Theme.primary` when focused, without moving the text
- `magnifyingglass` 18 pt `Theme.inkMuted`
- text 16 pt; placeholder `ค้นหาชื่อลูกค้า หรือรหัสโครงการ` in `Theme.inkMuted`; typed text navy, bold
- clear button: a 32 pt circle `Theme.segmentTrack` with `xmark`, 44 pt hit area. Accessibility `ล้างคำค้นหา`.

**Recent searches.** Same behaviour as today (`states/04`), with the label `ค้นหาล่าสุด` 12 pt `Theme.inkMuted`. Chips: min height 36 with a 44 pt hit area, padding 0 / 12, capsule, 1 pt `Theme.borderOutdoor` border, white fill, navy 13 pt semibold. The board chips are example data.

**Status chips** (`states/06`):
- a horizontal scroll row that bleeds to the screen edges (content inset 16 each side), gap 6, no scroll indicator
- chips: `ทั้งหมด`, then one per `JobStatus` in case order, each followed by its count over the search result
- add `JobStatus.shortTitle`: `สนใจ` / `ยืนยันแล้ว` / `กำลังติดตั้ง` / `เสร็จสิ้น`
- each chip: min height 36 (44 pt hit area), padding 0 / 12, capsule, 13.5 pt semibold, gap 6
  - an 8 pt dot in `status.color` (no dot on `ทั้งหมด`)
  - the count, tabular, at 70 % opacity
- selected chip: `Theme.navy` fill, white text, no border
- other chips: white fill, 1 pt `Theme.borderSubtle` border, `Theme.inkTab` text
- accessibility: a tab group labelled `กรองสถานะ`, with `.isSelected` on the selected chip

**Filtering.**
- An active query matches the project name or code (the existing `Job.matches`). It is **AND**-ed with the status chip.
- The `DateWindow` filter is **removed** from this screen. Keep `DateWindow` itself, which other queues use.
- Sort by distance from today, `abs(days(from: today, to: surveyDate))`, nearest first, so today's and recent jobs come first, whether past or future. On a tie, sort by `surveyDate`.

**List card.** One `Theme.surface` card, radius 16, clipped, no shadow. One row per job; each row opens `JobDetailView`. Row: min height 64, padding 8 top / 14 trailing / 8 bottom / 16 leading, gap 12.
- **Avatar**: 40 pt circle, `job.team.color` text on `team.color.opacity(0.1)`, 16 pt bold. The letter is the first character of `projectName` after stripping a leading `คุณ`, `บริษัท`, `ร้าน`, `โรงงาน` or `หอพัก` (`?` if empty).
- **Text** (flex, gap 1):
  - `job.projectName`, 15.5 pt bold navy, one line
  - `code · kW · province`, 12.5 pt `Theme.inkMuted`, tabular, one line, for example `TCR2569-23403 · 5.5 kW · นนทบุรี`
  - **only when a draft is in progress**, margin-top 5, gap 8:
    - a progress bar: 4 pt high, radius 2, `Theme.borderSubtle` track, `Theme.primary` fill at the draft percent
    - `ทำต่อ <next group> · <pct>%`, 12 pt bold `Theme.primary`
    - take the values from `SurveyCardProgress` (`shortValue`, `percent`); do not recompute them
- **Status pill**: `status.shortTitle`, 11.5 pt bold, padding 2 / 8, capsule, `status.color` on `status.color.opacity(0.12)`.
- **Chevron**: as in the agenda rows.
- **Separator**: 1 pt `Theme.borderSubtle`, inset 68 leading, not after the last row.
- **Accessibility**: `<project> <status.title>`.
- **Empty**:
  - with a query: `ไม่พบงานที่ตรงกับ "<q>"`
  - without a query: `ไม่มีงานในสถานะนี้`
  - 14 pt `Theme.inkMuted`, centred, min height 64, inside the card

Remove `SurveyJobCompactCard` from this screen. Delete it only if code-review-graph shows no other caller.

### 4. Dock (replaces the `TCFab` on this screen)
A floating bar above the tab bar. Board: 12 from each side, 10 above the tab bar.
- **Container**: padding 8, radius 24, gap 8.
  - "Glass": `.ultraThinMaterial` (the board uses white 62 %, blur 20, saturation 1.7)
  - 1 pt inner stroke in white at 70 %
  - shadow `0 10 30` `Theme.navy` at 18 %
- **Primary button** (flex): min height 52, radius 17, `Theme.headerGradient`, shadow `0 6 14` `Theme.primary` at 30 %, padding 0 / 16, two lines, left-aligned:
  - **Title**: 15.5 / 20 bold white, one line
    - `ทำแบบสำรวจต่อ · <next group>` when the next appointment's job has a draft in progress
    - `เริ่มสำรวจ` otherwise
  - **Subtitle**: 12 / 16 white at 88 %: `<project> · <RelativeDay> HH:mm น. · <pct>%`
  - Opens `SurveyFormView(job:)` for the next appointment's job. Accessibility: `<title> <project>`.
  - If there is no upcoming appointment, hide the primary button and keep only the add button, aligned trailing.
- **Add button**: 52 × 52, radius 17, white at 85 %, `person.badge.plus` 23 pt in teal (`#1F8F83`). Add a `Theme` token if none matches; `Theme.teal` is `#27A99A`. It opens the `NewJobView` sheet, as the FAB does today. Accessibility `เพิ่มลูกค้าใหม่`.
- **Bottom inset**: the scroll content's bottom inset must let the last list row clear the dock (dock ≈ 68 + 10 gap + 16). The tab bar is already a safe-area inset. Check with `states/01c-full-list.png`.

### 5. Tab bar
Unchanged: `สำรวจ` selected; the badge shows today's survey appointments.

### 6. Motion
- Buttons and rows: on press, scale 0.97 and brightness 0.96, 0.12 s.
- The draft progress bar fills from the left in 0.7 s (ease-out) when it first appears.
- With Reduce Motion on, turn both off.

## Logic in TCRoofCore (with tests)
Keep the view thin. Add pure helpers next to `RelativeDay` / `RecentSearches` in `TCRoofKit/Sources/TCRoofCore`, on plain values (dates and simple structs), not on the SwiftData `Job`:
- `SurveyGreeting.text(hour:)`, with tests at 11:59 / 12:00 / 16:59 / 17:00
- week strip: seven days from today (`isToday`, weekday label, has-appointments flag)
- next appointment: earliest `>= now`, ties broken by time
- agenda for a day, excluding the next appointment, sorted by time
- the list sort key `abs(days)` with the tie-break
- status counts over the search result
- avatar initial with the prefix strip
- the time-until text (`อีก 1 ชม. 20 นาที`, `อีก 20 นาที`, `อีก 3 วัน`)

Put the tests in `TCRoofKit/Tests/TCRoofCoreTests`.

## Debug launch arguments
- Keep `-surveySearch <text>`, `-surveySearchFocus YES` and `-surveyListDraft YES`.
- `-surveyWindow` no longer applies to this screen. Remove its handling here.
- Add `-surveyDay <0-6>` (the selected strip day) and `-surveyStatus interested|confirmed|installing|completed`, so that states 02, 03 and 06 can be opened.
- Update the `CLAUDE.md` "Simulator checks" list: replace the `docs/ui/tcroof-survey-list-iphone` sentence with these flags and this folder.

## Tokens
Use the existing `Theme` tokens; no hex in views. Already present:
- `background`, `surface`, `navy`, `primary`, `inkMuted`, `inkTab`, `muted`, `borderSubtle`, `borderOutdoor`, `segmentTrack`, `survey`, `headerGradient`

Add, with dark values, only what is missing:
- the dock add-button teal `#1F8F83`
- if needed, the 50 % navy search border as a named token (for example `searchBorder`)

## Rules
- Compact width only; the iPad survey list is pixel-identical to before.
- Thai UI text exactly as in the previews. Touch targets ≥ 44 pt.
- No model or sync changes. Only `JobStatus.shortTitle` (computed) is added.
- Keep `-homeTab survey` and `-screen survey` working.
- Work on a new branch, `feat/iphone-survey-home`. Commit only when asked.

## Acceptance
1. **Matches the board.** On an iPhone 16 simulator (390 × 844), launched with `-screen home -homeTab survey -homeDemo YES -surveyListDraft YES`, the screen matches `states/01-default.png`:
   - the header and greeting
   - the week strip with dots
   - `นัดถัดไป` with call and navigate
   - the search field
   - the status chips
   - the list rows with the draft progress
   - the dock and the tab bar
2. **States.** Selecting tomorrow or an empty day matches `02` / `03`. Search focus, result and no result match `04` / `05` / `07`. `ยืนยันแล้ว` matches `06`.
3. **Taps.**
   - Row, agenda and next-appointment text open `JobDetailView`.
   - Call opens `tel:`; navigate opens Maps.
   - The dock opens `SurveyFormView` for the next job; the add button opens `NewJobView`.
4. **Accessibility.** VoiceOver reads the labels above. The day and status tab groups expose the selection.
5. **iPad unchanged.** Compare a `SurveyListView` iPad screenshot before and after.
6. **Builds and tests pass.** `swift build`, `swift test` and the `CLAUDE.md` xcodebuild (with your own `-derivedDataPath`, run in the background) pass with no new warnings.
7. **Summary.** End with:
   - the files changed
   - new tokens, helpers and parameters
   - the removed date filter and history button
   - the remaining differences from the board
   - answers to the open questions

## Open questions (report back; don't block on them)
1. **History entry point.** The board has no history button in the header. Default: keep `SurveyHistoryView` reachable some other way (for example a `ประวัติการสำรวจ` row under the list), and report what you chose.
2. **Distance and drive time.** Default: `MKDirections` ETA, only when location access is already granted and the job has coordinates; otherwise the car item is hidden. Should the app ask for location access on this screen?
3. **Large commercial jobs.** The board's list keeps only jobs ≤ 50 kW (the "งานบ้าน" scope) and drops the 199.8 kW factory seed. Default: show every job, because `Job` has no residential/commercial type. Confirm, or name the field to filter on.
4. **Past jobs in the list.** Sorting by `abs(days)` mixes past and future jobs. Is that wanted, or should future jobs come first?
5. **Sun mode.** The board CSS has an outdoor high-contrast mode (`states/08-sun-mode.png`) but no control for it. Out of scope for now; where should the toggle live?
6. **Dark mode.** The app is light only. Give dark values for any new tokens anyway.
