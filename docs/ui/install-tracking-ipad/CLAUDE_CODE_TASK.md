# Claude Code task: iPad install tracking page (one project): tabs, KPI strip, plan-vs-actual Gantt / S-curve, daily-report tab (board 14 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and paste `PROMPT.md`, or type
> `Follow docs/ui/install-tracking-ipad/CLAUDE_CODE_TASK.md`

- **Board:** `iPad · ติดตามงานติดตั้ง + ภาพรวมโครงการ (โครงการเดียว)` (`iPadInstall.dc.html`, 1366 × 1024 pt, landscape).
- Thai strings in `backticks` are literal UI labels.
- **Everything in the previews is example data:** NO.098, dates, steps, %, weather, people, RFI/NCR names, money instalments. Never hardcode it.

## What is built today, and what this task does
- **The page doesn't exist yet.** `InstallTrackingView` (`TCRoofKit/Sources/TCRoofUI/Survey/Home/InstallViews.swift`) is a placeholder: it says `อยู่ระหว่างพัฒนา`.
- **Where it opens from today:**
  - an install-mode `JobCard` (`SurveyHomeView.open(_:.install)` → `tracking`)
  - the PWA home's install rows and install-phase cards (`openStation`), which open `JobDetailView`
- **This task builds the iPad page.**
  - Its plan is the job's install steps: `InstallInfo.steps`, the 7 steps the board shows.
  - Its tabs lead to screens that **already exist**: daily reports, weekly request, routine summary, IEC test, station documents, MP schedule.
- **Work in phases (A → D below).** Stop and report after each phase with screenshots. Do not start the next phase if the previous one doesn't build.

## Scope
- **In scope:** iPad (regular width) only.
  - The page frame, tab bar, KPI strip and `ภาพรวม` tab (A–C).
  - The `รายงานประจำวัน` tab (D).
  - The other tabs only **link** to existing screens.
- **Do not touch:**
  - the iPhone
  - the survey wizard
  - `DailyReportScreen`, `WeeklyRequestScreen`, `RoutineSummaryScreen`, `StationDocsScreen`, `MPScheduleScreen` and the IEC test screens. Link to them; do not restyle them.
  - the PWA home
  - `PWAPlanBoard`
  - the existing data models' stored fields
- **Data:** only show what has a source.
  - Weather forecast, milestones / payment instalments (`งวดเบิกเงิน`), RFI/NCR/CO/MOM/material approvals, labour, safety, PPC and SPI may have **no model yet**.
  - For each: if there's no source, **hide that element** (no fake numbers) and list it in the report.
  - A DEBUG flag `-installDemo YES` may seed the board's example data, **for screenshots only**.

**Before editing:** use code-review-graph (per `CLAUDE.md`). If the server is not available, use grep.
- Look at: `InstallTrackingView`, `InstallInfo` (steps, `doneSteps`, `currentFraction`, team, due), `Job.installStart`, `installDays`, `installDay(on:)`
- Look at: `MasterSchedule` (plan/actual, `RoutineReport.permits`), `DailyReportListView`, `RoutineReportCard`, `DailyReportScreen`
- Look at: `StationDocsStore`, `PWARoot.openStation`, `JobDetailView`, `TCCountSegments`
- Then run `tests_for` on what you touch.

## Files in this folder
| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `preview.png` | The default state, the same as `states/01` (@2x) |
| `states/01-overview-gantt.png` | `ภาพรวม`: header, 7 tabs, KPI strip, Gantt with weather row, step 4 expanded with sub-tasks |
| `states/02-overview-scurve.png` | The same card on `S-Curve`: plan / actual / forecast lines, the summary panel on the left |
| `states/03-stage-open.png` | A step tapped: the step sheet (late cause chips, checklist 2/4, photos, `ยืนยันเสร็จขั้นนี้`) |
| `states/04-actions-sheet.png` | The KPI `ต้องดำเนินการ n เรื่อง` tapped: list of open items by priority |
| `states/05-daily-tab.png` | `รายงานประจำวัน` tab: KPI row, report table, and under it workforce, cumulative progress, photos per MP item, tomorrow |
| `states/06-weekly-report-draft.png` | The weekly report draft sheet (auto-filled from the page) |
| `states/07-document-sheet.png` | A document tile tapped (`Daily Report`): its list |
| `states/08-overview-scrolled-end.png` | `ภาพรวม` scrolled to the end: milestones, instalments, `เอกสารโครงการ` grid, `ข้อมูลหน้างาน` panel |
| `states/09-overview-end-risk.png` · `10-overview-end-labour.png` | The site panel on `ความเสี่ยง` / `แรงงาน` |
| `iPadInstall.dc.html` + `grf.css` | The design source. Read it as text: the markup and `renderVals()` hold every size, colour and rule (`S`, `SUB`, `status`, `rows`, `kpi`, `DOCS`, `WXI`) |
| `screenshots/` | Empty. Put your simulator screenshots here |

## Phase A: frame, tabs and KPI strip (`states/01`)
- **Opens from:**
  - `InstallTrackingView` on iPad, i.e. the install-mode `JobCard`
  - on the PWA home, a station whose stage is installation (install-phase card or install row), in place of `JobDetailView`
- `JobDetailView` stays reachable for stations that are not in installation. Report what you routed where.
- **Header**, blue gradient, bottom radius 20:
  - a 44 pt back button (white 18 % fill, white 40 % border)
  - the title = project name, 20 pt bold
  - the sub line, 14 pt: `งานติดตั้ง NO.xxx · <site> · <kWp> kWp · ทีม <team> · เริ่ม <d/m/yyyy> · ส่งมอบ <d/m/yyyy>`
  - on the right, the outlined button `🔒 รายงานสำรวจ (ดูอย่างเดียว)`: it opens the survey report read-only, as `.locked` cards do
  - the iPad dock stays visible, with `โครงการ` selected
- **Tab bar**, 12 pt under the header, 24 pt margins:
  - track `#E9EEF5`, radius 14, padding 4, 7 equal tabs, 44 pt high, radius 11
  - 15 pt bold with an 18 pt glyph
  - selected = white, navy text, shadow `0 1 3 rgba(14,30,56,.15)`; others `#3B4A60`
  - The same component is already in the iPad component library (`iPadComponents` tile `แถบแท็บโครงการ`).

  | Tab | Opens |
  |---|---|
  | `ภาพรวม` | Phases B–C, in place |
  | `รายงานประจำวัน` (+ 8 pt orange dot when today's report isn't sent) | Phase D, in place |
  | `คำขอรายสัปดาห์` | `WeeklyRequestScreen` (push) |
  | `Weekly Report` | the weekly report draft sheet (`states/06`), or the existing routine summary if it covers it; report which |
  | `ทดสอบ IEC 62446` | the job's IEC test, in place |
  | `เอกสาร` | `StationDocsScreen` (push) |
  | `แผนก่อสร้าง` | `MPScheduleScreen` / the plan calendar on this job (push) |

- **KPI strip:** one white card, 1 pt `#DDE4ED` border, radius 16, 5 cells split by 1 pt dividers.
  - Each cell: label 12 pt `#5B6B82`, then the value 22 pt bold, then a note 12 pt.
  - The cells:
    1. `ความคืบหน้า 50%` (primary) · `แผน 52% · ▲14% สัปดาห์นี้`
    2. `กำหนดการ ตามแผน` (green / red when late) · variance
    3. `คาดส่งมอบ 6/10` · `ตามกำหนด เผื่อ 1 วัน`
    4. `SPI 0.96` · `ปกติ`
    5. `ต้องดำเนินการ n เรื่อง` (orange) · the first items. Tapping it opens the actions sheet (`states/04`).
  - Hide a cell that has no source (e.g. SPI without a plan).

## Phase B: `ภาพรวม` Gantt and S-curve (`states/01`, `02`, `03`)
- **Card:** white, radius 16. Title `ความคืบหน้าเทียบแผน` 18 pt bold + `<start> – <due> · n ขั้นตอน · n งานย่อย`.
- **Top right:** the legend (`คาดการณ์` dashed, `เกินแผน` red, `◆ เหตุการณ์สำคัญ`) and a `Gantt | S-Curve` segmented control.
- **Day axis:** one column per day from start to handover.
  - Month labels.
  - Each day: weekday + date, and today's column is a red pill.
  - Under the dates, the **weather row** (icon + rain %, red when ≥ 60 %) with `พยากรณ์อากาศ · อัปเดต <time>`. **Only if there is a forecast source; otherwise hide the row.**
  - Weekends and non-working days are hatched.
  - Today is a red dashed vertical line.
- **Step rows:**
  - left: chevron, status disc (green ✓ done / blue number current / grey number waiting), name 15 pt bold, `งานย่อย x/y`
  - bars: plan in light grey, actual green when done / blue when current, forecast dashed outline, overrun red hatched with `+n วัน`
  - the step % on the right, coloured
- **Expanded step:** shows its sub-tasks (checklist items) as thin rows with a dot and a small bar.
  - The current step starts expanded; others toggle.
  - Sub-tasks come from the step's checklist. Use whatever `InstallInfo` or the daily reports keep. If nothing, list the step's checklist as in the board's `S` data and report.
- **Below the rows:**
  - `เหตุการณ์สำคัญ`: ◆ milestones on the axis, filled when done
  - `งวดเบิกเงิน`: instalments
  - **Each only with a source**; otherwise hide it.
- **S-Curve view** (`states/02`):
  - cumulative plan (grey), actual (blue, solid to today), forecast (blue dashed)
  - the today line, and `แผน x%` / `จริง y%` callouts
  - on the left, the summary panel: `แผนสะสม ณ วันนี้`, `งานจริงสะสม`, `ต่างจากแผน`, `คาดเสร็จงานติดตั้ง`
- **Step sheet** (`states/03`), on tapping a step row:
  - title `ขั้นที่ n/7 · <dates> · <scope>` + step name, status chip
  - **when late:** the red box `คาดว่าเกินแผน n วัน · สาเหตุ` with cause chips `สภาพอากาศ · วัสดุ · เจ้าของงาน · ผู้รับเหมา`. Save the picked cause **only if there's a field for it; otherwise report it.**
  - checklist `รายการตรวจ x/4` as toggles (done blue, pending soft orange)
  - photos with a camera tile
  - `ยืนยันเสร็จขั้นนี้`, enabled when the checklist is complete
  - Saving updates the job's install progress (`doneSteps` / `currentFraction`) as the existing install logic does.

## Phase C: the rest of `ภาพรวม` (`states/08`, `09`, `10`, `04`, `07`)
- **`เอกสารโครงการ` card** (left half): a 2-column grid of tiles. Each tile has a status dot, a name and a status chip:
  - `Daily Report`
  - `Weekly Report`
  - `Work Permit`
  - `MOM`
  - `RFI ขอตรวจงาน`
  - `Material Approval`
  - `NCR งานไม่ตรงสเปก`
  - `Change Order`
  - `Test & Commissioning`
  - `Punch List`
  - `ขออนุญาตขนานไฟ`
  - `อุปกรณ์ที่ติดตั้ง`
  - `ส่งมอบงาน`

  Header `ต้องดำเนินการ n` chip. A tile opens a sheet listing its items (`states/07`). **Show only the tiles that have a source today** (daily reports, weekly, station documents, IEC, permits), and list the rest in the report.
- **Site panel** (right half), tabs `ข้อมูลหน้างาน · ความเสี่ยง n · แรงงาน`:
  - installed quantities with bars (panels, strings, DC boxes, inverter …)
  - KPI tiles (people today, PPC, safety days, open issues)
  - **only with sources**
- **Actions sheet** (`states/04`): rows with a priority chip (`สูง` red / `กลาง` orange), title, sub line, `›` to the item.

## Phase D: `รายงานประจำวัน` tab (`states/05`)
- **KPI row:**
  - `ส่งแล้ว x / n วัน`
  - `รอลงนาม · รับทราบ`
  - `วันนี้ <date>` with `ยังไม่ส่ง` / `ส่งแล้ว`
  - `คน·วันรวม`
  - `หยุดเพราะฝน`
- **Table card `ทุกรายงาน`:** segments `ทั้งหมด n · ต้องทำ n · มีปัญหา n`.
  - Buttons: `สร้าง Weekly Report Wnn จาก n รายงาน` and `PDF รวม`, wired to what exists; report what doesn't exist.
  - **Columns:** วันที่ · สถานะ chip · อากาศ · คน · งานที่ทำ · สะสม (แผน MP) bar · รูป x/4 · ลงนาม/รับทราบ chips · ปัญหา · action button.
    - Today unsent: a red row, `ทำรายงานวันนี้`.
    - Draft: `ทำต่อ · ส่ง`.
    - Otherwise: `เปิดรายงาน`.
  - The rows are `DailyReportListView`'s data, and the buttons open `DailyReportScreen`.
- **Under the table, four cards:**
  - `กำลังคนรายวัน` bars
  - `ความก้าวหน้าสะสม` vs MP
  - `รูปตามงาน MP`
  - `พรุ่งนี้ <date>` (from the MP plan)

  Again, each only with a source.

## DEBUG
- `-installTab overview|daily`, `-installView gantt|curve`, `-installStage n` (opens the step sheet), `-installDemo YES` (board example data).
- Add them to CLAUDE.md.

## Check (after each phase)
- [ ] Build with your own `-derivedDataPath`. If you touched `TCRoofKit/`, run `swift build` + `swift test` there.
- [ ] Run on an iPad Pro 13" simulator, landscape, with `-installDemo YES`. Compare with the matching `states/` image and note any difference larger than 4 pt.
- [ ] With real data (no demo): sections without a source are hidden, not filled with zeros.
- [ ] Tabs that push open the existing screens, and back returns to the page.
- [ ] iPhone unchanged. The install-mode card on iPhone still opens what it opens now.
- [ ] Simulator screenshots in `docs/ui/install-tracking-ipad/screenshots/`:
  - A: 01
  - B: 02, 03
  - C: 08
  - D: 05

## Open questions (report, don't decide)
1. **Plan:** for a PWA station, should the Gantt use its MP plan (`MasterSchedule`, 2.x tasks) instead of the 7 `InstallInfo.steps`? Say what you used.
2. Which board elements had no data source (weather, milestones, instalments, RFI/NCR/CO/MOM, labour, safety, PPC, SPI, late cause)?
3. `Weekly Report` tab: is the draft sheet the same thing as the existing routine summary, or a new report?
