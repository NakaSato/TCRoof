# Claude Code task: PWA `แผนงาน` page, update v2 (13 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/pwa-plan-iphone/CLAUDE_CODE_UPDATE_v2.md`

Thai strings in `backticks` are literal UI labels. Data on the board is example data (`assets/sample-data.json`).

## Context
The first version of this folder is **already built**: `TCRoof/Views/Survey/PWAPlan/` (`PWAPlanPhoneView`,
`+Schedule`, `+MP`, `+Due`, `PWAPlanData.swift`; commits `1d50b8b`, `3fb6ba2`). Your screenshots of it are in
`screenshots/`; the old reference renders moved to `states-v1/`.

The owner then changed the board `iPhone · แผนงาน PWA` (and the PWA home's switch). `PhonePwaPlan.dc.html`,
`states/` and `CLAUDE_CODE_TASK.md` in this folder are now the **new** design; `CLAUDE_CODE_TASK.md` §2, §3 and §6
describe it in full. **Only the differences below apply.** `แผน MP` (`+MP`) and `กำหนดส่ง` (`+Due`) keep their content.

Before you start, use code-review-graph (per `CLAUDE.md`) on `PWAPlanPhoneView.pills`, `weekStrip`, `dayCell`,
`dotTypes`, `dayHeading`, `agendaRow`, `emptyCard`, and the PWA home's stage pills (`SurveyHome+Phone.swift`
`stagePills`), plus `tests_for` on what you touch.

## Changes

### 1. View switch: pills → one segmented track (`states/13-header-tabs-crop.png`)
- `PWAPlanPhoneView.pills` and the PWA home `stagePills` (and the docs page's pills) become the same control:
  track `#E6ECF3`, radius 22, padding 3, height 44; segments 38 high, radius 19; selected = white with a 1 pt soft
  shadow, `navy` 700, count in `primary`; unselected = no fill, `inkMuted` 600; counts are plain bold text after the
  label (no badge), `dangerText` when warning (`กำหนดส่ง` with late items).
- Build it once in `TCRoofUI` (a `TCSegmented` variant with counts, or a new `TCCountSegments`) and add it to
  `ComponentGallery`. The home's label `งานติดตั้ง` is now `ติดตั้ง`.
- The `กำหนดส่ง` round filter button stays at the end of the row.

### 2. Calendar card: week / month (`states/14`, `15`, `05`)
- Top row: `‹ title ›` left, `สัปดาห์ | เดือน` switch right (same control as §1, label 13).
- Week title `12–18 ต.ค. 2569` with **`สัปดาห์ที่ 42`** under it (11.5, 600, `primary`; ISO week). Month title
  `ตุลาคม 2569`.
- New **month view**: weekday header + Mon-first month grid (cells 46 high, radius 10, number 15 bold) + a legend of
  12 × 4 bars per job type. Same selected / today / weekend styles as the week cells.
- `‹ ›` move by a week or a month.

### 3. Dots → colour bars with continuous runs (`states/14`, `15`)
- Replace `dotTypes` / the dots in `dayCell` with bars (4 pt high, 2 pt apart, type ink colour; white on the selected
  day). Lane 1 = `ติดตั้ง`, lanes 2–3 = other types.
- Consecutive days of the same type in one week row draw **one continuous line** (square where it continues, 2 pt
  rounded at its ends) and keep their lane for the whole run (pack runs per row, earliest first). The selected day
  breaks a run. Draw one overlay per week row so the joins are seamless. Use it in both week and month views.

### 4. One scrolling list of days with scroll-spy (`states/01`, `04`, `06`, `07`)
- The calendar card stays fixed; under it the agenda becomes **one list of every day** in the range (week: 7 days;
  month: the whole month) — `ScrollViewReader` + `LazyVStack`, bottom inset so the last day can reach the top.
- Each day: header `วันพฤหัสบดี 15 ต.ค.` (13 bold) + count (12 muted), `· วันนี้` on today; the selected day's header is
  `primary` with a 6 pt dot. Rows sorted by time. A day with nothing: dashed row `ไม่มีงาน` (or
  `ไม่มีงานในตัวกรองนี้` when the filter hid its rows). This replaces `emptyCard`.
- **Scroll-spy:** the day whose header is at the top of the list becomes the selected day, so the calendar highlight
  follows the scroll. Tapping a day selects it and smooth-scrolls the list to it (ignore spy updates during that
  scroll). First appear: scrolled to today. Month → week switch with a day outside the week: back to today.
- `dayHeading` becomes the list heading: `งานสัปดาห์นี้` / `งานทั้งเดือน` + `15 รายการ · เลื่อนดูได้` (or
  `N จาก M รายการ` when filtered) + the filter button. The filter now applies to every day in the list.

### 5. Debug arguments (update `CLAUDE.md`)
`-pwaPlanCalendar week|month`, `-pwaPlanDay 2026-10-15` (selects and scrolls there). `-pwaPlanDemo YES` also seeds
`monthTypesByDay` from `assets/sample-data.json` (dated from today) so the month shows the bars.

## Check
- [ ] The same segmented control on the PWA home, `แผนงาน` and `เอกสาร`
- [ ] Week number under the week title; week/month switch; month grid + legend
- [ ] Continuous lane-stable bars, broken by the selected day
- [ ] Scroll-spy and tap-to-scroll both work; per-day empty rows
- [ ] iPad unchanged (`MPOverviewView`)
- [ ] Screenshots of the new states 01–07 and 14–15 in `screenshots/v2/`, compared with `states/`; report differences
