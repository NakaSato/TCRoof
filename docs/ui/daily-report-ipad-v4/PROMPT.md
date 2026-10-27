# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/daily-report-ipad-v4 && git checkout -b feat/daily-report-ipad-v4

Follow docs/ui/daily-report-ipad-v4/CLAUDE_CODE_TASK.md.

Scope: only the iPad one-page daily report (DailyOnePage): its header, and a TC team view that acknowledges a sent
report on the page. Work through change list items 1–5 in order, and nothing else:
1. header line 1 "รายงานประจำวันที่ <d MMM yyyy> (วัน<full weekday>)" (a TCRoofCore formatter with a test); the
   board's role switch is not built
2. which view: the TC view for a signed, saved report opened by a non-external viewer who may acknowledge; otherwise
   the contractor view as built. The TC view makes the left card and the team card read-only (one flag)
3. the ลงนามรับทราบ card in place of the sign card: the reporter row, a 170 pt box that opens the existing
   InspectorAckSheet, signed state with clearAck (acknowledgement only), the inspector name field;
   Theme.planInspect for the purple
4. the TC bottom bar: status line, ส่งกลับให้แก้ (asks a reason, clears the signatures), the PDF preview, and
   ยืนยันรับทราบ (enabled once acknowledged)
5. DEBUG -routineDailyState ack|acked, one CLAUDE.md sentence, DailyOnePageUITests extended

Leave alone, with no refactors or renames outside the list:
- the left card (v2) and the calendar / working-time popovers (v3)
- the team card's layout
- the iPhone daily report
- the PDF layout
- stored InstallLog / RoutineReport fields
- firestore.rules
The feed's and the daily list's รับทราบ keep working.

Start with the code-review-graph tools as CLAUDE.md says. Then read DailyOnePage (header, blocker, bottomBar, Actions),
DailyOnePage+Right (signCard), DailyReportScreen (requestSign, requestAck, acknowledge, clearSignature),
Job.recordInspectorAck and Permissions.signsDaily before writing code. Reuse the existing ack sheet and the save path;
don't build a second signature pad.

Rules:
- The board's values are examples (assets/sample-data.json); never hard-code them.
- Colours from Theme, hit areas ≥ 44 pt, TCButtonStyle.
- Split each card and bar into its own view.

When done:
- run swift test in TCRoofKit
- run the xcodebuild app build with your own -derivedDataPath, in the background
- run DailyOnePageUITests, DailyLeftCardUITests and RoleUITests on an iPad simulator
- save screenshots named like states/ to screenshots/
- tick the change list and answer the four open questions in your report

Commit and push feat/daily-report-ipad-v4. Do not merge.
```
