# Claude Code task: iPhone install tracking page (`ติดตามงานติดตั้ง PWA`)

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/install-tracking-iphone` and type
> `Follow docs/ui/install-tracking-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels: keep them exactly.

**Do only what this task lists.** Do not refactor, rename or restyle anything outside the change list in §5.
Do not touch the iPad layout of `InstallTrackingPage`, the survey module, the PWA home, or other tabs.

**Example data.** Every station, date, percentage, person and count on the board is example data
(`assets/sample-data.json`). "Today" on the board is พ. 21 ต.ค. 2569 (2026-10-21). In the app, use the real `Job`,
`MasterSchedule` plan and actuals, daily reports, `IECReport`, `StationDocs` and today's date. Never hard-code a board value.

## 1. Context

- On iPad, a PWA station being installed opens `InstallTrackingPage` (`TCRoof/Views/Install/Tracking/`,
  `docs/ui/install-tracking-ipad`, `-v2`). It has a blue header, a tab bar, and the tabs `ภาพรวม` · `รายงานประจำวัน` ·
  `แผนก่อสร้าง` in place. The tabs `คำขอรายสัปดาห์`, `Weekly Report`, `ทดสอบ IEC 62446` and `เอกสาร` push their screens.
- On iPhone (compact width), the same tap opens `JobDetailView` instead:
  - `TCRoof/Views/Survey/PWARoot.swift`: `if sizeClass != .compact, jobs.pwaInstalling.contains(job) { InstallTrackingPage(job: job) } else { JobDetailView(job: job) }`
  - `TCRoof/Views/Survey/PWAPhoneTabs.swift`: `.navigationDestination(item: $station) { JobDetailView(job: $0) }`
- The owner finished the board **`iPhone · ติดตามงานติดตั้ง PWA`** (`PhonePwaInstall.dc.html`, 390 × 844). It is the
  compact counterpart of the iPad page. On iPhone, an installing PWA station must now open this page.

**Scope: compact width only.** On a regular width, keep exactly today's behaviour.

## 2. Before you start

Start with code-review-graph, as `CLAUDE.md` says:

- callers and callees of `InstallTrackingPage`, `InstallPageData`, `InstallDailyData`, `InstallGantt`, `InstallPlan`,
  `InstallStageSheet`, `PWARoot`, `PWAPhoneTabs`, `PhoneTabs`, `TCTabBar`, `TCDockFade`
- the screens this page opens: `WeeklyRequestScreen`, `RoutineSummaryScreen`, `StationDocsScreen`, `IECTestScreen`,
  `MPScheduleScreen`, `DailyReportScreen`, `DailyReportListView`, `JobDetailView`, `JobAccessCard`
- `MPWorkbook` (import / export) and `tests_for` on anything you touch

Then read the source, and open `PhonePwaInstall.dc.html` as text. Its `renderVals()` holds every rule the board shows,
in a readable form. The dashed `ตัวอย่างสถานะ` pill bar at the top (`NO.154 ตามแผน` / `NO.120 ช้ากว่าแผน`) only
switches between example stations. **It is not part of the app.**

## 3. Files in this folder

| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `PhonePwaInstall.dc.html`, `grf.css` | The board (open as text; the `{{…}}` holes are filled by `renderVals()`) |
| `preview.png` = `states/01-overview.png` | Default: `ภาพรวม`, station on plan. @2x (780 × 1688) |
| `states/02-overview-late.png` | `ภาพรวม`, a station behind plan: red stage bar, hatched `+n วัน`, red KPIs |
| `states/03-overview-scurve.png`, `04-overview-scurve-late.png` | `ภาพรวม` with `S-Curve` selected |
| `states/05-overview-site-risk.png`, `06-overview-site-labour.png` | Site panel: `ความเสี่ยง` and `แรงงาน` |
| `states/07-daily.png`, `08-daily-todo.png` | `รายงานประจำวัน`, all and `ต้องทำ` |
| `states/09-weekly-request.png` | `คำขอรายสัปดาห์` |
| `states/10-weekly-report.png` | `Weekly Report` |
| `states/11-iec.png`, `12-iec-not-started.png` | `ทดสอบ IEC 62446`, in progress and not started |
| `states/13-docs.png` | `เอกสาร` |
| `states/14-plan-gantt.png`, `15-plan-gantt-late.png` | `แผนก่อสร้าง` Gantt, on plan and late |
| `states/16-plan-table.png`, `17-plan-edit.png` | `ตาราง` view, and edit mode (reason strip, steppers, locked rows) |
| `states/18-plan-excel-menu.png`, `19-plan-import.png` | `Excel ▾` menu, and the import sheet |
| `states/20-settings.png`, `21-settings-team.png`, `22-settings-routine.png` | The header gear: `ตั้งค่าเฉพาะโครงการ` list and two categories |
| `full/*.png` | Each tab as one full-length capture (the whole scroll), for reading the order of cards |
| `assets/sample-data.json` | The board's example values: stations, the 7-stage WBS, milestones, IEC steps, settings categories |
| `screenshots/` | Put your simulator screenshots here |

## 4. The page

Compare the board as you go. All sizes are points at 390 pt width.

### 4.1 Shell

- **Header:** the blue gradient (`Theme.headerGradient`), bottom corners 15.
  - Left: the station name (19 bold, one line) and `{kWp} kWp · ทีม {team} · {contractor}` (13, 92 % white).
  - Right: two **round** 44 pt buttons (white 18 % fill, white 40 % stroke):
    - `ผู้ช่วย` (sparkles). It opens the project assistant, as on iPad, and is shown only when `permissions.can(.assistantUse)` and the job has a plan.
    - A gear, `ตั้งค่าเฉพาะโครงการ` (§4.9). While it is open, the gear is white with a blue icon and the tab strip is hidden.
  - The board has **no back button** (the owner removed it): use the navigation stack's back swipe (see §7, Q2).
- **Tab strip:** one horizontally scrolling capsule track (`#E3EAF3`, radius 14, 4 pt inset).
  - Pills in order, each with an icon: `ภาพรวม` · `รายงานประจำวัน` · `คำขอรายสัปดาห์` · `Weekly Report` · `ทดสอบ IEC 62446` · `เอกสาร` · `แผนก่อสร้าง`.
  - The selected pill is white with a shadow. `รายงานประจำวัน` has the orange dot when today's report isn't sent (`data.dailyUnsent`).
  - Selecting a pill scrolls it into view.
- **Dock:** the main iPhone dock (`หน้าหลัก · งานบ้าน · กปภ. · เอกสาร · ตั้งค่า`, `กปภ.` selected) stays visible on this page, with
  `TCDockFade` behind it. Content scrolls behind it and ends above it (bottom padding ≈ 132). See §7, Q1.

### 4.2 `ภาพรวม` (states 01–06, `full/overview*.png`)

Top to bottom:

1. **Summary card:** a 2 × 2 grid of KPIs from `data.tracking`:
   - `ความคืบหน้า`: actual %, note `แผน n% · ▲n% สัปดาห์นี้`
   - `กำหนดการ`: `ตามแผน` / `ช้ากว่าแผน` / `เร็วกว่าแผน`, ± %
   - `คาดส่งมอบ`: forecast date, with `ตามกำหนด` or `ช้า n วัน`
   - `SPI`: 2 decimals, `ปกติ` or `ต่ำกว่าแผน`

   Under the grid, a full-width row `ต้องดำเนินการ` with `n เรื่อง` (orange) and the first titles. It opens the actions sheet (`Sheet.actions`). These are the iPad KPI strip's cells and rules (`InstallTrackingPage.cells`), laid out 2 × 2.
2. **`ความคืบหน้าเทียบแผน` card:**
   - Header: the date range line, the forecast chip (green `คาดส่งมอบ d/m ตามกำหนด` or red `คาดส่งมอบ d/m · ช้า n วัน`), and a `Gantt | S-Curve` segmented switch.
   - **Gantt:** a sticky 150 pt left column with stage rows (status circle ✓ or number, name, `งานย่อย x/n · p%`). A stage row toggles its sub-tasks; the running stage starts open. The rest scrolls horizontally in 30 pt day columns:
     - Header rows: weekday, date (today a red pill), and the weather icon with rain chance from today on (≥ 50 % red).
     - Columns: today tinted with a red line, Sundays tinted, the wait-for-utility day hatched.
     - Bars: plan as a pale track, actual solid (green when done, blue while running, red when behind), forecast as a dashed outline, and the overrun past plan hatched red with a `+n วัน` label.
     - Two rows under the stages: `เหตุการณ์สำคัญ` (diamonds; filled when passed) and `งวดเบิกเงิน (ตัวอย่าง)`.
     - The strip opens scrolled so today is in view.
     - This is the iPad overview Gantt (`InstallTrackingPage+Progress.swift`, `InstallGantt`, `InstallAxis`) on a narrow width.
   - **S-Curve:** cumulative plan (grey), actual to today (blue, area under it), forecast dashed to the end, the today line with a `วันนี้ d/m` tag, `แผน n%` / `จริง n%` labels, and daily bars (plan grey, actual blue). It comes from `data.curveDays`, as on iPad.
3. **`เอกสารโครงการ`:** a 2-column grid of tiles (dot colour, title, status chip), from `data.docs` (`DocTile`). A tile opens what it opens on iPad (`InstallPageData.Target` → `go(_:)`). On the board, some tiles switch to this page's own tabs (Daily → `รายงานประจำวัน`, Weekly → `Weekly Report`, Test & Commissioning → `ทดสอบ IEC 62446`, ขนานไฟ and ส่งมอบงาน → `เอกสาร`).
4. **Site panel:** a segmented control `ข้อมูลหน้างาน · ความเสี่ยง n · แรงงาน` (`SiteTab.info / .risk / .labour`):
   - `ข้อมูลหน้างาน`: installed quantities with bars, and four stat tiles (แรงงานวันนี้, PPC, ความปลอดภัย, ปัญหาที่เปิดอยู่)
   - `ความเสี่ยง`: level chip (`สูง` / `กลาง`), title, `รับมือ: …`, owner
   - `แรงงาน`: plan vs actual crew bars per day with the totals line

   It uses the data of `InstallTrackingPage+Site.swift` (`data.site`). Show only what has a source. Where iPad hides a section, hide it here too.

### 4.3 `รายงานประจำวัน` (states 07–08)

- A 2 × 2 summary card: `ส่งแล้ว`, `รอลงนาม · รับทราบ`, `วันนี้ d/m`, `คน·วันรวม`, with the iPad `dailyKPI` values.
- Filter capsules `ทั้งหมด n` · `ต้องทำ n` · `มีปัญหา n`, and a square `PDF รวม` button (download icon).
- One card per day, newest first:
  - Day badge, title, sub-line, status chip, and the cumulative % bar with the plan tick and a `±n เร็วกว่า/ช้ากว่า` chip.
  - A problem line (orange) when there is one.
  - A full-width action: `ทำรายงานวันนี้` / `ทำต่อ · ส่ง` (primary), or `เปิดรายงาน` (outline). It opens `DailyReportScreen` for that day.
  - Today without a report gets a light red card.
- **The engineer / inspector / photo-count chips were removed by the owner: do not show them.**
- At the end: an outline button `สร้าง Weekly Report W.. จากรายงาน n ฉบับ`.
- Source: `InstallDailyData` (`InstallTrackingPage+Daily.swift`).

### 4.4 `คำขอรายสัปดาห์` (state 09)

A compact summary of R1 for next week:

- The header card: status chip, the `‹ สัปดาห์ที่ n ›` switcher, the `ส่งก่อน …` deadline, and a 3-step stepper (`ร่างคำขอ → ส่งขออนุมัติ → อนุมัติ`).
- Two buttons, `ดึงจากแผน MP` and `ดู PDF`.
- The cards `1 แผนงาน` (task rows with a 6-day grid; tags `จากแผน MP` / `ยกมา` / `ยังไม่มีวัน`), `2 กำลังคน`, `3 เครื่องมือ` (rows with −/+ steppers), and `ตรวจก่อนส่ง`.
- The signature area and `ส่งขออนุมัติ (PDF)`.

Data and every rule (contractor vs team, `sentAt`, approved = read only, `WeeklyRequest.trusting`) come from
`WeeklyRequestScreen` / `RoutineReport.WeeklyRequest`. Reuse its model and actions. If the summary's inline editing would
duplicate `WeeklyRequestScreen`, show the summary read only and make the cards open `WeeklyRequestScreen` (say which you chose).

### 4.5 `Weekly Report` (state 10)

- The header card: `สร้างอัตโนมัติทุกอาทิตย์ 18:00 · จากรายงานประจำวัน`, the week switcher, the `รอข้อมูล → พร้อมส่ง → ส่งแล้ว` steps, and the due line.
- A slide preview with a horizontally scrolling strip of 8 thumbnails (green / orange dot).
- `ความพร้อมก่อนส่ง n/4`: rows, with `ไปแก้` on an unmet row (it opens `รายงานประจำวัน`).
- Recipients chips, the download button (PPTX / PDF, `WeeklySlides`), and `ส่งให้ n ผู้รับ` (disabled until ready).
- Source: `RoutineSummaryScreen(period: .week)` and `WeeklySlides`.

### 4.6 `ทดสอบ IEC 62446` (states 11–12)

- A header card: status chip, the line `ครบ n/7 ขั้น · …`, a 7-segment bar, and three fact tiles (อินเวอร์เตอร์, สตริง, ผู้ทดสอบ).
- The 7 steps of `IECReport+Stages`, each with a done / current / todo mark and its missing line.
- The buttons `ทำต่อ · ขั้น n …` (or `เริ่มตั้งค่าการทดสอบ`) and `ดูชีต Excel`. Rows and buttons push `IECTestScreen` (at that step where the screen supports it).

### 4.7 `เอกสาร` (state 13)

- The summary `n / N ฉบับเรียบร้อย` with a progress bar, legend counts, `อัปโหลด`, and `ส่งออกชุดเอกสาร`.
- `เส้นทางขออนุญาต`: three stage cards (ring, agency, title, chip). Below 200 kVA the ERC stage reads `ไม่ต้องยื่น`. Tapping a card selects it.
- The selected stage's papers: a PDF badge coloured by state, code, title, source, three dots `ร่าง → ยื่น → อนุมัติ`, and a chip.
- A row opens `StationDocsScreen` at that paper. Source: `TCRoofCore/StationDocs`, `ERCFlow`.

### 4.8 `แผนก่อสร้าง` (states 14–19)

This is the iPad tab (`InstallTrackingPage+Plan.swift`, `docs/ui/install-tracking-ipad-v2` §6) at phone width:

- **Header card:**
  - `แผนก่อสร้าง` with the revision chip (`Baseline REV 01`, `REV 0n · รออนุมัติ`, or orange `ร่าง REV 0n` while editing), and the approval and date line.
  - Four stat tiles: `ระยะเวลา`, `วันทำงาน`, `งานย่อย`, `สถานะแผน`.
  - A `Gantt | ตาราง` switch, and the buttons `แก้ไขแผน` · `Excel ▾` · `PDF`. While editing they become `ยกเลิก` · `บันทึก REV 0n · n งาน`.
- **Gantt:** a sticky 150 pt column with WBS and name (stages bold, 2 lines; sub-tasks indented, 1 line). Day columns are 30 pt.
  - Today is tinted with a red line, Sundays are tinted, and the wait day is hatched.
  - Stage bars show a % fill with a red critical outline. Sub-task bars use the status colour; float is a dotted line.
  - There is a `Milestone` diamond row and a legend.
  - It opens scrolled to today, and a stage row toggles its sub-tasks.
- **Table:** a horizontally scrolling grid with a sticky first column: WBS · งาน, เริ่ม, เสร็จ, วัน, คน, ต่อจาก, สถานะ.
- **Edit mode:**
  - It switches to `ตาราง` and shows the orange strip `กำลังแก้ไข · ร่าง REV 0n` with a required reason field.
  - Rows get `‹ ›` for the start, and `− +` for the days and the crew. Changed cells are highlighted orange. Done rows are locked (🔒).
  - `บันทึก` is enabled only with at least one change **and** a reason. `ยกเลิก` restores the values from before editing.
  - Saving creates the next revision for approval, as the iPad plan edit does.
- **`Excel ▾`** opens a menu with two items:
  - `นำเข้าไฟล์แผน (.xlsx)` opens a bottom sheet:
    - the picked file
    - the checks (station name matches, plan read, formulas the app cannot work out)
    - the changed cells (old → new)
    - the mode `นำเข้าแผนทั้งหมด` / `รับเฉพาะความก้าวหน้า`
    - the green action button
  - `ส่งออก Excel`

  Use `MPWorkbook`, `MPWorkbook.FormulaCheck`, `Actual.merging` and the same flow the iPad page uses (`MPWorkbookFlow`). Do not build a new importer.
- **Under the Gantt:** `กำลังคนตามแผน` (bars, dashed team cap, over-cap days red), `Milestone` (diamond, date, `ผ่านแล้ว` / `อีก n วัน`), and `ความพร้อมขั้นถัดไป`. These show only when `InstallPlan` has a source, as on iPad.
- The board uses a generic 7-stage WBS (`assets/sample-data.json`). In the app, use the job's own plan rows and codes.

### 4.9 `ตั้งค่าเฉพาะโครงการ` (header gear; states 20–22)

The gear replaces the tab content with grouped inset lists, iOS Settings style:

- A station card with a `✓ ซิงก์แล้ว` chip.
- Groups:
  - `โครงการ`: `ทีมและสิทธิ์` · `หัวเอกสาร` · `แบบก่อสร้าง`
  - `การทำงาน`: `รอบรายงาน` · `ผู้ติดต่อหน้างาน` · `การเชื่อมต่อและ IEC`
  - `ข้อมูลอ้างอิง` (read only)
  - `ขั้นสูง` (red)

  Each row has a coloured icon tile, title, sub-line, a trailing summary (`3 คน`, `4 แบบ`, `จ – ส`, `Zero Export`) and a chevron.
- A category opens its rows: people with avatar and role chip, value rows, toggles, and `+ …` add rows. `‹ หมวดทั้งหมด` goes back.

Wire each row to the editor that already exists:

- people → `JobAccessCard` / `job.assign_team` (`Job.externals`, `supervisorEmail`, `teamMembers`)
- report cycle → `job.routineSettings`
- connection / ERC → `StationDocs` / `ERCFlow`
- IEC → the IEC set-up

Respect `permissions` exactly as those editors do. **Do not invent new stored fields.** A row with no existing source
stays out of the build and goes in your report (§7, Q4).

## 5. Change list

Work in this order and tick each item in your report.

1. [ ] **Routing (compact):** in `PWARoot` and `PWAPhoneTabs`, an installing PWA station (`jobs.pwaInstalling`) opens the new compact page on iPhone. Other stations keep `JobDetailView`. The iPad path is unchanged.
2. [ ] **Compact shell:** header (no back button; round `ผู้ช่วย` and gear buttons), the scrolling 7-pill tab strip with the unsent dot, and the dock kept visible (§4.1, §7 Q1). Put it in a new file `InstallTrackingPage+Phone.swift` (or `InstallTrackingPhone.swift`) and branch on `horizontalSizeClass` in `InstallTrackingPage.body`. Do not change the regular-width layout.
3. [ ] **`ภาพรวม`:** the 2 × 2 KPI card with the `ต้องดำเนินการ` row, the Gantt / S-Curve card (sticky column, weather row, forecast and overrun, milestones and payment rows, opens at today), the documents tile grid, and the site panel. Reuse `InstallGantt`, `InstallAxis`, `curveDays`, `DocTile` and `Site`.
4. [ ] **`รายงานประจำวัน`:** summary, filters with counts, `PDF รวม`, day cards without the sign / photo chips, and the Weekly Report button.
5. [ ] **`คำขอรายสัปดาห์`**, **`Weekly Report`**, **`ทดสอบ IEC 62446`**, **`เอกสาร`:** the in-page summaries of §4.4–§4.7. Their actions push the existing screens.
6. [ ] **`แผนก่อสร้าง`:** header, Gantt and table, edit mode with reason and revision, the Excel menu with the import sheet and export, crew, milestones and make-ready.
7. [ ] **`ตั้งค่าเฉพาะโครงการ`:** the gear page, wired to existing editors only.
8. [ ] **DEBUG flags:** `-installOpen YES`, `-installTab overview|daily|plan` and `-installSite …` also work on iPhone (`-screen pwa`). Add `-installTab request|weekly|iec|docs|settings` for the new in-page tabs, and `-installPlanEdit YES` for edit mode. Update `CLAUDE.md`'s simulator-checks section in one or two lines.
9. [ ] **UI test:** extend `InstallTrackingUITests` with an iPhone test, or add `PhoneInstallTrackingUITests`. Cover:
   - every pill opens its content
   - a stage row toggles its sub-tasks
   - `Gantt | S-Curve` switches
   - a document tile opens its target
   - `แก้ไขแผน` → change a row → `บันทึก` stays disabled until a reason is typed → `ยกเลิก` restores
   - the gear opens `ตั้งค่าเฉพาะโครงการ` and a category
   
   Use `-installDemo YES` (nothing saved).
10. [ ] **Build and screenshots:** follow §6.

Out of scope: the PWA home cards, the iPad page, `JobDetailView`'s content, the survey module, and new Firestore fields or rules.

## 6. Check

- `cd TCRoofKit && swift build && swift test`, and an app build:
  ```
  xcodebuild -project TCRoof.xcodeproj -scheme TCRoof -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratch>/DerivedData build
  ```
  Use your own `-derivedDataPath` (the owner keeps Xcode open), and run it in the background.
- On an iPhone simulator, run:
  ```
  xcrun simctl launch <udid> com.tcroof.internal -screen pwa -installOpen YES -installDemo YES -installTab <tab> -noNotificationPrompt YES
  ```
  Capture each state of §3 to `screenshots/` (same file names) and compare them with `states/`. Spacing and colours follow `Theme`, not the board's hex values. No hex in views and no `Color.white` (`CLAUDE.md`).
- Hit areas are ≥ 44 pt. VoiceOver labels follow the board's `aria-label`s (for example the stage rows' `… · แสดงงานย่อย`).
- Light mode only. Very long view expressions break type-checking: split cards into computed properties.

## 7. Open questions (report your answers; do not block on them)

1. **Dock on a pushed page.** The board keeps the main dock on this page, as iPad does. On iPhone, `PhoneTabs` covers the dock when a screen is pushed. Keep the dock for this page only (preferred by the board), or follow the iPhone convention?
2. **Back navigation.** The owner removed the header's back button. Is the edge swipe enough, or should the system back button show?
3. **WBS codes.** The board's plan uses stage codes 1–7. The PWA home cards show MP codes (`2.5 ติดตั้ง Inverter`). The app should show the job's real codes everywhere; confirm nothing else is expected.
4. **Settings rows without a source** (for example `หัวเอกสาร`, `แบบก่อสร้าง` revisions, `ขั้นสูง` actions): list which ones you left out.
5. **Payment milestones** (`งวดเบิกเงิน`) are example data on the board. Is there a source, or should the row be hidden until there is one?
