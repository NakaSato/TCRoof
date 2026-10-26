# Prompt for Claude Code

Paste this into Claude Code, opened in the `TCRoof` repo:

```
git fetch origin && git checkout design/install-tracking-ipad-weekly-report && git checkout -b feat/install-tracking-ipad-weekly-report

Follow docs/ui/install-tracking-ipad-weekly-report/CLAUDE_CODE_TASK.md.

Scope: only the iPad install tracking page's Weekly Report tab, moved from the pushed RoutineSummaryScreen into the
page as drawn in iPadInstallWeeklyReport.dc.html (menu "wr"): the week header with the step line and the download
menu, the 8-slide rail, the slide viewer, the readiness checks, the recipients and the send button, and the .pptx
sheet. Work through the change list in §5 in order, and nothing else: no refactors, renames or restyles outside it,
no changes to other tabs, the R3 PDF layout, Firestore rules or CloudSync. The only iPhone change is §5 item 3
(slidesCard reads WeeklySlides.outline). The only stored change is the optional send record of §5 item 2, decoded
with decodeIfPresent defaults.

Start with the code-review-graph tools as CLAUDE.md says, then read InstallTrackingPage (Tab, items, the request tab
as the pattern to follow), InstallTrackingPage+PhoneSummaries (phoneWeeklyTab, slidesCard), RoutineSummaryScreen,
RoutineReportFiles.weekly / weeklySlides and WeeklySlides with its tests before writing code. Reuse the iPhone's
readiness checks without changing their wording or results.

The board's values are examples (assets/sample-data.json); never hard-code them. The template's pictures are in
assets/. App colours from Theme, the slides' template colours as named constants in the slide views, hit areas ≥ 44 pt,
split each card into its own computed property.

When done: swift test in TCRoofKit, the xcodebuild app build with your own -derivedDataPath (in the background),
simulator screenshots named like states/ saved to screenshots/, the change list ticked, and answers to §7's open
questions in your report. Commit on feat/install-tracking-ipad-weekly-report and push it.
```
