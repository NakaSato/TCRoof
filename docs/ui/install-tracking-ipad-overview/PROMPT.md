# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/install-tracking-ipad-overview

Follow docs/ui/install-tracking-ipad-overview/CLAUDE_CODE_TASK.md.

Scope: only the iPad install tracking page's header buttons and its ภาพรวม tab's document tiles, as drawn in
iPadInstall.dc.html (menu "ov"). Work through the change list (§1–§7) in order, and nothing else:
- no tab bar changes (ตั้งค่าโครงการ and the in-page คำขอรายสัปดาห์ are other branches)
- no Gantt / S-curve / KPI layout / site panel changes (they match v2 already)
- no iPhone changes
- no StationDocs rule or catalog changes
- no stored-field changes
- no refactors or renames outside the list

Start with the code-review-graph tools as CLAUDE.md says. Then read InstallTrackingPage (header, headerButton),
InstallTrackingPage+Site, InstallPageData+Site (docTiles, packageTile, paperItems, demoTiles), StationDocs and
JobDevicesView before writing code.

Data rules:
- Show only what has a source. Hide the rest and list it in your report.
- The board's values are examples (assets/sample-data.json); never hard-code them outside demoTiles.

Style rules:
- Colours from Theme (the new waiting tone is Theme.planInspect / planInspectSoft).
- Hit areas ≥ 44 pt, TCButtonStyle.
- Split each card and row into its own computed property.

When done:
- run swift test in TCRoofKit
- run the xcodebuild app build with your own -derivedDataPath, in the background
- run InstallTrackingUITests on an iPad simulator
- save simulator screenshots named like states/ to screenshots/
- tick the change list and answer the open questions in your report

Commit on this branch.
```
