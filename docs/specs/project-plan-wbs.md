# Project plan WBS in the app

The team's plan files (`Project_Plan_TCRoof/`: the 102 stations' own, and the 20 install cases P9-001…020 in `3_แม่แบบ 20 กรณี`) carry two plans: the hidden `Weekly PLAN` sheet
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
as % of 2.5.1, the same six steps in every case) joins the list after 2.5.1 (step 4); the installation points are not
WBS rows: they are read as project facts (`ProjectSetup.points`, see below).

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
a document number. `mp.wbs_tick` (user-roles.json) lets the team tick; a tick is taken back by whoever made it, a
manager or the job's supervising engineer (`Permissions.mayTakeBack`).

Step 2c, three sources (CHA-71, built): every tick records where it came from (`WBSTick.source`, nil in older ticks:
the team's, or `ผู้รับเหมาติ๊ก` when `by` is one of the job's externals, `WBSTick.origin`):
- `team` (`ทีมติ๊ก`): a team member taps the box; it counts at once.
- `daily` (`รายงานประจำวัน`): a contractor no longer ticks. In a daily report line whose task has WBS rows, the reporter
  picks the sub-tasks finished that day (`งานย่อยที่เสร็จวันนี้`, `DailyWBSPicks`, `ProgressLine.wbsDone`), the line's
  photos being the evidence. A signed report's picks wait (`RoutineReport.wbsPending`, `รอยืนยัน · รายงานประจำวัน`)
  until the team taps `ยืนยัน` (or the row's dashed box) in the task's sheet, or acknowledges the report
  (`ลงนามรับทราบ`, `Job.recordInspectorAck`), which confirms all of its picks (`confirmingAll`); the tick is dated the
  report's day, by who confirmed it, with `reportedBy` and `confirmedAt`. `ส่งกลับ` returns a pick with a reason
  (`ProgressLine.wbsReturned`), shown on the reporter's chip; picking it again sends it once more.
- `sheet` (`Google Sheet`): a `Y` (and date) on the Master Plan sheet's `WBS` tab, written into `wbsTicks` by its Apps
  Script (signed `wbsTicksBy` with the editor's email; tools/master-plan-sheet). It counts once a team device syncs.
- `file`: the plan file's `เสร็จ (Y)` column, taken in by an import.
All book the same way (`bookWBS`). A contractor's device shows the boxes read only, and firestore.rules no longer let
an external member write `wbsTicks` / `wbsTicksBy`; team devices drop a write signed by a contractor
(`WBSTick.trusting`). The iPad task sheet lays the WBS out in two cards: `งานย่อย WBS` with a source chip per row and
`รอยืนยัน` with each pick's photo, reporter, `ส่งกลับ` / `ยืนยัน` and `เปิดรายงานประจำวัน`. `AppCompat.syncVersion` 8.

Why not inside `MasterSchedule.Input`: The plan syncs as one JSON string on the job document; 124 rows would add
about 35 KB to every job, and a device on an older build that saves ตั้งค่าแผน would drop a field it doesn't know. Set
`config/app.minSyncVersion` to 6 before anyone ticks: an older build saving the progress drops `fromWBS`, and the ticks
would then book again.

## Step 3: ticks back to Excel (built)

The full workbook already says where a tick goes: in a station's sheet, `เสร็จ / นัด` (L, under `จริง / นัด`) takes the
finish date and `เสร็จ (Y · S)` (M) takes `Y`, both by formula from `อัปเดตงาน WBS`. The import files keep them as empty
cells, so the app fills them.

- Export (`MPWorkbook.export(…, ticks:)`, the plan screen's and the install page's Excel menu) writes `Y` (an inline
  string) and the tick's day into each ticked row and clears both on a row the app unticked; a row that wasn't ticked
  keeps whatever L has (an appointment date). Formula cells are left alone. The rows it wrote are kept in the file as a
  custom XML part of their own (`urn:tcroof:wbs-ticks`, next to the progress record).
- Import (a whole plan or `รับเฉพาะความก้าวหน้า`) reads the `Y` rows and their dates (`Imported.wbsDone`) and takes only
  the rows ticked or unticked in Excel since that record (else since the file the job keeps), in the importer's name
  (`MasterSchedule.mergingTicks`, `MPWorkbookFlow.takeTicks`); a tick made in the app after the export stays.
- The Inverter station table's steps have no cells in that column: their ticks go in the table's own `เสร็จ (Y)` column
  (its header row starts `ขั้นงาน`, `MPWorkbook.stationMark` / `tickCells`), which has no date, and join the record like
  the others. A station file carries them (P3-001: its 15 list rows and the 6 steps).
- A plan moved from another station's file (`MPTemplates.plan` with a kickoff) takes none of that station's ticks
  (`wbsDone`, `wbsBase` empty); its first export clears their `Y`.
- A `Y` the file has without a `เสร็จ` date comes in dated the import's day for the booking, marked `undated`
  (`WBSTick.undated`), and export leaves its date cell as the file has it: a station's own file comes back byte for byte.
  Only the list's rows above the tables take ticks; a table further down whose rows also start with a code (P4-001's
  drawings per task) has none.
- `รับเฉพาะความก้าวหน้า` also takes the rows' `ผู้รับผิดชอบ` and `หลักฐาน / เลขที่เอกสาร` changed in Excel since the kept
  file, an emptied cell included (`MasterSchedule.mergingText`); the rest of the plan stays the job's. A whole import
  takes the file's rows as they are.

### People in `ผู้รับผิดชอบ`

The 20 cases name a role in each row (`วศ.`, `Admin`, `ผรม.`, with `วศ.01` / `ผรม. 01` as examples); the 102 station files
name that station's people in the same rows (`เปรม`, `บีม`, `ผรม. B`), always the set-up line's. `wbs-roles.json`
(`tools/plan-template/wbs_roles.py` from the cases) gives each row's role (`MPTemplates.roles`; the utility's rows,
`กฟภ.` and `พพ.`, have none), and `WBSPeopleExcelTests` holds every station file to it.

- The set-up line is the file's word on its people: a person taken out of it isn't read back from `รหัส` (which still
  gives the code).
- Export (with the job's facts) writes the job's people: a row naming a person takes the job's for its role, or the role
  when the job has no one for it; a row naming the role stays (the team may prefer roles). The set-up and `รหัส` lines
  take out whom the job has no one for (`ProjectSetup.rewrite(line:dropPeople:)`).
- A plan moved from another station's file names the job's people, else the roles, in the app's rows too
  (`MPTemplates.plan(…, people:)`, `withPeople`); an Inverter station step takes its row's.

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
- Installation points: not WBS rows. The station files that fill the table (`ประเภทหน้างาน` | `จุด` | `แผง` | `kWp`)
  give them as `ProjectSetup.points`, which an import can take as the daily reports' locations (`<type> 1…n`); a real
  station's figures still come from its survey.
- Project facts (built): the sheet's title and set-up lines, the points and the Inverter station's type are the file's
  `ProjectSetup` (TCRoofCore/ProjectSetup.swift, `MPWorkbook+Setup`): an import fills the job's empty facts from them,
  `ตั้งค่าโครงการจากไฟล์…` offers the rest, and export writes the job's facts back into those lines.
- Per site type (built): the site types share every date; what differs is 2.1's sub-tasks, named and split in the full
  workbook's `จุดติดตั้ง` sheet (columns Z–AD). `tools/plan-template/site_steps.py` writes them to ExcelExport's
  `site-steps.json`, and `MPWorkbook.read` gives a template file's 2.1.1–2.1.7 its site type's titles and shares of 2.1
  (`MPTemplates.applySite`, the type from the sheet's title), so `เริ่มจากแม่แบบ` and an import of a template file both
  get them. Run the script again when the workbook's table changes.
- Install cases (built): the 20 cases (`3_แม่แบบ 20 กรณี`, `MPTemplates.installCases`) are a station's plan when it has no
  file of its own: `เริ่มจากแม่แบบ`'s `แม่แบบตามกรณี` picks one by the station's main site type (most kWp, else its
  daily-report locations), zero export and size (`MPTemplates.suggest`), always moved to the kickoff. Beyond 2.1, the
  cases differ only in the permits: ≥ 200 kVA weighs 1.5 พค.2 at 1 (1.4 and 1.7 give 0.5 each) and opens its sub-tasks;
  LV marks 0.2.7 and 2.8.1 / 2.8.2 / 2.8.6 (22 kV) not for the station. Their figures are an example's
  (`ProjectSetup.isTemplate`): none is taken, and the station's export writes its own over them.

## Decisions (2026-10-26)

1. Evidence is optional: a tick alone counts; a document number or photo can be attached, and a row whose note names a
   station paper links to it.
2. Both tick: the job's contractor and the team; managers and the supervising engineer can untick. Changed by CHA-71:
   only the team ticks; a contractor reports finished sub-tasks in the daily report for the team to confirm.
3. Ticks sync both ways with the contractor's devices: a Firestore rule for the contractor's push (as the weekly
   request's, signed with its email), `AppCompat.syncVersion` raised, `config/app.minSyncVersion` set once every device
   runs it.
4. Step 3's tick column: L and M, as the full workbook's own formulas fill them (2026-10-26).

## Explicit dependency forecasts

`WorkItem.dependencies` optionally stores links (`predecessor`: WBS code, `lagDays`: working days, `type`: `FS`, `SS`
or `FF`, PMBOK 5th §6.3.2.1–3; CHA-76). A link without `type` is finish-to-start, and a finish-to-start link is written
without one, so older JSON and older plan files read and write as before. Missing links in older JSON leave the
existing schedule unchanged.

A link joins two sub-tasks or two task lines (`2.3` after `2.1`), as the Master Plan REV 11 links the install tasks
2.1–2.10 and 3.1. A linked task line's sub-tasks follow it, keeping their share of its span (the workbook's
`N + ROUND((O − N) × share)`), and can't be linked themselves while it is (`linkedInsideTask`). Parts (`2`) can't be
endpoints.

The worksheet's predecessor prose (`ย้อนจาก 2.10`, `Master Plan`, `3.2.7, 3.2.6`) is never parsed. Only the typed
notation a REV 11 file writes from its `DEP_*` lags is read (`WBSDependencies.parse`): `2.1 SS+3, 2.1 FF+2`,
`FS 2.1–2.9+0`, `FS 2.2, 2.3+0`. A full import takes them (`WBSDependencies.fromWorkbook`) when the file has no links
saved by the app. It drops a link to or from a row the station leaves out (`(ไม่ต้อง…)`), a missing row or one without
dates, so one station's case doesn't stop the plan from forecasting.

`WBSDependencies.schedule` validates duplicate codes/links, missing references, summary or irrelevant endpoints,
missing/invalid dates, negative or excessive lag, and cycles. Endpoints must be active leaf rows with baseline dates.
FS: zero lag starts on the next working day after the predecessor finishes. SS: the row starts `lag` working days after
the predecessor starts (zero: the same day). FF: the row finishes no earlier than `lag` working days after the
predecessor finishes, stretched when it would finish sooner, as the workbook's `MAX(N + H − 1, O_pred + lag)` does.
The workbook counts lags in calendar days; the app counts working days, as for its other links. Lag and duration use the station's working
weekdays, its holidays and public holidays, including dates beyond the original plan end. A linked row uses its `days`
when present (zero is a same-day milestone), else its baseline working-day span. Lag is limited to 3,650 working days;
durations to 3,650 days and baseline spans to 100 years. A calendar must have at least one working weekday.

The forward pass respects existing start dates as release constraints: it can delay linked rows but does not pull them
earlier. The backward pass computes float and critical rows from explicit links, not inferred date adjacency.
The construction plan shifts source dates with each stage before scheduling, displays forecast rows, extends summary
bars and the chart axis, and retains original baseline dates. Invalid graphs show an error and keep legacy dates.
This forecast does not overwrite MP progress, actual completion dates, weekly bookings or locked workbook baselines.

Critical path and float (CHA-77, PMBOK 5th §6.6.2.2): once the WBS has links, they decide every stage's float and red
outline on `แผนก่อสร้าง`, a stage without WBS rows of its own too: a task's float is the least of its task line's and
its sub-tasks' (`InstallCriticalPath.float(wbs:starts:…)`). The assistant's `get_schedule` gives the same `floatDays`
(with `floatFromLinks: true`), so `what_if` and `suggest_replan` can say which tasks can move without moving the
handover; a task the WBS has no rows for keeps the float read from the dates. A plan without links, or with links that
don't hold together, keeps the date-based float (`InstallCriticalPath.float(_:)`: a task follows every task that ends
before it starts).

Handover range (CHA-80, PMBOK 5th §6.5.2.4): `คาดส่งมอบ` stays one date, and beside it the tracking page shows
`น่าจะ … | กรณีช้า …` (P50 and P90, `HandoverRange`) while the tasks we don't control are open: 1.2 PPIM review, 1.4 อ.1,
1.5 พค.2 and 1.7 กฟภ. Each gets an optimistic, most likely and pessimistic duration as multiples of its planned one
(`HandoverRange.defaults`: 0.8 / 1 / 2, 1.75, 2.5, 2.5), drawn from a triangular distribution in 1,000 seeded runs; a
task pushes the point forecast by the days it overruns past its spare days to the install end, and an open task ends
today at the soonest. The chip shows only when the late case is after `คาดส่งมอบ`, amber when it passes the due date.
`get_schedule` gives `handoverLikely`, `handoverLate` and `handoverRangeTasks`. With O = M = P the range is the point
forecast. The defaults live in code; editing them per station is a later step.

The construction plan's `งานก่อนหน้า WBS` sheet is available on iPhone and iPad to people with `mp.setup` permission.
It edits a draft, blocks invalid graphs, and rejects saving when a remote edit changed the rows while it was open.
Rows persist through the existing `scheduleWBS` JSON and job sync. Finish-to-start links need `AppCompat.syncVersion`
7, and SS / FF links and task-line links need 9: once that build is out, set `config/public.minSyncVersion` to 9 before
relying on them across devices. Older builds read SS / FF as FS, refuse task-line links, and drop the type if they
rewrite WBS rows. This change does not alter the deployed Firebase switch.

Plan exports keep explicit links in `urn:tcroof:wbs-dependencies` custom XML, and full plan imports restore them.
The worksheet's human-readable predecessor text and baseline cells remain unchanged. Exporting an unchanged graph
keeps file bytes unchanged; exporting an empty graph clears previously exported links. Progress-only imports retain
the app's current links, since that flow merges completion and people rather than replacing the plan structure.
Dependency forecasts are currently calculated in the app; export carries the links without replacing the workbook's
forecast columns or its scheduling formulas. Lag can't be negative (no leads). Clearing a REV 11 file's typed links in the
app writes an empty links part, so the next import doesn't read them back from the sheet.

## Baseline revisions (CHA-79)

PMBOK 5th §6.6.3.1 (schedule baseline) and §4.5 (integrated change control). Each confirmed re-plan keeps the plan it
approved as the next revision (`MasterSchedule.Revision`, kept in `Input.revisions`): its number, the day it was
approved, who confirmed it (email), the reason and the change request it came from (`site.change_request`, typed as
its number or title, since change requests aren't records in the app yet). The assistant's `propose_replan` (with an
optional `change_request`) and the iPhone plan's `แก้ไขแผน` (reason required, CR optional) both save through
`applyAssistant`, which calls `PendingAction.revised`. The first revision recorded also keeps REV 00, the plan before
the first re-plan (`Input.baseline`, so `originalInstallEnd` reads as before). A station re-planned before revisions
were recorded counts on from its re-plan confirmations: two of them make the next one REV 03, and REV 00 is its baseline.

Progress is measured against the current revision, which is the plan itself. The plan header's REV chip (iPad and
iPhone) opens `ประวัติแผน`: each revision newest first, with its approval day, approver (named from the team
directory), reason, change request, install end, and how many days that end moved from the revision before.
`get_schedule` gives `revision`, `revisionReason` and `revisionChangeRequest`.

Export writes the current revision into the `แผนโครงการ` sheet's baseline box, each cell found by its label: `ฉบับ` →
`REV 02 (CR-014)`, `อนุมัติโดย` → the approver's name, `วันที่` → the approval day, and the `REV …` cell above `ฉบับ` →
`REV 02, อนุมัติแล้ว`. A plan never re-planned in the app leaves the box as the file has it. Revisions need
`AppCompat.syncVersion` 10: older builds drop them when they save the plan.
