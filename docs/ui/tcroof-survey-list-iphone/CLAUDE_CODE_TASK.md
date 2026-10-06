# Claude Code task: iPhone survey list (สำรวจหน้างาน · รายการงานสำรวจ), compact design

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/tcroof-survey-list-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels; keep them exactly. Names, codes, times, kW values and progress in the previews are **example data** (the board's `SEEDS`, `TIMES`, `DRAFT_DONE`). In the app, use the real `Job`, `surveyDate` and survey draft.

## Context
`SurveyListView` (`TCRoof/Views/Survey/SurveyViews.swift`) was designed for the iPad (`docs/ui/survey-list`, 1366 × 1024). On the iPhone it is the root of the `สำรวจ` tab in `PhoneTabs` (`TCRoof/Views/Home/PhoneTabs.swift`, from `docs/ui/tcroof-home-iphone-v2`). Today the phone gets the iPad layout in one column:
- `TCNavBar` with breadcrumbs
- `QueueFilterBar` (title + count, three gradient capsules, search field)
- `SurveyJobCard` with the teal gradient button

The board `iPhone · สำรวจหน้างาน · รายการงานสำรวจ` is a compact layout for the phone: denser, one tap target per action, and filters that take less height.

**Compact width only.** Apply every change below only when `horizontalSizeClass == .compact` (or the existing `isPhone`). The iPad survey list must look exactly as before. `SurveyJobCard`, `QueueFilterBar` and `JobCard` are shared, so add a compact variant instead of changing the iPad path:
- the plan, install and history lists also use `JobCard`
- `QueueFilterBar` is used by other queues

Use code-review-graph first (per `CLAUDE.md`):
- callers of `SurveyListView`, `SurveyJobCard`, `SurveyCardProgress`, `QueueFilterBar`, `TCNavBar`, `TCFab`, `tcFabPlacement`, `PhoneTabs`
- `tests_for` on anything you touch

Then read the source.

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` = `states/01-week.png` | Default: `7 วัน`, 4 jobs, today's job highlighted, one draft. @2x (780 × 1688) |
| `states/01a-header-filter-crop.png` | Header, segmented filter and search field (@2x) |
| `states/01b-card-today-crop.png` | Today's card with the draft progress box (@2x) |
| `states/01c-week-scrolled-full.png` | The whole list scrolled out, to see the last card clear the FAB and tab bar (@1x) |
| `states/02-30-days.png`, `03-all.png` | `30 วัน` and `ทั้งหมด`. Past jobs read `n วันที่แล้ว · HH:mm น.`; finished surveys read `สำรวจครบ · ดูแบบสำรวจ · 100%` |
| `states/04-search-open.png` | Search field focused: 2 pt primary border and `ค้นหาล่าสุด` chips |
| `states/05-search-result.png` | Query `นพพร`. The subtitle reads `ผลการค้นหา 1 งาน` |
| `states/06-empty.png` | No match: `ไม่พบงานสำรวจ` |
| `states/01-week.pdf`, `04-search-open.pdf` | **Vector** 390 × 844 renders. Measure here. |
| `PhoneSurveyList.dc.html` | Design source. Read as text; every style value is inline. `renderVals()` holds the filter, search, relative-day and progress logic. |
| `preview.html` + `grf.css` | Static render of the default state |
| `icons/` | SVGs for the glyphs, with the SF Symbol to prefer (see `icons/README.md`) |

## Changes (compact only)

### 1. Header
Replaces `TCNavBar` and its breadcrumbs on compact. See `states/01a-header-filter-crop.png`.
- **Bar**:
  - `Theme.headerGradient` (`#1F6FB5 → #2E8FDB`, left to right), white text
  - bottom corners 15
  - padding 6 top (below the status bar; extend the gradient under it) / 8 trailing / 14 bottom / 6 leading
  - gap 2
- **Leading**: back chevron, 44 × 44, glyph 24 pt white, stroke 2.4.
  - On the board it returns to the home screen.
  - In the app this screen is a tab root, so **hide the back button when it is the root of the `สำรวจ` tab**, and show it only when the list is pushed (for example from the home module row). See open question 1.
- **Title block** (flex, truncates):
  - `สำรวจหน้างาน`, 19 / 24, bold
  - subtitle 13 / 18 at 92 % opacity:
    - `นัดสำรวจ n งาน`, where n = the filtered count
    - `ผลการค้นหา n งาน` while a query is active
  - This replaces the `รายการงานสำรวจ` title + count badge of `QueueFilterBar`.
- **Trailing**: history button, 44 × 44, radius 12, fill white 16 %, glyph `clock` 22 pt white, stroke 2.2. It opens `SurveyHistoryView`, as `TopBarLink` does today. Accessibility label `ประวัติการสำรวจ`.

### 2. Filter: segmented control
Replaces the three gradient capsules on compact.
- **Track**:
  - full width, min height 44, padding 3, gap 3
  - radius 10, fill `#EEF2F7`
  - 3 equal columns: `7 วัน`, `30 วัน`, `ทั้งหมด` (`DateWindow.week / .month / .all`)
- **Selected segment**: white, radius 8, shadow `0 1 3 rgba(22,50,92,0.2)`, text navy `#16325C` weight 700, 14 pt.
- **Unselected segment**: transparent, text `#5B6B82`, 14 pt.
- A system `Picker(.segmented)` is acceptable only if it can match the colours and the 44 pt height; otherwise build it as a small `TCSegmented` in `TCRoofUI` and add it to `ComponentGallery`.
- Accessibility: `.isSelected` on the active segment.

### 3. Search field
- **Field**:
  - height 44, radius 12, white
  - 1 pt `#DDE4ED` border, leading padding 12
  - when focused: **2 pt `#1F6FB5`** border, leading padding 11 so the text does not move
- **Leading glyph**: `magnifyingglass` 18 pt `#5B6B82`.
- **Text**:
  - placeholder `ค้นหาชื่อลูกค้า หรือรหัสโครงการ` in `#5B6B82`, 14 pt
  - typed text navy, weight 700
- **Clear**: when the query is not empty, a 32 × 32 circle `#EEF2F7` with `✕` (`xmark`, 14 pt `#5B6B82`). Give it a 44 pt hit area. Accessibility label `ล้างคำค้นหา`.
- **Recent searches** (`states/04-search-open.png`): while the field is focused and empty, show under it:
  - the label `ค้นหาล่าสุด` (12 pt `#5B6B82`, full row)
  - up to 4 chips, each min height 36, padding 0 / 12, capsule, 1 pt `#C9D3DF` border, white fill, navy 13 pt weight 600
  - tapping a chip sets the query and ends editing
  - store the last 4 submitted queries in `@AppStorage("surveyList.recentSearches")`, newest first, without duplicates
  - the board's chips (`นพพร`, `สยามแพ็คกิ้ง`, `TCR2569-23404`, `กรีนเพลส`) are **example data**
- **Search scope**: on the board an active query searches **all** jobs and ignores the date filter. Today the app ANDs the two (`window.overlaps && matches`). On compact, follow the board: `search.isEmpty ? window.overlaps(...) : true`. Mention the change in your summary.
- Spacing: header → controls 12; segmented → search 10; controls block padding 12 / 16 / 4.

### 4. Job card (compact): `SurveyJobCard` compact variant
See `states/01b-card-today-crop.png`. Sorted by `surveyDate` ascending (unchanged).

**Card**
- white, radius 16, padding 12 / 14, inner gap 8
- shadow `0 3 8 rgba(22,50,92,0.08)`
- border 1 pt `#DDE4ED`; **today's job gets a 1 pt `Theme.primary` border**

**Tap target 1, the body** (rows 1–3, gap 8) opens `JobDetailView`. Accessibility label `รายละเอียดงาน <project> <when>`.
1. **Title row**:
   - `job.projectName`, 16 pt bold navy, one line, tail truncation
   - trailing: team pill with the team code only (`TCR03`), 11.5 pt weight 700, padding 1 / 8, capsule, `team.color` text on `team.color.opacity(0.1)`
   - **No** `ทีม` prefix, no dot, no chevron and no status chip on compact
2. **Code row** (pulled up 4 pt):
   - 13 pt `#5B6B82`: `job.code` · bolt glyph 13 · `job.capacityKW.kw`
   - No customer name, no divider
3. **When row**:
   - `calendar` 16 pt `Theme.primary`, then the relative label bold 14 pt: `Theme.primary` for today, navy otherwise
   - the relative label comes from the existing `RelativeDay.label`:
     - `วันนี้ 09:30 น.`
     - `พรุ่งนี้ 13:30 น.`
     - `อีก 3 วัน · 10:00 น.`
     - `n วันที่แล้ว · HH:mm น.`
   - trailing: pin glyph 14 + `job.province`, 13 pt `#5B6B82`
   - The short date (`30 ก.ย. 69`) is **not** shown on compact

**Tap target 2, the progress box** replaces the teal gradient button on compact and opens `SurveyFormView(job:)`.
- **Box**:
  - min height 44, padding 8 / 10, radius 10, gap 6
  - fill `Theme.progressBox` (`#EEF4FB`) for a draft in progress, `Theme.progressBoxIdle` (`#F3F6FA`) otherwise
- **Top line** (12.5 pt):
  - key in `#5B6B82`: `ยังไม่เริ่ม` / `ทำต่อ` / `สำรวจครบ`
  - value bold 13.5 navy: `เริ่มสำรวจ` / the next group name (`ค่าไฟ`) / `ดูแบบสำรวจ`
  - then, trailing, the percent bold:
    - `Theme.progressZero` at 0 %
    - `Theme.progressFull` when complete
    - `Theme.primary` otherwise
  - then `chevron.right` 14 pt `#1F6FB5`, stroke 2.6
- **Bar**: 4 equal segments (`หลังคา`, `ระบบไฟฟ้า`, `ค่าไฟ`, `รูปบังคับ`), height 5, radius 3, gap 3.
  - `Theme.stepDone` (`#70AD47`) done
  - `Theme.primary` current
  - `Theme.borderSubtle` to do
- **Accessibility label**: `<value> แบบสำรวจ`, for example `ค่าไฟ แบบสำรวจ`.

Reuse `SurveyCardProgress` / `SurveyOptions.progress` for key, value, percent and segments. If the compact labels (`ทำต่อ` + group name, instead of `ทำต่อ n/4`) need new fields, add them to `SurveyCardProgress` with unit tests. Do not duplicate the logic in the view.

### 5. List layout, FAB and empty state (compact)
- **List**: one column, padding 8 / 16, gap 10. Bottom content inset so the last card clears the FAB and the tab bar (board: 170 incl. the bar; in the app, the bar is already a safe-area inset, so add ≈ 76 = FAB 60 + 16).
- **FAB**: unchanged from v2 (`TCFab("person.badge.plus")`, 60 pt, 20 from the right, 16 above the tab bar).
- **Empty state**: on compact, a plain centred line `ไม่พบงานสำรวจ`, 14 pt `#5B6B82`, padding 40 / 16, instead of `ContentUnavailableView`.
- **Page background**: `#F3F6FA` (`Theme.background`) instead of `pageGradient` on compact.
- **Tab bar**: unchanged; `สำรวจ` selected, badge = today's survey appointments.

## Tokens
Use existing `Theme` tokens; no hex in views. If one of these has no token yet, add it to `TCRoofUI/Theme.swift` with a dark value:

| Use | Light | Suggested token |
|---|---|---|
| segmented track, clear button fill | `#EEF2F7` | `segmentTrack` |
| card and search border | `#DDE4ED` | `borderSubtle` (exists) |
| recent-search chip border | `#C9D3DF` | reuse `borderOutdoor` (`#C9D3E0`) |
| secondary text | `#5B6B82` | `inkMuted` (exists) |

## Rules
- Compact width only; the iPad survey list is pixel-identical to before. Thai UI text exactly as in the previews. Touch targets ≥ 44 pt.
- No model or sync changes. The date-window and search logic changes only as described in section 3.
- Keep `-homeTab survey` working; use it to open this screen in the simulator.

## Acceptance
1. **Matches the board.** On an iPhone 16 simulator (390 × 844) launched with `-homeTab survey`, the screen matches `states/01-week.png`:
   - gradient header with the subtitle count
   - segmented filter and search field
   - compact cards, today's card with a primary border
   - progress boxes, FAB and tab bar
2. **States.** Switching `7 วัน / 30 วัน / ทั้งหมด` matches states 01–03. A query matches state 05. No match shows state 06. Recent-search chips appear on focus (state 04) and fill the query.
3. **Tap targets.** The card body opens `JobDetailView`; the progress box opens `SurveyFormView`. Both are separate VoiceOver elements with the labels above.
4. **iPad unchanged.** Check `SurveyListView` on an iPad screenshot before and after.
5. **Builds and tests pass.** `swift build`, `swift test` and the `CLAUDE.md` xcodebuild (with your own `-derivedDataPath`) pass with no new warnings. Add tests for any new `SurveyCardProgress` fields and for the recent-searches list (dedupe, cap 4).
6. **Summary.** Finish with a summary covering:
   - the files changed
   - new tokens and components
   - the search-scope change
   - any remaining differences from the board

## Open questions (report back; don't block on them)
1. **Back button on the tab root.** The board shows a back chevron to the home screen. On a tab root it is redundant with `หน้าหลัก` in the tab bar. Default: hidden on the tab root, shown when pushed.
2. **Status chip.** The compact card drops `job.status` (`ลูกค้าสนใจติดตั้ง` …). Is that acceptable on the phone, or should it come back as a dot or colour?
3. **Customer name.** The compact card drops the customer name when it differs from the project name (for example `ร้านกาแฟบ้านสวน` / `คุณวิภาวรรณ ศรีสุข`). Show it in the code row instead?
4. **Dark mode.** The board is light only. Propose dark values for any new tokens.
