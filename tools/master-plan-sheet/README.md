# TCRoof › Master Plan sheet

The Apps Script for `Master_Plan_ประปา_เฟส3-4_ลิงก์แผนรายโครงการ` (a copy is in `Project_Plan_TCRoof/1_Master Plan`). The
sheet's `TCRoof` tab, its start page (`ดึงจากแอปล่าสุด`) and the Master Plan's `% MP ในแอป TCRoof` / `แก้ล่าสุดในแอป`
columns were laid out for it; this fills them.

| Menu `TCRoof ›` | What it does | Automatic |
|---|---|---|
| `ดึงข้อมูลตอนนี้` | Reads the app's jobs and daily reports from Firestore and writes the `TCRoof` tab's blue columns | every 5 minutes |
| `บันทึกประวัติตอนนี้` | Adds this week's station rows to `ประวัติรายสัปดาห์` and a phase line to `ประวัติสรุป` (the same day again replaces them) | Mondays 08:00 |

The sheet only reads from the app: nothing it holds goes back to Firestore. Columns are found through `_keys`.

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
