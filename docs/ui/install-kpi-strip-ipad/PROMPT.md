# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/install-kpi-strip-ipad && git checkout -b feat/install-kpi-strip-ipad

Follow docs/ui/install-kpi-strip-ipad/CLAUDE_CODE_TASK.md.

Scope: only the iPad install tracking page's KPI strip (kpiStrip / cells in InstallTrackingPage+HeaderAndKPI.swift).
Make every cell a button, as on the board:
- ความคืบหน้า and กำหนดการ switch the progress card to S-Curve;
- SPI opens a popover explaining SPI with the station's numbers;
- คาดส่งมอบ switches it to Gantt;
- the cell(s) whose view is showing are marked;
- ต้องดำเนินการ keeps opening its sheet.

Work through the change list in §4 in order, and nothing else:
- no change to the cells' values, notes, colours, widths, order or separator;
- no change to progressCard or the actions sheet;
- no change to the iPhone overview, which shares cells(_:);
- no change to InstallPageData.

Start with the code-review-graph tools as CLAUDE.md says. Then, before writing code, read:
- InstallTrackingPage+HeaderAndKPI.swift;
- InstallTrackingPage.swift (`view`, `sheet`);
- InstallTrackingPage+Progress.swift (`ProgressView` and the card's own switch);
- InstallTrackingPage+PhoneOverview.swift;
- InstallTrackingUITests.

Use colours from Theme only, and keep hit areas at the full 52 pt cell.

When done:
- run the xcodebuild app build with your own -derivedDataPath (in the background);
- run InstallTrackingUITests on an iPad simulator;
- save screenshots like states/02–03 to screenshots/;
- tick the change list;
- follow §6's decisions (already answered).

Commit on feat/install-kpi-strip-ipad and push it.
```
