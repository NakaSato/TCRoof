# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/install-tracking-ipad-daily && git checkout -b feat/install-tracking-ipad-daily

Follow docs/ui/install-tracking-ipad-daily/CLAUDE_CODE_TASK.md.

Scope: only the iPad install tracking page's รายงานประจำวัน tab (InstallTrackingPage+Daily.swift). The tab is
already built; make it match the board. Work through change list items 1–5 in order, and nothing else:
1. the KPI row becomes a 52 pt strip: label and value on one line, note under them
2. remove the three cards under the table; the reports card runs down to the dock
3. the progress cell: % + a delta chip vs the MP plan (เร็วกว่า / ตามแผน / ช้ากว่า), bar green or orange,
   tick at the plan; "แผน n%" when there is no actual
4. rows 56 pt, the portrait fallback still fits
5. extend InstallTrackingUITests

Do not change:
- InstallDailyData (beyond a small delta helper)
- the other tabs, the header, the tab bar, the dock
- the iPhone daily tab
- DailyOnePage / DailyReportScreen
- the PDF
- stored model fields
- firestore.rules
No photo quota (there is no source for it). No refactors or renames outside the list.

Start with the code-review-graph tools as CLAUDE.md says. Then read InstallTrackingPage+Daily.swift,
InstallDailyData.swift, InstallTrackingPage+Progress.swift (dockClearance) and InstallTrackingUITests before
writing code.

Rules:
- The board's values are examples (assets/sample-data.json); never hard-code them.
- Colours from Theme, hit areas ≥ 44 pt, TCButtonStyle.
- Keep each cell in its own function or view.

When done:
- run the xcodebuild app build with your own -derivedDataPath, in the background
- run InstallTrackingUITests on an iPad simulator
- save simulator screenshots named like states/ to screenshots/
- tick the change list and answer the open questions in your report

Commit and push feat/install-tracking-ipad-daily. Do not merge.
```
