# Claude Code task: PWA home · `บำรุงรักษา` stage (iPhone), 13 ต.ค. 2569

> **How to use:** open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/pwa-maintenance-iphone/CLAUDE_CODE_TASK.md`

Source board: `iPhone · หน้าแรก PWA Solar Project`, stage `บำรุงรักษา` (`PhoneHome.dc.html`, state `f: 'Draft'`;
the `isMnt` block). Thai strings in `backticks` are literal UI labels. All numbers on the board are **example data**
(`assets/sample-data.json`) — never ship them outside the DEBUG seed.

## 1. Context — what already exists
The maintenance overview was built from `docs/ui/pwa-solar-survey-iphone-v2/CLAUDE_CODE_TASK.md` §5 (states 08–09):
- `TCRoofKit/Sources/SurveyUI/SurveyHome+Overviews.swift`: `maintenanceOverview`, `maintenanceSummary`, `dueRow`,
  `maintenanceFilters`, `maintenanceRow`; `MaintenanceOverview` (`totals`, `due`, `matches`, `soonDays`, `RowFilter`).
- `SurveyHome+Phone.swift`: stage pills (`TCCountPill("ทั้งหมด" | "งานติดตั้ง" | "บำรุงรักษา", …)`), debug argument
  `-surveyHomeTab all|install|maintenance`.
- `PWAOverviewHost`: `maintenanceStations`, `maintenanceTasks`; DEBUG seed `static let maintenance`.

A diff of the board against the v2 handoff shows the **maintenance content is unchanged**. What changed is the
**stage switch** above it. So this task is one change (§2) and one verification pass (§3–§4).

Before you start, use code-review-graph (per `CLAUDE.md`) on `SurveyHome+Phone.swift` stage pills, `TCCountPill`,
`maintenanceOverview` and its helpers, plus `tests_for` on what you touch.

## 2. Change: stage pills → segmented switch with counts (`states/04-stage-switch-crop.png`)
This is the same control as `docs/ui/pwa-plan-iphone/CLAUDE_CODE_UPDATE_v2.md` §1. **Build it once** in `TCRoofUI`
(a `TCSegmented` variant with counts, or `TCCountSegments`) and add it to `ComponentGallery`. If that update was
already done, just reuse the control here.

| Part | Spec |
|---|---|
| Track | full width (16 pt page margins), height 44, radius 22, padding 3, fill `#E6ECF3` |
| Segments | equal width, height 38, radius 19 |
| Selected | white fill, shadow `0 1 3 rgba(22,50,92,0.16)`, label `navy` 700 15 pt, count `primary` (`#1F6FB5`) 700 |
| Unselected | no fill, label `inkMuted` (`#5B6B82`) 600, count `inkMuted` 700 |
| Count | plain bold text after the label, one space, no badge; `warning` (`#B45309`) if that stage has a warning count |
| Labels | `ทั้งหมด N` · `ติดตั้ง N` (was `งานติดตั้ง`) · `บำรุงรักษา N` |
| A11y | each segment is a tab: `isSelected` trait, label "บำรุงรักษา 6 สถานี" |

The animation of the white segment: slide with `matchedGeometryEffect`, 0.25 s easeInOut; off under Reduce Motion.

## 3. Reference: the maintenance overview (verify, fix differences)
Full-screen states: `01-maintenance-issue` (default filter), `02-maintenance-soon-pm`, `03-maintenance-all`
(PNG @2x + PDF to measure). Crops: `05-summary-card-crop`, `06-station-rows-crop`, `07-dock-crop`.
`08-install-tab-for-comparison` only shows the same switch on another stage.

Layout under the switch: vertical stack, 10 pt gap, 16 pt side margins, bottom inset for the dock.

**Summary card** (white, border `#DDE4ED`, radius 16, padding 12/14, gap 10)
- Ring 64 pt, stroke 7, track `#DDE4ED`, value `success` (`#2E9E5B`), centre `74%` 15 bold = today's energy / expected.
- Right: `ส่งมอบแล้ว 6 สถานี` 17 bold `navy`; `965 kWp · PR เฉลี่ย 77%` 13 `inkMuted` (PR weighted by kWp, offline
  stations excluded); `วันนี้ผลิต **2,572** / คาด 3,475 kWh` 13 `navy`.
- Three tiles (equal, gap 6, radius 10, padding 6/8): `4 ปกติ` green (`#E8F5EE`/`#1F6B43`), `1 แจ้งเตือน` red
  (`#FDECEA`/`#B42318`), `1 ออฟไลน์` grey (`#EEF1F5`/`#5B6B82`); value 18 bold, label 11.
- `งานที่ถึงกำหนดใน 14 วัน` 13 bold, then up to 3 rows (min 30 high, radius 9, fill `#F3F6FA`): date 44 pt wide
  13 bold `primary`; title 13 `navy` one line; assignee 11 `inkMuted` right.

**Filter pills** (unchanged, `style: .plain`): `มีปัญหา 2` · `ใกล้ถึง PM 3` · `ทั้งหมด 6`; 40 high, radius 20, 13 bold;
selected = `navy` fill, white text; others = white, border `#DDE4ED`. Default = `มีปัญหา`.
(Not part of this task: these may later become a segmented control too — leave them as pills.)

**Station row** (white card, radius 16, padding 10/12, gap 6)
1. `MP 25` 12 bold `inkMuted` · status chip (`ปกติ` / `แจ้งเตือน` / `ออฟไลน์`, colours as the tiles) · right:
   `แจ้งซ่อม 1 งาน` orange (`#FFF3E6`/`#9A4A06`) or `ไม่มีงานซ่อม` (`#F1F4F8`/`#9FB3CC`).
2. Name 15 bold `navy` one line · `220 kWp` 12 `inkMuted` right.
3. Bar 8 high, radius 4, track `#E3E9F1`, fill = energy / expected in the status colour (`#2E9E5B`, `#D9453B`, `#9FB3CC`).
4. `410` 12 bold `navy` `/ คาด 790 kWh` `· PR 63%` (`PR —%` when offline) · note right (`INV 2 fault · 2 วัน`).

Filters: `มีปัญหา` = status ≠ normal; `ใกล้ถึง PM` = next PM within `soonDays` (14); `ทั้งหมด` = all.
Empty filter result: `ไม่มีสถานีในตัวกรองนี้` (already built). The board shows 3 rows + `อีก N สถานี · เลื่อนดู`
only because the board can't scroll; in the app the list scrolls — keep the full list, no "more" line.

## 4. Data
Keep the existing DEBUG seed but make it match `assets/sample-data.json` (6 stations, 3 due tasks, dates relative to
today: +2, +7, +11 days) so screenshots line up with `states/`. Do not invent a production source.

## 5. Check
- [ ] One segmented control in `TCRoofUI`, in `ComponentGallery`, used by the PWA home (and the plan/docs pages if
      that update is done); label `ติดตั้ง`
- [ ] Maintenance summary, tiles, due rows, pills and station rows match states 01–03 (spacing within 2 pt)
- [ ] VoiceOver: segments read as tabs with counts; ring reads `ผลิตวันนี้ 74% ของที่คาด`
- [ ] Dynamic Type up to XL: no clipped Thai (tone marks), rows wrap or scale, not truncate the count
- [ ] iPad unchanged
- [ ] Screenshots `01–03` + switch crop in `docs/ui/pwa-maintenance-iphone/screenshots/`, compared with `states/`

Run: `-screen pwa -surveyHomeTab maintenance` (add `-pwaMaintenanceFilter issue|pmSoon|all` if you add it; then
document it in `CLAUDE.md`).

## 6. Open questions (report, don't decide)
1. Data source for `maintenanceStations` (energy, expected, PR, status) — still open from the v2 handoff, question 2.
2. Should a warning count in the switch (orange) appear on `บำรุงรักษา` when there are alarms/offline stations?
   The board shows plain counts; ask before adding.
