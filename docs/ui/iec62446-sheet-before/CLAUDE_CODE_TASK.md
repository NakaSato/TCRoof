# Task: IEC 62446 · 5 "IEC Test ก่อนออนระบบ" sheet preview (INV nn-ก่อน, iPad)

Board: `IECTest.dc.html` (2371 × 1439, the sheet at the original's proportions). States: `states/*.png`. Assets: `assets/iec/` (the PWA and PEA logos, the same images as the template's `xl/media`).
Board props: `sheet` = `INV 01-ก่อน | INV 02-ก่อน` (and the `-หลัง` sheets, see Scope), `source` = `แสดงที่มาจาก iPad | ซ่อน (ตามต้นฉบับ)`.

Branch: this hand-off lives on `design/iec62446-sheet-before` (cut from `feat/ipad-home-v3` 553bca6).
Work on `feat/iec62446-sheet-before` cut from it, and push it. Do not merge.

## What it is

A **read-only preview of the exported Excel sheet `INV nn-ก่อน`** inside the app, drawn like the customer's form `1FORMI1.XLS`, filled with the station's test values.
With `แสดงที่มา` on, every cell the app fills is tinted with the colour of the wizard step that fills it, and a legend under the sheet links each colour to its step.
It lets the tester check the sheet before exporting, and jump from a wrong or missing cell to the step that fills it.

## Scope: only this

- The before sheets `INV 01-ก่อน`, `INV 02-ก่อน`, … (one per inverter).
- Build it so the after sheets can use the same view later (board `IECTestAfter.dc.html`, "5b", is a separate hand-off); don't style or check them now.
- iPad (regular width). On iPhone, leave it unreachable.
- Do not change `IECExcel`'s output, the template, the cell map, or stored fields.

## Data: one source of truth with the export

- Factor the value of every cell out of `IECExcel` into a pure function, e.g. `IECExcel.cells(for: IECReport, sheet:) -> [CellRef: CellValue]`, used by BOTH the writer and the preview.
  `IECExcelTests` must still give back the original workbook byte for byte.
- Layout comes from the **template itself** (`Resources/iec62446_template.xlsx`): column widths, row heights, merges, fills, borders, fonts and alignment from the sheet XML and `styles.xml`, print area `A1:AB35`.
  Reuse `SheetXML` / `Workbook` parsing; put the layout model in `ExcelExport` (no UI).
  Check the geometry against `states/02-inv01-before-original.png`.
- Logos: the template's `xl/media` images at the top right (C1:Z2 title, AA–AB logos).
- Wingdings `P` in row 12 shows as ✓ (as the board).
- Formula cells (AA9 `=SUM(E9:X9)*$AA$4`, the linked C3 / E29 / E30 / AA30 on INV 02+) show their cached values, as the exporter refreshes them.

## Source colours (`แสดงที่มา`)

| Step (legend) | Tint / inner border | Cells on `INV nn-ก่อน` |
|---|---|---|
| ① ตั้งค่าระบบ | `#EEF2F7` / `#7D8FA8` | C3 · E5 · O5 · AA4 · rows 8–9 (E..X) · E29 · E30 · AA30 |
| ② ก่อนออน · แรงดัน / กระแส | `#FFF1DC` / `#F08C00` | row 12 polarity · row 16 Voc · row 18 current |
| ③ ก่อนออน · ฉนวน (IR) | `#EFE8FB` / `#7B5CC4` | row 13 test V · E14 (E14:X15 IR summary) |
| ④ หลังออน · แรงดัน / กระแส | `#E4F3E6` / `#2E9E5B` | E21 (after inverter testing) |
| ⑤ พลังงานและ PR | `#E1F2F5` / `#1B8A9E` | (after sheets only: rows 22–26, AA25, AA26) |

- Only used string columns are tinted; an empty slot's column stays white (as the board: INV 02 columns F, H, J, L).
- Cells the overview fills (E11 continuity, E20 inverter testing before) and the constant labels stay untinted.
- Put this mapping in `TCRoofCore` (`IECReport+SheetSources`, by row/cell → step), with a test.
- `ซ่อน (ตามต้นฉบับ)` draws the sheet exactly as exported (state 02).

## UI

1. **Entry points:** a `ดูชีต Excel` button on step 7 `ตรวจและส่งออก` (next to the Excel export) and on the IEC overview. It opens a full-screen page.
2. **Page:** top bar with back, title `ชีต INV 01-ก่อน · ตามฟอร์ม 1FORMI1`, a sheet picker (segmented or menu: `INV 01-ก่อน`, `INV 02-ก่อน`, …), and a `แสดงที่มา` toggle (on by default).
   The sheet fits the width; pinch to zoom up to 3×, pan when zoomed; double-tap toggles fit / 2×.
3. **Legend** under the sheet (board's dashed card): `ค่าที่มาจากแอป iPad · IEC 62446` and the 5 swatches with step names; right note `ไม่พิมพ์ลงไฟล์ Excel`. Each swatch opens its step.
4. **Tap a tinted cell:** opens that step's page at that inverter (and string, for a column cell). Steps not built as pages yet open the existing screen (setup sheet, string table before / after, performance); report what each tap opens.
5. **Missing values:** a tinted input cell with no value gets a dashed red inner border (not on the board; keep it subtle) so gaps are visible. Hidden when `แสดงที่มา` is off.
6. Draw with `Canvas` / vector shapes from the layout model (no web view, no bitmap of the sheet). Text in the sheet's own font sizes, scaled; use Sarabun for Thai if the template font isn't available, and report it.

## DEBUG

`-iecSheet INV01-before|INV02-before` opens the page on the sample (`-iecDemo YES`), `-iecSheetSource off` hides the sources. One line in CLAUDE.md.

## Tests (`swift test`)

- `IECExcel.cells(for:sheet:)` for the sample equals the original's values cell by cell (`cell-inventory.json` inputs); the exported workbook is unchanged.
- layout: column widths / row heights / merges of `INV 01-ก่อน` parsed from the template (spot-check C1:Z2, E5:N5, O5:X5, E11:X11, E14:X15, A4:A?…).
- source map: rows 12 / 16 / 18 → step 2, row 13 + E14 → 3, E21 → 4, setup cells → 1; empty slots untinted.

## Check list

- [ ] Build with your own `-derivedDataPath`; `swift test` passes (incl. `IECExcelTests`, `IECWordTests`).
- [ ] iPad Pro 13" landscape screenshots: `screenshots/01` (INV 01 with sources), `02` (sources off), `03` (INV 02), compared with `states/`.
- [ ] A tap on a Voc cell opens step 2's entry for that string (or the existing before table at that slot).
- [ ] Export unchanged (byte diff of the sample workbook).

## States

| File | What |
|---|---|
| 01-inv01-before-sources | INV 01-ก่อน, sources on |
| 02-inv01-before-original | sources off: the form as exported |
| 03-inv02-before-sources | INV 02-ก่อน (60 kW, 8 strings in slots 1,3,5,7,9–12; 16- and 12-module strings) |
| 04-legend-crop | the legend card, 2× |

Values are the แพรกหนามแดง sample; never hardcode them.

## Open questions (report)

1. Should the preview also offer `PDF ชีตนี้` (print the drawn sheet, A4 landscape) for sending before the Excel is final?
2. Pass / fail columns Y / Z are empty in the original; should the preview (and later the export) tick them from the rules?
3. Tapping a cell of a closed (locked) test: open the step read-only, or ask to `แก้ไข` first?
