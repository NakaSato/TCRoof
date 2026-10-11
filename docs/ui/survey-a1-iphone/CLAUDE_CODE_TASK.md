# Claude Code task: A1 ข้อมูลโครงการ on iPhone

> **How to use:** open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-a1-iphone/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are literal UI labels; keep them exactly.

**Example data.** Everything in the previews is example data, listed in `assets/sample-data.json`:
- project `กปภ. สาขาตัวอย่าง — สถานีผลิตน้ำ 1`, 120 kWp
- GPS 17.0062, 99.8235
- coordinator `คุณสมหญิง ใจดี` / 081-234-5678
- document NO.224, REV 00, 29/9/2569
- engineer `สมชาย ใจดี`

Always bind to the real `Job.values` / `Schema.info` fields.

## Goal

`InfoPageWide` (`TCRoofKit/Sources/SurveyUI/InfoPageWide.swift` + `InfoPageWide+Sections.swift`) is the iPad A1 card layout (docs/ui/survey-a1). On iPhone it already shows in one column (`twoColumns == false`, `phone == width < 500`), but in this order:

1. location
2. document
3. project
4. coordinator
5. areas

The cards also use the iPad card styling.

On compact width (`horizontalSizeClass == .compact`), make A1 match the board `iPhone · ขั้น 1/13 A1 ข้อมูลโครงการ` (`PhoneA1.dc.html`, 390 × 844).

- **Keep the iPad layout unchanged** (two columns in landscape, one column in iPad portrait).
- Follow the pattern used for D1 on iPhone: `TankPageWide+Phone.swift` adds a `phoneBody`. Add `InfoPageWide+Phone.swift` with a `phoneBody` and switch to it in `body` when compact.

**Before reading the source**, use code-review-graph (per `CLAUDE.md`). Look up these symbols:
- `InfoPageWide`, `A1Card`, `FieldLabel`, `PageStepBar`, `InfoPageHeader`, `InfoPageBar` (`phoneBar`), `inputBox`, `RatioRow`
- `GPSLocator`, `SiteMapPreview`, `MapImage`, `JobEditorView.cardInfo`
- `tests_for` on anything you touch

Then read the source.

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` = `states/01-screen.png` | First screen, @2x (780 × 1688) |
| `states/01-screen.pdf` | **Vector** 390 × 844. Measure here. |
| `states/02-full-length.png` / `.pdf` | Whole page scrolled out (390 × 1233 pt). The PDF is vector. |
| `states/01a-…crop` | Header, step line, section 01 |
| `states/02a-location-crop.png` | Section 02 ที่ตั้ง: map, GPS, addresses |
| `states/02b-coordinator-document-crop.png` | Sections 03 and 04 |
| `states/03-internet-none.png`, `03a-…crop` | `อินเทอร์เน็ต` set to `ไม่มี` |
| `states/04-saving.png`, `05-saved-just-now.png`, `06-saved-idle.png` + `…a-…bar-crop` | Save button states (see "Bottom bar") |
| `states/01c-bottom-bar-crop.png` | Bottom bar, idle |
| `preview.html` + `grf.css` | Static render; open in a browser to inspect sizes and colours |
| `PhoneA1.dc.html` | Board source. Inline CSS gives the exact values. The `class Component` script at the end is the save-state logic. |
| `svg/` + `svg/README.md` | Icons with SF Symbol mapping; the map drawing is only a stand-in |
| `assets/sample-data.json` | Every example value and label on the board |

## Layout, top to bottom

**Page.**
- Background `#F3F6FA` (`--background`).
- Content margin 16.
- The sections are **full-bleed white bands**, not floating cards:
  - 1 pt `#DDE4ED` top border on each; the last band also has a bottom border
  - padding 12 / 16 / 14
  - 12 pt gap between the elements inside a band
- Bands touch each other.
- The page scrolls; the bottom bar stays fixed.

### 1. Header and step line

The shared iPhone step header, as on the other phone steps (D1).

**Header.**
- Gradient header with bottom corners 15.
- Title `A1 ข้อมูลโครงการ`: 19 / 24 pt, bold.
- Subtitle `แบบสำรวจ NO.224 · GRF2567-23407`: 13 / 18 pt, 92% opacity, one line, truncates.
- The board shows no back button. Keep the existing `InfoPageHeader` back / sidebar behaviour (see open question 2).

**Step line.**
- Padding 10 / 16 / 8.
- Row: `1/13` (bold, 14 pt), then `ข้อมูลโครงการ` in `#5B6B82`.
- Completion chip at the trailing edge: `ครบ 11/11 ช่อง`, 11.5 pt bold, capsule.
  - Green `#E2EFDA` / `#3B7420` when complete.
  - Orange `#FFF4E5` / `#B45309` with `ขาด n ช่อง` otherwise.
- Below it, 13 bars: 6 pt high, gap 2. The current bar is `#1F6FB5`, completed bars `#70AD47`, the rest `#DDE4ED`.
- `PageStepBar(…, compact: true, chip:)` already does this for D1; reuse it.

### 2. Section header (shared by all four bands)

- **Number:** two-digit `01`…`04`, 24 / 24 pt, weight 800, `#1F6FB5`, tracking −0.5, tabular figures.
- **Divider:** 1 × 18 pt, `#D6E0EC`, gap 8.
- **Title:** 16 pt bold navy.
- **Trailing chip:** `✓ 3/3` (11 pt bold capsule, green as above); when incomplete it shows `n/m` in orange.

This replaces `A1Card`'s title row on compact width only.

### 3. Fields (shared)

**Label.**
- 14 / 18 pt, semibold, navy.
- Red `*` (`#D9453B`) when the field is required.
- Optional aside at the trailing edge, 12 pt `#7A8BA3` (`ไม่บังคับ`, `จากการตั้งค่า`).
- Gap of 5 between the label and its control.

**Input box.**
- Min height 44, padding 0 / 12, radius 10.
- 1 pt `rgba(22,50,92,0.35)` stroke, white fill, 16 pt navy text.
- **Pre-filled fields** (`InfoPageWide.prefilled`) use the mint fill `rgba(158,230,214,0.3)`. The board shows it on project name, capacity, station address, coordinator and phone.
- Placeholders are `#7A8BA3`.
- Use the existing `inputBox(…, minHeight: 44, trailing: 12)` rather than new styling.

**Two-up rows:** `RatioRow` with gap 10.

### 4. Band `01 โครงการ`

- `ชื่อโครงการ / สถานี *`: full width, one line, truncates.
- One row:
  - `ขนาดติดตั้ง *`: value `120` semibold, unit `kWp` 14 pt `#7A8BA3` at the trailing edge
  - `อินเทอร์เน็ต *`: segmented `มี` / `ไม่มี`. Track `#EEF2F7`, padding 3, radius 10. The selected item is white with a shadow `0 1 3 rgba(22,50,92,.2)` and bold navy text; the other item is `#5B6B82`, 15 pt.

### 5. Band `02 ที่ตั้ง`

This band **moves from first place to second**.

**Map** (`states/02a`):
- 170 pt high, radius 12, 1 pt `#DDE4ED` border.
- Reuse the existing `SiteMapPreview(gps:zoom:)` from `locationBox`, bound to `job.values["mapZoom"]`, not the SVG stand-in.
- Overlays, each 8 pt from the edges:
  - **Top left, zoom presets:** a white 95% pill (radius 9, padding 2, shadow) with `พื้นที่ 500 ม.` · `สถานี 200 ม.` · `อาคาร 50 ม.`. Each item is 28 high, 12 pt, with the distance at 11 pt. The selected item has a mint `#9EE6D6` fill and bold text. Map these to the existing `mapZoom` presets that the report uses.
  - **Top right, zoom buttons:** stacked `+` / `−`, 44 × 40 each, 20 pt semibold `#1F6FB5`, on a white 95% tile (radius 10, separator between them).
  - **Bottom left, hint:** `ลากหมุดเพื่อปรับ · ระดับซูมนี้ใช้ในรายงาน`, 11 pt on a white 92% label.
  - **Bottom right:** scale bar `50 ม.`, 10.5 pt.
  - **Red pin** at the GPS point. Dragging it updates the coordinate (existing behaviour, if present).

**`พิกัด Google Map *`:**
- Input showing `17.0062, 99.8235`, plus a **44 × 44 square button** with the GPS-locate icon (`ui-gps-locate`) that calls the existing `locate()`.
- Keep `gpsNote` / accuracy text under the field when it applies.

**`ที่อยู่สถานี / สถานที่ติดตั้ง *`:** full width.

**`ที่อยู่สำนักงาน / สาขา`** (aside `ไม่บังคับ`):
- Placeholder `เหมือนที่อยู่สถานี`.
- Trailing text button `คัดลอก` (14 pt bold `#1F6FB5`, 44 pt hit height) that copies `address` into `officeAddress`. The field is `Schema.info` `officeAddress`, which is optional.

### 6. Band `03 ผู้ประสานงาน`

One row:
- `ชื่อ *`
- `เบอร์โทร *`: shows `081-234-5678` with a 16 pt phone icon at the trailing edge, `#1F6FB5`. Tapping the icon calls the number (`tel:`); the field stays editable with `.phonePad`.

### 7. Band `04 เอกสาร`

- **First row**, columns `1fr` and `72 pt`:
  - `เลขที่ *`
  - `REV.`
- **Second row**, two columns:
  - `วันที่สำรวจ *`: `29/9/2569` with a 16 pt calendar icon. Keep the existing `dateInput` popover / graphical picker.
  - `วิศวกรผู้สำรวจ` (aside `จากการตั้งค่า`): **read-only**. Fill `#EEF2F7`, 1 pt `#DDE4ED` border, text `#5B6B82`, 15 pt lock icon `#7A8BA3` at the trailing edge. VoiceOver: `วิศวกรผู้สำรวจ สมชาย ใจดี · ดึงจากการตั้งค่า แก้ไขไม่ได้`. The value comes from Settings, as `engineerInput` does today.

### 8. Areas box

The board has no band for the installation-area counts (`areasBox`). **Do not drop it**: keep it as the last band, styled as above with number `05` (see open question 1).

### 9. Bottom bar (`states/01c`, `04a`–`06a`)

This is the shared phone bar (`InfoPageBar.phoneBar` / `BottomBar`), which is already compact:
- padding 8 / 24 / 12, gap 12
- buttons 53 high, radius 10

**`บันทึก` button** (left):
- Fixed width **104 pt**, outlined (1 pt `rgba(22,50,92,0.6)`), 15 pt semibold, one line.
- States:
  - idle: `บันทึก`
  - saving: 16 pt spinner + `บันทึก`
  - just saved (about 1.35 s): green fill `#F3F9EE`, border `#70AD47`, white check on a green circle, `บันทึกแล้ว` in `#3B7420`
  - idle after saving: white with a 2 pt `#70AD47` border, green check + `บันทึกแล้ว`
- Editing any field returns the button to idle.
- VoiceOver:
  - unsaved edits: `บันทึกแบบร่าง · มีการแก้ไขที่ยังไม่ได้บันทึก`
  - saving: `กำลังบันทึก`
  - saved: `บันทึกล่าสุดแล้ว · ยังไม่มีการแก้ไขใหม่`

**Nav buttons:**
- `‹` and `›` fill the remaining width equally (min 72 each) and show icons only.
- `‹` is disabled on A1 (grey `rgba(142,142,147,0.4)`, VoiceOver `ก่อนหน้า (ขั้นแรก)`).
- `›`: VoiceOver `ถัดไป A2 ภาพสถานที่`.

The 104-pt save button now applies to **every** iPhone step page. If `BottomBar` still stretches `บันทึก`, change it once there.

## Rules

- Thai text exactly as in the previews.
- Colours come from `Theme` / `Home`; no new hex literals in views. Add any missing tokens with dark-mode values.
- `.sarabun` fonts as elsewhere.
- Touch targets ≥ 44 pt.
- **Layout only:**
  - every field keeps its `Schema.info` id, label and storage, so Excel / PDF export and completion counts are unchanged
  - no model or sync changes
- Work on a new branch `feat/iphone-a1`.

## Open questions

Decide sensibly and list your choice in the summary:

1. **Areas box.** The board omits it. The default is to keep it as band `05`.
2. **Header buttons.** The board header shows only title and subtitle. The default is to keep the back / sidebar buttons that `InfoPageHeader` shows on iPhone today.
3. **`คัดลอก` button.** Hide it once `officeAddress` already has text, or keep it visible and let it overwrite. The default is to hide it when the field is not empty.

## Done when

- `xcodebuild` builds the app and TCRoofKit, and the existing tests pass.
- On an iPhone 16 simulator, A1 matches `states/01-screen.png` (first screen) and `states/02-full-length.png` (scrolled).
  - Use `-surveyDemoSection YES` (opens A1) if it helps.
  - Measure in the PDFs.
- `อินเทอร์เน็ต` toggles (`states/03`), and the save button runs through `states/04`–`06`.
- iPad A1 is unchanged in landscape and portrait (check an iPad Pro 13" screenshot).
- Write a summary of the files changed, the open-question choices and any remaining differences from the board.
