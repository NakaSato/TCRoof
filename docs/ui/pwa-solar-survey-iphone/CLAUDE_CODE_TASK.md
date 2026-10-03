# Claude Code task: PWA Solar Survey home on iPhone (compact width)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/pwa-solar-survey-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels.

## Context
`SurveyHomeView` already has a compact branch (`compact` = `horizontalSizeClass == .compact`):
- `SurveyHome.swift`
- `SurveyHome+Header.swift`
- `JobCard.swift`

On iPhone the branch is still the iPad layout squeezed: a 2 × 2 grid of filter boxes, the sort control on its own row under the heading, 17 pt card titles, a 58 pt ring and wide spacing. The owner's iPhone board (`PhoneHome.dc.html`, 390 × 844) is denser: filter pills, a one-line heading with a sort menu, and tighter cards, so more of the list fits on screen.

This is a visual pass. Don't change the model, filters' logic, sync, sorting rules or navigation.

Use code-review-graph first (callers of `SurveyHomeView`, `JobCard`, `PercentRing`, `stats`, `listHeading`), then read the source.

## Files in this folder
| File | Shows |
|---|---|
| `preview.png` | `ทั้งหมด` selected (same as `states/01-all.png`), @2x |
| `states/01-all.png` | `ทั้งหมด` · 6 jobs, NO.224 recently edited (blue border), pending sync |
| `states/02-doing.png` | `กำลังทำ` · 2 jobs |
| `states/03-draft.png` | `ร่าง` · 4 jobs without a project name |
| `states/04-all-synced.png` | after a sync: every footer shows `✓ ซิงก์แล้ว` |
| `preview.html` | static render (uses `grf.css` next to it) |
| `PhoneHome.dc.html` | design source: markup and `renderVals()` |
| `icons/` | every vector on the page with its SF Symbol (`icons/README.md`) |

The job names, numbers, dates and counts in the previews are examples.

## Changes for compact width only (iPad layout unchanged)

### 1. Header
- Title 22 pt bold (code: 24).
- Subtitle 13 pt at 90 % opacity, one line, tail truncation. Show `subtitle` only; the board drops the engineer name on iPhone. The iPad keeps `engineerLine`.
- Search field:
  - height 44 (code: 46)
  - placeholder `ค้นหาเลขที่ ชื่อโครงการ…` on compact (the iPad keeps `ค้นหาเลขที่ ชื่อโครงการ สถานที่…`)
- Padding: 16 sides, 14 bottom, gap 10 between the title block and search. Bottom corners stay 16.
- Keep `moreMenu` (`ellipsis` circle) at the right of the title row, even though the board omits it, as decided for the iPad. Make its frame 44 × 44 (code: 40) to meet the touch-target rule.

### 2. Filter pills replace the 2 × 2 boxes
- On compact, replace `stats` with one row of three equal pills:
  - `ทั้งหมด`
  - `กำลังทำ`
  - `ร่าง`
- Each pill is the label + a count chip; see `icons/filter-pill-on.svg` / `filter-pill-off.svg`:
  - 44 high, capsule, 6 pt gap
  - On: fill `#16325C`, white 13 pt bold
  - Off: white, 1 pt `#DDE4ED` border, navy 13 pt semibold
  - Count chip: 20 high, radius 10, 12 pt bold
- Counts come from `searched`, as in `stats` today.
- Add `Filter.shortTitle` (`.active` → `กำลังทำ`; the others are the same as `title`). The list heading keeps `heading` (`กำลังสำรวจ`).
- The board has no `รอซิงก์` pill. On compact don't show `.unsynced`; sync stays in `moreMenu` (`ซิงก์ทั้งหมด (n)`). Owner to confirm.
- Accessibility: each pill gets the label `"<title> <n> งาน"` and the `.isSelected` trait.

### 3. List heading: one row
- On compact, replace the stacked `VStackLayout` + segmented picker with one `HStack`:
  - heading 16 pt bold
  - `n งาน` 13 pt muted
  - `Spacer`
  - a `Menu` labelled `<sort.title> ▾`: 12.5 pt semibold `Home.primary`, `chevron.down`, min height 44
- The menu lists `Sort.allCases` and shows a checkmark on the current one.
- Drop the `เรียงตาม` caption on compact.

### 4. Spacing (compact)
- Header → pills 12 · pills → heading 4 · heading → first card 0 · card gap 10.
- The screen padding stays 16.

### 5. Card (compact)
- Padding 12 top, 14 sides, 10 bottom; internal spacing 8 (code: 14/16 and 12).
- `NO.224` 12 pt bold muted (code: subheadline heavy).
- Project name 16 pt bold (code: 17).
- Ring 44 pt: add a `PercentRing` style, e.g. `.cardSmall`, per `icons/progress-ring-44-*.svg`:
  - track `#DDE4ED` 5 pt
  - arc `Home.primary`, `Home.stepDone` at 100 %
  - centre `72%` 13 pt bold
- Continue strip:
  - min height 34, radius 9, background `Home.primarySoft`
  - lead `ทำต่อ 12/13` in 11 pt muted
  - code + title in 13 pt bold on one line (`D1 ถังน้ำใส`)
  - `chevron.right` in `Home.primary`
- Recent card border: 1 pt `Home.primary` (code: 1.5 pt at 55 %).
- Footer: `calendar` date · time and `photo` n stay. The sync mark changes; see below.

### 6. Floating add button (compact)
- 60 pt (code: 68), gradient `#1F6FB5` → `#2E8FDB` at 135°, plus 28 pt stroke 2.6. See `icons/fab-60.svg`.
- Inset: 20 trailing, 12 above the bottom safe area.

### 7. Sync status: icon only (owner, 3 ต.ค.)
- Replace the text `● รอซิงก์` / `✓ ซิงก์แล้ว` in `syncMark` with an icon and no text, 20 pt, at the right end of the footer after the photo count:
  - waiting: `icloud.and.arrow.up` in `#B45309` (`Home.pending`)
  - synced: `checkmark.icloud` in `#3B7420` (add `Home.syncedIcon`)
- `icons/cloud-pending.svg` and `icons/cloud-synced.svg` show the look.
- Keep the meaning for VoiceOver: `.accessibilityLabel("รอซิงก์")` / `"ซิงก์แล้ว"`.
- Apply the icon-only mark on both size classes, so the iPad footer matches. The iPad v2 task's dot + text is replaced by this.

## Card tokens on both size classes
The iPad board uses the same values (see `docs/ui/pwa-solar-survey/icons/README.md`), but `JobCard` doesn't follow them yet. Change them for all widths:
- **Step bar** (`color(_:)`):
  - done `Home.stepDone` `#70AD47` (code: mint)
  - missing `#B45309` = `Home.pending` (code: redSoft)
  - current `Home.primary`
  - not started `#DDE4ED`
  - height 6 (code: 5)
  - gap 2 on compact, 3 on regular (code: 4)
- **Status badge** (`badge`):
  - `ยังขาด n ช่อง`: `#FFF4E5` / `#B45309` (code: `ขาด n รายการ` in red)
  - `ครบ`: `#E2EFDA` / `#3B7420` (code: `ข้อมูลครบ` in teal)
  - `ร่าง`: `#E3EEF8` / `#5B6B82`
  - All 11 pt bold, capsule. Keep `n = job.missingItems.count`.
- **Section chips**: background `Home.primarySoft` (code: mint 45 %), navy 11 pt semibold, padding 1 × 8.

Add any missing colours to `Home`, e.g. `badgeWarnBg`, `badgeOkBg`, `badgeOkText`, `capTodo`.

## Rules
- Touch targets ≥ 44 pt. Thai text exactly as in the previews.
- Don't change `JobStage`, the stage tabs' behaviour, the install flow, sync, export or other pages.
- **Stage tabs:** the board omits them on iPhone, but keep `tabBar` on compact so `งานติดตั้ง` / `งานบำรุงรักษา` stay reachable. List this as a remaining difference.
- Never put the GISTDA key or any secret into code, fixtures or docs.

## Checks
- `swift build`, `swift test`, and the `CLAUDE.md` `xcodebuild` with your own `-derivedDataPath`.
- Run an iPhone 16 simulator (390 × 844) with the sample seeds and compare with `states/01–04`.
- Check the iPad at 1366 × 1024 against `docs/ui/pwa-solar-survey/preview.png`. Only the step-bar colours, badges and chips should change there.

## Finish with
A summary listing:
- the files changed
- the new `Home` colours and the `PercentRing` style
- what changed on the iPad (the card tokens)
- the remaining differences from the board (stage tabs, `•••` menu, no `รอซิงก์` pill)
