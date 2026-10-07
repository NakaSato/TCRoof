# แผนงาน MP (Master Project Schedule) per station (iPad Swift dev spec)

**Status:** Core logic built and tested (`TCRoofCore/MasterSchedule.swift`, 10 tests). Storage (§2), the job card
(§3.1), ตั้งค่าแผน (§3.2), the full screen (§3.3) and บันทึกความก้าวหน้า (§3.4) built 2026-10-07
(`TCRoof/Views/Job/MPScheduleViews.swift`, `MPScheduleScreen.swift`), and ภาพรวมทุกสถานี (§3.5, `MPOverviewView`, from
the Plan tab header) 2026-10-08; §4 not yet. The overview averages plan and actual over the stations' kWp. The progress sheet
does not take วันเริ่มจริง / วันเสร็จจริง yet.
**Source:** the company's per-station workbook `MP 189 สถานีผลิตน้ำทุ่งน้อย กปภ.สาขาเมืองพล 92.34 kWp.xlsx` (one sheet,
5,605 formulas). Every PWA station of โครงการประปา ระยะที่ 3–4 (102 stations) has one copy of it.
**Goal:** replace the 102 workbook copies with one screen per job: the plan is generated from three dates and one
flag, the site reports progress per task per week, and plan vs actual is summarised per job and across jobs.

---

## 1. The workbook, and what the app keeps

| Workbook | App |
|---|---|
| 18 tasks in 3 parts with fixed weights (Permit 5, ติดตั้ง 90, ทดสอบ 5) | `MasterSchedule.Task`, `Part`, `weight(over200kVA:)` |
| Flag `เกิน 200 kVA` (B61) moves weight: อ.1 1.5→1, พค.2 0→1, ขนานไฟ 1.5→1 | `Input.over200kVA`; default from the job's inverter kW (`Input.isOver200kVA`) |
| วันเริ่ม / วันจบ (C56/C57) looked up from the external `ข้อมูลดิบ` sheet by MP number | `Input.installStart` / `installEnd`, typed or imported |
| Permit dates typed by hand (Kick off, Engineering, ส่งมอบพื้นที่) | `Input.kickoff`, `engineeringStart`, `siteHandover` |
| Construction and commissioning dates: fractions of the install length (e.g. แผง = len/4.5 days after โครงสร้าง) | `MasterSchedule.plan(_:)` — same formulas, Excel `ROUND` |
| Weekly grid J…BJ: plan = weight ÷ weeks spanned; actual = weight points typed per week | `plannedPoints(_:)`, `Actual.points[task][weekKey]` |
| Weekly Update (C66…D83): plan %, actual %, ช้ากว่า/เร็วกว่า, per part, per 2.x item | `status(plan:actual:through:)` |
| Monthly Update (C85…F98) | `month(plan:actual:year:month:)` |
| Contract period 540 days from 3 ก.ค. 2567 (C100…C104) | **not carried over** — stale in every copy (gives −188 days). Contract dates belong to the project, see §6 |

**Workbook problems the app fixes**
1. Two rows numbered "1.6" (COP and ขนานไฟ). The app numbers ขนานไฟ **1.7**.
2. Actual rows have no real start/finish dates, only weekly points. The app adds `Actual.started` / `finished`.
3. Monthly and weekly reports read different "current" periods (month 6 vs week 92), so they disagree
   (Construction 68 vs 90). The app derives both from one date.
4. Week numbers are `WEEKNUM()+52` with a special case for 1–3 ม.ค.; the app keys weeks by their Sunday
   (`yyyy-MM-dd`), the same weeks without the year-boundary hack.
5. The external link to `ข้อมูลดิบ` goes stale when the file travels alone.
6. Typo "Satety".

Verified against MP 189 (tests): every planned date, weekly plan 4 pts × 5 weeks for 2.1, cumulative plan
3.5 / 52.75 / 93 / 100 at weeks 60 / 64 / 66 / 67, cumulative actual 8.5 / 40.5 / 65.5 / 71.5 / 96, and the
Weekly Update at week 92: plan 100, actual 96, **ช้ากว่า 4**, Permit 3.5, Construction 90, Commissioning 2.5.

---

## 2. Storage

Add to `Job` (SwiftData, all optional so old stores open without migration code):

| Field | Type | Meaning |
|---|---|---|
| `mpNumber` | `Int?` | MP number in the PWA project list (e.g. 189) |
| `inverterKW` | `Double?` | inverter total; sets the default of `over200kVA` |
| `scheduleInputJSON` | `String?` | encoded `MasterSchedule.Input` |
| `scheduleActualJSON` | `String?` | encoded `MasterSchedule.Actual` |

- Both JSON fields are text, so they ride the existing `jobs` Firestore record in `CloudRecords.swift`; no new
  collection and no rules change.
- Two people editing the same week: last write wins per job (as other job fields today). Points are per task per
  week, so a merge by key is possible later if needed.
- `installStart` / `installDays` already on `Job` stay the source for the Plan calendar. When the MP input is saved,
  write `installStart = input.installStart` and `installDays = days(installStart…installEnd)` so both views agree.

---

## 3. Screens

### 3.1 Job detail › การ์ด "แผนงาน MP"
Under `scheduleCard` in `JobDetailView`:
- empty: **สร้างแผน MP** (opens 3.2)
- filled: progress ring `actual %` with the plan % as a tick, chip **ช้ากว่า 4%** (red) / **เร็วกว่า** (green) /
  **ตามแผน**, three part bars (Permit · ติดตั้ง · ทดสอบ), and the current week's tasks. Tap → 3.3.

### 3.2 ตั้งค่าแผน (sheet)
Fields: MP number, วันเริ่มติดตั้ง, วันจบติดตั้ง, Kick off, Engineering เริ่ม, ส่งมอบพื้นที่, toggle
**inverter เกิน 200 kVA (ต้องยื่น พค.2)** with the job's inverter kW shown beside it. Optional "ปรับจำนวนวัน" for
Engineering 7, อ.1 21, พค.2 21, ขนานไฟ 7. A live preview lists the 18 tasks with dates. Saving regenerates the plan;
actual points are kept.

### 3.3 แผนงาน MP (full screen)
- **Gantt:** rows = tasks grouped by part (code, title, weight); columns = weeks (Sunday label + `W` number);
  planned bar from start to end; actual drawn as the weeks with points (cell shade = points ÷ weight);
  today line. Weights 0 (COP, พค.2 when not needed) are shown greyed with "ไม่ใช้".
- **Top bar:** week picker (default this week), plan % / actual % / variance, Weekly ↔ Monthly toggle.
- **Report panel:** the workbook's Weekly Update and Monthly Update tables, from `status` and `month`.
- iPad landscape: Gantt left, report right. iPhone: report first, Gantt below with horizontal scroll.
- Draw the Gantt with SwiftUI `Canvas` (vector), per the project's "plans are vector" rule.

### 3.4 บันทึกความก้าวหน้า (sheet, from a Gantt row or "อัปเดตสัปดาห์นี้")
For the chosen week, one row per task active or unfinished: a stepper/slider of **% สะสมของงานนี้** (0…100).
`Actual.setPercent` books the difference into that week and caps at the task's weight. Optional: วันเริ่มจริง /
วันเสร็จจริง. Save writes `scheduleActualJSON`.

### 3.5 ภาพรวมทุกสถานี (Home or Plan tab)
One row per job with an MP plan: MP no., station, plan %, actual %, variance chip, current task. Sort by
variance (most behind first). Totals: number of stations behind, weighted average progress.

---

## 4. Import and export

- **Import MP workbook (.xlsx):** read C56/C57 cached values (install window), B59 (kWp), B61 (flag), permit dates
  E12/E14/E16, and every numeric cell in actual rows 13…51 × J…BJ (week index in row 9 → Sunday
  = 28 ธ.ค. 2025 + 7 × (index − 53)). This moves the existing 102 stations without retyping. Use the existing
  `ExcelExport` zip/XML reader.
- **Import the tracking workbook** (`สรุปสถานะโครงการประปา ระยะที่ 3`): MP no., station, branch, kWp, inverter kW,
  lat/long, address → create or update jobs.
- **Export:** the Weekly Update and Gantt as one PDF page (`PDFReport` `DrawOp`s), for the weekly meeting.

---

## 5. Links to other modules (later)

- Permit tasks (1.4 อ.1, 1.5 พค.2, 1.7 ขนานไฟ) take their actual from the PWA document flow
  (`forms/pwa/` in the TCRoof Project): approved → 100 %.
- Construction tasks 2.1…2.9 map to install photo slots; the progress sheet can require the slot's photos before
  100 %.

---

## 6. Open questions

1. Contract period: the workbook's 540 days from 3 ก.ค. 2567 is the same in every copy. Is there a real contract
   start/end per project (PEA(EMD)-03/2024, 05/2024) to show "ระยะเวลาคงเหลือ"?
2. Who may enter actual points: Engineer only, or Admin too? Should past weeks lock after the weekly meeting?
3. COP (1.6) has weight 0 in every case. Keep it as an untracked row or drop it?
4. The lower table in the workbook (rows 111–152) has other durations (โครงสร้าง 45 วัน, Inverter 60 วัน). Is it an
   older template, or a second plan type the app should offer?
5. Week labels: the sheet shows both an index (53…105) and "W0…W50". Which one does the team read in meetings?

---

## 7. Tests (`TCRoofCoreTests/MasterScheduleTests.swift`)

Weights sum to 100 and Permit to 5 both ways; every MP 189 date; พค.2 dates when over 200 kVA; weekly plan spread;
cumulative plan and actual against the workbook; Weekly Update at week 92; Monthly Update for ส.ค. 2569 (construction
22, commissioning 2); `setPercent` capping; JSON round trip; Sunday week keys.
