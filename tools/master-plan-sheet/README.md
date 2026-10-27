# TCRoof › Master Plan sheet

The Apps Script for `Master_Plan_ประปา_เฟส3-4_ลิงก์แผนรายโครงการ` (a copy is in `Project_Plan_TCRoof/1_Master Plan`). The
sheet's `TCRoof` tab, its start page (`ดึงจากแอปล่าสุด`) and the Master Plan's `% MP ในแอป TCRoof` / `แก้ล่าสุดในแอป`
columns were laid out for it; this fills them.

| Menu `TCRoof ›` | What it does | Automatic |
|---|---|---|
| `ดึงข้อมูลตอนนี้` | Reads the app's jobs and daily reports from Firestore and writes the `TCRoof` tab's blue columns, and lists the app jobs no row took to the right of them (their ids go in a row's yellow cell) | every 5 minutes |
| `บันทึกประวัติตอนนี้` | Adds this week's station rows to `ประวัติรายสัปดาห์` and a phase line to `ประวัติสรุป` (the same day again replaces them) | Mondays 08:00 |

| `เพิ่มสถานีที่ยังไม่มีในแอป…` | Creates a PWA job in Firestore for each station row no app job is (`ไม่พบงานในแอป`), after asking: the station's code as the job's code, its name, `กปภ.สาขา…` from the Master Plan, its kWp, no dates yet, `ลูกค้ายืนยันติดตั้ง`. Only new documents, never an existing one; then it pulls, and the rows pair by code | by hand |
| `ลบสถานีที่เพิ่มจากชีต…` | Deletes, after asking, only the jobs the item above created (their ids are kept in the script's properties) | by hand |

Apart from those two items the sheet only reads from the app. Columns are found through `_keys`. Writing needs the
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
