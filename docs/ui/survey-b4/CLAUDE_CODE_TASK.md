# Claude Code task: B4 Zero export (ระบบกันย้อน), wide page (iPad)

> How to use: open Claude Code in the `TCRoof` repo and type
> `Follow docs/ui/survey-b4/CLAUDE_CODE_TASK.md`

This document is in English. Thai strings in `backticks` are the literal UI labels.

## Goal
B4 (`ModuleType.backfeed`, `ระบบกันย้อน`) is still drawn by the generic `groupPage`. Give it a designed wide page for iPad landscape, `BackfeedPageWide`, built the same way as `InverterPageWide` (B2) and `FtsPageWide` (B5). The whole page fits on one screen at 1366 × 1024.

| File | Shows |
|---|---|
| `preview.png` | default: LV selected, 2 of 4 photos, `ยังขาด` in the bottom bar |
| `states/01-lv-missing-photos.png` | same as preview |
| `states/02-lv-complete.png` | LV, all 4 photos: green ✓ `ครบช่องบังคับแล้ว · SLD และ B2 อัปเดตตามตำแหน่งกันย้อน` |
| `states/03-hv-missing-photos.png` | HV selected: the `เสา` row appears, the photo labels switch to HV, and the SLD crop switches to the 22 kV side |
| `states/04-hv-complete-old-pole.png` | HV, `เสาเดิม`, all 4 photos |
| `preview.html` | static render (uses `grf.css` next to it) |
| `iPadB4.dc.html` | design source: markup and `renderVals()` |
| `icons/` | every vector on the page (see `icons/README.md`) |

Use code-review-graph first, as `CLAUDE.md` says. Find every reader of:
- `ModuleType.backfeed`, `values["level"]`, `values["pole"]`, `photoArea`, `photoDetail`
- `SingleLine` (`hvOverride`, `b4?.values.choice("level")`), `SingleLineLayout` (the LV and HV relay/CT drawing), `SingleLinePage` (the B4 toggle there)
- `InverterPageWide+Plan.zeroExportLevels` (the B2 card)
- `SiteMarks` `.zeroExport`, `MapImage` / `SiteMapPreview`
- `Progress` (`case .backfeed`)
- the PDF section (`ReportLayout+Sections`, `checks(["กันย้อนที่แรงต่ำ", …])`) and the Excel radio (`ExcelExporter` row `h + 28`)

Read the source before editing.

## Product change in this design (owner's board)
The board asks for **at least 4 photos**, with labels that depend on the level. Today the schema has `photoArea` (required) and `photoDetail` (optional). Do this:

| Slot | Field | LV label | HV label |
|---|---|---|---|
| 1 | `photoArea` (existing) | `ตู้ MDP-1 · วงจุดติดตั้ง CT` | `เสาหลังมิเตอร์ · จุด CT/VT` |
| 2 | `photoDetail` (existing) | `ช่องว่างสำหรับรีเลย์` | `ระยะห่างสายแรงสูง` |
| 3 | `photoRating` (new) | `ป้ายพิกัด ACB เมน / CT เดิม` | `ป้ายมิเตอร์ กฟภ. / CT-VT เดิม` |
| 4 | `photoAccess` (new) | `บัสบาร์ขาออก ACB · วัดขนาดสำหรับ CT` | `ทางเข้ารถกระเช้า · พื้นที่ทำงาน` |

- In the LV labels, `MDP-1` is the A3 main panel name (`SingleLine` already resolves it). Use the real name. Use the real meter number and kV the same way.
- **Schema.** Add `photoRating` and `photoAccess` to `.backfeed` with generic schema labels: `ภาพป้ายพิกัดอุปกรณ์เดิม` and `ภาพพื้นที่ทำงาน / ขนาดบัสบาร์`. Keep `photoDetail`'s id.
- **Required photos.** All 4 slots are required on the wide page.
  - For old jobs, keep `photoDetail` `optional: true` in the schema and count the 4-photo rule only in the wide page's `missing` list and `Progress`, so old saved jobs don't fail to decode.
  - Old jobs with only 1–2 photos will show `ยังขาด` until the new photos are added. That is intended; call it out in your summary.
- **PDF and Excel.** Add the two new photos to the PDF page `ภาพตำแหน่งติดตั้งระบบกันย้อน` after the existing ones. Don't add Excel cells unless the workbook already has free photo slots there; if not, say so in the summary.

## Layout (landscape)
- **Header:** the standard survey header (`B4 ระบบกันย้อน` + document line) and the progress bar (`8/13 · ตำแหน่งติดตั้งระบบกันย้อน`).
- **Body:** two columns. Left 560 pt; right flexible, gap 20. Cards are white, radius 16, hairline border, soft shadow (same as B2/B5).
- **Bottom bar:**
  - Status line: an orange `!` with `ยังขาด: ภาพประกอบอีก n ภาพ (ต้องมีอย่างน้อย 4 ภาพ)`, or a green ✓ with `ครบช่องบังคับแล้ว · SLD และ B2 อัปเดตตามตำแหน่งกันย้อน`.
  - Then `บันทึกร่างตอนนี้`, `ก่อนหน้า 7/13 B3 ระบบน้ำล้างแผง` and `ถัดไป 9/13 B5 ปุ่ม Emergency`.

### Left column
1. **Card `1 ตำแหน่งกันย้อน *`.** Right hint: `ใช้ค่าเดียวกับ B2 และ SLD`.
   - Two option cards, min height 96, radius 14:
     - `LV · 400 V` tag, `กันย้อนที่แรงต่ำ`, sub `CT ที่เมนตู้ <MDP> (400 V)`
     - `HV · 22 kV` tag, `กันย้อนที่แรงสูง`, sub `CT/VT หลังมิเตอร์ กฟภ. (22 kV)`
   - Selected card: background `#E8F7F3`, 2 pt `#27A99A` border with a 3 pt glow, a teal check circle at the top right, and a solid teal tag. Unselected: white with a 1 pt `#C9D3DF` border and a grey tag.
   - Writes `values["level"]` with the existing strings. It is the same value the SLD page and the B2 card already toggle, so all three stay in sync.
   - **HV only:** the row `เสา *` (hint `สำหรับติดตั้ง CT/VT แรงสูง`) with two chips, `เสาเดิม` / `เสาใหม่`. They write `values["pole"]` using the existing `when:` rule. Selected chip: mint `#9EE6D6`.
2. **Card `2 ภาพประกอบ *`.**
   - Right counter: `n/4 ภาพ · ขาดอีก m ภาพ` in red bold, or `n ภาพ · ครบขั้นต่ำ 4 ภาพ ✓` in green.
   - 2 × 2 photo grid; each slot is 128 high, radius 10.
   - **Filled slot:**
     - green check at the top left, × at the top right (clear)
     - the label pill at the bottom left
     - the photo fills the slot
   - **Empty slot:** 2 pt dashed red border, a camera icon, `ถ่ายภาพ / อัปโหลด` and the slot label in muted grey. Tapping opens the existing photo picker (camera/library).
3. **Card `3 รายละเอียดเพิ่มเติม`** (hint `ไม่บังคับ`): a multi-line text field bound to the existing `detail` field. It grows to fill the rest of the column.

### Right column
1. **Card `ส่วนที่เปลี่ยนใน SLD`** (top, full width of the column).
   - Sub: `CT + รีเลย์ที่ตู้ <MDP>` for LV, `CT/VT + รีเลย์หลังมิเตอร์ กฟภ.` for HV.
   - Link `ดู SLD ทั้งหมด →` opens the SLD page.
   - Body: a 330 pt high crop of the real `SingleLineLayout` drawing around the B4 parts (relay box, CT/VT, the dashed control line). Use a view-box crop of the existing renderer; don't redraw.
   - `icons/sld-crop-lv.svg` and `icons/sld-crop-hv.svg` show the intended framing.
2. **Bottom row:** two cards side by side.
   - **`ตำแหน่งบนภาพ A2`** (sub `ภาพจากหน้า A2`, link `เปิด A2 →`):
     - The A2 site image (`MapImage` / `SiteMapPreview`), cropped around the `.zeroExport` site mark, with a caption pill: `ตู้ MDP-1 · ห้องไฟฟ้า อาคารสูบน้ำ` (LV) or `ข้างมิเตอร์ PEA · ริมถนนทางเข้า` (HV).
     - If no mark exists, show the whole image with a hint to place `กันย้อน` on A2.
     - `icons/a2-crop-*.svg` show the framing.
   - **`อุปกรณ์ที่ต้องติดตั้ง`** (sub `ตาม SLD`): a numbered list with 3 rows. Each row has a teal circle number, a bold title and a muted sub.
     - LV:
       1. `CT 3 ตัว`, `ที่เมน ACB <rating> ตู้ <MDP>`
       2. `รีเลย์กันย้อน (Zero export)`, `ในตู้ <MDP>`
       3. `สายสัญญาณควบคุม`, `ไปอินเวอร์เตอร์ <n> เครื่อง (B2)`
     - HV:
       1. `CT/VT แรงสูง 22 kV`, `หลังมิเตอร์ กฟภ.`
       2. `รีเลย์กันย้อนแรงสูง`, `ใช้เสาเดิม` or `ปักเสาใหม่` (from `pole`)
       3. `สายสัญญาณควบคุม`, `ไปอินเวอร์เตอร์ <n> เครื่อง (B2)`
     - Take the ACB rating, the panel name and the inverter count from A3/B2 data. If one is missing, write `?`.

## Rules
- Touch targets ≥ 44 pt. Thai text exactly as above. Names, numbers and photos in the previews are examples.
- In the board's HV SLD crop the relay sub reads `เสาใหม่ (B4)` even when `เสาเดิม` is chosen. That is a static drawing; the real renderer must follow `pole`.
- The board's file `<title>` still says `ขั้น 7`. The correct step is 8/13.
- Don't change field ids, the strings of `level` / `pole`, or other pages beyond what is listed.
- Never put the GISTDA key or any secret into code, fixtures or docs.

## Tests
- `Progress` for `.backfeed`:
  - LV with 2 photos → 2 missing
  - 4 photos → complete
  - HV without `pole` → `pole` missing
- An old job JSON without `photoRating` / `photoAccess` still decodes.
- `swift build`, `swift test`, and the `CLAUDE.md` `xcodebuild` with your own `-derivedDataPath`. Compare the simulator at 1366 × 1024 with `states/*.png`.

## Finish with
A summary listing the files changed, the new fields, how old jobs behave, the PDF/Excel changes, and anything left open (for example, the SLD crop rectangle for each level).
