# รายงานประจำ (Routine Reports): คำขอปฏิบัติงานรายสัปดาห์, รายงานประจำวัน, สัปดาห์, เดือน (iPad Swift design spec)

**Status:** Built 2026-10-09 (PR #4): rules in `TCRoofCore/RoutineReport.swift` with tests, the รายงานประจำ card
(§4.1), R2 daily report with signing, Excel and key plan (§4.2), R1 weekly request (§4.3), R3 and R4 (§4.4–4.5), A4 PDFs
filed to the Drive report folders and daily photos to `5. ภาพถ่ายประจำวัน` (§4.6), and the 17:00 / Friday 15:00
reminders (§5). R1 is stored as JSON on the job (`Job.weeklyRequestsJSON`), so it syncs with `jobs` and needed no new
Firestore collection (§2.4). R3 stays PDF only (open question 2, decided 2026-10-17).
**Platform:** TCRoof host app (SwiftUI, SwiftData, iPadOS 17+, also iPhone). Pure logic in `TCRoofCore`
(`RoutineReport.swift`, testable with `swift test`); PDF through `PDFReport`; Excel through `ExcelExport`.
**Depends on:** `docs/specs/master-schedule-swift.md` (แผน MP). The daily report feeds the MP actual.
**Source material:** `งานการประปาส่วนภูมิภาค/Report/สถานีผลิตน้ำโชคชัย กปภ.สาขาโชคชัย/` — 21 daily reports
(ก.ค. 2568, xlsx + pdf), 1 weekly request (xls + pdf), 1 weekly report (pptx + pdf, 16 slides), 2 monthly reports
(docx + pdf), daily photos (LINE albums).

| # | Report | Who / when | Goes to |
|---|---|---|---|
| R1 | คำขอปฏิบัติงานรายสัปดาห์ (Weekly Request) | Site Engineer, before the week | Inspector กฟภ. **approves** |
| R2 | รายงานประจำวัน (Daily Report) | Site Engineer, every working day | Inspector **acknowledges** |
| R3 | รายงานประจำสัปดาห์ (Weekly Report) | Engineer, after the week | Inspector / meeting |
| R4 | รายงานผลความก้าวหน้าประจำเดือน (Monthly Report) | Engineer, month end; last one = ติดตั้งแล้วเสร็จ 100% | กฟภ. (payment milestone) |
| R0 | ภาพถ่ายประจำวัน | ผรม. / site team, daily | feeds R2–R4 |

**One idea:** the site enters **R2 once a day** on the iPad. R3 and R4 are assembled from R2s + the MP plan, and
R1 is pre-filled from the MP plan. Nobody retypes the same numbers into four files.

---

## 1. What the sample files show (and what to fix)

| Finding | Evidence | Design answer |
|---|---|---|
| Crew and tools are identical on all 21 days (ผู้ควบคุมงาน 1, หัวหน้างาน 1, ผู้ปฏิบัติงาน 7; 4 tools) | every daily xlsx | prefill from yesterday, but the engineer must tap **ยืนยันกำลังคนวันนี้**; unconfirmed days are counted in R3/R4 |
| The "Today" column holds the **cumulative** fraction (ห้องอินเวอร์เตอร์ 0.1 → 0.15 → 0.2 → 0.4 → 1) and "Accumulated" is always 1 | progress table | store one value: **% สะสม** per work line; "วันนี้" = difference from yesterday, computed |
| Work lines are free text, not linked to the MP tasks | progress table | each line picks an MP task (2.1…3.2) or "งานอื่น"; free text stays as the description |
| Locations typed freely and combined ("หลังคา 4,5", "หลังคา 1-5 , ถังน้ำใส 1-2") | progress table | location picker from the station's list (หลังคา 1…n, ถังน้ำใส 1…n, ห้องอินเวอร์เตอร์, …); multi-select makes one line per place |
| Material on site and Problems are empty on all 21 days | | keep both sections, collapsed when empty; R3/R4 show "ไม่มี" instead of an empty table |
| 6 working days in ก.ค. have no report (12, 17, 24, 28, 29, 31) | folder | R3/R4 list missing working days; the job card shows "ยังไม่ส่งรายงานวันนี้" after 17:00 |
| Every daily xlsx carries hidden sheets "Week3/Week4" from a 2560 PEA substation job (other company, real names, #REF!) | xlsx | the app writes its own clean template; never copies the old workbook |
| Weekly report slide 4 still says "18-24 ธันวาคม 2566" | pptx | every date on generated pages comes from the data |
| File naming varied ("โชคชัย  14 ก.ค." with two spaces, day folders) | folder | generated names: `2568-07-01 รายงานประจำวัน <สถานี>.pdf` (the convention used when the folder was reorganised) |

---

## 2. Data

### 2.1 Daily report (R2) — extends `InstallLog`

`InstallLog` (date, recorder, details, photos) already exists and syncs. R2 **is** an install log with structured
parts; old logs keep working as text-only logs.

New optional fields on `InstallLog` (SwiftData, all with defaults):

| Field | Type | Notes |
|---|---|---|
| `reportJSON` | `String?` | encoded `RoutineReport.Daily` (below); nil = old free-text log |
| `engineerSignedAt` | `Date?` | Site Engineer signature time |
| `inspectorAckAt` | `Date?` | Inspector acknowledgement (typed in after the paper/LINE reply) |

`RoutineReport.Daily` (Codable, in `TCRoofCore`):

| Part | Fields |
|---|---|
| Header | date, working time (default 08.00–18.00), station from the job |
| 1 Weather | 15 slots 06:00…20:00, each F ท้องฟ้าโปร่ง / C เมฆครึ้ม / R ฝนตก / blank |
| 2 Manpower | lines `{role, count}`; role list from settings (ผู้ควบคุมงาน, หัวหน้างาน, ผู้ปฏิบัติงาน, ช่างไฟฟ้า, …); `crewConfirmed: Bool` |
| 3 Tools | lines `{name, count}` from a tool list |
| 4 Material on site | `{name, location, qty, unit, remark}` |
| 5 Progress | `{mpTask?, description, location, percentCumulative}` |
| 6 Problems | `{description, solution, status open/closed}`; open ones carry to the next day |
| Photos | the log's `PhotoAsset`s, each tagged with a progress line (optional) for R3 slides |
| Key plan | station picture with the day's locations highlighted (from the survey A2 site picture when present) |

`details` (the old text) is written as a readable summary of the progress lines, so the existing log list,
`LogCard` and search keep working.

### 2.2 Weekly request (R1)

New SwiftData model `WeeklyRequest` (or JSON on `Job` if one per week is enough — decide in review):
`weekStart` (Sunday, same weeks as MP), crew plan, tool plan, work plan `{mpTask?, description, location, qty, unit}`,
risks `{description, level ต่ำ/กลาง/สูง, prevention}`, `engineerSignedAt`, `approvedAt`, `approvedBy`.

### 2.3 Station settings used by reports

On the job (from the PWA project data): contract name, employer (การไฟฟ้าส่วนภูมิภาค), contractor (บริษัท ทีซี
รีนิวอะเบิ้ล เอ็นเนอร์ยี่ จำกัด), capacity kWp, **location list**, **working weekdays** (default จ.–ส.), holidays,
Site Engineer and Inspector names.

### 2.4 Sync

All new data is text (JSON strings, dates) on records that already sync (`installLogs`, `jobs`). A separate
`WeeklyRequest` model needs a new Firestore collection **and a rule in `firestore.rules`**. Photos stay on device and
Drive, as today.

---

## 3. Rules (pure logic, `TCRoofCore/RoutineReport`)

| Rule | Definition |
|---|---|
| "วันนี้" progress | `percent(today) − percent(previous report with the same line)`; shown, not stored |
| Line identity | `mpTask + description + location` |
| Next day prefill | crew & tools copied with `crewConfirmed = false`; open problems copied; progress lines < 100 % copied; weather blank |
| Missing day | a working weekday (settings) with no R2, not a holiday, between install start and today |
| Week | Sunday–Saturday, the same weeks as the MP plan |
| Man-days / tool-days | sum of counts over the reports in the range |
| Rain | rain hours = R slots; rain days = days with ≥ 1 R |
| Task % for MP | mean over the task's locations of each location's latest % (location not yet reported = 0) |
| Feed MP | after each saved, signed or unsigned R2, for every linked task, `MasterSchedule.Actual.setPercent(task %, week)` from the **signed** reports only (the contractor's foreman writes R2, our engineer signs it, so a draft must not move the plan; a report whose signature is taken off stops counting); the MP Gantt and weekly/monthly MP report follow automatically |
| R1 draft | MP tasks planned in that week and not yet 100 %, plus yesterday's crew and tools |
| Warnings before signing R2 | weather blank hours; no crew; crew not confirmed; a progress line went **down**; no progress line and no "หยุดงาน" reason |

A draft of this logic with tests against the ก.ค. 2568 files exists outside the repo (21 reports → 189 man-days,
84 tool-days, 25 rain hours on 6 days, missing 12/17/24/28/29/31 ก.ค.). It goes in only after this spec is agreed.

---

## 4. Screens

### 4.1 Job › การ์ด "รายงานประจำ"
Under the MP card on `JobDetailView`:
- today's status chip: **ส่งแล้ว** (green) / **ร่าง** (amber) / **ยังไม่ทำ** (red after 17:00)
- this week: 5/6 working days reported, R1 status (รออนุมัติ / อนุมัติแล้ว), R3 ready
- buttons: **รายงานวันนี้**, **คำขอสัปดาห์หน้า**, **รายงานสัปดาห์**, **รายงานเดือน**

### 4.2 รายงานประจำวัน (R2) — the main screen
iPad landscape: two columns. Left: sections 1–6 as cards. Right: photos of the day + key plan. iPhone: one column,
photos last. Bottom bar: **บันทึกร่าง** · **ตรวจ & ลงนาม**.

1. **อากาศ** — a 15-cell strip 06…20; tap cycles F → C → R → blank; long-press a cell and drag to paint a range;
   button **ทั้งวันโปร่ง**.
2. **กำลังคน** — steppers per role (44 pt), total man-day; banner "ใช้ค่าเมื่อวาน — แตะเพื่อยืนยัน" until confirmed.
3. **เครื่องมือ** — same pattern.
4. **วัสดุเข้าหน้างาน** — collapsed when empty; "+ เพิ่ม".
5. **ความก้าวหน้า** — one row per line: MP task chip (2.1 โครงสร้าง…), description, location chip, slider/stepper
   **% สะสม** with "+20 % วันนี้" shown beside it; "+ งาน" opens task → location (multi) → description.
   Lines carried over from yesterday are listed first.
6. **ปัญหา / อุปสรรค** — open items from yesterday on top with **ปิดเรื่อง**; "+ ปัญหา".
- **ภาพถ่าย** — camera / library (existing `PhotoPickerSection`); each photo can be tagged to a progress line.
- **ตรวจ & ลงนาม** — shows the warnings list; signing stamps the engineer and makes the PDF.

### 4.3 คำขอปฏิบัติงานรายสัปดาห์ (R1)
Opened for next week (default) with the draft from §3. Sections: กำลังคน, เครื่องมือ, แผนงาน (from MP, editable),
ประเมินความเสี่ยง (level chips ต่ำ/กลาง/สูง + แนวทางป้องกัน; a short list of common risks: งานบนที่สูง, ฝนตก,
งานไฟฟ้ามีแรงดัน, ยกของหนัก). Buttons **ส่งขออนุมัติ** (PDF) and **บันทึกอนุมัติแล้ว** (date + inspector name).

### 4.4 รายงานประจำสัปดาห์ (R3)
Read-only page built from the week's R2s, with an export to PDF (no PPTX: the meeting takes the PDF):
- cover: project, station, week number and dates
- progress: MP plan % / actual % for the week and cumulative (from `MasterSchedule.status`)
- per day: work done (progress lines with "วันนี้" > 0) and 2–4 tagged photos — replaces the hand-made slides
- weather table (7 days × 15 hours), man-days by role, tool-days
- problems open / closed this week; missing report days
- next week: the R1 of the following week if it exists

### 4.5 รายงานประจำเดือน (R4)
Same idea at month scale, following the existing docx structure: ส่วนที่ 1 รายละเอียดโครงการ (static, from the
project), ส่วนที่ 2 ความก้าวหน้า (MP table + สถานะการยื่นขออนุญาต from the document flow + photos), ส่วนที่ 3
แผนเดือนถัดไป (MP tasks planned next month), ส่วนที่ 4 สรุปแรงงาน (man-days by role per week). When the MP actual
reaches 100 %, the title becomes "ติดตั้งแล้วเสร็จ".

### 4.6 Export and filing
- PDF for R1–R4 via `PDFReport` (`DrawOp` pages, A4; weather/man-power tables as vector tables).
- Optional Excel for R2 matching the company template **without** the hidden Week3/Week4 sheets.
- Upload to Drive into the same structure as the cleaned folder:
  `<สถานี>/1. คำขอปฏิบัติงานรายสัปดาห์ …/`, `2. รายงานประจำวัน …/2568-07 กรกฎาคม/`, `3. …`, `4. …`, `5. ภาพถ่ายประจำวัน …/`.

---

## 5. Notifications
- 17:00 on a working day with no signed R2: "ยังไม่ได้ส่งรายงานประจำวัน <สถานี>".
- Friday 15:00: "ยังไม่มีคำขอปฏิบัติงานสัปดาห์หน้า".
- Uses the existing `NotificationScheduler`.

---

## 6. Open questions
1. Does the Inspector sign in the app (second iPad / link), or do we only record the date they signed on paper/LINE?
2. ~~Weekly report output: PDF only, or must it stay PowerPoint for the meeting?~~ PDF only (2026-10-17).
3. Who fills R2 on site — our engineer or the ผรม. foreman? (decides who may edit, and whether ผรม. needs app access)
4. Role and tool lists: fixed company lists, or per project? The 2560 template had 24 roles / 30 tools; โชคชัย used 3 / 4.
5. Working days: Mon–Sat everywhere? Public holidays list from where?
6. Is one R1 per week enough, or are there mid-week revisions that need versions?
7. "Key plan": draw from the survey A2 site picture, or attach the drawing the team uses now?
