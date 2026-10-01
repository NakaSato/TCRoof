# Claude Code task: B1 ตู้ไฟฟ้าอาคาร (iPad) — new design

> How to use: open Claude Code in the `TCRoof` repo folder and type
> `Follow docs/ui/survey-b1/CLAUDE_CODE_TASK.md`

UI text stays in Thai exactly as in `preview.png`. Thai strings in `backticks` are the literal labels.

## Goal
Each B1 building (`.panel` module) is currently its own `groupPage` with `photoBreaker`, `photoWide`, `breakerAT`, `loadKW`, `loadTime` and `detail`.

Build one B1 wide page for iPad landscape (`PanelsPageWide`) that shows every B1 building in a master list, as specified in [`SPEC.md`](SPEC.md):
- wide photo with a marked PV connection point
- main breaker photo
- a link to the feeding breaker in the A3 diagram
- load in kW with a time chip
- a daytime-load vs PV note that flags zero export (B4)

References: `preview.png`, `preview.html`, `iPadB1.dc.html` (static markup), `icons/`.

## Relevant files
- `TCRoofKit/Sources/TCRoofCore/Schema.swift`: `.panel` `ModuleSpec`, `detail()`
- `TCRoofKit/Sources/TCRoofCore/Models.swift`: `Transformer.boards`, `Board.breakers`, `Breaker.target`
- `TCRoofKit/Sources/TCRoofCore/SingleLine.swift`: `loadText(for:)` (name matching to replace with the link)
- `TCRoofKit/Sources/TCRoofCore/SiteShapes.swift`: reuse for `pvPoint`
- `TCRoofKit/Sources/TCRoofCore/Progress.swift` (~line 52), `PDFReport/ReportLayout.swift` (~line 544), `ExcelExport/ExcelExporter.swift` (~lines 126–127)
- `TCRoofKit/Sources/SurveyUI/JobEditor*.swift` (module pages, sidebar), `SitePageWide*.swift` (photo + shape drawing), `ElectricalPageWide*.swift`

Use code-review-graph per `CLAUDE.md` to find callers of `ModuleType.panel`, `breakerAT`, `loadKW`, `loadTime` and `SingleLine.loadText` before editing.

## Steps
1. **Model:**
   - `a3Breaker`, `pvPoint`, `spareSlots` (optional)
   - `BuildingPanels` rules (SPEC §3): status pill, sub-line, daytime note, missing list
   - linking writes `breakerAT` and A3 `Breaker.target`; deleting a building clears the target
2. **UI:** `PanelsPageWide` (SPEC §4):
   - master list with add / select
   - rename and delete (with confirm)
   - wide photo with connection-point rectangle
   - breaker photo empty state
   - A3 breaker picker, load field and time chips, note, details
   - bottom status
   - choose it from `JobEditor` for any `.panel` section on iPad landscape
3. **SLD:** `SingleLine` uses `a3Breaker` first and the name match as the fallback.
4. **PDF:** draw `pvPoint` on the wide photo and print the A3 link. Excel unchanged but still filled.
5. **Icons:** copy `icons/B1Icons.xcassets` into `TCRoofKit/Sources/SurveyUI/Resources/` and use the images per SPEC §7.

## Constraints
- Do not change existing field ids / labels or the Excel layout. New fields are optional, so B1 completion counts as before.
- Old job JSON must decode.
- iPad portrait / iPhone: stacked layout; the old `groupPage` stays reachable.
- Every button and chip is at least 44 pt.
- Values in the preview are examples. Do not hardcode them. Examples: โรงสูบน้ำ, อาคารสำนักงาน, โรงกรอง, CB1 400 AT, 85 kW, 107 kW, PV 120 kW, the note text.

## Check before finishing
1. Build passes and `swift test` passes, with the tests in SPEC §6.
2. Run the iPad simulator in landscape at 1366 × 1024 and compare with `preview.png`.
3. Try the flow:
   - add a building
   - take both photos
   - mark the connection point
   - link it to an A3 breaker, and check `breakerAT` and the A3 target
   - enter a load and pick a time
   - watch the daytime note
   - open the SLD and check the load block
   - delete the building and check the A3 target is cleared
4. Summarize the changed files and the open questions in SPEC §8.
