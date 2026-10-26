# Project plan WBS in the app

The team's plan files (`Project_Plan_TCRoof/`, 20 cases P9-001…020) carry two plans: the hidden `Weekly PLAN` sheet
with the 18 MP tasks, which the app reads today (`MPWorkbook`, `MPTemplates`), and the visible `แผนโครงการ` sheet with
the work breakdown under them. This spec brings the work breakdown into the app in four steps.

## The sheet

Header row 7 (the row of the `WBS` cell) under a row of groups:

| Column | Heading | Group | Read as |
|---|---|---|---|
| A | WBS | | `code`: `0`, `1.1`, `1.1.3`, `1.7.1` |
| B | กิจกรรม | | `title` (indent trimmed) |
| C | หลักฐาน / เลขที่เอกสาร | | `evidence` |
| D | ผู้รับผิดชอบ | | `responsible` |
| E | น้ำหนัก % | | `weight`, percent of the station |
| F | งานก่อนหน้า | | `predecessor`, the sheet's words |
| G, H | รอ (วัน), ระยะ (วัน) | | `lagDays`, `days` |
| I, J | เริ่ม, เสร็จ | Baseline (ล็อก) | `baselineStart`, `baselineEnd` |
| K, L | เริ่ม, เสร็จ / นัด | จริง / นัด (ลิงก์) | not read (links to the template's update sheet) |
| M | เสร็จ (Y · S) | | not read: a reference to `อัปเดตงาน WBS`, which the import files don't carry |
| N, O | เริ่ม, เสร็จ | คาดการณ์ | `forecastStart`, `forecastEnd` |
| P | สถานะ | | `status` |
| R | มาตรฐาน / หมายเหตุ | | `note`; `หลักฐาน: site_map` names a station paper |
| S | ชั้น | | `level`: 0 part, 1 task line, 2 sub-task |
| W | อนุมัติ / ตรวจรับ (A) | | `approver` |

Columns are found by these texts, not by letter. Every one of them holds values, no formulas.

The table ends at the first non-code text in column A. Below it, the Inverter station's own breakdown (2.5.1.1–2.5.1.6,
as % of 2.5.1, the same six steps in every case) joins the list after 2.5.1 (step 4); the installation points are left
out.

Numbering is the app's: the sheet's 1.1–3.2 are `MasterSchedule.Task.code`, so a row belongs to the task its first two
code parts name (`2.5.3` → 2.5 Inverter). Grid connection 1.7 has no line of its own, only 1.7.1–1.7.6. Part 0
(preparation, 0.x) and 2.10 Tie-in have no MP task and weigh 0. A task's sub-tasks add up to its weight; a part's line
carries its tasks' total (1: 5, 2: 90, 3: 5). The other case's rows (HV on an LV station, พค.2 under 200 kVA) stay in
the sheet marked `(ไม่เกี่ยวกับสถานีนี้)` / `(ไม่ต้อง…)` at weight 0.

## Step 1: read it (built)

- `MasterSchedule.WorkItem` (TCRoofCore, `MasterSchedule+WBS.swift`): one row, with `task`, `isMilestone` (◆),
  `notForThisStation`, `evidenceKinds`; `[WorkItem].items(for:)` gives a task's sub-tasks.
- `MPWorkbook.read` fills `Imported.wbs` from the `แผนโครงการ` sheet (`MPWorkbook+WBS.swift`); a file without one
  (a station's own `Master Plan Weekly`) gives `[]` and reads exactly as before. Only a file whose shared strings have
  `WBS` is looked through for the sheet. Export doesn't touch it.
- `ProjectPlanTemplateTests`: every case reads 124 rows, each task's sub-tasks add up to its weight, parts and the rows
  with no task weigh as above, 2.1's line keeps the plan's dates, and one row is checked field by field.

Nothing is stored on the job yet.

## Step 2: the checklist on the install page

Each MP task's sub-tasks under it in แผนก่อสร้าง and the task sheet (iPad and iPhone): evidence, owner, dates, the
station papers its note names; the other case's rows hidden. Ticking a sub-task done moves its task's % by its weight
and books it in the MP plan's progress, so reports and the S-curve follow.

Step 2a, storage and sync (built): `Job.scheduleWBS` (rows, set by the workbook import and `เริ่มจากแม่แบบ`, which
moves them with the plan) and `Job.wbsTicks` (`MasterSchedule.WBSTick` by code: who, the day, a document number), both
synced on the job record (`scheduleWBS` `[]`, `wbsTicks` `{}` when empty). A contractor's device pushes `wbsTicks`
signed `wbsTicksBy` (the rules check it); team devices take in only the contractor's own ticks
(`WBSTick.trusting`). `MasterSchedule.bookWBS` books each ticked sub-task's weight in its tick's week, once
(`Actual.fromWBS`), capped at its task's weight, and takes it back on untick; it runs whenever rows or ticks change,
received ones too, since the contractor can't send progress. `AppCompat.syncVersion` is 6.

Step 2b, the screens (built): a task's sheet (`InstallStageSheet`, iPad and iPhone) lists its sub-tasks under
`งานย่อย WBS n/m` (`WBSChecklist`): code, title, evidence, owner, weight, and who ticked it and when; a long press adds
a document number. `mp.wbs_tick` (user-roles.json) lets the team and a contractor on their own job tick; a tick is taken
back by whoever made it, a manager or the job's supervising engineer (`Permissions.mayTakeBack`).

Why not inside `MasterSchedule.Input`: The plan syncs as one JSON string on the job document; 124 rows would add
about 35 KB to every job, and a device on an older build that saves ตั้งค่าแผน would drop a field it doesn't know. Set
`config/app.minSyncVersion` to 6 before anyone ticks: an older build saving the progress drops `fromWBS`, and the ticks
would then book again.

## Step 3: ticks back to Excel

Export writes each ticked sub-task into the `แผนโครงการ` sheet and `รับเฉพาะความก้าวหน้า` takes the ticks changed in
Excel, as it does for the weekly points. Which column takes the tick has to be settled with the template's author:
column M is a reference into `อัปเดตงาน WBS`, a sheet the import files leave out.

## Step 4: the rest

- แผนก่อสร้าง's sub rows (built): a stage's WBS sub-tasks replace the daily reports' places (`InstallPlan.useWBS`), their
  baseline dates moved by as much as the stage has moved from the file's own line, done when ticked; a stage without WBS
  rows keeps its places.
- Sub rows (built): แผนก่อสร้าง shows each stage's WBS sub-tasks as its rows (`InstallPlan.useWBS`), moved with the
  stage, done when ticked.
- Baseline (built): each stage carries its baseline dates (`InstallPlan.baselineDates`: the plan before its first
  re-plan, `Input.baseline`, else the WBS task lines' locked Baseline columns), drawn as a grey line under its bar, with
  `เทียบ Baseline` in the header and the table (`Row.slip`, `InstallPlan.slip`: the end's days later or earlier). A
  sub-task's baseline is its row's own dates.
- Predecessors: not filled. The template plans backward from 2.10 (`ย้อนจาก 2.10 (n วัน)`) or from the Master Plan;
  only a few part 3 rows name a row they follow, so `ต่อจาก` stays hidden.
- Inverter station steps (built): `MPWorkbook.stationSteps` puts 2.5.1.1–2.5.1.6 after 2.5.1, each weighing its share of
  2.5.1 (`30% ของ 2.5.1` in its note), and adds the table's `รูปแบบ` line (type and size) to 2.5.1's note. A row with
  rows under it (`parentCodes`) is their sum: `bookWBS` skips it and the checklist shows it as a heading with its steps
  indented. A plan imported before this has no steps until it is imported again.
- Installation points: left out. They are the template's own figures per site type (points, panels, kWp, standard
  designs); a real station's come from its survey.
- Per site type plans: `make_template.py` with each type's durations; the files ship through `PlanTemplates` as they are.

## Decisions (2026-10-26)

1. Evidence is optional: a tick alone counts; a document number or photo can be attached, and a row whose note names a
   station paper links to it.
2. Both tick: the job's contractor and the team; managers and the supervising engineer can untick.
3. Ticks sync both ways with the contractor's devices: a Firestore rule for the contractor's push (as the weekly
   request's, signed with its email), `AppCompat.syncVersion` raised, `config/app.minSyncVersion` set once every device
   runs it.
4. Step 3's tick column is decided later, with the template's author.
