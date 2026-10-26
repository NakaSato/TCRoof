# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git checkout design/survey-c1-ipad-shade && git checkout -b feat/survey-c1-ipad-shade

Follow docs/ui/survey-c1-ipad-shade/CLAUDE_CODE_TASK.md.

Scope: only the shade card under the plan in C1's PV mode (แผงบนหลังคา) on iPad, and the core it needs.
Work through change list items 1–3 in order, and nothing else:
1. TCRoofCore/RoofPV/RoofShade.swift: per face and whole roof, from RoofMountYield's hourly run (PVYield only, no
   SAM): DC kWp, module, tilt / azimuth, Sun Access, TOF (vs the site's best fixed plane), TSRF = TOF × SA, monthly
   sun access / shading, hour × month sun access, and the site's sun path (21 Jun, 21 Mar / Sep, 21 Dec); nil with
   the reason when there's no GPS or no hourly weather near the site; RoofShadeTests
2. RoofPageWide+Shade.swift: the card เงาบังแผง | Shade in place of rowSectionCard in PV mode: face tabs,
   the 8-column metrics row, Sun-path / Monthly / Hour-Month charts as Sketch, the source line
3. DEBUG -surveyC1 pvshade | pvshadenorth, one CLAUDE.md sentence, RoofShadeUITests

Leave alone, with no refactors or renames outside the list:
- the structure section card
- the right column
- the plan and its legend
- field ids and Excel cells
- the PDF and Excel
- PVYield's golden fixtures
- the RoofDXF golden files

Start with the code-review-graph tools as CLAUDE.md says. Then read RoofMountYield (and +Report), PlaneYield,
PVYield/Hourly (YieldResult, YieldEngine, SolarPosition, SunTrack, BundledWeather), RoofPageWide+Section,
RoofPageWide+Energy and RoofPageWide (wideLayout, stackedColumn, sectionHeight) before writing code.

Rules:
- The board's numbers are examples (assets/sample-data.json); never hard-code them.
- Run the hourly engine once per layout, off the main thread, never stored.
- Colours from Theme, hit areas ≥ 44 pt, TCButtonStyle, RoofSegments.
- Draw charts with Sketch, one view each.

When done:
- run swift test in TCRoofKit (golden files unchanged)
- run the xcodebuild app build with your own -derivedDataPath, in the background
- run RoofShadeUITests, RoofRulesUITests and RoofDesignDragUITests on an iPad simulator
- save screenshots named like states/ to screenshots/
- tick the change list and answer the four open questions in your report

Commit and push feat/survey-c1-ipad-shade. Do not merge.
```
