# Task: iPad · Install tracking: a third view, `Key Plan`, in the progress card (board 27 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/install-tracking-ipad-keyplan`, then paste `PROMPT.md`, or type
> `Follow docs/ui/install-tracking-ipad-keyplan/CLAUDE_CODE_TASK.md`

- **Board:** `iPadInstall.dc.html`, card `ความคืบหน้าเทียบแผน` (1366 × 1024, landscape). Open it in a browser with `grf.css` beside it; the switch `Gantt | S-Curve | Key Plan` is live.
- Thai strings in `backticks` are literal UI labels.
- **Everything in the previews is example data** (การประปาบ้านโป่ง, หลังคา 1–5, ถังน้ำใส 1–2, ห้องอินเวอร์เตอร์, the 16 points, the percentages, the site picture). It is listed in `assets/sample-data.json`. Never hard-code it.

## Previews

| File | State |
|---|---|
| `states/01-default.png` (= `preview.png`) | `Key Plan` selected, nothing selected, list `ทั้งหมด` |
| `states/02-point-selected.png` | pin `2.1-4` tapped: ring on the pin, its row expanded with `ย้ายจุดบนผัง` / `เอาออกจากผัง` |
| `states/03-placing.png` | `วางบนผัง` on an unplaced row: the plan dims, a banner `แตะบนผังเพื่อวาง …`, crosshair cursor |
| `states/04-placed-next.png` | after the tap: the pin is placed, toast `วาง … ที่ …`, the next unplaced row is armed |
| `states/05-gantt-switch.png` | the card header: legend, `วางแล้ว n/N` chip, the three-way switch |
| `states/06-card-crop.png` | the card alone, for measuring |

## Scope: only this

- **In scope:** the iPad install tracking page's progress card (`InstallTrackingPage+Progress.swift`, `progressCard` / `progressHeader`): a third view `Key Plan` beside `Gantt` and `S-Curve` (change list 1–7).
- **Do not touch:**
  - the Gantt and S-Curve content (`ganttGrid`, `curvePanel`)
  - the iPhone progress (`InstallTrackingPage+PhoneProgress.swift`)
  - the daily report's `KeyPlanCard` / `KeyPlanEditor`, the weekly request's key plan, and the PDF (`reportKeyPlan`)
  - stored model fields and their `Codable` (`RoutineReport.Settings`, `MasterSchedule`, `InstallLog`)
  - `firestore.rules`
- **Out of scope:** the zone rectangles drawn on the board around each roof / tank. There is no field for an area, only a point per location (`Settings.keyPoints`). Don't add one; mention it in the report.

**Before editing:** use code-review-graph (per `CLAUDE.md`), else grep. Read:
- `TCRoof/Views/Install/Tracking/InstallTrackingPage+Progress.swift`: `ProgressView`, `progressCard`, `progressHeader`, `fittedHeight`
- `TCRoof/Views/Install/Tracking/InstallTrackingPage.swift`: the DEBUG `Debug.view` (`-installView`), how the page holds `job`
- `TCRoof/Views/Job/RoutineReports/KeyPlanViews.swift`: `Job.keyPlanPicture`, `KeyPlanImage(image:points:highlight:selected:onTap:)`, `KeyPlanEditor` (its place-then-advance flow), `KeyPlanSheet` (how settings are saved: `job.routineSettings = settings`)
- `TCRoofKit/Sources/TCRoofCore/RoutineReport.swift`: `Settings.locations`, `taskLocations`, `keyPoints`, `keyPoint(_:)`, `previousPercent(_:before:in:)`
- `TCRoofKit/Sources/TCRoofCore/RoutineReport+Day.swift` (`plannedNotReported`) and `InstallGantt.swift` (how a task's locations and per-location progress are already worked out)
- `TCRoofKit/Sources/TCRoofCore/MasterSchedule.swift` (`plannedPoints`: planned % by date)
- `TCRoofUITests/InstallTrackingUITests.swift`

## How the board maps onto the data (no new stored fields)

- **A point** = one MP task × one of its locations: `settings.taskLocations[task.rawValue]` (a task with no locations is one point with no location and is always unplaced). Label `<task code>-<n>`, n = the location's index in that task's list, 1-based (`2.1-3`).
- **Its position** = `settings.keyPoint(location)`, a fraction of the picture (0…1). A point is *placed* when its location has a key point. Several points sharing a location fan out around it (e.g. 26 pt apart on a small circle) so none hides another.
- **Placing / moving** a point writes `settings.keyPoints[location]`, so every task at that location moves with it. Say so in the toast only if more than one point moved (`ย้าย 3 จุดของ หลังคา 3`). `เอาออกจากผัง` removes `keyPoints[location]`.
- **Its % and plan %:** actual = the location's latest reported % for that task (the same figure `InstallGantt` / `previousPercent` give); planned = the task's planned % by today from the MP plan. Reuse those; write no new calculation in a view (put a small pure helper in TCRoofCore if needed, with a test).
- **Colour** (Theme, never hex): done (100 %) success green · late (actual < planned today) danger red · on plan (started, not late) primary blue · not started (0 % and nothing planned yet) muted grey. The legend `เสร็จ · ตามแผน · ช้ากว่าแผน · ยังไม่เริ่ม` uses the same.
- **The picture** = `job.keyPlanPicture` (the station's uploaded plan, else the survey's A2 picture). With none: an empty state in the plan area, `ยังไม่มีผัง` and a line that points to `อัปโหลดผัง` in the daily report; the list still works.

## Change list

1. **Switch.** `ProgressView` gets `case keyplan`; the header's `TCCountSegments` becomes `Gantt | S-Curve | Key Plan`. The `today` status chip shown for Gantt stays Gantt only. `-installView keyplan` (DEBUG) opens it.
2. **Header extras (Key Plan only).** The colour legend and a chip `วางแล้ว n/N` (n placed of N points; warning tint while n < N), left of the switch, as `states/05`.
3. **Plan (left).** `KeyPlanImage` at the picture's aspect, on `Theme.paper`, with one pin per placed point: a pill with the label, filled by its colour, white text; a selected pin gets a 3 pt ring and a larger size. Location names stay as the picture shows them (don't draw extra labels). A caption under it: the picture's source (`ภาพ A2 จากรายงานสำรวจ` or `ผังที่อัปโหลด`) and `จุดติดตั้งดึงจากแผน MP`.
4. **List (right, 360 pt).** A two-segment filter `ทั้งหมด N | ยังไม่วาง m`; then the points grouped by MP task (`2.1 โครงสร้าง + ราง`, with `n จุด · เฉลี่ย x%` on the right); each row: a numbered circle in the point's colour (grey outline when unplaced), the task name + location, `อยู่บนผัง · <location>` or `ยังไม่วางบนผัง` (danger), the % and under it `เสร็จ` / `แผน y%` / `ตามแผน` / `ยังไม่เริ่ม`, and a bar with a tick at the planned %. Rows ≥ 44 pt. The list scrolls inside the card; the card keeps the height `fittedHeight` gives the other views.
5. **Selection.** Tapping a pin selects its row (scrolls it into view, expands it); tapping a row selects its pin. Tapping again or on empty plan clears it. An expanded placed row shows `ย้ายจุดบนผัง` (primary) and `เอาออกจากผัง` (danger outline); an unplaced row shows `วางบนผัง`.
6. **Place mode.** `วางบนผัง` / `ย้ายจุดบนผัง` arm the row: the plan dims slightly, a banner on the plan `แตะบนผังเพื่อวาง <label> · <location>` with `ยกเลิก`. A tap on the plan writes `keyPoints[location]` (KeyPlanImage's `onTap` fractions), saves the job's settings the way `KeyPlanSheet` does, shows a toast `วาง <label> ที่ <location>` (2.5 s, the app's existing toast if there is one) and, as `KeyPlanEditor` does, arms the next unplaced row; when none is left, place mode ends. `เอาออกจากผัง` clears and saves at once (no dialog). Only people who may edit station settings get these buttons (the same capability the station settings / `KeyPlanSheet` entry checks); others see the plan and list read only.
7. **DEBUG + test.** `-installView keyplan` with `-installDemo YES` shows the board's example in memory (nothing saved); `-installKeyPlanState selected|placing|placed` opens states 02–04. Add a test to `InstallTrackingUITests`: switch to `Key Plan`, tap a pin → its row shows `ย้ายจุดบนผัง`; filter `ยังไม่วาง` → tap `วางบนผัง` → tap the plan → the `วางแล้ว` count goes up by one.

## Checks when done

- `swift test` in `TCRoofKit` (with a test for any new TCRoofCore helper: point list, colour state, fan-out).
- The app builds with `xcodebuild … -derivedDataPath <your scratch>` (in the background).
- `InstallTrackingUITests` (new test plus the existing ones) on an iPad simulator.
- Screenshots of states 01–04 with the DEBUG flags, saved to `screenshots/` under the same names, compared with `states/`.
- Gantt and S-Curve look unchanged; the iPhone page unchanged.

## Open questions (answer in your report)

1. Zones: should a location get an area (rectangle) as well as a point? Not built here.
2. Moving one location moves every task at it. Is that right, or should a point be per task × location? (That would need a new field.)
3. Who may place points: everyone who edits station settings, or the contractor too?
4. Late is measured against the plan for today. Should a grace margin (e.g. 5 %) apply before a point turns red?
