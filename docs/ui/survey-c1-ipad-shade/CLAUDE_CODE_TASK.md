# Task: iPad · C1 หลังคา `แผงบนหลังคา` · the shade card `เงาบังแผง | Shade` (board 26 ต.ค. 2569)

> **How to use:** open Claude Code in the `TCRoof` repo on branch `design/survey-c1-ipad-shade`, then paste `PROMPT.md`, or type
> `Follow docs/ui/survey-c1-ipad-shade/CLAUDE_CODE_TASK.md`

- **Board:** `iPadC1.dc.html` (1366 × 1024), the design canvas's "iPad · ขั้น 10/13 C1 แปลน + โครงสร้าง".
  - Read it as text and search for `เงาบังแผง`, `shFace`, `shSam` and `Sun-path`.
  - Its script is a toy for the states only. **Don't port it.** Its sun-path curves are real geometry for 13.75° N; the app draws them for A1's GPS.
- **Everything on the board is example data** (`assets/sample-data.json`). Never hard-code it.

## What changes

In the PV mode of C1 (`แผงบนหลังคา`), the card under the plan was the closed `รูปตัดแถวที่เลือก` (`RoofPageWide+Section.swift`, `rowSectionCard`). It becomes a shade report for one module group, computed by **PVYield only** (no SAM; the design reviewed and dropped it).

## Scope: only this

**In scope:**
- `TCRoofCore/RoofPV`: a shade summary per roof face and for the whole roof, from `RoofMountYield`'s hourly run.
- `TCRoofUI/Survey/Pages/Roof`: the new card in place of `rowSectionCard` in PV mode (iPad wide and stacked; iPhone keeps what it has).
- `PVYield`: an optional hourly beam-shade input on a face (for the roof's own obstacles).
- `PDFReport`: one shade page per face after `พลังงานไฟฟ้าโดยประมาณ` (decided 26 ต.ค.: open questions 1 and 2 answered yes).
- Tests for the core.

**Do not touch:**
- the structure mode's section card (`frameSectionCard`)
- the obstacle sheet's height field (`Roof.Area.height`, `RoofObstacleKind.defaultHeight`): it exists already; use it, don't add another
- the right column's cards
- the plan and its legend
- field ids and Excel cells
- the RoofDXF golden files
- PVYield's existing stages: the golden fixtures must not change (the new input defaults to nil)
- the Excel

**Before editing:** use code-review-graph (per `CLAUDE.md`), else grep. Read:
- `RoofMountYield.swift` (`Inputs`, `Face`, `FaceYield`, `Estimate`, `estimate`, `site`)
- `PVYield/Hourly/YieldResult.swift` (`Face.hInc`, `hShade`, `Hourly.poa`, `monthly`) and `YieldEngine.swift`, `SolarPosition.swift`, `SunTrack.swift`
- `PlaneYield.swift`
- `RoofPageWide+Section.swift`, `RoofPageWide+Energy.swift`, `RoofPageWide.swift` (`wideLayout`, `stackedColumn`, `sectionHeight`)

## Files in this folder

| File | Shows |
|---|---|
| `preview.png` | = `states/01` |
| `states/01-shade-south.png` | PV mode, the card on `ด้านใต้` |
| `states/02-shade-north.png` | `ด้านเหนือ` |
| `states/03-shade-whole-roof.png` | `รวมทั้งหลังคา` |
| `states/04-shade-card-crop.png` | The card alone, @2x |
| `iPadC1.dc.html`, `grf.css`, `assets/sample-data.json` | Design source and example values |
| `screenshots/` | Empty. Put your simulator screenshots here, named like `states/` |

## Change list

Work in order. After each item, build and take its screenshot.

### 1. Obstacles shade the modules (decided: open question 2)
C1's obstacles already carry a height above the roof (`Roof.Area.height`, typed in the obstacle sheet; nil = `RoofObstacleKind.defaultHeight`: turbine 0.60, stack 2.00, pipe 0.50; skylight, keep-out and other 0). Today the height only drives the layout's `เว้นเงา 09:00–15:00` keep-out; the yield engine ignores it.
- **PVYield:** add `Face.beamShadeHourly: [Double]?` (8760 values, 0–1, the share of the face's modules in an obstacle's shadow at that hour; nil = none). The engine multiplies the beam part by `1 − value` next to `nearShadingLossFrac`. Nil keeps every golden fixture and stage test unchanged.
- **TCRoofCore:** for each face in use, each hour with the sun up, project every obstacle with a height > 0 as a box (its plan rectangle × its height, standing on the roof plane) along the sun's direction onto the face's plane, and take the share of the face's module rectangles it covers. Use the layout's real module rectangles. Fill `beamShadeHourly`.
- **`RoofMountYield.estimate` uses it too**, so the energy card, the PDF and the Excel figure include the roof's own obstacles. Report which demo and fixture figures changed. A job without obstacles of any height gives exactly the figures of today.
- **Tests:**
  - an obstacle of height 0 changes nothing
  - a 2 m stack due south of a face lowers its December noon beam
  - the same stack north of a south face (northern-hemisphere winter) shades nothing at noon
  - `RoofMountYield` golden figures unchanged for a roof with no obstacles

### 2. Core: shade figures (`TCRoofCore/RoofPV/RoofShade.swift`, new)
A pure value made from the same hourly run `RoofMountYield.estimate` does (run it once, don't duplicate the weather load):
- **Per group** (each face in use, and the whole roof):
  - `dcKWp`, `modules`, module name from the catalog (as `RoofMountYield` matches it), `tilt`, `azimuth`
  - **Sun Access** = POA after shading ÷ POA without shading, over the year (`Face.hShade` ÷ `Face.hInc`, or the hourly sums)
  - **TOF** = POA without shading on the real tilt / azimuth ÷ POA on the site's best fixed plane. Find the best plane with the same engine and weather (a coarse search, tilt 0–40° × azimuth 90–270°, then refine). Report the step you used.
  - **TSRF** = TOF × Sun Access
  - **monthly** sun access and shading (12 values, % of that month's unshaded POA)
  - **hour × month** sun access (12 × the daylight hours), for the heat map
- **Sun path** for the site: alt / az for the 21st of June, March / September, and December, every 10 min, from `SolarPosition` with A1's latitude and longitude. Hours marked.
- **Whole roof** = POA-weighted over the faces in use.
- Without A1's GPS or hourly weather near the site (`BundledWeather`, 100 km), return nil and give the reason (the card says it). Don't fall back to SolarModel for these metrics.
- Computed off the main thread and never stored, like `RoofMountYield`.
- **Tests** (`RoofShadeTests`):
  - no shade → Sun Access 100 %
  - a face at the best plane → TOF 100 % (within the search step)
  - TSRF = TOF × SA
  - monthly values in 0–100 %
  - the sun path at 13.75° N: June noon altitude about 80°, December noon about 53°
  - golden fixtures of PVYield unchanged

### 3. Card UI (`RoofPageWide+Shade.swift`, new) (`states/01`–`04`)
Replaces `rowSectionCard` in PV mode; `sectionHeight` gives it the structure section's height (no closed state).
- **Header:** `เงาบังแผง | Shade` (underlined) `| <group>`, and on the right a `RoofSegments` `ด้านใต้ | ด้านเหนือ | รวมทั้งหลังคา`.
  - It lists the faces in use by their direction (`RoofFace.direction`), then `รวมทั้งหลังคา`. A shed roof has one face and no `รวม`.
- **Metrics row:** 8 columns, tiles on `Self.track`, 44 pt:
  - `DC capacity` (kWp)
  - `ผู้ผลิตแผง | จำนวน`, span 2
  - `Tilt | Azimuth`, span 2: `15° | S 180°`, or both faces on `รวม`
  - `Sun Access`, `TOF`, `TSRF` (%, one decimal)
- **Charts row**, drawn as `Sketch`, never bitmaps:
  - **Sun-path Diagram:** polar, N up; rings at 0°, 30°, 60°; the three days in orange, amber and blue; hour dots; legend under it. Each obstacle with a height is drawn on it as the grey silhouette seen from the face group's centre (azimuth range × elevation), so the user sees which hours it blocks.
  - **Monthly Sun Access & Shading Averages:** two bars per month, 0–100 %.
  - **Hour-Month Sun Access:** a heat map from `Theme` colours, months down and hours across.
- **Footer line** (`Theme.inkMuted`, 12 pt): `PVYield รายชั่วโมง | <weather source> | พิกัด A1 <lat>° N`, or why there's nothing (no GPS, or weather too far).
- While computing: `กำลังคำนวณเงา…` in the tiles. With no layout: `ยังไม่มีผังแผง`.
- Colours from `Theme`, hit areas ≥ 44 pt, `TCButtonStyle`, `RoofSegments`. Split each chart into its own view.

### 4. PDF: one shade page per face (decided: open question 1)
After `พลังงานไฟฟ้าโดยประมาณ` (`ReportLayout+Sections.swift`, `roofEnergyUnit`), add `เงาบังแผง` for each face in use (and none for a roof without a layout or without RoofShade):
- the same figures as the card's metrics row, as a table
- the three charts from the same `Sketch`es as the screen (shared, not redrawn)
- the source line
- vector only. Report the page count of the demo job before and after.

### 5. DEBUG, docs and test
- **`-surveyC1 pvshade`** (with `-surveyPage roof`): sets A1's GPS to Bangkok (as `pvyield` does), adds a 2.00 m stack south of the ridge (as `pvobst` adds its stack) and opens PV mode with the card in view. **`pvshadenorth`** selects `ด้านเหนือ`. **`-surveyRoofPDF YES`** with `pvshade` writes the report with the shade pages.
- **CLAUDE.md:** add them to the `-surveyC1` item in one sentence, naming `RoofShade`.
- **`RoofShadeUITests`** (iPad): the card shows `Sun Access`; a tap on `ด้านเหนือ` changes `Tilt | Azimuth` to `N 0°`.

## Rules
- The board's numbers are examples. Engineering values come from the job, the catalog and PVYield, never from the board.
- No SAM. No new dependency.
- An old job with no obstacle of any height keeps its layout, energy figures, PDF, Excel and DXF.

## Check list
- [ ] `swift test` in `TCRoofKit` passes (`RoofShadeTests`, the obstacle-shade tests; PVYield and RoofDXF golden files unchanged).
- [ ] `-surveyRoofPDF YES -surveyC1 pvshade` writes `Documents/survey.pdf` with a shade page per face; its pages are in `screenshots/pdf-shade-*.png`.
- [ ] The xcodebuild app build passes, with your own `-derivedDataPath`, in the background.
- [ ] `RoofShadeUITests`, `RoofRulesUITests` and `RoofDesignDragUITests` pass on an iPad simulator.
- [ ] iPad screenshots `01`–`03` in `screenshots/`, taken with `-screen pwa -surveyDemo YES -surveyDemoSection YES -surveyWideA1 YES -surveyPage roof -surveyC1 pvshade` (and `pvshadenorth`; `รวม` by a tap).

## Decided (26 ต.ค. 2569)
- **PDF:** yes, one shade page per face after `พลังงานไฟฟ้าโดยประมาณ` (item 4).
- **Obstacle heights:** use the height C1's obstacles already have to shade the modules in the engine (item 1).

## Open questions (report, don't decide)
1. **TOF reference:** the best fixed plane at the site (as built here), or a fixed reference (tilt = latitude, due south) as some tools use?
2. **Removed `รูปตัดแถวที่เลือก`:** the row section is gone from PV mode. Keep it reachable somewhere (e.g. a button on the plan), or drop it?
3. **Objects around the building (A2):** trees and buildings beside the roof are not in this task. Add them as a horizon profile later?
