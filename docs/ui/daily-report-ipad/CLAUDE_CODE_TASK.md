# Task: iPad · รายงานประจำวัน, one page (key plan · MP plan)

Board: `iPadDaily.dc.html` (1366 × 1024; prop `step` = 0 is the one-page layout, the one to build). States: `states/*.png`.
Assets: `assets/daily/station-keyplan.jpg` (the board's A2 site picture of สถานีผลิตน้ำโชคชัย), `assets/daily/photo-1…4.jpg` (the real report's photos of 2 ก.ค. 2568), `assets/iec/photo-slot.svg` (empty photo slot).
These images are board examples only; don't ship them.

Branch: this hand-off lives on `design/daily-report-ipad` (cut from `feat/ipad-home-v3` 51c9508).
Work on `feat/daily-report-ipad` cut from it, and push it. Do not merge.

## What exists

- `TCRoof/Views/Job/RoutineReports/DailyReportScreen.swift` (+ `DailyReportSections`, `KeyPlanViews`, `RoutineReportSheets`, `RoutineReportSupport`): R2 of `docs/specs/routine-reports-swift.md`.
  Today on iPad wide it shows sections 1–6 on the left and photos on the right, with `บันทึกร่าง · ตรวจ & ลงนาม`.
- `TCRoofCore/RoutineReport.swift`: `Daily` (`workStart/End`, `weather[15]`, `crew`, `tools`, `materials`, `progress: [ProgressLine]` with `task: MasterSchedule.Task?`, `location`, `percent`, `problems`), settings with `locations`.
- The key plan: `Job.keyPlanPicture` (the A2 site picture) with a point per location from the report settings.
- The daily PDF (3 pages) and signing sheets already exist (`-routineDemo pdf|sign`).

## Scope: only this

Re-lay `DailyReportScreen` on **iPad regular width (≥ 1000 pt)** as the board's one-page layout. Keep the model, the PDF, the sign / acknowledge flow and the iPhone layout as they are.
Out of scope: the board's 4-step wizard mode (`step` 1–4), the iPhone, the PDF's look, `WeeklyRequestScreen`, R3 / R4.

## Change list

1. **Header** (blue): back, `รายงานประจำวัน · <weekday d MMM yyyy>`, station line.
2. **Layout:** left column (flexible, ~840 pt) and right column (384 pt), 16 pt gaps, 63 pt side margins (as the board). The page doesn't scroll; the cards do.
3. **Key plan card** (left, top, ~545 pt tall):
   - The A2 site picture (aspect fill, slightly desaturated) with the station's locations as labels.
   - Today's progress lines as numbered pins in the task's colour (1 blue, 2 green, 3 orange, 4 purple, 5 red), each with its location and `% today` (`หลังคา 1 · 100%`).
   - Areas: outline blue = worked today, green = done, grey = not started (legend chip bottom left: `ทำวันนี้ · เสร็จแล้ว · ยังไม่เริ่ม · + = งานตามแผน MP`).
   - **`+` ghost pins** for MP tasks planned this week that aren't in today's list. Tapping one adds a progress line for that task and location (10 %) and selects it.
   - Tapping a pin selects its line; the other pins dim to 35 %.
   - ⛶ opens the plan full screen (state 06): title `ผังสถานี · งานวันนี้ · <date> · แตะหมุดเพื่อเลือกงาน แล้วปิดเพื่อกรอก`, and a chip `ตรวจพบอัตโนมัติ n พื้นที่ · … · ตรวจใหม่` only if the app has detected areas (see open question 2).
   - No picture: show the locations as a simple list of chips with the same pins, and report it.
4. **Today's work** (left, under the plan):
   - **Task tabs:** one card per progress line, with the number pin, name, location, 📷 count and `+n%` today. The selected one has a 2 pt border in its colour.
   - **Selected task panel:**
     - Title, location, and `MP 2.1 · โครงสร้าง + Walkway · 20%` (the MP task and its weight).
     - Tools used (`ใช้ สว่านไร้สาย`, suggested from the task, e.g. 2.1 → สว่าน).
     - Status pill `✓ งานเสร็จ` or `เหลือ n%`.
     - Buttons: วัสดุ (box) adds a material row at this location; ปัญหา (⚠) adds a problem row; ✕ removes the line.
   - **`วันนี้` quick picks:** `+10% · +20% · +30% · +50% · เสร็จ`, capped at what is left of the task. The picked one is mint `#A8E6D4`-ish.
   - The line's photo thumbnails (numbered) + camera button.
   - **Bottom line:**
     - `0% → 100% · สถานี +4.0%`.
     - A progress bar.
     - `MP 2.1 รวม 44% / แผน 45% ช้ากว่า 1.0%`, the station % from `MasterSchedule` weights; red when behind.
   - Material and problem rows appear under the panel (state 08). Make this card scroll when they don't fit (the board clips them).
5. **Right column, top:** a day switcher `‹ พ. 2 ก.ค. 2568 ›` (moves to the previous / next report day) and a `เวลาทำงาน 08:00–18:00` chip. The chip cycles through the site's working-hour presets, or opens a picker; report which.
6. **ทีมงานวันนี้** card:
   - Header totals `9 คน · เครื่องมือ 4 รายการ`.
   - Two tiles:
     - `แรงงานวันนี้ 90 คน·ชม.` (9 คน × 10 ชม.).
     - `ทำงานได้จริง 54 คน·ชม.` (หักฝน n ชม.: rain hours inside the working time, from `weather`).
   - Segmented `คน n | เครื่องมือ n`.
   - **Rows with a dropdown** `7 คน ⌄`: a list 1–12 with the current value highlighted, and `ลบออก` in red at the top.
   - A dashed `+ เพิ่มตำแหน่ง ⌄` / `+ เพิ่มเครื่องมือ ⌄` dropdown listing only the catalogue items not in the list.
   - One dropdown open at a time. Every option is ≥ 44 pt (state 04).
7. **ลงนาม** card:
   - `ผู้รายงาน *` (SITE ENGINEER) and `ผู้ตรวจงาน` (INSPECTOR) signature boxes `แตะเพื่อเซ็น`, with name fields under them; `ลงใน DAILY REPORT หน้า 3`.
   - Reuse the existing sign sheet. A signed box shows the signature and time with a clear button (state 05).
8. **Bottom bar:**
   - Status: `ยังส่งไม่ได้ · <reason>` (orange !), or `ครบทุกส่วนแล้ว · พร้อมส่ง PDF 3 หน้า` (green ✓).
   - Buttons:
     - `บันทึกร่างตอนนี้`.
     - `PDF 3 หน้า · ดูตัวอย่างรายงาน` (the existing PDF preview).
     - `ส่งรายงาน ›`, disabled with the reason as its sub label until ready.
   - Ready = photos complete, reporter named and signed, as today's rule.
9. **Weather** (not visible in the one-page board): keep the existing 15-hour strip, reachable from the `เวลาทำงาน` chip's sheet or a small `อากาศ` row in the right column. Report where you put it.
10. **DEBUG:**
    - `-routineDaily onepage` forces this layout with `-screen daily`.
    - `-routineDailyState task2|tools|dropdown|signed|map|daybefore|material` reproduces states 02–08.
    - One line in CLAUDE.md.

## Rules

- Station % today = Σ (line % today × task weight ÷ task's location count); behind = plan % to date − actual. Put it in `TCRoofCore` (RoutineReport or MasterSchedule) with tests.
- Pins and ghost pins come from `settings.locations` positions on the key plan and this week's `MasterSchedule` tasks.
- Labour hours = crew × working hours; working = crew × (hours − rain hours in the working time).
- Colours from `Theme` (add the 5 task colours as tokens), `TCButtonStyle`, hit areas ≥ 44 pt, no hex in views.

## States

| File | What |
|---|---|
| 01-default | 3 lines, line 1 selected, team list |
| 02-task-2 | line 2 selected (others dimmed), +50 % picked |
| 03-team-tools | the เครื่องมือ tab |
| 04-count-dropdown | ผู้ปฏิบัติงาน's dropdown open |
| 05-signed | reporter signed |
| 06-map-full | key plan full screen |
| 07-day-before | previous day |
| 08-material-problem | a material and a problem row under the task panel |

Values are the board's example (สถานีผลิตน้ำโชคชัย, 2 ก.ค. 2568); never hardcode them.

## Tests

- station % today and behind-plan from weights and location counts
- labour hours with rain inside / outside the working time
- quick picks capped at 100 − accumulated
- a ghost pin adds a line for the right task and location

## Check list

- [ ] Build with your own `-derivedDataPath`; `swift test` passes.
- [ ] iPad Pro 13" landscape screenshots 01, 02, 04, 06 and 08 in `screenshots/` (with `-screen daily -routineKeyPlan YES`), compared with `states/`.
- [ ] The PDF of `-routineDemo pdf` is unchanged.
- [ ] The iPhone daily report is unchanged.

## Open questions (report)

1. The board drops the step wizard (`วันนี้ · ทีมงาน · งานวันนี้ · รูปและส่ง`). Keep it for iPad portrait, or one page everywhere on iPad?
2. `ตรวจพบอัตโนมัติ n พื้นที่` in the full-screen plan: is there an area detector, or should the areas come only from the report settings' locations?
3. Where should weather editing live in the one-page layout?
4. Tools per task (`ใช้ สว่านไร้สาย`): a fixed table by MP task, or learnt from earlier reports?
