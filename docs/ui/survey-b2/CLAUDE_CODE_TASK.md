# Claude Code task: B2 พื้นที่ติดตั้งอินเวอร์เตอร์ (iPad) — new design

> How to use: open Claude Code in the `TCRoof` repo folder and type
> `Follow docs/ui/survey-b2/CLAUDE_CODE_TASK.md`

UI text stays in Thai exactly as in the previews. Thai strings in `backticks` are the literal labels.

## Goal
B2 is currently drawn by `groupPage` from the `.inverter` `ModuleSpec`: `photoArea`, `photoDetail`, `sizeLWH` (text), `inverterCount` and a note.

Build the B2 wide page for iPad landscape (`InverterPageWide`) as specified in [`SPEC.md`](SPEC.md):
- measured area with a boundary drawn on the photo
- Growatt inverter list
- automatic cabinets, breakers, cables, AC tray and ladder from the equipment catalog
- a live dimensioned plan, outdoor or indoor, with fit and walkway checks
- icons from `icons/`

References in this folder:
- `preview.png` (outdoor, 2 × 60 kW), `preview-indoor.png`, `preview-overflow.png` (60 + 60 + 80 kW, area too short)
- `plan-outdoor.png`, `plan-indoor.png`, `plan-overflow.png`: the plan drawings at 2.5×
- `iPadB2.dc.html`: design source; its script is the reference for every formula
- `equipment-catalog.json`: inverter, PV module, cabinet data and breaker rules
- `icons/`: SVG, PNG and `B2Icons.xcassets`

## Relevant files
- `TCRoofKit/Sources/TCRoofCore/Schema.swift`: `.inverter` `ModuleSpec`
- `TCRoofKit/Sources/TCRoofCore/Progress.swift` (~line 54), `Flood.swift` (inverter count, `invFloorCm`), `SingleLine.swift` (inverter count and kW)
- `TCRoofKit/Sources/PDFReport/ReportLayout.swift` (~line 551), `ExcelExport/ExcelExporter.swift` (~lines 134–136)
- `TCRoofKit/Sources/SurveyUI/JobEditor*.swift` (wide page selection), `SitePageWide*.swift` (photo + shape drawing to reuse for the boundary), `ElectricalPageWide*.swift` (zoom card pattern)
- `TCRoofKit/Sources/TCRoofCore/SiteShapes.swift` (reuse for `invBoundary`)

Use code-review-graph per `CLAUDE.md` to find callers of `inverterCount`, `sizeLWH`, `ModuleType.inverter` and `SingleLine.build` before editing.

## Steps (one PR each)
1. **Catalog:** `EquipmentCatalog` + bundled `equipment-catalog.json` (TCRoofCore resource) + decode test.
2. **Model and rules:**
   - new optional B2 fields (SPEC §2)
   - old `sizeLWH` / `inverterCount` migration and write-back
   - `InverterStation` calculations (SPEC §4) with the unit tests in SPEC §9
3. **Drawing:** `InverterStationDrawing` → `Sketch` for outdoor and indoor, with the ladder section (SPEC §5), plus snapshot tests against the three previews.
4. **UI:** `InverterPageWide` (SPEC §6): boundary drawing on the photo, size steppers, span chips, plan card with tray and ladder steppers, inverter rows, summary, status line; B4 toggle writes B4 `level`.
5. **Icons:** copy `icons/B2Icons.xcassets` into `TCRoofKit/Sources/SurveyUI/Resources/` (next to the A2 / SLD catalogs). Draw plan symbols as `DrawOp` paths matching `icons/svg/b2-*.svg`; use the `ui-*` images for controls.
6. **Outputs:**
   - PDF B2 unit (photos, plan, equipment table)
   - Excel unchanged but still filled
   - SLD reads `invSizes`, the catalog `imax` and the B2 feeder (SPEC §7)

## Constraints
- Do not change existing field ids / labels or the Excel layout. All new fields are optional, so B2 completion counts as before.
- Old job JSON must decode. `sizeLWH` and `inverterCount` must stay in step with the new fields.
- iPad portrait and iPhone keep `groupPage`.
- Buttons and steppers have at least 44 pt hit areas.
- Plan and PDF drawings are vector (`Sketch`), never bitmaps of the icons.
- Values in the previews are examples. Do not hardcode them. Examples: NO.224, 9.5 × 2.5 × 3.0 m, 2 × 60 kW, 120 kW A1, the note text.

## Check before finishing
1. Build passes and `swift test` passes, including SPEC §9. Expected values:
   - 2 × 60 kW: 125 AT each, tray 100, feeder 250 AT `4×1C 120 + G25`, ladder 200, room 9.5 m, walkway 1.48
   - indoor: wall 8.5 m
   - 60 + 60 + 80: needs 12.0 m
2. Run the iPad simulator in landscape at 1366 × 1024 and compare with the three previews.
3. Try the flow:
   - draw a boundary and type edge lengths
   - change W / L
   - edit, add and EQ the spans
   - add a third inverter and see the overflow
   - switch indoor / outdoor
   - step the tray and ladder up
   - toggle B4
   - export the PDF
   - open the SLD and check the inverter kW and PV breaker come from B2
4. Summarize the changed files and the open questions in SPEC §10.
