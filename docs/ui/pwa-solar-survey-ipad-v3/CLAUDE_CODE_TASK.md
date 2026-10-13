# Claude Code task: PWA project home (iPad) v3: new dock, `โครงการ | แผนงาน | บำรุงรักษา`, iPhone-style cards (board update 14 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and paste `PROMPT.md`, or type
> `Follow docs/ui/pwa-solar-survey-ipad-v3/CLAUDE_CODE_TASK.md`

- **Board:** `iPad · หน้าแรก PWA Solar Survey (รายการงาน)` (`iPadHome.dc.html`, 1366 × 1024 pt, landscape 12.9").
- Thai strings in `backticks` are literal UI labels.
- Every name, number, date, MP, team and count in the previews is **example data**. Never hardcode any of it.

## What is built today, and what this task does
- **iPad (regular width):** `SurveyHomeView.padPage` follows `docs/ui/pwa-solar-survey` (v1).
  - Header: `PWA Solar Survey` + subtitle + a 330 pt search field + `···`.
  - The `① งานสำรวจ · ② งานติดตั้ง · ③ งานบำรุงรักษา` stage tabs.
  - 4 stat boxes, a list heading with sort segments, a 3-column grid of large `JobCard`s, and the floating `+`.
  - It runs under `PadTabs` (`หน้าหลัก · สำรวจ · แผนงาน · ติดตั้ง · สแกน · กปภ. · เครื่องมือ | ตั้งค่า`). Its `.pwa` stack shows `SolarSurveyEntryView` with no `PWAOverviewHost`.
  - See `docs/ui/pwa-solar-survey/states/01-survey-all.png` for how it looks now.
- **iPhone (compact):** already has the new design (`docs/ui/pwa-solar-survey-iphone-v3`, commit `c06b723`):
  - `phonePage`, `phoneHeader`, `navRow`, `filterButton` / `filterPopover` / `typeRows`
  - `installOverview`, `maintenanceOverview`, install-phase `JobCard`s via `phaseStations`
  - `PWAPhoneRoot` as the host
- **This task brings the iPhone v3 design to the iPad, laid out for 1366 pt, and swaps the iPad dock.**
  - Reuse the iPhone v3 code; do not write a second copy of it.
  - Most of the work is removing `compact`-only guards and giving the shared pieces a regular-width layout.

## Scope: change only this list
1. iPad dock (`PadTabs`): new items and order.
2. The `โครงการ` tab hosts the PWA home with a `PWAOverviewHost`, as `PWAPhoneRoot` does on iPhone.
3. Header: `โครงการ PWA`, round search that grows, bell. No subtitle and no `···`.
4. The nav row `โครงการ | แผนงาน | บำรุงรักษา` plus the filter button replaces the stage tabs, the 4 stat boxes and the list heading.
5. The filter popover, in the iPad's list style.
6. The project grid: 3 columns of the **iPhone-size** `JobCard` (survey + install-phase cards).
7. The install and maintenance overviews on iPad: one wide summary card, then the row filters, then a 3-column grid.

**Do not touch:**
- the iPhone (any `compact` path). After the change, iPhone screenshots must be identical to v3.
- `JobCard`'s content and colours, the overview **logic** (`InstallOverview`, `MaintenanceOverview`, pace rules, filters)
- the survey wizard, `JobEditorView`, `InstallTrackingView`, `PWAPlanPhoneView`, `StationDocsScreen`
- `PadHome` (the iPad home screen), data models, `Values`, field ids, Excel cells
- the dock's **look**: `TCTabBar(size: .pad)`, 84 × 58 items, fade and spacing stay as they are. Only the items change.

**Before editing:** use code-review-graph (per `CLAUDE.md`). If the server is not available, use grep.
- Look at: `PadTabs`, `PadTab`, `PadDock`, `AppModule`, `PhoneTabs`, `PWAPhoneRoot`, `SolarSurveyEntryView`, `SolarSurveyReportView`
- Look at: `SurveyHomeView` (`padPage`, `phonePage`, `header`, `tabBar`, `stats`, `listHeading`, `grid`, `phaseStations`, `applyDebugHome`)
- Look at: `TCPhoneSearchHeader`, `TCCountSegments`, `JobCard`
- Then run `tests_for` on what you touch: `HomeNavbarUITests`, `PhoneSurveyUITests`, `PWAOverviewTests`, and any `Pad*` UI test.

## Files in this folder
| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `preview.png` | The default state, the same as `states/01-projects.png` (@2x) |
| `states/01-projects.png` | `โครงการ`: survey and install-phase cards, 3 columns, the floating `+`, the new dock with `โครงการ` selected |
| `states/02-filter-open.png` | Filter popover on `ทั้งหมด`: `ประเภทงาน`, `สถานะงาน` (with `ล้าง`), `เรียงตาม` |
| `states/03-install-overview.png` | `ประเภทงาน → ติดตั้ง`: the wide install summary, row filters, station rows in 3 columns |
| `states/04-maintenance-overview.png` | `ประเภทงาน → บำรุงรักษา`: the wide maintenance summary, row filters, rows in 3 columns |
| `states/05-search-open.png` | Search open: the field grows left to 420 pt, the title stays, the bell stays |
| `states/06-filter-open-install.png` | Filter popover on `ติดตั้ง`: only `ประเภทงาน` |
| `states/07-header-nav-crop.png` | Header + nav + filter button, close-up |
| `states/08-cards-survey-vs-install-crop.png` | Survey card vs. the late and on-plan install-phase cards |
| `states/09-dock-crop.png` | The new iPad dock |
| `states/10-filter-popover-crop.png` | The popover, close-up |
| `iPadHome.dc.html` + `grf.css` | The design source. Read it as text: the markup and `renderVals()` hold every size, colour and rule |
| `icons/tab-*.svg` | The dock glyphs as drawn in the board (24 pt, stroke 2.1). Compare them with the existing `tab-*` assets and add nothing that already matches |
| `icons/badge-install-hardhat.svg` | The `ติดตั้ง` badge glyph (already used by the iPhone `JobCard`) |
| `reference/iPadPwaPlan.png` · `reference/iPadPwaMaintenance.png` | The iPad pages `แผนงาน` and `บำรุงรักษา` lead to in the board. **Reference only, not in scope** |
| `screenshots/` | Empty. Put your simulator screenshots here |

## 1. iPad dock (`states/09`)
Items, left to right:

`หน้าแรก · โครงการ(badge) · งานบ้าน · เอกสาร · เครื่องมือ · สแกน | ตั้งค่า`

There is a divider before `ตั้งค่า`, as now.

| Item | `PadTab` | Glyph | Opens |
|---|---|---|---|
| `หน้าแรก` | `.home` (title was `หน้าหลัก`) | `house` | `PadHome`, unchanged |
| `โครงการ` | `.pwa` (title was `กปภ.`) | `icons/tab-projects.svg` (a clipboard with lines); compare with `tab-pwa` | the PWA home of this task (section 2) |
| `งานบ้าน` | `.survey` (title was `สำรวจ`) | `tab-homework` (as on iPhone) | the residential survey home it opens today |
| `เอกสาร` | new `.docs` | `tab-docs` | what the iPhone dock's `เอกสาร` opens today (v4); report which |
| `เครื่องมือ` | `.tools` | `tab-tools` | unchanged |
| `สแกน` | `.scan` | `tab-scan` | unchanged |
| `ตั้งค่า` | `.settings` | `gearshape` | the settings sheet, unchanged |

- **Badge:**
  - on `โครงการ`: today's PWA survey appointments, using the same rule as the iPhone's `กปภ.` badge in `PhoneTabs`
  - on `งานบ้าน`: today's home appointments, as on iPhone
  - VoiceOver: `โครงการ · นัดวันนี้ n`
  - The old badge on `สำรวจ` (all of today's jobs) goes.
- **Removed from the dock:** `แผนงาน` (`.plan`) and `ติดตั้ง` (`.install`). Do not delete their modules or screens.
  - `แผนงาน` stays reachable from the PWA nav (section 4).
  - Keep `.install` reachable from wherever it is easiest. For example, a row in `เครื่องมือ` like the iPhone's `เครื่องมือวัด` row, or the settings sheet.
  - Report where it went (open question 1).
- Update the `-homeTab` DEBUG values in `PadTabs.initialTab` and in CLAUDE.md to `home|survey|pwa|docs|tools|scan`.
- Update any UI test that taps `สำรวจ`, `กปภ.`, `แผนงาน` or `ติดตั้ง` on iPad.

## 2. The `โครงการ` stack hosts the PWA home
- On iPhone, `PWAPhoneRoot` wraps `SolarSurveyEntryView` with `\.pwaOverview` and handles:
  - stations, daily reports and maintenance stations
  - `openPlan` and the bell
- **Use the same root for the iPad's `.pwa` stack.** Make `PWAPhoneRoot` size-agnostic (rename it if you like, e.g. `PWARoot`, and update the iPhone caller) instead of copying it.
- Bell on iPad: `openNotifications` opens what the iPad home's bell opens today (`PadHome`'s notifications), not the iPhone full-screen cover. Report which.
- `SolarSurveyEntryView`, regular width: title `โครงการ PWA`, no subtitle (the same as compact).

## 3. Header (`states/07`, `05`)
- **Shape:** blue gradient as now. Bottom radius **20**, padding `22 / 63 / 22` (top / sides / bottom), so it is 88 pt tall.
- **Title:** `โครงการ PWA`, **30 pt bold**, one line. The old title `PWA Solar Survey` and the subtitle are gone.
- **Right side**, 10 pt apart:
  - **Search:** round 44 pt, white 18 % fill, 1 pt white 40 % border.
    - Tapped, it grows **leftwards to 420 pt** into a white field (radius 22).
    - The field has the placeholder `ค้นหาเลขที่ ชื่อโครงการ…` (15 pt) and an `×` that closes it.
    - The title stays visible on iPad (on iPhone it fades).
    - This is `TCPhoneSearchHeader`'s animation. Give it a regular-width size rather than writing a new header.
  - **Bell:** the same 44 pt round button, unread badge 16 pt `Theme.danger` with a 2 pt `#2A84CF` ring.
- **No `···`:** the board has no more-menu. Keep its actions reachable, the same way the iPhone v3 build did, and report where (open question 2).
- The old 330 pt search field goes.

## 4. Nav row (`states/07`)
- Sits 20 pt under the header, with side margins **63 pt** (the content margin of the whole page).
- `TCCountSegments`, three equal segments, no counts: `โครงการ` · `แผนงาน` · `บำรุงรักษา`.
  - track `#E6ECF3`, padding 3, capsule; segments 38 pt
  - 14 pt labels; selected = white with a soft shadow, bold navy
- 8 pt gap, then the round 44 pt **filter** button, always shown.
- **Behaviour:** the same as the iPhone `navRow`.
  - `โครงการ` = the list.
  - `แผนงาน` calls `host.openPlan` and is never the selected segment. On iPad it pushes `PWAPlanPhoneView` for now; the board's iPad plan page is `reference/iPadPwaPlan.png` and is out of scope.
  - `บำรุงรักษา` shows the maintenance overview inline, as on iPhone. The board links it to a separate iPad maintenance page (`reference/iPadPwaMaintenance.png`), which is out of scope (open question 3).
- **Removed on iPad:** the stage tabs (`tabBar`), the 4 stat boxes (`stats`) and the list heading with its sort segments (`listHeading`). Their counts and sort are now in the filter popover.
  - If nothing else uses `tabBar`, `stats` or `listHeading`, delete them, and say so.

## 5. Filter popover (`states/02`, `06`, `10`)
- Same sections and rules as the iPhone `filterPopover`. On iPad it is a **list**, matching the board.
- **Shape:** 248 pt wide, white, 1 pt `#C9D3E0` border, radius 16, under the filter button with its arrow, right-aligned to the 63 pt margin.
- **Rows:** every row is 44 pt, 14 pt text, padding 14.
  - Selected row: `#F1F6FC` fill, bold, a blue tick on the right.
  - The count is 13 pt bold `inkMuted` before the tick.
- **Sections:** each title is 11 pt bold `#5B6B82`, and a 1 pt `#EEF2F7` divider sits between sections.
  1. `ประเภทงาน`: `ทั้งหมด n` / `ติดตั้ง n` / `บำรุงรักษา n`. Picking one switches the view and closes the popover (as iPhone).
  2. `สถานะงาน` (only for `ทั้งหมด`), with `ล้าง` on the right of its title:
     - rows `งานทั้งหมด` / `กำลังสำรวจ` / `ร่าง` / `รอซิงก์`, each with an 8 pt status dot
     - the `รอซิงก์` count is orange when > 0
  3. `เรียงตาม` (only for `ทั้งหมด`): `แก้ไขล่าสุด` / `เลขที่` / `ความคืบหน้า`.
- No `แสดง n งาน` button on iPad. Rows apply at once, and tapping outside closes the popover.
- **Filter button states:**

  | State | Look |
  |---|---|
  | Open | `#E3EEF8` fill, 1 pt `Theme.primary` border |
  | Filtered | navy fill, white glyph, 8 pt orange dot |
  | Neither | white fill, 1 pt `#DDE4ED` border |

  "Filtered" is iPhone's `isFiltered`. All of this matches the iPhone button.
- If the iPhone popover and the iPad list need different bodies, branch on `compact` inside `filterPopover`, and keep `typeRows` and the rules shared.

## 6. Project grid (`states/01`, `08`)
- 3 equal columns, gap 16, margins 63, top 16 under the nav.
- **Cards are the iPhone-size `JobCard`, not the large iPad card:**
  - radius 16, padding 12 / 14
  - number 12 pt, name 16 pt bold, sub 12 pt, ring 44 pt, 13 caps
  - next-step row, tag chips, footer
- The **same card types as iPhone v3**: survey cards with the blue `สำรวจ` badge, and install-phase cards with the green hard-hat `ติดตั้ง` badge.
  - Install-phase cards have the pace-coloured ring and bar, `กำลังทำ … · ช้ากว่าแผน n% / ตามแผน`, and the chips `แผน · จริง`, `ส่งมอบ`, `ผู้รับเหมา`.
  - Remove the `compact` guard in `phaseStations` so install-phase cards also show on iPad. Keep the `-surveyHomeDemo cards` seeding for both sizes.
- If `JobCard` has a separate regular-width layout, the iPad now uses the compact one. Keep the regular layout only if something else still uses it, and report.
- Tapping a card does what it does on iPhone v3: a survey card opens the wizard at its next step, and an install-phase card opens its station.
- The recently opened card has a 1 pt `Theme.primary` border (as now).
- Floating `+`: **64 pt**, gradient, 63 pt from the right, sitting **116 pt** above the bottom edge so it clears the dock. It shows only on `ทั้งหมด`. Leave room under the last row (bottom padding ≈ 140).

## 7. Install and maintenance overviews on iPad (`states/03`, `04`)
- These use the iPhone overviews' content and logic. Only the arrangement is wider.
- **Summary card:**
  - one white card, 1 pt `#DDE4ED` border, radius 16, padding 14 / 16
  - a 3-column grid `330 pt | 300 pt | flexible` with 20 pt between
  - **Install:**
    1. ring 64 pt with the plan tick + `กำลังติดตั้ง n สถานี`, kWp, average real / plan, overall variance
    2. the 3 stat tiles (`ช้ากว่าแผน`, `ตามแผน`, `เร็วกว่าแผน`)
    3. `ผู้รับเหมา n ทีม · แตะเพื่อดูเฉพาะทีม` with the contractor buttons in one row
    - Then, across the full width: the orange `รายงานประจำวันวันนี้ x/y ส่งแล้ว · ยังไม่ส่ง n สถานี ›` strip.
  - **Maintenance:**
    1. ring + `ส่งมอบแล้ว n สถานี`, kWp · PR, today's energy
    2. the 3 stat tiles (`ปกติ`, `แจ้งเตือน`, `ออฟไลน์`)
    3. `งานที่ถึงกำหนดใน 14 วัน` with the due rows
- **Row filters:** the chips (`ช้ากว่าแผน n` …, or `มีปัญหา n` …) on the left, and `n สถานี` on the right.
- **Rows:** the iPhone rows' content, in a 3-column grid, gap 16.
- Taps are the same as on iPhone: station, daily reports, maintenance station.

## DEBUG and CLAUDE.md
- `applyDebugHome()` returns early when not `compact`. Let it run on iPad too, with the same flags:
  - `-surveyHomeTab`, `-surveyHomeType`, `-surveyHomeSearch`, `-surveyHomeFilter`, `-pwaMaintenanceFilter`, `-surveyHomeDemo cards|maintenance`
- Update CLAUDE.md where it says these flags are iPhone-only, and update `-homeTab` (section 1).

## Check
- [ ] Build with your own `-derivedDataPath`. Run `swift build` and `swift test` in `TCRoofKit/`.
- [ ] Run on an iPad Pro 13" simulator, landscape. Compare with `states/` 01, 02, 03, 04, 05 and 09. Note any difference larger than 4 pt.
- [ ] Dock: `หน้าแรก · โครงการ(badge) · งานบ้าน · เอกสาร · เครื่องมือ · สแกน | ตั้งค่า`. Each item opens what the table says. `แผนงาน` and the install module are still reachable (say where).
- [ ] The cards are the iPhone size in 3 columns. `-surveyHomeDemo cards` shows a late and an on-plan install-phase card.
- [ ] The popover's type rows switch the view. `สถานะงาน` and `เรียงตาม` show only for `ทั้งหมด`. `ล้าง` resets type, status and sort.
- [ ] Every tap target is ≥ 44 pt.
- [ ] iPhone v3 is unchanged. Run the iPhone screenshots of `docs/ui/pwa-solar-survey-iphone-v3` states 01 and 04 again and compare them.
- [ ] `HomeNavbarUITests`, `PhoneSurveyUITests` and `PWAOverviewTests` pass.
- [ ] Simulator screenshots of states 01, 02, 03 and 09 are in `docs/ui/pwa-solar-survey-ipad-v3/screenshots/`.

## Open questions (report, don't decide)
1. With `แผนงาน` and `ติดตั้ง` off the iPad dock, where should the plan calendar and the install module live? Say where you put them for now.
2. Where did the old `···` actions go on iPad (import, Drive, export, settings, sync list)? Is that where the owner wants them?
3. The board's nav `บำรุงรักษา` (and `แผนงาน`) link to separate iPad pages (`reference/`). Until those are built, iPad shows the maintenance overview inline and pushes `PWAPlanPhoneView`. Is that acceptable as an interim?
4. The dock's `เอกสาร` opens the iPhone's docs target for now. The cross-station `เอกสาร PWA` overview is still not built.
