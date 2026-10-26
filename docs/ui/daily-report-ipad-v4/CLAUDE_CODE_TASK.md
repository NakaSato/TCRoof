# Task: iPad · รายงานประจำวัน v4: header, and the TC team's acknowledgement view (board 25 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/daily-report-ipad-v4`, then paste `PROMPT.md`, or type
> `Follow docs/ui/daily-report-ipad-v4/CLAUDE_CODE_TASK.md`

- **Board:** `iPadDaily.dc.html` (1366 × 1024, landscape, one-page layout).
  - Read it as text and search for `headT`, `isTc`, `ackGo`, `ลงนามรับทราบ`, `backGo` and `nextL`.
  - Its image references point at `assets/blob/*.jpg`, which are example pictures only.
- Thai strings in `backticks` are literal UI labels.
- **Everything on the board is example data** (`assets/sample-data.json`): สถานีผลิตน้ำโชคชัย, 2 ก.ค. 2568, names and times. Never hard-code it.

## Where this sits

| Hand-off | Covers | State |
|---|---|---|
| v1 `docs/ui/daily-report-ipad` | the one-page layout | built (`DailyOnePage`) |
| v2 `docs/ui/daily-report-ipad-v2` | the left card | built |
| v3 `docs/ui/daily-report-ipad-v3` | the right column: date calendar, working-time popover, reporter-only sign card | built (`DailyOnePage+Right`, `DailyOnePageUITests`) |
| **v4 (this)** | the header title, and a **TC team view** of the same page that acknowledges a sent report | this task |

**What changed on the board since v3:**
1. The header title now reads like the weekly request's. It is the document name with the date, `รายงานประจำวันที่ 2 ก.ค. 2568 (วันพุธ)`, with the station on the second line.
2. The page has two views:
   - **ผู้รับเหมา** fills in and signs. This is today's page, unchanged.
   - **ทีม TC** opens the sent report and signs its acknowledgement on this page.
   - The right column's sign card and the bottom bar change; nothing else does.

v3 moved the inspector's acknowledgement off this page (to the home feed and `DailyReportListView`'s `รับทราบ`). **v4 brings it back here, for the TC team only.** Keep the feed's and the list's `รับทราบ` working; they record the same thing.

## Scope: only this

**In scope:** `DailyOnePage` (iPad regular width ≥ 1000 pt):
- `header`
- `signCard` (in `DailyOnePage+Right.swift`)
- `bottomBar`
- the wiring in `DailyReportScreen` (`Actions`, the ack path)

**Do not touch:**
- the left card (v2)
- the date calendar and working-time popover (v3)
- the team card
- the iPhone daily report and `DailyReportScreen`'s non-iPad paths
- the PDF (`RoutineReportPages.dailyForm`): page 3 keeps both boxes, and now gets the inspector's drawn signature from here
- the stored fields of `InstallLog` / `RoutineReport`
- `firestore.rules`

No refactors or renames outside the list.

**Before editing:** use code-review-graph (per `CLAUDE.md`), else grep. Read:
- `DailyOnePage.swift`: `header`, `blocker`, `bottomBar`, `Actions`
- `DailyOnePage+Right.swift`: `signCard`, `idleBox`, `signedBox`, `signature`
- `DailyReportScreen.swift`: `onePage` actions, `requestSign`, `requestAck`, `acknowledge`, `clearSignature`, `InspectorAckSheet`
- `Job.recordInspectorAck`
- `InstallLog.inspectorAckAt` / `inspectorSignatureTag`
- `Permissions.signsDaily`, `UserRoles` (`daily.sign`, `daily.fill`)
- `DailyOnePageUITests`, `RoleUITests` (`dailySign`)

Then run `tests_for` on what you touch.

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` | = `states/02` |
| `states/01-contractor.png` | **ผู้รับเหมา** view: the new header; the rest as built in v3 |
| `states/02-tc-to-acknowledge.png` | **ทีม TC** view of a sent report, not yet acknowledged: the `ลงนามรับทราบ` card, and the bar with `ส่งกลับให้แก้` and a disabled `ยืนยันรับทราบ` |
| `states/03-tc-acknowledged.png` | ทีม TC after signing: the purple signed box, `ยืนยันรับทราบ` enabled |
| `states/04-header.png` | The header, cropped |
| `states/05-ack-card.png` · `06-ack-card-signed.png` | The `ลงนามรับทราบ` card, idle and signed |
| `states/07-tc-bottom-bar.png` | The TC bottom bar, acknowledged |
| `iPadDaily.dc.html` + `grf.css` + `assets/blob/` | Design source and its example pictures |
| `assets/sample-data.json` | The example values |
| `screenshots/` | Empty. Put your simulator screenshots here, named like `states/` |

## Change list

Work in order. After each item, build and take its screenshot.

### 1. Header title (`states/04`)
- **Line 1:** `รายงานประจำวันที่ <d MMM yyyy> (วัน<weekday in full>)`, for example `รายงานประจำวันที่ 2 ก.ค. 2568 (วันพุธ)`.
  - Use a full Thai weekday name (`อาทิตย์ … เสาร์`).
  - Add a formatter beside `RoutineReport.thaiWeekdayDate` (in `TCRoofCore`), with a test.
- **Line 2:** the station (`job.stationName`), as today.
- **Keep** the back button and the gear.
- **The board's `เปิดในบทบาท ผู้รับเหมา | ทีม TC` switch is for the canvas only. Don't build it.** The app chooses the view from the signed-in person (item 2).
- It changes with the day picked in the calendar.

### 2. Which view (`states/01`, `02`)
Add one computed property on `DailyOnePage`, for example `acknowledging: Bool`, passed in from `DailyReportScreen`.

- **TC view, all four must hold:**
  - the report is signed and sent: `log?.engineerSignedAt != nil`
  - it has no unsaved edits: `!dirty`
  - the viewer is on our side: `permissions.role != .external`
  - the viewer may acknowledge: today's `requestAck` rule
- **Otherwise:** the ผู้รับเหมา view, exactly as built.
- A team member who opens an unsigned report sees the ผู้รับเหมา view, as today.
- Report the rule you used (open question 1).

**In the TC view, the left card and the team card are read-only:**
- no quick picks, steppers, photo capture, `+ วัสดุ` / `+ ปัญหา`, `เอาออก` or `อัปโหลดผัง`
- the key plan, the photos and full screen still open
- Use one flag, not per-control checks scattered through the views. The left card likely already has an edit gate; reuse it if so.

### 3. The `ลงนามรับทราบ` card, in place of the sign card in the TC view (`states/05`, `06`)
**Title:** `ลงนามรับทราบ` (18 pt bold).

**Reporter row:** 52 pt, `Theme.successSoft` fill, 1 pt success border, radius 12.
- a 26 pt `Theme.success` circle with ✓
- `ผู้รายงาน <siteEngineer>` (14 pt bold)
- `SITE ENGINEER ผู้รับเหมา ลงนามและส่งแล้ว <HH:mm of engineerSignedAt>` (12 pt `Theme.successText`)

**Signature box:** full width, **170 pt**, radius 12.
- **Idle:**
  - dashed 1.5 pt border, `Theme.surfaceMuted`-ish fill (use the closest existing token)
  - the signature glyph, then `แตะเพื่อเซ็นรับทราบ` (15 pt bold) and `ตรวจงานในหน้านี้และ PDF ก่อนเซ็น` (12 pt `Theme.inkMuted`)
  - a hairline signing line 40 pt above the bottom, inset 18, with a small × at its left
- **A tap** opens the existing `InspectorAckSheet` (`signs: true`).
  - Don't build a second signature pad.
  - Saving goes through `acknowledge(name:at:signature:)` → `Job.recordInspectorAck`, which sets `inspectorAckAt` and the `signature.inspector` photo.
- **Signed:**
  - the drawn inspector signature sitting on the line (scaled to fit about 220 × 82)
  - a pill `✓ รับทราบแล้ว HH:mm` at the top left
  - a 44 pt clear button at the top right
  - **Clear** removes only the acknowledgement: `inspectorAckAt = nil` and the `signature.inspector` photo. It never touches the engineer's signature, unlike today's `clearSignature`, which clears both. Add a separate `clearAck` action.
  - No drawn image: show the name in italics on the line, as the reporter card does.

**Colour:** the board's purple is `Theme.planInspect` (light 0x6B4FBB):
- border, text and pill: `Theme.planInspect`
- fills: `Theme.planInspect.opacity(…)`, or add `Theme.inspectSoft` if you need a token. Report which.
- No hex in views.

**Name:** a label `ชื่อผู้ตรวจงาน`, then a field, centred, 48 pt, placeholder `ชื่อผู้ตรวจงาน ทีม TC`. It binds `routineSettings.inspector`; the ack sheet already uses that name.

### 4. The TC bottom bar (`states/02`, `03`, `07`)
**Status line:**
- **Waiting:** an orange `!` and `ผู้รับเหมาส่งรายงานแล้ว <HH:mm> · รอทีม TC ตรวจและเซ็นรับทราบ`.
- **Acknowledged:** a purple ✓ circle (`Theme.planInspect`) and `เซ็นรับทราบแล้ว · ส่งกลับไปยังผู้รับเหมาและลงใน PDF หน้า 3`.

**Buttons, left to right:**
1. **`ส่งกลับให้แก้`** in place of the save button. Secondary style, with `Theme.pendingText` / `Theme.pending` border.
   - It asks for a reason (an alert with a text field, as `ClaimReviewScreen` / `IECTestScreen` do).
   - It then clears the engineer's signature and any acknowledgement (today's `clearSignature`).
   - It posts the reason where the contractor sees it: the report's problems or notes field, whichever the model already has. **Don't add a stored field.**
   - Report where it went (open question 2).
2. **`PDF 3 หน้า · ดูตัวอย่างรายงาน`**, as today.
3. **`ยืนยันรับทราบ`** with the sub label `ยังไม่ได้เซ็นรับทราบ` / `เซ็นแล้ว`.
   - Disabled until acknowledged; `Theme.planInspect` when enabled.
   - Its action closes the page with a toast `รับทราบรายงานแล้ว`, since the acknowledgement is already saved by the sheet.

### 5. DEBUG, docs and test
- **`-routineDailyState`:**
  - Add `ack`: today's report signed by the example engineer, the TC view, not saved.
  - Add `acked`: the same with a drawn inspector signature.
  - Add `-role internal` to see the TC view.
- **CLAUDE.md:** add one sentence to the `-routineDaily` item.
- **UI test:** extend `DailyOnePageUITests` (iPad).
  - With `-routineDailyState ack -role internal`:
    - the card `ลงนามรับทราบ` is there and `ลงนามผู้รายงาน` is not
    - a tap on the box opens the ack sheet
  - With `-role external` on the same state: the ผู้รับเหมา view.
- **`RoleUITests`' `dailySign` cases must keep passing.**

## Rules
- Colours from `Theme` (`planInspect`, `success`, `successSoft`, `successText`, `pending`, `pendingText`, `inkMuted`, `surface`). No hex in views, no `Color.white`.
- Hit areas ≥ 44 pt. Buttons use `TCButtonStyle`.
- Split the ack card, its two box states and the TC bar into their own views or computed properties (Debug type-check limits).
- Old job data must still decode. Nothing stored changes shape.

## Check list
- [ ] `swift test` in `TCRoofKit` passes, with the header date formatter test.
- [ ] The xcodebuild app build passes, with your own `-derivedDataPath`, in the background.
- [ ] `DailyOnePageUITests`, `RoleUITests` and `DailyLeftCardUITests` pass on an iPad simulator.
- [ ] iPad Pro 13" landscape screenshots `01`–`07` in `screenshots/`, taken with:
  ```
  -screen daily -routineDaily onepage -routineKeyPlan YES -routineDailyState ack|acked -role internal
  ```
- [ ] The PDF of `-routineDemo pdf` is unchanged, apart from page 3 showing an inspector signature made here.
- [ ] The iPhone daily report is unchanged.

## Open questions (report, don't decide)
1. Who gets the TC view? The task uses a signed and saved report, a non-external viewer, and the existing ack permission. Should it be limited to the job's supervisor (`supervisorEmail`) or a named inspector instead?
2. `ส่งกลับให้แก้`: where should the reason live so the contractor sees it (notes, a problem line, a feed post)? Should sending back also notify the contractor?
3. After `ยืนยันรับทราบ`, should the page close, or stay open read-only?
4. Should the daily list (`DailyReportListView`) and the home feed's `รับทราบ` now open this page instead of the ack sheet?
