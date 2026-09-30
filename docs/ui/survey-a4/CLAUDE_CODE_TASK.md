# Claude Code task: A4 Flood history (น้ำท่วม) page for iPad, new design

> How to use: open Claude Code in the `TCRoof` repo folder and type
> `Follow docs/ui/survey-a4/CLAUDE_CODE_TASK.md`

UI text stays in Thai exactly as shown in the previews. This document is in English; Thai strings in `backticks` are the literal labels to use.

## Goal
A4 is currently drawn from `Schema.flood` through `groupPage` (`JobEditor+Detail.swift`, `case .flood`) as a vertical list of fields, plus a blue hint label from `Schema.recommendedEquipHeight`.

Build a dedicated A4 layout for iPad landscape, matching the previews, in the same way the A1/A2/A3 wide pages were done (`InfoPageWide`, `SitePageWide`, the A3 wide page). Name it `FloodPageWide`.
- Left column: a live **water-level cross-section drawing**, an **equipment height check** table, and flood evidence photos.
- Right column: the flood questions, a GISTDA lookup card when the answer is "unknown", and notes.
- Everything fits on one screen without scrolling.

The page has three states driven by `floodHistory`:

| State | Preview | Right column shows |
|---|---|---|
| `เคย` (flooded) | `preview.png` | full detail form |
| `ไม่ทราบ` (unknown), not fetched | `preview-unknown.png` | GISTDA card with a fetch button; the drawing has an overlay with the same button |
| `ไม่ทราบ`, fetched | `preview-gistda.png` | GISTDA result table; the drawing shows an estimated water line (dashed) |
| `ไม่เคย` (never) | `preview-never.png` | green note `ไม่เคยท่วม · ข้ามรายละเอียดได้` / `ระดับติดตั้งอุปกรณ์ใช้แค่ระยะเผื่อจากพื้น` |

References:
- `preview*.png`: 1366 × 1024 screenshots of each state
- `preview.html`: opens in a browser (flooded state)
- `iPadA4.dc.html`: the design source. Its `<script type="text/x-dc">` block contains the reference logic for the drawing coordinates and the check table (`renderVals`). Read it for the formulas.

## Relevant files
- `TCRoofKit/Sources/TCRoofCore/Schema.swift`: `flood`, `flooded`, `floodSources`, `floodHits`, `recommendedEquipHeight`
- `TCRoofKit/Sources/SurveyUI/JobEditor+Detail.swift`: `groupPage` for `.flood` and the recommended-height label
- `TCRoofKit/Sources/SurveyUI/JobEditor.swift`: page selection for wide layouts
- `TCRoofKit/Sources/TCRoofCore/Progress.swift`, `Validation.swift`: A4 completion / missing items
- `TCRoofKit/Sources/PDFReport/ReportLayout.swift`: `flood()` (~line 407) and the summary row `ประวัติน้ำท่วม` (~line 295)
- `TCRoofKit/Sources/TCRoofCore/PhotoFolders.swift`: `A4 ประวัติน้ำท่วม`
- `TCRoofKit/Sources/TCRoofCore/Validation.swift`: `gps` parsing (`lat, lon`) — used for the GISTDA lookup
- `TCRoofKit/Sources/TCRoofCore/SiteMarks.swift`: A2 image marks (affected points are shown on the A2 image)

Use code-review-graph per `CLAUDE.md` to find callers of `Schema.flood`, `flooded`, `floodHistory`, `floodDepth`, `recommendedEquipHeight` before editing.

## Layout (iPad landscape, content width 1318)
Left column ~560 pt, right column fills the rest, gap 28. Bottom bar as on the other pages.

### Left column
1. **Card `ภาพตัดระดับน้ำ`** with caption `อัปเดตตามข้อมูลด้านขวา · ใช้ในรายงาน PDF`
   - A vector cross-section (SwiftUI `Canvas` or `Path`), scale 1.8 pt per cm, ground line at the bottom with a hatched soil band.
   - Elements, left to right:
     - `MDB 1 (เดิม)`: tall existing cabinet standing on the ground (±0.00).
     - `ห้อง Inverter (B2)`: building outline on a raised floor slab (dotted fill) labelled `พื้นห้อง +0.30`; inside it `INV` and `SMDB` boxes mounted at floor + mounting height.
     - Water body: blue fill from the ground up to the flood level with the marker `▽ +0.80 น้ำสูงสุด ปี 2554`. Solid line when flooded; dashed and labelled `+0.50 ระดับน้ำประเมิน (GISTDA)` when estimated; hidden when never flooded or unknown and not fetched.
     - Minimum install level: dash-dot green line across the drawing with `▽ +1.30 ระดับติดตั้งต่ำสุด`, and a vertical dimension `ระยะเผื่อ 50` between the water line and this line.
     - Dimension chain on the right: floor height (30) and mounting height (100).
     - Datum `▽ ±0.00 ดินเดิม`, footnote `หน่วย: ซม. (ระดับเป็นเมตร)`.
   - Flooded state only: a pill `⇕ ลากเส้นน้ำเพื่อปรับระดับ` on the water line. Dragging the water line vertically changes `floodDepth` in 10 cm steps and updates everything live.
   - Unknown, not fetched: centered overlay card `ยังไม่มีข้อมูลระดับน้ำ` / `ดึงประวัติน้ำท่วมจาก GISTDA ตามพิกัด A1` / button `ดึงข้อมูลจาก GISTDA`.
   - Unknown, fetched: orange-outlined banner at the top `GISTDA · จุดติดตั้งไม่อยู่ในพื้นที่ท่วมซ้ำซาก · ความลึกเป็นค่าประเมิน` (text from the result).
   - Provide an accessibility label equivalent to the design's `chartAria`.
2. **`ตรวจความสูงอุปกรณ์`** table under the drawing, subtitle `ต้อง ≥ {minCm} ซม. จาก{reference}`
   - Row format: name · source section tag (grey, e.g. `B2`) · height · status pill.
   - Rows:
     - `พื้นห้อง Inverter` (B2): floor height; pill `✓ สูงกว่าน้ำ` (green) or `! ต่ำกว่าน้ำ N ซม.` (orange) when floor < water level
     - `อินเวอร์เตอร์ × n` (B2), `ตู้ SMDB-PV · รีเลย์กันย้อน` (B4): floor + mounting height
     - `ปุ่ม Emergency` (B5): its own mounting height
     - pass: `✓ ผ่าน` (green); fail: `✗ ต่ำกว่า N ซม.` (red)
     - Only when there is a water level: `MDP-1 จุดเชื่อมต่อ (เดิม)` (A3 main board name), height `ฐาน 0 ซม.`, orange pill `! น้ำเคยเข้า 80 ซม.` (flooded) or `! ใกล้พื้นที่ท่วมซ้ำซาก` (estimated)
   - Rows for sections that don't exist in the job are omitted. Inverter count comes from the inverter sections.
3. **`ภาพคราบระดับน้ำ / หลักฐานน้ำท่วม`** (right aside `ไม่บังคับ · แนะนำถ่ายคู่ตลับเมตร`): photo thumbnails with a remove (×) button, then `อัปโหลด` and `กล้อง` buttons. Multiple photos are allowed (see data changes).

### Right column
1. `พื้นที่เคยมีน้ำท่วมหรือไม่ *`: three large choice buttons `ไม่เคย` / `เคย` / `ไม่ทราบ`.
2. **Flooded** (`เคย`):
   - Row: `ปีล่าสุด (พ.ศ.) *` → `floodYear`, `ระดับน้ำสูงสุด *` (ซม.) → `floodDepth`, `ท่วมขัง` (วัน) → `floodDays`
   - `วัดความสูงจาก *`: `ดินเดิม` / `พื้นถนน` / `พื้นห้อง MDB` → new `floodRef`
   - `ที่มาข้อมูล *` with a link `แผนที่ GISTDA ↗` (opens https://flood.gistda.or.th in Safari): `เจ้าหน้าที่` / `คราบน้ำ` / `GISTDA` → new `floodInfoSource`
   - `ความถี่`: `ทุกปี` / `2–5 ปีครั้ง` / `นานกว่า 5 ปี` → `floodFreq`
   - `สาเหตุ` (aside `เลือกได้ 1`): chips from `floodSources` → `floodSource` (keep the existing `อื่นๆ` + other text)
   - `จุดที่เคยได้รับผลกระทบ` (aside `แสดงบนภาพ A2`): checkboxes from `floodHits` in 3 columns → `floodHit`
3. **Unknown** (`ไม่ทราบ`): card `ข้อมูลน้ำท่วมจาก GISTDA`, right aside `ตามพิกัด A1 · {lat}, {lon}`
   - Not fetched: text `ยังไม่มีข้อมูลจากหน้างาน ดึงประวัติพื้นที่น้ำท่วมซ้ำซากจากภาพดาวเทียม GISTDA ได้ทันที` + button `ดึงข้อมูลจาก GISTDA`
   - Fetched: label/value rows
     - `จุดติดตั้ง` (green when outside a repeat-flood area)
     - `พื้นที่ท่วมใกล้สุด` (distance · times · years)
     - `รัศมี 1 กม.` (plots · max times · years, orange)
     - `30 วันล่าสุด` (nearest recent flood from satellite images and the image date range)
     - `ความลึกน้ำ` (red: `ไม่มีในข้อมูลดาวเทียม · ใช้ค่าประเมิน 50 ซม.`)
     - small footnote: API endpoints used · sub-district/district/province · fetch timestamp · `ควรยืนยันความลึกกับเจ้าหน้าที่สถานี`
4. **Never** (`ไม่เคย`): green note card (see table above).
5. `หมายเหตุ` → `floodNote`, multi-line, fills the remaining height. Shown in every state.

### Bottom bar
- Left: ✓ `บันทึกอัตโนมัติ HH:mm` and a status line:
  - all equipment passes: `ครบช่องบังคับแล้ว · อุปกรณ์ใหม่ผ่านเกณฑ์ ≥ {minCm} ซม.`
  - any fail: `อุปกรณ์ต่ำกว่าเกณฑ์ N รายการ` in red
  - suffix: flooded `· จุดต่อ MDP-1 เคยน้ำท่วม`; unknown fetched `· ระดับน้ำจาก GISTDA เป็นค่าประเมิน`; unknown not fetched `· ยังไม่มีข้อมูลน้ำท่วม ดึงจาก GISTDA ได้`
- Right: `บันทึกร่างตอนนี้` · `‹ ก่อนหน้า 3/13 A3 หม้อแปลง · MDB` · `ถัดไป 5/13 B1 ตู้ไฟฟ้าอาคาร ›`

## Calculation (from the design logic)
- `level` = `floodDepth` when flooded; the GISTDA estimated depth (50 cm when the service has no depth) when unknown and fetched; otherwise 0.
- `freeboard` = 50 cm (keep the existing rule in `recommendedEquipHeight`).
- `minCm = ceil((level + freeboard) / 10) × 10`. When never flooded, `minCm` = freeboard from the reference level.
- Update `recommendedEquipHeight` to use this rule for the flooded and estimated cases. Keep its signature and keep writing/deriving `equipHeight` as before.
- Floor height, mounting heights and inverter count must come from the B-sections when those fields exist. They don't exist today, so add optional fields (see below) with defaults: floor 0, inverter/SMDB mounting 100 cm, emergency button 140 cm. The design's values 30 / 100 / 140 are examples.

## GISTDA lookup
- Coordinates come from A1 `gps` (`Validation` parser). Disable the button with a hint when `gps` is empty or invalid.
- Implement a small `FloodLookup` client (in `TCRoofCore` or `SurveyUI`) calling the GISTDA flood API: repeat-flood frequency at and around the point (1 km radius) and floods in the last 30 days.
- **The API key must not be committed.** Read it at runtime from a git-ignored config (e.g. a `Secrets.xcconfig` → Info.plist key, or the app Settings screen). Add the ignore rule and a `Secrets.example.xcconfig` with an empty value. If no key is configured, show `ยังไม่ได้ตั้งค่า GISTDA API key` instead of calling.
- Handle offline / timeout / error with a retry message. Never block saving.
- Store the fetched result in the job (see data changes) so it shows again offline and prints in the PDF.

## Data changes (do not rename existing ids)
Keep and reuse: `floodHistory`, `floodYear`, `floodDepth`, `floodDays`, `floodFreq`, `floodSource`, `floodHit`, `floodPhoto`, `equipHeight`, `floodNote`.

- `floodHistory` options: add `ไม่ทราบ` after `ไม่เคย`, `เคย`. Existing jobs keep their answers. `flooded()` stays `== "เคย"`.
- New fields, all optional, so A4 completion counts as before:
  - `floodRef`: `ดินเดิม` / `พื้นถนน` / `พื้นห้อง MDB`
  - `floodInfoSource`: `เจ้าหน้าที่` / `คราบน้ำ` / `GISTDA`
  - `floodPhotos`: extra evidence photos (`.photos`). Keep `floodPhoto` as the first photo so old jobs and the PDF still work.
  - `floodGistda`: the stored lookup result (JSON text or a small Codable value): point status, nearest-flood distance/times/years, 1 km plots/max times/years, 30-day finding and date range, estimated depth, place name, fetched-at timestamp
  - `invFloorCm`, `invMountCm`, `emgMountCm`: optional numbers. Put them on the inverter / FTS sections if that fits `ModuleSpec`; otherwise put them in A4 and note it in the summary.
- The A4 completion rule for `ไม่ทราบ`: completion is met by the choice alone, as for `ไม่เคย`.

## PDF / Excel
- `flood()`: the `พื้นที่เคยมีน้ำท่วมหรือไม่` checkbox row must list all three options.
- Add the cross-section drawing to the PDF flood unit (vector, same drawing code or a shared geometry function), followed by the equipment height check table.
- When `floodGistda` exists, print its rows under the flood table with the source footnote.
- Summary row `ประวัติน้ำท่วม` (~line 295) must handle `ไม่ทราบ` (e.g. `ไม่ทราบ · GISTDA: ไม่อยู่ในพื้นที่ท่วมซ้ำซาก`).
- Excel doesn't use flood fields today. Do not change the Excel layout.

## Constraints
- Do not change existing field ids / labels in `Schema` or the Excel format.
- Old job JSON must still decode (no `floodRef`, `floodGistda`, etc.).
- iPad portrait and iPhone (compact) keep using `groupPage`.
- Every button and input is at least 44 pt tall.
- Values in the previews (NO.224, 2554, 80 cm, 7 days, 17.0062, 99.8235, ต.ยางซ้าย อ.เมืองสุโขทัย จ.สุโขทัย, 550 m, 54 plots, the note text, 30 / 100 / 140 cm) are examples. Do not hardcode them.

## Check before finishing
1. Build passes and `swift test` passes. Add tests for:
   - `minCm` for flooded (80 → 130), estimated (50 → 100), never (→ 50)
   - old JSON without new fields decodes, and `floodHistory = ไม่ทราบ` counts as complete
   - `FloodLookup` result parsing from a fixture JSON (no network in tests)
2. Run the iPad simulator in landscape at 1366 × 1024 and compare each state with its preview.
3. Try the flow:
   - `เคย` → type depth → drag the water line → the check table and the bottom status update
   - `ไม่ทราบ` → fetch from GISTDA (with and without a key, and offline) → result is shown and kept after reopening the job
   - `ไม่เคย` → detail fields hide, the note stays
   - Export PDF and check the drawing, the table and the GISTDA rows.
4. Summarize the changed files and anything left open.
