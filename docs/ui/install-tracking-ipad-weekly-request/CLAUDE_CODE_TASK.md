# Claude Code task: iPad install tracking, `คำขอรายสัปดาห์` tab in the page

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/install-tracking-ipad-weekly-request` and type
> `Follow docs/ui/install-tracking-ipad-weekly-request/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels: keep them exactly.

**Do only what this task lists.** Do not refactor, rename or restyle anything outside the change list in §5. Do not touch:

- the iPhone (`InstallTrackingPage+Phone*.swift`)
- the other tabs of the page
- the R1 PDF layout (`RoutineReportPages.request`)
- Firestore rules or sync
- any stored field except the two optional fields in §5 item 2

**Example data.** The board's station, weeks, crew, tools, tasks, risks and dates are examples (`assets/sample-data.json`).
The app reads:

- `RoutineReport.WeeklyRequest` (`Job.weeklyRequest(for:)`, `RoutineReport.requestDraft`)
- the MP plan
- the job's routine settings
- the tools register (`ToolsView`, `Documents/Tools/instruments.json`)

Never hard-code a board value.

## 1. Context

- `InstallTrackingPage` (`TCRoof/Views/Install/Tracking/`) is the iPad page of a PWA station being installed. Its
  `คำขอรายสัปดาห์` item is `Item(id: "request", … route: .request)` and pushes `WeeklyRequestScreen(job:)`
  (`TCRoof/Views/Job/RoutineReports/WeeklyRequestScreen.swift`): a plain form of cards (กำลังคน, เครื่องมือ, แผนงาน,
  ความเสี่ยง) with a bottom bar.
- The board **`iPad · ติดตามงานติดตั้ง + ภาพรวมโครงการ (โครงการเดียว)`** (`iPadInstall.dc.html`, 1366 × 1024, menu `wq`)
  now draws `คำขอรายสัปดาห์` **in the page**, as the R1 request form. This task builds that tab.
- Another branch, `design/install-tracking-ipad-docs`, does the same for `เอกสาร` (it adds `Tab.docs`). Both may add a
  case to `Tab`. Keep your change small so the two merge cleanly.
- The roles, `WeeklyRequest.status` / `send` / `sendBack` / `approve` / `reopen` / `isEditable(external:)` and
  `WeeklyRequest.trusting` already exist. Reuse them; do not change their behaviour.

## 2. Before you start

Start with code-review-graph, as `CLAUDE.md` says:

- `InstallTrackingPage`: `items`, `Route`, `Tab`, `go(_:)`, `requestWeek`
- `WeeklyRequestScreen`: `load`, `workCard`, `riskCard`, `bottomBar`, `save(file:)`, `exportPDF`, `InspectorAckSheet`
- `RoutineReport`:
  - `WeeklyRequest`, `Count`, `PlanLine`, `Risk`, `RiskLevel`
  - `requestDraft`, `commonRisks`, `defaultRoles`, `defaultTools`
- `RoutineReportPages.request` (the PDF), `ToolsView` (the register and its calibration dates)
- `tests_for` on anything you touch, plus `InstallTrackingUITests` and the routine report tests

Then read the source and open `iPadInstall.dc.html` as text. The tab's logic is the block after `v.isWq` in
`renderVals()`, and its markup is the `{{isWq}}` section.

## 3. Files in this folder

| File | Shows |
|---|---|
| `PROMPT.md` | The prompt to paste into Claude Code |
| `iPadInstall.dc.html`, `grf.css` | The board (the whole install page; this task is its `คำขอรายสัปดาห์` tab) |
| `preview.png` = `states/01-draft.png` | Next week's draft, nothing signed. @2x (2732 × 2048) |
| `states/02-edited.png` | Edits while a draft: a role off on one day (`หยุด`), workers + 1, a day added to 7.3, a task outside the MP plan, 7.2 removed |
| `states/03-signature-sheet.png` | `เซ็นชื่อ` opened the signature sheet |
| `states/04-signed-ready.png` | Signed: the signature box, `ส่งขออนุมัติ (PDF)` enabled |
| `states/05-sent-waiting.png` | Sent: `ส่งแล้ว · รอผู้ตรวจ กฟภ. อนุมัติ`, read only, `บันทึกอนุมัติแล้ว` for the team |
| `states/06-approved.png` | Approved: steps all green, read only, no steppers |
| `states/07-previous-week.png` | Week 40 (approved) after `‹` |
| `states/08-pdf-preview.png` | `ดู PDF`: the A4 R1 form preview with `แชร์`, `ปิด` and `บันทึก PDF` |
| `states/09-draft-scrolled-end.png` | The left column scrolled to its end: the work table's end and `4 ประเมินความเสี่ยง` |
| `assets/sample-data.json` | The board's example values |

## 4. The tab

The page header, tab bar and dock stay as they are. Under the tab bar there is a header card, then two columns: the
form on the left (scrolls) and a fixed right panel (about 340 pt).

### 4.1 Header card (full width)

- **Left:** `คำขอปฏิบัติงานรายสัปดาห์`, with the sub-line `ส่งก่อนเริ่มสัปดาห์`.
- **Week switcher:** `‹` / `›` (44 pt), `สัปดาห์ที่ n` and the dates (Mon–Sat, as the MP plan's weeks). It opens on
  next week, as `WeeklyRequestScreen` does today.
- **Status chip:**

  | `WeeklyRequest.Status` | Chip |
  |---|---|
  | `.draft` | `ร่าง · ยังไม่ส่ง` (blue) |
  | `.sent` | `ส่งแล้ว · รอผู้ตรวจ กฟภ. อนุมัติ` (purple) |
  | `.approved` | `อนุมัติแล้ว` (green) |

- **Right:**
  - the `กำหนดส่ง` line: in a draft, the deadline with how many days are left (orange). This is the Friday reminder
    that already exists, the routine report reminder `ยังไม่มีคำขอปฏิบัติงานสัปดาห์หน้า`, and its time comes from
    settings. Once sent or approved, the sent or approved date.
  - `ดึงจากแผน MP`, only while editable: rebuilds the work lines from `requestDraft` for that week, keeping lines the
    user added outside the plan. It shows a spinner, then a chip `✓ ดึงจากแผน MP hh:mm` on the work card.
  - `ดู PDF`: the preview of §4.6.

### 4.2 `1 กำลังคน`: a role × day table

- **Header:**
  - `กำลังคน`
  - a chip `ผู้รับเหมา … ยืนยันแล้ว` when the crew has been confirmed. If there is no such flag today, leave it out and
    list it in §7.
  - the hint `แตะช่องวันเพื่อให้ตำแหน่งนั้นหยุด`, while editable
  - on the right: `ต่อวัน n คน` with the change from last week (`+1 จากสัปดาห์ก่อน`), and `ทั้งสัปดาห์ n คน·วัน`
- **Columns:** `ตำแหน่ง` · one per working day (จ–ส, from `routineSettings` working weekdays) · `คน·วัน` · `จำนวน`.
- **One row per `crew` Count:**
  - an icon and the role
  - a sub-line comparing with last week's approved request (`เท่าสัปดาห์ก่อน` / `สัปดาห์ก่อน 3 (+1)`)
  - day cells:
    - the count on a day that has at least one work line
    - `หยุด` when that role is off that day
    - `–` on a day with no work
  - the row's man-days
  - a `− | +` stepper (hidden when read only)
- **Bottom row** `รวมต่อวัน`: the sum per day and the week's man-days.
- **Interaction:** tap a day cell to switch that role off or on for that day, while editable.

### 4.3 `2 เครื่องมือ`: four cards in a row (wrap if more)

- **Header:** `เครื่องมือ` and `รวม n ชิ้น · n รายการ`. A note `● เครื่องวัดสอบเทียบแล้ว · ดึงจากทะเบียนเครื่องมือ`.
- **Each `tools` Count is a card:**
  - an icon, the name, and the count with `ชิ้น`
  - a `− | +` stepper (hidden when read only)
  - a calibration line taken from the tools register by matching name: `สอบเทียบถึง …` (green), `สอบเทียบครบ …` within
    30 days (orange, with a warm card fill), or `ไม่ต้องสอบเทียบ` (muted). Use the register's own due logic (the badge
    rule of `ToolsView`). An item not in the register shows no line.

### 4.4 `3 งานที่ขอเข้าปฏิบัติ`: task × day table

- **Header:**
  - `งานที่ขอเข้าปฏิบัติ` and `n งาน · n มีวัน`
  - a legend: `วันทำงาน` (blue), `ยกมา` (orange), `ยังไม่มีวัน` (outlined)
- **Columns:**
  - `MP` (code)
  - `งาน · ตำแหน่ง · ปริมาณ`, with the hint `แตะช่องวันเพื่อเลือก / ยกเลิก` while editable
  - the working days
  - a remove column
- **One row per `PlanLine`:**
  - the MP code, or `+n` for a line outside the plan
  - the title, one line
  - a tag:
    - `จากแผน MP`
    - `ยกมา · ช้า n วัน`: a task carried over from this week because it is behind the plan. Use the plan's status for
      that week.
    - `ยังไม่มีวัน · รอนัด`: a line with no day
    - `นอกแผน MP`: `task == nil`
  - the location and quantity
  - the day cells:
    - a working day: blue
    - a carried-over task's first day: orange, reading `ยกมา`
    - a line with no day: outlined orange cells
  - `×` to take the line out of the request. It stays in the MP plan. Show a short confirmation toast.
- **Interaction:**
  - tap a day cell to add or remove that day, while editable
  - `+ เพิ่มงานนอกแผน MP` adds a line with `task: nil` and asks for its name, location and quantity, in the existing
    inline fields or a small sheet
- **Bottom row** `งานต่อวัน`: the number of lines per day (`3 งาน`, `–` on a day with none).

### 4.5 `4 ประเมินความเสี่ยง`

- Two columns of risk cards. Each card has the description, `ป้องกัน: …`, and level chips `ต่ำ | กลาง | สูง` (green /
  orange / red when selected).
- Suggestion chips from `commonRisks` that are not yet listed (`+ ยกของหนัก`, …) add a risk, while editable.

### 4.6 Right panel

- **Header:** `สัปดาห์ที่ n` and the status chip.
- **Approval flow:** three steps, each with a number, or a green ✓ once done:
  1. `ร่างคำขอ` · `Site Engineer · ยังไม่ลงนาม / ลงนามแล้ว`
  2. `ส่งขออนุมัติ (PDF)` · `ส่งถึงผู้ตรวจ …`
  3. `อนุมัติ` · `ผู้ตรวจ …`, the inspector name from settings

  The current step is blue.
- **`ตรวจก่อนส่ง`** (hidden once approved): ✓ or ! rows, each with a reason line when it fails:
  - the work matches the MP plan's week
  - every line has a location and a day (`n งานยังไม่มีวัน · แตะช่องวันเพื่อเลือก`)
  - risks cover work at height and live electrical work
  - the crew is confirmed
  - the requester signed (`ยังไม่ได้เซ็น · เซ็นด้านล่าง` / `ใส่ชื่อผู้ส่งคำขอ`)

  These are warnings except the signature and the name, which gate sending.
- **Signature** `ลายเซ็นผู้ส่งคำขอ *` · `SITE ENGINEER`:
  - Unsigned: a compact dashed `เซ็นชื่อ` button. It opens a signature sheet with a drawing pad, the name under the
    line, `ยกเลิก` and `ยืนยันลายเซ็น`. Reuse the daily report's signature pad and its `PhotoAsset` storage pattern if
    one exists. Otherwise keep the existing `engineerSignedAt` behaviour and list the drawing in §7.
  - Signed: a small box with the signature and `ลงนาม <date>`, plus `✕` to clear it while a draft.
  - Below it, the requester's name: a field while a draft, plain text after.
- **Primary button:**
  - Draft: `ส่งขออนุมัติ (PDF)`, enabled only when signed and named. It calls the existing send path
    (`send(by:signs:)`, `save(file: true)`) and files the PDF.
  - Sent: `บันทึกอนุมัติแล้ว` for the team (`InspectorAckSheet`) and `ส่งกลับให้แก้`, as today.
  - Approved: a green `✓ อนุมัติแล้ว` state, plus the team's existing `เปิดแก้อีกครั้ง`.

  Follow `WeeklyRequestScreen`'s current rules for who sees what (`mayAct`, `isEditable(external:)`).
- **`ดู PDF` sheet:**
  - the R1 page from `RoutineReportPages.request`, as an image of page 1, A4
  - the title `คำขอปฏิบัติงาน สัปดาห์ที่ n.pdf` and `A4 · 1 หน้า · <status>`
  - `แชร์` (the existing share sheet), `ปิด` and `บันทึก PDF` (files it as today)

  Do not change the PDF layout. If the PDF does not yet print the new per-day ticks of §5 item 2, list that in §7; do
  not change it.

**Read only.** When `!editable`, hide every stepper, `×`, `+ เพิ่ม…` and `ดึงจากแผน MP`, and do not react to taps on
cells. Contractors and the team follow `isEditable(external:)` exactly.

## 5. Change list

Work in this order and tick each item in your report.

1. [ ] **Route → tab:** in `InstallTrackingPage`:
   - add `case request` to `Tab`, and change the `request` item to `tab: .request` (in place)
   - keep `Route.request` and `WeeklyRequestScreen` for every other caller: the job screen's routine card, the home
     and the iPhone
   - check that the overview's tiles and `ต้องดำเนินการ` rows that open the request now land on the tab
2. [ ] **Model (optional fields only):** in `RoutineReport`, add:
   - `PlanLine.days: [Int]`: the weekdays 0…5 of the week the line is planned on. Empty = no day yet. `requestDraft`
     fills it from the plan's start and end within the week.
   - `WeeklyRequest.crewOff: [String]`: keys `"<role index>-<day>"` for a role off that day. Empty by default.

   Both decode with `decodeIfPresent` defaults, so old JSON still loads. Add them to `CodingKeys`. `trusting` keeps
   treating them like the other fields. Add unit tests: old JSON decodes, the draft fills `days`, man-days per day
   honour `crewOff`. Write the per-day and man-day sums as pure functions in `TCRoofCore`, and test them.
3. [ ] **View:** add `InstallTrackingPage+Request.swift` with:
   - the header card
   - the four left cards (§4.2–§4.5), each a computed property
   - the right panel (§4.6)

   Fit the page above the dock as the other in-page tabs do (`dockClearance`). The left column scrolls; the right
   panel does not. Reuse `WeeklyRequestScreen`'s state handling (`load`, `save(file:)`, `exportPDF`) by moving shared
   bits into a small helper both use, not by copying.
4. [ ] **Signature sheet:** compact `เซ็นชื่อ` button → sheet (§4.6). Signing sets `engineerSignedAt` as today's send
   does.
5. [ ] **DEBUG flags:**
   - `-installTab request` opens the tab
   - `-installRequestWeek 0|1|2` picks next week, the one before, the one before that
   - `-installRequestState sign|signed|sent|approved|pdf|edited` opens states 03–08 and 02
   - with `-installDemo YES`, show the board's example (nothing saved)

   Add one line to `CLAUDE.md`'s `-installOpen` item.
6. [ ] **UI test:** extend `InstallTrackingUITests`:
   - `คำขอรายสัปดาห์` opens in the page (no push)
   - a crew day cell toggles `หยุด` and the day total changes
   - a work day cell toggles and `งานต่อวัน` changes
   - `ส่งขออนุมัติ (PDF)` stays off until signed
   - the signature sheet's `ยืนยันลายเซ็น` enables it
   - `ดู PDF` opens its sheet
   - `-role external` on a sent week shows no steppers
7. [ ] **Build and screenshots:** follow §6.

**Out of scope:**

- the iPhone page
- the R1 PDF layout
- new Firestore fields or rules (the two optional fields ride in `weeklyRequestsJSON`)
- the tools register itself
- weather or per-day crew requirements

## 6. Check

- `cd TCRoofKit && swift build && swift test`, and an app build:
  ```
  xcodebuild -project TCRoof.xcodeproj -scheme TCRoof -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratch>/DerivedData build
  ```
  Use your own `-derivedDataPath`, and run it in the background.
- On an iPad simulator:
  ```
  xcrun simctl launch <udid> com.tcroof.internal -screen home -homeTab pwa -homeBoard YES -installOpen YES -installDemo YES -installTab request [-installRequestState signed]
  ```
  Save the screenshots to `screenshots/` with the names of `states/`, and compare them.
- **Colours** come from `Theme` (no hex, no `Color.white`).
- **Hit areas** are ≥ 44 pt (day cells included: make the cell's tap area 44 pt even when the drawn bar is shorter).
- **VoiceOver:**
  - a crew cell reads `<role> <day> <n> คน` or `ไม่มา`
  - a work cell reads `<day> มีงาน` or `ไม่มีงาน`
  - the steppers read `ลด / เพิ่ม <name>`

## 7. Open questions (report your answers; do not block on them)

1. Is there a "crew confirmed by the contractor" flag? If not, should `ผู้รับเหมา … ยืนยันแล้ว` come from the
   contractor sending the request?
2. Should `crewOff` and `PlanLine.days` print on the R1 PDF (ticks per day), or stay in the app only for now?
3. Does the signature need a drawn image in the PDF (like the daily report's `signature.engineer`), or is the name and
   date enough?
4. The deadline: is Friday 15:00 the rule for every station, or a routine setting per station?
5. The tools' calibration line matches by name. Should a request's tool keep a link to the register's item id instead?
