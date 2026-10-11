# Claude Code task: A1 ข้อมูลโครงการ on iPad (board update 10 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-a1-ipad/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels; keep them exactly.

**Example data.** Every value in the previews is example data (`assets/sample-data.json`):
- 224 / 00 / 29/9/2569 / สมชาย
- the project name, 120 kWp
- the address, the coordinator, the phone number
- GPS 17.0062, 99.8235
- ±5 ม. · 09:41
- the area counts 2 and 1

Bind everything to the real `Job.values` / `Schema.info` fields and settings.

## Context: what already exists

The iPad A1 page is `InfoPageWide.padBody` (`TCRoofKit/Sources/SurveyUI/InfoPageWide.swift` + `InfoPageWide+Sections.swift`), built from `docs/ui/survey-a1`. The following already work and must keep working:
- `SiteMapPreview` with zoom presets, `mapZoom` and the report crop `mapCrop` (`TCRoofCore/MapCrop.swift`, `MapCropTests`)
- `รีเซ็ตกรอบ`
- GPS locate with accuracy
- the date picker
- `tel:` on the phone number
- area steppers with the delete confirmation
- `InfoPageBar.padBar`

The iPhone page (`phoneBody`, `docs/ui/survey-a1-iphone`) and its `SaveButton` in `BottomBar.swift` are done. **Do not change the iPhone layout.**

This task brings `padBody` and `padBar` in line with the updated board `iPad · ขั้น 1/13 A1 ข้อมูลโครงการ` (`iPadA1.dc.html`, 1366 × 1024).

**Before reading the source**, use code-review-graph (per `CLAUDE.md`). Look up these symbols:
- `InfoPageWide`, `padBody`, `locationBox`, `documentBox`, `projectBox`, `coordinatorBox`, `areasBox`, `A1Card`, `RatioRow`
- `InfoPageBar.padBar`, `SaveButton`, `BottomBar`, `TCStepBar`
- `tests_for` on anything you touch

Then read the source.

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` = `states/01-landscape.png` | Whole page, iPad landscape, @2x (2732 × 2048) |
| `states/01-landscape.pdf` | **Vector** 1366 × 1024. Measure here. |
| `states/01a-header-step-crop.png` | Header and step line |
| `states/01d-bottom-bar-crop.png` | Bottom bar, idle |
| `states/02-crop-moved.png` | Report frame moved and resized; the label updates to `ภาพในรายงาน · 80 × 58 ม.` (1x) |
| `states/03`–`05-save-…-bar.png` | Save button: saving → just saved → saved idle |
| `preview.html` + `grf.css` | Static render; open in a browser to inspect sizes and colours |
| `iPadA1.dc.html` | Board source. Inline CSS gives exact values. The script holds the crop drag (`dragStart`) and the save states (`save`, `ph`). |
| `assets/sample-data.json` | Every label and example value |

**Icons:** no new icons. Reuse the `A1Icons` / `A2Icon` assets already in the app (`ui-gps-locate`, `ui-calendar`, `ui-phone`, `ui-prev`, `ui-next`, `a1-checkbox-on` / `-off`); originals are in `docs/ui/survey-a1/icons`.

## Changes, by area

### 1. Columns (landscape, content width 1240)

- Location card on the **left, 720 pt wide**; the right column takes the rest.
- Column gap **20** (was 28).
- Card gap inside the right column: **14**.
- Both columns stretch to the same height. The location card's map grows to fill its card, minimum 232 pt high.
- Portrait iPad (one column) keeps the current order. Apply the new card contents from §2–§4 there too.

### 2. Location card `ที่ตั้ง` (left)

The card now holds **only** the map, the hint and the GPS:

1. **Map:**
   - fills the free height
   - radius 12, 1 pt `rgba(22,50,92,0.2)` border
   - unchanged parts: zoom segment top-left (selected level mint `#9EE6D6`), `+` / `−` top-right, scale bar, pin, report frame with corner handles and the label `ภาพในรายงาน`

   The board draws `+` / `−` at 32 × 32; keep a 44 × 44 hit area.
2. **Hint row** under the map (13 pt `#5B6B82`): the existing hint text, then the trailing link `รีเซ็ตกรอบ` (semibold `#1F6FB5`).
3. **`พิกัดดาวเทียม Google Map *`:**
   - the coordinate field
   - the `ตำแหน่งปัจจุบัน` button (`ui-gps-locate` + text, min 50 high)
   - the line `ความแม่นยำ ±5 ม. · บันทึกเมื่อ 09:41` (13 pt muted)

**`ที่อยู่สถานี / สถานที่ติดตั้ง` moves out** of this card into §4.

**`ที่อยู่สำนักงาน / สาขา` is not on the board.** See open question 1.

### 3. Card `เอกสาร` (right, top)

- One row: `เลขที่ *` · `REV.` · `วันที่สำรวจ *` (calendar icon, mint "pre-filled" fill) · `วิศวกรผู้สำรวจ *`.
- Width ratio **0.8 : 0.6 : 1.35 : 1.25**, gap 10.
- The engineer label now has the red `*`. Keep how `engineerInput` gets its value today.

### 4. Card `โครงการ · ผู้ประสานงาน` (right, middle)

This merges the old `projectBox` and `coordinatorBox` into one card. It takes the remaining height and spaces its rows evenly (`justify-content: space-between`, gap 14). The rows are:

1. `ชื่อโครงการ / สถานี *`
2. `ขนาดที่ต้องการติดตั้ง *` (unit `kWp`) | `สัญญาณอินเตอร์เน็ต *` with choice buttons `มี` / `ไม่มี` (min 50 high, selected mint). Ratio 1 : 1, gap 12.
3. `ที่อยู่สถานี / สถานที่ติดตั้ง *`: moved here from the location card, min height 50.
4. `ชื่อผู้ประสานงาน *` | `เบอร์โทร *` (`ui-phone`, tap = `tel:`). Ratio 1.4 : 1, gap 12.

Pre-filled fields keep the mint fill (`InfoPageWide.prefilled`).

### 5. Card `พื้นที่ติดตั้ง *` (right, bottom)

Unchanged in behaviour:
- aside `กำหนดหน้า C / D ในแบบสำรวจ · รวม 13 ขั้น` (the number is the live step count)
- two tiles `หลังคา` (`หน้า C · หลัง`) and `ถังน้ำใส` (`หน้า D1 · ถัง`)

Match the board's tiles:
- min 60 high, radius 12, fill `#E3EEF8`, 1 pt `rgba(22,50,92,0.2)` border
- 22 pt checkbox
- title 15 bold, sub 12 muted
- − count + with 44 pt targets

### 6. Shared input styling on this page

- Labels: 17 / 22 semibold navy with a red `*`; gap 6 to the control.
- Card titles: 18 semibold.
- Cards: white, 1 pt `rgba(22,50,92,0.2)` border, radius 12, padding 16 / 18.
- Inputs: min 50, padding 14, **radius 12**, 1 pt navy 45% stroke, 17 pt.

Use the existing `inputBox` and `A1Card`. Add a radius parameter only if needed.

### 7. Bottom bar (`padBar`)

**Left side:** the round badge (green ✓ / orange !) and **only** the status line `ครบ 11/11 ช่องในหน้านี้` (13 pt). The board drops the `บันทึกอัตโนมัติ HH:mm` line; see open question 2. The gap chips on other pages stay as they are.

**`บันทึกร่างตอนนี้`:**
- 170 × 56 (narrow: 130; tight: icon only), outlined.
- Animates **like the iPhone `SaveButton`**:
  1. idle `บันทึกร่างตอนนี้`
  2. tap → small spinner + `กำลังบันทึก` (muted)
  3. after the save returns: green fill `Home.okSoftBG`, a green circle with a white check that pops in (scale 0.6 → 1.15 → 1) and draws its tick, and `บันทึกแล้ว` in `Home.okTick`; about 1.35 s
  4. then a white button with a **2 pt** `Home.stepDone` border, a plain green check and `บันทึกแล้ว`
- Any edit (`job.editVersion` changes) returns it to idle.
- Ignore taps while saving.

**Do not copy the logic.** Generalise `SaveButton` in `BottomBar.swift`, for example:

```swift
SaveButton(width: 170, height: 56, font: 16, idle: "บันทึกร่างตอนนี้", busy: "กำลังบันทึก", save: …, version: job.editVersion)
```

The iPhone call site keeps its defaults (104, `บันทึก`). The save itself stays `model.flush(job.id)` with `savedNow = Date()`.

**VoiceOver** (same as iPhone):
- idle: `บันทึกแบบร่าง · มีการแก้ไขที่ยังไม่ได้บันทึก`
- saving: `กำลังบันทึก`
- saved: `บันทึกล่าสุดแล้ว · ยังไม่มีการแก้ไขใหม่`

**Nav buttons:** `‹ หัวข้อแรก` (210, disabled outline) and `ถัดไป 2/13 · A2 ภาพสถานที่ติดตั้ง ›` (250, gradient). These are unchanged.

If `TCStepBar` in TCRoofUI (gallery) shows the same button, update its preview to the animated version too.

**Screenshots:** add `-surveySave saving|saved|clean` support to the iPad button, as the iPhone button already has, so `states/03`–`05` can be reproduced.

## Rules

- Thai text exactly as in the previews.
- Colours come from `Theme` / `Home`; no new hex literals in views.
- Touch targets ≥ 44 pt.
- **Layout only:**
  - keep every `Schema.info` id, label and storage, `mapZoom` / `mapCrop`, and the Excel / PDF output
  - A1 completion counts stay as they are
- **iPhone A1 must not change.** Check it after the `SaveButton` refactor.
- Work on a new branch `feat/ipad-a1-v2`.

## Open questions

Choose the default unless it breaks something, and list your choice in the summary:

1. **`ที่อยู่สำนักงาน / สาขา`** (optional field) is not on the iPad board. The default is to leave it out of the iPad A1 layout but keep the field, its storage and its export. Say so in the summary so the owner can confirm.
2. **`บันทึกอัตโนมัติ HH:mm`** is gone from the board, because the animated button now shows the save state. The default is to remove the line on iPad A1 only. If the same `padBar` serves other pages, remove it everywhere and say so.

## Done when

- `xcodebuild` builds the app and TCRoofKit, and `swift test` passes, including `MapCropTests`.
- iPad Pro 13" simulator in landscape (1366 × 1024) matches `states/01-landscape.png`. Measure in the PDF.
- Moving and resizing the report frame updates the label (`states/02`).
- `รีเซ็ตกรอบ` restores the default frame.
- The save button runs through `states/03`–`05` and resets on edit.
- iPad portrait shows one column with the new card contents.
- iPhone A1 is unchanged.
- Write a summary of the files changed, the open-question choices and any remaining differences from the board.
