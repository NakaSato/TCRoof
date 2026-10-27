# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/weekly-request-pdf && git checkout -b feat/weekly-request-pdf

Follow docs/ui/weekly-request-pdf/CLAUDE_CODE_TASK.md.

Scope: only the weekly request PDF (R1, RoutineReportPages.request). Redraw it in the customer's one-page
WORK REQUEST CIVIL-ELECTRICAL form, as docs/ui/daily-report-pdf did for the daily report, and add the blank form.
Work through change list items 1–6 in order, and nothing else:
1. the form header's two title lines become a parameter (the daily form stays byte-for-byte the same)
2. requestForm: manpower and tools side by side, work plan, risk assessment, two signatures, from WeeklyRequest
3. continuation pages for rows beyond 8 / 8 / 7 / 4, signatures on the last page only
4. requestBlankForm and RoutineReportFiles.requestBlank
5. DEBUG: -screen request -routineDemo pdf|blank writes Documents/request.pdf and request-blank.pdf
6. tests in TCRoofKit

Do not change:
- R2, R3 or R4 output
- RoutineReport.WeeklyRequest or any stored field
- the request screens' UI or RequestPDFSheet's UI
- firestore.rules
No refactors or renames outside the list.

Start with the code-review-graph tools as CLAUDE.md says. Then read RoutineReportPages.swift (R1),
RoutineReportPages+DailyForm.swift (all), RoutineReport+Request.swift and RoutineReportSupport.swift before writing
code. Reuse the daily form's frame, header, table, cell and signature helpers.

Rules:
- The board's values are examples (assets/sample-data.json); never hard-code them.
- Draw in the board's px and scale onto A4 as finishForm does.

When done:
- run swift test in TCRoofKit
- run the xcodebuild app build with your own -derivedDataPath, in the background
- render request.pdf and request-blank.pdf on a simulator, save PNGs named like states/ to screenshots/ and compare
- tick the change list and answer the open questions in your report

Commit and push feat/weekly-request-pdf. Do not merge.
```
