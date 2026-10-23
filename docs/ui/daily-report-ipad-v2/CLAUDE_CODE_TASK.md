# Task: iPad · รายงานประจำวัน v2 (one page · key plan · task list)

Board: `iPadDaily.dc.html` (1366 × 1024, prop `step` = 0). States: `states/*.png`.
Assets:
- `assets/daily/station-keyplan.jpg`: the A2 site picture of สถานีผลิตน้ำโชคชัย.
- `assets/daily/photo-1…4.jpg`: the real report's photos of 2 ก.ค. 2568.

These assets are board examples only. Don't ship them.

Branch: this hand-off lives on `design/daily-report-ipad-v2`, cut from `main` bf220f0.
Work on `feat/daily-report-ipad-v2` cut from it, and push it. Do not merge.

v1 (`docs/ui/daily-report-ipad`) is built: `DailyOnePage`, `DailyOnePage+Plan`, `DailyOnePage+Work`.
This task is **only the difference between v1 and v2**. Everything not listed stays as it is in the app:
- the right column (day switcher, เวลาทำงาน, team, signing)
- the PDF
- the iPhone
- the model

## Scope: only this

Change `DailyOnePage` (iPad regular width ≥ 1000 pt) so that the left card, the key plan's top-right controls and the save button match the board.

Out of scope:
- the right column (except removing one line, item 7)
- the 4-step wizard (`step` 1–4)
- the PDF's look
- iPhone, R1, R3, R4

## Change list

1. **No card header.** Remove the work card's header row: `งานวันนี้`, the `n งาน · n อาคาร · ถ่ายแล้ว n รูป` line, and the `+ งานจากแผน MP` button with its menu.
   MP tasks are added only by the key plan's `+` ghost pins (already in v1).
   Also remove the `+` (เพิ่มงาน) button of v1's tab strip.

2. **One scroll for plan and list.** The left card holds one vertical scroll view with, in order:
   - the key plan (inset 10 pt top, 12 pt sides, radius 12, ~560 pt tall)
   - the task list (item 4)

   The **selected task's detail** (item 5) is pinned under the scroll view, at the card's bottom edge. It does not scroll.

3. **Key plan overlay.**
   - **Top left:** a `KEY PLAN` badge (navy pill, white 12 pt bold, letter-spaced) followed by `หน้า 2` (it prints on DAILY REPORT page 2), on a white rounded chip.
   - **Top right:** two compact buttons, 28 pt visual on a 44 pt hit area, white with a hairline border:
     - **`อัปโหลดผัง`** (upload icon + text). It opens a menu (state 03), each row 48 pt with icon, title and subtitle:
       1. `ถ่ายรูปผัง` · `กล้อง · ปรับมุมกระดาษอัตโนมัติ`: camera, then document perspective correction (VisionKit document camera).
       2. `เลือกจากคลังภาพ` · `JPG · PNG`: PhotosPicker.
       3. `ไฟล์แบบ PDF / DWG` · `เลือกหน้าและครอปเฉพาะผัง`: file importer. For a PDF, pick a page, then crop. Report what you do with DWG (see open question 2).
       4. `ใช้ภาพ A2 จากรายงานสำรวจ` · `ภาพผังหน้างานที่ลงนามแล้ว`: back to today's source, the linked survey's `siteMap`.

       After an upload, toast `อัปโหลดผังแล้ว · ลากหมุดงานไปวางบนผังใหม่`. After the A2 option, toast `ใช้ภาพ A2 เป็นผังของสถานีนี้แล้ว · ตำแหน่งงานเดิมยังอยู่`.
       Location points keep their normalized positions.
     - **⛶ full screen**: same action as v1 (state 07), now the same compact 28 pt style.
   - Legend chip bottom left: unchanged.

4. **Task list v3** (replaces v1's tab strip, panel quick picks and status line).

   Lines are **grouped by location**, sorted by Thai numeric order (`หลังคา 1, หลังคา 2 … ห้องอินเวอร์เตอร์`).
   - **Group header:** building glyph, the location bold 13 pt, then `n งาน · +x% วันนี้` (the sum of today's % in the group), then a hairline to the right edge.
   - **Row:** a white card, radius 12, 1 pt `#DDE4ED`-like border.
     - The selected row's border takes the task colour, with a soft shadow.
     - The grid is `26 pt pin | title | progress control | camera`.
   - **Pin:** a 26 pt circle in the task colour with the line number.
   - **Title block** (a button, ≥ 44 pt): the name (14.5 pt bold, one line, ellipsis) over `MP <code> · ก่อนวันนี้ <before>%`.
     - **Tap = select the line AND take a photo for it.** That is the camera action of the camera button.
     - Accessibility label: `<name> · แตะเพื่อถ่ายรูป`.
   - **Progress control** (replaces the `+10 / +20 / +30 / +50 / เสร็จ` picks):
     - `−` (36 × 40, radius 10): today −5 %, floor 0.
     - **A 10-segment bar** (150 pt wide, 44 pt tall hit, 16 pt tall bar, 2 pt gaps, ends rounded 6 pt). Each segment is 10 % of the whole task.
       - Segments ≤ the accumulated-before-today % are grey (`#9FB3CC`) and disabled.
       - Segments up to before + today are in the task colour. The rest are light (`#E3E9F1`).
       - Tapping segment *i* sets today = min(remaining, i × 10 − before). The control is an accessibility slider with `ถึง n%` per segment.
     - `+` (36 × 40): today +5 %, capped at the remaining.
     - Value column (74 pt): the accumulated % (15 pt bold), and under it `+x% วันนี้` in the task colour. When today is 0, show `ยังไม่กรอก` in orange `#B45309`.
     - **`เสร็จ`** toggle (✓ + text, 40 pt). It sets today = remaining.
       - On: filled green `#2E9E5B`, white text.
       - Off: white with a green border.
   - **Camera button** (44 × 40, radius 10), with a count badge (top-right, the task colour) when the line has photos.
     - With photos: soft blue.
     - No photo yet: orange dashed (`#FFF8F0` fill, `#E8A15A` dashed border). That is the cue that a photo is missing.

5. **Selected task detail** (pinned at the bottom of the left card, white, top hairline).
   - Left: the pin (32 pt), the name (16 pt bold), and `<location> · <before>% → <after>% · <variance>`.
     - The variance is the MP task's actual vs plan to date, from `MasterSchedule` weights (v1's math): `เร็วกว่า 23.0%` in green or `ช้ากว่า 1.0%` in red.
   - Then the line's photo thumbnails:
     - 48 pt, radius 8, numbered.
     - A tap retakes that photo.
     - An empty `ถ่าย` slot with a camera glyph, dashed, takes a new one.
   - Then `n รูป · ใช้ในรายงาน`, or `ถ่ายอย่างน้อย 1 รูป` when there is none.
   - Right:
     - `+ วัสดุ` (soft blue pill)
     - `+ ปัญหา` (soft orange pill)
     - `เอาออก` (plain text button, removes the line from today)
   - **Material and problem rows** appear inside this footer, under it (state 11). The footer grows upward; the scroll view shrinks.
     - `วัสดุ`: [name, flexible] [qty, 80 pt, decimal] [unit, 90 pt] ✕.
     - `ปัญหา`: [problem] [solution / action] ✕.
     - A material row carries the line's location (`Material.location` exists).
     - `Problem` has no link to a line yet. Add an optional `lineKey` (the line's identity key: task + description + location) with `decodeIfPresent`.
     - Problems without a key show under no line, in the PDF as today.
   - v1's panel items **removed** from the screen:
     - the status pill `✓ งานเสร็จ / เหลือ n%` (the bar shows it)
     - `ใช้ <tools>`
     - the `MP 2.1 · โครงสร้าง + Walkway · 20%` line
     - the `สถานี +x%` bar line

   The data and the PDF still use all of them.

6. **Save button animation** (bottom bar `บันทึกร่างตอนนี้`, states 04–06):
   - idle → **saving**: spinner + `กำลังบันทึก…`, soft blue, disabled, ~0.9 s or until the save returns.
   - → **saved**: green fill flash, a check drawn in, `บันทึกแล้ว`, ~1.6 s.
   - → **clean**: green outline, ✓ `บันทึกแล้ว`, with the sub line `ล่าสุด HH:mm น.`.
   - Any edit returns it to idle.
   - Reuse `TCSaveButton.pad(...)` from `TCRoofUI/SaveButton.swift`. Don't build a new one.

7. **Team card header:** remove the right-aligned `n คน · เครื่องมือ n รายการ` text from `ทีมงานวันนี้`. The tiles and tabs already carry the counts.

8. **DEBUG:** extend `-routineDailyState` with the new states:
   - `upload` (the upload menu open)
   - `saving`, `saved`, `clean`
   - `material` (a material and a problem row on line 1)

   Keep `task2|tools|map|daybefore`. Update CLAUDE.md's `-routineDaily` line.

## Rules

- **Key plan source:** today it is only the survey's A2 `siteMap` (`Job.keyPlanPicture`). Add an optional per-station uploaded plan:
  - store it as a `PhotoAsset` on the job, synced by `Sync/PhotoSync.swift` like the daily photos
  - it wins over the A2 picture; option 4 clears it
  - the PDF's key plan (`reportKeyPlan()`) uses the same picture

  New fields are optional, and old data must still decode.
- The 10-segment bar and ±5 % keep v1's caps: today ∈ [0, 100 − before]. Put the segment → today mapping in `TCRoofCore` (`RoutineReport`), with tests.
- `Problem.lineKey` is optional; the PDF's problem table is unchanged.
- Group order and the group's `+x% วันนี้` are derived. They are not stored.
- Tap-title-to-shoot and the camera button share one action. When the report's photo slots are full, it shows the same message as the camera button.
- Theme tokens (the 5 task colours exist since v1), `TCButtonStyle`, hit areas ≥ 44 pt (the 28 pt key-plan buttons keep a 44 pt hit area), no hex in views.

## States

| File | What |
|---|---|
| 01-default | line 1 selected, list grouped (หลังคา 1, หลังคา 2 …), detail pinned at the bottom |
| 02-task-2 | line 2 selected: its row border in its colour, detail shows line 2 |
| 03-upload-plan | the `อัปโหลดผัง` menu open (4 options) |
| 04-saving | save button: spinner, `กำลังบันทึก…` |
| 05-saved | save button: green flash, `บันทึกแล้ว` |
| 06-saved-clean | save button: green outline, `ล่าสุด 17:42 น.` |
| 07-map-full | key plan full screen (as v1) |
| 08-team-tools | team card, `เครื่องมือ` tab (header line removed) |
| 09-count-dropdown | a count dropdown open (as v1) |
| 10-signed | reporter signed, `ส่งรายงาน` enabled |
| 11-material-problem | a material and a problem row inside the detail footer |
| 12-day-before | previous day |

Values are the board's example (สถานีผลิตน้ำโชคชัย, 2 ก.ค. 2568). Never hardcode them.

## Tests

- segment tap → today: below before (ignored), inside the remaining, past the remaining (capped)
- ±5 % at 0 and at the cap
- an uploaded key plan wins over A2. Clearing it falls back to A2. Old job data decodes.

## Check list

- [ ] Build with your own `-derivedDataPath`. `swift test` passes.
- [ ] iPad Pro 13" landscape screenshots 01, 02, 03, 06 and 11 in `docs/ui/daily-report-ipad-v2/screenshots/` (`-screen daily -routineDaily onepage -routineKeyPlan YES`), compared with `states/`.
- [ ] The PDF of `-routineDemo pdf` is unchanged, unless an uploaded plan is set.
- [ ] The iPhone daily report is unchanged.

## Open questions (report)

1. When a new plan is uploaded, the location points keep their normalized positions. Is that right, or should the user be asked to re-place them?
2. DWG in `ไฟล์แบบ PDF / DWG`: there is no DWG renderer on iOS. Accept PDF only and show DWG as "convert to PDF first", or drop DWG from the label?
3. With v1's tab strip gone, is the line list ever long enough to need a "collapse group" control?
