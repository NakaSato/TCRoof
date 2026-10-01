# Claude Code task: A1 ข้อมูลโครงการ (iPad) — finish the latest design

> How to use: open Claude Code in the `TCRoof` repo folder and type
> `Follow docs/ui/survey-a1/CLAUDE_CODE_TASK.md`
>
> This replaces the earlier Thai task (29–30/9). The A1 wide page (`InfoPageWide`) already exists; this task closes the gaps to the 30/9 design and adds the icons. Full detail: [`SPEC.md`](SPEC.md).

UI text stays in Thai exactly as in `preview.png`. Thai strings in `backticks` are the literal labels.

## Goal
Bring `InfoPageWide` in line with `preview.png`:
1. **Swap the columns:** location card on the left (~620 pt), document / project / coordinator / areas on the right, gap 28.
2. **Report crop frame** on the map, stored as `mapCrop` (SPEC §3): move and resize with 44 pt corner handles, minimum 12 %, stays inside the map. Label `ภาพในรายงาน · {W} × {H} ม.`, hint text and `รีเซ็ตกรอบ`. PDF and Excel map images use only the crop.
3. **Install areas:** only หลังคา and ถังน้ำใส. Remove the พื้นดิน tile, but keep decoding and backing up `groundAreas`.
4. **Engineer field:** remove the `ผู้ใช้เครื่องนี้` tag.
5. **Bottom bar:** `บันทึกอัตโนมัติ HH:mm`, without the word แล้ว.
6. **Icons:** copy `icons/A1Icons.xcassets` into `TCRoofKit/Sources/SurveyUI/Resources/` and use the icons per SPEC §7.

References in this folder: `preview.png`, `preview.html`, `iPadA1.dc.html` (crop logic in `dragStart`), `SPEC.md`, `icons/`.

## Relevant files
- `TCRoofKit/Sources/SurveyUI/InfoPageWide.swift` (`body` column order, `engineerInput`, `groundKey`)
- `TCRoofKit/Sources/SurveyUI/InfoPageWide+Sections.swift` (areas tiles ~line 17, location box, bottom bar ~line 268)
- `TCRoofKit/Sources/SurveyUI/MapImage.swift` (`fetch`, `metersAcross`)
- `TCRoofKit/Sources/TCRoofCore/WebBackup.swift` (`extraJobKeys`: add `mapCrop`)
- `TCRoofKit/Sources/PDFReport/ReportLayout+Cover.swift`, `TCRoofKit/Sources/ExcelExport/ExcelExporter.swift` (map image)

Use code-review-graph per `CLAUDE.md` to find callers of `groundAreas` / `groundKey`, `MapImage` and `mapZoom` before editing.

## Constraints
- Do not change field ids / labels in `Schema.info` or the Excel layout. A1 completion counts as before.
- Old jobs without `mapCrop` use the whole map image. Jobs with `groundAreas` still open and round-trip.
- iPad portrait / iPhone: one column. Order: location, document, project, coordinator, areas.
- Every control is at least 44 pt.
- Values in the preview are examples. Do not hardcode them. Examples: 224, 00, 29/9/2569, สมชาย, the project name, 120 kWp, the coordinator, the phone number, 17.0062, 99.8235, the address, `108 × 69 ม.`.

## Check before finishing
1. Build passes and `swift test` passes, with the tests in SPEC §6.
2. Run the iPad simulator in landscape at 1366 × 1024 and compare with `preview.png`.
3. Try the flow:
   - move and resize the crop at each zoom level; reset it
   - export PDF and Excel, and check the cropped map
   - open an old job that has `groundAreas`
4. Summarize the changed files and the open questions in SPEC §8.
