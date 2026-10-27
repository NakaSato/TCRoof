# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/weekly-request-ipad-map-v2 && git checkout -b feat/weekly-request-ipad-map-v2

Follow docs/ui/weekly-request-ipad-map/CLAUDE_CODE_TASK.md.

Scope: only the iPad one-page layout of คำขอรายสัปดาห์ (R1) drawn in iPadWeeklyMap.dc.html: the week's lines as pins
on the station's key plan with + for MP tasks not yet requested, each line's six day chips, the crew and tools
dropdown rows, the 5 × 5 risk sheet per hazard, the engineer's signature in the page and the bottom bar. Work through
the change list in §5 in order, and nothing else: no refactors, renames or restyles outside it, no iPhone changes, no
changes to the daily report (reuse its views; a new parameter must default to today's behaviour), no Firestore rule,
CloudSync or trusting changes, and no R1 PDF changes beyond the working-time value. The only model changes are the
optional fields of §5 items 1 and 2, decoded with decodeIfPresent defaults.

Start with the code-review-graph tools as CLAUDE.md says, then read WeeklyRequestScreen and WeeklyRequestStore,
RoutineReport.WeeklyRequest (Risk, PlanLine, requestDraft), DailyReportScreen and DailyOnePage (+Plan, +Right),
KeyPlanViews and InstallTrackingPage.items before writing code. Reuse the existing send / send back / approve / reopen
paths and isEditable(external:); do not change their behaviour.

The board's values are examples (assets/sample-data.json); never hard-code them. Colours from Theme (line colours and
risk bands as named constants in one place), hit areas ≥ 44 pt, split each card into its own computed property.

When done: swift test in TCRoofKit, the xcodebuild app build with your own -derivedDataPath (in the background),
simulator screenshots named like states/ saved to screenshots/, the change list ticked, and answers to §7's open
questions in your report. Commit on feat/weekly-request-ipad-map-v2 and push it.
```
