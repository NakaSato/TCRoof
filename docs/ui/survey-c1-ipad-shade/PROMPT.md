# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git checkout design/survey-c1-ipad-shade && git checkout -b feat/survey-c1-ipad-shade

Follow docs/ui/survey-c1-ipad-shade/CLAUDE_CODE_TASK.md.

Scope: only the shade card under the plan in C1's PV mode (แผงบนหลังคา) on iPad, the shaded modules on the plan, and
the core it needs. Ignore the board's right column (trimmed in another review).
Work through change list items 1–5 in order, and nothing else:
1. obstacles shade the modules: PVYield Face.beamShadeHourly (nil = today), TCRoofCore projects each obstacle with a
   height (Roof.Area.height, kind default) onto the face's modules per hour; RoofMountYield.estimate uses it; tests
2. TCRoofCore/RoofPV/RoofShade.swift: per face and whole roof, from RoofMountYield's hourly run (PVYield only, no
   SAM): DC kWp, module, tilt / azimuth, Sun Access, TOF (vs the site's best fixed plane), TSRF = TOF × SA, monthly
   sun access / shading, hour × month sun access, and the site's sun path (21 Jun, 21 Mar / Sep, 21 Dec); nil with
   the reason when there's no GPS or no hourly weather near the site; RoofShadeTests
3. RoofPageWide+Shade.swift: the card เงาบังแผง | Shade in place of rowSectionCard in PV mode: face tabs,
   the 8-column metrics row, Sun-path (with obstacle silhouettes) / Monthly / Hour-Month charts as Sketch, the source line
   3b. the plan shows the modules in shadow at 21 ธ.ค. 09:00 (no moment picker), the obstacles' shadow polygons, two
   legend rows; one projection shared with item 1
4. PDF: one shade page per face after พลังงานไฟฟ้าโดยประมาณ, the same Sketches
5. DEBUG -surveyC1 pvshade | pvshadenorth, one CLAUDE.md sentence, RoofShadeUITests

Leave alone, with no refactors or renames outside the list:
- the structure section card
- the right column
- the plan and its legend, beyond item 3b
- field ids and Excel cells
- the Excel layout
- PVYield's golden fixtures (the new input defaults to nil)
- the RoofDXF golden files

Start with the code-review-graph tools as CLAUDE.md says. Then read RoofMountYield (and +Report), PlaneYield,
PVYield/Hourly (YieldResult, YieldEngine, SolarPosition, SunTrack, BundledWeather), RoofPageWide+Section,
RoofPageWide+Energy, RoofPageWide (wideLayout, stackedColumn, sectionHeight), Roof.Area / RoofFaces (height,
heightOrDefault) and ReportLayout+Sections (roofEnergyUnit) before writing code.

Rules:
- The board's numbers are examples (assets/sample-data.json); never hard-code them.
- Run the hourly engine once per layout, off the main thread, never stored.
- Colours from Theme, hit areas ≥ 44 pt, TCButtonStyle, RoofSegments.
- Draw charts with Sketch, one view each.

When done:
- run swift test in TCRoofKit (golden files unchanged)
- write the demo PDF with -surveyRoofPDF YES -surveyC1 pvshade and save its shade pages to screenshots/
- run the xcodebuild app build with your own -derivedDataPath, in the background
- run RoofShadeUITests, RoofRulesUITests and RoofDesignDragUITests on an iPad simulator
- save screenshots named like states/ to screenshots/
- tick the change list, list the energy figures that changed, and answer the three open questions in your report

Commit and push feat/survey-c1-ipad-shade. Do not merge.
```
