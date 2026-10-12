# Claude Code task: PWA Solar Project home on iPhone, v2

This version covers the search button, filter popover, install and maintenance overviews, the PWA tab dock and the settings page.

> **How to use.** Open Claude Code in the `TCRoof` repo and paste the prompt in `PROMPT.md`, or type:
> `Follow docs/ui/pwa-solar-survey-iphone-v2/CLAUDE_CODE_TASK.md`

This document is in English.
- Thai strings in `backticks` are literal UI labels.
- Every name, number, date and percentage in the previews is **example data**. Never hardcode any of it.

## Context

The board is `iPhone · หน้าแรก PWA Solar Project` (`PhoneHome.dc.html`, 390 × 844), as of 13 ต.ค. 2569 with the owner's own edits. The dock links to three sibling boards, which are included as reference:
- `PhonePwaPlan.dc.html` (`แผนงาน`)
- `PhonePwaDocs.dc.html` (`เอกสาร`)
- `PhonePwaSettings.dc.html` (`ตั้งค่า`)

v1 (`docs/ui/pwa-solar-survey-iphone`) is already built in the compact branch of `SurveyHomeView`. The files are:
- `TCRoofKit/Sources/SurveyUI/SurveyHome.swift`
- `SurveyHome+Header.swift`
- `JobCard.swift`

v1 has the filter pills, the one-row list heading, tight cards, a 60 pt FAB, and stage tabs (`JobStage` survey / install / maintenance).

**This task covers only the differences below, and only for compact width.** The iPad survey home stays as it is.

**Supersedes.** This replaces the earlier draft of the same name: search beside a gear, a settings sheet, no dock. If you find that draft anywhere, ignore it.

**Before changing code:**
1. Start with code-review-graph. Look up the callers of `SurveyHomeView`, `header`, `tabBar`, `filterPills`, `moreMenu`, `stageEmpty`, `JobStage`, `SolarSurveyEntry` and `PhoneTabs`.
2. If the server is not available, use grep.
3. Read the source before you change it.

## Files in this folder

| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `preview.png` | Default state, @2x (same as `states/01`) |
| `states/01-all.png` | `ทั้งหมด` tab: survey list, search collapsed to one button, dock with `โครงการ` selected |
| `states/02-search-open.png` | Search expanded; the title is gone |
| `states/03-filter-popover.png` | Filter button open: `กรองและเรียง` popover |
| `states/04-filtered-draft.png` | Status `ร่าง`, sort `ความคืบหน้า`: navy filter button with an orange dot |
| `states/05-install-behind.png` | `งานติดตั้ง` tab, rows filter `ช้ากว่าแผน` (the default) |
| `states/06-install-team-a.png` | Contractor `ผู้รับเหมา A` selected |
| `states/07-install-no-report.png` | Rows filter `ยังไม่ส่งรายงาน` |
| `states/08-maintenance-issue.png` | `บำรุงรักษา` tab, filter `มีปัญหา` (the default) |
| `states/09-maintenance-pm-soon.png` | Filter `ใกล้ถึง PM` |
| `states/10-all-synced.png` | After a sync: every cloud icon is green |
| `states/11`–`13-plan-*.png` | Reference: `แผนงาน` tab (`ตารางงาน` / `แผน MP` / `กำหนดส่ง`) |
| `states/14`–`16-docs-*.png` | Reference: `เอกสาร` tab (`ตามสถานี` / `ต้องทำ` / `คลังกลาง`) |
| `states/17-settings-page.png` | `ตั้งค่า` tab: the settings page |
| `states/18-dock-crop.png` | Close-up of the dock and the fade above it |
| `*.dc.html` + `grf.css` | Design source. Read it as text: the markup and `renderVals()` hold every size, colour and rule. |
| `icons/` | Vectors for the new parts, with the SF Symbol to use for each (see `icons/README.md`) |

## Changes (compact only)

### 1. Header: one search button that grows to the left

**Layout**
- Header row: the title block, then the search button pushed to the right. The header has no other buttons.
  - The gear is gone, because `ตั้งค่า` is now a dock tab.
  - The `•••` button is gone (see section 3).
- Title block:
  - `PWA Solar Project` at 18 pt bold, line height 23.
  - `การประปาส่วนภูมิภาค` at 12 pt, 90 % opacity.
- The header keeps its 15 pt bottom corners. The search row under the title is removed.
- Search button:
  - 44 × 44, radius 12.
  - White 18 % fill with a white 40 % 1 pt border.
  - White 21 pt magnifier.

**Opening (state `02`)**
- Wait 0.10 s. Then the button grows **leftwards** into a field over 0.36 s with `.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.36)`, and its fill turns white 97 %.
- The title block fades out, slides 16 pt left and gives up its width (0.30 s, starting at 0.10 s).
- The magnifier turns `Theme.inkMuted`.
- At 0.42 s these fade in:
  - The text field: `ค้นหาเลขที่ ชื่อโครงการ…`, 15 pt.
  - A ✕ button, 44 wide.
- Focus the field so the keyboard opens.

**Closing (tap ✕)**
- The field shrinks back to 44 pt (0.30 s, starting at 0.06 s).
- The title fades back in (0.34 s, starting at 0.14 s).
- Clear the text and drop focus.
- If the user dismisses the keyboard while the text is not empty, keep the field open.

**Reduce Motion:** a plain cross-fade, with no movement.

**Accessibility**
- Label the button `ค้นหาเลขที่ ชื่อโครงการ` and the close button `ปิดการค้นหา`.
- Hide the title from VoiceOver while it is collapsed.

**Implementation**
- Use one `@State var searchOpen` and one `@FocusState`.
- Animate one shape's width, or use `matchedGeometryEffect`.
- Search filters the survey list exactly as v1 does (same fields).

### 2. Stage pills plus a filter button

**Pill row**
- On compact, replace `tabBar` with the board's pill row: `ทั้งหมด` · `งานติดตั้ง` · `บำรุงรักษา`, then a 44 pt round filter button.
- Pills are 44 pt capsules with count chips. On: `Theme.navySolid` fill, white bold text. Off: `surface` fill with a `borderSubtle` stroke.
- Mapping:
  - `ทั้งหมด` = `JobStage.survey` (count = survey jobs).
  - `งานติดตั้ง` = `.install` (count = stations).
  - `บำรุงรักษา` = `.maintenance` (count = stations).
- Keep each count on one line.
- The v1 survey filter pills row (`ทั้งหมด` / `กำลังทำ` / `ร่าง`) is removed; its job moves into the popover below.

**Filter button** (`icons/filter.svg`): shown on the `ทั้งหมด` tab only. Hide it on the other two tabs, where the overviews have their own filters. States:
- Default: white fill, 1 pt `borderSubtle`, ink glyph.
- Open: `primarySoft` fill, 1 pt `primary`, `primary` glyph.
- Filtered (status ≠ all, or sort ≠ `แก้ไขล่าสุด`): `navySolid` fill, white glyph, and an 8 pt orange dot at top-right with a 2 pt ring in the fill colour.
- Accessibility label: `กรองและเรียงงาน: <status> <n> งาน · เรียง <sort>`.

**Popover `กรองและเรียง`** (state `03`)
- A 300 pt wide card anchored under the button: radius 18, 1 pt `borderOutdoor`, padding 12, a small arrow, **no shadow**. On iPhone, use `.popover` with `.presentationCompactAdaptation(.popover)`.
- Header: `กรองและเรียง` at 15 pt bold. On the right, `ล้าง` resets both choices; it is `inkMuted` and disabled when nothing is set.
- `สถานะงาน`: a 2 × 2 grid of tiles. Each tile has a dot and a 13 pt bold label, with a 20 pt bold count below. The tiles:
  - `งานทั้งหมด`
  - `กำลังสำรวจ`
  - `ร่าง`
  - `รอซิงก์`

  These are the v1 filters all / active / draft / unsynced (`shortTitle`). The selected tile is navy with white text.
- `เรียงตาม`: a segmented control with `แก้ไขล่าสุด` · `เลขที่` · `ความคืบหน้า`. These are the existing sort options; find them in `moreMenu` / the list heading.
- A full-width 44 pt `primary` button, `แสดง <n> งาน`, closes the popover. Choices apply live; the button only closes.
- The list heading shows the active status (`งานทั้งหมด` / `กำลังสำรวจ` / `ร่าง` / `รอซิงก์`).
- Hit areas: in the board the segments are 38 high and `ล้าง` is 32 high. Give both a 44 pt hit area.

The survey list, the cards and the FAB stay as in v1 (state `01`). The FAB shows only on `ทั้งหมด` and sits above the dock.

### 3. `•••` menu items move to the settings page

On compact, `moreMenu` goes away. Every item it had must stay reachable from the `ตั้งค่า` tab (section 7):
- `ซิงก์ทั้งหมด (n)`
- `เปิดจาก Google Drive`
- `นำเข้าไฟล์ข้อมูล (.json)`
- `สำรองข้อมูลทุกงาน`
- `ตั้งค่า`, the app-wide survey settings, as a row that opens `showSettings`.

### 4. `งานติดตั้ง` tab: installation overview (states `05`–`07`)

This replaces the install card grid on compact. It covers the **PWA project's** stations only.

**Summary card** (white, radius 16, padding 12/14, no shadow)
- A 64 pt ring (`icons/ring-64-install.svg`):
  - The arc is the actual %, as the kWp-weighted average of station actual %, in `Theme.primary`.
  - A navy tick marks the plan %, also kWp-weighted.
  - The centre text is 15 pt bold.
- `กำลังติดตั้ง n สถานี` at 17 pt bold.
- `<kWp> kWp · เฉลี่ย a% / แผน p%` at 13 pt.
- Then `ภาพรวมตามแผน` (green) or `ภาพรวมช้ากว่าแผน d%` (red), 13 pt bold.
- Three stat tiles: `ช้ากว่าแผน` (red tint), `ตามแผน` (blue tint), `เร็วกว่าแผน` (green tint).
  - Behind means actual − plan ≤ −threshold. Ahead means actual − plan ≥ +threshold.
  - The threshold is the `เกณฑ์ "ช้ากว่าแผน"` setting (default 2 %).
- `ผู้รับเหมา n ทีม` with `แตะเพื่อดูเฉพาะทีม`, then a grid of 4 contractor buttons, each 48 pt.
  - Each button shows `ผู้รับเหมา A` and `n สถานี · ช้า m`. The `ช้า` part is red and is left out when m is 0.
  - Tap filters the rows to that contractor; tap again clears the filter.
- Daily report strip: orange tint, 44 pt, `icons/daily-report.svg`, text `รายงานประจำวันวันนี้ x/n ส่งแล้ว · ยังไม่ส่ง y สถานี ›`. It opens the daily report list (the routine reports screen, `-screen dailies`).

**Row filter pills** (40 pt, 44 pt hit area)
- `ช้ากว่าแผน n` (the default)
- `ยังไม่ส่งรายงาน n`
- `ทั้งหมด n`

**Station rows**, sorted by actual − plan, lowest first:
- Top line:
  - `MP <no>`.
  - A status chip: `ช้ากว่า d%` (red), `ตามแผน` (blue) or `เร็วกว่า d%` (green).
  - On the right: `รายงานวันนี้ ✓` (green) or `ยังไม่ส่งรายงาน` (orange).
- The station name at 15 pt bold on one line, plus `kWp`.
- An 8 pt bar (`icons/plan-bar.svg`): the actual fill is red when behind, otherwise `primary`. A 2 × 14 navy tick marks the plan.
- Bottom line: `a% / แผน p% · <current MP task>`. On the right: `ผู้รับเหมา X · ส่งมอบ dd/MM`.
- Tap opens that station's job, the same destination as the install card today.
- When the filter matches nothing, show `ไม่มีสถานีในตัวกรองนี้`.
- The list scrolls under the dock (section 6).

**Data**
- Actual % and plan % come from each job's MP plan (`docs/specs/master-schedule-swift.md`, `MPScheduleScreen`).
- Today's report status comes from the routine daily reports (`docs/specs/routine-reports-swift.md`).
- Both live in the **app target**, while `SurveyHomeView` is in `TCRoofKit/SurveyUI`. Don't make SurveyUI import the app. Instead:
  1. Add a value type to `TCRoofCore`, `InstallStationSummary`, with these fields: id, MP no, name, kWp, actual, plan?, current task, contractor, due date, report sent today.
  2. Have the app inject `[InstallStationSummary]` from `SolarSurveyEntry`, as an environment value or an init parameter.
  3. If nothing is injected, fall back to `InstallInfo` (`percent`, `team`, `dueDate`) with plan = nil. That means no tick and no behind / ahead chip.
- Contractor: find where a job's `ผู้รับเหมา` is stored (`ContractorWorkView`, the MP plan). If it isn't stored anywhere, group by `InstallInfo.team` and report that.
- "PWA project only" uses the same rule the survey home already uses for its list. Reuse it.

### 5. `บำรุงรักษา` tab: O&M overview (states `08`, `09`)

**Summary card**
- A 64 pt green ring (`icons/ring-64-maintenance.svg`) showing today's energy ÷ expected energy.
- `ส่งมอบแล้ว n สถานี`.
- `<kWp> kWp · PR เฉลี่ย x%`.
- `วันนี้ผลิต E / คาด X kWh`.
- Stat tiles: `ปกติ` (green) · `แจ้งเตือน` (red) · `ออฟไลน์` (grey).
- `งานที่ถึงกำหนดใน 14 วัน`: up to 3 rows. Each row has a date (blue bold, 44 wide), the task, and who does it.

**Filter pills**
- `มีปัญหา n` (the default)
- `ใกล้ถึง PM n`
- `ทั้งหมด n`

**Station rows**
- Top line: `MP <no>`, a status chip, and on the right `แจ้งซ่อม n งาน` (orange) or `ไม่มีงานซ่อม` (grey).
- The station name and kWp.
- An 8 pt bar of energy ÷ expected, in the status colour.
- Bottom line: `E / คาด X kWh · PR x%`, with a note on the right.

**Data**
- There is no monitoring feed yet. Build on a `MaintenanceStationSummary` value type with an empty default.
- Keep `stageEmpty` (`ยังไม่มีงานบำรุงรักษา`) when the list is empty.
- Add a DEBUG seed with the board's example values (section 9).
- Don't invent a data source.

### 6. PWA tab dock (state `18`)

The PWA module gets its own floating dock, styled like the main iPhone home dock in `docs/ui/tcroof-home-iphone-v3` (section 0). If that dock's view (`TCTabDock` or similar) is already built, reuse it with different items. If it isn't, build it in `TCRoofUI` so both docks can share it.

**Dock**
- Inset 12 pt from the sides and 22 pt from the bottom.
- `surface` fill, 1 pt `borderOutdoor`, radius 28, padding 5, **no shadow**.
- Items are 56 high with radius 22, a 23 pt glyph and an 11 pt label.
- Selected item: `navySolid` capsule, white glyph and bold label.
- Unselected: `inkTab`.
- A 1 pt divider before `ตั้งค่า`.

**Items, in order**

| Label | Asset | Opens |
|---|---|---|
| `หน้าหลัก` | `tab-home` / `house` | Leaves the PWA module and goes back to the TCRoof home |
| `โครงการ` | `tab-project` | This screen (the survey home). Badge = surveys due today. Accessibility label `โครงการ · นัดวันนี้ n` |
| `แผนงาน` | `tab-plan` / `calendar` | The PWA plan page (section 8) |
| `เอกสาร` | `tab-docs` | `StationDocsScreen` (เอกสารสถานี กปภ.). Orange badge = papers waiting to be sent. Label `เอกสารสถานี กปภ. · รอส่ง n` |
| `ตั้งค่า` | `tab-settings` / `gearshape` | The settings page (section 7). Label `ตั้งค่าโครงการ PWA` |

**Badge:** 17 pt, `danger` (or orange for `เอกสาร`), with a 2 pt white ring, at top `4` and left `50% + 5`.

**Fade and scrolling**
- Lists scroll **under** the dock.
- Add a 128 pt fade above the bottom: `phonePage` going from clear, to 85 % at 38 %, to solid at 62 %. It does not take touches.
- Give content 108 pt of bottom padding so the last row clears the dock.

**Hosting**
- When the PWA module is shown inside the main iPhone tabs (the `กปภ.` tab from v3), this dock **replaces** the main dock while the module is on screen.
- Pushed screens (a job editor) cover the dock, as the main tabs do.
- Each PWA tab keeps its own `NavigationStack` and scroll position.
- If v3 isn't built yet, host the dock in `SolarSurveyEntry`'s compact path.

### 7. `ตั้งค่า` is a page (state `17`, `PhonePwaSettings.dc.html`)

This replaces both the old gear sheet and `moreMenu`. It is a scrolling page under the same blue header: `PWA Setting`, with no search and no account card. It uses grouped cards: white, 1 pt `borderSubtle`, radius 16, rows at least 50 pt, and group titles at 12 pt bold `inkMuted`.

The groups:
- `โครงการ`: the project name with its station count and client; `สัญญาและระยะเวลา`.
- `ทีมงาน`: `ผู้รับเหมา` (count and letters); `ทีมควบคุมงาน TC`.
- `แผน MP`: `น้ำหนักงานมาตรฐาน`; `เกณฑ์ "ช้ากว่าแผน"` (default 2 %, used in section 4).
- `รายงานประจำวัน`: the toggles `แจ้งเตือนก่อนหมดเวลาส่ง` and `เตือนเมื่อผู้ตรวจยังไม่รับทราบ` (both default on); the row `ผู้ตรวจงานเริ่มต้น`.
- `เอกสารและซิงก์`: `แม่แบบรายงาน`; the toggle `ซิงก์รูปขึ้น Google Drive อัตโนมัติ`; the action row `ซิงก์ทั้งหมดตอนนี้`.
  - The action row's pill shows `ซิงก์ n` in `primary`, or `ครบแล้ว` in green.
  - It runs the existing sync-all.
- `ข้อมูล`: `เปิดจาก Google Drive`, `นำเข้าไฟล์ข้อมูล (.json)`, `สำรองข้อมูลทุกงาน`. These are the existing actions.
- Add one row the board doesn't show: `ตั้งค่าแอป`, which opens `showSettings`. Without it, the app-wide survey settings would be unreachable on compact.
- A footer: `TCRoof <version> · ใช้กับงานของ กปภ. เท่านั้น งานอื่นไม่เปลี่ยน`. Read the version from the bundle; `2.4` in the board is an example.

How the rows behave:
- Rows that link to screens that already exist open them.
- Rows with no screen yet show `›` and do nothing. List them in your report.
- The toggles are new **optional** settings. Store them with the survey settings, and keep old settings JSON decoding (`decodeIfPresent` with defaults).
- `DriveSync` may already have an auto-upload setting. Find it and reuse it.

### 8. `แผนงาน` page: phase 2, reference only

`PhonePwaPlan.dc.html` (states `11`–`13`) shows three views:
- `ตารางงาน`: a week strip and an agenda.
- `แผน MP`: an S-curve and a Gantt chart.
- `กำหนดส่ง`: a due list with a select filter.

**Don't build it in this task.** For now, the `แผนงาน` tab opens what already exists: `MPOverviewView` (แผน MP ทุกสถานี). If that can't be reached from SurveyUI, open the main plan calendar through the same injection pattern as section 4. Say which one you used. The `เอกสาร` page design (`14`–`16`) is reference too; the tab opens `StationDocsScreen` as it is.

### 9. DEBUG launch arguments

Add these to CLAUDE.md under "Simulator checks".
- `-surveyHomeTab all|install|maintenance|plan|docs|settings` picks the stage pill or the dock tab.
- `-surveyHomeSearch YES` opens the search.
- `-surveyHomeFilter YES` opens the filter popover. `-surveyHomeFilter draft` sets status `ร่าง` and sort `ความคืบหน้า` (state `04`).
- `-surveyHomeDemo install|maintenance` seeds the board's example stations. The install seed has 12 stations with the board's numbers, so the screenshots match.

## Keep

- The data rules in CLAUDE.md:
  - No change to `Values`, field ids or Excel cells.
  - New settings and types are optional.
  - Old JSON still decodes.
- Colours come from `Theme`, with no hex and no `Color.white` in views.
  - Board hex maps to `primary`, `navySolid`, `inkMuted`, `inkTab`, `danger`, `primarySoft`, `borderSubtle`, `borderOutdoor`, `phonePage` and `surface`.
  - Add a token only if none fits, and say which one you added.
- **No shadows** anywhere on these screens (the owner removed them).
- Hit areas are at least 44 pt.
- Split long view bodies into computed properties, because of the Debug type-checker limit in CLAUDE.md.
- New reusable views go in `TCRoofUI` and get a `ComponentGallery` entry.

## Check list

- [ ] `swift build` and `swift test` pass in `TCRoofKit/`, plus unit tests for the behind / ahead classification and the kWp-weighted averages.
- [ ] xcodebuild succeeds with your own `-derivedDataPath` (run it in the background).
- [ ] iPhone simulator screenshots of states `01`, `02`, `03`, `04`, `05`, `06`, `08`, `17` and `18`, taken with the new launch arguments and compared side by side with `states/`.
- [ ] The search animation runs with the 0.1 s delay, and Reduce Motion gives a cross-fade.
- [ ] Every old `moreMenu` action is reachable from the `ตั้งค่า` tab.
- [ ] The last list row clears the dock, and content fades behind it.
- [ ] The iPad survey home is unchanged (screenshot `-screen pwa` on an iPad simulator).
- [ ] `PhoneSurveyUITests` and `HomeNavbarUITests` still pass, or are updated where they tapped the search field, `•••` or the survey filter pills.

## Open questions (report back)

1. **`หน้าหลัก` in the PWA dock.** Should it leave the module, which means the main dock comes back? Or should the PWA dock only ever appear under the main `กปภ.` tab?
2. **Maintenance data source.** Where should maintenance energy, PR and alarms come from: the inverter monitoring API, manual entry, or Drive?
3. **Install overview on iPad.** Should it also exist on iPad, or stay iPhone only?
4. **Settings rows without screens.** Which of them need new screens: contract dates, contractor list, report templates, default inspector?
5. **`แผนงาน` page.** Should phase 2 build the PWA plan page (`PhonePwaPlan`) as designed, or keep using `MPOverviewView`?
