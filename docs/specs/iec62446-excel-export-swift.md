# IEC 62446 Excel export: fill the original 1FORMI1 workbook in place (Swift spec)

**Status:** Not built.
**Platform:** `TCRoofKit` package. Pure logic in `TCRoofCore` (`IECReport`), the writer in `ExcelExport`
(`IECExcel.swift`), testable with `swift test` on macOS.
**Source file:** `docs/specs/iec62446/1FORMI1.xlsx`, a byte-for-byte copy of the customer's `1FORMI1.XLS`
(สถานีจ่ายน้ำแพรกหนามแดง กปภ.สาขาสมุทรสงคราม, 209.76 kWp). Despite the `.XLS` name it is an **Excel 2007+ package**
(zip + XML), so the existing `ZipArchive` reads it.
**Cell inventory:** `docs/specs/iec62446/cell-inventory.json`, generated from that file: every cell the exporter
touches, with its style `s`, type `t`, kind (`input` / `formula` / `constant`) and the sample value.
**Related:** the iPad screens `iPadIECStep1–7` in the TCRoof design canvas (ก่อนออน · แรงดัน / กระแส, ก่อนออน · ฉนวน
(IR), หลังออน · แรงดัน / กระแส, พลังงานและ PR …); the Project docs `forms/iec62446-pwa/` (README, `form-schema.json`,
`excel-cell-map.json`, `sample-praek-nam-daeng.json`).

**One idea:** the export is **the original workbook with values typed into its input cells, and nothing else
changed**. The PWA's other files and formulas point at this form's sheets and cells, so sheet names, cell
addresses, cell types, styles, formulas and print set-up must stay exactly as in the original. The app never
rebuilds the workbook and never uses the generic `Workbook` class (it renames sheets, renumbers `sheetId`s and
rewrites `definedNames`).

---

## 1. What the original file contains

| Part | Content | Export rule |
|---|---|---|
| `xl/workbook.xml` | 4 sheets in this order: `INV 01-ก่อน` (sheetId 82), `INV 02-ก่อน` (86), `INV 01-หลัง` (89), `INV 02-หลัง` (90); 4 `_xlnm.Print_Area` = `$A$1:$AB$35`; `calcPr calcId="191029"` | unchanged (2 inverters) |
| `xl/worksheets/sheet1–4.xml` | rows 1–687 styled (17,862 `<c>` per sheet), 54 merges, A4 landscape at 42 %, page break at row 122, view = page break preview at 55 % | only the input cells change (§3) |
| `xl/sharedStrings.xml` | 90 unique strings, `count="517"` | append only (§3.3) |
| `xl/calcChain.xml` | 16 formula cells | unchanged |
| `xl/styles.xml`, `theme1.xml` | TH Sarabun New; Wingdings 2 for polarity | unchanged |
| `xl/drawings/drawing1–4.xml` + `media/image1.jpeg`, `image2.png` | กปภ. and กฟภ. logos grouped at Y1:AB3 | unchanged |
| `xl/drawings/vmlDrawing1–4.vml` + `image3.jpeg` | header picture (`legacyDrawingHF`) | unchanged |
| `xl/printerSettings/printerSettings1–4.bin` | printer set-up | unchanged |
| `docProps/*` | core, app (sheet names in `TitlesOfParts`), thumbnail.emf | unchanged (2 inverters) |

### 1.1 Formulas (the only ones in the file)

| Cell | Sheets | Formula | Cached value in the sample |
|---|---|---|---|
| AA9 | all 4 | `SUM(E9:X9)*$AA$4` | 145920 / 63840 (W, though the label says "kWp ติดตั้งของ INV") |
| C3 | INV 02-ก่อน → `'INV 01-ก่อน'!$C$3`; INV 02-หลัง → `'INV 01-หลัง'!$C$3` | link | station line |
| AA25, AA26, E29, E30, AA30 | INV 02-ก่อน / INV 02-หลัง → same cell on INV 01 of the same phase | link | `t="str"` text |

The note in AD8 says it: "แก้ข้อมูลหลัก จากหน้า INV 1 หน้าอื่นๆ link สูตรไปให้แล้ว". Values typed by hand: PR, Yf, kWh,
efficiency (rows 22–26) have **no formula**. Checked against the sample: E24 = E25 ÷ 7 and PR = Yf ÷ 4.24 hold;
Yf ≠ E24 ÷ kWp (INV1 3.13 vs typed 2.93, INV2 3.37 vs 3.33); efficiency ≈ PR × module efficiency (570 W ÷ 2.58 m²).

---

## 2. Data (`TCRoofCore/IECReport.swift`)

Follows `forms/iec62446-pwa/form-schema.json`. One report per station; stored on the job as JSON
(`Job.iecReportJSON`, optional, `decodeIfPresent`).

```swift
public struct IECReport: Codable, Equatable {
    public var stationLine: String              // C3 on INV 01 sheets
    public var module: Module                   // brand, powerW (AA4), areaM2 (for efficiency)
    public var inverters: [Inverter]            // 1…n, order = INV 01, 02, …
    public var before: Conditions               // INV 01-ก่อน E29, E30, AA30
    public var after: Conditions                // INV 01-หลัง E29, E30, AA30
    public var yrKWhM2Day: Double?              // AA25 on หลัง sheets
    public var arrayTempC: Double?              // AA26 on หลัง sheets
}
public struct Inverter: Codable, Equatable {
    public var ratedKW: Double                  // E5
    public var serial: String                   // O5
    public var slots: [Slot?]                   // exactly 20 (slot n → column E+n-1); nil = no string
    public var continuity: Check?               // E11
    public var irSummary: Check?                // E14 (derived from slot IR values, §3.2)
    public var functionalBefore: Check?         // E20
    public var functionalAfter: Check?          // E21
    public var energy7dKWh: Double?             // E25
    public var remark: String?                  // D31 on the หลัง sheet
}
public struct Slot: Codable, Equatable {
    public var seq: Int                         // INVnSTseq label (Word appendix order)
    public var brand: String?                   // row 8
    public var modules: Int                     // row 9
    public var optimizers: Int?                 // row 10
    public var polarityOK: Bool?                // row 12
    public var irTestV: Int?                    // row 13 (1000)
    public var irPosMOhm, irNegMOhm: Double?    // kept in the app and the Word appendix; Excel gets E14 only
    public var vocV, iBeforeA: Double?          // rows 16, 18 (ก่อนออน)
    public var vmpV, impA: Double?              // rows 17, 19 (หลังออน)
}
public enum Check: String, Codable { case normal, abnormal }
```

Derived values (pure functions, tested): `installedW = Σ modules × powerW`, `dailyKWh = energy7d ÷ 7`,
`yf = dailyKWh ÷ (installedW ÷ 1000)`, `pr = yf ÷ yr`, `efficiency = dailyKWh ÷ (yr × Σ modules × areaM2)`.
Each is rounded to 2 decimals **before** it is written and before it is used in the next step (the sample's PR was
computed from the rounded Yf).

---

## 3. Writing rules

### 3.1 Template and parts

- Ship the original as `TCRoofKit/Sources/ExcelExport/Resources/iec62446_template.xlsx`, **byte-identical** to
  `docs/specs/iec62446/1FORMI1.xlsx` (sample values included). Do not clean it in Excel: saving it again changes
  styles, revision ids and `calcId`.
- The exporter first **clears** every `input` cell from the inventory, then writes the report. An empty report
  therefore gives the blank form, and the sample report gives back the original (§5).
- Keep the zip entry order. A part that is not changed is copied as the same bytes (re-compressing is allowed).
- Parts that may change with 2 inverters: `sheet1–4.xml` and `sharedStrings.xml`. Nothing else.

### 3.2 Cell patching (`IECSheetPatch`)

Patch the sheet XML **in place by byte range**; do not parse and re-serialise the sheet (the `SheetXML` writer
rewrites every `<row>` and `<c>`, which changes attribute order and spacing in 17,862 cells).

1. Find `<c r="REF" …/>` or `<c r="REF" …>…</c>` for each target. All targets already exist in the original (the
   inventory has `present: true` for every one), so no cell or row is ever inserted.
2. Replace only that element. Keep `r` and `s` exactly; set or remove `t`; replace the children.
   - number → `<c r="E16" s="25"><v>755</v></c>` (no `t`)
   - text → `<c r="E12" s="23" t="s"><v>24</v></c>` (shared string index)
   - empty → `<c r="E17" s="30"/>`
3. Never write a `formula` cell. After all inputs are written, refresh the cached `<v>` of each formula cell so
   viewers that do not recalculate (Quick Look, Files, Drive preview) show the right value:
   - AA9 = Σ row 9 × AA4, as a number;
   - link cells copy the INV 01 value and keep `t="str"`; an empty source gives `t="str"` with `<v></v>`, as Excel
     writes it.
   `workbook.xml` stays as it is (no `fullCalcOnLoad`), so Excel opens without a "save changes?" prompt caused by us.
4. Numbers: shortest round-trip text (`755`, `561.2`, `0.69`), `.` as decimal separator regardless of locale, no
   exponent, no trailing zeros. Measured values keep the precision entered (V: 1 decimal, A: 2 decimals, MΩ: 0).

### 3.3 Shared strings

- Text is written through `sharedStrings.xml`, never `inlineStr`, matching how Excel stored the original.
- Reuse the index when the exact text already exists (`Normal` = 21, `P` = 24, `1000V` = 46, `Znshine` = 38 …).
- New text is appended as `<si><t>…</t></si>` (`xml:space="preserve"` when it has leading/trailing or double spaces,
  e.g. `Inverter 1 (125 kW) `). Existing `<si>` entries are never removed or reordered, because unchanged cells
  point at them by index.
- Recompute `count` (number of `t="s"` cells in all sheets) and `uniqueCount` (number of `<si>`).

### 3.4 Cell map

Columns E…X = slot 1…20 (`MPPT k` = columns 2k−1, 2k). A slot with no string leaves its whole column empty.
"Both" means the cell is written on the ก่อน and the หลัง sheet of that inverter, as in the original.

| Cell(s) | Sheets | Value | Type, format |
|---|---|---|---|
| C3 | INV 01 (both) | `stationLine` | text |
| E5 | both | `Inverter {i} ({ratedKW} kW) ` (trailing space; kW without decimals when whole) | text |
| O5 | both | `S/N : {serial}` | text |
| AA4 | both | `module.powerW` | number |
| E8:X8 | both | slot brand | text |
| E9:X9 | both | modules | number |
| E10:X10 | both | optimizers (empty when nil or 0) | number |
| E11 | both | continuity: `Normal` / `Abnormal` | text (merged E11:X11) |
| E12:X12 | both | polarity: `P` (✓ in Wingdings 2) / `O` (✗) | text |
| E13:X13 | both | `{irTestV}V` → `1000V` | text |
| E14 | both | IR summary: `Normal` when every used slot has min(+E, −E) ≥ 1 MΩ at 1000 V, else `Abnormal` | text (merged E14:X15) |
| E16:X16 | both | Voc ก่อนออน | number |
| E17:X17 | หลัง | Vmp หลังออน | number |
| E18:X18 | both | current ก่อนออน (0) | number |
| E19:X19 | หลัง | Imp หลังออน | number (format 0.00) |
| E20 | both | functional ก่อนออน: `Normal` / `Abnormal` | text |
| E21 | both | functional หลังออน | text |
| E22 / E23 | หลัง | PR / Yf | number (0.00) |
| E24 / E25 | หลัง | kWh/day / kWh 7 days | number (0.00) |
| E26 | หลัง | efficiency as a fraction (0.15) | number (format 0 %) |
| E29 | INV 01 | `{°C, 1 decimal} (ºC)` → `34.3 (ºC)` (ก่อน sheet from `before`, หลัง from `after`) | text |
| E30 | INV 01 | `{W/m², integer} (W/m²)` → `1022 (W/m²)` | text |
| AA30 | INV 01 | `{H}.{mm} น.` → `13.00 น.` | text |
| AA25 | INV 01-หลัง | `Solar irradiance (เฉลี่ย) =   {yr} kWh/m2` (3 spaces); the ก่อน sheet keeps the blank text `Solar irradiance (เฉลี่ย) =   kWh/m2` | text |
| AA26 | INV 01-หลัง | `Array Temperature = {t} (ºC)`; ก่อน keeps `Array Temperature =   (ºC)` | text |
| D31 | หลัง | `remark` (sample: `กำลังผลิตถูกหรี่โดยโหลด` on INV 01-หลัง) | text |
| E27 | — | `เอกสารแนบ` constant | unchanged |
| Y, Z (ผ่าน / ไม่ผ่าน) | — | empty in the original | unchanged (open question 3) |

Rows 17 and 19 stay empty on the ก่อน sheets. Rows 22–26 stay empty on the ก่อน sheets (AA24: "…ก่อนเชื่อมระบบเท่ากับ 0").
The ก่อน sheet E21 is written when it is known, as the original does.

Exporting before turn-on is allowed: whatever is recorded is written; the rest stays empty.

---

## 4. Inverter count other than 2

The original has 2 inverters. Other counts change the package, but only by the minimum, and every kept part
stays as in §3.

**1 inverter.** Remove `INV 02-ก่อน` and `INV 02-หลัง`: their `<sheet>` entries, workbook rels, sheet parts and
rels, drawing / vml / printerSettings parts that only they use, content-type overrides, their `_xlnm.Print_Area`
names (renumber the remaining `localSheetId`s to the new sheet positions), their `calcChain` entries
(`i="86"`, `i="90"`) and their names in `docProps/app.xml` `TitlesOfParts` (update the two `vt:i4` counts).
`INV 01-หลัง` keeps sheetId 89.

**3 or more inverters.** Clone `INV 02-ก่อน` and `INV 02-หลัง` (they already carry the links to INV 01) as
`INV 03-ก่อน` … with:
- sheet order: all ก่อน sheets first, then all หลัง sheets (INV 01-ก่อน, INV 02-ก่อน, INV 03-ก่อน, INV 01-หลัง …);
- new sheetIds above the current maximum (91, 92 …), new `rId`s, new part names (`sheet5.xml` …);
- cloned drawing, vml and printerSettings parts per sheet (sharing the existing `media/` images);
- `tabSelected` removed from clones; `Print_Area` names for each clone, `localSheetId`s renumbered for all sheets;
- `calcChain` entries for the clone's formula cells (`C3, AA25, AA26, E29, E30, AA30, AA9`, `i` = its sheetId);
- `TitlesOfParts` and its counts updated.
Formulas in a clone are copied unchanged (they point at INV 01, which is what the PWA expects).

**More than 20 strings on one inverter:** export is refused with a message naming the inverter (open question 4).

---

## 5. Tests (`Tests/ExcelExportTests/IECExcelTests.swift`)

Fixtures: `iec62446_template.xlsx` and a Swift copy of the Praek Nam Daeng sample built from
`sample-praek-nam-daeng.json` with the original's typed values (Yf 2.93 / 3.33, not recomputed; a test-only
override).

1. **Round trip = 100 %.** Export the sample, unzip both files and compare:
   - every part other than `sheet1–4.xml` and `sharedStrings.xml` is byte-identical;
   - in each sheet the XML outside the touched `<c>` elements is byte-identical (compare with the touched elements
     cut out);
   - each touched cell has the same `s`, the same `t` family (`s` / `str` / number), the same resolved text or
     number, and formulas byte-identical;
   - every `<si>` that existed keeps its index and text.
2. **Blank form.** Export an empty report: all `input` cells are `<c r s/>` except the INV 01 ก่อน blanks of
   AA25/AA26 (kept text); formulas unchanged; AA9 cached 0; `count` / `uniqueCount` consistent.
3. **Rules.** Yf, PR and efficiency rounding; IR summary (one slot at 0.8 MΩ → `Abnormal`); `P` / `O`;
   `Inverter 1 (125 kW) ` spacing; `13.00 น.`; empty slot leaves the column empty; ก่อน sheets never get rows 17,
   19, 22–26.
4. **1 and 3 inverters.** Every relationship target exists; every part has a content type; sheet names unique and
   ≤ 31 characters; `localSheetId`s and `calcChain` sheet ids exist; INV 03 links point at INV 01.
5. **Manual (before release).** Open the exported file in Excel for Mac and Excel for Windows: no repair prompt,
   no "save changes?" on close, logos and print preview identical to the original; open a PWA workbook that links
   to the form and update links.

---

## 6. File name and delivery

- Default name `IEC62446 {station short name} {yyyy-MM-dd}.xlsx` (open question 1 for `.XLS`).
- Export from the IEC review screen (`ตรวจและส่งออก`, step 7) beside `ดูตัวอย่างแผ่น Excel`; the share sheet and
  the Drive report folder use the same bytes.

---

## 7. Open questions

1. **Extension.** The customer's file is a 2007+ package named `.XLS`, and Excel warns about the mismatch when
   opening it. If the linking workbooks refer to `1FORMI1.XLS` by name, the export should keep that name and
   extension; otherwise `.xlsx` avoids the warning. Which do the PWA files use?
2. **Rounding of Yf / PR.** The app computes Yf from kWp (INV1 3.13, PR 0.74), where the sample typed 2.93 / 0.69.
   Confirm that the computed values replace hand-typed ones.
3. **ผ่าน / ไม่ผ่าน (Y, Z).** Empty in the original. Leave empty (100 % original) or tick from the rules
   (`✓` in Y or Z per row)?
4. **More than 20 inputs on one inverter.** Refuse, or continue on a second sheet pair (`INV 01-ก่อน (2)`)?
5. **Failure text.** `Abnormal` for E11, E14, E20, E21 when a check fails, or another word the PWA uses?
6. **Author path.** `workbook.xml` keeps `x15ac:absPath` = `C:\Users\chawalwit.s\Desktop\คุมงานประปา\…` from the
   original. Keep it (100 %) or remove it from the template?
7. **Continuity and inverter functional checks** (E11, E20, E21) have no input on the iPad screens yet: put them
   at the end of ก่อนออน · ฉนวน and หลังออน · แรงดัน / กระแส, or on the review screen?
