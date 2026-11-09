# TCRoof › Master Plan sheet

The Apps Script for `Master_Plan_ประปา_เฟส3-4_ลิงก์แผนรายโครงการ` (a copy is in `Project_Plan_TCRoof/1_Master Plan`). The
sheet's `TCRoof` tab, its start page (`ดึงจากแอปล่าสุด`) and the Master Plan's `% MP ในแอป TCRoof` / `แก้ล่าสุดในแอป`
columns were laid out for it; this fills them.

| Menu `TCRoof ›` | What it does | Automatic |
|---|---|---|
| `ดึงข้อมูลตอนนี้` | Reads the app's jobs and daily reports from Firestore and writes the `TCRoof` tab's blue columns, and lists the app jobs no row took to the right of them (their ids go in a row's yellow cell); first sends the `WBS` tab's typed `Y` to the app, then rewrites that tab | every 5 minutes |
| `บันทึกประวัติตอนนี้` | Adds this week's station rows to `ประวัติรายสัปดาห์` and a phase line to `ประวัติสรุป` (the same day again replaces them) | Mondays 08:00 |

| `เพิ่มสถานีที่ยังไม่มีในแอป…` | Creates a PWA job in Firestore for each station row no app job is (`ไม่พบงานในแอป`), after asking: the station's code as the job's code, its name, `กปภ.สาขา…` from the Master Plan, its kWp, no dates yet, `ลูกค้ายืนยันติดตั้ง`. Only new documents, never an existing one; then it pulls, and the rows pair by code | by hand |
| `ลบสถานีที่เพิ่มจากชีต…` | Deletes, after asking, only the jobs the item above created (their ids are kept in the script's properties) | by hand |

Apart from those two items and the `WBS` tab's `Y` (below) the sheet only reads from the app. Columns are found through `_keys`. Writing needs the
account's **Cloud Datastore User** role instead of Viewer (the project's owner has it). A station added this way has
no MP plan yet: in the app, its `ตั้งค่าแผน › เริ่มจากแม่แบบ` opens on its own plan file (found by its code) and keeps
its dates and progress.

Every pull also rewrites a hidden `_app` tab: every job Firestore holds, one row each (id, name, kind, status, job
code, station code, kWp, MP plan and %, IEC, daily reports, signed, latest report, last change, and the station row it
pairs with), so what the app has can be read from the sheet alone, through Drive, without access to Firebase.

## What the `TCRoof` tab gets

Each station row is paired with a job in the app (`จับคู่โดย`): the job id typed in the yellow `กำหนดงานในแอปเอง`, else
the job carrying the station's code (`P3-001`, set when a plan file was imported), else the one job of that name, two of
the same name told apart by kWp. A job two rows would take goes to neither: type its id in the yellow cell (the id is in
`งานในแอป (id)` of the row it belongs to, or ask the team).

| Column | From the app |
|---|---|
| `แก้ล่าสุดในแอป` | the job's last change or its latest daily report, whichever is later |
| `% MP ในแอป`, `1.1` … `3.2` | the MP plan's progress: each task's points done (at most its weight; weights total 100) |
| `ติดตั้งครบ (2.x)` | the day the last 2.x task finished, once every 2.x task with a weight is done |
| `IEC เสร็จ (3.1)`, `ขนานไฟ (1.7)` | the day the task finished, once done |
| `IEC ในแอป` | the IEC 62446 test: `กำลังทดสอบ`, `ส่งผลแล้ว รอปิด`, `ปิดการทดสอบแล้ว` |
| `รายงานประจำวัน`, `รายงานล่าสุด`, `ลงนามแล้ว` | the station's daily reports: how many, the latest day, how many the engineer signed |

## The `WBS` tab: ticking sub-tasks from the sheet

Every pull rewrites a `WBS` tab (made the first time): one row per sub-task of each paired PWA station's MP plan that
the app ticks (no task line, no row with steps under it, no row of the other case), with `เสร็จ (Y)`, `วันที่เสร็จ`,
`ที่มา` (`ทีมติ๊ก`, `รายงานประจำวัน`, `Google Sheet`, `ไฟล์แผน`, or `ผู้รับเหมาติ๊ก` for a contractor's tick from before
CHA-71) and `โดย`, as the app has them. A hidden `_wbs` tab keeps what it showed.

To tick a sub-task, type `Y` in `เสร็จ (Y)` (and the day in `วันที่เสร็จ`, else today; `yyyy-mm-dd`, `d/m/yyyy` or a
Buddhist year). The next pull (within 5 minutes, or `ดึงข้อมูลตอนนี้`) compares the tab with `_wbs` and writes what was
typed into the job's `wbsTicks` as a tick with `source: "sheet"`, its day at Bangkok's midnight, in the name of who typed
it, and `wbsTicksBy` the same email (`syncWBSEdits`, `Core.wbsSheetChanges`). One commit per job, of those two fields
only. A team device books it into the MP plan as soon as it syncs, like a tick made in the app; there is nothing to
confirm.

Guard rails:
- Only a team member's edit is written: the editor's `members/<email>` must exist, not be `external` nor suspended.
- Taking a `Y` off clears only a tick the sheet made (`Google Sheet`). A tick of the team, a daily report or a plan file
  stays, as does its date: those change in the app. The row is written back as the app has it and `แก้โดย` says why
  (`ไม่รับ: …`); B4 counts the refusals.
- A `Y` on a row the app already ticks changes nothing.

Who typed it: `เปิดงานอัตโนมัติ` also installs an edit trigger (`onWBSEdit`) that notes the editor's email in `แก้โดย`.
Google gives it only when the editor's account allows (same Workspace domain, or the trigger's own account); otherwise,
and for an edit made before the trigger was installed, the tick is written in the name of the account that turned the
timers on. Writing needs that account's **Cloud Datastore User** role (not only Viewer), and the script now asks for
its email (`userinfo.email`): run `เปิดงานอัตโนมัติ` again after updating the script so Google asks for it.

A team device that saved the job before it received the sheet's write can still write its own older copy over it; the
next pull then shows the row without `Y` again, and it can be typed again.

## Set-up (once, by someone with access to the Firebase project)

1. The file must be a Google Sheet (File › Save as Google Sheets if it is still an .xlsx on Drive).
2. Extensions › Apps Script. Add two script files, `Core` and `Code`, and paste `Core.js` and `Code.js` into them.
   Project Settings › tick "Show appsscript.json", then replace `appsscript.json` with this folder's.
3. The account that turns it on reads Firestore with its own Google access, so it needs, on Google Cloud project
   `tcroof-1564c` (IAM & Admin › IAM): **Cloud Datastore Viewer** (read only) and **Service Usage Consumer**. The project's
   owner has both already. A different project id: `TCRoof › ตั้งค่าโปรเจกต์ Firebase…`.
4. Reload the sheet, then `TCRoof › เปิดงานอัตโนมัติ`. Google asks that account to allow the script (the sheet, external
   requests, timers, Firestore). It pulls once straight away; `TCRoof!B4` says how many stations it paired, or the error.

The timers run as that account. To stop them: `TCRoof › ปิดงานอัตโนมัติ`. Results also show in `ตั้งค่าแจ้งเตือน` under
`ผลการทำงานล่าสุด`.

Not built yet: `นำเข้าไฟล์ติดตาม` (the tracking file in `ตั้งค่าแจ้งเตือน` B9) and the alerts (email / Google Chat, the
daily 08:00 summary).

## Tests

`node --test tools/master-plan-sheet/core.test.js` checks `Core.js` (the calculations, no Google APIs) against
`fixtures/plans.json`: P3-001's plan and an in-app plan as the app encodes them (Swift's `JSONEncoder`), with the points,
% and finish days the app works out. `Code.js` (menus, Firestore, writing the sheet) runs only in Apps Script.

The sheet's own time zone must be Bangkok (File › Settings › Time zone: (GMT+07:00) Bangkok): the app's days are
Bangkok's, and a sheet in another zone shows them a day early. `B4` warns when it isn't.
