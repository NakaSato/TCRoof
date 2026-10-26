# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/daily-report-ipad-v3 && git checkout -b feat/daily-report-ipad-v3

Follow docs/ui/daily-report-ipad-v3/CLAUDE_CODE_TASK.md.

Scope: only the right column of the iPad one-page daily report (DailyOnePage). Work through change list items 1–4
in order, and nothing else:
1. the date button opens a month calendar with report-status dots
2. a working-time popover with presets and start / end steppers replaces the cycling chip / sheet; weather stays
   reachable from it
3. the sign card shows the reporter (SITE ENGINEER of the contractor) only, with a 180 pt signature box
4. DEBUG states and a UI test

Leave the left card alone. Its v2 redesign is a separate hand-off on design/daily-report-ipad-v2, built in its own
branch. Also no changes to:
- the team card or the bottom bar
- the iPhone
- the PDF
- stored model fields
- firestore.rules
No refactors or renames outside the list.

Start with the code-review-graph tools as CLAUDE.md says. Then read DailyOnePage (daySwitcher, DailyTimeSheet,
signCard), DailyReportScreen (actions, changeDay, requestSign, requestAck) and RoutineReport (reportDay, labour)
before writing code. Reuse the existing day change, sign and clear paths. Inspector acknowledgement stays in the
home feed and the ack sheet.

Rules:
- The board's values are examples (assets/sample-data.json); never hard-code them.
- Colours from Theme, hit areas ≥ 44 pt, TCButtonStyle.
- Split each popover and card into its own view.

When done:
- run swift test in TCRoofKit (with the day-status test)
- run the xcodebuild app build with your own -derivedDataPath, in the background
- run RoleUITests and the new UI test on an iPad simulator
- save simulator screenshots named like states/ to screenshots/
- tick the change list and answer the open questions in your report

Commit and push feat/daily-report-ipad-v3. Do not merge.
```
