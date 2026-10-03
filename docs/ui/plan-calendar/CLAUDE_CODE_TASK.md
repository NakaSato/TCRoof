# Claude Code task: Construction plan calendar (แผนก่อสร้าง · ปฏิทิน), new month view

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/plan-calendar/CLAUDE_CODE_TASK.md`

UI text stays in Thai exactly as shown in the previews. This document is in English. Thai strings in `backticks` are the literal labels.

## Goal
Redesign `PlanCalendarView` (`TCRoof/Views/Plan/PlanViews.swift`) for iPad landscape so it matches `preview.png`. Today the month is a `LazyVGrid` of small `DayCell`s with coloured dots. The new design is a full-height month grid that draws **install jobs as horizontal bars across the days they run**, like a wall planner. Survey appointments appear as a dashed pill in each day cell, and a selected-day panel sits on the right.

Fit on one screen at 1366 × 1024 with no page scroll. The day panel scrolls on its own if it overflows.

Data, queries and navigation stay the same: `jobs(on:)`, `surveys(on:)`, `Job.installDay(on:)`, `SurveyModel.shared`, `JobDetailView`, `SurveyReportEditor` and `PlanListView`. This is a layout and visual change only.

Use code-review-graph first, as `CLAUDE.md` says (callers of `PlanCalendarView`, `PlanJobRow`, `DayCell`, `SurveyDot`). `PlanJobRow` is also used by `PlanListView`, so don't change it in place. Read the source before editing.

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` | default: today (30 ก.ย. 2569) selected, all teams |
| `states/01-today-sep.png` | same as preview |
| `states/02-empty-day.png` | a day with no work: the panel shows only `งานติดตั้ง` and the note `ไม่มีงานติดตั้งในวันนี้` |
| `states/03-survey-only-day.png` | a day with only a survey appointment |
| `states/04-install-day.png` | a day inside a 2-day install (TCR01) |
| `states/05-filter-team.png` | team filter `TCR01` on: other teams' bars hidden |
| `states/06-next-month-oct.png` | October: overlapping jobs stack into lanes, and bars carried over from the previous week have a square left edge and `ต่อ ·` |
| `preview.html` | open in a browser (uses `ds/` CSS next to it) |
| `iPadPlanCal.dc.html` | design source. `renderVals()` in its `<script type="text/x-dc">` is the reference for the week and lane layout (see "Bars" below) |
| `icons/` | every vector on the page as SVG, with the matching SF Symbol (`icons/README.md`) |

Names, codes and dates in the previews are the app's sample seeds (`SampleData.swift`) as they look on 30 ก.ย. 2569. The `09:00` in the survey row is a placeholder; use the real `surveyDate` time as the code already does.

## Layout
- **Header:** keep the `PageHeader` with `HeaderLink("ดูรายการแผนก่อสร้าง", systemImage: "list.bullet")`. Keep the breadcrumb style the other pages use, if `PageHeader` supports one.
- **Body:** an `HStack(spacing: 16)` with padding 16 top and 24 on the sides and bottom. The calendar card is flexible; the day panel is 360 pt wide. Both are white cards, radius 16, with the card shadow.

### Calendar card (padding 16, spacing 12)
1. **Title row**
   - `month.thaiMonthYear`: bold, 24 pt, navy.
   - Under it, a summary in 14 pt muted: `n งานติดตั้ง · n นัดสำรวจ · n ทีมทำงาน`. Counts are for the visible month: installs overlapping it, survey appointments in it, and distinct teams among those installs.
   - Right side: one segmented group (background `#F3F6FA`, border `#DDE4ED`, radius 10, padding 3) holding `chevron.left`, `วันนี้` and `chevron.right`. Each segment is ≥ 38 × 38. `วันนี้` is drawn selected (white with a card shadow). This replaces the three separate navy buttons.
2. **Month grid:** fills the remaining height. Border `#DDE4ED`, radius 16, clipped.
   - **Weekday row:** `อาทิตย์ … เสาร์` in full, 12 pt bold muted, left-aligned with padding 6×12. Saturday and Sunday use a lighter muted colour.
   - **Week rows:** equal height. Each week is a 7-column grid with five row tracks: 32 (date), 20, 20, 20 (three bar lanes), and a flexible track for the survey pill. Rows have a 2 pt gap and a 1 px top border.
   - **Day cell:** spans all rows. 1 px left border, except the first column. Padding 4×6. The whole cell is tappable and selects the day.
     - Weekend days and days outside the month: background `#F2F2F7` (`paper-page`).
     - Selected day: background `#E3EEF8` with an inset 2 pt `Theme.primary` border.
     - Date number: 15 pt bold navy. Today is a filled `Theme.primary` capsule with white text. Days outside the month are muted and regular weight.
     - The 1st of a month shows the short month after the number, e.g. `1 ต.ค.`.
   - **Survey pill:** in the last row, bottom-left of the cell. Text `นัดสำรวจ n`, where n = appointments + NO.224 reports that day, the same as `surveys(on:)`. Style: white, 1 px dashed `#77889E`, capsule, height 20, 12 pt bold. See `icons/survey-marker.svg`.
3. **Footer row**
   - **Team filter chips:** `ทุกทีม` plus `TCR01…TCR04`.
     - Each chip: an 8 pt dot in `Team.color` (navy for `ทุกทีม`), the label, and the count of that team's installs in the month (regular weight, muted).
     - Chip style: capsule, 1 px `#DDE4ED`, white, 13 pt bold muted, height 36.
     - Selected chip: navy border, navy text, `#E3EEF8` fill.
     - The filter hides other teams' bars and their rows in the day panel. It does not hide survey pills.
   - **Right side:** the legend, `survey-dot-legend` + `นัดสำรวจ`.
   - These chips replace the old static `ทีม TCR0x` legend.

### Bars (install jobs)
For each week row, take the jobs visible under the filter whose `installStart…installEnd` overlaps the week.
- Sort by start, then by longer duration first.
- Give each job the first lane (0–2) whose previous bar ended before this job's first column in the week. Jobs that need a 4th lane are not drawn as bars; they still appear in the day panel.
- **Bar:** grid row = lane + 2, columns = clipped start…end within the week.
  - Background: `Team.color` at 18 % opacity, height 20, 4 pt horizontal inset.
  - Text: bold 12 pt navy `TCR0x · <customer>`, where `customerName` drops a leading `คุณ` or `บริษัท `. Then regular muted ` <n> วัน · <kW>`.
  - A one-day bar shows only `TCR0x`.
- **Continuation:** when a job continues from the previous week, the left edge is square with no inset, and the sub-text starts with `ต่อ · `. When it continues into the next week, the right edge is square. Otherwise the radius is 4.
- Bars must not block taps on the day cells (`allowsHitTesting(false)`).
- The board's `renderVals()` (the `lanes` loop) is the exact reference.

### Day panel (360 pt)
- **Top band:** `paper-band` green `#E2EFDA`, padding 12×16, 1 px bottom border.
  - Title: `วันนี้ · <thaiLong>`, or `<thaiLong>` if the day isn't today. 17 pt bold.
  - Subtitle: `n งานสำรวจ · n งานติดตั้ง`, 12 pt.
- **Content:** scrollable, padding 16, spacing 12.
  - Section caption `งานสำรวจ`: 12 pt bold muted. Shown only when there are surveys.
  - **Survey rows:** white, 1 px `#DDE4ED`, radius 10, padding 12.
    - Left: clipboard icon in `Theme.primary`.
    - Text: bold 16 pt `<code> · <projectName>` (one line, truncated), then a 14 pt muted detail.
    - NO.224 reports have a `แบบ กปภ.` info badge on the right.
    - Taps go where they go today.
  - Section caption `งานติดตั้ง`: always shown.
  - **Empty note:** `tc-note` style (`#F2F2F7`, radius 8, padding 12, info icon) with `ไม่มีงานติดตั้งในวันนี้`.
  - **Install rows** (a new `PlanDayJobRow`; keep `PlanJobRow` for the list page): white, 1 px border, radius 10. A 4 pt left stripe in `Team.color`.
    - Line 1: bold 16 pt code + right-aligned info badge `Day d/n`.
    - Line 2: customer, 16 pt regular.
    - Line 3: `bolt` kW (bold) · `mappin` province, 14 pt muted.
    - Line 4: team pill, an 8 pt dot + `ทีม TCR0x` in a 1 px `#77889E` capsule.
    - Taps go to `JobDetailView`.

## Rules
- Touch targets ≥ 44 pt, except the segmented buttons (38 pt inside a 44 pt group) and the bars, which aren't tappable.
- Keep the narrow-width fallback (width ≤ 900): stack the calendar above the panel and let the page scroll.
- Accessibility: each day cell keeps a combined label such as `"<thaiLong>, n งานติดตั้ง, นัดสำรวจ n"` and the selected trait. Each bar gets an accessibility label even though it isn't tappable.
- Don't change models, queries, sync or other pages.
- Never put the GISTDA key or any secret into code, fixtures or docs.

## Tests
- Unit test the lane assignment as a pure function, for example `PlanLayout.lanes(for jobs:, weekStart:)`:
  - two overlapping jobs go into lanes 0 and 1
  - a job that starts after another ends reuses lane 0
  - a 4th overlapping job is dropped
  - start and end columns are clipped to the week
  - `continuesBefore` / `continuesAfter` flags are correct
- Run `swift build`, `swift test`, and the `CLAUDE.md` `xcodebuild` with your own `-derivedDataPath`.
- On the iPad simulator at 1366 × 1024, compare with `preview.png` and `states/06-next-month-oct.png`.

## Finish with
A summary listing the files changed, the new views and helpers, the test results, and anything left open (for example, how a 4th overlapping job is shown).
