# Claude Code task: iPad install tracking v2: Gantt and S-curve redesign, page fits above the dock, `แผนก่อสร้าง` tab (board 17 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and paste `PROMPT.md`, or type
> `Follow docs/ui/install-tracking-ipad-v2/CLAUDE_CODE_TASK.md`

- **Board:** `iPad · ติดตามงานติดตั้ง + ภาพรวมโครงการ (โครงการเดียว)` (`iPadInstall.dc.html`, 1366 × 1024 pt, landscape).
- Thai strings in `backticks` are literal UI labels.
- **Everything in the previews is example data:** NO.098, dates, steps, %, crew, weather, milestones. Never hardcode it.

## What exists (v1 is built)

- `docs/ui/install-tracking-ipad` is implemented: `TCRoof/Views/Install/Tracking/`:
  - `InstallTrackingPage` (frame, tabs `overview` / `daily`)
  - `+Progress` (Gantt / S-curve card)
  - `+Daily` (รายงานประจำวัน tab)
  - `+Site`, `InstallPageData`, `InstallDailyData`, `InstallStageSheet`
- The tab bar's `แผนก่อสร้าง` item routes to `MPScheduleScreen` today (`Item(id: "plan", … route: .plan)`).
- **This task changes only what the board changed since v1** (the change list below). Everything else stays.

## Scope

- **In scope:** iPad regular width, the install tracking page only.
- **Do not touch:**
  - the iPhone
  - `MPScheduleScreen` and the routine report, IEC and station docs screens (keep linking to them)
  - `MasterSchedule` stored fields, `InstallInfo` stored fields, the PWA home
- **Data rule (same as v1):** show only what has a source.
  - Crew per task, predecessors and a baseline revision may have **no model**.
  - When they don't, hide the element and list it in the report. Do not invent numbers.
  - `-installDemo YES` may show the board's example values, for screenshots only.

**Before editing:** use code-review-graph (per `CLAUDE.md`), else grep. Read `InstallTrackingPage*.swift`, `InstallPageData.swift`, `InstallGantt` / `InstallAxis`, `MasterSchedule` (plan, actual, status, weights), and `InstallTrackingUITests`.

## Files in this folder

| File | Shows |
|---|---|
| `states/01-overview-gantt.png` | `ภาพรวม`, Gantt (= `preview.png`) |
| `states/02-overview-scurve.png` | `ภาพรวม`, S-Curve v2 |
| `states/03-overview-scrolled-end.png` | `ภาพรวม` at its end: documents grid and site panel fit above the dock |
| `states/04-daily-tab.png` | `รายงานประจำวัน`: the new 3-card bottom row |
| `states/05-plan-gantt.png` | The new `แผนก่อสร้าง` tab, Gantt view (stages 4 and 5 expanded) |
| `states/06-plan-table.png` | `แผนก่อสร้าง`, `ตาราง` view |
| `states/07-plan-collapsed.png` | `แผนก่อสร้าง` with every stage collapsed: the milestone row shows |
| `iPadInstall.dc.html` + `grf.css` + `assets/` | Design source. Read it as text: `renderVals()` holds every size, colour and rule. Search for `S`, `SUB`, `curveH2`, `GH`, and the `cp…` values of the new tab |
| `screenshots/` | Empty: put your simulator screenshots here |

Compare v1 with this board: `docs/ui/install-tracking-ipad/states/01`, `02`, `05`, `08` against these states.

## Change list

### 1. Header subtitle
- **Was:** `งานติดตั้ง NO.098 · สถานี… · 90 kWp · ทีม · เริ่ม · ส่งมอบ`.
- **Now:** `งานติดตั้ง <kWp> kWp · ทีม <team> · เริ่ม <d> · ส่งมอบ <d>`. The station name is already the title.

### 2. Overview Gantt card (`states/01`)
- **Card height:** the card ends just above the dock: `1024 − 114 − 14 − 52 − 14 − 18 − 96` pt on the board, i.e. the free height minus the dock's 96 pt.
  - Its rows scroll **inside** the card.
  - The day header, the `เหตุการณ์สำคัญ` row and the `งวดเบิกเงิน` row stay pinned.
- **Header:** after the subtitle, a green pill `คาดส่งมอบ <d> ตามกำหนด · เผื่อ n วัน`. It is red `ช้า n วัน` when late, from the existing forecast.
- **Bars:**
  - Capsule bars (fully rounded): stage 24 pt, sub-task 8 pt, overrun 16 pt.
  - The stage bar is the plan in a light track, with the actual fill over it.
  - The overrun stays hatched red with a `+n วัน` pill.
  - The forecast stays dashed.
- **Percent:** the right `%` column becomes a pill per stage (green done, blue current, grey waiting). Sub-task percents stay plain text.
- **Today:**
  - A red-tinted day column (`rgba(192,57,43,0.06)`) and a **solid** red line. v1 had a dashed line.
  - The weekday header keeps the red `30 พ` pill.
- **Sundays:** a light column tint (`#F8FAFC`).
- **Rows:**
  - The current stage row is tinted (`#F7FAFE`).
  - Expanded sub-task rows get a 1 pt left rule under the stage disc.
- **WBS (example data):** 7 stages × 4–5 sub-tasks = 34. The order follows the rooftop EPC sequence:
  1. `เตรียมงาน · รับวัสดุ`
  2. `โครงสร้างรองรับ (Mounting)`
  3. `ติดตั้งแผง · สายดินโครง`
  4. `ระบบ DC · สาย · MC4 · ตู้ DC`
  5. `อินเวอร์เตอร์ · ระบบ AC`
  6. `ทดสอบ IEC 62446-1`
  7. `ขนานไฟ · ส่งมอบ`

  `InstallInfo.steps` holds the labels for non-PWA jobs. **Report** whether to rename them: it is a display label only, `doneSteps` keeps counting 7, and nothing stored changes. PWA jobs take their tasks from the MP plan as now.

### 3. Overview S-curve v2 (`states/02`)
- **Removed:** the left summary panel (`แผนสะสม · งานจริงสะสม · ต่างจากแผน · คาดเสร็จ`) and the curve's own weather header. The chart is full width.
- **Chart, in the same card height as the Gantt:**
  - Y labels `0–100%` on the left, X day labels along the bottom. Sundays are pink, today is bold red.
  - Daily bars per day: plan in light grey, actual in blue, side by side, scaled ×3 so they read.
  - Area fills under the plan and the actual lines.
  - The forecast stays dashed.
  - A today band with a red `วันนี้ <d>` pill, and the gap between plan and actual at today as a short red segment.
  - Plan and actual labels at today (`แผน 52%`, `จริง 50%`).
  - An end dot with `คาดเสร็จ <d> · 100%`.
  - The utility-wait band is hatched, labelled `รอการไฟฟ้านัดตรวจ`.
- **Legend line under the chart:** `แท่ง = งานต่อวัน (แผน · จริง)` · `เส้นแดงที่วันนี้ = ห่างจากแผน`.

### 4. Overview end (`states/03`)
- The overview keeps 14 pt top and **96 pt bottom** padding, so the last cards end above the dock.
- `เอกสารโครงการ` and the site panel (`ข้อมูลหน้างาน · ความเสี่ยง · แรงงาน`) keep their v1 content.
- They scroll inside their own card when they don't fit.

### 5. `รายงานประจำวัน` tab (`states/04`)
- Same 96 pt bottom padding.
- The report table card has a fixed height (372 pt on the board), and its rows scroll inside it.
- **The bottom row becomes 3 equal columns:** `กำลังคนรายวัน` · `รูปตามงาน MP` · `พรุ่งนี้`.
  - **Remove** the `ความก้าวหน้าสะสม` card (the overview's S-curve shows it).
  - `รูปตามงาน MP` and `พรุ่งนี้` scroll inside.
  - `พรุ่งนี้` loses its coloured top border.

### 6. New in-page tab `แผนก่อสร้าง` (`states/05`–`07`)
The tab bar's `แผนก่อสร้าง` becomes a **third in-page tab** (`Tab.plan`), not a route.
- Keep `MPScheduleScreen` reachable from the tab's `แก้ไขแผน`.
- **Header card:**
  - Title `แผนก่อสร้าง` with a `Baseline REV nn` pill.
  - Sub line `อนุมัติ <d> · <approver> · <start> – <end>`.
  - Chips: `ระยะเวลา n วัน` · `วันทำงาน n วัน` (minus Sundays and wait days) · `งานย่อย n งาน` · `สถานะแผน ตามแผน / ช้ากว่าแผน`.
  - Segmented control `Gantt | ตาราง`.
  - Buttons `แก้ไขแผน` (opens `MPScheduleScreen`) and `ส่งออก PDF` (the existing MP plan PDF, `-mpDemo pdf`'s page; report if it can't take A3).
- **Gantt view:** a WBS grid.
  - **Columns:** `WBS` (1, 4.1 …), `งาน`, `วัน`, `คน`, `ต่อจาก`, then one column per day. Day headers show the weekday and date; today is a red pill.
  - **Stage rows** (40 pt):
    - A chevron expands and collapses the stage. Stages 4 and 5 start open, as the current stage and the next.
    - The bar is 20 pt, with a navy actual fill and a white `n%` label (no label on 1-day bars).
    - Green when done.
    - A **2 pt red outline** marks critical-path stages that aren't done.
  - **Sub-task rows** (32 pt): a 10 pt bar, green when done, blue in progress, grey `#AFC0D4` when planned.
    - A red ring marks a critical sub-task: no float, not done.
    - A dotted grey tail shows **float**, from the sub-task's end to its stage's end.
  - **Columns behind the bars:** the today column tinted, Sundays tinted, wait days hatched.
  - **Milestone row** at the end: diamonds on their days, green filled when passed, navy outlined when ahead.
  - **Legend:** `เสร็จ · กำลังทำ · ตามแผน · เส้นทางวิกฤต · เผื่อเวลา (Float) · รอการไฟฟ้า`, and on the right `ต่อจาก = งานก่อนหน้า (เสร็จ → เริ่ม)`.
- **Table view:** the same rows as a table.
  - Columns: `WBS · งาน · เริ่ม · เสร็จ · วัน · คน · ต่อจาก · สถานะ`.
  - Stage rows have a grey background and bold text; sub-tasks are indented.
  - A status pill: `เสร็จ / กำลังทำ / ตามแผน`.
- **Right column (340 pt):**
  - `กำลังคนตามแผน`: a bar per day of the planned crew, the sum of the active stages' crew.
    - Bar colours: past green, today blue, future grey, and red where it goes over the team.
    - A dashed line at the team size (`เส้นประ = ทีม n คน`).
    - Under it, `ไม่มีวันที่เกินกำลังทีม` (green) or `เกินกำลัง <days> · ขยับงานที่มีเวลาเผื่อ หรือเพิ่มคน` (red).
  - `Milestone`: each milestone with its date and a pill `ผ่านแล้ว` / `อีก n วัน`.
  - `ความพร้อมขั้นถัดไป` (`ขั้น n · <name>`): the next stage's make-ready list (✓ / !), the same source as the overview's make-ready.
- **Data:**
  - Dates, status and % come from `MasterSchedule` plan and actual (or `InstallInfo` for non-PWA jobs).
  - Float is the stage end minus the sub-task end.
  - Critical path: put it in `TCRoofCore`, as a function of the plan with a test.
  - **Report:** whether crew per task, predecessors and a baseline revision exist. Hide `คน`, `ต่อจาก`, the crew chart and the `Baseline REV` pill when they don't.
- **DEBUG:** `-installTab plan`, `-installPlanView gantt|table`, `-installPlanCollapsed YES`. Add one line to `CLAUDE.md`'s `-installOpen` item.

## Rules

- `Theme` tokens only:
  - Add `installCritical` (red outline), `installFloat` (dotted grey) and `installWait` (hatch) if they're missing.
  - No hex in views. `TCButtonStyle`. Hit areas ≥ 44 pt.
- Split big views into computed properties (CLAUDE.md, the `View.modifier` SIGSEGV).
- Keep `InstallTrackingUITests` and `InstallPerformanceUITests` passing. Extend `InstallTrackingUITests`:
  - `แผนก่อสร้าง` opens the tab.
  - A stage chevron collapses its sub-tasks.
  - `ตาราง` shows the table.
  - `แก้ไขแผน` pushes `MPScheduleScreen`.

## Check list

- [ ] Build with your own `-derivedDataPath`; `swift test` passes, with the new critical-path test.
- [ ] iPad Pro 13" landscape, `-screen home -homeTab pwa -homeBoard YES -installOpen YES -installDemo YES`: screenshots `01`–`07` in `screenshots/` (the same names as `states/`), compared with `states/`.
- [ ] The overview, daily tab and plan tab end above the dock with nothing hidden under it.
- [ ] `InstallTrackingUITests` passes with the new plan-tab test.

## Open questions (report, don't decide)

1. Rename `InstallInfo.steps` to the board's 7 EPC stage names?
2. Crew per task and predecessors: is there a source (MP plan, daily reports), or should the plan tab hide those columns?
3. `Baseline REV`: does the MP plan keep revisions? If not, hide the pill.
4. `ส่งออก PDF`: the existing MP weekly page, or a new A3 Gantt PDF?
