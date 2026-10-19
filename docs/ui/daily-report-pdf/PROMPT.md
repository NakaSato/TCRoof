# Prompt for Claude Code

```
git fetch origin && git switch -c feat/daily-report-pdf origin/design/daily-report-pdf
```

```
Follow docs/ui/daily-report-pdf/CLAUDE_CODE_TASK.md.

FIRST check that these exist. If any is missing, STOP and report.
- TCRoofKit/Sources/PDFReport/RoutineReportPages.swift with daily(_:all:keyPlan:)
- TCRoofKit/Sources/TCRoofCore/RoutineReport.swift with Daily (weather, crew, tools, materials, progress, problems)
- RoutineReport.weatherHours == 6...20

Build:
1. The daily report PDF in the customer's DAILY REPORT form:
   - page 1: header, weather 06–20, manpower 17, tools 17, materials 8
   - page 2: key plan, progress 6, problems 5
   - page 3: 4 photos and the signatures
   - pages 4+: 6 photos each
   Every caller of the daily PDF uses it.
2. The blank form (4 pages): RoutineReportPages.dailyBlankForm(), behind `พิมพ์แบบฟอร์มเปล่า` in the daily report list's menu.
3. DEBUG -routineDemo pdf / blank. Update CLAUDE.md.
4. The PDFReport tests in the task.

Rules:
- Vector tables (DrawOp). Logos and photos as images. No screenshots of views.
- Fixed rows. Overflow goes to an extra page with the same header. Never shrink the text.
- Values in the boards are examples. Take data from RoutineReport.Daily / Settings / DailyEntry.
- R1, R3 and R4 are unchanged.

Steps:
1. Read the task, then the 7 boards as text (markup = layout; the live prop = data mapping). Look at states/*.png.
2. Use code-review-graph first (grep if it doesn't connect). Find every caller of daily(...).
3. swift test, then xcodebuild with your own -derivedDataPath.
4. Render Documents/daily.pdf and daily-blank.pdf to PNG and save them in screenshots/ (01–09). Compare them with states/.
5. Commit on feat/daily-report-pdf and push (no merge).
6. Report: the differences, the page size you used, and the open questions.
```
