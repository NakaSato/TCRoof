# Prompt for Claude Code

```
git fetch origin && git switch -c feat/iec62446-sheet-before origin/design/iec62446-sheet-before
```

```
Follow docs/ui/iec62446-sheet-before/CLAUDE_CODE_TASK.md.

FIRST check that TCRoofKit/Sources/ExcelExport/IECExcel.swift, Resources/iec62446_template.xlsx and
TCRoof/Views/Install/IEC/ exist. If not, STOP and report.

Build ONLY a read-only iPad preview of the exported sheet "INV nn-ก่อน" (board IECTest.dc.html):
1. Factor every cell's value out of IECExcel into one pure function used by both the writer and the preview.
   The exported workbook must not change (IECExcelTests).
2. Read the layout (column widths, row heights, merges, fills, borders, fonts, logos) from the template xlsx
   into a model in ExcelExport. Draw it with Canvas, fit to width, pinch zoom up to 3x.
3. "แสดงที่มา" toggle (on by default): tint each app-filled cell with its wizard step's colour (the task's table),
   plus a legend card. Off = the form exactly as exported. Mapping in TCRoofCore with a test.
4. Sheet picker INV 01-ก่อน / INV 02-ก่อน / …; the after sheets reuse the view later (not now).
5. Tapping a tinted cell or a legend swatch opens the step that fills it, at that inverter / string
   (existing screens where a step page isn't built; report each).
6. Missing app values: a subtle dashed red inner border, only with sources on.
7. Entry: "ดูชีต Excel" on step 7 and on the IEC overview.
8. DEBUG -iecSheet INV01-before|INV02-before, -iecSheetSource off (one line in CLAUDE.md).

Do not change:
- the export
- the template or the cell map
- stored fields
- the iPhone

Steps:
1. Read the task, then IECTest.dc.html as text, and measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run swift test with the new tests.
4. Run on an iPad Pro 13" simulator with -iecDemo YES. Save screenshots 01, 02 and 03 in
   docs/ui/iec62446-sheet-before/screenshots/ and compare them with states/.
5. Commit on feat/iec62446-sheet-before and push it (no merge).
6. Report:
   - the differences
   - the font used
   - what each cell tap opens
   - the open questions
```
