# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/install-tracking-ipad-keyplan && git checkout -b feat/install-tracking-ipad-keyplan

Follow docs/ui/install-tracking-ipad-keyplan/CLAUDE_CODE_TASK.md.

Scope: only the iPad install tracking page's progress card (InstallTrackingPage+Progress.swift). Add a third view
"Key Plan" beside Gantt and S-Curve. Work through change list items 1–7 in order, and nothing else:
1. ProgressView.keyplan and the switch Gantt | S-Curve | Key Plan (-installView keyplan)
2. the legend and the วางแล้ว n/N chip in the header, Key Plan only
3. the plan on the left: KeyPlanImage on job.keyPlanPicture, one coloured pin per MP task × location
4. the 360 pt list on the right: ทั้งหมด / ยังไม่วาง filter, grouped by MP task, % with a plan tick
5. pin ↔ row selection
6. place mode: วางบนผัง / ย้ายจุดบนผัง write Settings.keyPoints[location], save, toast, advance to the next unplaced;
   เอาออกจากผัง clears it
7. DEBUG states and a UI test in InstallTrackingUITests

Do not change:
- the Gantt and S-Curve content
- the iPhone progress
- the daily report / weekly request key plan views
- the PDF
- stored model fields or their Codable
- firestore.rules
No zone rectangles (no field for them). No refactors or renames outside the list.

Start with the code-review-graph tools as CLAUDE.md says. Then read InstallTrackingPage+Progress.swift,
KeyPlanViews.swift (KeyPlanImage, KeyPlanEditor, KeyPlanSheet), RoutineReport.Settings (taskLocations, keyPoints),
RoutineReport+Day / InstallGantt (per-location progress) and MasterSchedule.plannedPoints before writing code.
Reuse them; put any new calculation in TCRoofCore with a test, not in the view.

Rules:
- The board's values are examples (assets/sample-data.json); never hard-code them.
- Colours from Theme, hit areas ≥ 44 pt, TCButtonStyle.
- Split the plan, the list and its row into their own views.

When done:
- run swift test in TCRoofKit
- run the xcodebuild app build with your own -derivedDataPath, in the background
- run InstallTrackingUITests on an iPad simulator
- save simulator screenshots named like states/ to screenshots/
- tick the change list and answer the open questions in your report

Commit and push feat/install-tracking-ipad-keyplan. Do not merge.
```
